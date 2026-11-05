import Base

def deep(n: Nat) -> U32:
  match n:
    case 0n:
      0
    case 1n+p:
      (deep(p) + 1 : U32)

def g(n: Nat) -> U32:
  (deep(n) + 1 : U32)

def f(c: Bool) -> U32:
  # bend-lint: expect-next performance/eager_branch@information -- Bool.pick computes g(9n), which calls deep
  Bool.pick(U32, c, 7, g(9n))
