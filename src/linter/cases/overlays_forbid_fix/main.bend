import Base

def say(m: IO(Unit)) -> IO(U32):
  do IO<U32>:
    m
    n : U32 <- IO.pure(U32, 3)
    return n

def both(-A: Type, -B: Type) -> Type:
  A & B

def twice(+k: U32) -> U32:
  (k * k : U32)
