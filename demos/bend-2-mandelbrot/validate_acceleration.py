#!/usr/bin/env python3
"""Compare optimized GPU pixels to the saved scalar path and Decimal samples."""
from fractions import Fraction
from pathlib import Path
import argparse,hashlib,json,struct,subprocess,time
from camera import packet
from render import read_exact
from validate import reference_rgb
ROOT=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('baseline',type=Path,help='Preserved worker executable, with its adjacent .gpu file')
options=parser.parse_args()
logs=[open(ROOT/f'evidence/acceleration/validation-{i}.log','w') for i in range(2)]
workers=[subprocess.Popen([str(path),'--gpu','on'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=logs[i]) for i,path in enumerate((options.baseline.resolve(),ROOT/'Mandelbrot.app/Contents/MacOS/worker'))]
rows=[];w,h=512,384;it=16384
try:
    for depth in (20,50,68,100,300,1000):
        span=Fraction(1,10**depth);cx=Fraction(0);cy=Fraction(1);images=[];times=[]
        for p in workers:
            for repeat in range(2):
                start=time.perf_counter();p.stdin.write(packet(cx,cy,span,w,h,it,.4,True));p.stdin.flush()
                header=struct.unpack('<IIIIdIIII',read_exact(p.stdout,40));data=read_exact(p.stdout,header[3]);assert header[5]==1
            images.append(data);times.append((time.perf_counter()-start)*1000)
        changed=[i//4 for i in range(0,len(data),4) if images[0][i:i+4]!=images[1][i:i+4]]
        max_diff=max(abs(a-b) for a,b in zip(*images));base_error=error=0
        samples={(27,37),(79,203),(151,91),(233,177),(317,61),(371,299),(449,147),(483,351)}
        samples.update((i%w,i//w) for i in changed[:16])
        regressions=[]
        for px,py in samples:
            expected=reference_rgb(cx,cy,span,w,h,px,py,it,.4,depth+80);offset=(py*w+px)*4
            old=max(abs(a-b) for a,b in zip(expected,images[0][offset:offset+3]));new=max(abs(a-b) for a,b in zip(expected,images[1][offset:offset+3]));base_error=max(base_error,old);error=max(error,new)
            if new>max(3,old):regressions.append((px,py,old,new))
        row=dict(depth=depth,bits=header[7],different_pixels=len(changed),max_channel_difference=max_diff,decimal_samples=len(samples),baseline_decimal_error=base_error,accelerated_decimal_error=error,regressions=regressions,baseline_ms=times[0],accelerated_ms=times[1],sha256=hashlib.sha256(images[1]).hexdigest());rows.append(row);print(json.dumps(row),flush=True)

finally:
    for p in workers:p.stdin.close()
    for p in workers:p.wait(timeout=30)
    for log in logs:log.close()
(ROOT/'evidence/acceleration/validation.json').write_text(json.dumps(rows,indent=2)+'\n')
assert not any(row['different_pixels'] for row in rows), 'Pixels changed against the preserved renderer'
assert not any(row['regressions'] for row in rows), 'Numerical regression against Decimal'
