import Base

def pow2(d: Nat, +acc: U32) -> U32:
  match d:
    case 0n:
      acc
    case 1n+p:
      pow2(p, U32.add(acc, acc))

def f(d: Nat, +lo: U32) -> U32:
  match d:
    case 0n:
      lo
    case 1n++p:
      a b = f(p, lo) f(p, U32.add(lo, pow2(p, 1)))
      U32.add(a, b)
