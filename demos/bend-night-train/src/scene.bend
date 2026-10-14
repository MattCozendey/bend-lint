# Scene: the night train, as pure functions.
#
# The world is a graph over z.  The centreline is P(z) = (Track.x(z),
# Track.y(z), z) -- the same two sine harmonics the WebGL demo uses, so the
# camera and the geometry cannot drift apart.  Every function here is pure,
# which is exactly why the renderer parallelises: two pixels share nothing.
#
# Deliberate simplifications against the original, all recorded in docs/:
#   * no heightmap: the grass is flat under the bed, the forest stands on it;
#   * no catenary poles, no viaducts, no villages;
#   * pines are two stacked cones, not the demo's five-tier mesh.
#
# Bend needs `(e : T)` around every arithmetic term: outside an annotation
# `+ - * /` mean Nat, so an unannotated call argument is a type error.  That
# is why this file is denser than the equivalent JS.
import Base
import ./color.bend as Color

# ---- constants -------------------------------------------------------


# ---- camera ----------------------------------------------------------
# The camera hangs beside the consist at window height, offset to the left
# of the centreline, looking down the train as it curves away: the original's
# framing with lean = 1 and yaw = 0.

type Cam is Data:
  Cam{ex: F32, ey: F32, ez: F32, fx: F32, fy: F32, fz: F32, rx: F32, ry: F32,
    rz: F32, ux: F32, uy: F32, uz: F32, cx: F32, cy: F32, sx: F32, sy: F32}




# ---- vectors ---------------------------------------------------------

type V3 is Data:
  V3{x: F32, y: F32, z: F32}




def V3.norm(+v: V3) -> V3:
  V3{+x, +y, +z} = v
  +il = (1.0 / F32.sqrt((x * x + y * y + z * z : F32)) : F32)
  V3{(x * il : F32), (y * il : F32), (z * il : F32)}




# ---- scalar helpers --------------------------------------------------
# Declared this early because the noise and albedo helpers below need them,
# and Bend resolves names in declaration order.

def S.mix(+a: F32, +b: F32, +t: F32) -> F32:
  (a + (b - a) * t : F32)


def S.smooth(+a: F32, +b: F32, +x: F32) -> F32:
  +t = F32.clamp(((x - a : F32) / (b - a : F32) : F32), 0.0, 1.0)
  (t * t * (3.0 - 2.0 * t) : F32)


# A match may not scrutinise a call, so a Bool test result is turned into a
# number by a def that takes the Bool as its parameter.
def S.one.if(yes: Bool) -> F32:
  match yes:
    case True{}:
      1.0
    case False{}:
      0.0


def S.fract(+x: F32) -> F32:
  (x - F32.floor(x) : F32)


def Cam.at(+x: U32, +y: U32, cam: Cam) -> V3:
  Cam{ex, ey, ez, fx, fy, fz, rx, ry, rz, ux, uy, uz, +cx, +cy, sx, sy} = cam
  +px = ((U32.to_f32(x) - cx : F32) / cx * sx : F32)
  +py = ((cy - U32.to_f32(y) : F32) / cy * sy : F32)
  V3.norm(V3{(fx + px * rx + py * ux : F32), (fy + px * ry + py * uy : F32),
    (fz + px * rz + py * uz : F32)})




# The basis is written out in components: a let may not consume a value that
# a later let still needs, and the checker enforces binder order.
def Cam.build(+ex: F32, +ey: F32, +ez: F32, +fx: F32, +fy: F32, +fz: F32)
  -> Cam:
  +fl = (1.0 / F32.sqrt((fx * fx + fy * fy + fz * fz : F32)) : F32)
  +nx = (fx * fl : F32)
  +ny = (fy * fl : F32)
  +nz = (fz * fl : F32)
  # Camera basis, matching the demo's M4.lookAt: right = normalize(cross(look,
  # up)) with up = world +Y, and the screen-up then follows from right x look.
  # Getting this sign wrong mirrors the whole frame left-to-right.
  +rl = (1.0 / F32.sqrt((fz * fz + fx * fx : F32)) : F32)
  +rx = ((0.0 - fz : F32) * rl : F32)
  +rz = (fx * rl : F32)
  +vx = ((0.0 - rz : F32) * ny : F32)
  +vy = (rz * nx - rx * nz : F32)
  +vz = (rx * ny : F32)
  Cam{ex, ey, ez, nx, ny, nz, rx, 0.0, rz, vx, vy, vz, 0.0, 0.0, 0.0, 0.0}




def S.fovy() -> F32: 1.12




def Cam.fit(+w: U32, +h: U32, cam: Cam) -> Cam:
  Cam{ex, ey, ez, fx, fy, fz, rx, ry, rz, ux, uy, uz, cx, cy, sx, sy} = cam
  +nw = (U32.to_f32(w) * 0.5 : F32)
  +nh = (U32.to_f32(h) * 0.5 : F32)
  +t = F32.tan((S.fovy() * 0.5 : F32))
  Cam{ex, ey, ez, fx, fy, fz, rx, ry, rz, ux, uy, uz, nw, nh,
    (t * (nw / nh : F32) : F32), t}



def S.a1() -> F32: 58.0



def S.a2() -> F32: 13.0



def S.f1() -> F32: 0.00840



def S.f2() -> F32: 0.02150



def S.p2() -> F32: 1.3




# ---- track -----------------------------------------------------------

def Track.x(+z: F32) -> F32:
  (S.a1() * F32.sin(z * S.f1()) + S.a2() * F32.sin(z * S.f2() + S.p2()) : F32)



def S.b1() -> F32: 3.4



def S.b2() -> F32: 1.6



def S.g1() -> F32: 0.00625



def S.g2() -> F32: 0.015625



def S.q2() -> F32: 0.7




def Track.y(+z: F32) -> F32:
  (S.b1() * F32.sin(z * S.g1()) + S.b2() * F32.sin(z * S.g2() + S.q2()) : F32)




def Track.dx(+z: F32) -> F32:
  (S.a1() * S.f1() * F32.cos(z * S.f1())
    + S.a2() * S.f2() * F32.cos(z * S.f2() + S.p2()) : F32)




def Track.yaw(+z: F32) -> F32:
  F32.atan2(Track.dx(z), 1.0)




def Cam.ride(+s: F32, +side: F32, +hgt: F32, +yaw_off: F32, +pitch: F32) -> Cam:
  +base = Track.yaw(s)
  +cy = F32.cos(base)
  +sy = F32.sin(base)
  +yaw = (base + yaw_off : F32)
  +cp = F32.cos(pitch)
  Cam.build((Track.x(s) - side * cy : F32), (Track.y(s) + hgt : F32),
    (s + side * sy : F32), (F32.sin(yaw) * cp : F32), F32.sin(pitch),
    (F32.cos(yaw) * cp : F32))




# ---- the consist -----------------------------------------------------
# The yaw is baked into cc/ss when the consist is built: the per-step SDF
# must be pure arithmetic, with no sin/cos in the inner loop.

type Car is Data:
  Car{cx: F32, cy: F32, cz: F32, cc: F32, ss: F32, kind: U32}




def Car.far() -> Car:
  Car{0.0, 0.0, 0.0, 1.0, 0.0, 0}




# `kind` is 0 for the locomotive and 1 + i%3 for a carriage, so the window
# parity doubles as the paint variant the demo picks its lit windows from.
def Car.kind.of(loco: Bool, +i: U32) -> U32:
  match loco:
    case True{}:
      0
    case False{}:
      U32.add(U32.mod(i, 3), 1)



def M.body() -> U32: 3



def M.window() -> U32: 4



def M.window.dark() -> U32: 8



def M.roof() -> U32: 9



def M.brass() -> U32: 10



# The demo lights a window by a hash of the car variant and the window index:
# lit = ((variant*7 + w)*7919) % 11 > 2.  A dark pane keeps its own glass
# colour and a near-zero emissive, which is what stops the whole side of the
# train glowing.
def Car.mat.lit(lit: Bool) -> U32:
  match lit:
    case True{}:
      M.window()
    case False{}:
      M.window.dark()



def M.loco() -> U32: 7




# Seven windows a side at lz = (w-3)*3; the glass is 1.51 x 0.94 and sits
# 0.45 above the body centre.  The band is clipped at the outermost pane so
# the modulo does not paint a window on the car end.
def window.band(+m: F32, +lz: F32, +ly: F32) -> Bool:
  ((F32.is_lt(F32.abs(lz), 9.76) && F32.is_lt(F32.abs((m - 1.5 : F32)), 0.755))
    && (F32.is_lt(F32.abs((ly - 0.45 : F32)), 0.47) : Bool) : Bool)



def window.pattern(+lz: F32, +ly: F32) -> Bool:
  window.band(F32.mod((lz + 1.5 : F32), 3.0), lz, ly)




# The brass mouldings run the length of the side at local y -0.82 and +1.32,
# so a narrow band plus the ring around each window is the whole trim.
def Car.trim.band(+ly: F32) -> Bool:
  (F32.is_lt(F32.abs((ly + 0.82 : F32)), 0.035)
    || F32.is_lt(F32.abs((ly - 1.32 : F32)), 0.030) : Bool)



def Car.detail.pick4(mold: Bool) -> U32:
  match mold:
    case True{}:
      M.brass()
    case False{}:
      M.body()



def Car.detail.pick3(ring: Bool, mold: Bool) -> U32:
  match ring:
    case True{}:
      M.brass()
    case False{}:
      Car.detail.pick4(mold)



def Car.detail.pick2(band: Bool, ring: Bool, mold: Bool, lit: Bool) -> U32:
  match band:
    case True{}:
      Car.mat.lit(lit)
    case False{}:
      Car.detail.pick3(ring, mold)



def Car.detail.pick(roof: Bool, band: Bool, ring: Bool, mold: Bool, lit: Bool)
  -> U32:
  match roof:
    case True{}:
      M.roof()
    case False{}:
      Car.detail.pick2(band, ring, mold, lit)




# Carriage detail: the arch roof, glass, the brass ring around a window, the
# two side mouldings, then the paint.
def Car.detail(+lx: F32, +ly: F32, +m: F32, +lz: F32, lit: Bool) -> U32:
  +band = window.band(m, lz, ly)
  +ring = (F32.is_lt(F32.abs((m - 1.5 : F32)), 0.93)
    && F32.is_lt(F32.abs((ly - 0.45 : F32)), 0.64) : Bool)
  +mold = (F32.is_gt(F32.abs(lx), 1.2) && Car.trim.band(ly) : Bool)
  Car.detail.pick(F32.is_gt(ly, 1.5), band, ring, mold, lit)




def Car.mat.pick(+kind: U32, detail: U32) -> U32:
  match kind:
    case 0:
      M.loco()
    case _:
      detail




def Car.mat(+px: F32, +py: F32, +pz: F32, car: Car) -> U32:
  Car{cx, cy, cz, +cc, +ss, +kind} = car
  +dx = (px - cx : F32)
  +dz = (pz - cz : F32)
  +lx = (dx * cc - dz * ss : F32)
  +lz = (dx * ss + dz * cc : F32)
  +ly = (py - cy : F32)
  +m = F32.mod((lz + 1.5 : F32), 3.0)
  +w = F32.to_u32((F32.floor((lz / 3.0 + 0.5 : F32)) + 3.0 : F32))
  +variant = U32.sub(kind, 1)
  +lit = U32.is_gt(
    U32.mod(U32.mul(U32.add(U32.mul(variant, 7), w), 7919), 11), 2)
  Car.mat.pick(kind, Car.detail(lx, ly, m, lz, lit))



def S.car_hx() -> F32: 1.45



def S.car_hy() -> F32: 1.50



def S.car_hz() -> F32: 12.0




# ---- distances -------------------------------------------------------

def box(+qx: F32, +qy: F32, +qz: F32) -> F32:
  +mx = F32.max(qx, F32.max(qy, qz))
  +ox = F32.max(qx, 0.0)
  +oy = F32.max(qy, 0.0)
  +oz = F32.max(qz, 0.0)
  (F32.sqrt((ox * ox + oy * oy + oz * oz : F32)) + F32.min(mx, 0.0) : F32)




def Car.sdf(+px: F32, +py: F32, +pz: F32, car: Car) -> F32:
  Car{cx, cy, cz, +cc, +ss, kind} = car
  +dx = (px - cx : F32)
  +dz = (pz - cz : F32)
  +lx = (dx * cc - dz * ss : F32)
  +lz = (dx * ss + dz * cc : F32)
  +ly = (py - cy : F32)
  +q = box((F32.abs(lx) - S.car_hx() + 0.25 : F32),
    (F32.abs(ly) - S.car_hy() + 0.25 : F32),
    (F32.abs(lz) - S.car_hz() + 0.25 : F32))
  +body = (q - 0.25 : F32)
  # The demo's roof is a half-cylinder arch on top of the body: 3.02 wide and
  # 1.3 tall, running the car's length.  An ellipse scaled by its minor axis
  # is a conservative distance bound, which is all the march needs.
  +ry = F32.max((ly - S.car_hy() : F32), 0.0)
  +e = (F32.hypot((F32.abs(lx) / 1.51 : F32), (ry / 0.65 : F32)) - 1.0 : F32)
  +rz = (F32.abs(lz) - 12.06 : F32)
  +roof = (F32.max((e * 0.65 : F32), rz) : F32)
  F32.min(body, roof)




# ---- hashing ---------------------------------------------------------

def Hash.mix(+a: U32, +b: U32) -> U32:
  +h = U32.xor(a, U32.mul(b, 2654435769))
  +h2 = U32.xor(h, U32.shrn(h, 16n))
  U32.mul(U32.xor(h2, U32.shrn(h2, 13n)), 2246822507)




def Hash.f(+a: U32, +b: U32) -> F32:
  (U32.to_f32(Hash.mix(a, b)) * 2.3283064365386963e-10 : F32)




# ---- value noise -----------------------------------------------------
# The demo's GLSL hash21 / vnoise / fbm, straight across, for the ground
# blotch and the sky.

def S.hash21(+px: F32, +pz: F32) -> F32:
  +ax = S.fract((px * 123.34 : F32))
  +az = S.fract((pz * 345.45 : F32))
  +dd = (ax * (ax + 34.345) + az * (az + 34.345) : F32)
  S.fract(((ax + dd) * (az + dd) : F32))


def S.vnoise(+px: F32, +pz: F32) -> F32:
  +ix = F32.floor(px)
  +iz = F32.floor(pz)
  +fx = (px - ix : F32)
  +fz = (pz - iz : F32)
  +ux = (fx * fx * (3.0 - 2.0 * fx) : F32)
  +uz = (fz * fz * (3.0 - 2.0 * fz) : F32)
  +a = S.hash21(ix, iz)
  +b = S.hash21((ix + 1.0 : F32), iz)
  +c = S.hash21(ix, (iz + 1.0 : F32))
  +dd = S.hash21((ix + 1.0 : F32), (iz + 1.0 : F32))
  +m1 = S.mix(a, b, ux)
  +m2 = S.mix(c, dd, ux)
  S.mix(m1, m2, uz)


def S.fbm(+px: F32, +pz: F32) -> F32:
  +v1 = S.vnoise(px, pz)
  +x2 = (px * 2.03 : F32)
  +z2 = (pz * 2.03 : F32)
  +v2 = S.vnoise(x2, z2)
  +x3 = (x2 * 2.03 : F32)
  +z3 = (z2 * 2.03 : F32)
  +v3 = S.vnoise(x3, z3)
  +x4 = (x3 * 2.03 : F32)
  +z4 = (z3 * 2.03 : F32)
  +v4 = S.vnoise(x4, z4)
  (0.5 * v1 + 0.25 * v2 + 0.125 * v3 + 0.0625 * v4 : F32)



def M.ballast() -> U32: 2




# ---- materials -------------------------------------------------------
# Evaluated once, at the hit point.  The nearest carriage is found here and
# reused for the material, the normal and the window spill, so the consist is
# walked once per pixel instead of once per marching step.

def M.grass() -> U32: 1



def M.pine() -> U32: 5



def M.rail() -> U32: 6




# A pine is two round cones stacked: distance to each axis segment minus the
# radius interpolated along it.  Not exact near the tips, but the seam is
# what gives the demo's trees their layered silhouette.

# The demo's tree is 0.85..2.75x scale with a crown about 8.6x scale tall
# standing on the terrain; the cone keeps that silhouette.  `base` is the
# ground height under the trunk, so a tree on a sloped track does not float.
type Pine is Data:
  Pine{ox: F32, oz: F32, r: F32, h: F32, base: F32}




def Pine.cell.if(far: Bool, +ox: F32, +oz: F32) -> Pine:
  match far:
    case True{}:
      +h0 = Hash.f(F32.to_u32((ox + 4096.0 : F32)),
        F32.to_u32((oz + 4096.0 : F32)))
      +scale = (0.85 + 1.9 * h0 : F32)
      # The demo's crown is 0.5*4.2*scale across and 0.8*7.8*scale tall,
      # standing 0.8*scale above the terrain on a trunk.
      Pine{ox, oz, (2.1 * scale : F32), (6.3 * scale : F32),
        (Track.y(oz) - 0.9 + 0.8 * scale : F32)}
    case False{}:
      Pine{1000000000.0, 1000000000.0, 0.0, 1.0, 1000000000.0}




# Two stacked cones instead of the demo's five-tier mesh: the silhouette
# breaks at the tier seam, which is what reads at night.  Cheap enough to
# evaluate for four candidate cells per march step.
def pine(+px: F32, +py: F32, +pz: F32, p: Pine) -> F32:
  Pine{ox, oz, +r, +h, +base} = p
  +q = F32.hypot((px - ox : F32), (pz - oz : F32))
  +ly = (py - base : F32)
  +h1 = (0.60 * h : F32)
  +t1 = F32.clamp((ly / h1 : F32), 0.0, 1.0)
  +r1 = (r * (1.0 - 0.75 * t1) : F32)
  +u1 = (ly - t1 * h1 : F32)
  +d1 = (F32.hypot(q, u1) - r1 : F32)
  +b2 = (0.45 * h : F32)
  +h2 = (h - b2 : F32)
  +u2 = (ly - b2 : F32)
  +t2 = F32.clamp((u2 / h2 : F32), 0.0, 1.0)
  +r2 = (0.68 * r * (1.0 - t2) : F32)
  +d2 = (F32.hypot(q, (u2 - t2 * h2 : F32)) - r2 : F32)
  F32.min(d1, d2)




# A cell with no tree holds a pine a billion metres away, which makes the
# min-reduction total: no branch, and no Bool to match on.
def Pine.sdf(+px: F32, +py: F32, +pz: F32, p: Pine, +d: F32) -> F32:
  F32.min(d, pine(px, py, pz, p))



def S.cam_hgt() -> F32: 3.05



def S.cars_n() -> Nat: 15n




def S.cell() -> F32: 6.0



def S.cell_bias() -> F32: 4096.0




def S.cellidx(+x: F32) -> U32:
  F32.to_u32((F32.floor((x / S.cell() : F32)) + S.cell_bias() : F32))



def S.fog_b() -> F32: 0.115



def S.fog_density() -> F32: 0.0026



def S.fog_g() -> F32: 0.068




def S.fog_r() -> F32: 0.055



def S.forest_min_lat() -> F32: 13.0




# normalize(0.42, 0.36, 0.83): the demo's moon direction
def S.moon_x() -> F32: 0.4211



def S.moon_y() -> F32: 0.3609



def S.moon_z() -> F32: 0.8322




def S.pitch() -> F32: 26.6




# ---- scalars ---------------------------------------------------------

def S.sign(+x: F32) -> F32:
  F32.clamp((x * 1000000.0 : F32), (0.0 - 1.0 : F32), 1.0)



def S.slope() -> F32: 0.999




# ---- sky -------------------------------------------------------------

# 3D value noise (the demo's hash31 / vnoise3 / fbm), used by the sky.
def S.hash31(+px: F32, +py: F32, +pz: F32) -> F32:
  +ax = S.fract((px * 0.3183 + 0.71 : F32))
  +ay = S.fract((py * 0.3183 + 0.113 : F32))
  +az = S.fract((pz * 0.3183 + 0.419 : F32))
  +bx = (ax * 17.0 : F32)
  +by = (ay * 17.0 : F32)
  +bz = (az * 17.0 : F32)
  S.fract((bx * by * bz * (bx + by + bz) : F32))


def S.vnoise3(+px: F32, +py: F32, +pz: F32) -> F32:
  +ix = F32.floor(px)
  +iy = F32.floor(py)
  +iz = F32.floor(pz)
  +fx = (px - ix : F32)
  +fy = (py - iy : F32)
  +fz = (pz - iz : F32)
  +ux = (fx * fx * (3.0 - 2.0 * fx) : F32)
  +uy = (fy * fy * (3.0 - 2.0 * fy) : F32)
  +uz = (fz * fz * (3.0 - 2.0 * fz) : F32)
  +x0 = (ix + 1.0 : F32)
  +y0 = (iy + 1.0 : F32)
  +z0 = (iz + 1.0 : F32)
  +c00 = S.mix(S.hash31(ix, iy, iz), S.hash31(x0, iy, iz), ux)
  +c10 = S.mix(S.hash31(ix, y0, iz), S.hash31(x0, y0, iz), ux)
  +c01 = S.mix(S.hash31(ix, iy, z0), S.hash31(x0, iy, z0), ux)
  +c11 = S.mix(S.hash31(ix, y0, z0), S.hash31(x0, y0, z0), ux)
  S.mix(S.mix(c00, c10, uy), S.mix(c01, c11, uy), uz)


def S.fbm3(+px: F32, +py: F32, +pz: F32) -> F32:
  +v1 = S.vnoise3(px, py, pz)
  +x2 = (px * 2.07 : F32)
  +y2 = (py * 2.07 : F32)
  +z2 = (pz * 2.07 : F32)
  +v2 = S.vnoise3(x2, y2, z2)
  +x3 = (x2 * 2.07 : F32)
  +y3 = (y2 * 2.07 : F32)
  +z3 = (z2 * 2.07 : F32)
  +v3 = S.vnoise3(x3, y3, z3)
  +x4 = (x3 * 2.07 : F32)
  +y4 = (y3 * 2.07 : F32)
  +z4 = (z3 * 2.07 : F32)
  +v4 = S.vnoise3(x4, y4, z4)
  (0.62 * v1 + 0.3224 * v2 + 0.167648 * v3 + 0.08717696 * v4 : F32)


# The demo's 1100 stars are a separate additive sprite pass.  Here they are
# one cell lookup on the ray direction: round, dim, fading into the haze.
def S.star(+dx: F32, +dy: F32, +dz: F32) -> V3:
  +nx = (dx * 140.0 : F32)
  +ny = (dy * 140.0 : F32)
  +nz = (dz * 140.0 : F32)
  +ix = F32.floor(nx)
  +iy = F32.floor(ny)
  +iz = F32.floor(nz)
  +h = S.hash31(ix, iy, iz)
  +o1 = S.hash31((ix + 7.13 : F32), (iy + 3.31 : F32), (iz + 11.70 : F32))
  +o2 = S.hash31((ix + 1.71 : F32), (iy + 9.37 : F32), (iz + 5.19 : F32))
  +o3 = S.hash31((ix + 4.23 : F32), (iy + 6.11 : F32), (iz + 2.87 : F32))
  +fx = (nx - ix - o1 : F32)
  +fy = (ny - iy - o2 : F32)
  +fz = (nz - iz - o3 : F32)
  +d = F32.sqrt((fx * fx + fy * fy + fz * fz : F32))
  +core = F32.pow(F32.max(0.0, (1.0 - d * 4.0 : F32)), 3.5)
  +w = (S.one.if(F32.is_gt(h, 0.9925)) * core * S.smooth((0.0 - 0.04 : F32), 0.16, dy) : F32)
  +warm = S.hash31((ix + 0.5 : F32), (iy + 0.5 : F32), (iz + 0.5 : F32))
  V3{(w * S.mix(0.78, 1.00, warm) : F32), (w * S.mix(0.85, 0.90, warm) : F32),
    (w * S.mix(1.00, 0.76, warm) : F32)}




def Track.bed(+z: F32) -> F32:
  (Track.y(z) - 0.9 : F32)




def Track.dy(+z: F32) -> F32:
  (S.b1() * S.g1() * F32.cos(z * S.g1())
    + S.b2() * S.g2() * F32.cos(z * S.g2() + S.q2()) : F32)




def Track.grass(+z: F32) -> F32:
  (Track.y(z) - 0.9 : F32)




# A destructuring let may only scrutinise a parameter or a field: neither a
# call nor a local binder can head a match.  Accessors are the way around
# that, and the compiler inlines them.
def V3.px(v: V3) -> F32:
  match v:
    case V3{x, y, z}:
      x




def V3.py(v: V3) -> F32:
  match v:
    case V3{x, y, z}:
      y




def V3.pz(v: V3) -> F32:
  match v:
    case V3{x, y, z}:
      z




# ---- albedo ----------------------------------------------------------

# Grass and the wet embankment either side of the track, then the demo's
# fbm blotch: grass *= 0.75 + blotch*0.6.
def grass.albedo(+px: F32, +pz: F32) -> V3:
  +wet = S.smooth(0.0, 26.0, F32.abs((px - Track.x(pz) : F32)))
  +r = S.mix(0.105, 0.070, wet)
  +g = S.mix(0.125, 0.092, wet)
  +b = S.mix(0.108, 0.120, wet)
  +blotch = S.fbm((px * 0.03 : F32), (pz * 0.03 : F32))
  +k = (0.75 + blotch * 0.6 : F32)
  V3{(r * k : F32), (g * k : F32), (b * k : F32)}


# Ballast and sleepers.  The demo instances box sleepers every 0.62 m on a
# bed of (0.085, 0.078, 0.070); here the bed is the ground plane and the
# sleepers are a stripe in its albedo, which costs nothing in the march.
def ballast(+px: F32, +pz: F32) -> V3:
  +alat = F32.abs((px - Track.x(pz) : F32))
  +m = F32.mod((pz + 0.31 : F32), 0.62)
  +sleeper = (F32.is_lt(F32.abs((m - 0.31 : F32)), 0.14)
    && F32.is_lt(alat, 1.35) : Bool)
  +k = S.one.if(sleeper)
  +g = Hash.f(U32.add(F32.to_u32((F32.floor((px * 9.0 : F32)) : F32)), 4096),
    U32.add(F32.to_u32((F32.floor((pz * 9.0 : F32)) : F32)), 4096))
  +br = (0.085 + 0.020 * g : F32)
  +bg = (0.078 + 0.018 * g : F32)
  +bb = (0.070 + 0.016 * g : F32)
  V3{S.mix(br, 0.070, k), S.mix(bg, 0.058, k), S.mix(bb, 0.048, k)}




def albedo(+mat: U32, +px: F32, +py: F32, +pz: F32) -> V3:
  match mat:
    case 2:
      ballast(px, pz)
    case 3:
      V3{0.120, 0.200, 0.220}
    case 4:
      V3{0.940, 0.620, 0.290}
    case 5:
      V3{0.075, 0.125, 0.100}
    case 6:
      V3{0.380, 0.400, 0.440}
    case 7:
      V3{0.120, 0.190, 0.200}
    case 8:
      V3{0.070, 0.130, 0.190}
    case 9:
      V3{0.210, 0.250, 0.280}
    case 10:
      V3{0.490, 0.350, 0.180}
    case _:
      grass.albedo(px, pz)




def car(+i: U32, +s: F32) -> Car:
  # carS(i) is the rear reference point; the mesh sits CAR_LEN*0.5 further on,
  # so the centre is at s - 2.88 + (i-5)*26.6.  Placing it at carS(i) instead
  # parks the whole consist 12 m too far back.
  +rel = (U32.to_f32(i) * S.pitch() - 5.0 * S.pitch() - 2.88 : F32)
  +cz = (s + rel : F32)
  +yaw = Track.yaw(cz)
  Car{Track.x(cz), (Track.y(cz) + 2.6 : F32), cz, F32.cos(yaw), F32.sin(yaw),
    Car.kind.of(U32.is_eq(i, 14), i)}




def cars.go(+px: F32, +py: F32, +pz: F32, cars: List<&2, Car>, +d: F32)
  -> F32:
  match cars:
    case []:
      d
    case c <> rest:
      cars.go(px, py, pz, rest, F32.min(d, Car.sdf(px, py, pz, c)))




def cars.if(near: Bool, +px: F32, +py: F32, +pz: F32,
  cars: List<&2, Car>, +d: F32) -> F32:
  match near:
    case True{}:
      cars.go(px, py, pz, cars, d)
    case False{}:
      d




def cars.nearest(+px: F32, +py: F32, +pz: F32, +cars: List<&2, Car>,
  +best: Car) -> Car:
  match cars:
    case []:
      best
    case c <> rest:
      +dc = Car.sdf(px, py, pz, c)
      +db = Car.sdf(px, py, pz, best)
      cars.nearest(px, py, pz, rest,
        Bool.pick(Car, F32.is_lt(dc, db), c, best))


def consist.list(+s: F32, idx: List<&2, Nat>, +acc: List<&2, Car>)
  -> List<&2, Car>:
  match idx:
    case []:
      acc
    case i <> rest:
      consist.list(s, rest, car(U32.from_nat(i), s) <> acc)




# The index sequence the consist is built from.  It is split out from the
# geometry so that LAWS.bend can state -- and PROOF.bend can prove -- that it
# has exactly k slots, which F32 would otherwise make unprovable.
def slots(+k: Nat) -> List<&2, Nat>:
  match k:
    case 0n:
      []
    case 1n+p:
      p <> slots(p)


def consist(+s: F32) -> List<&2, Car>:
  consist.list(s, slots(S.cars_n()), [])




def emissive(+mat: U32) -> F32:
  match mat:
    case 4:
      0.62
    case 8:
      0.02
    case _:
      0.0




# The demo applies the same moon glint to every material; the coefficient
# lives in `shade`, so this is flat.
def gloss(+mat: U32) -> F32:
  1.0




def mat.ground.hi(above: Bool, +px: F32, +py: F32, +pz: F32) -> U32:
  match above:
    case True{}:
      M.pine()
    case False{}:
      M.grass()




def mat.ground.near(rail: Bool, +px: F32, +py: F32, +pz: F32) -> U32:
  match rail:
    case True{}:
      M.rail()
    case False{}:
      M.ballast()


def mat.ground.pick(far: Bool, rail: Bool, +px: F32, +py: F32, +pz: F32)
  -> U32:
  match far:
    case True{}:
      mat.ground.hi(
        F32.is_gt(py, (Track.grass(pz) + 0.12 : F32)), px, py, pz)
    case False{}:
      mat.ground.near(rail, px, py, pz)


def mat.ground(+px: F32, +py: F32, +pz: F32) -> U32:
  +alat = F32.abs((px - Track.x(pz) : F32))
  # the rail head sits at |alat - 0.72| < 0.075, top at trackY - 0.02
  +rail = (F32.is_lt(F32.abs((alat - 0.72 : F32)), 0.083)
    && F32.is_lt(F32.abs((py - (Track.y(pz) - 0.10 : F32) : F32)), 0.12)
    : Bool)
  mat.ground.pick(F32.is_gt(alat, 4.6), rail, px, py, pz)




def mat.pick(iscar: Bool, +px: F32, +py: F32, +pz: F32, car: Car) -> U32:
  match iscar:
    case True{}:
      Car.mat(px, py, pz, car)
    case False{}:
      mat.ground(px, py, pz)




def mat(+px: F32, +py: F32, +pz: F32, car: Car, +cd: F32) -> U32:
  mat.pick(F32.is_lt(cd, 0.10), px, py, pz, car)




def normal.car.axis2(ybig: Bool, +lx: F32, +dy: F32, +lz: F32, +cc: F32,
  +ss: F32) -> V3:
  match ybig:
    case True{}:
      V3{0.0, S.sign(dy), 0.0}
    case False{}:
      V3.norm(V3{(S.sign(lz) * ss : F32), 0.0, (S.sign(lz) * cc : F32)})




def normal.car.axis(xbig: Bool, ybig: Bool, +lx: F32, +dy: F32, +lz: F32,
  +cc: F32, +ss: F32) -> V3:
  match xbig:
    case True{}:
      V3.norm(V3{(S.sign(lx) * cc : F32), 0.0, ((0.0 - S.sign(lx) : F32) * ss : F32)})
    case False{}:
      normal.car.axis2(ybig, lx, dy, lz, cc, ss)




# ---- normals ---------------------------------------------------------

def normal.car(+px: F32, +py: F32, +pz: F32, car: Car) -> V3:
  Car{cx, cy, cz, +cc, +ss, kind} = car
  +dx = (px - cx : F32)
  +dy = (py - cy : F32)
  +dz = (pz - cz : F32)
  +lx = (dx * cc - dz * ss : F32)
  +lz = (dx * ss + dz * cc : F32)
  # The body is a long box, so the face has to be picked by the distance to
  # each face in units of half-extent, not by the raw magnitude: a point on
  # the side of a 24 m car has |lz| up to 12 and would otherwise take the
  # end-cap normal.
  +ax = (F32.abs(lx) / S.car_hx() : F32)
  +ay = (F32.abs(dy) / S.car_hy() : F32)
  +az = (F32.abs(lz) / S.car_hz() : F32)
  # `>=` is sugar for T.is_ge on the annotated type, so a comparison on F32
  # has to name F32 rather than be wrapped in `: Bool`.
  normal.car.axis(F32.is_ge(ax, ay) && F32.is_ge(ax, az),
    F32.is_ge(ay, az), lx, dy, lz, cc, ss)




def normal.ground(+pz: F32) -> V3:
  V3.norm(V3{(0.0 - Track.dy(pz) : F32), 1.0, 0.0})




# The tree in the cell that contains the hit point is the one that was hit
# (or its neighbour), which is close enough for a cone at night: a full fold
# over the candidate cells would need another recursive walk.
def normal.pine.axis(p: Pine, +px: F32, +pz: F32) -> V3:
  Pine{ox, oz, r, h, base} = p
  V3.norm(V3{(px - ox : F32), 0.8, (pz - oz : F32)})




def pine.cell(+i: U32, +j: U32, +tx: F32, +tdx: F32, +pz: F32) -> Pine:
  +h0 = Hash.f(i, j)
  +h1 = Hash.f(j, i)
  +ox = ((U32.to_f32(i) - S.cell_bias() : F32) * S.cell() + 0.5 + 5.0 * h0 : F32)
  +oz = ((U32.to_f32(j) - S.cell_bias() : F32) * S.cell() + 0.5 + 5.0 * h1 : F32)
  # The centreline is linearised around the marched point: exact to well under
  # a metre over one cell.
  +txx = (tx + tdx * (oz - pz : F32) : F32)
  Pine.cell.if(F32.is_gt(F32.abs((ox - txx : F32)), S.forest_min_lat()), ox, oz)




def normal.pine(+px: F32, +py: F32, +pz: F32) -> V3:
  normal.pine.axis(
    pine.cell(S.cellidx(px), S.cellidx(pz), Track.x(pz), Track.dx(pz),
      pz), px, pz)




def normal(+px: F32, +py: F32, +pz: F32, +mat: U32, car: Car) -> V3:
  match mat:
    case 3:
      normal.car(px, py, pz, car)
    case 4:
      normal.car(px, py, pz, car)
    case 5:
      normal.pine(px, py, pz)
    case _:
      normal.ground(pz)




# ---- shading ---------------------------------------------------------
# The demo's fragment shader, one for one: hemisphere ambient, a moon diffuse
# plus one glint, a headlight cone, ten warm window points, the procedural
# grain, then tone map and fog.  The lights are pure functions of the frame's
# s, so they are built once and handed down the quadtree.

type Head is Data:
  Head{hx: F32, hy: F32, hz: F32, dx: F32, dy: F32, dz: F32}


def S.grain(+px: F32, +pz: F32) -> F32:
  +fx = F32.floor((px * 18.0 : F32))
  +fz = F32.floor((pz * 18.0 : F32))
  +s = F32.sin((fx * 12.9898 + fz * 78.233 : F32))
  +v = (s * 43758.5453 : F32)
  (v - F32.floor(v) : F32)


# ---- headlight and window lights -------------------------------------
# headCenterS = carS(CARS-1) + CAR_LEN*0.5; with the consist placed at
# carS(i) = s - 2.88 + (i-5)*26.6 that is s + 248.52.

def S.head_center(+s: F32) -> F32:
  (s + 248.52 : F32)


def Head.pos(+s: F32) -> Head:
  +cs = S.head_center(s)
  +yaw = Track.yaw(cs)
  +d = V3.norm(V3{F32.sin(yaw), (0.0 - 0.075 : F32), F32.cos(yaw)})
  Head{(Track.x(cs) + 9.92 * F32.sin(yaw) : F32), (Track.y(cs) + 1.6 : F32),
    (cs + 9.92 * F32.cos(yaw) : F32), V3.px(d), V3.py(d), V3.pz(d)}


def Win.at(+i: U32, +s: F32) -> V3:
  +ws = (s - 120.0 + U32.to_f32(i) * 42.0 : F32)
  +yaw = Track.yaw(ws)
  V3{(Track.x(ws) - 2.4 * F32.cos(yaw) : F32), (Track.y(ws) + 2.9 : F32),
    (ws + 2.4 * F32.sin(yaw) : F32)}


def Win.list(+i: Nat, +s: F32, +acc: List<&2, V3>) -> List<&2, V3>:
  match i:
    case 0n:
      acc
    case 1n+p:
      Win.list(p, s, Win.at(U32.from_nat(p), s) <> acc)


def Wins(+s: F32) -> List<&2, V3>:
  Win.list(10n, s, [])


def win.one(+px: F32, +py: F32, +pz: F32, +nx: F32, +ny: F32, +nz: F32,
  +w: V3, +acc: V3) -> V3:
  +wx = V3.px(w)
  +wy = V3.py(w)
  +wz = V3.pz(w)
  +wlx = (wx - px : F32)
  +wly = (wy - py : F32)
  +wlz = (wz - pz : F32)
  +wd2 = (wlx * wlx + wly * wly + wlz * wlz : F32)
  +watt = (1.0 / (1.0 + 0.055 * wd2 : F32) : F32)
  +iwl = (1.0 / F32.sqrt(F32.max(wd2, 0.000001)) : F32)
  +wlam = F32.max(0.0, ((nx * wlx + ny * wly + nz * wlz : F32) * iwl : F32))
  +k = (watt * wlam * 1.25 : F32)
  V3{(V3.px(acc) + 1.00 * k : F32), (V3.py(acc) + 0.70 * k : F32),
    (V3.pz(acc) + 0.36 * k : F32)}


def win.light.go(+px: F32, +py: F32, +pz: F32, +nx: F32, +ny: F32, +nz: F32,
  wins: List<&2, V3>, +acc: V3) -> V3:
  match wins:
    case []:
      acc
    case w <> rest:
      win.light.go(px, py, pz, nx, ny, nz, rest,
        win.one(px, py, pz, nx, ny, nz, w, acc))


def head.light(+px: F32, +py: F32, +pz: F32, +nx: F32, +ny: F32, +nz: F32,
  head: Head) -> V3:
  Head{+hx, +hy, +hz, +hdx, +hdy, +hdz} = head
  +lx = (hx - px : F32)
  +ly = (hy - py : F32)
  +lz = (hz - pz : F32)
  +ld = F32.sqrt((lx * lx + ly * ly + lz * lz : F32))
  +il = (1.0 / F32.max(ld, 0.001) : F32)
  +ux = (lx * il : F32)
  +uy = (ly * il : F32)
  +uz = (lz * il : F32)
  +cone = S.smooth(0.955, 0.995,
    ((0.0 - ux : F32) * hdx + (0.0 - uy : F32) * hdy
      + (0.0 - uz : F32) * hdz : F32))
  +atten = (1.0 / (1.0 + 0.0022 * ld * ld : F32) : F32)
  +lam = F32.max(0.0, (nx * ux + ny * uy + nz * uz : F32))
  +k = (cone * atten * lam * 26.0 : F32)
  V3{(1.00 * k : F32), (0.87 * k : F32), (0.66 * k : F32)}


def shade(+px: F32, +py: F32, +pz: F32, +dist: F32, cam: Cam,
  cars: List<&2, Car>, head: Head, wins: List<&2, V3>) -> U32:
  Cam{ex, ey, ez, fx, fy, fz, rx, ry, rz, ux, uy, uz, cx, cy, sx, sy} = cam
  +car = cars.nearest(px, py, pz, cars, Car.far())
  +cd = Car.sdf(px, py, pz, car)
  +mat = mat(px, py, pz, car, cd)
  +n = normal(px, py, pz, mat, car)
  +nx = V3.px(n)
  +ny = V3.py(n)
  +nz = V3.pz(n)
  # A destructuring let may only scrutinise a parameter, so the value is read
  # through the accessors rather than bound out of a local let.
  +alb = albedo(mat, px, py, pz)
  +ar = V3.px(alb)
  +ag = V3.py(alb)
  +ab = V3.pz(alb)
  # ambient hemisphere: cold from the sky, almost black off the ground
  +sky = (ny * 0.5 + 0.5 : F32)
  +lr = (0.065 + 0.155 * sky : F32)
  +lg = (0.079 + 0.191 * sky : F32)
  +lb = (0.110 + 0.250 * sky : F32)
  +lam = F32.max(0.0,
    (nx * S.moon_x() + ny * S.moon_y() + nz * S.moon_z() : F32))
  # Blinn-Phong highlight: it is what makes the rails and the roofs read
  +vx = (ex - px : F32)
  +vy = (ey - py : F32)
  +vz = (ez - pz : F32)
  +il = (1.0 / F32.sqrt((vx * vx + vy * vy + vz * vz : F32)) : F32)
  +hx = (S.moon_x() + vx * il : F32)
  +hy = (S.moon_y() + vy * il : F32)
  +hz = (S.moon_z() + vz * il : F32)
  +ih = (1.0 / F32.sqrt((hx * hx + hy * hy + hz * hz : F32)) : F32)
  +nh = F32.max(0.0, ((nx * hx + ny * hy + nz * hz : F32) * ih : F32))
  +spec = (F32.pow(nh, 48.0) * gloss(mat) * 0.55 : F32)
  +winl = win.light.go(px, py, pz, nx, ny, nz, wins, V3{0.0, 0.0, 0.0})
  +hl = head.light(px, py, pz, nx, ny, nz, head)
  +emis = emissive(mat)
  +ltr = (lr + 0.40 * lam * 1.15 + 0.55 * spec + V3.px(winl)
    + V3.px(hl) : F32)
  +ltg = (lg + 0.47 * lam * 1.15 + 0.62 * spec + V3.py(winl)
    + V3.py(hl) : F32)
  +ltb = (lb + 0.66 * lam * 1.15 + 0.82 * spec + V3.pz(winl)
    + V3.pz(hl) : F32)
  # the demo's procedural grain only bites on unlit, nearby surfaces
  +amt = ((1.0 - S.one.if(F32.is_ge(emis, 0.01)))
    * (1.0 - S.smooth(15.0, 100.0, dist) : F32) : F32)
  +gr = (1.0 - amt * S.grain(px, pz) * 0.12 : F32)
  +cr = (ar * ltr * gr + ar * emis : F32)
  +cg = (ag * ltg * gr + ag * emis : F32)
  +cb = (ab * ltb * gr + ab * emis : F32)
  +tr = (cr / (1.0 + cr * 0.38 : F32) : F32)
  +tg = (cg / (1.0 + cg * 0.38 : F32) : F32)
  +tb = (cb / (1.0 + cb * 0.38 : F32) : F32)
  +f = F32.clamp((1.0 - F32.exp((0.0 - F32.square(
    (dist * S.fog_density() : F32)) : F32)) : F32), 0.0, 1.0)
  Color.pack((tr + (S.fog_r() - tr : F32) * f : F32),
    (tg + (S.fog_g() - tg : F32) * f : F32),
    (tb + (S.fog_b() - tb : F32) * f : F32))




# The demo's sky pass: three-stop gradient, Milky Way band, a small moon with
# a wide halo, low clouds, a weld into the fog and two ridge lines; the stars
# are added last, because in the demo they are a separate additive pass.
def sky(dir: V3) -> U32:
  V3{+dx, +dy, +dz} = dir
  +h = F32.clamp(dy, (0.0 - 1.0 : F32), 1.0)
  +up = S.smooth(0.18, 0.85, h)
  +dn = S.smooth((0.0 - 0.05 : F32), 0.18, h)
  +hi = S.one.if(F32.is_gt(h, 0.18))
  +br = S.mix(S.mix(0.150, 0.045, dn), S.mix(0.045, 0.014, up), hi)
  +bg = S.mix(S.mix(0.135, 0.061, dn), S.mix(0.061, 0.020, up), hi)
  +bb = S.mix(S.mix(0.190, 0.126, dn), S.mix(0.126, 0.052, up), hi)
  # Milky Way: axis normalize(0.62, 0.42, -0.66), fbm3 at 7/unit
  +axis = (dx * 0.6211 + dy * 0.4207 - dz * 0.6612 : F32)
  +mcore = S.smooth(0.80, 1.0, (1.0 - F32.abs(axis) : F32))
  +cloud = S.fbm3((dx * 7.0 : F32), (dy * 7.0 : F32), (dz * 7.0 : F32))
  +milky = (mcore * (0.25 + cloud * 0.95) * S.smooth((0.0 - 0.02 : F32), 0.22, h) : F32)
  +mr = (br + 0.100 * milky : F32)
  +mg = (bg + 0.108 * milky : F32)
  +mb = (bb + 0.150 * milky : F32)
  # moon: narrow disc, wide halo, then the noisy limb
  +md = (dx * S.moon_x() + dy * S.moon_y() + dz * S.moon_z() : F32)
  +mdp = F32.max(0.0, md)
  +disc = (F32.pow(mdp, 420.0) * 0.32 : F32)
  +halo = (F32.pow(mdp, 14.0) * 0.30 : F32)
  +maria = S.vnoise3((dx * 320.0 : F32), (dy * 320.0 : F32), (dz * 320.0 : F32))
  +e = (S.one.if(F32.is_gt(md, 0.99965)) * S.smooth(0.99965, 0.99985, md) : F32)
  +mr2 = S.mix((mr + 0.55 * disc + 0.24 * halo : F32),
    (0.90 * (0.80 + maria * 0.20) : F32), e)
  +mg2 = S.mix((mg + 0.62 * disc + 0.29 * halo : F32),
    (0.93 * (0.80 + maria * 0.20) : F32), e)
  +mb2 = S.mix((mb + 0.85 * disc + 0.45 * halo : F32),
    (0.88 * (0.80 + maria * 0.20) : F32), e)
  # low cloud deck near the horizon
  +cp = S.vnoise3((dx * 5.0 : F32), (dy * 5.0 : F32), (dz * 5.0 : F32))
  +cp2 = S.vnoise3((dx * 13.5 : F32), (dy * 13.5 : F32), (dz * 13.5 : F32))
  +clouds = S.smooth(0.50, 0.78, (cp * 0.7 + cp2 * 0.3 : F32))
  +cw = (clouds * 0.42 * S.smooth(0.02, 0.23, h) : F32)
  +cr2 = S.mix(mr2, 0.105, cw)
  +cg2 = S.mix(mg2, 0.135, cw)
  +cb2 = S.mix(mb2, 0.190, cw)
  # weld into the fog, then the two distant ridge lines
  +fh = (1.0 - S.smooth((0.0 - 0.06 : F32), 0.16, h) : F32)
  +fr2 = S.mix(cr2, S.fog_r(), fh)
  +fg2 = S.mix(cg2, S.fog_g(), fh)
  +fb2 = S.mix(cb2, S.fog_b(), fh)
  +az = F32.atan2(dx, dz)
  +ridge = (0.025 + F32.sin(az * 7.0) * 0.015 + F32.sin(az * 17.0 + 2.0) * 0.009
    : F32)
  +rw = (1.0 - S.smooth(ridge, (ridge + 0.004 : F32), h) : F32)
  +rr2 = S.mix(fr2, 0.060, rw)
  +rg2 = S.mix(fg2, 0.087, rw)
  +rb2 = S.mix(fb2, 0.128, rw)
  +ridge2 = (0.008 + F32.sin(az * 11.0 + 1.0) * 0.011 : F32)
  +nw = (1.0 - S.smooth(ridge2, (ridge2 + 0.003 : F32), h) : F32)
  +sr = S.mix(rr2, S.fog_r(), nw)
  +sg = S.mix(rg2, S.fog_g(), nw)
  +sb = S.mix(rb2, S.fog_b(), nw)
  +st = S.star(dx, dy, dz)
  Color.pack((sr + V3.px(st) : F32), (sg + V3.py(st) : F32),
    (sb + V3.pz(st) : F32))




# ---- one pixel -------------------------------------------------------

def pixel.hit(miss: Bool, +ex: F32, +ey: F32, +ez: F32, +dx: F32, +dy: F32,
  +dz: F32, +t: F32, dir: V3, cam: Cam, cars: List<&2, Car>, head: Head,
  wins: List<&2, V3>) -> U32:
  match miss:
    case True{}:
      sky(dir)
    case False{}:
      shade((ex + t * dx : F32), (ey + t * dy : F32), (ez + t * dz : F32),
        t, cam, cars, head, wins)




def pines.go(+px: F32, +py: F32, +pz: F32, ps: List<&2, Pine>, +d: F32)
  -> F32:
  match ps:
    case []:
      d
    case p <> rest:
      pines.go(px, py, pz, rest, Pine.sdf(px, py, pz, p, d))




def pines.if(far: Bool, +px: F32, +py: F32, +pz: F32, +tx: F32,
  +tdx: F32, +d: F32) -> F32:
  match far:
    case True{}:
      +i0 = S.cellidx(px)
      +j0 = S.cellidx(pz)
      +i1 = U32.add(i0, 1)
      +j1 = U32.add(j0, 1)
      a b c e = pine.cell(i0, j0, tx, tdx, pz)
        pine.cell(i1, j0, tx, tdx, pz)
        pine.cell(i0, j1, tx, tdx, pz)
        pine.cell(i1, j1, tx, tdx, pz)
      pines.go(px, py, pz, [a, b, c, e], d)
    case False{}:
      d




# ---- the field -------------------------------------------------------

def sdf(+px: F32, +py: F32, +pz: F32, cars: List<&2, Car>) -> F32:
  +tx = Track.x(pz)
  +ty = Track.y(pz)
  +tdx = Track.dx(pz)
  +alat = F32.abs((px - tx : F32))
  # The field is flat at terrain height (trackY - 0.9) as far as the eye sees:
  # the demo's hills are a deliberate simplification.  The ballast is only an
  # albedo band; the rails stand proud of it, at +-0.72, top trackY - 0.02.
  +grass = ((py - Track.grass(pz) : F32) * S.slope() : F32)
  +rail = (box((F32.abs((alat - 0.72 : F32)) - 0.075 : F32),
    (F32.abs((py - (ty - 0.10 : F32) : F32)) - 0.08 : F32), 0.0)
    * S.slope() : F32)
  +d0 = F32.min(grass, rail)
  +d1 = cars.if(F32.is_lt(alat, 8.0), px, py, pz, cars, d0)
  pines.if(F32.is_gt(alat, 9.0), px, py, pz, tx, tdx, d1)




# ---- marching --------------------------------------------------------

def march(+i: Nat, +stop: Bool, +ox: F32, +oy: F32, +oz: F32, +dx: F32,
  +dy: F32, +dz: F32, +t: F32, +cars: List<&2, Car>) -> F32:
  match i:
    case 0n:
      t
    case 1n+k:
      match stop:
        case True{}:
          t
        case False{}:
          +d = sdf((ox + t * dx : F32), (oy + t * dy : F32),
            (oz + t * dz : F32), cars)
          +t2 = (t + d : F32)
          march(k, (F32.is_lt(d, 0.02) || F32.is_gt(t2, 400.0) : Bool), ox,
            oy, oz, dx, dy, dz, t2, cars)




def trace(+ox: F32, +oy: F32, +oz: F32, dir: V3, cars: List<&2, Car>)
  -> F32:
  V3{dx, dy, dz} = dir
  march(80n, False{}, ox, oy, oz, dx, dy, dz, 0.02, cars)




def pixel(+x: U32, +y: U32, +cam: Cam, +cars: List<&2, Car>, +head: Head,
  +wins: List<&2, V3>) -> U32:
  Cam{ex, ey, ez, fx, fy, fz, rx, ry, rz, ux, uy, uz, cx, cy, sx, sy} = cam
  +dir = Cam.at(x, y, cam)
  +dx = V3.px(dir)
  +dy = V3.py(dir)
  +dz = V3.pz(dir)
  +t = trace(ex, ey, ez, dir, cars)
  pixel.hit(F32.is_gt(t, 390.0), ex, ey, ez, dx, dy, dz, t, dir, cam, cars,
    head, wins)




# ---- the frame -------------------------------------------------------
# One quadtree, built by a four-way parallel call at every level.  A `!` at
# the call site hands the whole tree to the GPU; without one it spreads over
# the CPU cores.  This is the only place work is split, and it is where every
# speedup in docs/benchmarks.md comes from.

def frame(+d: Nat, +x: U32, +y: U32, +cam: Cam, +cars: List<&2, Car>,
  +head: Head, +wins: List<&2, V3>) -> Image:
  match d:
    case 0n:
      Pix{pixel(x, y, cam, cars, head, wins)}
    case 1n+e:
      +k = U32.shln(1, e)
      +x1 = U32.add(x, k)
      +y1 = U32.add(y, k)
      a b c f = frame(e, x, y, cam, cars, head, wins)
        frame(e, x1, y, cam, cars, head, wins)
        frame(e, x, y1, cam, cars, head, wins)
        frame(e, x1, y1, cam, cars, head, wins)
      Qua{a, b, c, f}
