# Probe: what does it cost to materialise an N-triangle list in Bend?
#
# The rasteriser's whole architecture hangs on this number.  If a 175k-triangle
# list (the reference demo's full scene, see docs/reference-demo-spec.md) can be
# built once per frame for a few milliseconds, the renderer can be a plain
# triangle pipeline: build, bin down the quadtree, rasterise.  If it costs
# hundreds of milliseconds, the geometry has to stay procedural inside the
# rasteriser instead.
#
# Two lists are built and folded to force evaluation: A of plain F32, B of
# triangles (3 vertices of 10 F32).  The difference per element is the cost of
# the record allocation the rasteriser would pay.
#
#   NT_N=<triangles> ./out/buildcost --threads 16
#   NT_N=<triangles> ./out/buildcost --gpu 4GB
import Base

type V is Data:
  V{x: F32, y: F32, z: F32, nx: F32, ny: F32, nz: F32, cr: F32, cg: F32, cb: F32,
    e: F32}


type T is Data:
  T{a: V, b: V, c: V}


def V.at(+i: U32) -> V:
  +f = U32.to_f32(i)
  V{f, (f + 1.0 : F32), (f + 2.0 : F32), 0.0, 1.0, 0.0, 0.1, 0.2, 0.3, 0.0}


def V.sum(v: V) -> F32:
  V{+x, +y, +z, +nx, +ny, +nz, +cr, +cg, +cb, +e} = v
  (x + y + z + nx + ny + nz + cr + cg + cb + e : F32)


def T.at(+i: U32) -> T:
  T{V.at(i), V.at(U32.add(i, 1)), V.at(U32.add(i, 2))}


# ---- list B: triangles -------------------------------------------------
def tri.go(+n: Nat, +i: U32, +acc: List<&2, T>) -> List<&2, T>:
  match n:
    case 0n:
      acc
    case 1n+p:
      tri.go(p, U32.add(i, 1), T.at(i) <> acc)


def tri.sum(ts: List<&2, T>, +acc: F32) -> F32:
  match ts:
    case []:
      acc
    case t <> rest:
      T{a, b, c} = t
      tri.sum(rest, (acc + V.sum(a) + V.sum(b) + V.sum(c) : F32))


# ---- list A: plain scalars, the fold-only baseline ---------------------
def one.go(+n: Nat, +i: U32, +acc: List<&2, F32>) -> List<&2, F32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      one.go(p, U32.add(i, 1), (U32.to_f32(i) : F32) <> acc)


def one.sum(xs: List<&2, F32>, +acc: F32) -> F32:
  match xs:
    case []:
      acc
    case x <> rest:
      one.sum(rest, (acc + x : F32))


def Main.n.maybe(m: Maybe<&2, U32>) -> IO(U32):
  match m:
    case None{}:
      IO.pure(U32, 175000)
    case Some{v}:
      IO.pure(U32, v)


def Main.n.pick(r: Result<&1, &1, U32 & String, String>) -> IO(U32):
  match r:
    case Fail{e}:
      IO.pure(U32, 175000)
    case Done{value}:
      Main.n.maybe(U32.read(value))


def Main.n() -> IO(U32):
  do IO<U32>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env("NT_N")
    Main.n.pick(r)


def main() -> IO(Unit):
  do IO<Unit>:
    n : U32 <- Main.n()
    +nn : Nat = U32.to_nat(n)
    IO.print("n=" ++ Nat.show(nn) ++ "\n")
    IO.print("A=" ++ F32.show(one.sum(one.go(nn, 0, []), 0.0)) ++ "\n")
    IO.print("B=" ++ F32.show(tri.sum(tri.go(nn, 0, []), 0.0)) ++ "\n")
