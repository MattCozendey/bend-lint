import Base

type T is Data:
  Leaf{}
  Node{l: T, r: T}

def f(d: Nat, +i: U32) -> T:
  match d:
    case 0n:
      Leaf{}
    case 1n++p:
      # bend-lint: expect-next performance/missed_fork@hint -- two calls of f in a constructor
      Node{f(p, i), f(p, U32.inc(i))}
