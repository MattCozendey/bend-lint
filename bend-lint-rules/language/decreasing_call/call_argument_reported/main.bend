import Base

def f(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+p:
      # bend-lint: expect-next language/decreasing_call@warning -- argument 1 is a call
      f(Nat.add(p, 1n))
