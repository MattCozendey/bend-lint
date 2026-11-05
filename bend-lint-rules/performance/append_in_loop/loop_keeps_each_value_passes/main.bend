import Base

def f(n: Nat, +acc: String, out: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n:
      out
    case 1n+p:
      f(p, acc ++ "x", (acc ++ "x") <> out)
