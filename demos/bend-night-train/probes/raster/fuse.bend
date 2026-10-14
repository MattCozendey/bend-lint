# Expected to be rejected: a constructor argument with no annotation and an
# unbound type variable -- "an annotated term (cannot infer)".
import Base

type P is Data:
  P{a: F32, b: F32, c: F32, d: F32}


def P.sum(p: P) -> F32:
  P{+a, b, c, d} = p
  (a + b + c + d : F32)


def Main.mk(+x: F32) -> F32:
  P.sum(P{x, 2.0, 3.0, 4.0})


def Main.mk2(+x: F32, +y: F32) -> F32:
  +p = (P{x, 2.0, 3.0, 4.0} : P)
  (P.sum(p) + P.sum(p) : F32)


def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(F32.show(Main.mk(1.0)) ++ "\n")
    IO.print(F32.show(Main.mk2(1.0, 5.0)) ++ "\n")
