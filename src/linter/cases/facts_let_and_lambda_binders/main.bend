import Base

def inc(+n: U32) -> U32:
  f : U32 -> U32 = z => (z + n : U32)
  f(n)
