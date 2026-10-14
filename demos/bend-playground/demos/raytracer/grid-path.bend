# Uniform-grid traversal of the Weekend scene. Its small spheres occupy one
# jittered cell each. A 3x3 neighborhood covers their overlap across cell edges.
# Scene coordinates and materials are identical to path.bend's reference tree.
import Base
import ./path.bend as P
import ./ray.bend as V
import ../shared/grid.bend as G

def spread(+x: U32) -> U32:
  (((x .&. 16) << 4n) .|. ((x .&. 8) << 3n) .|. ((x .&. 4) << 2n) .|. ((x .&. 2) << 1n) .|. (x .&. 1) : U32)

def compact(+x: U32) -> U32:
  (((x .&. 256) >> 4n) .|. ((x .&. 64) >> 3n) .|. ((x .&. 16) >> 2n) .|. ((x .&. 4) >> 1n) .|. (x .&. 1) : U32)

def index(x: F32, z: F32) -> U32:
  ((spread(F32.to_u32((x + 16.0 : F32))) << 1n) .|. spread(F32.to_u32((z + 16.0 : F32))) : U32)

def cell_seed(index: U32, seed: U32) -> U32:
  P.hash((seed * 1024 + 1023 + index : U32))

def candidate_clear(valid: Bool, center: V.Vec, index: U32, origin: V.Vec, direction: V.Vec) -> Nat:
  match valid:
    case False{}:
      P.candidate(1.0e20,0n)
    case True{}:
      P.candidate(V.intersect(origin,direction,center,0.2),(1024n + U32.to_nat(index)))

def cell_candidate(valid: Bool, +x: F32, +z: F32, seed: U32, origin: V.Vec, direction: V.Vec) -> Nat:
  match valid:
    case False{}:
      P.candidate(1.0e20,0n)
    case True{}:
      +i = index(x,z)
      +s = cell_seed(i,seed)
      +cx = (x + 0.1 + 0.8 * P.random((s + 1 : U32)) : F32)
      +cz = (z + 0.1 + 0.8 * P.random((s + 2 : U32)) : F32)
      +a = (cx + 4.0 : F32)
      +b = (cx - 4.0 : F32)
      clear = (a * a + cz * cz > 1.44 : F32) && (cx * cx + cz * cz > 1.44 : F32) && (b * b + cz * cz > 1.44 : F32)
      candidate_clear(clear,V.Vec{cx,0.2,cz},i,origin,direction)

def neighbors(n: Nat, +x: F32, +z: F32, +seed: U32, +origin: V.Vec, +direction: V.Vec, best: Nat) -> Nat:
  match n:
    case 0n:
      best
    case 1n+ +p:
      +i = U32.from_nat(p)
      +cx = (x + U32.to_f32((i / 3 : U32)) - 1.0 : F32)
      +cz = (z + U32.to_f32((i % 3 : U32)) - 1.0 : F32)
      valid = (cx >= (0.0 - 11.0) : F32) && (cx < 11.0 : F32) && (cz >= (0.0 - 11.0) : F32) && (cz < 11.0 : F32)
      next = P.closest(best,cell_candidate(valid,cx,cz,seed,origin,direction))
      neighbors(p,x,z,seed,origin,direction,next)

# A line crosses at most 48 cells of the 24x24 enclosing grid. Fuel 64 is a
# geometric traversal bound, independent of image quality or bounce settings.
def march(fuel: Nat, active: Bool, choose_x: Bool, +x: F32, +z: F32, +tx: F32, +tz: F32, +sx: F32, +sz: F32, +dtx: F32, +dtz: F32, +end: F32, +seed: U32, +origin: V.Vec, +direction: V.Vec, best: Nat) -> Nat:
  match fuel:
    case 0n:
      best
    case 1n+p:
      match active:
        case False{}:
          best
        case True{}:
          match choose_x:
            case True{}:
              +hit = neighbors(9n,x,z,seed,origin,direction,best)
              +next_tx = (tx + dtx : F32)
              march(p,(tx <= F32.min(end,P.candidate_distance(hit)) : F32),(next_tx < tz : F32),(x + sx : F32),z,next_tx,tz,sx,sz,dtx,dtz,end,seed,origin,direction,hit)
            case False{}:
              +hit = neighbors(9n,x,z,seed,origin,direction,best)
              +next_tz = (tz + dtz : F32)
              march(p,(tz <= F32.min(end,P.candidate_distance(hit)) : F32),(tx < next_tz : F32),x,(z + sz : F32),tx,next_tz,sx,sz,dtx,dtz,end,seed,origin,direction,hit)

def crossing(parallel: Bool, +cell: F32, +origin: F32, +direction: F32) -> F32:
  match parallel:
    case True{}:
      1.0e20
    case False{}:
      ((cell + Bool.pick(F32,(direction > 0.0 : F32),1.0,0.0) - origin) / direction : F32)

def march_start(valid: Bool, origin: V.Vec, direction: V.Vec, +start: F32, end: F32, seed: U32, best: Nat) -> Nat:
  match valid:
    case False{}:
      best
    case True{}:
      V.Vec{+ox,+oy,+oz} = origin
      V.Vec{+dx,+dy,+dz} = direction
      +x = F32.floor((ox + dx * start : F32))
      +z = F32.floor((oz + dz * start : F32))
      +tx = crossing(F32.is_eq(dx,0.0),x,ox,dx)
      +tz = crossing(F32.is_eq(dz,0.0),z,oz,dz)
      sx = Bool.pick(F32,(dx > 0.0 : F32),1.0,(0.0 - 1.0 : F32))
      sz = Bool.pick(F32,(dz > 0.0 : F32),1.0,(0.0 - 1.0 : F32))
      dtx = Bool.pick(F32,F32.is_eq(dx,0.0),1.0e20,F32.abs((1.0 / dx : F32)))
      dtz = Bool.pick(F32,F32.is_eq(dz,0.0),1.0e20,F32.abs((1.0 / dz : F32)))
      march(64n,True{},(tx < tz : F32),x,z,tx,tz,sx,sz,dtx,dtz,end,seed,V.Vec{ox,oy,oz},V.Vec{dx,dy,dz},best)

def grid_hit(origin: V.Vec, direction: V.Vec, seed: U32, +best: Nat) -> Nat:
  V.Vec{+ox,+oy,+oz} = origin
  V.Vec{+dx,+dy,+dz} = direction
  +a = P.slab((0.0 - 11.2 : F32),11.2,ox,dx)
  +b = P.slab(0.0,0.4,oy,dy)
  +c = P.slab((0.0 - 11.2 : F32),11.2,oz,dz)
  +start = F32.max(0.001,F32.max(P.near(a),F32.max(P.near(b),P.near(c))))
  +end = F32.min(P.candidate_distance(best),F32.min(P.far(a),F32.min(P.far(b),P.far(c))))
  march_start((start <= end : F32),V.Vec{ox,oy,oz},V.Vec{dx,dy,dz},start,end,seed,best)

def object_hit(tree: P.Tree, origin: V.Vec, direction: V.Vec) -> P.Hit:
  match tree:
    case P.Ball{center,radius,kind,color,fuzz}:
      P.ball_hit(center,radius,kind,color,fuzz,origin,direction)
    case _:
      P.miss()

def selected(index: Nat, seed: U32, origin: V.Vec, direction: V.Vec) -> P.Hit:
  match index:
    case 0n:
      P.miss()
    case 1n:
      P.ball_hit(V.Vec{0.0,(0.0 - 1000.0 : F32),0.0},1000.0,0,V.Vec{0.5,0.5,0.5},0.0,origin,direction)
    case 2n:
      P.ball_hit(V.Vec{0.0,1.0,0.0},1.0,2,V.Vec{1.0,1.0,1.0},0.0,origin,direction)
    case 3n:
      P.ball_hit(V.Vec{(0.0 - 4.0 : F32),1.0,0.0},1.0,0,V.Vec{0.4,0.2,0.1},0.0,origin,direction)
    case 4n:
      P.ball_hit(V.Vec{4.0,1.0,0.0},1.0,1,V.Vec{0.7,0.6,0.5},0.0,origin,direction)
    case other:
      +i = (U32.from_nat(other) .&. 1023 : U32)
      x = (U32.to_f32(compact((i >> 1n : U32))) - 16.0 : F32)
      z = (U32.to_f32(compact(i)) - 16.0 : F32)
      object_hit(P.cell(x,z,cell_seed(i,seed)),origin,direction)

def maybe_grid(enabled: Bool, origin: V.Vec, direction: V.Vec, seed: U32, best: Nat) -> Nat:
  match enabled:
    case True{}:
      grid_hit(origin,direction,seed,best)
    case False{}:
      best

def scene_hit(+enabled: Bool, +scene_seed: U32, +origin: V.Vec, +direction: V.Vec) -> P.Hit:
  floor = P.candidate(V.intersect(origin,direction,V.Vec{0.0,(0.0 - 1000.0 : F32),0.0},1000.0),1n)
  a = P.candidate(V.intersect(origin,direction,V.Vec{0.0,1.0,0.0},1.0),2n)
  b = P.candidate(V.intersect(origin,direction,V.Vec{(0.0 - 4.0 : F32),1.0,0.0},1.0),3n)
  c = P.candidate(V.intersect(origin,direction,V.Vec{4.0,1.0,0.0},1.0),4n)
  key = maybe_grid(enabled,origin,direction,scene_seed,P.closest(P.closest(floor,a),P.closest(b,c)))
  selected((key % 4096n),scene_seed,origin,direction)

def next_path(enabled: Bool, scene_seed: U32, +origin: V.Vec, +direction: V.Vec, seed: U32) -> P.Path:
  +h = scene_hit(enabled,scene_seed,origin,direction)
  P.path_hit((P.distance(h) > 100000.0 : F32),h,origin,direction,seed)

def walk(depth: Nat, path: P.Path, +enabled: Bool, +scene_seed: U32, +seed: U32, weight: V.Vec) -> V.Vec:
  match depth:
    case 0n:
      V.Vec{0.0,0.0,0.0}
    case 1n+p:
      match path:
        case P.Escaped{color}:
          P.multiply(weight,color)
        case P.Stopped{}:
          V.Vec{0.0,0.0,0.0}
        case P.Segment{point,direction,attenuation}:
          +next_seed = P.hash((seed + 17 : U32))
          walk(p,next_path(enabled,scene_seed,point,direction,next_seed),enabled,scene_seed,next_seed,P.multiply(weight,attenuation))

def trace(depth: Nat, +enabled: Bool, +scene_seed: U32, origin: V.Vec, direction: V.Vec, +seed: U32) -> V.Vec:
  walk(depth,next_path(enabled,scene_seed,origin,direction,seed),enabled,scene_seed,seed,V.Vec{1.0,1.0,1.0})

def sample(+x: U32, +y: U32, +width: U32, height: U32, depth: Nat, enabled: Bool, +scene_seed: U32, +seed: U32) -> V.Vec:
  +from = P.vec(13.0,2.0,3.0)
  +w = V.unit(from)
  +u = V.unit(P.cross(V.Vec{0.0,1.0,0.0},w))
  +v = P.cross(w,u)
  +h = U32.to_f32(height)
  sx = ((2.0 * (U32.to_f32(x) + P.random(seed)) / U32.to_f32(width) - 1.0) * U32.to_f32(width) / h * 1.7632698 : F32)
  sy = ((1.0 - 2.0 * (U32.to_f32(y) + P.random((seed + 1 : U32))) / h) * 1.7632698 : F32)
  +angle = (6.283185307 * P.random((seed + 2 : U32)) : F32)
  +radius = (0.05236 * F32.sqrt(P.random((seed + 3 : U32))) : F32)
  +offset = V.add(V.scale(u,(radius * F32.cos(angle) : F32)),V.scale(v,(radius * F32.sin(angle) : F32)))
  direction = V.unit(V.sub(V.add(V.scale(w,(0.0 - 10.0 : F32)),V.add(V.scale(u,sx),V.scale(v,sy))),offset))
  trace(depth,enabled,scene_seed,V.add(from,offset),direction,P.hash((seed + 4 : U32)))

def samples(n: Nat, +x: U32, +y: U32, +width: U32, +height: U32, +depth: Nat, +enabled: Bool, +scene_seed: U32, +seed: U32, sum: V.Vec) -> V.Vec:
  match n:
    case 0n:
      sum
    case 1n+p:
      samples(p,x,y,width,height,depth,enabled,scene_seed,P.hash((seed + 101 : U32)),V.add(sum,sample(x,y,width,height,depth,enabled,scene_seed,seed)))

def pixel(+x: U32, +y: U32, +width: U32, height: U32, depth: Nat, enabled: Bool, +scene_seed: U32, +spp: U32, seed: U32) -> U32:
  color = samples(U32.to_nat(spp),x,y,width,height,depth,enabled,scene_seed,P.hash((seed .^. (y * width + x) : U32)),V.Vec{0.0,0.0,0.0})
  V.pack(V.scale(color,(1.0 / U32.to_f32(spp) : F32)))

def render_pixel(valid: Bool, +index: U32, +width: U32, height: U32, bounces: Nat, enabled: Bool, +scene_seed: U32, spp: U32, seed: U32) -> G.Grid:
  match valid:
    case False{}:
      G.Leaf{0}
    case True{}:
      G.Leaf{pixel((index % width : U32),(index / width : U32),width,height,bounces,enabled,scene_seed,spp,seed)}

def render(depth: Nat, +offset: U32, +width: U32, +height: U32, +bounces: Nat, +enabled: Bool, +scene_seed: U32, +spp: U32, +seed: U32) -> G.Grid:
  match depth:
    case 0n:
      render_pixel((offset < width * height : U32),offset,width,height,bounces,enabled,scene_seed,spp,seed)
    case 1n+ +p:
      a b = render(p,offset,width,height,bounces,enabled,scene_seed,spp,seed) render(p,(offset + (1 << p) : U32),width,height,bounces,enabled,scene_seed,spp,seed)
      G.Branch{a,b}

