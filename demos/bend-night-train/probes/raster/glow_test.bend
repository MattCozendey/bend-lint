# Scratch harness for Ride.glows: builds the ride camera from the demo's own
# 1024x1024 settings, asks for one frame of glow sprites at s=110, t=0 with the
# headlight on, and prints the count and the first three sprites' cx, cy, r, a.
# Run with: tools/bend probes/raster/glow_test.bend
import Base
import ../../src/ride.bend as Ride
import ../../src/rt.bend as Rt


def Main.spr(s: Rt.Spr) -> String:
  Rt.Spr{cx, cy, r, iw, cr, cg, cb, a, kind} = s
  "cx=" ++ F32.show(cx) ++ " cy=" ++ F32.show(cy) ++ " r=" ++ F32.show(r)
    ++ " a=" ++ F32.show(a)


def Main.show3(xs: List<&2, Rt.Spr>, +acc: String) -> String:
  match xs:
    case []:
      acc
    case h <> rest:
      Main.show3(rest, acc ++ "  " ++ Main.spr(h) ++ "\n")


# Sprites whose centre is inside the 1024x1024 frame.  The list starts with
# car 0, which is behind the camera, so the first few carry the off-screen
# sentinel (cx = -100000) -- this is the count that says the pass actually
# lands on screen.
def Main.on(xs: List<&2, Rt.Spr>, +acc: Nat) -> Nat:
  match xs:
    case []:
      acc
    case h <> rest:
      Rt.Spr{+cx, cy, r, iw, cr, cg, cb, a, kind} = h
      Main.on(rest, Bool.pick(Nat,
        Bool.and(F32.is_ge(cx, 0.0), F32.is_le(cx, 1024.0)),
        Nat.add(acc, 1n), acc))


def main() -> IO(Unit):
  do IO<Unit>:
    +cam : Rt.VCam = Rt.VCam.ride(1024, 1024, 110.0, 4.6, 3.05, 0.0,
      (0.0 - 0.02 : F32))
    +gs : List<&2, Rt.Spr> = Ride.Ride.glows(cam, 110.0, 110.0, True{}, 0.0)
    IO.print("count " ++ Nat.show(List.length(&2, Rt.Spr, gs)))
    IO.print("on-screen " ++ Nat.show(Main.on(gs, 0n)))
    IO.print(Main.show3(List.take(&2, Rt.Spr, gs, 3n), ""))
