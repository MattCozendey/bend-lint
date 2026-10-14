#!/usr/bin/env python3
"""Exact rational camera bookkeeping only; all fractal orbits run on Metal."""
from fractions import Fraction
import math, struct, sys
PLACES=[('-0.62','0','3.4'),('-.743643887037151','.131825904205330','.008'),('-.74543','.11301','.015'),('-.743643887037151','.131825904205330','1e-7'),('0','1','1e-12'),('0','1','1e-100'),('0','1','1e-300')]
def power2(n):
    return Fraction(1<<n,1) if n>=0 else Fraction(1,1<<-n)
def exponent(value):
    exp=value.numerator.bit_length()-value.denominator.bit_length()
    return exp-1 if value<power2(exp) else exp
def packet(cx,cy,span,width,height,iterations,phase,force=False):
    step=span/width
    exp=exponent(step)
    if not force and exp>-35:
        return f'{float(cx):.17g} {float(cy):.17g} {float(span):.17g} {width} {height} {iterations} {phase:.17g}\n'.encode()
    bits=((max(48,-exp)+80+15)//16)*16
    if bits>16384: raise ValueError('Requested precision exceeds the current16384-bit GPU memory/work budget')
    n=bits//16+1
    mantissa=float(step/power2(exp))
    ox=cx/step;oy=(cy-1)/step
    anchor=abs(ox)<65536 and abs(oy)<65536
    out=f'MP {n} {iterations} {width} {height} {phase:.17g} {mantissa:.17g} {exp} {int(cx<0)} {int(cy<0)} {int(anchor)} {float(ox) if anchor else 0:.17g} {float(oy) if anchor else 0:.17g}\n'.encode()
    for value in (abs(cx),abs(cy),step/2):
        fixed=(value.numerator<<bits)//value.denominator
        out+=b''.join(struct.pack('<I',(fixed>>(16*i))&65535) for i in range(n))
    return out
class Camera:
    def __init__(self): self.preset(1)
    def preset(self,i): self.cx,self.cy,self.span=map(Fraction,PLACES[i])
    def zoom(self,delta,ax,ay):
        new=self.span*Fraction.from_float(math.exp(delta));diff=self.span-new
        self.cx+=diff*Fraction.from_float(ax);self.cy+=diff*Fraction.from_float(ay);self.span=new
    def transform(self,scale,dx,dy):
        self.cx+=self.span*Fraction.from_float(dx)
        self.cy+=self.span*Fraction.from_float(dy)
        self.span*=Fraction.from_float(scale)
    def compact(self,width):
        # Keep camera rounding far below the GPU coordinate guard precision.
        bits=max(192,-exponent(self.span/width)+128)
        unit=power2(-bits)
        self.cx=round(self.cx/unit)*unit
        self.cy=round(self.cy/unit)*unit
        self.span=round(self.span/unit)*unit
    def pan(self,dx,dy):
        self.cx-=self.span*Fraction.from_float(dx);self.cy-=self.span*Fraction.from_float(dy)
def main():
    camera=Camera()
    for line in sys.stdin:
        args=line.split()
        if not args: continue
        if args[0]=='zoom':camera.zoom(*map(float,args[1:]))
        elif args[0]=='transform':camera.transform(*map(float,args[1:]))
        elif args[0]=='pan':camera.pan(*map(float,args[1:]))
        elif args[0]=='preset':camera.preset(int(args[1]))
        elif args[0]=='snapshot':
            camera.compact(int(args[1]))
            try: payload=packet(camera.cx,camera.cy,camera.span,*map(int,args[1:4]),float(args[4]))
            except ValueError as error: print(str(error),file=sys.stderr);payload=b''
            sys.stdout.buffer.write(struct.pack('<I',len(payload))+payload);sys.stdout.buffer.flush()
if __name__=='__main__':main()
