import Base

def f(n: Nat, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+p:
      # bend-lint: expect-next performance/append_in_loop@warning -- ++ copies acc each step
      f(p, acc ++ "x")
