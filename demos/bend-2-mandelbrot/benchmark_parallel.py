#!/usr/bin/env python3
"""Compare a bounded number of persistent GPU workers on identical native pixels."""
from concurrent.futures import ThreadPoolExecutor
from fractions import Fraction
from pathlib import Path
import hashlib,json,statistics,struct,subprocess,time
from camera import packet
from render import read_exact
ROOT=Path(__file__).resolve().parent
w,h,root=2200,1560,256
cases=[('seahorse',Fraction('-.743643887037151'),Fraction('.131825904205330'),Fraction('.008'),1222),('generic_deep',Fraction('-.743643887037151'),Fraction('.131825904205330'),Fraction('1e-7'),2785),('deep300',Fraction(0),Fraction(1),Fraction('1e-300'),16384)]
workers=[subprocess.Popen([str(ROOT/'Mandelbrot.app/Contents/MacOS/worker'),'--gpu','on'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL) for _ in range(3)]
def tile(p,command,x,y):
    start=time.perf_counter();p.stdin.write(f'T 1 {x} {y} {root}\n'.encode()+command);p.stdin.flush()
    header=struct.unpack('<IIIIdIIII',read_exact(p.stdout,40));data=read_exact(p.stdout,header[3]);assert header[5]==1
    return x,y,header[1],header[2],data,(time.perf_counter()-start)*1000
rows=[]
try:
    with ThreadPoolExecutor(max_workers=3) as pool:
        for name,cx,cy,span,it in cases:
            command=packet(cx,cy,span,w,h,it,.4)
            list(pool.map(lambda p:tile(p,command,0,0),workers))
            hashes=set()
            for count in (1,2,3,3,2,1,1,2,3):
                pixels=bytearray(w*h*4);times=[]
                regions=[(x,y) for y in range(0,h,root) for x in range(0,w,root)]
                def lane(index):
                    return [tile(workers[index],command,x,y) for x,y in regions[index::count]]
                start=time.perf_counter()
                for results in pool.map(lane,range(count)):
                    for x,y,tw,th,data,ms in results:
                        for yy in range(th):pixels[((y+yy)*w+x)*4:((y+yy)*w+x+tw)*4]=data[yy*tw*4:(yy+1)*tw*4]
                        times.append(ms)
                ms=(time.perf_counter()-start)*1000;digest=hashlib.sha256(pixels).hexdigest();hashes.add(digest)
                row=dict(name=name,workers=count,total_ms=ms,batch_p50_ms=statistics.median(times),batch_p95_ms=sorted(times)[int(len(times)*.95)],sha256=digest)
                rows.append(row);print(json.dumps(row),flush=True)
            assert len(hashes)==1
finally:
    for p in workers:p.stdin.close()
    for p in workers:p.wait(timeout=20)
(ROOT/'evidence/scheduler/parallel.json').write_text(json.dumps(rows,indent=2)+'\n')
