import Base

def free(xs: List<&2, U32>) -> Unit:
  match xs:
    case Nil{}:
      Unit{}
    case Con{x, rest}:
      free(rest)

def main(xs: List<&2, U32>) -> Unit:
  # bend-lint: expect-next performance/drop_in_bang@warning -- free! only frees
  free!(xs)
