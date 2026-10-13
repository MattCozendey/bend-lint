import Base
import ./lists.bend as Lists

# Values by number, from 0: a balanced tree. Each node parts its values by a bit of their number, the lowest first, so
# a lookup reads the bits of a number, and no text.
type Table<-A: Data> is Data:
  TLeaf{value: Maybe<&2, A>}
  TNode{even: Table<A>, odd: Table<A>}

# A table and its size, a power of two.
type Indexed<-A: Data> is Data:
  Indexed{size: U32, table: Table<A>}

# The smallest power of two at least `n`, and its exponent.
def Table.fit(fuel: Nat, +n: U32, +size: U32, depth: Nat, fits: Bool) -> U32 & Nat:
  match fuel fits:
    case _ True{}:
      (size, depth)
    case 0n False{}:
      (size, depth)
    case 1n+f False{}:
      Table.fit(f, n, (size * 2: U32), 1n+depth, U32.is_le(n, (size * 2: U32)))

# The node over the values parted in `halves` (those at even places, and those at odd), `depth` levels above its leaves.
def Table.grow(-A: Data, +depth: Nat, halves: List<&2, A> & List<&2, A>) -> Table<A>:
  match depth halves:
    case 0n Tuple{e, o}:
      TNode{TLeaf{List.head(&2, A, e)}, TLeaf{List.head(&2, A, o)}}
    case 1n+d Tuple{e, o}:
      # bend-lint: expect-next performance/missed-fork@information -- measured: forking the halves made no run faster, as the table is a small part of a run
      TNode{Table.grow(A, d, Lists.deal(&2, A, e)), Table.grow(A, d, Lists.deal(&2, A, o))}

def Table.root(-A: Data, depth: Nat, xs: List<&2, A>) -> Table<A>:
  match depth:
    case 0n:
      TLeaf{List.head(&2, A, xs)}
    case 1n+d:
      Table.grow(A, d, Lists.deal(&2, A, xs))

def Table.sized(-A: Data, xs: List<&2, A>, fit: U32 & Nat) -> Indexed<A>:
  match fit:
    case Tuple{size, depth}:
      Indexed{size, Table.root(A, depth, xs)}

# The values of `xs`, numbered from 0; `n` is its length.
def Table.of(-A: Data, +n: U32, xs: List<&2, A>) -> Indexed<A>:
  Table.sized(A, xs, Table.fit(33n, n, 1, 0n, U32.is_le(n, 1)))

# A table that grows, one value at a time: a leaf holds the value whose number has no bits left (the number read from its
# lowest bit, a bit a level), so a value numbered `i` is about log2(i) levels down. A table `Table.of` built is one.

# The value numbered `i` in `t`: `odd` is whether `i` is.
def Table.get(-A: Data, t: Table<A>, +i: U32, odd: Bool) -> Maybe<&2, A>:
  match t odd:
    case TLeaf{v} _:
      Bool.pick(Maybe<&2, A>, U32.is_zero(i), v, None{})
    case TNode{e, o} False{}:
      Table.get(A, e, U32.shr(i), U32.is_eq(U32.and(U32.shr(i), 1), 1))
    case TNode{e, o} True{}:
      Table.get(A, o, U32.shr(i), U32.is_eq(U32.and(U32.shr(i), 1), 1))

def Table.read(-A: Data, t: Table<A>, +i: U32) -> Maybe<&2, A>:
  Table.get(A, t, i, U32.is_eq(U32.and(i, 1), 1))

# `t` with `x` numbered `i`: `odd` is whether `i` is, and `zero` whether it is 0. A leaf of another number parts
# first. `fuel` bounds the levels: two a bit.
def Table.put(-A: Data, fuel: Nat, t: Table<A>, +i: U32, x: A, odd: Bool, zero: Bool) -> Table<A>:
  match fuel t odd zero:
    case 0n _ _ _:
      t
    case 1n+f TLeaf{v} _ True{}:
      TLeaf{Some{x}}
    case 1n+f TLeaf{v} _ False{}:
      Table.put(A, f, TNode{TLeaf{v}, TLeaf{None{}}}, i, x, odd, zero)
    case 1n+f TNode{e, o} False{} _:
      TNode{
        Table.put(
          A,
          f,
          e,
          U32.shr(i),
          x,
          U32.is_eq(U32.and(U32.shr(i), 1), 1),
          U32.is_zero(U32.shr(i))
        ),
        o
      }
    case 1n+f TNode{e, o} True{} _:
      TNode{
        e,
        Table.put(
          A,
          f,
          o,
          U32.shr(i),
          x,
          U32.is_eq(U32.and(U32.shr(i), 1), 1),
          U32.is_zero(U32.shr(i))
        )
      }

def Table.set(-A: Data, t: Table<A>, +i: U32, x: A) -> Table<A>:
  Table.put(A, 66n, t, i, x, U32.is_eq(U32.and(i, 1), 1), U32.is_zero(i))

def Indexed.get(-A: Data, x: Indexed<A>, i: U32) -> Maybe<&2, A>:
  match x:
    case Indexed{size, table}:
      Table.read(A, table, i)

def Table.both(~A: Data, ~f: A -> A -> A, a: Maybe<&2, A>, b: Maybe<&2, A>) -> Maybe<&2, A>:
  match a b:
    case Some{x} Some{y}:
      Some{f(x, y)}
    case Some{x} None{}:
      Some{x}
    case None{} y:
      y

# The values of both tables, by number; `f` makes one of two values with one number, the first's first.
def Table.merge(~A: Data, ~f: A -> A -> A, +a: Table<A>, b: Table<A>) -> Table<A>:
  match a b:
    case TLeaf{x} TLeaf{y}:
      TLeaf{Table.both(~A, ~f, x, y)}
    case TNode{e, o} TNode{p, q}:
      evens odds = Table.merge(~A, ~f, e, p) Table.merge(~A, ~f, o, q)
      TNode{evens, odds}
    case TLeaf{x} TNode{p, q}:
      TNode{Table.merge(~A, ~f, a, p), q}
    case TNode{e, o} TLeaf{y}:
      TNode{Table.merge(~A, ~f, e, TLeaf{y}), o}

# The numbers of `t`'s values, onto `out`: `at` is what this part of the table has numbered so far, and `bit` the next
# bit of a number below it.
def Table.numbers(-A: Data, t: Table<A>, +at: U32, +bit: U32, out: List<&2, U32>) -> List<&2, U32>:
  match t:
    case TLeaf{Some{v}}:
      at <> out
    case TLeaf{None{}}:
      out
    case TNode{e, o}:
      Table.numbers(
        A,
        o,
        (at + bit: U32),
        (bit * 2: U32),
        Table.numbers(A, e, at, (bit * 2: U32), out)
      )

# `t` with `f(c, v)` for each value `v`.
def Table.map(~C: Data, ~A: Data, ~B: Data, ~f: @+c: C -> A -> B, +c: C, t: Table<A>) -> Table<B>:
  match t:
    case TLeaf{Some{v}}:
      TLeaf{Some{f(c, v)}}
    case TLeaf{None{}}:
      TLeaf{None{}}
    case TNode{e, o}:
      evens odds = Table.map(~C, ~A, ~B, ~f, c, e) Table.map(~C, ~A, ~B, ~f, c, o)
      TNode{evens, odds}

def Indexed.map(
  ~C: Data,
  ~A: Data,
  ~B: Data,
  ~f: @+c: C -> A -> B,
  c: C,
  x: Indexed<A>
) -> Indexed<B>:
  match x:
    case Indexed{size, table}:
      Indexed{size, Table.map(~C, ~A, ~B, ~f, c, table)}
