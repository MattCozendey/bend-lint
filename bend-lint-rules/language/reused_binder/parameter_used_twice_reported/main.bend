import Base

def f(c: Bool, x: Nat) -> Nat:
  # bend-lint: expect-next language/reused_binder@warning -- x is used twice on one path
  Bool.pick(Nat, c, x, x)
