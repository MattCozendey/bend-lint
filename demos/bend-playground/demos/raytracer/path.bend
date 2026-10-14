# Seeded Monte Carlo path tracing, inspired by Ray Tracing in One Weekend.
# Materials: 0 = Lambertian, 1 = rough metal, 2 = dielectric (IOR 1.5).
import Base
import ./ray.bend as V
import ../shared/grid.bend as G

type Tree is Data:
  Empty{}
  Ball{center: V.Vec, radius: F32, kind: U32, color: V.Vec, fuzz: F32}
  Branch{low: V.Vec, high: V.Vec, left: Tree, right: Tree}

type Hit is Data:
  Hit{distance: F32, normal: V.Vec, kind: U32, color: V.Vec, fuzz: F32, front: Bool}

type Scatter is Data:
  Absorb{}
  Bounce{direction: V.Vec, attenuation: V.Vec}

type Interval is Data:
  Interval{near: F32, far: F32}

def vec(x: F32, y: F32, z: F32) -> V.Vec:
  V.Vec{x,y,z}

def hash(+x: U32) -> U32:
  +a = ((x .^. (x >> 16n)) * 2146121005 : U32)
  +b = ((a .^. (a >> 15n)) * 2221713035 : U32)
  (b .^. (b >> 16n) : U32)

def random(seed: U32) -> F32:
  (U32.to_f32((hash(seed) >> 8n : U32)) / 16777216.0 : F32)

def random_vec(+seed: U32) -> V.Vec:
  V.Vec{random(seed), random((seed + 1 : U32)), random((seed + 2 : U32))}

def multiply(a: V.Vec, b: V.Vec) -> V.Vec:
  V.Vec{x,y,z} = a
  V.Vec{u,v,w} = b
  V.Vec{(x * u : F32), (y * v : F32), (z * w : F32)}

def cross(a: V.Vec, b: V.Vec) -> V.Vec:
  V.Vec{+x,+y,+z} = a
  V.Vec{+u,+v,+w} = b
  V.Vec{(y * w - z * v : F32), (z * u - x * w : F32), (x * v - y * u : F32)}

# Uniform direction on the sphere, without an unbounded rejection loop.
def random_unit(+seed: U32) -> V.Vec:
  +z = (2.0 * random(seed) - 1.0 : F32)
  +angle = (6.283185307 * random((seed + 1 : U32)) : F32)
  +r = F32.sqrt(F32.max(0.0, (1.0 - z * z : F32)))
  V.Vec{(r * F32.cos(angle) : F32), (r * F32.sin(angle) : F32), z}

def miss() -> Hit:
  Hit{1.0e20, V.Vec{0.0,1.0,0.0}, 0, V.Vec{0.0,0.0,0.0}, 0.0, True{}}

def distance(h: Hit) -> F32:
  Hit{d,n,k,c,f,front} = h
  d

def nearer(+a: Hit, +b: Hit) -> Hit:
  Bool.pick(Hit, (distance(a) < distance(b) : F32), a, b)

def ball_hit(+center: V.Vec, +radius: F32, kind: U32, color: V.Vec, fuzz: F32, +origin: V.Vec, +direction: V.Vec) -> Hit:
  +d = V.intersect(origin, direction, center, radius)
  +outward = V.scale(V.sub(V.add(origin,V.scale(direction,F32.min(d,10000.0))),center), (1.0 / radius : F32))
  +front = (V.dot(direction,outward) < 0.0 : F32)
  Hit{d, Bool.pick(V.Vec,front,outward,V.scale(outward,(0.0 - 1.0 : F32))), kind,color,fuzz,front}

def slab_parallel(inside: Bool) -> Interval:
  match inside:
    case True{}:
      Interval{(0.0 - 1.0e20 : F32),1.0e20}
    case False{}:
      Interval{1.0e20,(0.0 - 1.0e20 : F32)}

def slab_case(parallel: Bool, +low: F32, +high: F32, +origin: F32, +direction: F32) -> Interval:
  match parallel:
    case True{}:
      slab_parallel((origin >= low : F32) && (origin <= high : F32))
    case False{}:
      +a = ((low - origin) / direction : F32)
      +b = ((high - origin) / direction : F32)
      Interval{F32.min(a,b),F32.max(a,b)}

def slab(+low: F32, +high: F32, +origin: F32, +direction: F32) -> Interval:
  slab_case((F32.abs(direction) < 0.00000001 : F32),low,high,origin,direction)

def near(i: Interval) -> F32:
  Interval{n,f} = i
  n

def far(i: Interval) -> F32:
  Interval{n,f} = i
  f

def box_hit(low: V.Vec, high: V.Vec, origin: V.Vec, direction: V.Vec, limit: F32) -> Bool:
  V.Vec{lx,ly,lz} = low
  V.Vec{hx,hy,hz} = high
  V.Vec{ox,oy,oz} = origin
  V.Vec{dx,dy,dz} = direction
  +a = slab(lx,hx,ox,dx)
  +b = slab(ly,hy,oy,dy)
  +c = slab(lz,hz,oz,dz)
  (F32.max(0.001,F32.max(near(a),F32.max(near(b),near(c)))) <= F32.min(limit,F32.min(far(a),F32.min(far(b),far(c)))) : F32)

def bounds(tree: Tree, origin: V.Vec, direction: V.Vec, limit: F32) -> Bool:
  match tree:
    case Branch{low,high,left,right}:
      box_hit(low,high,origin,direction,limit)
    case _:
      True{}

def hit_tree(tree: Tree, valid: Bool, +origin: V.Vec, +direction: V.Vec, +best: Hit) -> Hit:
  match tree:
    case Empty{}:
      best
    case Ball{center,radius,kind,color,fuzz}:
      nearer(best,ball_hit(center,radius,kind,color,fuzz,origin,direction))
    case Branch{low,high,+left,+right}:
      match valid:
        case False{}:
          best
        case True{}:
          +first = hit_tree(left,bounds(left,origin,direction,distance(best)),origin,direction,best)
          hit_tree(right,bounds(right,origin,direction,distance(first)),origin,direction,first)

def material_ball_tag(kind: Nat, center: V.Vec, +seed: U32) -> Tree:
  match kind:
    case 0n:
      Ball{center,0.2,0,multiply(random_vec((seed + 3 : U32)),random_vec((seed + 6 : U32))),0.0}
    case 1n:
      Ball{center,0.2,1,V.add(V.Vec{0.5,0.5,0.5},V.scale(random_vec((seed + 3 : U32)),0.5)),(0.5 * random((seed + 6 : U32)) : F32)}
    case _:
      Ball{center,0.2,2,V.Vec{1.0,1.0,1.0},0.0}

def material_ball(kind: U32, center: V.Vec, +seed: U32) -> Tree:
  material_ball_tag(U32.to_nat(kind), center, seed)

def little_ball(valid: Bool, center: V.Vec, +seed: U32) -> Tree:
  match valid:
    case False{}:
      Empty{}
    case True{}:
      +choice = random(seed)
      material_ball(Bool.pick(U32,(choice < 0.8 : F32),0,Bool.pick(U32,(choice < 0.95 : F32),1,2)),center,seed)

def cell(+x: F32, +z: F32, +seed: U32) -> Tree:
  +center = vec((x + 0.1 + 0.8 * random((seed + 1 : U32)) : F32),0.2,(z + 0.1 + 0.8 * random((seed + 2 : U32)) : F32))
  +a = V.sub(center,V.Vec{(0.0 - 4.0 : F32),0.2,0.0})
  +b = V.sub(center,V.Vec{0.0,0.2,0.0})
  +c = V.sub(center,V.Vec{4.0,0.2,0.0})
  valid = (x >= (0.0 - 11.0) : F32) && (x < 11.0 : F32) && (z >= (0.0 - 11.0) : F32) && (z < 11.0 : F32) && (V.dot(a,a) > 1.44 : F32) && (V.dot(b,b) > 1.44 : F32) && (V.dot(c,c) > 1.44 : F32)
  little_ball(valid,center,seed)

# A spatial binary hierarchy prunes whole patches of spheres for each ray.
def field(depth: Nat, axis: Bool, +x: F32, +z: F32, +sx: F32, +sz: F32, +seed: U32) -> Tree:
  match depth:
    case 0n:
      cell(x,z,hash(seed))
    case 1n+ +p:
      match axis:
        case True{}:
          +low = vec((x - 0.2 : F32),0.0,(z - 0.2 : F32))
          +high = vec((x + sx + 0.2 : F32),0.4,(z + sz + 0.2 : F32))
          a = field(p,False{},x,z,(sx * 0.5 : F32),sz,(seed * 2 + 1 : U32))
          b = field(p,False{},(x + sx * 0.5 : F32),z,(sx * 0.5 : F32),sz,(seed * 2 + 2 : U32))
          Branch{low,high,a,b}
        case False{}:
          +low = vec((x - 0.2 : F32),0.0,(z - 0.2 : F32))
          +high = vec((x + sx + 0.2 : F32),0.4,(z + sz + 0.2 : F32))
          a = field(p,True{},x,z,sx,(sz * 0.5 : F32),(seed * 2 + 1 : U32))
          b = field(p,True{},x,(z + sz * 0.5 : F32),sx,(sz * 0.5 : F32),(seed * 2 + 2 : U32))
          Branch{low,high,a,b}

def world_tag(scene: Nat, seed: U32) -> Tree:
  match scene:
    case 2n:
      field(10n,True{},(0.0 - 16.0 : F32),(0.0 - 16.0 : F32),32.0,32.0,seed)
    case _:
      Empty{}

def world(scene: U32, seed: U32) -> Tree:
  world_tag(U32.to_nat(scene), seed)

def scene_hit(tree: Tree, +origin: V.Vec, +direction: V.Vec) -> Hit:
  floor = ball_hit(V.Vec{0.0,(0.0 - 1000.0 : F32),0.0},1000.0,0,V.Vec{0.5,0.5,0.5},0.0,origin,direction)
  a = ball_hit(V.Vec{0.0,1.0,0.0},1.0,2,V.Vec{1.0,1.0,1.0},0.0,origin,direction)
  b = ball_hit(V.Vec{(0.0 - 4.0 : F32),1.0,0.0},1.0,0,V.Vec{0.4,0.2,0.1},0.0,origin,direction)
  c = ball_hit(V.Vec{4.0,1.0,0.0},1.0,1,V.Vec{0.7,0.6,0.5},0.0,origin,direction)
  hit_tree(tree,True{},origin,direction,nearer(nearer(floor,a),nearer(b,c)))

# Positive F32 distance bits plus a 12-bit object index fit in one immediate
# Nat. The grid traversal uses this instead of allocating candidate hit records.
def candidate(d: F32, index: Nat) -> Nat:
  (U32.to_nat(F32.bits(d)) * 4096n + index)

def bits_float(x: U32) -> F32:
  U32{bits} = x
  F32{bits}

def candidate_distance(key: Nat) -> F32:
  bits_float(U32.from_nat((key / 4096n)))

def closest(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat,(candidate_distance(a) < candidate_distance(b) : F32),a,b)

def sky(direction: V.Vec) -> V.Vec:
  +t = (0.5 * (V.vy(direction) + 1.0) : F32)
  V.add(V.scale(V.Vec{1.0,1.0,1.0},(1.0 - t : F32)),V.scale(V.Vec{0.5,0.7,1.0},t))

def reflectance(+cosine: F32, +ratio: F32) -> F32:
  +r = ((1.0 - ratio) / (1.0 + ratio) : F32)
  (r * r + (1.0 - r * r) * F32.pow((1.0 - cosine : F32),5.0) : F32)

def refract(+direction: V.Vec, +normal: V.Vec, +ratio: F32, cosine: F32) -> V.Vec:
  +perpendicular = V.scale(V.add(direction,V.scale(normal,cosine)),ratio)
  parallel = V.scale(normal,(0.0 - F32.sqrt(F32.abs((1.0 - V.dot(perpendicular,perpendicular) : F32))) : F32))
  V.add(perpendicular,parallel)

def glass(+direction: V.Vec, +normal: V.Vec, +ratio: F32, seed: U32) -> V.Vec:
  +cosine = F32.min(1.0,V.dot(V.scale(direction,(0.0 - 1.0 : F32)),normal))
  sine = F32.sqrt(F32.max(0.0,(1.0 - cosine * cosine : F32)))
  Bool.pick(V.Vec,(ratio * sine > 1.0 : F32) || (reflectance(cosine,ratio) > random(seed) : F32),V.reflect(direction,normal),refract(direction,normal,ratio,cosine))

def metal(valid: Bool, direction: V.Vec, color: V.Vec) -> Scatter:
  match valid:
    case True{}:
      Bounce{direction,color}
    case False{}:
      Absorb{}

def scatter_tag(kind: Nat, +direction: V.Vec, +normal: V.Vec, color: V.Vec, fuzz: F32, front: Bool, seed: U32) -> Scatter:
  match kind:
    case 0n:
      +out = V.add(normal,random_unit(seed))
      Bounce{V.unit(Bool.pick(V.Vec,(V.dot(out,out) < 0.00000001 : F32),normal,out)),color}
    case 1n:
      +out = V.unit(V.add(V.reflect(direction,normal),V.scale(random_unit(seed),fuzz)))
      metal((V.dot(out,normal) > 0.0 : F32),out,color)
    case _:
      Bounce{V.unit(glass(direction,normal,Bool.pick(F32,front,(1.0 / 1.5 : F32),1.5),seed)),V.Vec{1.0,1.0,1.0}}

type Path is Data:
  Escaped{color: V.Vec}
  Stopped{}
  Segment{point: V.Vec, direction: V.Vec, attenuation: V.Vec}

def scatter(kind: U32, +direction: V.Vec, +normal: V.Vec, color: V.Vec, fuzz: F32, front: Bool, seed: U32) -> Scatter:
  scatter_tag(U32.to_nat(kind), direction, normal, color, fuzz, front, seed)

def segment(s: Scatter, point: V.Vec) -> Path:
  match s:
    case Absorb{}:
      Stopped{}
    case Bounce{direction,attenuation}:
      Segment{point,direction,attenuation}

def path_hit(missed: Bool, h: Hit, +origin: V.Vec, +direction: V.Vec, seed: U32) -> Path:
  match missed:
    case True{}:
      Escaped{sky(direction)}
    case False{}:
      Hit{d,normal,kind,color,fuzz,front} = h
      segment(scatter(kind,direction,normal,color,fuzz,front,seed),V.add(origin,V.scale(direction,d)))

def next_path(tree: Tree, +origin: V.Vec, +direction: V.Vec, seed: U32) -> Path:
  +h = scene_hit(tree,origin,direction)
  path_hit((distance(h) > 100000.0 : F32),h,origin,direction,seed)

# One sampled path per ray. Never evaluate a second recursive branch eagerly.
def walk_acc(depth: Nat, path: Path, +tree: Tree, +seed: U32, weight: V.Vec) -> V.Vec:
  match depth:
    case 0n:
      V.Vec{0.0,0.0,0.0}
    case 1n+p:
      match path:
        case Escaped{color}:
          multiply(weight,color)
        case Stopped{}:
          V.Vec{0.0,0.0,0.0}
        case Segment{point,direction,attenuation}:
          +next_seed = hash((seed + 17 : U32))
          walk_acc(p,next_path(tree,point,direction,next_seed),tree,next_seed,multiply(weight,attenuation))

def walk(depth: Nat, path: Path, tree: Tree, seed: U32) -> V.Vec:
  walk_acc(depth,path,tree,seed,V.Vec{1.0,1.0,1.0})

def trace(depth: Nat, +tree: Tree, origin: V.Vec, direction: V.Vec, +seed: U32) -> V.Vec:
  walk(depth,next_path(tree,origin,direction,seed),tree,seed)

def sample(+x: U32, +y: U32, +width: U32, height: U32, depth: Nat, tree: Tree, +seed: U32) -> V.Vec:
  +from = vec(13.0,2.0,3.0)
  +w = V.unit(from)
  +u = V.unit(cross(V.Vec{0.0,1.0,0.0},w))
  +v = cross(w,u)
  +h = U32.to_f32(height)
  sx = ((2.0 * (U32.to_f32(x) + random(seed)) / U32.to_f32(width) - 1.0) * U32.to_f32(width) / h * 1.7632698 : F32)
  sy = ((1.0 - 2.0 * (U32.to_f32(y) + random((seed + 1 : U32))) / h) * 1.7632698 : F32)
  +angle = (6.283185307 * random((seed + 2 : U32)) : F32)
  +radius = (0.05236 * F32.sqrt(random((seed + 3 : U32))) : F32)
  +offset = V.add(V.scale(u,(radius * F32.cos(angle) : F32)),V.scale(v,(radius * F32.sin(angle) : F32)))
  direction = V.unit(V.sub(V.add(V.scale(w,(0.0 - 10.0 : F32)),V.add(V.scale(u,sx),V.scale(v,sy))),offset))
  trace(depth,tree,V.add(from,offset),direction,hash((seed + 4 : U32)))

def samples(n: Nat, +x: U32, +y: U32, +width: U32, +height: U32, +depth: Nat, +tree: Tree, +seed: U32, sum: V.Vec) -> V.Vec:
  match n:
    case 0n:
      sum
    case 1n+p:
      samples(p,x,y,width,height,depth,tree,hash((seed + 101 : U32)),V.add(sum,sample(x,y,width,height,depth,tree,seed)))

def pixel(+x: U32, +y: U32, +width: U32, height: U32, depth: Nat, tree: Tree, +spp: U32, seed: U32) -> U32:
  color = samples(U32.to_nat(spp),x,y,width,height,depth,tree,hash((seed .^. (y * width + x) : U32)),V.Vec{0.0,0.0,0.0})
  V.pack(V.scale(color,(1.0 / U32.to_f32(spp) : F32)))

def render_pixel(valid: Bool, +index: U32, +width: U32, height: U32, bounces: Nat, tree: Tree, spp: U32, seed: U32) -> G.Grid:
  match valid:
    case False{}:
      G.Leaf{0}
    case True{}:
      G.Leaf{pixel((index % width : U32),(index / width : U32),width,height,bounces,tree,spp,seed)}

def render(depth: Nat, +offset: U32, +width: U32, +height: U32, +bounces: Nat, +tree: Tree, +spp: U32, +seed: U32) -> G.Grid:
  match depth:
    case 0n:
      render_pixel((offset < width * height : U32),offset,width,height,bounces,tree,spp,seed)
    case 1n+ +p:
      a b = render(p,offset,width,height,bounces,tree,spp,seed) render(p,(offset + (1 << p) : U32),width,height,bounces,tree,spp,seed)
      G.Branch{a,b}
