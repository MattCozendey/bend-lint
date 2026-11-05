import Base

def f(+x: Nat) -> Nat:
  Nat.add(x, x)

def g(+n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+p:
      Nat.add(p, p)
