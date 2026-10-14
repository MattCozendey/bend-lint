#!/usr/bin/env python3
"""Independent numerical and exact camera checks against the actual GPU worker."""
from decimal import Decimal,localcontext
from fractions import Fraction
from pathlib import Path
import hashlib,json,math,struct,subprocess,time
from camera import Camera,packet,power2
from render import read_exact,png
ROOT=Path(__file__).resolve().parent
STOPS=[(5,12,27),(13,57,77),(46,141,151),(225,237,211),(206,130,59),(77,33,41),(5,12,27)]
def reference_rgb(cx,cy,span,w,h,px,py,iterations,phase,digits):
    with localcontext() as ctx:
        ctx.prec=digits
        dec=lambda q: Decimal(q.numerator)/Decimal(q.denominator)
        cr=dec(cx+span*Fraction(2*px+1-w,2*w));ci=dec(cy+span*Fraction(2*py+1-h,2*w))
        zr=zi=Decimal(0)
        for n in range(1,iterations+1):
            zr,zi=zr*zr-zi*zi+cr,2*zr*zi+ci
            radius=zr*zr+zi*zi
            if radius>256:
                mu=max(0,n+1-math.log2(math.log2(float(radius))*.5))
                t=((mu*.018+phase)%1)*6;j=min(5,int(t));u=t-math.floor(t);u=u*u*(3-2*u)
                return tuple(int(STOPS[j][k]+(STOPS[j+1][k]-STOPS[j][k])*u) for k in range(3))
        return (5,9,17)
def main():
    evidence=ROOT/'evidence';evidence.mkdir(exist_ok=True)
    camera=Camera();before=camera.cx+camera.span*Fraction.from_float(.3125)
    camera.zoom(-.713,.3125,-.21875)
    assert before==camera.cx+camera.span*Fraction.from_float(.3125)
    old=(camera.cx,camera.cy);camera.pan(.125,-.0625);camera.pan(-.125,.0625);assert old==(camera.cx,camera.cy)
    worker=ROOT/'Mandelbrot.app/Contents/MacOS/worker'
    process=subprocess.Popen([str(worker),'--gpu','on'],stdin=subprocess.PIPE,stdout=subprocess.PIPE)
    rows=[];images={};width=512;height=384;iterations=4096;phase=.4
    def render(cx,cy,span,name):
        request=packet(cx,cy,span,width,height,iterations,phase,True)
        header=request.split(b'\n')[0].decode();bits=(int(header.split()[1])-1)*16
        start=time.perf_counter();process.stdin.write(request);process.stdin.flush()
        magic,w,h,size,ms,gpu,repairs,actual_bits,mode=struct.unpack('<IIIIdIIII',read_exact(process.stdout,40));assert magic==0x4d424632 and gpu==1
        rgba=read_exact(process.stdout,size)
        row=dict(name=name,bits=bits,width=w,height=h,iterations=iterations,gpu=True,repairs=repairs,render_ms=ms,total_ms=(time.perf_counter()-start)*1000,sha256=hashlib.sha256(rgba).hexdigest())
        rows.append(row);png(evidence/(name+'.png'),w,h,rgba);return rgba,row
    try:
        for depth in (20,50,100,300,1000):
            span=Fraction(1,10**depth);cx=Fraction(0);cy=Fraction(1)
            rgba,row=render(cx,cy,span,f'antenna-1e{depth}')
            error=0
            for px,py in [(27,37),(79,203),(151,91),(233,177),(317,61),(371,299),(449,147),(483,351)]:
                expected=reference_rgb(cx,cy,span,width,height,px,py,iterations,phase,depth+80)
                offset=(py*width+px)*4;actual=rgba[offset:offset+3]
                error=max(error,max(abs(a-b) for a,b in zip(actual,expected)))
            row['max_channel_error_vs_decimal']=error
            assert error<=3,(depth,error)
            encoded=packet(cx,cy,span,width,height,iterations,phase,True)
            text,words=encoded.split(b'\n',1);limbs=int(text.split()[1])
            step_words=struct.unpack('<'+str(limbs)+'I',words[2*limbs*4:])
            assert any(step_words), 'Adjacent arbitrary-precision pixels collapsed'
            images[depth]=rgba
            print(json.dumps(row),flush=True)
        span=Fraction(1,10**300);dx=13;dy=-9
        shifted,row=render(span*Fraction(dx,width),Fraction(1)+span*Fraction(dy,width),span,'antenna-1e300-pan')
        original=images[300];checked=0
        for py in range(max(0,-dy),min(height,height-dy)):
            for px in range(max(0,-dx),min(width,width-dx)):
                a=(py*width+px)*4;b=((py+dy)*width+px+dx)*4
                assert shifted[a:a+4]==original[b:b+4],('pan mismatch',px,py)
                checked+=1
        row['identical_overlap_pixels']=checked
        print(json.dumps(row),flush=True)
    finally:
        process.stdin.close();process.wait(timeout=10)
    assert len({row['sha256'] for row in rows[:5]})==5
    result={'camera_pointer_anchor_exact':True,'camera_pan_inverse_exact':True,'depth_frames':rows,'decimal_samples_per_depth':8,'note':'Decimal is an independent offline validator only; the app uses GPU reference, perturbation, and repair.'}
    (evidence/'validation.json').write_text(json.dumps(result,indent=2)+'\n')
    print('All numerical and camera checks passed.')
if __name__=='__main__':main()
