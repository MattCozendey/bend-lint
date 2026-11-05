import Base

def F(-T: Type) -> Type:
  # bend-lint: expect-next layout/case@warning -- fooQux is not snake_case
  @ - fooQux: T -> T

def k(xs: List<U32>) -> U32 -> U32:
  match xs:
    # bend-lint: expect-next layout/case@warning -- myHead is not snake_case
    case Con{+myHead, rest}:
      # bend-lint: expect-next layout/case@warning -- fooBar is not snake_case
      fooBar => (myHead + fooBar : U32)
    case Nil{}:
      # bend-lint: expect-next layout/case@warning -- fooBar is not snake_case
      fooBar => fooBar
