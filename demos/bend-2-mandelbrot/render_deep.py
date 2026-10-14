#!/usr/bin/env python3
"""Capture a real high-precision GPU frame at a chosen antenna zoom."""
from fractions import Fraction
from pathlib import Path
import argparse,csv,hashlib,json,statistics,struct,subprocess,time
from camera import packet
from render import png,read_exact
ROOT=Path(__file__).resolve().parent
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--depth',type=int,default=100);parser.add_argument('--width',type=int,default=2200);parser.add_argument('--height',type=int,default=1560);parser.add_argument('--iterations',type=int,default=4096);parser.add_argument('--frames',type=int,default=4);parser.add_argument('--output');parser.add_argument('--csv');parser.add_argument('--pan-x',type=int,default=0);parser.add_argument('--pan-y',type=int,default=0);args=parser.parse_args()
    span=Fraction(1,10**args.depth);cx=span*Fraction(args.pan_x,args.width);cy=Fraction(1)+span*Fraction(args.pan_y,args.width)
    command=packet(cx,cy,span,args.width,args.height,args.iterations,.4,True)
    process=subprocess.Popen([str(ROOT/'Mandelbrot.app/Contents/MacOS/worker'),'--gpu','on'],stdin=subprocess.PIPE,stdout=subprocess.PIPE)
    rows=[]
    try:
        for i in range(args.frames):
            start=time.perf_counter();process.stdin.write(command);process.stdin.flush()
            magic,w,h,n,ms,gpu,repairs,bits,mode=struct.unpack('<IIIIdIIII',read_exact(process.stdout,40));assert magic==0x4d424632 and gpu==1 and mode==1
            rgba=read_exact(process.stdout,n)
            rows.append(dict(depth=args.depth,width=w,height=h,iterations=args.iterations,frame=i,bits=bits,gpu=True,repairs=repairs,render_ms=ms,total_ms=(time.perf_counter()-start)*1000,sha256=hashlib.sha256(rgba).hexdigest()))
        if args.output:png(args.output,w,h,rgba)
    finally:
        process.stdin.close();process.wait(timeout=10)
    if args.csv:
        with open(args.csv,'w',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=rows[0]);writer.writeheader();writer.writerows(rows)
    warm=rows[1:] or rows
    print(json.dumps(dict(depth=args.depth,bits=bits,resolution=f'{w}x{h}',iterations=args.iterations,frames=args.frames,cold_ms=rows[0]['render_ms'],warm_render_median_ms=statistics.median(r['render_ms'] for r in warm),warm_total_median_ms=statistics.median(r['total_ms'] for r in warm),identical_frames=len({r['sha256'] for r in rows})==1,sha256=rows[-1]['sha256']),indent=2))
if __name__=='__main__':main()
