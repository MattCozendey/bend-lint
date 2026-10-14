# Ray tracing in a weekend, ported from raytracing-nim to Bend 2.
# Renders the random sphere scene to ray.tga (and ray.ppm with "ppm").
#
#   bend main.bend -o ray && ./ray [samples] [ppm]
#
# The image is split by a fork tree of parallel lets: each level sends
# the even rows of its set to one branch and the odd ones to the other,
# so every leaf gets rows from the whole height and the work stays
# balanced. The leaves are flat loops; the joins interleave rows back.
# LAWS.bend states that this tree renders the same rows as a sequential
# loop, and PROOF.bend proves it: bend PROOF.bend
import Base

# Config
# ------

def W() -> U32:
  1200

def H() -> U32:
  600

# fork levels: 2^9 = 512 interleaved row sets (fewer left threads idle)
def Depth() -> Nat:
  9n

def None() -> U32:
  4294967295

def Far() -> F32:
  1000000000.0

# Vec
# ---

type Vec is Data:
  Vec{x: F32, y: F32, z: F32}

type Ray is Data:
  Ray{a: Vec, b: Vec}

def pick(c: Bool, a: F32, b: F32) -> F32:
  match c:
    case True{}:
      a
    case False{}:
      b

def word(c: Bool, a: U32, b: U32) -> U32:
  match c:
    case True{}:
      a
    case False{}:
      b

def vpick(c: Bool, a: Vec, b: Vec) -> Vec:
  match c:
    case True{}:
      a
    case False{}:
      b

def Vec.zero() -> Vec:
  Vec{0.0, 0.0, 0.0}

def Vec.unit() -> Vec:
  Vec{1.0, 1.0, 1.0}

def Vec.add(+a: Vec, +b: Vec) -> Vec:
  Vec{ax, ay, az} = a
  Vec{bx, by, bz} = b
  Vec{(ax + bx : F32), (ay + by : F32), (az + bz : F32)}

def Vec.sub(+a: Vec, +b: Vec) -> Vec:
  Vec{ax, ay, az} = a
  Vec{bx, by, bz} = b
  Vec{(ax - bx : F32), (ay - by : F32), (az - bz : F32)}

def Vec.mul(+a: Vec, +b: Vec) -> Vec:
  Vec{ax, ay, az} = a
  Vec{bx, by, bz} = b
  Vec{(ax * bx : F32), (ay * by : F32), (az * bz : F32)}

def Vec.neg(+a: Vec) -> Vec:
  Vec{x, y, z} = a
  Vec{(0.0 - x : F32), (0.0 - y : F32), (0.0 - z : F32)}

def Vec.scale(+a: Vec, +k: F32) -> Vec:
  Vec{x, y, z} = a
  Vec{(x * k : F32), (y * k : F32), (z * k : F32)}

def Vec.div(+a: Vec, +k: F32) -> Vec:
  Vec{x, y, z} = a
  Vec{(x / k : F32), (y / k : F32), (z / k : F32)}

def Vec.dot(+a: Vec, +b: Vec) -> F32:
  Vec{ax, ay, az} = a
  Vec{bx, by, bz} = b
  (ax * bx + ay * by + az * bz : F32)

def Vec.cross(+a: Vec, +b: Vec) -> Vec:
  Vec{ax, ay, az} = a
  Vec{bx, by, bz} = b
  Vec{(ay * bz - az * by : F32), (az * bx - ax * bz : F32),
    (ax * by - ay * bx : F32)}

def Vec.sqlen(+v: Vec) -> F32:
  Vec.dot(v, v)

def Vec.len(+v: Vec) -> F32:
  F32.sqrt(Vec.dot(v, v))

def Vec.normalize(+v: Vec) -> Vec:
  Vec.scale(v, (1.0 / (Vec.len(v) + 0.0001) : F32))

def Vec.reflect(+v: Vec, +n: Vec) -> Vec:
  Vec.sub(v, Vec.scale(n, (Vec.dot(v, n) * 2.0 : F32)))

def Ray.at(+ray: Ray, +t: F32) -> Vec:
  Ray{a, b} = ray
  Vec.add(a, Vec.scale(b, t))

# Random
# ------
# Bend is pure, so there is no global rand(): a xorshift32 state word is
# threaded through every call that draws. A state is fresh until read;
# Rng.u reads it, Rng.next steps past it. Each pixel seeds its own state
# from its index, so pixels are independent and can render in parallel.

def Rng.hash(+x: U32) -> U32:
  +a = (U32.xor(x, U32.shrn(x, 16n)) * 2146121005 : U32)
  +b = (U32.xor(a, U32.shrn(a, 15n)) * 2221713035 : U32)
  U32.xor(b, U32.shrn(b, 16n))

def Rng.next(+s: U32) -> U32:
  +a = U32.xor(s, U32.shln(s, 13n))
  +b = U32.xor(a, U32.shrn(a, 17n))
  U32.xor(b, U32.shln(b, 5n))

def Rng.next2(+s: U32) -> U32:
  Rng.next(Rng.next(s))

def Rng.next3(+s: U32) -> U32:
  Rng.next(Rng.next(Rng.next(s)))

# rand(1f): the float in [0, 1) of a state
def Rng.u(+s: U32) -> F32:
  (U32.to_f32(U32.shrn(s, 8n)) / 16777216.0 : F32)

def Rng.at(+h: U32, +j: U32) -> F32:
  Rng.u(Rng.hash((h + j : U32)))

# the point in [-1, 1]^3 drawn from s, next(s) and next2(s)
def Rng.vec3(+s: U32) -> Vec:
  +s1 = Rng.next(s)
  Vec{(2.0 * Rng.u(s) - 1.0 : F32), (2.0 * Rng.u(s1) - 1.0 : F32),
    (2.0 * Rng.u(Rng.next(s1)) - 1.0 : F32)}

def Rng.vec2(+s: U32) -> Vec:
  Vec{(2.0 * Rng.u(s) - 1.0 : F32), (2.0 * Rng.u(Rng.next(s)) - 1.0 : F32),
    0.0}

# randInSphere and randInDisk: the state whose point is accepted (read
# it with vec3 / vec2, then step past it with next3 / next2). As in
# v3.nim, a point is accepted when it lies outside the unit ball; kept so
# the image matches the original.
def Rng.in_sphere(fuel: Nat, done: Bool, +s: U32) -> U32:
  match fuel done:
    case _ True{}:
      s
    case 0n False{}:
      s
    case 1n+k False{}:
      +c = Rng.next3(s)
      Rng.in_sphere(k, (Vec.sqlen(Rng.vec3(c)) >= 1.0 : F32), c)

def Rng.in_disk(fuel: Nat, done: Bool, +s: U32) -> U32:
  match fuel done:
    case _ True{}:
      s
    case 0n False{}:
      s
    case 1n+k False{}:
      +c = Rng.next2(s)
      Rng.in_disk(k, (Vec.sqlen(Rng.vec2(c)) >= 1.0 : F32), c)

def Rng.sphere(+s: U32) -> U32:
  Rng.in_sphere(64n, (Vec.sqlen(Rng.vec3(s)) >= 1.0 : F32), s)

def Rng.disk(+s: U32) -> U32:
  Rng.in_disk(64n, (Vec.sqlen(Rng.vec2(s)) >= 1.0 : F32), s)

# Camera
# ------

type Cam is Data:
  Cam{origin: Vec, corner: Vec, hor: Vec, vert: Vec, u: Vec, v: Vec,
    lens: F32}

def Cam.new(+from: Vec, +at: Vec) -> Cam:
  +vup = {Vec{0.0, 1.0, 0.0} : Vec}
  +dist = Vec.sub(from, at)
  +w = Vec.normalize(dist)
  +u = Vec.normalize(Vec.cross(vup, w))
  +v = Vec.cross(w, u)
  +fd = Vec.len(dist)
  +hh = F32.tan((20.0 * F32.pi() / 180.0 / 2.0 : F32))
  +hw = (2.0 * hh : F32)
  # v points up; rows go top to bottom, so the corner is the top left
  # and the vertical span points down
  +corner = Vec.sub(Vec.add(Vec.sub(from, Vec.scale(u, (hw * fd : F32))),
    Vec.scale(v, (hh * fd : F32))), Vec.scale(w, fd))
  Cam{from, corner, Vec.scale(u, (hw * fd * 2.0 : F32)),
    Vec.scale(v, (0.0 - hh * fd * 2.0 : F32)), u, v, (0.005 / 2.0 : F32)}

# d: the randInDisk() point for the lens
def Cam.ray(+cam: Cam, +pu: F32, +pv: F32, d: Vec) -> Ray:
  Cam{origin, corner, hor, vert, u, v, lens} = cam
  Vec{dx, dy, dz} = d
  +offset = Vec.add(Vec.scale(u, (dx * lens : F32)),
    Vec.scale(v, (dy * lens : F32)))
  +uh = Vec.scale(hor, pu)
  +vv = Vec.sub(Vec.sub(Vec.scale(vert, pv), origin), offset)
  Ray{Vec.sub(origin, offset), Vec.add(corner, Vec.add(uh, vv))}

# Scene
# -----

type Mat is Data:
  Lambertian{albedo: Vec}
  Metalic{albedo: Vec, fuzzy: F32}
  Dielectric{refraction: F32}

type Sphere is Data:
  Sphere{o: Vec, r: F32, mat: Mat}

type Scene is Data:
  Void{}
  Ball{s: Sphere, next: Scene}

# a cell's material from its random numbers h + 3, h + 4, ..
def Mat.pick(lam: Bool, met: Bool, +h: U32) -> Mat:
  match lam met:
    case True{} _:
      Lambertian{Vec{(Rng.at(h, 3) * Rng.at(h, 4) : F32),
        (Rng.at(h, 5) * Rng.at(h, 6) : F32),
        (Rng.at(h, 7) * Rng.at(h, 8) : F32)}}
    case False{} True{}:
      Metalic{Vec{(0.5 * (Rng.at(h, 3) + 1.0) : F32),
        (0.5 * (Rng.at(h, 4) + 1.0) : F32),
        (0.5 * (Rng.at(h, 5) + 1.0) : F32)}, 0.01}
    case False{} False{}:
      Dielectric{1.5}

def Scene.add(keep: Bool, sp: Sphere, rest: Scene) -> Scene:
  match keep:
    case True{}:
      Ball{sp, rest}
    case False{}:
      rest

# the 22 x 22 grid of small spheres, cell k at (k / 22 - 11, k % 22 - 11);
# cell k draws its random numbers from the hashes of 16 k + 1000 + j
def Scene.random(n: Nat, +k: U32, acc: Scene) -> Scene:
  match n:
    case 0n:
      acc
    case 1n+m:
      +h = (k * 16 + 1000 : U32)
      +mp = Rng.at(h, 0)
      +cx = (U32.to_f32((k / 22 : U32)) - 11.0 + 0.9 + Rng.at(h, 1) : F32)
      +cz = (U32.to_f32((k % 22 : U32)) - 11.0 + 0.9 + Rng.at(h, 2) : F32)
      +c = {Vec{cx, 0.2, cz} : Vec}
      +far = (Vec.len(Vec.sub(c, Vec{4.0, 0.2, 0.0})) > 0.9 : F32)
      +cy = (0.2 - 0.2 / 45.0 * Vec.len(c) : F32)
      Scene.random(m, (k + 1 : U32), Scene.add(far, Sphere{Vec{cx, cy, cz},
        0.2, Mat.pick((mp < 0.8 : F32), (mp < 0.95 : F32), h)}, acc))

def Scene.new() -> Scene:
  +big = {Ball{Sphere{Vec{0.0, 1.0, 0.0}, 1.0, Dielectric{1.5}},
    Ball{Sphere{Vec{(0.0 - 4.0 : F32), 1.0, 0.0}, 1.0,
      Lambertian{Vec{0.4, 0.2, 0.1}}},
    Ball{Sphere{Vec{4.0, 1.0, 0.0}, 1.0, Metalic{Vec{0.7, 0.6, 0.5}, 0.01}},
    Void{}}}} : Scene}
  Ball{Sphere{Vec{0.0, (0.0 - 1000.0 : F32), 0.0}, 1000.0,
    Lambertian{Vec{0.5, 0.5, 0.5}}},
    Scene.random(484n, 0, big)}

# Hits
# ----

# the nearest t of the sphere in (0.01, hi), or hi on a miss
def Sphere.hit(s: Sphere, +ray: Ray, +hi: F32) -> F32:
  Sphere{+o, +r, mat} = s
  Ray{+a, +b} = ray
  +oc = Vec.sub(a, o)
  +qa = Vec.dot(b, b)
  +qb = Vec.dot(oc, b)
  +qc = (Vec.dot(oc, oc) - r * r : F32)
  +disc = (qb * qb - qa * qc : F32)
  +sq = F32.sqrt(disc)
  +tm = ((0.0 - qb - sq) / qa : F32)
  +tp = ((0.0 - qb + sq) / qa : F32)
  pick(((disc > 0.0) && (tm > 0.01) && (tm < hi) : F32), tm,
    pick(((disc > 0.0) && (tp > 0.01) && (tp < hi) : F32), tp, hi))

type Hit is Data:
  Hit{t: F32, idx: U32}

# one flat loop over the scene: the nearest t and the index of its sphere
def Scene.hit(scene: Scene, +i: U32, +ray: Ray, +closest: F32, +best: U32) ->
  Hit:
  match scene:
    case Void{}:
      Hit{closest, best}
    case Ball{s, next}:
      +t = Sphere.hit(s, ray, closest)
      Scene.hit(next, (i + 1 : U32), ray, t, word((t < closest : F32), i, best))

# Materials
# ---------

type St is Data:
  Bounce{ray: Ray, acc: Vec, seed: U32}
  Stop{c: Vec, seed: U32}

def Mat.keep(ok: Bool, ray: Ray, acc: Vec, s: U32) -> St:
  match ok:
    case True{}:
      Bounce{ray, acc, s}
    case False{}:
      Stop{Vec.zero(), s}

def schlick(+cosine: F32, +ri: F32) -> F32:
  +r0 = ((1.0 - ri) / (1.0 + ri) : F32)
  +r = (r0 * r0 : F32)
  (r + (1.0 - r) * F32.pow((1.0 - cosine : F32), 5.0) : F32)

def Mat.scatter(mat: Mat, +ray: Ray, +p: Vec, +n: Vec, +acc: Vec, s: U32) ->
  St:
  match mat:
    case Lambertian{albedo}:
      +c = Rng.sphere(s)
      +target = Vec.add(Vec.add(p, n), Rng.vec3(c))
      Bounce{Ray{p, Vec.sub(target, p)}, Vec.mul(acc, albedo), Rng.next3(c)}
    case Metalic{albedo, fuzzy}:
      Ray{a, b} = ray
      +c = Rng.sphere(s)
      +d = Vec.add(Vec.reflect(Vec.normalize(b), n),
        Vec.scale(Rng.vec3(c), fuzzy))
      Mat.keep((Vec.dot(d, n) > 0.0 : F32), Ray{p, d}, Vec.mul(acc, albedo),
        Rng.next3(c))
    case Dielectric{+refraction}:
      Ray{a, +b} = ray
      +bn = Vec.dot(b, n)
      +inside = (bn > 0.0 : F32)
      +out = vpick(inside, Vec.neg(n), n)
      +ni = pick(inside, refraction, (1.0 / refraction : F32))
      +cos0 = (0.0 - bn / Vec.len(b) : F32)
      +cosine = pick(inside, (0.0 - cos0 * refraction : F32), cos0)
      +nv = Vec.normalize(b)
      +dt = Vec.dot(nv, out)
      +disc = (1.0 - ni * ni * (1.0 - dt * dt) : F32)
      +refr = Vec.sub(Vec.scale(Vec.sub(nv, Vec.scale(out, dt)), ni),
        Vec.scale(out, F32.sqrt(disc)))
      +s1 = s
      +through = ((disc > 0.0) && (Rng.u(s1) > schlick(cosine, refraction))
        : F32)
      Bounce{Ray{p, vpick(through, refr, Vec.reflect(b, n))}, acc, Rng.next(s1)}

def Sphere.scatter(sp: Sphere, +t: F32, +ray: Ray, +acc: Vec, s: U32) -> St:
  Sphere{o, r, mat} = sp
  +p = Ray.at(ray, t)
  Mat.scatter(mat, ray, p, Vec.div(Vec.sub(p, o), r), acc, s)

# walks to the sphere at idx and scatters the ray off it
def Scene.scatter(
  scene: Scene, here: Bool, +idx: U32, +t: F32, +ray: Ray, +acc: Vec, s: U32
) -> St:
  match scene here:
    case Ball{sp, next} True{}:
      Sphere.scatter(sp, t, ray, acc, s)
    case Ball{sp, next} False{}:
      Scene.scatter(next, U32.is_eq(idx, 1), (idx - 1 : U32), t, ray, acc, s)
    case Void{} _:
      Stop{Vec.zero(), s}

# Color
# -----

def sky.of(v: Vec) -> Vec:
  Vec{x, y, z} = v
  +t = (0.5 * (y + 1.0) : F32)
  Vec.add(Vec.scale(Vec.unit(), (1.0 - t : F32)),
    Vec.scale(Vec{0.5, 0.7, 1.0}, t))

def sky(+d: Vec) -> Vec:
  sky.of(Vec.normalize(d))

def step.go(
  miss: Bool, +scene: Scene, +idx: U32, +t: F32, +ray: Ray, +acc: Vec, s: U32
) -> St:
  match miss:
    case True{}:
      Ray{a, b} = ray
      Stop{Vec.mul(acc, sky(b)), s}
    case False{}:
      Scene.scatter(scene, U32.is_eq(idx, 0), idx, t, ray, acc, s)

def step.hit(h: Hit, +scene: Scene, +ray: Ray, +acc: Vec, s: U32) -> St:
  Hit{t, +idx} = h
  step.go(U32.is_eq(idx, None()), scene, idx, t, ray, acc, s)

def step(+scene: Scene, +ray: Ray, +acc: Vec, s: U32) -> St:
  step.hit(Scene.hit(scene, 0, ray, Far(), None()), scene, ray, acc, s)

def last.go(miss: Bool, +ray: Ray, +acc: Vec) -> Vec:
  match miss:
    case True{}:
      Ray{a, b} = ray
      Vec.mul(acc, sky(b))
    case False{}:
      Vec.zero()

def last(h: Hit, +ray: Ray, +acc: Vec) -> Vec:
  Hit{t, idx} = h
  last.go(U32.is_eq(idx, None()), ray, acc)

# a pixel's running sum of samples and its generator state
type Col is Data:
  Col{sum: Vec, seed: U32}

# color() of main.nim, added to sum: n bounces left; the hit after the
# last one is black
def trace(n: Nat, st: St, +sum: Vec, +scene: Scene) -> Col:
  match n st:
    case _ Stop{c, s}:
      Col{Vec.add(sum, c), s}
    case 0n Bounce{+ray, acc, s}:
      Col{Vec.add(sum, last(Scene.hit(scene, 0, ray, Far(), None()), ray,
        acc)), s}
    case 1n+k Bounce{ray, acc, s}:
      trace(k, step(scene, ray, acc, s), sum, scene)

def sample(+x: U32, +y: U32, col: Col, +cam: Cam, +scene: Scene) -> Col:
  Col{sum, +s} = col
  +d = Rng.disk(Rng.next2(s))
  +ray = Cam.ray(cam,
    ((U32.to_f32(x) + Rng.u(s)) / U32.to_f32(W()) : F32),
    ((U32.to_f32(y) + Rng.u(Rng.next(s))) / U32.to_f32(H()) : F32),
    Rng.vec2(d))
  trace(49n, Bounce{ray, Vec.unit(), Rng.next2(d)}, sum, scene)

def samples(n: Nat, +x: U32, +y: U32, col: Col, +cam: Cam, +scene: Scene) ->
  Col:
  match n:
    case 0n:
      col
    case 1n+k:
      samples(k, x, y, sample(x, y, col, cam, scene), cam, scene)

def pack(v: Vec) -> U32:
  Vec{r, g, b} = v
  (F32.to_u32((255.99 * F32.sqrt(r) : F32)) << 16n
    .|. F32.to_u32((255.99 * F32.sqrt(g) : F32)) << 8n
    .|. F32.to_u32((255.99 * F32.sqrt(b) : F32)) : U32)

def Col.mean(col: Col, +ns: U32) -> Vec:
  Col{sum, s} = col
  Vec.div(sum, U32.to_f32(ns))

# the averaged, gamma-2 color of a pixel as 0xRRGGBB
def pixel(+x: U32, +y: U32, +ns: U32, +cam: Cam, +scene: Scene) -> U32:
  +seed = Rng.hash((y * W() + x + 1 : U32))
  pack(Col.mean(samples(U32.to_nat(ns), x, y, Col{Vec.zero(), seed}, cam,
    scene), ns))

# Render
# ------
# The rows to render are a list of row indices, and render forks on that
# list: the rows at even positions go to one branch, the rows at odd
# positions to the other, and the join merges them back in order. Every
# leaf gets rows from the whole height, so the work stays balanced. Being
# plain list work, the fork tree is something LAWS.bend can state and
# PROOF.bend can prove: it returns the same rows as the sequential rows().

type Rows is Data:
  RNil{}
  RCon{row: List<&2, U32>, next: Rows}

# a row, right to left onto acc: one flat loop
def row(
  n: Nat, +x: U32, +y: U32, +ns: U32, +cam: Cam, +scene: Scene,
  acc: List<&2, U32>
) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +x1 = (x - 1 : U32)
      row(k, x1, y, ns, cam, scene, pixel(x1, y, ns, cam, scene) <> acc)

# the image line y: its first w pixels (w is W() at run time; the laws
# keep it abstract, so the checker never unrolls a line)
def line(+w: U32, +y: U32, +ns: U32, +cam: Cam, +scene: Scene) ->
  List<&2, U32>:
  row(U32.to_nat(w), w, y, ns, cam, scene, [])

# the lines ys, one after another: the sequential render
def rows(ys: List<&2, U32>, +w: U32, +ns: U32, +cam: Cam, +scene: Scene) ->
  Rows:
  match ys:
    case []:
      RNil{}
    case y <> t:
      RCon{line(w, y, ns, cam, scene), rows(t, w, ns, cam, scene)}

# the items at even positions (0, 2, ..) and at odd positions (1, 3, ..)
def evens(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case []:
      []
    case x <> []:
      [x]
    case x <> y <> t:
      x <> evens(t)

def odds(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case []:
      []
    case x <> []:
      []
    case x <> y <> t:
      y <> odds(t)

# merges the rows at even positions with the rows at odd positions
def interleave(xs: Rows, ys: Rows) -> Rows:
  match xs ys:
    case RCon{x, xt} RCon{y, yt}:
      RCon{x, RCon{y, interleave(xt, yt)}}
    case RCon{x, xt} RNil{}:
      RCon{x, xt}
    case RNil{} RCon{y, yt}:
      RCon{y, yt}
    case RNil{} RNil{}:
      RNil{}

# the lines ys, forked d levels deep: the parallel render
def render(
  d: Nat, +ys: List<&2, U32>, +w: U32, +ns: U32, +cam: Cam, +scene: Scene
) -> Rows:
  match d:
    case 0n:
      rows(ys, w, ns, cam, scene)
    case 1n++p:
      a b = render(p, evens(ys), w, ns, cam, scene)
        render(p, odds(ys), w, ns, cam, scene)
      interleave(a, b)

# the row indices y - n, .., y - 1 onto acc
def indices(n: Nat, +y: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +y1 = (y - 1 : U32)
      indices(k, y1, y1 <> acc)

# Image files
# -----------

def Tga.header() -> List<&2, U32>:
  [0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, (W() .&. 255 : U32), (W() >> 8n : U32),
    (H() .&. 255 : U32), (H() >> 8n : U32), 24, 0]

def Tga.bgr(+p: U32, rest: List<&2, U32>) -> List<&2, U32>:
  (p .&. 255 : U32) <> (p >> 8n .&. 255 : U32) <> (p >> 16n : U32) <> rest

def Tga.row(px: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match px:
    case []:
      acc
    case p <> t:
      Tga.bgr(p, Tga.row(t, acc))

# targa stores rows bottom up: folding each row onto the front reverses them
def Tga.body(rs: Rows, acc: List<&2, U32>) -> List<&2, U32>:
  match rs:
    case RNil{}:
      acc
    case RCon{r, t}:
      Tga.body(t, Tga.row(r, acc))

def ascii(s: String, acc: List<&2, U32>) -> List<&2, U32>:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{c}, t}:
      c <> ascii(t, acc)

def Ppm.px(+p: U32, rest: List<&2, U32>) -> List<&2, U32>:
  ascii(U32.show((p >> 16n : U32)) ++ " " ++ U32.show((p >> 8n .&. 255 : U32))
    ++ " " ++ U32.show((p .&. 255 : U32)) ++ "\n", rest)

def Ppm.row(px: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match px:
    case []:
      acc
    case p <> t:
      Ppm.px(p, Ppm.row(t, acc))

def Ppm.body(rs: Rows) -> List<&2, U32>:
  match rs:
    case RNil{}:
      []
    case RCon{r, t}:
      Ppm.row(r, Ppm.body(t))

def Ppm.file(rs: Rows) -> List<&2, U32>:
  ascii("P3\n" ++ U32.show(W()) ++ " " ++ U32.show(H()) ++ "\n255\n",
    Ppm.body(rs))

# Main
# ----

type Opts is Data:
  Opts{ns: U32, ppm: Bool}

def Opts.rest(ns: U32, args: List<String>) -> Opts:
  match args:
    case []:
      Opts{ns, False{}}
    case a <> t:
      Opts{ns, String.eq(a, "ppm")}

def Opts.parse(args: List<String>) -> Opts:
  match args:
    case []:
      Opts{64, False{}}
    case a <> t:
      Opts.rest(Maybe.default(&2, U32, U32.read(a), 64), t)

def wrote(pair: File & Result<&1, &1, U32 & String, Unit>) -> IO(File):
  (file, result) = pair
  do IO<File>:
    IO.pass(Unit, result)
    return file

def save(path: String, bytes: List<&2, U32>) -> IO(Unit):
  +name = path
  do IO<Unit>:
    f : File <- IO.try(File, File.open(name, "w"))
    p : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, bytes)
    f : File <- wrote(p)
    File.close(f)
    IO.print("wrote " ++ name)

def save.ppm(ppm: Bool, rs: Rows) -> IO(Unit):
  match ppm:
    case True{}:
      save("ray.ppm", Ppm.file(rs))
    case False{}:
      IO.pure(Unit, Unit{})

def save.all(ppm: Bool, t0: Nat, +rs: Rows) -> IO(Unit):
  do IO<Unit>:
    t1 : Nat <- IO.now()
    IO.print("rendered in " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
    save("ray.tga", List.append(&2, U32, Tga.header(), Tga.body(rs, [])))
    save.ppm(ppm, rs)

def run(opts: Opts) -> IO(Unit):
  Opts{+ns, ppm} = opts
  +cam = Cam.new(Vec{(0.0 - 1.0 : F32), 1.0, 18.0},
    Vec{0.0, 1.0, (0.0 - 1.0 : F32)})
  +scene = Scene.new()
  do IO<Unit>:
    IO.print("rendering " ++ U32.show(W()) ++ "x" ++ U32.show(H()) ++ " at "
      ++ U32.show(ns) ++ " samples per pixel")
    t0 : Nat <- IO.now()
    save.all(ppm, t0, render(Depth(), indices(U32.to_nat(H()), H(), []), W(),
      ns, cam, scene))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(Opts.parse(args))
