import Base

def build(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+m:
      build(m, 1 <> acc)

def then(-R: Type, xs: List<&2, U32>, k: List<&2, U32> -> U32 -> R) -> R:
  k(xs, 7)

def g(n: Nat, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+m:
      # bend-lint: expect-next performance/unused_result@information -- xs is never used
      xs = build(3n, [])
      g(m, acc)
