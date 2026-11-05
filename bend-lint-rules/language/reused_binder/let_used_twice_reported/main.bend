import Base

def f(x: Nat) -> Nat:
  y = x
  # bend-lint: expect-next language/reused_binder@warning -- y is used twice
  Nat.add(y, y)
