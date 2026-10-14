# materials: how bright a material each mesh group actually carries.
#
# The render's left side is a saturated slab where the reference has a dark
# carriage, and shading a hand-made fragment there returns the reference's own
# values -- so a fragment is arriving with a material the reference never hands
# the shader.  This walks the three mesh groups and prints the largest emissive,
# the brightest flat colour and the counts of anything unusual in each.  A group
# whose maximum is small cannot be the slab.
#
# There is no field access in Bend, so the accumulator is destructured to read
# it and rebuilt to carry it on.
import Base
import ../../src/geo.bend as Geo
import ../../src/world.bend as World
import ../../src/inst.bend as Inst
import ../../src/carriage.bend as Carriage


type Max is Data:
  Max{em: F32, ecr: F32, ecg: F32, ecb: F32, ne: Nat, nc: Nat}


def Max.zero() -> Max:
  Max{0.0, 0.0, 0.0, 0.0, 0n, 0n}


def Max.vtx(+m: Max, v: Geo.WVtx) -> Max:
  Max{em, ecr, ecg, ecb, ne, nc} = m
  Geo.WVtx{x, y, z, nx, ny, nz, +cr, cg, cb, +e} = v
  +se = Bool.pick(Nat, F32.is_gt(e, 0.1), 1n, 0n)
  +sc = Bool.pick(Nat, F32.is_gt(cr, 0.5), 1n, 0n)
  Max{F32.max(em, e), F32.max(ecr, cr), F32.max(ecg, cg), F32.max(ecb, cb),
    Nat.add(ne, se), Nat.add(nc, sc)}


def Max.tri(+m: Max, t: Geo.WTri) -> Max:
  Geo.WTri{a, b, c} = t
  Max.vtx(Max.vtx(Max.vtx(m, a), b), c)


def Max.go(ts: List<&2, Geo.WTri>, +m: Max) -> Max:
  match ts:
    case []:
      m
    case t <> rest:
      Max.go(rest, Max.tri(m, t))


def Max.show(label: String, +m: Max, +n: Nat) -> String:
  Max{em, ecr, ecg, ecb, ne, nc} = m
  label ++ " tris=" ++ Nat.show(n) ++ " maxE=" ++ F32.show(em) ++ " maxC=["
    ++ F32.show(ecr) ++ " " ++ F32.show(ecg) ++ " " ++ F32.show(ecb)
    ++ "] nE+.1=" ++ Nat.show(ne) ++ " nCr+.5=" ++ Nat.show(nc) ++ "\n"


def Main.count(ts: List<&2, Geo.WTri>, +n: Nat) -> Nat:
  match ts:
    case []:
      n
    case t <> rest:
      Main.count(rest, Nat.add(n, 1n))


def Main.group(label: String, +ts: List<&2, Geo.WTri>) -> String:
  Max.show(label, Max.go(ts, Max.zero()), Main.count(ts, 0n))


def Main.run() -> IO(Unit):
  do IO<Unit>:
    +s : F32 = 110.0
    +w : List<&2, Geo.WTri> = World.World.emit(s, [])
    +i : List<&2, Geo.WTri> = Inst.Inst.emit(s, [])
    +c : List<&2, Geo.WTri> = Carriage.Carriage.all(s, Carriage.Carriage.cars(),
      [])
    IO.print(Main.group("world  ", w) ++ Main.group("inst   ", i)
      ++ Main.group("carriage", c))


def main() -> IO(Unit):
  Main.run()
