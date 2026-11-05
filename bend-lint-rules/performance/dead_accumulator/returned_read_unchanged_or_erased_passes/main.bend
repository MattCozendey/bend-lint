import Base

def g(todo: List<&2, U32>, done: List<&2, U32>) -> List<&2, U32>:
  match todo:
    case Nil{}:
      done
    case Con{h, t}:
      g(t, h <> done)

def m(todo: List<&2, U32>, +done: List<&2, U32>) -> Nat:
  match todo:
    case Nil{}:
      0n
    case Con{h, t}:
      Nat.add(List.length(&2, U32, done), m(t, h <> done))

def p(todo: List<&2, U32>, done: List<&2, U32>) -> Nat:
  match todo:
    case Nil{}:
      0n
    case Con{h, t}:
      p(t, done)

def e(todo: List<&2, U32>, -done: List<&2, U32>) -> Nat:
  match todo:
    case Nil{}:
      0n
    case Con{h, t}:
      e(t, h <> done)
