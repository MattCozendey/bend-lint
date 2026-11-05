import Base

type T is Data:
  Leaf{}
  Node{l: T, r: T}

def f(d: Nat, +i: U32) -> U32:
  match d:
    case 0n:
      1
    case 1n++p:
      # bend-lint: expect-next performance/missed_fork@hint -- a typed let counts
      l = f(p, i)
      r: U32 = f(p, U32.inc(i))
      (l + r : U32)
