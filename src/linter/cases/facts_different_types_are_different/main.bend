import Base

def size(s: String, n: U32) -> U32:
  (U32.from_nat(String.length(s)) + n : U32)
