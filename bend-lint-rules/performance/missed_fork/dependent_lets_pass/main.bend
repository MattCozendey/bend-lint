import Base

type T is Data:
  Leaf{}
  Node{l: T, r: T}

def f(d: Nat, x: U32) -> U32:
  match d:
    case 0n:
      x
    case 1n++p:
      +l = f(p, x)
      r = f(p, l)
      (l + r : U32)
