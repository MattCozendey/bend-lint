import Base

def f(d: Nat, +lo: U32) -> U32:
  match d:
    case 0n:
      lo
    case 1n++p:
      a b = f(p, lo) f(p, U32.add(lo, U32.shln(1, p)))
      U32.add(a, b)
