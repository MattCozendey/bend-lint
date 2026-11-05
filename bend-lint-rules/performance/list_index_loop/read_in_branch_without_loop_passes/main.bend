import Base

def or_zero(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}:
      0
    case Some{x}:
      x

def f(n: Nat, +xs: List<&2, U32>, acc: U32) -> U32:
  match n:
    case 0n:
      U32.add(acc, U32.from_nat(List.length(&2, U32, xs)))
    case 1n+p:
      f(p, xs, U32.add(acc, 1))
