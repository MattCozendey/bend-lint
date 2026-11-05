import Base

def f(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      f(p, List.append(&2, U32, [1], acc))
