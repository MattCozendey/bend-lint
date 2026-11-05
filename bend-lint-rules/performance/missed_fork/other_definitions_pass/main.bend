import Base

type T is Data:
  Leaf{}
  Node{l: T, r: T}

def g(d: Nat, +i: U32) -> U32:
  match d:
    case 0n:
      1
    case 1n++p:
      g(p, i)

def f(d: Nat, +i: U32) -> U32:
  match d:
    case 0n:
      1
    case 1n++p:
      U32.add(g(p, i), g(p, U32.inc(i)))
