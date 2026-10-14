#!/usr/bin/env python3
"""Exercise the real GPU region protocol, precision, cancellation and bounded camera state."""
from fractions import Fraction
from pathlib import Path
import json, math, mmap, os, struct, subprocess, tempfile, threading, time
from camera import Camera, packet, exponent
from render import read_exact
ROOT=Path(__file__).resolve().parent

def camera_checks():
    exact=Camera();coalesced=Camera();scale=1.;dx=dy=0.
    for i in range(300):
        delta=math.sin(i)*.001;ax=.31;ay=-.17;k=math.exp(delta)
        exact.zoom(delta,ax,ay)
        dx+=scale*(1-k)*ax;dy+=scale*(1-k)*ay;scale*=k
        px=math.cos(i)*.0001;py=math.sin(i)*.0001
        exact.pan(px,py);dx-=scale*px;dy-=scale*py
    coalesced.transform(scale,dx,dy)
    errors=[float(abs(a-b)/exact.span*4096) for a,b in zip((exact.cx,exact.cy,exact.span),(coalesced.cx,coalesced.cy,coalesced.span))]
    assert max(errors)<1e-8,errors
    coalesced.preset(6)
    for i in range(10000):
        coalesced.transform(math.exp(-.0001),.00002,-.00001)
        before=(coalesced.cx,coalesced.cy,coalesced.span);unit=coalesced.span/4096
        coalesced.compact(4096)
        assert max(abs(a-b)/unit for a,b in zip(before,(coalesced.cx,coalesced.cy,coalesced.span)))<Fraction(1,2**127)
    bits=-exponent(coalesced.span/4096)+128
    assert max(x.denominator.bit_length() for x in (coalesced.cx,coalesced.cy,coalesced.span))<=bits+1
    return dict(coalesced_max_pixel_error=max(errors),compactions=10000,max_denominator_bits=bits+1)

def main():
    result={'camera':camera_checks(),'regions':[]}
    with tempfile.NamedTemporaryFile() as mailbox:
        mailbox.write(struct.pack('<Q',1));mailbox.flush()
        shared=mmap.mmap(mailbox.fileno(),8)
        def generation(n):struct.pack_into('<Q',shared,0,n)
        env={**os.environ,'MANDELBROT_MAILBOX':mailbox.name}
        log=open(ROOT/'evidence/scheduler/worker.log','w')
        p=subprocess.Popen([str(ROOT/'Mandelbrot.app/Contents/MacOS/worker'),'--gpu','on'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log,env=env)
        def render(command,region=None,gen=1):
            prefix=f'T {gen} {region[0]} {region[1]} {region[2]}\n'.encode() if region else b''
            started=time.perf_counter();p.stdin.write(prefix+command);p.stdin.flush()
            h=struct.unpack('<IIIIdIIII',read_exact(p.stdout,40));rgba=read_exact(p.stdout,h[3]);assert h[0]==0x4d424632
            return h,rgba,(time.perf_counter()-started)*1000
        try:
            cases=[('ordinary',Fraction('-.743643887037151'),Fraction('.131825904205330'),Fraction('.008'),1024,False),
                   ('generic_mp',Fraction('-.743643887037151'),Fraction('.131825904205330'),Fraction('1e-7'),1024,True),
                   ('repair_50',Fraction(0),Fraction(1),Fraction('1e-50'),4096,True),
                   ('deep_300',Fraction(0),Fraction(1),Fraction('1e-300'),4096,True)]
            for name,cx,cy,span,iterations,force in cases:
                w,h=(512,384) if name=='repair_50' else (537,389);command=packet(cx,cy,span,w,h,iterations,.4,force)
                header,full,total=render(command);assert header[5]==1
                for root in (256,512):
                    stitched=bytearray(w*h*4);times=[];repairs=0
                    for y in range(0,h,root):
                        for x in range(0,w,root):
                            th,pixels,ms=render(command,(x,y,root));assert th[5]==1 and th[8]!=(2)
                            tw,hh=th[1:3];assert (tw,hh)==(min(root,w-x),min(root,h-y))
                            for row in range(hh):stitched[((y+row)*w+x)*4:((y+row)*w+x+tw)*4]=pixels[row*tw*4:(row+1)*tw*4]
                            times.append(ms);repairs+=th[6]
                    assert stitched==full,(name,root,sum(a!=b for a,b in zip(stitched,full)))
                    assert repairs==header[6]
                    if name=='repair_50':assert repairs>0
                    row=dict(name=name,root=root,pixels=w*h,identical=True,repairs=repairs,batch_ms=times,full_ms=total)
                    result['regions'].append(row);print(json.dumps(row),flush=True)
            generation(2)
            header,rgba,ms=render(command,(0,0,256),gen=1)
            assert header[8]==2 and not rgba and header[5]==0
            result['already_stale_cancel_ms']=ms
            generation(3)
            heavy=packet(Fraction('-.743643887037151'),Fraction('.131825904205330'),Fraction('1e-300'),512,384,16384,.4,True)
            timer=threading.Timer(.05,lambda:generation(4));timer.start()
            header,rgba,ms=render(heavy,(0,0,256),gen=3);timer.join()
            assert header[8]==2 and not rgba
            result['reference_invalidation_ms']=ms
            # The cancelled packet is fully consumed and the next latest request renders.
            easy=packet(Fraction('-.62'),Fraction(0),Fraction('3.4'),512,384,128,.4)
            header,rgba,ms=render(easy,(0,0,256),gen=4);assert header[5]==1 and len(rgba)==256*256*4
            result['latest_after_cancel_ms']=ms
        finally:
            p.stdin.close();p.wait(timeout=20);shared.close();log.close()
    (ROOT/'evidence/scheduler/validation.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result['camera']));print('GPU region, camera, cancellation, and recovery checks passed.')
if __name__=='__main__':main()
