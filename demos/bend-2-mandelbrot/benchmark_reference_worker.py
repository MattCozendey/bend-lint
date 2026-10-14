#!/usr/bin/env python3
"""Cold/warm production reference requests against a preserved worker."""
from fractions import Fraction
from pathlib import Path
import argparse,hashlib,json,struct,subprocess,time
from camera import packet
from render import read_exact
ROOT=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('baseline');options=parser.parse_args()
logs=[open(ROOT/f'evidence/deep-performance/reference-worker-{i}.log','w') for i in range(2)]
workers=[subprocess.Popen([str(path),'--gpu','on'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=logs[i]) for i,path in enumerate((Path(options.baseline),ROOT/'Mandelbrot.app/Contents/MacOS/worker'))]
rows=[]
def render(p,request):
    started=time.perf_counter();p.stdin.write(b'T 1 0 0 256\n'+request);p.stdin.flush()
    header=struct.unpack('<IIIIdIIII',read_exact(p.stdout,40));data=read_exact(p.stdout,header[3]);assert header[5]==1
    return header,data,(time.perf_counter()-started)*1000
try:
    for p in workers:render(p,b'-.62 0 3.4 512 384 128 .4\n')
    for span,it in (('1e-14',1025),('1e-14',1030),('1e-14',1030),('1e-300',512),('1e-1000',512)):
        request=packet(Fraction('-.743643887037151'),Fraction('.131825904205330'),Fraction(span),512,384,it,.4,True)
        hashes=[]
        for i,p in enumerate(workers):
            header,data,elapsed=render(p,request);digest=hashlib.sha256(data).hexdigest();hashes.append(digest)
            row=dict(span=span,iterations=it,bits=header[7],implementation=('baseline','candidate')[i],total_ms=elapsed,repairs=header[6],sha256=digest);rows.append(row);print(json.dumps(row),flush=True)
        assert hashes[0]==hashes[1],(span,it,hashes)
finally:
    for p in workers:p.stdin.close()
    for p in workers:p.wait(timeout=30)
    for log in logs:log.close()
(ROOT/'evidence/deep-performance/reference-worker.json').write_text(json.dumps(rows,indent=2)+'\n')
