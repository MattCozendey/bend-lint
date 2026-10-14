# shade: the demo's fragment shader and its sky pass, in Bend.
#
# FS_COMMON is a handful of lines of GLSL; this is the same arithmetic with
# the same constants, in the same order.  It is the reason the rasteriser can
# skip the ray marcher: the field was only ever there to *find* the surface.
# Once a triangle has been rasterised the surface, its normal and its colour
# are already known, and the shading costs one pass over the pixel instead of
# eighty evaluations of an SDF.
#
# F32 is a `law` in Bend, so none of this is provable -- see docs/laws.md.
import Base
import ./geo.bend as Geo
import ./rt.bend as Rt
import ./trk.bend as Trk


type RGB is Data:
  RGB{r: F32, g: F32, b: F32}


# The demo's uniforms: ten warm window points, the headlight, the moon, the
# fog.  Built once per frame and handed down the quadtree.
type Lights is Data:
  Lights{hx: F32, hy: F32, hz: F32, hdx: F32, hdy: F32, hdz: F32,
    ws: List<&2, Rt.P3>}


def Moon.x() -> F32:
  0.421075


def Moon.y() -> F32:
  0.360922


def Moon.z() -> F32:
  0.832125


def Fog.r() -> F32:
  0.055


def Fog.g() -> F32:
  0.068


def Fog.b() -> F32:
  0.115


def Fog.density() -> F32:
  0.0026


# Bend has no field access, and the sky chain below reads each colour's three
# channels once, so the constructors it needs are here rather than a destructure
# at every step.
def Rgb.at(+r: F32, +g: F32, +b: F32) -> RGB:
  RGB{r, g, b}


def Rgb.mix(a: RGB, b: RGB, +t: F32) -> RGB:
  RGB{ar, ag, ab} = a
  RGB{br, bg, bb} = b
  RGB{Trk.S.mix(ar, br, t), Trk.S.mix(ag, bg, t), Trk.S.mix(ab, bb, t)}


def Rgb.toward(a: RGB, +tr: F32, +tg: F32, +tb: F32, +t: F32) -> RGB:
  RGB{ar, ag, ab} = a
  RGB{Trk.S.mix(ar, tr, t), Trk.S.mix(ag, tg, t), Trk.S.mix(ab, tb, t)}


# a + k*(kr,kg,kb) + j*(jr,jg,jb) -- the moon adds its disc and its halo at
# once, and the milky way is the one-term case.
def Rgb.add2(a: RGB, +kr: F32, +kg: F32, +kb: F32, +k: F32, +jr: F32, +jg: F32,
  +jb: F32, +j: F32) -> RGB:
  RGB{ar, ag, ab} = a
  RGB{(ar + kr * k + jr * j : F32), (ag + kg * k + jg * j : F32),
    (ab + kb * k + jb * j : F32)}


def Rgb.add(a: RGB, +kr: F32, +kg: F32, +kb: F32, +k: F32) -> RGB:
  Rgb.add2(a, kr, kg, kb, k, 0.0, 0.0, 0.0, 0.0)


# the filmic curve and the fog, so the shader's tail stays a chain of colours
def Rgb.tone(a: RGB) -> RGB:
  RGB{+qr, +qg, +qb} = a
  RGB{(qr / (1.0 + qr * 0.38 : F32) : F32), (qg / (1.0 + qg * 0.38 : F32) : F32),
    (qb / (1.0 + qb * 0.38 : F32) : F32)}


def Rgb.fog(a: RGB, +ff: F32) -> RGB:
  RGB{mr, mg, mb} = a
  RGB{Trk.S.mix(mr, Fog.r(), ff), Trk.S.mix(mg, Fog.g(), ff),
    Trk.S.mix(mb, Fog.b(), ff)}


# One window light's tint, a helper so the loop can pass the running colour
# to a parameter instead of matching on it inside the branch.
def Light.add(acc: RGB, +kk: F32) -> RGB:
  RGB{ar, ag, ab} = acc
  RGB{(ar + 1.00 * kk : F32), (ag + 0.70 * kk : F32), (ab + 0.36 * kk : F32)}


# Additive billboard tint: the same "arrive as a parameter" rule, so a
# sprite accumulates into the pixel's running colour without field access.
def Rgb.tint(acc: RGB, +cr: F32, +cg: F32, +cb: F32, +al: F32) -> RGB:
  RGB{ar, ag, ab} = acc
  RGB{(ar + cr * al : F32), (ag + cg * al : F32), (ab + cb * al : F32)}


# The window lights land on the lit colour, and the grain only bites on unlit,
# nearby surfaces.  `wl` is a computed colour, so it arrives as a parameter --
# a match inspects a parameter or a pattern-bound variable, never a computed
# value, and destructuring it at the call site would be rejected.
def Rgb.lit(+tr: F32, +tg: F32, +tb: F32, wl: RGB, +cr: F32, +cg: F32, +cb: F32,
  +e: F32, +gs: F32) -> RGB:
  RGB{wr, wg, wb} = wl
  RGB{(cr * (tr + wr) * gs + cr * e : F32), (cg * (tg + wg) * gs + cg * e : F32),
    (cb * (tb + wb) * gs + cb * e : F32)}

def Sh.safe(+x: F32) -> F32:
  F32.max(x, 0.000001)


# ---- hash31 / vnoise3 / fbm3 -----------------------------------------
# The sky shader's own noise, distinct from the geometry's hash21.

def Sk.hash(+px: F32, +py: F32, +pz: F32) -> F32:
  +ax = Trk.S.fract((px * 0.3183 + 0.71 : F32))
  +ay = Trk.S.fract((py * 0.3183 + 0.113 : F32))
  +az = Trk.S.fract((pz * 0.3183 + 0.419 : F32))
  +bx = (ax * 17.0 : F32)
  +by = (ay * 17.0 : F32)
  +bz = (az * 17.0 : F32)
  Trk.S.fract((bx * by * bz * (bx + by + bz) : F32))


def Sk.vnoise(+px: F32, +py: F32, +pz: F32) -> F32:
  +ix = F32.floor(px)
  +iy = F32.floor(py)
  +iz = F32.floor(pz)
  +fx0 = Trk.S.fract(px)
  +fy0 = Trk.S.fract(py)
  +fz0 = Trk.S.fract(pz)
  +fx = (fx0 * fx0 * (3.0 - 2.0 * fx0) : F32)
  +fy = (fy0 * fy0 * (3.0 - 2.0 * fy0) : F32)
  +fz = (fz0 * fz0 * (3.0 - 2.0 * fz0) : F32)
  +n00 = Trk.S.mix(Sk.hash(ix, iy, iz), Sk.hash((ix + 1.0 : F32), iy, iz), fx)
  +n10 = Trk.S.mix(Sk.hash(ix, (iy + 1.0 : F32), iz),
    Sk.hash((ix + 1.0 : F32), (iy + 1.0 : F32), iz), fx)
  +n01 = Trk.S.mix(Sk.hash(ix, iy, (iz + 1.0 : F32)),
    Sk.hash((ix + 1.0 : F32), iy, (iz + 1.0 : F32)), fx)
  +n11 = Trk.S.mix(Sk.hash(ix, (iy + 1.0 : F32), (iz + 1.0 : F32)),
    Sk.hash((ix + 1.0 : F32), (iy + 1.0 : F32), (iz + 1.0 : F32)), fx)
  Trk.S.mix(Trk.S.mix(n00, n10, fy), Trk.S.mix(n01, n11, fy), fz)


# cloud = sum of 4 octaves at amp 0.62, 0.3224, 0.1676, 0.0872 and scale 2.07
def Sk.fbm.go(+i: Nat, +px: F32, +py: F32, +pz: F32, +amp: F32, +acc: F32)
  -> F32:
  match i:
    case 0n:
      acc
    case 1n+k:
      Sk.fbm.go(k, (px * 2.07 : F32), (py * 2.07 : F32), (pz * 2.07 : F32),
        (amp * 0.52 : F32), (acc + amp * Sk.vnoise(px, py, pz) : F32))


def Sk.fbm(+px: F32, +py: F32, +pz: F32) -> F32:
  Sk.fbm.go(4n, px, py, pz, 0.62, 0.0)


# ---- the sky ---------------------------------------------------------
def Sk.high(b: Bool, +lo: RGB, +hi: RGB) -> RGB:
  match b:
    case True{}:
      hi
    case False{}:
      lo


def Sky.rgb(dir: Rt.P3, +t: F32) -> RGB:
  Rt.P3{+dx, +dy, +dz} = dir
  +h = F32.clamp(dy, (0.0 - 1.0 : F32), 1.0)
  +lo = Rgb.at(0.150, 0.135, 0.190)
  +md = Rgb.at(0.045, 0.061, 0.126)
  +hi = Rgb.at(0.014, 0.020, 0.052)
  +dn = Trk.S.smooth((0.0 - 0.05 : F32), 0.18, h)
  +up = Trk.S.smooth(0.18, 0.85, h)
  +c0 = Sk.high(F32.is_gt(h, 0.18), Rgb.mix(lo, md, dn), Rgb.mix(md, hi, up))
  # Milky Way: a wide band at 7/unit, four octaves of vnoise3.
  # the axis lives inline: a let whose right-hand side is a bare literal is
  # not inferable, and an annotated literal is not enough either -- only an
  # annotated expression is.  Same reason Track.roll inlines its 6 m.
  +band = (1.0 - F32.abs((dx * 0.621108 + dy * 0.420751 - dz * 0.661181 : F32))
    : F32)
  +core = Trk.S.smooth(0.80, 1.0, band)
  +cloud = Sk.fbm((dx * 7.0 : F32), (dy * 7.0 : F32), (dz * 7.0 : F32))
  +milky = (core * (0.25 + cloud * 0.95)
    * Trk.S.smooth((0.0 - 0.02 : F32), 0.22, h) : F32)
  +m1 = Rgb.add(c0, 0.100, 0.108, 0.150, milky)
  # the moon: a narrow disc, a wide halo, and a noisy limb
  +dot = (dx * Moon.x() + dy * Moon.y() + dz * Moon.z() : F32)
  +mdp = F32.max(dot, 0.0)
  +disc = (F32.pow(mdp, 420.0) * 0.32 : F32)
  +halo = (F32.pow(mdp, 14.0) * 0.30 : F32)
  +m2 = Rgb.add2(m1, 0.55, 0.62, 0.85, disc, 0.24, 0.29, 0.45, halo)
  +maria = Sk.vnoise((dx * 320.0 : F32), (dy * 320.0 : F32), (dz * 320.0 : F32))
  +e = (Rt.S.if1(F32.is_gt(dot, 0.99965), 1.0, 0.0)
    * Trk.S.smooth(0.99965, 0.99985, dot) : F32)
  +ma = (0.80 + maria * 0.20 : F32)
  +m3 = Rgb.toward(m2, (0.90 * ma : F32), (0.93 * ma : F32), (0.88 * ma : F32), e)
  # low cloud deck near the horizon, drifting slowly with time
  +cp = Sk.vnoise((dx * 5.0 + t * 0.0015 : F32), (dy * 5.0 : F32), (dz * 5.0 : F32))
  +cp2 = Sk.vnoise((dx * 13.5 + t * 0.00405 : F32), (dy * 13.5 : F32),
    (dz * 13.5 : F32))
  +clouds = Trk.S.smooth(0.50, 0.78, (cp * 0.7 + cp2 * 0.3 : F32))
  +cw = (clouds * 0.42 * Trk.S.smooth(0.02, 0.23, h) : F32)
  +m4 = Rgb.mix(m3, Rgb.at(0.105, 0.135, 0.190), cw)
  # weld into the fog, then the two distant ridge lines
  +fh = (1.0 - Trk.S.smooth((0.0 - 0.06 : F32), 0.16, h) : F32)
  +m5 = Rgb.mix(m4, Rgb.at(Fog.r(), Fog.g(), Fog.b()), fh)
  +az = F32.atan2(dx, dz)
  +ridge = (0.025 + F32.sin(az * 7.0) * 0.015 + F32.sin(az * 17.0 + 2.0) * 0.009
    : F32)
  +rw = (1.0 - Trk.S.smooth(ridge, (ridge + 0.004 : F32), h) : F32)
  +m6 = Rgb.mix(m5, Rgb.at(0.060, 0.087, 0.128), rw)
  +ridge2 = (0.008 + F32.sin(az * 11.0 + 1.0) * 0.011 : F32)
  +nw = (1.0 - Trk.S.smooth(ridge2, (ridge2 + 0.003 : F32), h) : F32)
  Rgb.mix(m6, Rgb.at(Fog.r(), Fog.g(), Fog.b()), nw)


# ---- FS_COMMON -------------------------------------------------------
def Light.win.go(f: Rt.Frag, ws: List<&2, Rt.P3>, +acc: RGB) -> RGB:
  # The fragment comes before the list in the binder order, so it is
  # destructured first and rebuilt for the tail of the fold -- the compiler
  # fuses the pair, and the fields are floats.
  Rt.Frag{+px, +py, +pz, +nx, +ny, +nz, +cr, +cg, +cb, +e, +iw} = f
  match ws:
    case []:
      acc
    case w <> rest:
      Rt.P3{dx, dy, dz} = w
      +lx = (dx - px : F32)
      +ly = (dy - py : F32)
      +lz = (dz - pz : F32)
      +d2 = (lx * lx + ly * ly + lz * lz : F32)
      +watt = (1.0 / (1.0 + d2 * 0.055 : F32) : F32)
      +il = (1.0 / F32.sqrt(Sh.safe(d2)) : F32)
      +lam = F32.max(0.0, ((nx * lx + ny * ly + nz * lz : F32) * il : F32))
      +kk = (watt * lam * 1.25 : F32)
      Light.win.go(Rt.Frag{px, py, pz, nx, ny, nz, cr, cg, cb, e, iw}, rest,
        Light.add(acc, kk))


def Sh.v(f: Rt.Frag, cam: Rt.VCam, lts: Lights, +head_on: Bool) -> RGB:
  # every fragment channel is read more than once below (position for the
  # headlight, colour and emissive both into the window pass and into the
  # final lambert), so the binders are reusable rather than linear.
  Rt.Frag{+wx, +wy, +wz, +nx, +ny, +nz, +cr, +cg, +cb, +e, +iw} = f
  Rt.VCam{ex, ey, ez, rx, ry, rz, ux, uy, uz, fx, fy, fz, k, hw, hh} = cam
  Lights{+hx, +hy, +hz, +hdx, +hdy, +hdz, +ws} = lts
  +nl = (1.0 / F32.sqrt(Sh.safe((nx * nx + ny * ny + nz * nz : F32))) : F32)
  +Nx = (nx * nl : F32)
  +Ny = (ny * nl : F32)
  +Nz = (nz * nl : F32)
  +vx = (ex - wx : F32)
  +vy = (ey - wy : F32)
  +vz = (ez - wz : F32)
  +dist = F32.sqrt((vx * vx + vy * vy + vz * vz : F32))
  # hemisphere ambient: cold from above, almost black below
  +sky = (Ny * 0.5 + 0.5 : F32)
  +ar = (0.065 + 0.155 * sky : F32)
  +ag = (0.079 + 0.191 * sky : F32)
  +ab = (0.110 + 0.250 * sky : F32)
  # moon: diffuse plus one narrow glint -- it is what makes the rails read
  +id = (1.0 / F32.max(dist, 0.001) : F32)
  +moon = F32.max(0.0, (Nx * Moon.x() + Ny * Moon.y() + Nz * Moon.z() : F32))
  +hxv = (Moon.x() + vx * id : F32)
  +hyv = (Moon.y() + vy * id : F32)
  +hzv = (Moon.z() + vz * id : F32)
  +ih = (1.0 / F32.sqrt(Sh.safe((hxv * hxv + hyv * hyv + hzv * hzv : F32))) : F32)
  +nh = F32.max(0.0, ((Nx * hxv + Ny * hyv + Nz * hzv : F32) * ih : F32))
  +spec = (F32.pow(nh, 48.0) * 0.55 : F32)
  +lr = (ar + 0.40 * moon * 1.15 + 0.55 * spec : F32)
  +lg = (ag + 0.47 * moon * 1.15 + 0.62 * spec : F32)
  +lb = (ab + 0.66 * moon * 1.15 + 0.82 * spec : F32)
  # the locomotive's headlight
  +lx = (hx - wx : F32)
  +ly = (hy - wy : F32)
  +lz = (hz - wz : F32)
  +ld = F32.sqrt((lx * lx + ly * ly + lz * lz : F32))
  +ild = (1.0 / F32.max(ld, 0.001) : F32)
  +u0 = (lx * ild : F32)
  +u1 = (ly * ild : F32)
  +u2 = (lz * ild : F32)
  +cone = Trk.S.smooth(0.955, 0.995,
    ((0.0 - u0 : F32) * hdx + (0.0 - u1 : F32) * hdy + (0.0 - u2 : F32) * hdz : F32))
  +atten = (1.0 / (1.0 + 0.0022 * ld * ld : F32) : F32)
  +lam = F32.max(0.0, (Nx * u0 + Ny * u1 + Nz * u2 : F32))
  +hk = (cone * atten * lam * 26.0 * Rt.S.if1(head_on, 1.0, 0.0) : F32)
  +wl = Light.win.go(
    Rt.Frag{wx, wy, wz, nx, ny, nz, cr, cg, cb, e, iw}, ws, RGB{0.0, 0.0, 0.0})
  # the demo's grain only bites on unlit, nearby surfaces
  +gx = F32.floor((wx * 18.0 : F32))
  +gz = F32.floor((wz * 18.0 : F32))
  +grain = Trk.S.fract((F32.sin((gx * 12.9898 + gz * 78.233 : F32)) * 43758.5453
    : F32))
  +emis1 = Rt.S.if1(F32.is_ge(e, 0.01), 1.0, 0.0)
  +amt = ((1.0 - emis1) * (1.0 - Trk.S.smooth(15.0, 100.0, dist)) : F32)
  +gs = (1.0 - amt * grain * 0.12 : F32)
  +ff = F32.clamp((1.0 - F32.exp((0.0 - F32.square((dist * Fog.density() : F32))
    : F32)) : F32), 0.0, 1.0)
  Rgb.fog(Rgb.tone(Rgb.lit((lr + 1.00 * hk : F32), (lg + 0.87 * hk : F32),
    (lb + 0.66 * hk : F32), wl, cr, cg, cb, e, gs)), ff)


# ---- the star sphere -------------------------------------------------
# 1100 directions from the demo's own generator, seeded 7, in the same call
# order -- u, v, then the brightness.
#
# That generator is not the one the dust uses.  The demo writes it in plain
# JavaScript numbers, `seed = (seed * 1103515245 + 12345) & 0x7fffffff`, so the
# product is first rounded to what a double can hold -- 53 significant bits --
# and only then masked.  A wrapping 32-bit multiply keeps bits the demo throws
# away, and from the second call on every value differs, which would put all
# 1100 stars somewhere else.  So the rounding is part of the picture and is
# reproduced here: the product is 62 bits wide, and the three defs below are
# what it costs to round it the way the double does.
type Wide is Data:
  Wide{hi: U32, lo: U32}


# 1103515245 = 16838 * 2^16 + 20077, and the seed is 31 bits, so the product
# splits into four 30-bit pieces: s1*m1 * 2^32 + (s1*m0 + s0*m1) * 2^16 + s0*m0.
def Stars.wide(+s: U32) -> Wide:
  +s1 = U32.shrn(s, 16n)
  +s0 = U32.and(s, 65535)
  +a = U32.mul(s1, 16838)
  +b = U32.mul(s1, 20077)
  +c = U32.mul(s0, 16838)
  +d = U32.mul(s0, 20077)
  +mid = U32.add(b, c)
  +u = U32.shln(U32.and(mid, 65535), 16n)
  +lo = U32.add(u, d)
  +carry = Bool.pick(U32, U32.is_lt(lo, u), 1, 0)
  Wide{U32.add(U32.add(a, U32.shrn(mid, 16n)), carry), lo}


# How many bits the high word holds: the first k whose 2^(k-1) it reaches,
# scanning down from 30.  Bool.pick takes both arms, so the scan always runs to
# the bottom and the outermost match is the one that survives.
def Stars.bits.go(+hi: U32, +k: Nat) -> Nat:
  match k:
    case 0n:
      0n
    case 1n+j:
      Bool.pick(Nat, U32.is_ge(hi, U32.shln(1, j)), k, Stars.bits.go(hi, j))


def Stars.bits(+hi: U32) -> Nat:
  Stars.bits.go(hi, 30n)


# The double keeps the top 53 bits, so what it holds is a multiple of 2^e, e
# counted down from the top of the 62-bit product.  The seed is 31 bits, so e
# never passes 9.
def Stars.shift(+hi: U32) -> Nat:
  +b = Stars.bits(hi)
  Bool.pick(Nat, Nat.is_ge(b, 22n), Nat.sub(b, 21n), 0n)


# Round up when the remainder is past half, or exactly at half with an odd
# quotient: IEEE's round-half-to-even.
def Stars.up(+rem: U32, +half: U32, +odd: U32) -> U32:
  Bool.pick(U32,
    Bool.or(U32.is_gt(rem, half),
      Bool.and(U32.is_eq(rem, half), U32.is_eq(odd, 1))), 1, 0)


# One call: round the product to a multiple of 2^e, add 12345 and round that to
# the same multiple -- the double's own two roundings -- then keep the low 31
# bits.  Only those bits are wanted and e never passes 9, so the product's low
# word carries the whole answer.
def Stars.rounded(+lo: U32, +e: Nat) -> U32:
  +mask = U32.sub(U32.shln(1, Nat.sub(31n, e)), 1)
  +ones = U32.sub(U32.shln(1, e), 1)
  +half = U32.shln(1, Nat.sub(e, 1n))
  +q = U32.shrn(lo, e)
  +c1 = Stars.up(U32.and(lo, ones), half, U32.and(q, 1))
  +dd = U32.shrn(12345, e)
  +c2 = Stars.up(U32.and(12345, ones), half,
    U32.and(U32.add(q, U32.add(c1, dd)), 1))
  U32.and(U32.shln(U32.and(U32.add(q, U32.add(c1, U32.add(dd, c2))), mask), e),
    2147483647)


# The product is taken apart in a def of its own: a destructuring let can only
# read a parameter, and e == 0 means the double held the product exactly, so the
# whole call is the product plus the increment.
def Stars.next.w(w: Wide) -> U32:
  Wide{hi, +lo} = w
  +e = Stars.shift(hi)
  Bool.pick(U32, U32.is_eq(U32.from_nat(e), 0),
    U32.and(U32.add(lo, 12345), 2147483647), Stars.rounded(lo, e))


def Stars.next(+s: U32) -> U32:
  Stars.next.w(Stars.wide(s))


def Stars.rnd(+s: U32) -> F32:
  (U32.to_f32(s) / 2147483647.0 : F32)


def Stars.go(+i: Nat, +seed: U32, +cam: Rt.VCam, +t: F32, +acc: List<&2, Rt.Spr>)
  -> List<&2, Rt.Spr>:
  match i:
    case 0n:
      acc
    case 1n+k:
      +s1 = Stars.next(seed)
      +s2 = Stars.next(s1)
      +s3 = Stars.next(s2)
      +u = Stars.rnd(s1)
      +v = Stars.rnd(s2)
      +w = (0.40 + F32.pow(Stars.rnd(s3), 2.0) * 0.85 : F32)
      +th = (u * 6.283185307179586 : F32)
      +yy = F32.pow(v, 0.75)
      +rr = F32.sqrt(F32.max(0.0, (1.0 - yy * yy : F32)))
      +dx = (F32.cos(th) * rr : F32)
      +dz = (F32.sin(th) * rr : F32)
      +tw = (0.72 + 0.28 * F32.sin((t * (0.6 + Trk.S.fract((w * 13.0 : F32)) * 2.2)
        + w * 40.0 : F32)) : F32)
      +lowv = Trk.S.smooth((0.0 - 0.04 : F32), 0.16, yy)
      +alpha = (w * tw * lowv : F32)
      +tt = Trk.S.fract((w * 31.0 : F32))
      Stars.go(k, s3, cam, t,
        Rt.Spr.star(cam, dx, yy, dz, (0.75 + w * 2.0 : F32),
          Trk.S.mix(0.78, 1.0, tt), Trk.S.mix(0.85, 0.90, tt),
          Trk.S.mix(1.0, 0.76, tt), alpha) <> acc)


def Stars.list(cam: Rt.VCam, +t: F32) -> List<&2, Rt.Spr>:
  Stars.go(1100n, 7, cam, t, [])
