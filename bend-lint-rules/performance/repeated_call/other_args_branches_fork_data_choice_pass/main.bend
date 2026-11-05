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
  Nat.add(count(xs, 0n), count(xs, 1n))

def g(+xs: List<&2, U32>, b: Bool) -> Nat:
  match b:
    case True{}:
      count(xs, 0n)
    case False{}:
      count(xs, 0n)

def h(+xs: List<&2, U32>) -> Nat:
  a b = count(xs, 0n) count(xs, 0n)
  Nat.add(a, b)

def k(+xs: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, copy(xs), copy(xs))

def m(+xs: List<&2, U32>, b: Bool) -> Nat:
  Bool.pick(Nat, b, count(xs, 0n), count(xs, 0n))
