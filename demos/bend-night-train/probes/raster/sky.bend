# sky: does the moon disc survive Sky.rgb?
#
# The reference draws a solid moon disc with `md > 0.99965` (its own sky shader,
# normalize(far/w - uCam) then dot with uMoonDir).  The projected moon centre
# lands on pixel (73.5, 73.5) of a 512x512 frozen frame in *both* renders, but
# the reference is 200+ there and this one is 8 -- so the direction is right and
# the disc term is not.  This evaluates Sky.rgb at the moon's own axis, at the
# pixel the moon projects to, and reports the two dot products.
#
# The whole report is built by one pure def: a do block wants a bind before a
# let, so the arithmetic does not live there.
import Base
import ../../src/rt.bend as Rt
import ../../src/shade.bend as Shade


def Main.s(c: Shade.RGB) -> String:
  Shade.RGB{r, g, b} = c
  F32.show(r) ++ " " ++ F32.show(g) ++ " " ++ F32.show(b)


# the ray arrives as a parameter: a match cannot scrutinise a computed value
def Main.ray.rep(d: Rt.P3) -> String:
  Rt.P3{+d1, +d2, +d3} = d
  +mdot = (Shade.Moon.x() * 0.421075 + Shade.Moon.y() * 0.360922
    + Shade.Moon.z() * 0.832125 : F32)
  +rdot = (Shade.Moon.x() * d1 + Shade.Moon.y() * d2 + Shade.Moon.z() * d3
    : F32)
  +rlen = F32.sqrt((d1 * d1 + d2 * d2 + d3 * d3 : F32))
  "moon axis  " ++ Main.s(Shade.Sky.rgb(
      Rt.P3{0.421075, 0.360922, 0.832125}, 0.0)) ++ "\n"
    ++ "pixel 73.5 " ++ Main.s(Shade.Sky.rgb(Rt.P3{d1, d2, d3}, 0.0)) ++ "\n"
    ++ "moon dot   " ++ F32.show(mdot) ++ "\n"
    ++ "ray dot    " ++ F32.show(rdot) ++ "\n"
    ++ "ray len    " ++ F32.show(rlen) ++ "\n"


def Main.report() -> String:
  +cam = Rt.VCam.ride(512, 512, 110.0, 4.6, 3.05, 0.0, (0.0 - 0.02 : F32))
  Main.ray.rep(Rt.VCam.ray(cam, 73.5, 73.5))


def Main.run() -> IO(Unit):
  do IO<Unit>:
    IO.print(Main.report())


def main() -> IO(Unit):
  Main.run()
