# Checks the carriage meshes: roof 48, wheel 56, the four carMesh variants
# (low thousands, under the demo's 65535-vertex cap), the 15-carriage placed
# total at s=110, and the z-sum of one placed carriage -- a broken model matrix
# shows up there because the local mesh's z sums near zero.
import Base
import ../../src/geo.bend as Geo
import ../../src/carriage.bend as Carriage


def Main.ng(xs: List<&2, Geo.Geo>) -> Nat:
  List.length(&2, Geo.Geo, xs)


def Main.nw(xs: List<&2, Geo.WTri>) -> Nat:
  List.length(&2, Geo.WTri, xs)


def Main.zof(v: Geo.WVtx) -> F32:
  Geo.WVtx{+x, +y, +z, +nx, +ny, +nz, +cr, +cg, +cb, +e} = v
  z


def Main.zsum(xs: List<&2, Geo.WTri>, +acc: F32) -> F32:
  match xs:
    case []:
      acc
    case t <> rest:
      Geo.WTri{+a, +b, +c} = t
      Main.zsum(rest, (acc + Main.zof(a) + Main.zof(b) + Main.zof(c) : F32))


def Main.show(+name: String, +n: Nat) -> String:
  name ++ " " ++ Nat.show(n)


# The 15-carriage total.  Counting the single concatenated Carriage.all list
# would walk a ~51k-cons spine in one recursion and overflow the interpreter
# stack, so the same triangles are counted per carriage and summed.  It is the
# identical set -- Carriage.emit is exactly what Carriage.all composes.
def Main.count15(+n: Nat, +i: U32, +s: F32, +cars: Carriage.Cars, +acc: Nat)
  -> Nat:
  match n:
    case 0n:
      acc
    case 1n+k:
      +mesh = Carriage.Carriage.emit(i, s, cars, [])
      Main.count15(k, U32.add(i, 1), s, cars, Nat.add(acc, Main.nw(mesh)))


def main() -> IO(Unit):
  do IO<Unit>:
    +cars : Carriage.Cars = Carriage.Carriage.cars()
    +v0 : List<&2, Geo.WTri> = Carriage.Cars.mesh(cars, 0, 0n)
    +v1 : List<&2, Geo.WTri> = Carriage.Cars.mesh(cars, 0, 1n)
    +v2 : List<&2, Geo.WTri> = Carriage.Cars.mesh(cars, 0, 2n)
    +loco : List<&2, Geo.WTri> = Carriage.Cars.mesh(cars, 14, 0n)
    +one : List<&2, Geo.WTri> = Carriage.Carriage.emit(0, 110.0, cars, [])
    +fifteen : Nat = Main.count15(15n, 0, 110.0, cars, 0n)
    IO.print(Main.show("roof", Main.ng(Carriage.Carriage.roof())))
    IO.print(Main.show("wheel", Main.ng(Carriage.Carriage.wheel())))
    IO.print(Main.show("v0", Main.nw(v0)))
    IO.print(Main.show("v1", Main.nw(v1)))
    IO.print(Main.show("v2", Main.nw(v2)))
    IO.print(Main.show("loco", Main.nw(loco)))
    IO.print(Main.show("fifteen", fifteen))
    IO.print("zsum " ++ F32.show(Main.zsum(one, 0.0)) ++ "\n")
