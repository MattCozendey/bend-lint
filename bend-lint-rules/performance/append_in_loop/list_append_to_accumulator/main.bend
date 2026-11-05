import Base

def f(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      # bend-lint: expect-next performance/append_in_loop@warning -- List.append copies acc each step
      f(p, List.append(&2, U32, acc, [1]))
