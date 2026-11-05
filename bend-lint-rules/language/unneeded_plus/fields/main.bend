import Base

def f(xs: List<&2, Nat>) -> Nat:
  match xs:
    case Nil{}:
      0n
    # bend-lint: expect-next language/unneeded_plus@hint -- +h is used once
    case Con{+h, t}:
      # bend-lint: expect-next language/unneeded_plus@hint -- +y is used once
      +y = h
      y
