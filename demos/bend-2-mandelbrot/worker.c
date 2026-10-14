#include <sys/mman.h>
#include <fcntl.h>
static unsigned worker_width,worker_height,worker_root,worker_iterations;
static unsigned worker_origin_x,worker_origin_y,worker_full_width,worker_full_height;
static uint64_t worker_generation;
static uint64_t* worker_mailbox;
static bool worker_cancelled;
static NSData* mp_cached_key;
static bool mp_bend_cached;
static Term mp_bend_reference;
static bool worker_stale(void) {
  return worker_cancelled || (worker_generation && worker_mailbox && __atomic_load_n(worker_mailbox,__ATOMIC_ACQUIRE)!=worker_generation);
}
static void worker_region(unsigned root) {
  worker_full_width=worker_width;worker_full_height=worker_height;
  if(root) {
    if((root!=256&&root!=512)||worker_origin_x>=worker_width||worker_origin_y>=worker_height) err_fail("Invalid render region");
    worker_root=root;worker_width=MIN(root,worker_width-worker_origin_x);worker_height=MIN(root,worker_height-worker_origin_y);
  } else {
    worker_root=256;while(worker_root<worker_width||worker_root<worker_height)worker_root*=2;
  }
}
static u64 worker_start;
static bool worker_deep,worker_direct;
static float worker_mantissa,worker_exponent,worker_offset_x,worker_offset_y;
static double worker_deep_gpu_ms;
static id<MTLComputePipelineState> mp_deep_pipeline;
static id<MTLBuffer> mp_flat_buffer;
static unsigned mp_limbs,mp_rneg,mp_ineg,mp_anchor;
static float worker_phase;
static double mp_reference_ms,mp_reference_wall_ms;
static u64 worker_pixel_start;
static bool mp_reference_hit;
static unsigned mp_reference_lanes;
static id<MTLLibrary> mp_library;
static id<MTLComputePipelineState> mp_reference_pipeline,mp_parallel_pipeline,mp_pack_pipeline,mp_repair_pipeline,mp_candidates_pipeline;
static id<MTLBuffer> mp_center_buffer,mp_scratch_buffer,mp_orbit_buffer,mp_length_buffer,mp_pixel_buffer,mp_repair_buffer,mp_repaired_buffer,mp_candidates_buffer;
static Term worker_float(float value) { u32 bits; memcpy(&bits,&value,4); return bits; }

static void mp_pipelines(void) {
  if(mp_library) return;
  NSError* error=nil;MTLCompileOptions* options=[MTLCompileOptions new];options.mathMode=MTLMathModeSafe;
  mp_library=[gpu_dev newLibraryWithSource:@(PRECISION_SOURCE) options:options error:&error];
  if(!mp_library) err_fail(error.localizedDescription.UTF8String);
  mp_reference_pipeline=[gpu_dev newComputePipelineStateWithFunction:[mp_library newFunctionWithName:@"reference_orbit"] error:&error];
  mp_parallel_pipeline=[gpu_dev newComputePipelineStateWithFunction:[mp_library newFunctionWithName:@"reference_orbit_parallel"] error:&error];
  mp_deep_pipeline=[gpu_dev newComputePipelineStateWithFunction:[mp_library newFunctionWithName:@"deep_pixels"] error:&error];
  mp_pack_pipeline=[gpu_dev newComputePipelineStateWithFunction:[mp_library newFunctionWithName:@"pack_pixels"] error:&error];
  mp_repair_pipeline=[gpu_dev newComputePipelineStateWithFunction:[mp_library newFunctionWithName:@"repair_pixels"] error:&error];
  mp_candidates_pipeline=[gpu_dev newComputePipelineStateWithFunction:[mp_library newFunctionWithName:@"repair_candidates"] error:&error];
  if(!mp_deep_pipeline||!mp_parallel_pipeline||!mp_candidates_pipeline||!mp_reference_pipeline||!mp_pack_pipeline||!mp_repair_pipeline) err_fail(error.localizedDescription.UTF8String);
}
static void mp_complete(id<MTLCommandBuffer> command) {
  [command commit];[command waitUntilCompleted];
  if(command.error) err_fail(command.error.localizedDescription.UTF8String);
}
static Term mp_prepare(Env e) {
  mp_pipelines();
  u64 reference_start=io_tick();
  unsigned capacity=MIN(16384,((worker_iterations+255)/256)*256);
  uint32_t key_header[]={mp_limbs,capacity,mp_rneg,mp_ineg,mp_anchor};
  if(mp_anchor) {key_header[2]=0;key_header[3]=0;}
  NSMutableData* key=[NSMutableData dataWithBytes:key_header length:sizeof key_header];
  if(!mp_anchor) [key appendBytes:mp_center_buffer.contents length:mp_limbs*2*4];
  mp_reference_ms=0;
  mp_reference_hit=[mp_cached_key isEqualToData:key];
  mp_reference_lanes=mp_anchor?1:(mp_limbs<=17?32:128);
  if(!mp_reference_hit) {
  mp_cached_key=nil;
  if(mp_bend_cached){term_sink(e,mp_bend_reference);mp_bend_cached=false;}
  mp_scratch_buffer=[gpu_dev newBufferWithLength:(mp_limbs*8+2)*4 options:MTLResourceStorageModeShared];
  mp_orbit_buffer=[gpu_dev newBufferWithLength:(capacity+1)*8 options:MTLResourceStorageModeShared];
  mp_length_buffer=[gpu_dev newBufferWithLength:4 options:MTLResourceStorageModeShared];
  struct {uint32_t limbs,iterations,rneg,ineg,start,stop;} config={mp_limbs,capacity+1,mp_rneg,mp_ineg,0,0};
  id<MTLBuffer> reference_center=mp_center_buffer;
  if(mp_anchor) { reference_center=[gpu_dev newBufferWithLength:mp_limbs*2*4 options:MTLResourceStorageModeShared];memset(reference_center.contents,0,mp_limbs*2*4);((uint32_t*)reference_center.contents)[mp_limbs*2-1]=1;config.rneg=0;config.ineg=0; }
  unsigned chunk=mp_anchor?config.iterations:MIN(256,MAX(1,16000/(mp_limbs+mp_limbs*mp_limbs/32)));
  mp_reference_ms=0;
  for(unsigned start=0;start<config.iterations;start+=chunk) {
    if(worker_stale()) {worker_cancelled=true;return term_pak(CID_PERTURBATION_REFEND,0);}
    config.start=start;config.stop=MIN(start+chunk,config.iterations);
    id<MTLCommandBuffer> cb=[gpu_que commandBuffer];id<MTLComputeCommandEncoder> enc=[cb computeCommandEncoder];
    [enc setComputePipelineState:mp_anchor?mp_reference_pipeline:mp_parallel_pipeline];[enc setBuffer:reference_center offset:0 atIndex:0];[enc setBuffer:mp_scratch_buffer offset:0 atIndex:1];[enc setBuffer:mp_orbit_buffer offset:0 atIndex:2];[enc setBuffer:mp_length_buffer offset:0 atIndex:3];[enc setBytes:&config length:sizeof config atIndex:4];
    [enc dispatchThreads:MTLSizeMake(mp_reference_lanes,1,1) threadsPerThreadgroup:MTLSizeMake(mp_reference_lanes,1,1)];[enc endEncoding];mp_complete(cb);
    mp_reference_ms+=(cb.GPUEndTime-cb.GPUStartTime)*1000;
    if(*(uint32_t*)mp_length_buffer.contents<=config.stop&&*(uint32_t*)mp_length_buffer.contents<config.iterations) break;
  }
  mp_cached_key=[key copy];
  }
  if(worker_direct){mp_reference_wall_ms=(io_tick()-reference_start)*1e-6;return term_pak(CID_PERTURBATION_REFEND,0);}
  if(mp_bend_cached) {
    mp_reference_wall_ms=(io_tick()-reference_start)*1e-6;
    return term_keep(e,mp_bend_reference);
  }
  uint32_t length=*(uint32_t*)mp_length_buffer.contents;
  float* orbit=mp_orbit_buffer.contents;
  Term list=term_pak(CID_PERTURBATION_REFEND,0);
  for(uint32_t i=length;i>1;) { --i;Loc loc=heap_alloc(e,cls_fit(3));e.mem[loc]=worker_float(orbit[i*2]);e.mem[loc+1]=worker_float(orbit[i*2+1]);e.mem[loc+2]=list;list=term_ctr(CID_PERTURBATION_REFPOINT,loc); }
  mp_reference_wall_ms=(io_tick()-reference_start)*1e-6;
  mp_bend_reference=rfc_seal(e,list);mp_bend_cached=true;
  return term_keep(e,mp_bend_reference);
}
Term worker_read_run(Env e,Term* f,IoWork* w) {
  char line[512];
  if(!fgets(line,sizeof line,stdin)) return term_pak(CID_STOP,0);
  gpu_enc=nil;
  worker_cancelled=false;worker_generation=0;worker_origin_x=worker_origin_y=0;
  unsigned region_root=0;
  if(!strncmp(line,"T ",2)) {
    unsigned long long generation;
    if(sscanf(line,"T %llu %u %u %u",&generation,&worker_origin_x,&worker_origin_y,&region_root)!=4) err_fail("Invalid tile header");
    worker_generation=generation;
    if(!fgets(line,sizeof line,stdin)) err_fail("Missing tile camera");
    if(!worker_mailbox) {
      const char* path=getenv("MANDELBROT_MAILBOX");
      if(path) {int fd=open(path,O_RDONLY);if(fd<0)err_fail("Cannot open render mailbox");void* memory=mmap(NULL,8,PROT_READ,MAP_SHARED,fd,0);close(fd);if(memory==MAP_FAILED)err_fail("Cannot map render mailbox");worker_mailbox=memory;}
    }
  }
  worker_deep=!strncmp(line,"MP ",3);
  if(worker_deep) {
    float mantissa,exponent,offset_x,offset_y;
    if(sscanf(line,"MP %u %u %u %u %f %f %f %u %u %u %f %f",&mp_limbs,&worker_iterations,&worker_width,&worker_height,&worker_phase,&mantissa,&exponent,&mp_rneg,&mp_ineg,&mp_anchor,&offset_x,&offset_y)!=12) err_fail("Invalid deep render header");
    worker_direct=!getenv("MANDELBROT_BEND_DEEP");
    worker_mantissa=mantissa;worker_exponent=exponent;worker_offset_x=offset_x;worker_offset_y=offset_y;
    worker_deep_gpu_ms=0;
    if(!io_gpu) err_fail("Growing-precision rendering requires --gpu on");
    if(mp_limbs<4||mp_limbs>1025||worker_iterations<1||worker_iterations>16384||worker_width<256||worker_width>4096||worker_height<256||worker_height>4096) err_fail("Deep render request exceeds resource budget");
    size_t size=mp_limbs*3*4;
    mp_center_buffer=[gpu_dev newBufferWithLength:size options:MTLResourceStorageModeShared];
    if(fread(mp_center_buffer.contents,1,size,stdin)!=size) err_fail("Truncated coordinate words");
    worker_region(region_root);
    worker_start=io_tick();
    Term reference=mp_prepare(e);
    if(worker_stale()) {worker_cancelled=true;term_sink(e,reference);return term_pak(CID_SKIP,0);}
    worker_pixel_start=io_tick();
    if(worker_direct)return term_pak(CID_DIRECT,0);
    Loc loc=heap_alloc(e,cls_fit(12));Term values[12]={worker_float(mantissa),worker_float(exponent),worker_float(offset_x),worker_float(offset_y),worker_full_width,worker_full_height,worker_root,worker_iterations,worker_float(worker_phase),reference,worker_origin_x,worker_origin_y};
    for(unsigned i=0;i<12;i++)e.mem[loc+i]=values[i];
    return term_ctr(CID_DEEP,loc);
  }
  double cx,cy,span,phase;unsigned width,height,iterations;
  if(sscanf(line,"%lf %lf %lf %u %u %u %lf",&cx,&cy,&span,&width,&height,&iterations,&phase)!=7) err_fail("Invalid render header");
  if(!isfinite(cx)||!isfinite(cy)||!isfinite(span)||!isfinite(phase)||span<=0||width<256||width>4096||height<256||height>4096||iterations<1||iterations>16384) err_fail("Invalid render request");
  worker_width=width;worker_height=height;worker_iterations=iterations;worker_phase=phase;worker_root=256;
  worker_region(region_root);
  worker_start=io_tick();
  if(worker_stale()) {worker_cancelled=true;return term_pak(CID_SKIP,0);}
  float xh=cx,yh=cy;Loc loc=heap_alloc(e,cls_fit(12));
  Term values[12]={worker_float(xh),worker_float(cx-xh),worker_float(yh),worker_float(cy-yh),worker_float(span/width),width,height,worker_root,iterations,worker_float(phase),worker_origin_x,worker_origin_y};
  for(unsigned i=0;i<12;i++)e.mem[loc+i]=values[i];
  worker_start=io_tick();return term_ctr(CID_RENDER,loc);
}
static unsigned worker_pixel(Env e,Term t,unsigned px,unsigned py) {
  unsigned k=0;while((1u<<k)<worker_root)k++;
  while(term_tag(t)==TAG_CTR){unsigned j=0;if(k){k--;j=((py>>k)&1)*2+((px>>k)&1);}t=e.mem[term_peek(e,t)+j];}
  return term_loc(t);
}
static Term worker_cancel(Env e,Term image) {
  struct{uint32_t magic,width,height,bytes;double render_ms;uint32_t gpu,repairs,bits,mode;} header={0x4d424632,worker_width,worker_height,0,(io_tick()-worker_start)*1e-6,0,0,0,2};
  if(fwrite(&header,sizeof header,1,stdout)!=1||fflush(stdout))exit(0);
  term_sink(e,image);return term_pak(CID_UNIT,0);
}
Term worker_write_run(Env e,Term* f,IoWork* w) {
  io_sync();
  if(worker_stale())return worker_cancel(e,f[0]);
  if(io_gpu&&gpu_enc==nil&&!(worker_deep&&worker_direct))err_fail("Bend fractal computation did not dispatch to Metal");
  double render_ms=(io_tick()-worker_start)*1e-6;
  double pixel_ms=worker_deep?(io_tick()-worker_pixel_start)*1e-6:render_ms;
  unsigned repaired=0;
  size_t bytes=(size_t)worker_width*worker_height*4;unsigned char* pixels;
  if(io_gpu) {
    mp_pipelines();
    bool direct=worker_deep&&worker_direct;
    if(direct&&mp_flat_buffer.length<bytes*2)mp_flat_buffer=[gpu_dev newBufferWithLength:bytes*2 options:MTLResourceStorageModeShared];
    id<MTLBuffer> image_buffer=direct?mp_flat_buffer:gpu_buf;
    struct {uint64_t root,rfcbit,locmask;uint32_t width,height,depth,ctr,origin_x,origin_y,full_width,full_height,flat;} args={direct?0:f[0],RFC_BIT,LOC_MASK,worker_width,worker_height,0,TAG_CTR,worker_origin_x,worker_origin_y,worker_full_width,worker_full_height,direct};
    while((1u<<args.depth)<worker_root)args.depth++;
    if(worker_deep&&worker_direct) {
      struct {uint32_t iterations,length;float mantissa,exponent,offset_x,offset_y,phase;} config={worker_iterations,*(uint32_t*)mp_length_buffer.contents,worker_mantissa,worker_exponent,worker_offset_x,worker_offset_y,worker_phase};
      id<MTLCommandBuffer> cb=[gpu_que commandBuffer];id<MTLComputeCommandEncoder> enc=[cb computeCommandEncoder];
      [enc setComputePipelineState:mp_deep_pipeline];[enc setBuffer:image_buffer offset:0 atIndex:0];[enc setBuffer:mp_orbit_buffer offset:0 atIndex:1];[enc setBytes:&args length:sizeof args atIndex:2];[enc setBytes:&config length:sizeof config atIndex:3];
      [enc dispatchThreads:MTLSizeMake(worker_width*worker_height,1,1) threadsPerThreadgroup:MTLSizeMake(256,1,1)];[enc endEncoding];mp_complete(cb);
      worker_deep_gpu_ms=(cb.GPUEndTime-cb.GPUStartTime)*1000;
      pixel_ms=(io_tick()-worker_pixel_start)*1e-6;render_ms=(io_tick()-worker_start)*1e-6;
    }
    if(worker_stale())return worker_cancel(e,f[0]);
    if(worker_deep) {
      const unsigned lanes=256;
      struct{uint32_t limbs,iterations,rneg,ineg;float phase;uint32_t lanes,start,stop;} config={mp_limbs,worker_iterations,mp_rneg,mp_ineg,worker_phase,lanes,0,0};
      mp_repair_buffer=[gpu_dev newBufferWithLength:(size_t)lanes*mp_limbs*12*4 options:MTLResourceStorageModeShared];
      mp_repaired_buffer=[gpu_dev newBufferWithLength:4 options:MTLResourceStorageModeShared];
      *(uint32_t*)mp_repaired_buffer.contents=0;
      mp_candidates_buffer=[gpu_dev newBufferWithLength:worker_width*worker_height*4 options:MTLResourceStorageModeShared];
      id<MTLCommandBuffer> scan=[gpu_que commandBuffer];id<MTLComputeCommandEncoder> scan_enc=[scan computeCommandEncoder];
      [scan_enc setComputePipelineState:mp_candidates_pipeline];[scan_enc setBuffer:image_buffer offset:0 atIndex:0];[scan_enc setBuffer:mp_candidates_buffer offset:0 atIndex:1];[scan_enc setBuffer:mp_repaired_buffer offset:0 atIndex:2];[scan_enc setBytes:&args length:sizeof args atIndex:3];
      [scan_enc dispatchThreads:MTLSizeMake(worker_width*worker_height,1,1) threadsPerThreadgroup:MTLSizeMake(256,1,1)];[scan_enc endEncoding];mp_complete(scan);
      repaired=*(uint32_t*)mp_repaired_buffer.contents;
      double repair_ms=(scan.GPUEndTime-scan.GPUStartTime)*1000;
      // Bound repair submission as well as pixel work. Existing commands finish.
      unsigned chunk=worker_generation?32:MAX(1,repaired);
      for(unsigned start=0;start<repaired;start+=chunk) {
      if(worker_stale())return worker_cancel(e,f[0]);
      config.start=start;config.stop=MIN(start+chunk,repaired);
      id<MTLCommandBuffer> cb=[gpu_que commandBuffer];id<MTLComputeCommandEncoder> enc=[cb computeCommandEncoder];
      [enc setComputePipelineState:mp_repair_pipeline];[enc setBuffer:image_buffer offset:0 atIndex:0];[enc setBuffer:mp_center_buffer offset:0 atIndex:1];[enc setBuffer:mp_repair_buffer offset:0 atIndex:2];[enc setBuffer:mp_repaired_buffer offset:0 atIndex:3];[enc setBytes:&args length:sizeof args atIndex:4];[enc setBytes:&config length:sizeof config atIndex:5];[enc setBuffer:mp_candidates_buffer offset:0 atIndex:6];
      [enc dispatchThreads:MTLSizeMake(lanes,1,1) threadsPerThreadgroup:MTLSizeMake(32,1,1)];[enc endEncoding];mp_complete(cb);
      repair_ms+=(cb.GPUEndTime-cb.GPUStartTime)*1000;
      }
      repaired=*(uint32_t*)mp_repaired_buffer.contents;
      fprintf(stderr,"deep bits=%u reference_cache=%s reference_lanes=%u reference_GPU_ms=%.3f reference_wall_ms=%.3f pixels_wall_ms=%.3f pixels_GPU_ms=%.3f engine=%s repairs=%u repair_GPU_ms=%.3f prepack_wall_ms=%.3f\n",(mp_limbs-1)*16,mp_reference_hit?"hit":"miss",mp_reference_lanes,mp_reference_ms,mp_reference_wall_ms,pixel_ms,worker_deep_gpu_ms,worker_direct?"Metal":"Bend",repaired,repair_ms,(io_tick()-worker_start)*1e-6);
    }
    if(worker_stale())return worker_cancel(e,f[0]);
    mp_pixel_buffer=[gpu_dev newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> cb=[gpu_que commandBuffer];id<MTLComputeCommandEncoder> enc=[cb computeCommandEncoder];
    [enc setComputePipelineState:mp_pack_pipeline];[enc setBuffer:image_buffer offset:0 atIndex:0];[enc setBuffer:mp_pixel_buffer offset:0 atIndex:1];[enc setBytes:&args length:sizeof args atIndex:2];
    [enc dispatchThreads:MTLSizeMake(worker_width,worker_height,1) threadsPerThreadgroup:MTLSizeMake(16,16,1)];[enc endEncoding];mp_complete(cb);pixels=mp_pixel_buffer.contents;
  } else {
    pixels=malloc(bytes);if(!pixels)err_fail("Image allocation failed");
    for(unsigned py=0;py<worker_height;py++)for(unsigned px=0;px<worker_width;px++){unsigned rgb=worker_pixel(e,f[0],px,py);size_t idx=((size_t)py*worker_width+px)*4;pixels[idx]=rgb>>16;pixels[idx+1]=rgb>>8;pixels[idx+2]=rgb;pixels[idx+3]=255;}
  }
  struct{uint32_t magic,width,height,bytes;double render_ms;uint32_t gpu,repairs,bits,mode;}header={0x4d424632,worker_width,worker_height,(uint32_t)bytes,render_ms,(uint32_t)(io_gpu&&(gpu_enc!=nil||(worker_deep&&worker_direct))),repaired,worker_deep?(mp_limbs-1)*16:48,(uint32_t)worker_deep};
  if(fwrite(&header,sizeof header,1,stdout)!=1||fwrite(pixels,bytes,1,stdout)!=1||fflush(stdout))exit(0);
  static bool reported=false;if(!reported){fprintf(stderr,"Mandelbrot completed %ux%u frame: %s; device=%s; %.3f ms\n",worker_width,worker_height,io_gpu?"Metal GPU (fractal dispatch verified)":"Bend CPU",io_gpu?gpu_dev.name.UTF8String:"CPU",render_ms);reported=true;}
  if(!io_gpu)free(pixels);term_sink(e,f[0]);return term_pak(CID_UNIT,0);
}
static void __attribute__((constructor)) worker_use(void){io_eff(CID_WORKER_READ,worker_read_run,0);io_eff(CID_WORKER_WRITE,worker_write_run,0);}
