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

# The value numbered `i` in `t`: `odd` is whether `i` is.
def Table.at(-A: Data, t: Table<A>, +i: U32, odd: Bool) -> Maybe<&2, A>:
  match t odd:
    case TLeaf{v} _:
      v
    case TNode{e, o} False{}:
      Table.at(A, e, U32.shr(i), U32.is_eq(U32.and(U32.shr(i), 1), 1))
    case TNode{e, o} True{}:
      Table.at(A, o, U32.shr(i), U32.is_eq(U32.and(U32.shr(i), 1), 1))

def Table.find(-A: Data, t: Table<A>, +i: U32, inside: Bool) -> Maybe<&2, A>:
  match inside:
    case False{}:
      None{}
    case True{}:
      Table.at(A, t, i, U32.is_eq(U32.and(i, 1), 1))

def Indexed.get(-A: Data, x: Indexed<A>, +i: U32) -> Maybe<&2, A>:
  match x:
    case Indexed{size, table}:
      Table.find(A, table, i, U32.is_lt(i, size))
