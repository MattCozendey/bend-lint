# Expected to be rejected: only three of the five fields are named in the
# pattern.
import Base

type V is Data:
  V{a: F32, b: F32, c: F32, d: F32, e: F32}


# only three of the five fields named
def V.part(v: V) -> F32:
  V{+a, b, c} = v
  (a + b + c : F32)


# nested constructor fields
type W is Data:
  W{p: V, q: F32}


def W.use(w: W) -> F32:
  W{p, q} = w
  (V.part(p) + q : F32)


def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(F32.show(W.use(W{V{1.0, 2.0, 3.0, 4.0, 5.0}, 6.0})) ++ "\n")
