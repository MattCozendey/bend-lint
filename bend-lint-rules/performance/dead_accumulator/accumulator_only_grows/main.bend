import Base

# bend-lint: expect-next performance/dead_accumulator@information -- done only grows
def f(todo: List<&2, U32>, done: List<&2, U32>) -> Nat:
  match todo:
    case Nil{}:
      0n
    case Con{h, t}:
      f(t, h <> done)
