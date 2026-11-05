import Base

def f(c: Bool, +x: Nat) -> Nat:
  Bool.pick(Nat, c, x, x)

def g(c: Bool, x: Nat, y: Nat) -> Nat:
  match c:
    case True{}:
      Nat.add(x, y)
    case False{}:
      x

def k(x: Nat) -> Nat:
  match x:
    case 0n:
      Nat.add(x, x)
    case 1n+p:
      p

def t(x: Nat) -> Nat:
  ({x : Nat} : Nat)
