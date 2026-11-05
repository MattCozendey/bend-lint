import Base

type Shape is Data:
  Circle{r: U32}
  Rect{w: U32, h: String}

def again(x: Shape) -> Shape:
  match x:
    case Circle{r}:
      x
    case Rect{w, h}:
      x
