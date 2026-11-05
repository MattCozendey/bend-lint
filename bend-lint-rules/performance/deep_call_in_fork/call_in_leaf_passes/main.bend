import Base

def pow2(d: Nat) -> U32:
  match d:
    case 0n:
      1
    case 1n+p:
      +h = pow2(p)
      U32.add(h, h)

def f(d: Nat, +lo: U32) -> U32:
  match d:
    case 0n:
      U32.add(lo, pow2(5n))
    case 1n++p:
      a b = f(p, lo) f(p, U32.add(lo, U32.shln(1, p)))
      U32.add(a, b)
