# dump: write the placed carriage triangles out, one per line.
#
# Something in this render covers the moon (pixel 73,73 of a 512x512 frozen
# frame) and in the reference it does not.  The sky alone draws the moon in both
# (stage "nothing" and "world"/"inst" all show it at 213,220,209), so the
# carriage is what hides it.  Reasoning about the mesh by eye has not settled
# which part, so the mesh itself is written out and intersected in Python:
# a hit names the triangle, its colour and its position.
#
#   ax ay az bx by bz cx cy cz cr cg cb e nx ny nz
import Base
import ../../src/geo.bend as Geo
import ../../src/carriage.bend as Carriage


def Main.line(t: Geo.WTri) -> String:
  Geo.WTri{a, b, c} = t
  Geo.WVtx{ax, ay, az, anx, any_, anz, +ar, +ag, +ab, +ae} = a
  Geo.WVtx{bx, by, bz, nx1, ny1, nz1, cr1, cg1, cb1, e1} = b
  Geo.WVtx{cx, cy, cz, nx2, ny2, nz2, cr2, cg2, cb2, e2} = c
  F32.show(ax) ++ " " ++ F32.show(ay) ++ " " ++ F32.show(az) ++ " "
    ++ F32.show(bx) ++ " " ++ F32.show(by) ++ " " ++ F32.show(bz) ++ " "
    ++ F32.show(cx) ++ " " ++ F32.show(cy) ++ " " ++ F32.show(cz) ++ " "
    ++ F32.show(ar) ++ " " ++ F32.show(ag) ++ " " ++ F32.show(ab) ++ " "
    ++ F32.show(ae) ++ " " ++ F32.show(anx) ++ " " ++ F32.show(any_) ++ " "
    ++ F32.show(anz) ++ "\n"


def Main.go(ts: List<&2, Geo.WTri>, +acc: String) -> String:
  match ts:
    case []:
      acc
    case t <> rest:
      Main.go(rest, acc ++ Main.line(t))


def Main.run() -> IO(Unit):
  do IO<Unit>:
    IO.print(Main.go(Carriage.Carriage.all(110.0, Carriage.Carriage.cars(), []),
      ""))


def main() -> IO(Unit):
  Main.run()
