# carbox: the local bounding box of a carriage mesh.
#
# The carriage covers the moon in this render and does not in the reference, so
# the mesh reaches somewhere the reference's does not.  The reference builds a
# carriage from a body box (y 1.1..4.1), an arch roof at y 4.1 scaled 1.3, an
# underframe and the window band at |x| 1.45..1.6, over z +-12.06; the box here
# says which of those a port has overshot.
import Base
import ../../src/geo.bend as Geo
import ../../src/carriage.bend as Carriage


type Box is Data:
  Box{x0: F32, x1: F32, y0: F32, y1: F32, z0: F32, z1: F32}


def Box.zero() -> Box:
  Box{1.0e9, (0.0 - 1.0e9 : F32), 1.0e9, (0.0 - 1.0e9 : F32), 1.0e9,
    (0.0 - 1.0e9 : F32)}


def Box.v(+b: Box, v: Geo.WVtx) -> Box:
  Box{x0, x1, y0, y1, z0, z1} = b
  Geo.WVtx{+x, +y, +z, nx, ny, nz, cr, cg, cb, e} = v
  Box{F32.min(x0, x), F32.max(x1, x), F32.min(y0, y), F32.max(y1, y),
    F32.min(z0, z), F32.max(z1, z)}


def Box.t(+b: Box, t: Geo.WTri) -> Box:
  Geo.WTri{a, c, d} = t
  Box.v(Box.v(Box.v(b, a), c), d)


def Box.go(ts: List<&2, Geo.WTri>, +b: Box) -> Box:
  match ts:
    case []:
      b
    case t <> rest:
      Box.go(rest, Box.t(b, t))


def Main.show(label: String, +b: Box) -> String:
  Box{x0, x1, y0, y1, z0, z1} = b
  label ++ " x[" ++ F32.show(x0) ++ " " ++ F32.show(x1) ++ "] y["
    ++ F32.show(y0) ++ " " ++ F32.show(y1) ++ "] z[" ++ F32.show(z0) ++ " "
    ++ F32.show(z1) ++ "]\n"


def Main.run() -> IO(Unit):
  do IO<Unit>:
    IO.print(Main.show("v0   ", Box.go(Carriage.Carriage.variant(0n, False{}),
      Box.zero())))
    IO.print(Main.show("loco ", Box.go(Carriage.Carriage.variant(0n, True{}),
      Box.zero())))


def main() -> IO(Unit):
  Main.run()
