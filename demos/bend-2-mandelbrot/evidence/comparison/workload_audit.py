#!/usr/bin/env python3
"""Audit escape counts in the existing 320-bit timing scene using Decimal."""
from decimal import Decimal, localcontext
from pathlib import Path
from statistics import median
import json


def sample(digits):
    width, height = 2200, 1560
    rows = []
    with localcontext() as context:
        context.prec = digits
        span = Decimal('1e-68')
        for gy in range(8):
            for gx in range(8):
                x = gx * width // 8 + width // 16
                y = gy * height // 8 + height // 16
                cr = (Decimal(x) + Decimal('.5') - Decimal(width) / 2) * span / width
                ci = 1 + (Decimal(y) + Decimal('.5') - Decimal(height) / 2) * span / width
                zr = zi = Decimal(0)
                escaped = None
                for iteration in range(1, 16385):
                    zr, zi = zr * zr - zi * zi + cr, 2 * zr * zi + ci
                    if zr * zr + zi * zi > 256:
                        escaped = iteration
                        break
                rows.append({'x': x, 'y': y, 'escape_iteration': escaped})
    return rows


rows = sample(150)
assert rows == sample(200), 'Escape counts changed when oracle precision increased'
escaped = [r['escape_iteration'] for r in rows if r['escape_iteration'] is not None]
result = {
    'date': '2026-09-20',
    'scene': {'center': ['0', '1'], 'span': '1e-68', 'width': 2200, 'height': 1560,
              'reference_fractional_bits': 320, 'iteration_budget': 16384,
              'escape_radius_squared': 256},
    'method': '8x8 stratified pixel sample; independent Decimal recurrence at 150 and 200 decimal digits; identical escape counts at both precisions',
    'sampled_pixels': len(rows),
    'escaped': len(escaped),
    'bounded_at_budget': len(rows) - len(escaped),
    'escape_iteration_min': min(escaped),
    'escape_iteration_median': median(escaped),
    'escape_iteration_max': max(escaped),
    'scope': 'A sample, not a complete image census or a GPU instruction count. Boundary pixels can take much longer.',
    'samples': rows,
}
Path(__file__).with_name('workload-audit.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({k: v for k, v in result.items() if k != 'samples'}, indent=2))
