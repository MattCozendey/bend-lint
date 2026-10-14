import Base
import ./life.bend as Life
import ../shared/grid.bend as G

# Empty subtrees take one node. Bounds are absolute word indices, so whole
# regions outside the live cells' neighbourhood can be skipped safely.
type Grid is Data:
  Empty{}
  Leaf{index: U32, word: U32}
  Branch{low: U32, high: U32, left: Grid, right: Grid}

def empty(g: Grid) -> Bool:
  match g:
    case Empty{}:
      True{}
    case _:
      False{}

def low(g: Grid) -> U32:
  match g:
    case Empty{}:
      4294967295
    case Leaf{i, w}:
      i
    case Branch{lo, hi, l, r}:
      lo

def high(g: Grid) -> U32:
  match g:
    case Empty{}:
      0
    case Leaf{i, w}:
      i
    case Branch{lo, hi, l, r}:
      hi

def leaf(zero: Bool, i: U32, w: U32) -> Grid:
  match zero:
    case True{}:
      Empty{}
    case False{}:
      Leaf{i, w}

def join_empty(zero: Bool, +a: Grid, +b: Grid) -> Grid:
  match zero:
    case True{}:
      Empty{}
    case False{}:
      Branch{U32.min(low(a), low(b)), U32.max(high(a), high(b)), a, b}

def join(+a: Grid, +b: Grid) -> Grid:
  join_empty(empty(a) && empty(b), a, b)

def first(g: Grid) -> U32:
  match g:
    case Empty{}:
      0
    case Leaf{i, w}:
      w
    case Branch{lo, hi, left, right}:
      first(left)

def get(depth: Nat, g: Grid, +index: U32) -> U32:
  match depth:
    case 0n:
      first(g)
    case 1n+ +p:
      match g:
        case Empty{}:
          0
        case Leaf{i, w}:
          w
        case Branch{lo, hi, left, right}:
          +half = U32.shln(1, p)
          get(p, Bool.pick(Grid, (index < half : U32), left, right), (index .&. (half - 1) : U32))

def rowword(g: Grid, depth: Nat, +size: U32, x: U32, y: U32) -> U32:
  +wide = (size / 32 : U32)
  get(depth, g, (((y .&. (size - 1)) * wide) + (x .&. (wide - 1)) : U32))

def word(+g: Grid, +depth: Nat, +size: U32, +i: U32) -> U32:
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
  c1 = Life.add(Life.Counts{0, 0, 0, 0}, Life.west(nw, n))
  c2 = Life.add(c1, n)
  c3 = Life.add(c2, Life.east(n, ne))
  c4 = Life.add(c3, Life.west(mw, m))
  c5 = Life.add(c4, Life.east(m, me))
  c6 = Life.add(c5, Life.west(sw, s))
  c7 = Life.add(c6, s)
  Life.rule(Life.add(c7, Life.east(s, se)), m)

# A torus neighbour is at most two word-rows away in flattened indices,
# including horizontal wrapping. The wrapped tails are checked separately.
def active(+offset: U32, span: U32, +lo: U32, +hi: U32, +size: U32) -> Bool:
  +margin = (2 * (size / 32) : U32)
  +total = ((size / 32) * size : U32)
  +end = (offset + span : U32)
  ((offset <= hi + margin : U32) && (end > U32.max(lo, margin) - margin : U32)) ||
    ((lo < margin : U32) && (end > total - (margin - lo) : U32)) ||
    ((hi + margin >= total : U32) && (offset <= hi + margin - total : U32))

def update(fuel: Nat, enabled: Bool, +g: Grid, +depth: Nat, +size: U32, +offset: U32) -> Grid:
  match fuel:
    case 0n:
      match enabled:
        case False{}:
          Empty{}
        case True{}:
          +w = word(g, depth, size, offset)
          leaf(U32.is_eq(w, 0), offset, w)
    case 1n+ +p:
      match enabled:
        case False{}:
          Empty{}
        case True{}:
          +half = U32.shln(1, p)
          +right = (offset + half : U32)
          a b = update(p, active(offset, half, low(g), high(g), size), g, depth, size, offset) update(p, active(right, half, low(g), high(g), size), g, depth, size, right)
          join(a, b)

def step(+depth: Nat, size: U32, +g: Grid) -> Grid:
  update(depth, Bool.not(empty(g)), g, depth, size, 0)

def initial(depth: Nat, +kind: U32, +size: U32, +seed: U32, +offset: U32) -> Grid:
  match depth:
    case 0n:
      +w = Life.seed_word(kind, size, seed, offset)
      leaf(U32.is_eq(w, 0), offset, w)
    case 1n+ +p:
      a b = initial(p, kind, size, seed, offset) initial(p, kind, size, seed, (offset + (1 << p) : U32))
      join(a, b)

def run(steps: Nat, +depth: Nat, +size: U32, g: Grid) -> Grid:
  match steps:
    case 0n:
      g
    case 1n+p:
      run(p, depth, size, step(depth, size, g))

type Replay is Data:
  End{last: Grid}
  Frame{grid: Grid, next: Replay}

# Retain every state while advancing a short batch in one GPU call.
def record(steps: Nat, +depth: Nat, +size: U32, +g: Grid) -> Replay:
  match steps:
    case 0n:
      End{g}
    case 1n+p:
      Frame{g, record(p, depth, size, step(depth, size, g))}

# Only nonzero word-index/value pairs are exported. Every generation remains.
def text(g: Grid) -> String:
  match g:
    case Empty{}:
      ""
    case Leaf{i, w}:
      U32.show(i) ++ " " ++ U32.show(w) ++ " "
    case Branch{lo, hi, left, right}:
      text(left) ++ text(right)

def expand(depth: Nat, +g: Grid) -> G.Grid:
  match depth:
    case 0n:
      G.Leaf{get(0n, g, 0)}
    case 1n+ +p:
      match g:
        case Empty{}:
          a b = expand(p, Empty{}) expand(p, Empty{})
          G.Branch{a, b}
        case Leaf{i, w}:
          G.Leaf{w}
        case Branch{lo, hi, left, right}:
          a b = expand(p, left) expand(p, right)
          G.Branch{a, b}
