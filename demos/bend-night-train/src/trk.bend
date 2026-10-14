# trk: the track curve and the terrain noise, exactly as the reference's
# GLSL_TRACK block defines them.
#
# The demo duplicates these formulas twice -- once in JavaScript for the camera
# and the consist, once inside a GLSL string for the geometry.  They are the
# same formulas; here there is one copy, and both the camera and the triangle
# soup call it.  The constants are written the way GLSL_TRACK writes them
# (${TRACK.a1.toFixed(3)} and friends), not as the JS product, so a
# last-bit difference cannot creep in between the two paths.
import Base

# ---- the centreline --------------------------------------------------
# trackX(s) = 58.000*sin(s*0.008400) + 13.000*sin(s*0.021500 + 1.300)

def Track.x(+s: F32) -> F32:
  (58.0 * F32.sin((s * 0.0084 : F32)) + 13.0 * F32.sin((s * 0.0215 + 1.3 : F32))
    : F32)


# trackY(s) = 3.400*sin(s*0.006250) + 1.600*sin(s*0.015625 + 0.700)

def Track.y(+s: F32) -> F32:
  (3.4 * F32.sin((s * 0.00625 : F32)) + 1.6 * F32.sin((s * 0.015625 + 0.7 : F32))
    : F32)


def Track.dx(+s: F32) -> F32:
  (58.0 * 0.0084 * F32.cos((s * 0.0084 : F32))
    + 13.0 * 0.0215 * F32.cos((s * 0.0215 + 1.3 : F32)) : F32)


def Track.yaw(+s: F32) -> F32:
  F32.atan2(Track.dx(s), 1.0)


# trackRoll: the consist leans into the curve, clamped to +-0.09 rad.  The 6 m
# half-span is inlined: a bare float literal is not an acceptable let RHS
# (`+h = 6.0` cannot be inferred), only an annotated expression is.
def Track.roll(+s: F32) -> F32:
  +curve = ((Track.dx((s + 6.0 : F32)) - Track.dx((s - 6.0 : F32)) : F32)
    / (2.0 * 6.0 : F32) : F32)
  F32.clamp((curve * 260.0 : F32), (0.0 - 0.09 : F32), 0.09)


# ---- smoothstep ------------------------------------------------------
def S.smooth(+a: F32, +b: F32, +x: F32) -> F32:
  +t = F32.clamp(((x - a : F32) / (b - a : F32) : F32), 0.0, 1.0)
  (t * t * (3.0 - 2.0 * t) : F32)


def S.mix(+a: F32, +b: F32, +t: F32) -> F32:
  (a + (b - a) * t : F32)


def S.fract(+x: F32) -> F32:
  (x - F32.floor(x) : F32)


# `match` only scrutinises a parameter, so the computed comparison is handed
# to a helper rather than matched in place.
def S.sign.b(b: Bool) -> F32:
  match b:
    case True{}:
      1.0
    case False{}:
      (0.0 - 1.0 : F32)


def S.sign(+x: F32) -> F32:
  S.sign.b(F32.is_ge(x, 0.0))


# ---- the noise the geometry uses -------------------------------------
# GLSL hash21, not the JavaScript one: the trees and the ground are built in
# the vertex shader and hash with this.
def H.h21(+px: F32, +pz: F32) -> F32:
  +ax = S.fract((px * 123.34 : F32))
  +az = S.fract((pz * 345.45 : F32))
  +d = (ax * (ax + 34.345) + az * (az + 34.345) : F32)
  S.fract(((ax + d : F32) * (az + d : F32) : F32))


def H.vnoise(+px: F32, +pz: F32) -> F32:
  +ix = F32.floor(px)
  +iz = F32.floor(pz)
  +fx0 = S.fract(px)
  +fz0 = S.fract(pz)
  +fx = (fx0 * fx0 * (3.0 - 2.0 * fx0) : F32)
  +fz = (fz0 * fz0 * (3.0 - 2.0 * fz0) : F32)
  +a = H.h21(ix, iz)
  +b = H.h21((ix + 1.0 : F32), iz)
  +c = H.h21(ix, (iz + 1.0 : F32))
  +d = H.h21((ix + 1.0 : F32), (iz + 1.0 : F32))
  S.mix(S.mix(a, b, fx), S.mix(c, d, fx), fz)


# fbm: four octaves, amp 0.5 halving, p scaled by 2.03.
def H.fbm.go(+i: Nat, +px: F32, +pz: F32, +amp: F32, +acc: F32) -> F32:
  match i:
    case 0n:
      acc
    case 1n+k:
      H.fbm.go(k, (px * 2.03 : F32), (pz * 2.03 : F32), (amp * 0.5 : F32),
        (acc + amp * H.vnoise(px, pz) : F32))


def H.fbm(+px: F32, +pz: F32) -> F32:
  H.fbm.go(4n, px, pz, 0.5, 0.0)


# ---- terrain ---------------------------------------------------------
# Hills that flatten towards the embankment: `bed` within 9 m of the track
# centreline, full hills past 46 m.
def T.terrain(+x: F32, +z: F32) -> F32:
  +h1 = (H.fbm((x * 0.0042 : F32), (z * 0.0042 : F32)) - 0.5 : F32)
  +h2 = (H.fbm((x * 0.021 : F32), (z * 0.021 : F32)) - 0.5 : F32)
  +hills = (h1 * 34.0 + h2 * 4.5 : F32)
  +d = F32.abs((x - Track.x(z) : F32))
  +k = S.smooth(9.0, 46.0, d)
  +bed = (Track.y(z) - 0.9 : F32)
  S.mix(bed, (bed + hills : F32), k)
