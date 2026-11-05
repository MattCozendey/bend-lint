import Base

def f(+m: Nat, n: Nat) -> Nat:
  match n:
    case 0n:
      m
    case 1n+p:
      f(m, p)

@unsafe
def g(n: Nat) -> Nat:
  g(n)

def h?(n: Nat) -> Nat:
  h(n)

def Ord(xs: List<&2, Nat>) -> Type:
  match xs:
    case Nil{}:
      Unit
    case x <> t:
      (Nat & Ord(t))
