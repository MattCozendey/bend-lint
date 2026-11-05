import Base

def say(m: IO(Unit)) -> IO(U32):
  do IO<U32>:
    m
    n : U32 <- IO.pure(U32, 3)
    return n
