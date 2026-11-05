import Base

def count(xs: List<&2, U32>, +n: Nat) -> Nat:
  match xs:
    case Nil{}:
      n
    case Con{x, t}:
      count(t, 1n+n)

def twice(+n: Nat) -> Nat:
  Nat.add(n, n)

def f(k: Nat, +xs: List<&2, U32>, +acc: Nat) -> Nat:
  match k:
    case 0n:
      acc
    case 1n+p:
      # bend-lint: expect-next performance/loop_invariant_call@information -- count(xs, 0n) on every step
      f(p, xs, Nat.add(acc, count(xs, 0n)))
