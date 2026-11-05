import Base

def free(xs: List<&2, U32>) -> Unit:
  match xs:
    case Nil{}:
      Unit{}
    case Con{x, rest}:
      free(rest)

def main(img: Image, xs: List<&2, U32>) -> Unit:
  Image.drop(img)

def id(n: U32) -> U32:
  n

def g(n: U32) -> U32:
  id!(n)
