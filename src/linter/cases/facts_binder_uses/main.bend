import Base

type Shape is Data:
  Circle{r: U32}
  Rect{w: U32, h: String}

def area(x: Shape, k: U32) -> U32:
  match x:
    case Circle{r}:
      (r * k : U32)
    case Rect{w, h}:
      w

def inc(+n: U32) -> U32:
  f : U32 -> U32 = z => (z + n : U32)
  f(n)
