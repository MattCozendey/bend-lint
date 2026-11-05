import Base

def tree(+d: Nat) -> U32:
  match d:
    case 0n:
      1
    case 1n+p:
      a b = tree(p) tree(p)
      U32.add(a, b)

def f(d: Nat, +lo: U32) -> U32:
  match d:
    case 0n:
      lo
    case 1n++p:
      a b = f(p, lo) f(p, U32.add(lo, tree(p)))
      U32.add(a, b)
