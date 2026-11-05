import Base

def count(xs: List<&2, U32>, +n: Nat) -> Nat:
  match xs:
    case Nil{}:
      n
    case Con{x, t}:
      count(t, 1n+n)

def copy(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      x <> copy(t)

def f(+xs: List<&2, U32>, d: Nat) -> Nat:
  match d:
    case 0n:
      0n
    case 1n+p:
      Nat.add(Nat.add(count(xs, 0n), count(xs, 0n)), f(xs, p))
