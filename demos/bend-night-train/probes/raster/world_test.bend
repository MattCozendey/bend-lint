# Probe: World.ground and World.track build the grids the reference shaders
# imply.  Counts catch a dropped or duplicated cell (23040 ground, 3360 track);
# the x-sum of every ground vertex catches a wrong index, because buildGrid's
# a/b/c/d order picks different grid coordinates, and a wrong vertex is a
# different x.
import Base
import ../../src/geo.bend as Geo
import ../../src/world.bend as World


def M.wx(v: Geo.WVtx) -> F32:
  Geo.WVtx{x, y, z, nx, ny, nz, cr, cg, cb, e} = v
  x


def M.sum(xs: List<&2, Geo.WTri>, +acc: F32) -> F32:
  match xs:
    case []:
      acc
    case t <> rest:
      Geo.WTri{+a, +b, +c} = t
      M.sum(rest, (acc + M.wx(a) + M.wx(b) + M.wx(c) : F32))


def main() -> IO(Unit):
  do IO<Unit>:
    +ground : List<&2, Geo.WTri> = World.World.ground(0.0, [])
    +track : List<&2, Geo.WTri> = World.World.track(0.0, [])
    IO.print("ground triangles " ++ Nat.show(List.length(&2, Geo.WTri, ground)) ++ "\n")
    IO.print("track triangles " ++ Nat.show(List.length(&2, Geo.WTri, track)) ++ "\n")
    IO.print("ground x-sum " ++ F32.show(M.sum(ground, 0.0)) ++ "\n")
