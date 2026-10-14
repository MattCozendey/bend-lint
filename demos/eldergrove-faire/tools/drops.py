# drops.py park.c: per emitted function, how many term_drop / term_keep /
# rfc_wrap calls it contains (the reference-count work), top 30
import re, sys
src = open(sys.argv[1] if len(sys.argv) > 1 else 'park.c').read()
funcs = re.split(r'\n(?=(?:INLINE |static |OUTLINE )?[A-Za-z_][A-Za-z0-9_ \*]* (?:spin_\d+|WL_FID_[A-Z0-9_]+)\()', src)
rows = []
for f in funcs:
    m = re.match(r'(?:INLINE |static |OUTLINE )?[A-Za-z_][A-Za-z0-9_ \*]* (spin_\d+|WL_FID_[A-Z0-9_]+)\(', f)
    if not m:
        continue
    d, k, w = f.count('term_drop('), f.count('term_keep('), f.count('rfc_wrap(')
    if d + k + w:
        rows.append((d + k + w, d, k, w, m.group(1)))
for r in sorted(rows, reverse=True)[:30]:
    print('%4d  drop %3d  keep %3d  wrap %3d  %s' % r)
