import Base

# Values by number, from 0: a balanced tree. Each node parts its values by a bit of their number, the lowest first, so
# a lookup reads the bits of a number, and no text.
type Table<-A: Data> is Data:
  TLeaf{value: Maybe<&2, A>}
  TNode{even: Table<A>, odd: Table<A>}

# A table grows one value at a time: a leaf holds the value whose number has no bits left (the number read from its
# lowest bit, a bit a level), so a value numbered `i` is about log2(i) levels down.

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
