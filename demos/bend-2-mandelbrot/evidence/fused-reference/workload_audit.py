#!/usr/bin/env python3
"""Independent CPU-only escape-count audit for performance test selection."""
from decimal import Decimal, localcontext
from fractions import Fraction
from pathlib import Path
import json
import statistics
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from camera import packet

WIDTH, HEIGHT, LIMIT = 2200, 1560, 16384
CASES = [
    ('generic_seahorse_12', '-.743643887037151', '.131825904205330', '1e-12'),
    ('generic_seahorse_15', '-.743643887037151', '.131825904205330', '1e-15'),
    ('generic_seahorse_68', '-.743643887037151', '.131825904205330', '1e-68'),
    ('parabolic_68', '-.75', '0', '1e-68'),
    ('period3_interior_68', '-.122561166876', '.744861766619', '1e-68'),
]

def sample(cx, cy, span, digits):
    with localcontext() as context:
        context.prec = digits
        cx, cy, span = map(Decimal, (cx, cy, span))
        rows = []
        points = [(None, None)] + [(gx*WIDTH//4+WIDTH//8, gy*HEIGHT//4+HEIGHT//8)
                                 for gy in range(4) for gx in range(4)]
        for x, y in points:
            cr, ci = cx, cy
            if x is not None:
                cr += (Decimal(x)+Decimal('.5')-Decimal(WIDTH)/2)*span/WIDTH
                ci += (Decimal(y)+Decimal('.5')-Decimal(HEIGHT)/2)*span/WIDTH
            zr = zi = Decimal(0)
            escaped = None
            for iteration in range(1, LIMIT+1):
                zr, zi = zr*zr-zi*zi+cr, 2*zr*zi+ci
                if zr*zr+zi*zi > 256:
                    escaped = iteration
                    break
            rows.append({'x': x, 'y': y, 'escape_iteration': escaped})
        return rows

results = []
for name, cx, cy, span in CASES:
    start = time.perf_counter()
    first = sample(cx, cy, span, 150)
    second = sample(cx, cy, span, 200)
    assert first == second, (name, 'oracle precision disagreement')
    escaped = [r['escape_iteration'] for r in first[1:] if r['escape_iteration'] is not None]
    header = packet(*map(Fraction, (cx, cy, span)), WIDTH, HEIGHT, LIMIT, .4, True).split(b'\n')[0]
    row = dict(name=name, center=[cx, cy], span=span, width=WIDTH, height=HEIGHT,
               reference_fractional_bits=(int(header.split()[1])-1)*16,
               iteration_budget=LIMIT, escape_radius_squared=256,
               oracle_decimal_digits=[150, 200], oracle_precision_agreed=True,
               center_escape_iteration=first[0]['escape_iteration'],
               sampled_pixels=len(first)-1, escaped=len(escaped), bounded_at_budget=len(first)-1-len(escaped),
               escape_min=min(escaped) if escaped else None,
               escape_median=statistics.median(escaped) if escaped else None,
               escape_max=max(escaped) if escaped else None,
               samples=first[1:], cpu_audit_seconds=time.perf_counter()-start)
    results.append(row)
    print(json.dumps({k: v for k, v in row.items() if k != 'samples'}), flush=True)

output = Path(__file__).with_name('workload-audit.json')
output.write_text(json.dumps({'method': 'Exact Decimal recurrence from zero; center plus 4x4 stratified native-resolution pixel sample, repeated at two precisions.',
                            'scope': 'Workload selection only, not a GPU benchmark. Bounded at budget is not proof of set membership. Very deep finite-decimal centers may produce a uniform image.',
                            'cases': results}, indent=2)+'\n')
