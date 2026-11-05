import Base

def or_zero(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}:
      0
    case Some{x}:
      x

def f(n: Nat, +xs: List<&2, U32>, +i: Nat, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      U32.add(f(p, xs, i, acc), f(p, List.drop(&2, U32, xs, 1n), i, acc))
