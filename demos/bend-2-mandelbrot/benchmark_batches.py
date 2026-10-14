#!/usr/bin/env python3
"""Measure complete native-resolution tiled renders and compare the retained deep golden image."""
from fractions import Fraction
from pathlib import Path
import hashlib,json,statistics,struct,subprocess,time
from camera import packet
from render import read_exact
ROOT=Path(__file__).resolve().parent
p=subprocess.Popen([str(ROOT/'Mandelbrot.app/Contents/MacOS/worker'),'--gpu','on'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
rows=[]
try:
    for name,cx,cy,span,iterations in [('native_seahorse',Fraction('-.743643887037151'),Fraction('.131825904205330'),Fraction('.008'),1222),('native_300',Fraction(0),Fraction(1),Fraction('1e-300'),16384)]:
        w,h,root=2200,1560,256;command=packet(cx,cy,span,w,h,iterations,.4)
        pixels=bytearray(w*h*4);times=[];started=time.perf_counter()
        for y in range(0,h,root):
            for x in range(0,w,root):
                t=time.perf_counter();p.stdin.write(f'T 1 {x} {y} {root}\n'.encode()+command);p.stdin.flush()
                header=struct.unpack('<IIIIdIIII',read_exact(p.stdout,40));image=read_exact(p.stdout,header[3]);assert header[5]==1
                tw,th=header[1:3]
                for yy in range(th):pixels[((y+yy)*w+x)*4:((y+yy)*w+x+tw)*4]=image[yy*tw*4:(yy+1)*tw*4]
                times.append((time.perf_counter()-t)*1000)
        row=dict(name=name,width=w,height=h,root=root,iterations=iterations,total_ms=(time.perf_counter()-started)*1000,batch_median_ms=statistics.median(times),batch_max_ms=max(times),batch_p95_ms=sorted(times)[int(len(times)*.95)],batch_ms=times,sha256=hashlib.sha256(pixels).hexdigest())
        if name=='native_300':
            golden=json.loads((ROOT/'evidence/native-navigation.json').read_text())[0]['sha256'];assert row['sha256']==golden
            row['matches_previous_full_frame']=True
        rows.append(row);print(json.dumps({k:v for k,v in row.items() if k!='batch_ms'}),flush=True)
finally:p.stdin.close();p.wait(timeout=20)
(ROOT/'evidence/scheduler/native-batches.json').write_text(json.dumps(rows,indent=2)+'\n')
