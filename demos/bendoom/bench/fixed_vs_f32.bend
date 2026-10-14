# A measurement, not a test: the inner loop a wall renderer runs per
# screen column, once in emulated 16.16 fixed point and once in F32, over
# the same iteration count, each summing a checksum. Build both as native
# binaries and time them:
#
#   bend bench/fixed_vs_f32.bend -o fixed_vs_f32
#   BENCH=fixed ./fixed_vs_f32; BENCH=f32 ./fixed_vs_f32
#
# A column: from a start angle, the distance to a wall at 512 units is
# scaled by the cosine of the view angle and the column's texture step
# is the inverse of that scale; a frame sums the steps of 640 columns,
# and the checksum sums the frames' sums in sixteenths.
import Base
import ../src/fixed.bend as F
import ../src/angle.bend as A
import ../src/vec.bend as V
import ../src/tables.bend as T

def Bench.frames() -> U32:
  20000

# Fixed: 640 columns a frame.
def Bench.fixed.col(n: Nat, +sine: V.Vec, +angle: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+m:
      +cos = A.Angle.cos(sine, A.Angle.fine(angle))
      +scale = F.Fixed.mul(33554432, F.Fixed.max(cos, 1024))
      Bench.fixed.col(m, sine, (angle + 1048576 : U32),
        (acc + F.Fixed.div(65536, F.Fixed.max(scale, 1024)) : U32))

def Bench.fixed.go(n: Nat, +sine: V.Vec, +angle: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+m:
      Bench.fixed.go(m, sine, (angle + 3145728 : U32),
        (acc + (Bench.fixed.col(U32.to_nat(640), sine, angle, 0) >> 12n) : U32))

def Bench.fixed() -> U32:
  Bench.fixed.go(U32.to_nat(Bench.frames()), V.Vec.of_list(T.Tables.finesine(), 10240),
    2415919104, 0)

# F32: the same loop with a float cosine.
def Bench.f32.col(n: Nat, +angle: F32, +acc: F32) -> F32:
  match n:
    case 0n:
      acc
    case 1n+m:
      +cos = F32.max(F32.cos(angle), 0.015625)
      +scale = F32.mul(512.0, cos)
      Bench.f32.col(m, F32.add(angle, 0.00153398), F32.add(acc, F32.div(1.0, scale)))

def Bench.f32.go(n: Nat, +angle: F32, +acc: F32) -> F32:
  match n:
    case 0n:
      acc
    case 1n+m:
      Bench.f32.go(m, F32.add(angle, 0.0046019),
        F32.add(acc, F32.floor(F32.mul(16.0, Bench.f32.col(U32.to_nat(640), angle, 0.0)))))

def Bench.f32() -> F32:
  Bench.f32.go(U32.to_nat(Bench.frames()), 3.5342917, 0.0)

def Bench.run(f32: Bool) -> IO(Unit):
  match f32:
    case True{}:
      IO.print("f32 " ++ F32.show(Bench.f32()))
    case False{}:
      IO.print("fixed " ++ U32.show(Bench.fixed()))

def main() -> IO(Unit):
  do IO<Unit>:
    which : String <- IO.try(String, IO.get_env("BENCH"))
    Bench.run(String.eq(which, "f32"))
