#include <metal_stdlib>
using namespace metal;
#pragma clang fp contract(off)

// Unsigned radix-2^16 fixed point. The final limb holds the integer part;
// all preceding limbs are fractional. Precision is supplied at dispatch.
void mp_zero(device uint* a, uint n) { for(uint i=0;i<n;i++) a[i]=0; }
void mp_copy(device const uint* a, device uint* b, uint n) { for(uint i=0;i<n;i++) b[i]=a[i]; }
int mp_cmp(device const uint* a, device const uint* b, uint n) {
  for(uint i=n;i>0;i--) { if(a[i-1]>b[i-1]) return 1; if(a[i-1]<b[i-1]) return -1; }
  return 0;
}
void mp_add(device const uint* a, device const uint* b, device uint* out, uint n) {
  uint carry=0;
  for(uint i=0;i<n;i++) { uint sum=a[i]+b[i]+carry; out[i]=sum&65535; carry=sum>>16; }
}
void mp_sub(device const uint* a, device const uint* b, device uint* out, uint n) {
  uint borrow=0;
  for(uint i=0;i<n;i++) { int difference=int(a[i])-int(b[i])-int(borrow); out[i]=uint(difference)&65535; borrow=difference<0; }
}
bool mp_signed_add(device const uint* a, bool sa, device const uint* b, bool sb, device uint* out, uint n) {
  if(sa==sb) { mp_add(a,b,out,n); return sa; }
  if(mp_cmp(a,b,n)>=0) { mp_sub(a,b,out,n); return sa; }
  mp_sub(b,a,out,n); return sb;
}
void mp_mul(device const uint* a, device const uint* b, device uint* out, device uint* scratch, uint n) {
  mp_zero(scratch,n*2);
  for(uint i=0;i<n;i++) {
    ulong carry=0;
    for(uint j=0;j<n;j++) {
      ulong value=ulong(a[i])*ulong(b[j])+scratch[i+j]+carry;
      scratch[i+j]=uint(value)&65535; carry=value>>16;
    }
    scratch[i+n]=uint(carry);
  }
  uint carry=scratch[n-2]>=32768;
  for(uint i=0;i<n;i++) { uint value=scratch[i+n-1]+carry; out[i]=value&65535; carry=value>>16; }
}
void mp_twice(device uint* a, uint n) {
  uint carry=0;
  for(uint i=0;i<n;i++) { uint value=a[i]*2+carry; a[i]=value&65535; carry=value>>16; }
}
float mp_float(device const uint* a, bool negative, uint n) {
  float value=float(a[n-1]);
  float scale=1.0/65536.0;
  for(uint i=n-1;i>0 && scale>1e-37;i--) { value+=float(a[i-1])*scale; scale*=1.0/65536.0; }
  return negative?-value:value;
}
struct PrecisionConfig { uint limbs, iterations, real_negative, imag_negative, start, stop; };
kernel void reference_orbit(device const uint* center [[buffer(0)]],
                            device uint* scratch [[buffer(1)]],
                            device float2* orbit [[buffer(2)]],
                            device uint* length [[buffer(3)]],
                            constant PrecisionConfig& config [[buffer(4)]],
                            uint tid [[thread_position_in_grid]]) {
  if(tid!=0) return;
  uint n=config.limbs;
  bool imaginary_unit=!config.real_negative&&!config.imag_negative&&center[2*n-1]==1;
  for(uint i=0;i<2*n-1;i++) imaginary_unit=imaginary_unit&&center[i]==0;
  if(imaginary_unit) {
    if(config.start==0) *length=config.iterations;
    for(uint k=config.start;k<min(config.stop,config.iterations);k++) orbit[k]=k==0?float2(0):k==1?float2(0,1):(k&1)?float2(0,-1):float2(-1,1);
    return;
  }
  device uint* zr=scratch;
  device uint* zi=scratch+n;
  device uint* rr=scratch+2*n;
  device uint* ii=scratch+3*n;
  device uint* cross=scratch+4*n;
  device uint* nr=scratch+5*n;
  device uint* work=scratch+6*n;
  if(config.start==0) { mp_zero(scratch,8*n+2); *length=config.iterations; }
  if(*length<=config.start) return;
  bool sr=scratch[8*n],si=scratch[8*n+1];
  for(uint k=config.start;k<min(config.stop,config.iterations);k++) {
    float2 value=float2(mp_float(zr,sr,n),mp_float(zi,si,n));
    orbit[k]=value;
    if(dot(value,value)>256.0) { *length=k+1; return; }
    mp_mul(zr,zr,rr,work,n);
    mp_mul(zi,zi,ii,work,n);
    mp_mul(zr,zi,cross,work,n); mp_twice(cross,n);
    bool ns=mp_signed_add(rr,false,ii,true,nr,n);
    ns=mp_signed_add(nr,ns,center,config.real_negative,zr,n);
    si=mp_signed_add(cross,sr!=si,center+n,config.imag_negative,zi,n);
    sr=ns;
  }
  scratch[8*n]=sr; scratch[8*n+1]=si;
}

// Each lane evaluates independent convolution columns. Carry propagation and
// rounding use the same radix and rounding rule as the serial multiplier.
void mp_round_columns(threadgroup const ulong* columns,device uint* out,device uint* work,uint n) {
  ulong carry=0;
  for(uint k=0;k<2*n;k++){ulong value=columns[k]+carry;work[k]=uint(value)&65535;carry=value>>16;}
  uint rounded=work[n-2]>=32768;
  for(uint i=0;i<n;i++){uint value=work[i+n-1]+rounded;out[i]=value&65535;rounded=value>>16;}
}
void mp_mul_parallel(device const uint* a,device const uint* b,device uint* out,
                     device uint* work,uint n,threadgroup ulong* columns,uint tid,uint lanes) {
  for(uint k=tid;k<2*n;k+=lanes) {
    ulong sum=0;
    uint begin=k>=n?k-n+1:0,end=min(k+1,n);
    for(uint i=begin;i<end;i++)sum+=ulong(a[i])*ulong(b[k-i]);
    columns[k]=sum;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  if(tid==0)mp_round_columns(columns,out,work,n);
  threadgroup_barrier(mem_flags::mem_device|mem_flags::mem_threadgroup);
}
void mp_products_parallel(device const uint* zr,device const uint* zi,device uint* rr,
                          device uint* ii,device uint* cross,uint n,
                          threadgroup ulong* columns,uint tid,uint lanes) {
  for(uint k=tid;k<2*n;k+=lanes) {
    ulong real=0,imaginary=0,mixed=0;
    uint begin=k>=n?k-n+1:0,end=min(k+1,n);
    for(uint i=begin;i<min(end,(k+1)/2);i++) {
      ulong ar=zr[i],ai=zi[i],br=zr[k-i],bi=zi[k-i];
      real+=2*ar*br;imaginary+=2*ai*bi;mixed+=ar*bi+ai*br;
    }
    if(!(k&1)&&k/2<n){ulong ar=zr[k/2],ai=zi[k/2];real+=ar*ar;imaginary+=ai*ai;mixed+=ar*ai;}
    columns[k]=real;columns[2*n+k]=imaginary;columns[4*n+k]=mixed;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  if(tid<3) {
    threadgroup const ulong* product=columns+2*n*tid;
    device uint* out=tid==0?rr:tid==1?ii:cross;
    ulong carry=0;
    for(uint k=0;k<n-2;k++)carry=(product[k]+carry)>>16;
    ulong guard=product[n-2]+carry;
    uint rounded=(uint(guard)&65535)>=32768;carry=guard>>16;
    for(uint i=0;i<n;i++) {
      ulong value=product[i+n-1]+carry;carry=value>>16;
      uint limb=(uint(value)&65535)+rounded;out[i]=limb&65535;rounded=limb>>16;
    }
  }
  threadgroup_barrier(mem_flags::mem_device|mem_flags::mem_threadgroup);
}
kernel void reference_orbit_parallel(device const uint* center [[buffer(0)]],
                                     device uint* scratch [[buffer(1)]],
                                     device float2* orbit [[buffer(2)]],
                                     device uint* length [[buffer(3)]],
                                     constant PrecisionConfig& config [[buffer(4)]],
                                     uint tid [[thread_index_in_threadgroup]],
                                     uint lanes [[threads_per_threadgroup]]) {
  threadgroup ulong columns[2050];
  uint n=config.limbs;
  device uint* zr=scratch;device uint* zi=scratch+n;
  device uint* rr=scratch+2*n;device uint* ii=scratch+3*n;
  device uint* cross=scratch+4*n;device uint* nr=scratch+5*n;
  device uint* work=scratch+6*n;
  if(tid==0&&config.start==0){mp_zero(scratch,8*n+2);*length=config.iterations;}
  threadgroup_barrier(mem_flags::mem_device);
  if(*length<=config.start)return;
  for(uint k=config.start;k<min(config.stop,config.iterations);k++) {
    if(tid==0){float2 value=float2(mp_float(zr,scratch[8*n],n),mp_float(zi,scratch[8*n+1],n));orbit[k]=value;if(dot(value,value)>256)*length=k+1;}
    threadgroup_barrier(mem_flags::mem_device);
    if(*length==k+1)return;
    // Three products fit in the existing scratch through 5,440 fractional bits.
    if(n<=341)mp_products_parallel(zr,zi,rr,ii,cross,n,columns,tid,lanes);
    else {
      mp_mul_parallel(zr,zr,rr,work,n,columns,tid,lanes);
      mp_mul_parallel(zi,zi,ii,work,n,columns,tid,lanes);
      mp_mul_parallel(zr,zi,cross,work,n,columns,tid,lanes);
    }
    if(tid==0) {
      mp_twice(cross,n);
      bool ns=mp_signed_add(rr,false,ii,true,nr,n);
      ns=mp_signed_add(nr,ns,center,config.real_negative,zr,n);
      bool si=mp_signed_add(cross,scratch[8*n]!=scratch[8*n+1],center+n,config.imag_negative,zi,n);
      scratch[8*n]=ns;scratch[8*n+1]=si;
    }
    threadgroup_barrier(mem_flags::mem_device);
  }
}

struct PresentationArgs { ulong root, rfcbit, locmask; uint width,height,depth,ctr,origin_x,origin_y,full_width,full_height,flat; };
ulong image_node(device const ulong* memory, ulong term, constant PresentationArgs& args) {
  return term&args.rfcbit ? memory[term&args.locmask]>>24 : term&args.locmask;
}
kernel void pack_pixels(device const ulong* memory [[buffer(0)]],
                        device uint* pixels [[buffer(1)]],
                        constant PresentationArgs& args [[buffer(2)]],
                        uint2 point [[thread_position_in_grid]]) {
  if(point.x>=args.width||point.y>=args.height) return;
  ulong term=args.root; uint depth=args.depth;
  while(((term>>56)&127)==args.ctr) {
    uint child=0;
    if(depth) { depth--; child=((point.y>>depth)&1)*2+((point.x>>depth)&1); }
    term=memory[image_node(memory,term,args)+child];
  }
  if(args.flat)term=memory[point.y*args.width+point.x];
  uint rgb=uint(term&args.locmask);
  pixels[point.y*args.width+point.x]=0xff000000|((rgb&255)<<16)|(rgb&65280)|(rgb>>16);
}
float3 atlas_palette(float t) {
  float3 stops[7]={float3(5,12,27),float3(13,57,77),float3(46,141,151),float3(225,237,211),float3(206,130,59),float3(77,33,41),float3(5,12,27)};
  uint segment=min(5u,uint(t)); float u=t-floor(t);u=u*u*(3-2*u);
  return stops[segment]+(stops[segment+1]-stops[segment])*u;
}
uint atlas_color(uint count,float radius,float phase) {
  float mu=max(0.0,float(count)+1-log2(log2(radius)*.5));
  float t=fmod(mu*.018+phase,1.0)*6;
  uint3 rgb=uint3(clamp(atlas_palette(t),0.0,255.0));
  return (rgb.r<<16)|(rgb.g<<8)|rgb.b;
}
struct Delta {float r,i,e;};
float delta_scale(float e){return e< -100?0:as_type<float>(uint(127+e)<<23);}
Delta delta_normalize(float r,float i,float e) {
  float m=max(abs(r),abs(i));if(m<1e-35f)return {0,0,0};
  uint encoded=(as_type<uint>(m)>>23)&255;
  float factor=as_type<float>((254-encoded)<<23);
  return {r*factor,i*factor,e+float(encoded)-127};
}
Delta delta_add(Delta a,Delta b) {
  if(max(abs(a.r),abs(a.i))<1e-35f)return b;
  if(max(abs(b.r),abs(b.i))<1e-35f)return a;
  float e=max(a.e,b.e),af=delta_scale(a.e-e),bf=delta_scale(b.e-e);
  return delta_normalize(a.r*af+b.r*bf,a.i*af+b.i*bf,e);
}
float delta_magnitude(Delta a){return (a.r*a.r+a.i*a.i)*delta_scale(min(100.f,2*a.e));}
Delta delta_advance(float zr,float zi,Delta dc,Delta d) {
  float lr=2*zr*d.r-2*zi*d.i,li=2*zr*d.i+2*zi*d.r;
  float qr=d.r*d.r-d.i*d.i,qi=d.r*d.i+d.i*d.r;
  if(max(abs(lr),abs(li))<1e-35f)return delta_add(delta_normalize(qr,qi,2*d.e),dc);
  float e=max(d.e,2*d.e),linear=delta_scale(d.e-e),quadratic=delta_scale(2*d.e-e);
  return delta_add(delta_normalize(lr*linear+qr*quadratic,li*linear+qi*quadratic,e),dc);
}
struct DeepConfig {uint iterations,length;float mantissa,exponent,offset_x,offset_y,phase;};
uint deep_float_color(Delta dc,device const float2* orbit,constant DeepConfig& config) {
  float factor=delta_scale(dc.e),cr=dc.r*factor,ci=dc.i*factor;
  float dr=0,di=0,zr=0,zi=0;uint ref=0;
  for(uint n=0;n<config.iterations;n++) {
    if(ref+1>=config.length)return 16777214;
    float rr=(2*zr*dr-2*zi*di)+(dr*dr-di*di)+cr;
    float ri=(2*zr*di+2*zi*dr)+(dr*di+di*dr)+ci;
    float2 z=orbit[++ref];float tr=z.x+rr,ti=z.y+ri,mag=tr*tr+ti*ti;
    if(mag>256)return atlas_color(n+1,mag,config.phase);
    if(mag<1e-8f*(z.x*z.x+z.y*z.y))return 16777214;
    if(mag<rr*rr+ri*ri){dr=tr;di=ti;zr=zi=0;ref=0;}
    else{dr=rr;di=ri;zr=z.x;zi=z.y;}
  }
  return 330001;
}
kernel void deep_pixels(device ulong* memory [[buffer(0)]],device const float2* orbit [[buffer(1)]],
                        constant PresentationArgs& args [[buffer(2)]],constant DeepConfig& config [[buffer(3)]],
                        uint index [[thread_position_in_grid]]) {
  if(index>=args.width*args.height)return;
  uint2 point=uint2(index%args.width,index/args.width);
  Delta dc=delta_normalize((float(point.x+args.origin_x)+.5f-float(args.full_width)*.5f+config.offset_x)*config.mantissa,
                           (float(point.y+args.origin_y)+.5f-float(args.full_height)*.5f+config.offset_y)*config.mantissa,config.exponent);
  Delta delta={0,0,0};float zr=0,zi=0;uint ref=0,color=330001;
  if(config.exponent>= -60)color=deep_float_color(dc,orbit,config);
  else for(uint n=0;n<config.iterations;n++) {
    if(ref+1>=config.length){color=16777214;break;}
    Delta next=delta_advance(zr,zi,dc,delta);float2 z=orbit[++ref];
    Delta total=delta_add({z.x,z.y,0},next);float mag=delta_magnitude(total);
    if(mag>256){color=atlas_color(n+1,mag,config.phase);break;}
    if(mag<1e-8f*(z.x*z.x+z.y*z.y)){color=16777214;break;}
    if(mag<delta_magnitude(next)){delta=total;zr=zi=0;ref=0;}
    else {delta=next;zr=z.x;zi=z.y;}
  }
  ulong term=args.root;uint depth=args.depth;device ulong* slot=nullptr;
  while(((term>>56)&127)==args.ctr){uint child=0;if(depth){depth--;child=((point.y>>depth)&1)*2+((point.x>>depth)&1);}slot=memory+image_node(memory,term,args)+child;term=*slot;}
  if(args.flat){slot=memory+index;term=0;}
  if(slot)*slot=(term&~args.locmask)|color;
}

void mp_small(device const uint* a,uint multiplier,device uint* out,uint n) {
  uint carry=0;
  for(uint i=0;i<n;i++) { uint sum=a[i]*multiplier+carry;out[i]=sum&65535;carry=sum>>16; }
}
kernel void repair_candidates(device const ulong* memory [[buffer(0)]],
                              device uint* candidates [[buffer(1)]],
                              device atomic_uint* count [[buffer(2)]],
                              constant PresentationArgs& args [[buffer(3)]],
                              uint index [[thread_position_in_grid]]) {
  if(index>=args.width*args.height) return;
  uint2 point=uint2(index%args.width,index/args.width);
  ulong term=args.root;uint depth=args.depth;
  while(((term>>56)&127)==args.ctr) {uint child=0;if(depth){depth--;child=((point.y>>depth)&1)*2+((point.x>>depth)&1);}term=memory[image_node(memory,term,args)+child];}
  if(args.flat)term=memory[index];
  if((term&args.locmask)==16777214) candidates[atomic_fetch_add_explicit(count,1u,memory_order_relaxed)]=index;
}
struct RepairConfig { uint limbs,iterations,real_negative,imag_negative; float phase; uint lanes,start,stop; };
kernel void repair_pixels(device ulong* memory [[buffer(0)]],
                          device const uint* center [[buffer(1)]],
                          device uint* workspace [[buffer(2)]],
                          device atomic_uint* repaired [[buffer(3)]],
                          constant PresentationArgs& args [[buffer(4)]],
                          constant RepairConfig& config [[buffer(5)]],
                          device const uint* candidates [[buffer(6)]],
                          uint tid [[thread_position_in_grid]]) {
  uint n=config.limbs;
  device uint* scratch=workspace+tid*n*12;
  device uint* cr=scratch;device uint* ci=scratch+n;
  device uint* zr=scratch+2*n;device uint* zi=scratch+3*n;
  device uint* rr=scratch+4*n;device uint* ii=scratch+5*n;
  device uint* cross=scratch+6*n;device uint* nr=scratch+7*n;
  device uint* work=scratch+8*n;
  for(uint candidate=config.start+tid;candidate<config.stop;candidate+=config.lanes) {
    uint index=candidates[candidate];
    uint2 point=uint2(index%args.width,index/args.width);
    ulong term=args.root;uint depth=args.depth;device ulong* slot=nullptr;
    while(((term>>56)&127)==args.ctr) { uint child=0;if(depth){depth--;child=((point.y>>depth)&1)*2+((point.x>>depth)&1);}slot=memory+image_node(memory,term,args)+child;term=*slot; }
    if(args.flat){slot=memory+index;term=*slot;}
    if((term&args.locmask)!=16777214||slot==nullptr) continue;
    int dx=int((point.x+args.origin_x)*2+1)-int(args.full_width),dy=int((point.y+args.origin_y)*2+1)-int(args.full_height);
    mp_small(center+2*n,uint(abs(dx)),work,n);
    bool scr=mp_signed_add(center,config.real_negative,work,dx<0,cr,n);
    mp_small(center+2*n,uint(abs(dy)),work,n);
    bool sci=mp_signed_add(center+n,config.imag_negative,work,dy<0,ci,n);
    mp_zero(zr,2*n);bool sr=false,si=false;uint color=330001;
    for(uint k=0;k<config.iterations;k++) {
      mp_mul(zr,zr,rr,work,n);mp_mul(zi,zi,ii,work,n);mp_mul(zr,zi,cross,work,n);mp_twice(cross,n);
      bool ns=mp_signed_add(rr,false,ii,true,nr,n);
      ns=mp_signed_add(nr,ns,cr,scr,zr,n);
      si=mp_signed_add(cross,sr!=si,ci,sci,zi,n);sr=ns;
      float2 z=float2(mp_float(zr,sr,n),mp_float(zi,si,n));float mag=dot(z,z);
      if(mag>256){color=atlas_color(k+1,mag,config.phase);break;}
    }
    *slot=(term&~args.locmask)|color;
  }
}
