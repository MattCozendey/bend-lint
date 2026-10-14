# Probe: the Bend syntax the rasteriser leans on.  Written before the real
# files so a surprise costs one line instead of a thousand: negative F32
# literals, list literals of constructors, `<>` on lists, List.concat, and a
# match on a list parameter.
import Base

type P is Data:
  P{x: F32, y: F32}


def P.at(+x: F32, +y: F32) -> P:
  P{x, y}


def P.x(p: P) -> F32:
  P{x, y} = p
  x


def P.neg() -> P:
  P.at((0.0 - 1.5 : F32), 0.25)


def P.quad(a: P, b: P, c: P, d: P) -> List<&2, P>:
  a <> [b, c, d]


def P.four() -> List<&2, P>:
  P.quad(P.at(1.0, 1.0), P.at(2.0, 2.0), P.at(3.0, 3.0), P.neg())


def P.two() -> List<&2, P>:
  List.concat(&2, P, [P.quad(P.at(1.0, 1.0), P.neg(), P.at(2.0, 2.0), P.at(3.0, 3.0)),
    P.quad(P.at(4.0, 4.0), P.at(5.0, 5.0), P.at(6.0, 6.0), P.at(7.0, 7.0))])


def P.sum(xs: List<&2, P>, +acc: F32) -> F32:
  match xs:
    case []:
      acc
    case p <> rest:
      P{x, y} = p
      P.sum(rest, (acc + x + y : F32))


def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(F32.show(P.sum(P.four(), 0.0)) ++ "\n")
    IO.print(F32.show(P.sum(P.two(), 0.0)) ++ "\n")
    IO.print(F32.show(P.x(P.neg())) ++ "\n")
