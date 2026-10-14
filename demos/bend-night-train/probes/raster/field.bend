# Expected to be rejected: a field cannot be projected off a parameter with dot
# syntax in Bend 2.  Kept for the error message quoted in docs/language-notes.md.
import Base

type P is Data:
  P{a: F32, b: F32}


def P.use(p: P) -> F32:
  (p.a + p.b : F32)


def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(F32.show(P.use(P{1.0, 2.0})) ++ "\n")
