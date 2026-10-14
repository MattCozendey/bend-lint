# inst_test: every instanced kind at one camera s, and the three checks the
# port is accepted on: the triangle total, the emissive triangle count (the
# lit windows of kind 10) and a y-coordinate checksum a mis-wired kind would
# move.
#
# The reference draws fixed instance counts regardless of uS
# (620/30/1000/1000/60/300/1600/35/35/35/35), so the total is constant.
#
# The total is 86790, not the 87000 the brief quotes for "villages 1680
# (35 x 4 kinds x 12)".  Kind 9 is the roof and uses gableMesh, which is 6
# triangles, not 12 (reference lines 780-791: six tris in the list, and
# `kind===9?gableVao` at 1239).  The villages therefore contribute
# 35*(12+6+12+12) = 1470 and the soup 86790.  Everything else in the brief's
# per-kind table matches exactly.
import Base
import ../../src/inst.bend as Props
import ../../src/geo.bend as Geo


# List.length is non-tail and overflows the runtime stack on a 50k-element
# list, so the total is folded here instead.
def Main.tris(xs: List<&2, Geo.WTri>, +acc: Nat) -> Nat:
  match xs:
    case []:
      acc
    case h <> t:
      Main.tris(t, Nat.add(acc, 1n))


# A field is only reachable by destructuring a parameter; these thin defs are
# that parameter for the folds below.
def Main.wy(v: Geo.WVtx) -> F32:
  Geo.WVtx{x, y, z, nx, ny, nz, cr, cg, cb, e} = v
  y


def Main.we(v: Geo.WVtx) -> F32:
  Geo.WVtx{x, y, z, nx, ny, nz, cr, cg, cb, e} = v
  e


def Main.if.nat(+c: Bool, +t: Nat, +f: Nat) -> Nat:
  match c:
    case True{}:
      t
    case False{}:
      f


def Main.sumy(ts: List<&2, Geo.WTri>, +acc: F32) -> F32:
  match ts:
    case []:
      acc
    case t <> rest:
      Geo.WTri{a, b, c} = t
      Main.sumy(rest, (acc + Main.wy(a) + Main.wy(b) + Main.wy(c) : F32))


def Main.em.count(ts: List<&2, Geo.WTri>, +acc: Nat) -> Nat:
  match ts:
    case []:
      acc
    case t <> rest:
      +e = Main.we(Geo.WTri.wa(t))
      Main.em.count(rest,
        Nat.add(acc, Main.if.nat(F32.is_gt(e, 0.5), 1n, 0n)))


def main() -> IO(Unit):
  do IO<Unit>:
    +ts : List<&2, Geo.WTri> = Props.Inst.emit(110.0, [])
    +n : Nat = Main.tris(ts, 0n)
    +em : Nat = Main.em.count(ts, 0n)
    +ys : F32 = Main.sumy(ts, 0.0)
    IO.print("total " ++ Nat.show(n) ++ "\n")
    IO.print("emissive " ++ Nat.show(em) ++ "\n")
    IO.print("ysum " ++ F32.show(ys) ++ "\n")
