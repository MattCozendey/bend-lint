import Base

type T is Data:
  Leaf{}
  Node{l: T, r: T}

def f(d: Nat, +i: U32) -> IO(Unit):
  match d:
    case 0n:
      IO.print("x")
    case 1n++p:
      IO.bind(Unit, Unit, f(p, i), u => f(p, U32.inc(i)))
