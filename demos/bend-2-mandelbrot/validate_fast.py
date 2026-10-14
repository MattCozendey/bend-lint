#!/usr/bin/env python3
"""Check the float perturbation range against preserved scaled pixels and Decimal."""
from fractions import Fraction
from pathlib import Path
import argparse,hashlib,json,struct,subprocess
from camera import packet,power2
from render import read_exact
from validate import reference_rgb
ROOT=Path(__file__).resolve().parent
args=argparse.ArgumentParser();args.add_argument('baseline');options=args.parse_args()
workers=[subprocess.Popen([str(p),'--gpu','on'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL) for p in (Path(options.baseline),ROOT/'Mandelbrot.app/Contents/MacOS/worker')]
rows=[];w,h=512,384;it=4096
cases=[]
for exp in (-35,-44,-50,-59,-60,-61):
    span=power2(exp)*w
    cases.append((f'generic_{exp}',Fraction('-.743643887037151'),Fraction('.131825904205330'),span))
    cases.append((f'antenna_{exp}',span*Fraction(13,w),Fraction(1)-span*Fraction(9,w),span))
try:
    for name,cx,cy,span in cases:
        images=[]
        for p in workers:
            p.stdin.write(packet(cx,cy,span,w,h,it,.4,True));p.stdin.flush()
            header=struct.unpack('<IIIIdIIII',read_exact(p.stdout,40));assert header[5]==1
            images.append(read_exact(p.stdout,header[3]))
        different=sum(images[0][i:i+4]!=images[1][i:i+4] for i in range(0,len(images[0]),4))
        max_error=0;baseline_error=0
        for px,py in ((27,37),(79,203),(151,91),(233,177),(317,61),(371,299),(449,147),(483,351)):
            expected=reference_rgb(cx,cy,span,w,h,px,py,it,.4,100);offset=(py*w+px)*4
            max_error=max(max_error,max(abs(a-b) for a,b in zip(expected,images[1][offset:offset+3])))
            baseline_error=max(baseline_error,max(abs(a-b) for a,b in zip(expected,images[0][offset:offset+3])))
        row=dict(name=name,different_pixels=different,baseline_max_channel_error_vs_decimal=baseline_error,max_channel_error_vs_decimal=max_error,sha256=hashlib.sha256(images[1]).hexdigest());rows.append(row);print(json.dumps(row),flush=True)
        assert different==0,row
        assert max_error<=max(3,baseline_error),row
finally:
    for p in workers:p.stdin.close()
    for p in workers:p.wait(timeout=30)
(ROOT/'evidence/deep-performance/fast-validation.json').write_text(json.dumps(rows,indent=2)+'\n')
