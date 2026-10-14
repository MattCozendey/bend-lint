import Base

def parsed(v: Maybe<&2, U32>) -> IO(U32):
  match v:
    case None{}:
      IO.die(U32, 2, "Demo configuration must be an unsigned 32-bit integer.")
    case Some{x}:
      IO.pure(U32, x)

def found(v: Result<&1, &1, U32 & String, String>, fallback: U32) -> IO(U32):
  match v:
    case Fail{error}:
      IO.pure(U32, fallback)
    case Done{text}:
      parsed(U32.read(text))

def read(name: String, fallback: U32) -> IO(U32):
  do IO<U32>:
    v : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    found(v, fallback)
