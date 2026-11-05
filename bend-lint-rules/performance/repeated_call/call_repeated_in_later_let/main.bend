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

def f(+xs: List<&2, U32>) -> Nat:
  +a = count(xs, 0n)
  # bend-lint: expect-next performance/repeated_call@information -- count(xs, 0n) again
  +b = count(xs, 0n)
  Nat.add(a, b)
