# litprobe: what the shading of a known fragment actually evaluates to.
#
# The rendered frame disagrees with the reference on the near carriage and the
# ballast beside the camera, and the disagreement is far too large to be a
# rounding difference -- so it is not read off the image, it is read off the
# fragment shader: the window lights are printed as positions, and the window
# term and the whole shaded colour are printed for fragments whose world
# position, normal and material are chosen by hand.
#
# The reference's own arithmetic is reproduced beside these numbers in Python,
# so a fragment whose two values disagree names the broken term.
#
# The fragment arrives as a parameter rather than as a let: a constructor call
# is not an inferable let right-hand side in a pure def, and an annotated one
# does not parse there either.
import Base
import ../../src/rt.bend as Rt
import ../../src/ride.bend as Ride
import ../../src/shade.bend as Shade


def Main.p3s(p: Rt.P3) -> String:
  Rt.P3{a, b, c} = p
  F32.show(a) ++ " " ++ F32.show(b) ++ " " ++ F32.show(c)


def Main.rgbs(c: Shade.RGB) -> String:
  Shade.RGB{r, g, b} = c
  F32.show(r) ++ " " ++ F32.show(g) ++ " " ++ F32.show(b)


def Main.ws.go(ws: List<&2, Rt.P3>, +i: U32, +acc: String) -> String:
  match ws:
    case []:
      acc
    case w <> rest:
      Main.ws.go(rest, U32.add(i, 1),
        acc ++ "  light" ++ U32.show(i) ++ " " ++ Main.p3s(w) ++ "\n")


def Main.ws.show(ws: List<&2, Rt.P3>) -> String:
  Main.ws.go(ws, 0, "")


# One fragment: the window term alone, then the whole shaded colour.
def Main.probe(label: String, +f: Rt.Frag, +cam: Rt.VCam, +lts: Shade.Lights,
  +head: Bool, ws: List<&2, Rt.P3>) -> String:
  +w = Shade.Light.win.go(f, ws, Shade.RGB{0.0, 0.0, 0.0})
  +c = Shade.Sh.v(f, cam, lts, head)
  label ++ " win=[" ++ Main.rgbs(w) ++ "] col=[" ++ Main.rgbs(c) ++ "]\n"


def Main.go(+cam: Rt.VCam, +lts: Shade.Lights, +head: Bool) -> String:
  Shade.Lights{hx, hy, hz, hdx, hdy, hdz, ws} = lts
  +hd = "head pos " ++ F32.show(hx) ++ " " ++ F32.show(hy) ++ " "
    ++ F32.show(hz) ++ " dir " ++ F32.show(hdx) ++ " " ++ F32.show(hdy) ++ " "
    ++ F32.show(hdz) ++ "\n"
  # beside the camera: ballast, carriage wall, window pane.  The track there
  # runs along +z and the camera sits at -x of it, so a camera-side wall's
  # normal is the -x direction (written 0-x: a bare negative literal is not a
  # term).
  +a = Main.probe("ballast  ",
    Rt.Frag{31.6, 3.2, 110.0, 0.0, 1.0, 0.0, 0.12, 0.13, 0.14, 0.0, 1.0}, cam,
    lts, head, ws)
  +b = Main.probe("wall     ",
    Rt.Frag{33.15, 5.35, 110.0, (0.0 - 1.0 : F32), 0.0, 0.0, 0.12, 0.20, 0.22,
      0.0, 1.0}, cam, lts, head, ws)
  +c = Main.probe("window   ",
    Rt.Frag{33.22, 5.35, 110.0, (0.0 - 1.0 : F32), 0.0, 0.0, 0.94, 0.62, 0.29,
      0.62, 1.0}, cam, lts, head, ws)
  # the same wall 26 m ahead, where the reference is warm and mine is dark
  +d = Main.probe("wall+26  ",
    Rt.Frag{35.0, 5.35, 136.0, (0.0 - 1.0 : F32), 0.0, 0.0, 0.12, 0.20, 0.22,
      0.0, 1.0}, cam, lts, head, ws)
  +e = Main.probe("win+26   ",
    Rt.Frag{35.07, 5.35, 136.0, (0.0 - 1.0 : F32), 0.0, 0.0, 0.94, 0.62, 0.29,
      0.62, 1.0}, cam, lts, head, ws)
  hd ++ Main.ws.show(ws) ++ a ++ b ++ c ++ d ++ e


def Main.run() -> IO(Unit):
  do IO<Unit>:
    IO.print(Main.go(Rt.VCam.ride(512, 512, 110.0, 4.6, 3.05, 0.0,
      (0.0 - 0.02 : F32)), Ride.Ride.lights(110.0), True{}))


def main() -> IO(Unit):
  Main.run()
