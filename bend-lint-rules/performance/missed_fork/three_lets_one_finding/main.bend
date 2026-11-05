import Base

type T is Data:
  Leaf{}
  Node{l: T, r: T}

def f(d: Nat, +i: U32) -> U32:
  match d:
    case 0n:
      1
    case 1n++p:
      # bend-lint: expect-next performance/missed_fork@hint -- three lets of calls of f in a row
      x = f(p, i)
      y = f(p, U32.inc(i))
      z = f(p, U32.add(i, 2))
      (x + y + z : U32)
