import Base

def f(n: Nat, m: Nat) -> Nat:
  match n:
    case 0n:
      m
    case 1n+p:
      # bend-lint: expect-next language/decreasing_call@warning -- argument 1 is m, not a part of n
      f(m, p)
