import Base

def or_zero(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}:
      0
    case Some{x}:
      x

def f(n: Nat, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n++p:
      f(p, U32.add(acc, or_zero(List.get(&2, U32, [1, 2, 3], p))))
