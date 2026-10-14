#!/usr/bin/env python3
"""Independent Decimal oracle for the actual Metal multiprecision reference kernel."""
from decimal import Decimal, localcontext
from fractions import Fraction
from pathlib import Path
import json, struct, subprocess
ROOT=Path(__file__).resolve().parent
build=ROOT/'.build';build.mkdir(exist_ok=True)
subprocess.run(['clang','-O2','-fobjc-arc',str(ROOT/'precision-test.m'),'-framework','Foundation','-framework','Metal','-o',str(build/'precision-test')],check=True)
rows=[]
for bits in (128,256,512):
    limbs=bits//16+1;iterations=2048
    data=struct.pack('<6I',limbs,iterations,1,0,0,iterations)
    for coordinate in ('-.743643887037151','.131825904205330'):
        value=abs(Fraction(coordinate));fixed=(value.numerator<<bits)//value.denominator
        data+=b''.join(struct.pack('<I',(fixed>>(16*i))&65535) for i in range(limbs))
    source=build/'reference-input.bin';source.write_bytes(data)
    run=subprocess.run([str(build/'precision-test'),str(source),str(ROOT/'precision.metal')],check=True,capture_output=True)
    for lanes,chunk in ((32,iterations),(128,iterations),(128,37)):
        parallel=subprocess.run([str(build/'precision-test'),str(source),str(ROOT/'precision.metal'),str(lanes),str(chunk)],check=True,capture_output=True)
        assert parallel.stdout==run.stdout,(bits,lanes,chunk)
    count=struct.unpack('<I',run.stdout[:4])[0];points=list(struct.iter_unpack('<ff',run.stdout[4:]));assert count==iterations
    with localcontext() as context:
        context.prec=bits+80
        cr=Decimal('-.743643887037151');ci=Decimal('.131825904205330');zr=zi=Decimal(0);error=0
        for real,imaginary in points:
            error=max(error,abs(float(zr)-real),abs(float(zi)-imaginary))
            zr,zi=zr*zr-zi*zi+cr,2*zr*zi+ci
    assert error<1e-6,(bits,error)
    rows.append(dict(bits=bits,points=count,max_float_conversion_error=error,parallel_and_chunked_identical=True,metal=run.stderr.decode().strip()))
for bits,cr,ci in ((144,'0','0'),(144,'0','1'),(144,'0','-1'),(144,'-2','0'),(144,'2','.5'),(512,'-.12','-.65'),(3424,'-.743643887037151','.131825904205330')):
    limbs=bits//16+1;iterations=129
    data=struct.pack('<6I',limbs,iterations,int(Fraction(cr)<0),int(Fraction(ci)<0),0,iterations)
    for coordinate in (cr,ci):
        fixed=int(abs(Fraction(coordinate))*(1<<bits))
        data+=b''.join(struct.pack('<I',(fixed>>(16*i))&65535) for i in range(limbs))
    source=build/'reference-input.bin';source.write_bytes(data)
    expected=subprocess.run([str(build/'precision-test'),str(source),str(ROOT/'precision.metal')],check=True,capture_output=True).stdout
    for lanes,chunk in ((32,37),(128,1),(128,129)):
        actual=subprocess.run([str(build/'precision-test'),str(source),str(ROOT/'precision.metal'),str(lanes),str(chunk)],check=True,capture_output=True).stdout
        assert actual==expected,(bits,cr,ci,lanes,chunk)
    rows.append(dict(bits=bits,center=[cr,ci],parallel_and_chunked_identical=True))
print(json.dumps(rows,indent=2))
(ROOT/'evidence/reference-validation.json').write_text(json.dumps(rows,indent=2)+'\n')
