#!/usr/bin/env python3
"""Render/benchmark the same native Bend worker used by the desktop app."""
import argparse, csv, hashlib, json, math, os, statistics, struct, subprocess, time, zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parent
SCENES={"overview":(-.62,0.,3.4),"seahorse":(-.743643887037151,.131825904205330,.008),"deep":(-.743643887037151,.131825904205330,1e-7)}
def png(path,w,h,rgba):
    def chunk(tag,data):
        return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
    scan=b''.join(b'\0'+rgba[y*w*4:(y+1)*w*4] for y in range(h))
    Path(path).write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(scan,6))+chunk(b'IEND',b''))
def read_exact(stream,n):
    data=bytearray()
    while len(data)<n:
        block=stream.read(n-len(data))
        if not block: raise RuntimeError('Worker exited before completing a frame')
        data.extend(block)
    return bytes(data)
def main():
    a=argparse.ArgumentParser();a.add_argument('--scene',choices=SCENES,default='seahorse');a.add_argument('--width',type=int,default=2200);a.add_argument('--height',type=int,default=1560);a.add_argument('--iterations',type=int,default=1024);a.add_argument('--frames',type=int,default=8);a.add_argument('--backend',choices=['gpu','cpu'],default='gpu');a.add_argument('--output');a.add_argument('--phase',type=float,default=.4);a.add_argument('--csv');args=a.parse_args()
    worker=ROOT/'Mandelbrot.app/Contents/MacOS/worker'
    proc=subprocess.Popen([str(worker),'--gpu','on' if args.backend=='gpu' else 'off'],stdin=subprocess.PIPE,stdout=subprocess.PIPE)
    cx,cy,span=SCENES[args.scene];line=f'{cx:.17g} {cy:.17g} {span:.17g} {args.width} {args.height} {args.iterations} {args.phase}\n'.encode()
    rows=[]
    try:
        for i in range(args.frames):
            start=time.perf_counter();proc.stdin.write(line);proc.stdin.flush()
            magic,w,h,n,ms,gpu,repairs,bits,mode=struct.unpack('<IIIIdIIII',read_exact(proc.stdout,40))
            assert magic==0x4d424632 and (w,h)==(args.width,args.height) and n==w*h*4
            assert bool(gpu)==(args.backend=='gpu'), 'Unexpected renderer backend'
            data=read_exact(proc.stdout,n);elapsed=(time.perf_counter()-start)*1000
            rows.append(dict(scene=args.scene,width=w,height=h,iterations=args.iterations,backend=args.backend,frame=i,render_ms=ms,total_ms=elapsed,sha256=hashlib.sha256(data).hexdigest()))
        if args.output: png(args.output,w,h,data)
    finally:
        proc.stdin.close();proc.wait(timeout=10)
    if args.csv:
        with open(args.csv,'w',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=rows[0]);writer.writeheader();writer.writerows(rows)
    warm=rows[min(2,len(rows)-1):]
    print(json.dumps(dict(scene=args.scene,resolution=f'{w}x{h}',iterations=args.iterations,backend=args.backend,frames=len(rows),cold_ms=rows[0]['render_ms'],warm_render_median_ms=statistics.median(r['render_ms'] for r in warm),warm_total_median_ms=statistics.median(r['total_ms'] for r in warm),identical_frames=len({r['sha256'] for r in rows})==1,sha256=rows[-1]['sha256']),indent=2))
if __name__=='__main__':main()
