import Base

def deep(n: Nat) -> U32:
  match n:
    case 0n:
      0
    case 1n+p:
      (deep(p) + 1 : U32)
