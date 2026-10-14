# Bend needs every name defined above its uses. Topologically sort the
# defs/types of a file (stable: original order where there is no constraint;
# cycles from false matches are ignored). Usage: python3 tools/reorder.py f
import re, sys

path = sys.argv[1]
src = open(path).read()
parts = re.split(r'(?m)^(?=(?:def|type|law|@unsafe def) )', src)
head, blocks = parts[0], parts[1:]

def name(b):
    return re.match(r'(?:@unsafe )?(?:def|type|law) ([A-Za-z0-9_.]+)', b).group(1)

def strip_strings(t):
    return re.sub(r'"(?:[^"\\]|\\.)*"', '""', t)

names = [name(b) for b in blocks]
index = {}
for i, n in enumerate(names):
    index.setdefault(n, i)
# constructors of each type map to the type block
for i, b in enumerate(blocks):
    if b.startswith('type '):
        for c in re.findall(r'(?m)^  ([A-Z][A-Za-z0-9_]*)\{', b):
            index.setdefault(c, i)

deps = []
for i, b in enumerate(blocks):
    body = strip_strings(b)
    body = re.sub(r'#.*', '', body)
    ds = set()
    for m in re.finditer(r'(?<![A-Za-z0-9_.])([A-Za-z_][A-Za-z0-9_.]*)', body):
        tok = m.group(1)
        nxt = body[m.end():m.end() + 1]
        # a call, a constructor, or a type name; not a field or binder
        if not (nxt == '(' or tok[0].isupper() or body[m.start() - 1:m.start()] == '~'):
            continue
        j = index.get(tok)
        if j is not None and j != i:
            ds.add(j)
    deps.append(sorted(ds))

out, state = [], [0] * len(blocks)
def visit(i):
    if state[i] == 2 or state[i] == 1:
        return
    state[i] = 1
    for j in deps[i]:
        visit(j)
    state[i] = 2
    out.append(i)

for i in range(len(blocks)):
    visit(i)
open(path, 'w', newline='\n').write(head + ''.join(blocks[i] if blocks[i].endswith('\n') else blocks[i] + '\n' for i in out))
print('reordered', path)
