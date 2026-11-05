import Base

type T is Data:
  Leaf{}
  Node{l: T, r: T}

def f(d: Nat, +i: U32) -> U32:
  match d:
    case 0n:
      1
    case 1n++p:
      Bool.pick(U32, True{}, f(p, i), U32.add(f(p, U32.inc(i)), 1))

def g(d: Nat, +i: U32) -> Bool:
  match d:
    case 0n:
      True{}
    case 1n++p:
      g(p, i) && g(p, U32.inc(i))
