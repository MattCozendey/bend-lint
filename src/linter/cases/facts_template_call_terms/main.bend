import Base

def tid(~A: Data, x: A) -> A:
  x

def use(y: U32) -> U32:
  tid(~U32, y)
