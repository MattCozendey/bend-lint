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
      lo
    case 1n++p:
      # bend-lint: expect-next performance/deep_call_in_fork@information -- pow2 is not tail-recursive
      a b = f(p, lo) f(p, U32.add(lo, pow2(p)))
      U32.add(a, b)
