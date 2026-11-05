import Base

def f(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      List.append(&2, U32, acc, [1])
    case 1n+p:
      f(p, acc)
