#!/usr/bin/env python3
"""Full Retina-resolution deep pan and small pointer-anchored zoom regression."""
from fractions import Fraction
from pathlib import Path
import hashlib,json,struct,subprocess,time
from camera import Camera,packet
from render import read_exact,png
from validate import reference_rgb
ROOT=Path(__file__).resolve().parent
w,h,iterations=2200,1560,16384
camera=Camera();camera.preset(6)
process=subprocess.Popen([str(ROOT/'Mandelbrot.app/Contents/MacOS/worker'),'--gpu','on'],stdin=subprocess.PIPE,stdout=subprocess.PIPE)
rows=[]
def frame(name):
    request=packet(camera.cx,camera.cy,camera.span,w,h,iterations,.4,True)
    start=time.perf_counter();process.stdin.write(request);process.stdin.flush()
    magic,width,height,size,ms,gpu,repairs,bits,mode=struct.unpack('<IIIIdIIII',read_exact(process.stdout,40))
    assert magic==0x4d424632 and (width,height)==(w,h) and gpu==1
    image=read_exact(process.stdout,size)
    row=dict(name=name,resolution=[w,h],iterations=iterations,bits=bits,gpu=True,repairs=repairs,render_ms=ms,total_ms=(time.perf_counter()-start)*1000,sha256=hashlib.sha256(image).hexdigest())
    rows.append(row);print(json.dumps(row),flush=True);return image,row
try:
    original,row=frame('native-300')
    png(ROOT/'evidence/native-300.png',w,h,original)
    camera.cx+=camera.span*Fraction(13,w);camera.cy+=camera.span*Fraction(-9,w)
    shifted,row=frame('native-300-pan')
    count=0
    for y in range(9,h):
        a=(y*w)*4;b=((y-9)*w+13)*4;length=(w-13)*4
        assert shifted[a:a+length]==original[b:b+length],y
        count+=w-13
    row['identical_overlap_pixels']=count
    anchor=camera.cx+camera.span*Fraction.from_float(.3125)
    camera.zoom(-.003,.3125,-.21875)
    assert anchor==camera.cx+camera.span*Fraction.from_float(.3125)
    zoomed,row=frame('native-300-small-zoom')
    error=0
    for px,py in ((271,377),(791,1203),(1511,911),(2033,1177)):
        expected=reference_rgb(camera.cx,camera.cy,camera.span,w,h,px,py,iterations,.4,380)
        actual=zoomed[(py*w+px)*4:(py*w+px)*4+3]
        error=max(error,max(abs(a-b) for a,b in zip(actual,expected)))
    assert error<=3,error
    row['max_channel_error_vs_decimal']=error
    assert len({row['sha256'] for row in rows})==3
finally:
    process.stdin.close();process.wait(timeout=10)
(ROOT/'evidence/native-navigation.json').write_text(json.dumps(rows,indent=2)+'\n')
print('Native-resolution GPU navigation checks passed.')
