import Base

type T is Data:
  Leaf{}
  Node{l: T, r: T}

def f(d: Nat, +i: U32) -> U32:
  match d:
    case 0n:
      1
    case 1n++p:
      # bend-lint: expect-next performance/missed_fork@hint -- two calls of f under an operator
      (f(p, i) + f(p, U32.inc(i)) : U32)
