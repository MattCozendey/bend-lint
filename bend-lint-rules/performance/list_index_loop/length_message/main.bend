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
      f(p, xs, i, U32.add(acc, U32.from_nat(List.length(&2, U32, xs))))
