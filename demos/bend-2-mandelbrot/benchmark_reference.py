#!/usr/bin/env python3
from pathlib import Path
from fractions import Fraction
import json,struct,subprocess,re
ROOT=Path(__file__).resolve().parent
build=ROOT/'.build';build.mkdir(exist_ok=True)
subprocess.run(['clang','-O2','-fobjc-arc',str(ROOT/'precision-test.m'),'-framework','Foundation','-framework','Metal','-o',str(build/'precision-test')],check=True)
(ROOT/'evidence/deep-performance').mkdir(parents=True,exist_ok=True)
rows=[]
for bits in (144,512,1088,3424,8192,16384):
    n=bits//16+1;iterations=128 if bits>=8192 else 512
    data=struct.pack('<6I',n,iterations,1,0,0,iterations)
    for c in ('-.743643887037151','.131825904205330'):
        fixed=int(abs(Fraction(c))*(1<<bits));data+=b''.join(struct.pack('<I',(fixed>>(16*i))&65535) for i in range(n))
    path=ROOT/'evidence/deep-performance/reference-input.bin';path.write_bytes(data)
    baseline=None
    for lanes in (1,32,64,128):
        run=subprocess.run([str(build/'precision-test'),str(path),str(ROOT/'precision.metal'),str(lanes)],capture_output=True,check=True)
        if baseline is None:baseline=run.stdout
        assert run.stdout==baseline,(bits,lanes)
        ms=float(re.search(r'GPU_ms=([0-9.]+)',run.stderr.decode())[1])
        row=dict(bits=bits,iterations=iterations,lanes=lanes,gpu_ms=ms,identical=True);rows.append(row);print(json.dumps(row),flush=True)
(ROOT/'evidence/deep-performance/reference-parallel.json').write_text(json.dumps(rows,indent=2)+'\n')
