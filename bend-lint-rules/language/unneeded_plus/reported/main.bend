import Base

# bend-lint: expect-next language/unneeded_plus@hint -- +x is used once
def f(+x: Nat, y: Nat) -> Nat:
  Nat.add(x, y)
