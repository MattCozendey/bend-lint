import Base

def deep(n: Nat) -> U32:
  match n:
    case 0n:
      0
    case 1n+p:
      (deep(p) + 1 : U32)

def f(c: Bool) -> Bool:
  # bend-lint: expect-next performance/eager_branch@information -- && computes its right side, which calls deep
  c && U32.is_eq(deep(9n), 9)
