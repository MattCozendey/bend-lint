#!/usr/bin/env python3
"""Compare deep frame completion against a preserved worker executable."""
from fractions import Fraction
from pathlib import Path
import argparse,hashlib,json,statistics,struct,subprocess,time
from camera import packet
from render import read_exact
ROOT=Path(__file__).resolve().parent
args=argparse.ArgumentParser();args.add_argument('baseline');args.add_argument('--output',default='evidence/acceleration/native-paired.json');options=args.parse_args()
w,h=2200,1560
cases=[('deep320',Fraction(0),Fraction(1),Fraction('1e-68'),16384),('generic',Fraction('-.743643887037151'),Fraction('.131825904205330'),Fraction('1e-7'),2785),('deep300',Fraction(0),Fraction(1),Fraction('1e-300'),16384)]
paths=[Path(options.baseline),ROOT/'Mandelbrot.app/Contents/MacOS/worker'];rows=[]
logs=[open(ROOT/f'evidence/acceleration/worker-{i}.log','w') for i in range(2)]
workers=[subprocess.Popen([str(p),'--gpu','on'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=logs[i]) for i,p in enumerate(paths)]
def tile(p,command,x,y):
    start=time.perf_counter();p.stdin.write(f'T 1 {x} {y} 256\n'.encode()+command);p.stdin.flush()
    header=struct.unpack('<IIIIdIIII',read_exact(p.stdout,40));data=read_exact(p.stdout,header[3]);assert header[5]==1
    return header,data,(time.perf_counter()-start)*1000
try:
    for name,cx,cy,span,it in cases:
        command=packet(cx,cy,span,w,h,it,.4);hashes=set()
        for p in workers:tile(p,command,0,0)
        for index in (0,1,1,0,0,1):
            pixels=bytearray(w*h*4);times=[];start=time.perf_counter()
            for y in range(0,h,256):
                for x in range(0,w,256):
                    header,data,ms=tile(workers[index],command,x,y);tw,th=header[1:3];times.append(ms)
                    for yy in range(th):pixels[((y+yy)*w+x)*4:((y+yy)*w+x+tw)*4]=data[yy*tw*4:(yy+1)*tw*4]
            elapsed=(time.perf_counter()-start)*1000;digest=hashlib.sha256(pixels).hexdigest();hashes.add(digest)
            row=dict(name=name,implementation=('baseline','candidate')[index],total_ms=elapsed,batch_p50_ms=statistics.median(times),batch_p95_ms=sorted(times)[int(len(times)*.95)],sha256=digest)
            rows.append(row);print(json.dumps(row),flush=True)
        assert len(hashes)==1,(name,hashes)
finally:
    for p in workers:p.stdin.close()
    for p in workers:p.wait(timeout=30)
    for log in logs:log.close()
(ROOT/options.output).write_text(json.dumps(rows,indent=2)+'\n')
