import Base

def main() -> Nat:
  # bend-lint: expect-next language/forward_reference@warning -- later is below main
  later()

def later() -> Nat:
  1n
