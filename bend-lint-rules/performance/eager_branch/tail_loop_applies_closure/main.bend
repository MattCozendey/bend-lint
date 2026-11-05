import Base

def apply(f: U32 -> U32, x: U32) -> U32:
  f(x)

def walk(n: Nat, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      walk(p, apply(x => (x + 1 : U32), acc))

def f(c: Bool) -> U32:
  # bend-lint: expect-next performance/eager_branch@information -- Bool.pick computes walk, which applies a closure at each step
  Bool.pick(U32, c, 7, walk(9n, 0))
