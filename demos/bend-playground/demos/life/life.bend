import Base
import ../shared/grid.bend as G

# Conway B3/S23 on a torus. Each U32 updates 32 cells in parallel using
# bit planes; the tree distributes independent words over CPU/GPU workers.
type Counts is Data:
  Counts{ones: U32, twos: U32, fours: U32, eights: U32}

def add(c: Counts, +bits: U32) -> Counts:
  Counts{+a, +b, +c, d} = c
  +carry1 = (a .&. bits : U32)
  +carry2 = (b .&. carry1 : U32)
  Counts{(a .^. bits : U32), (b .^. carry1 : U32), (c .^. carry2 : U32), (d .^. (c .&. carry2) : U32)}

def rule(c: Counts, old: U32) -> U32:
  Counts{a, b, c, d} = c
  ((old .|. a) .&. b .&. U32.not((c .|. d : U32)) : U32)

def west(left: U32, mid: U32) -> U32:
  ((mid << 1n) .|. (left >> 31n) : U32)

def east(mid: U32, right: U32) -> U32:
  ((mid >> 1n) .|. (right << 31n) : U32)

def rowword(g: G.Grid, depth: Nat, +size: U32, x: U32, y: U32) -> U32:
  +wide = (size / 32 : U32)
  G.lookup(depth, g, (((y .&. (size - 1)) * wide) + (x .&. (wide - 1)) : U32))

def word(+g: G.Grid, +depth: Nat, +size: U32, +i: U32) -> U32:
  +x = (i % (size / 32) : U32)
  +y = (i / (size / 32) : U32)
  +n = rowword(g, depth, size, x, (y - 1 : U32))
  +m = rowword(g, depth, size, x, y)
  +s = rowword(g, depth, size, x, (y + 1 : U32))
  nw = rowword(g, depth, size, (x - 1 : U32), (y - 1 : U32))
  ne = rowword(g, depth, size, (x + 1 : U32), (y - 1 : U32))
  mw = rowword(g, depth, size, (x - 1 : U32), y)
  me = rowword(g, depth, size, (x + 1 : U32), y)
  sw = rowword(g, depth, size, (x - 1 : U32), (y + 1 : U32))
  se = rowword(g, depth, size, (x + 1 : U32), (y + 1 : U32))
  c1 = add(Counts{0, 0, 0, 0}, west(nw, n))
  c2 = add(c1, n)
  c3 = add(c2, east(n, ne))
  c4 = add(c3, west(mw, m))
  c5 = add(c4, east(m, me))
  c6 = add(c5, west(sw, s))
  c7 = add(c6, s)
  rule(add(c7, east(s, se)), m)

def update(fuel: Nat, +g: G.Grid, +depth: Nat, +size: U32, +offset: U32) -> G.Grid:
  match fuel:
    case 0n:
      G.Leaf{word(g, depth, size, offset)}
    case 1n+ +p:
      a b = update(p, g, depth, size, offset) update(p, g, depth, size, (offset + (1 << p) : U32))
      G.Branch{a, b}

def step(+depth: Nat, size: U32, g: G.Grid) -> G.Grid:
  update(depth, g, depth, size, 0)

def hash(+x: U32) -> U32:
  +a = ((x .^. (x >> 16n)) * 2246822519 : U32)
  +b = ((a .^. (a >> 13n)) * 3266489917 : U32)
  (b .^. (b >> 16n) : U32)

def pattern(kind: U32, +x: U32, +y: U32) -> Bool:
  match kind:
    case 1:
      (U32.is_eq(y, 0) && U32.is_eq(x, 1)) || (U32.is_eq(y, 1) && U32.is_eq(x, 2)) || (U32.is_eq(y, 2) && (x <= 2 : U32))
    case _:
      U32.is_eq(y, 1) && (x <= 2 : U32)

def seed_bits(fuel: Nat, +kind: U32, +size: U32, +i: U32, acc: U32) -> U32:
  match fuel:
    case 0n:
      acc
    case 1n+ +p:
      +bit = U32.from_nat(p)
      +x = ((i % (size / 32)) * 32 + bit - size / 2 : U32)
      +y = (i / (size / 32) - size / 2 : U32)
      mask = U32.shln(Bool.to_u32(pattern(kind, x, y)), p)
      seed_bits(p, kind, size, i, (acc .|. mask : U32))

def seed_word(kind: U32, size: U32, +seed: U32, +i: U32) -> U32:
  match kind:
    case 0:
      (hash((i + seed : U32)) .&. hash((i + seed + 2654435761 : U32)) : U32)
    case _:
      seed_bits(32n, kind, size, i, 0)

def initial(depth: Nat, +kind: U32, +size: U32, +seed: U32, +offset: U32) -> G.Grid:
  match depth:
    case 0n:
      G.Leaf{seed_word(kind, size, seed, offset)}
    case 1n+ +p:
      a b = initial(p, kind, size, seed, offset) initial(p, kind, size, seed, (offset + (1 << p) : U32))
      G.Branch{a, b}

def run(generations: Nat, +depth: Nat, +size: U32, g: G.Grid) -> G.Grid:
  match generations:
    case 0n:
      g
    case 1n+p:
      run(p, depth, size, step(depth, size, g))
