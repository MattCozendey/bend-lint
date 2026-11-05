import Base

def F(-T: Type) -> Type:
  @ - foo_qux: T -> T

def k(xs: List<U32>) -> U32 -> U32:
  match xs:
    case Con{+my_head, rest}:
      foo_bar => (my_head + foo_bar : U32)
    case Nil{}:
      foo_bar => foo_bar
