import Base
import ../shared/grid.bend as G

type Vec is Data:
  Vec{x: F32, y: F32, z: F32}

type Sphere is Data:
  Sphere{center: Vec, radius: F32, color: Vec, mirror: F32}

type Hit is Data:
  Hit{distance: F32, normal: Vec, color: Vec, mirror: F32}

def add(a: Vec, b: Vec) -> Vec:
  Vec{x, y, z} = a
  Vec{u, v, w} = b
  Vec{(x + u : F32), (y + v : F32), (z + w : F32)}

def scale(a: Vec, +k: F32) -> Vec:
  Vec{x, y, z} = a
  Vec{(x * k : F32), (y * k : F32), (z * k : F32)}

def sub(a: Vec, b: Vec) -> Vec:
  add(a, scale(b, (0.0 - 1.0 : F32)))

def dot(a: Vec, b: Vec) -> F32:
  Vec{x, y, z} = a
  Vec{u, v, w} = b
  (x * u + y * v + z * w : F32)

def unit(+a: Vec) -> Vec:
  scale(a, (1.0 / F32.sqrt(F32.max(0.00000001, dot(a, a))) : F32))

def vy(a: Vec) -> F32:
  Vec{x, y, z} = a
  y

def distance(h: Hit) -> F32:
  Hit{d, n, c, r} = h
  d

def normal(h: Hit) -> Vec:
  Hit{d, n, c, r} = h
  n

def color(h: Hit) -> Vec:
  Hit{d, n, c, r} = h
  c

def mirror(h: Hit) -> F32:
  Hit{d, n, c, r} = h
  r

def sphere(i: Nat) -> Sphere:
  match i:
    case 0n:
      Sphere{Vec{(0.0 - 1.4 : F32), 0.85, 2.4}, 0.85, Vec{0.95, 0.22, 0.13}, 0.22}
    case 1n:
      Sphere{Vec{0.6, 1.05, 3.2}, 1.05, Vec{0.10, 0.65, 0.68}, 0.55}
    case 2n:
      Sphere{Vec{1.8, 0.5, 1.0}, 0.5, Vec{1.0, 0.65, 0.10}, 0.32}
    case _:
      Sphere{Vec{(0.0 - 0.25 : F32), 0.35, 0.5}, 0.35, Vec{0.8, 0.85, 0.95}, 0.88}

# Both roots are considered, including rays starting inside a sphere.
def roots(valid: Bool, +b: F32, disc: F32) -> F32:
  match valid:
    case False{}:
      1.0e20
    case True{}:
      +root = F32.sqrt(disc)
      +near = (0.0 - b - root : F32)
      +far = (0.0 - b + root : F32)
      Bool.pick(F32, (near > 0.001 : F32), near, Bool.pick(F32, (far > 0.001 : F32), far, 1.0e20))

def intersect(origin: Vec, +direction: Vec, center: Vec, +radius: F32) -> F32:
  +offset = sub(origin, center)
  +b = dot(offset, direction)
  +disc = (b * b - dot(offset, offset) + radius * radius : F32)
  roots((disc >= 0.0 : F32), b, disc)

def sphere_hit(s: Sphere, +origin: Vec, +direction: Vec) -> Hit:
  Sphere{+center, radius, tint, reflection} = s
  +d = intersect(origin, direction, center, radius)
  p = add(origin, scale(direction, F32.min(d, 1000.0)))
  Hit{d, unit(sub(p, center)), tint, reflection}

def floor_color(p: Vec) -> Vec:
  Vec{x, y, z} = p
  +parity = (F32.floor(x) + F32.floor(z) : F32)
  light = F32.is_eq((parity - 2.0 * F32.floor((parity / 2.0 : F32)) : F32), 0.0)
  Bool.pick(Vec, light, Vec{0.50, 0.55, 0.64}, Vec{0.12, 0.16, 0.23})

def floor_hit(valid: Bool, +origin: Vec, +direction: Vec) -> Hit:
  match valid:
    case False{}:
      Hit{1.0e20, Vec{0.0, 1.0, 0.0}, Vec{0.0, 0.0, 0.0}, 0.0}
    case True{}:
      +d = ((0.0 - vy(origin)) / vy(direction) : F32)
      Hit{d, Vec{0.0, 1.0, 0.0}, floor_color(add(origin, scale(direction, d))), 0.20}

def nearer(+a: Hit, +b: Hit) -> Hit:
  Bool.pick(Hit, (distance(a) < distance(b) : F32), a, b)

def nearest(fuel: Nat, +origin: Vec, +direction: Vec, hit: Hit) -> Hit:
  match fuel:
    case 0n:
      hit
    case 1n+ +p:
      nearest(p, origin, direction, nearer(hit, sphere_hit(sphere(p), origin, direction)))

def scene(+origin: Vec, +direction: Vec) -> Hit:
  floor = floor_hit((vy(direction) < (0.0 - 0.00001) : F32) && (vy(origin) > 0.001 : F32), origin, direction)
  nearest(4n, origin, direction, floor)

def sky(direction: Vec) -> Vec:
  +t = F32.clamp((0.5 + 0.5 * vy(direction) : F32), 0.0, 1.0)
  add(scale(Vec{0.65, 0.74, 0.88}, (1.0 - t : F32)), scale(Vec{0.12, 0.24, 0.48}, t))

def reflect(+direction: Vec, +n: Vec) -> Vec:
  sub(direction, scale(n, (2.0 * dot(direction, n) : F32)))

# Bool.pick evaluates both arguments. Match before shading or recursion so
# a ray that reaches the sky stops immediately, at any requested depth.
def trace_path(depth: Nat, missed: Bool, +origin: Vec, +direction: Vec, +hit: Hit) -> Vec:
  match depth:
    case 0n:
      sky(direction)
    case 1n+p:
      match missed:
        case True{}:
          sky(direction)
        case False{}:
          +d = distance(hit)
          +n = normal(hit)
          +point = add(add(origin, scale(direction, F32.min(d, 1000.0))), scale(n, 0.003))
          +light = unit(Vec{(0.0 - 0.6 : F32), 1.0, (0.0 - 0.5 : F32)})
          +shadow = (distance(scene(point, light)) < 100000.0 : F32)
          diffuse = Bool.pick(F32, shadow, 0.0, F32.max(0.0, dot(n, light)))
          +reflected = unit(reflect(direction, n))
          shine = Bool.pick(F32, shadow, 0.0, F32.pow(F32.max(0.0, dot(reflected, light)), 60.0))
          local = add(scale(color(hit), (0.12 + 0.88 * diffuse : F32)), scale(Vec{1.0, 1.0, 1.0}, (0.45 * shine : F32)))
          +kr = mirror(hit)
          +following = scene(point, reflected)
          bounced = trace_path(p, (distance(following) >= 100000.0 : F32), point, reflected, following)
          add(scale(local, (1.0 - kr : F32)), scale(bounced, kr))

# Bounded reflection depth. Pixel subtrees are independent GPU tasks.
def trace(depth: Nat, +origin: Vec, +direction: Vec) -> Vec:
  match depth:
    case 0n:
      sky(direction)
    case 1n+p:
      +hit = scene(origin, direction)
      trace_path((1n+p), (distance(hit) >= 100000.0 : F32), origin, direction, hit)

def channel(x: F32) -> U32:
  F32.to_u32((255.0 * F32.sqrt(F32.clamp(x, 0.0, 1.0)) : F32))

def pack(c: Vec) -> U32:
  Vec{r, g, b} = c
  ((channel(r) << 16n) .|. (channel(g) << 8n) .|. channel(b) : U32)

def sample(+x: F32, +y: F32, +width: F32, +height: F32, bounces: Nat) -> Vec:
  dx = ((2.0 * x / width - 1.0) * width / height * 0.55 : F32)
  dy = ((1.0 - 2.0 * y / height) * 0.55 - 0.12 : F32)
  trace(bounces, Vec{0.0, 1.4, (0.0 - 5.0 : F32)}, unit(Vec{dx, dy, 1.0}))

def pixel(+x: U32, +y: U32, +width: U32, +height: U32, +bounces: Nat) -> U32:
  +fx = U32.to_f32(x)
  +fy = U32.to_f32(y)
  +w = U32.to_f32(width)
  +h = U32.to_f32(height)
  a = sample((fx + 0.25 : F32), (fy + 0.25 : F32), w, h, bounces)
  b = sample((fx + 0.75 : F32), (fy + 0.25 : F32), w, h, bounces)
  c = sample((fx + 0.25 : F32), (fy + 0.75 : F32), w, h, bounces)
  d = sample((fx + 0.75 : F32), (fy + 0.75 : F32), w, h, bounces)
  pack(scale(add(add(a, b), add(c, d)), 0.25))

def render_pixel(valid: Bool, +index: U32, +width: U32, height: U32, bounces: Nat) -> G.Grid:
  match valid:
    case False{}:
      G.Leaf{0}
    case True{}:
      G.Leaf{pixel((index % width : U32), (index / width : U32), width, height, bounces)}

def render(depth: Nat, +offset: U32, +width: U32, +height: U32, +bounces: Nat) -> G.Grid:
  match depth:
    case 0n:
      render_pixel((offset < width * height : U32), offset, width, height, bounces)
    case 1n+ +p:
      a b = render(p, offset, width, height, bounces) render(p, (offset + (1 << p) : U32), width, height, bounces)
      G.Branch{a, b}
