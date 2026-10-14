# hitprobe: which projected triangles claim one pixel of the sky.
#
# Car 5 alone covers the moon's pixel while cars 4 and 6 do not, and car 5 is
# the one carriage whose 24 m hull spans the camera's own z.  Its wall and roof
# therefore cross the near plane, and the clip that cuts them puts a vertex at
# w = near: for a wall 2.8 m to the side that projects to |x| ~ k*2.8/0.15,
# tens of thousands of pixels wide.  This asks the rasteriser's own test
# whether such a triangle claims pixel (73.5, 73.5), and with what depth key.
#
# Prints: how many projected triangles contain the pixel, the largest screen
# coordinate among those that do, and the depth key and vertices of the last
# one to claim it.
import Base
import ../../src/geo.bend as Geo
import ../../src/rt.bend as Rt
import ../../src/raster.bend as Raster
import ../../src/carriage.bend as Carriage
import ../../src/ride.bend as Ride


type Win is Data:
  Win{n: Nat, m: F32, iw: F32, x0: F32, y0: F32, x1: F32, y1: F32, x2: F32,
    y2: F32}


def Win.zero() -> Win:
  Win{0n, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}


def Win.big(+x: F32, y: F32) -> F32:
  F32.max(F32.abs(x), F32.abs(y))


# The hit arrives as a parameter: a match inspects a parameter, not a computed
# value.
def Win.take(+w: Win, h: Raster.Hit, +ax: F32, +ay: F32, +bx: F32, +by: F32,
  +cx: F32, +cy: F32) -> Win:
  Win{n, m, iw, x0, y0, x1, y1, x2, y2} = w
  match h:
    case Raster.Miss{}:
      Win{n, m, iw, x0, y0, x1, y1, x2, y2}
    case Raster.Hit{q1, q2, q3, hiw}:
      Win{Nat.add(n, 1n),
        F32.max(m, F32.max(F32.max(Win.big(ax, ay), Win.big(bx, by)),
          Win.big(cx, cy))),
        hiw, ax, ay, bx, by, cx, cy}


def Win.go(ts: List<&2, Rt.Tri>, +w: Win, +fx: F32, +fy: F32) -> Win:
  match ts:
    case []:
      w
    case t <> rest:
      Rt.Tri{a, b, c, bx0, by0, bx1, by1} = t
      Rt.Vtx{at1, +ax, +ay, aiw} = a
      Rt.Vtx{at2, +bx, +by, biw} = b
      Rt.Vtx{at3, +cx, +cy, ciw} = c
      Win.take(Win.go(rest, w, fx, fy),
        Raster.Tri.hit(fx, fy, ax, ay, aiw, bx, by, biw, cx, cy, ciw), ax, ay, bx,
        by, cx, cy)


# the winning record is read out of a parameter: there is no field access, and a
# let-bound value cannot be destructured
def Win.show(car: U32, +w: Win) -> String:
  Win{n, m, iw, x0, y0, x1, y1, x2, y2} = w
  "car " ++ U32.show(car) ++ " claims=" ++ Nat.show(n) ++ " maxCoord="
    ++ F32.show(m) ++ " iw=" ++ F32.show(iw) ++ " verts=[" ++ F32.show(x0) ++ " "
    ++ F32.show(y0) ++ "][" ++ F32.show(x1) ++ " " ++ F32.show(y1) ++ "]["
    ++ F32.show(x2) ++ " " ++ F32.show(y2) ++ "]\n"


def Main.report(+car: U32) -> String:
  +cam = Rt.VCam.ride(512, 512, 110.0, 4.6, 3.05, 0.0, (0.0 - 0.02 : F32))
  +ts = Rt.Tri.emit(
    Carriage.Carriage.emit(car, 110.0, Carriage.Carriage.cars(), []), cam)
  Win.show(car, Win.go(ts, Win.zero(), 73.5, 73.5))


# The two paths at the same pixel, through the renderer's own entry points:
# the sky alone, and the full pixel over car 5's triangle list.  The Env is a
# constructor, which is not an inferable let right-hand side, so it is built at
# the call and read out of a parameter.
def Main.env.show(car: U32, +env: Raster.Env, +ts: List<&2, Rt.Tri>) -> String:
  "car " ++ U32.show(car) ++ " sky="
    ++ U32.show(Raster.Tile.px.sky(73.5, 73.5, [], env)) ++ " px="
    ++ U32.show(Raster.Tile.px(73, 73, ts, [], env)) ++ "\n"


def Main.px(+car: U32) -> String:
  +cam = Rt.VCam.ride(512, 512, 110.0, 4.6, 3.05, 0.0, (0.0 - 0.02 : F32))
  Main.env.show(car, Raster.Env{cam, Ride.Ride.lights(110.0), True{}, 0.0},
    Rt.Tri.emit(Carriage.Carriage.emit(car, 110.0, Carriage.Carriage.cars(), []),
      cam))


def Main.run() -> IO(Unit):
  do IO<Unit>:
    IO.print(Main.report(4) ++ Main.report(5) ++ Main.report(6) ++ Main.px(4)
      ++ Main.px(5) ++ Main.px(6))


def main() -> IO(Unit):
  Main.run()
