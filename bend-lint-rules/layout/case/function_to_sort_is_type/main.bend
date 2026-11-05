import Base

# bend-lint: expect-next layout/case@warning -- f is a type
def Fam(f: @-x: U32 -> Type) -> Type:
  f(1)
