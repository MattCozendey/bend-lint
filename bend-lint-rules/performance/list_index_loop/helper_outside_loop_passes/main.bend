import Base

def or_zero(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}:
      0
    case Some{x}:
      x

def at(xs: List<&2, U32>, i: Nat) -> U32:
  or_zero(List.get(&2, U32, xs, i))

def f(xs: List<&2, U32>) -> U32:
  at(xs, 3n)
