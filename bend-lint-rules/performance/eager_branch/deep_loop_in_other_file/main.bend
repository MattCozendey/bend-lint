import Base
import ./loops.bend as L

def f(c: Bool) -> U32:
  # bend-lint: expect-next performance/eager_branch@information -- Bool.pick computes L.deep(9n) even when unused
  Bool.pick(U32, c, 7, L.deep(9n))
