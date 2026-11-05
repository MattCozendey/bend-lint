import Base

def f(n: Nat) -> Nat:
  # bend-lint: expect-next language/decreasing_call@warning -- every argument is unchanged
  f(n)
