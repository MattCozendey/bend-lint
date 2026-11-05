import Base
# bend-lint: expect-next layout/case@warning -- leaf is an import alias
import ./leaf.bend as leaf

# bend-lint: expect-next layout/case@warning -- my_box is a type
type my_box is Data:
  # bend-lint: expect-next layout/case@warning -- my_Box is a constructor, myVal a field
  my_Box{myVal: U32}

# bend-lint: expect-next layout/case@warning -- pair_of returns a type, a is a type
def pair_of(a: Type) -> Type:
  a

# bend-lint: expect-next layout/case@warning -- IdF and X are not types
def IdF(X: U32) -> U32:
  X

# bend-lint: expect-next layout/case@warning -- Odd_law is a law
law Odd_law:
  for x: U32
  U32

def main() -> U32:
  leaf.one()
