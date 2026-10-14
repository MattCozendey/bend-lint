import Base
import ./complex.bend as C

type Orbit is Data:
  Escaped{steps: U32, radius: F32}
  Bounded{}

# Iteration fuel is structural Nat, so all pixel orbits terminate.
def iterate(fuel: Nat, escaped: Bool, +cr: C.Wide, +ci: C.Wide, +zr: C.Wide, +zi: C.Wide, +count: U32, radius: F32) -> Orbit:
  match fuel escaped:
    case _ True{}:
      Escaped{count, radius}
    case 0n False{}:
      Bounded{}
    case 1n+rest False{}:
      +rr = C.mul(zr, zr)
      +ii = C.mul(zi, zi)
      +nr = C.add(C.sub(rr, ii), cr)
      +cross = C.mul(zr, zi)
      +ni = C.add(C.add(cross, cross), ci)
      +nrf = C.value(nr)
      +nif = C.value(ni)
      +mag = (nrf * nrf + nif * nif : F32)
      iterate(rest, (mag > 256.0 : F32), cr, ci, nr, ni, (count + 1 : U32), mag)

def channel(v: F32) -> U32:
  F32.to_u32(F32.clamp(v, 0.0, 255.0))

def blend(+t: F32, ar: F32, ag: F32, ab: F32, br: F32, bg: F32, bb: F32) -> U32:
  +u = (t * t * (3.0 - 2.0 * t) : F32)
  r = channel(F32.lerp(ar, br, u))
  g = channel(F32.lerp(ag, bg, u))
  b = channel(F32.lerp(ab, bb, u))
  (r * 65536 + g * 256 + b : U32)

def palette(segment: U32, t: F32) -> U32:
  match segment:
    case 0:
      blend(t, 5.0, 12.0, 27.0, 13.0, 57.0, 77.0)
    case 1:
      blend(t, 13.0, 57.0, 77.0, 46.0, 141.0, 151.0)
    case 2:
      blend(t, 46.0, 141.0, 151.0, 225.0, 237.0, 211.0)
    case 3:
      blend(t, 225.0, 237.0, 211.0, 206.0, 130.0, 59.0)
    case 4:
      blend(t, 206.0, 130.0, 59.0, 77.0, 33.0, 41.0)
    case _:
      blend(t, 77.0, 33.0, 41.0, 5.0, 12.0, 27.0)

def color(result: Orbit, phase: F32) -> U32:
  match result:
    case Bounded{}:
      330001
    case Escaped{steps, radius}:
      +mu = F32.max(0.0, (U32.to_f32(steps) + 1.0 - F32.log2(F32.log2(radius) * 0.5) : F32))
      +t = ((mu * 0.018 + phase) % 1.0 * 6.0 : F32)
      palette(F32.to_u32(t), (t - F32.floor(t) : F32))

def pixel(+fuel: Nat, cr: C.Wide, ci: C.Wide, phase: F32) -> Image:
  Pix{color(iterate(fuel, False{}, cr, ci, C.wide(0.0), C.wide(0.0), 0, 0.0), phase)}

def sample(+px: U32, +py: U32, +width: U32, +height: U32, +cx: C.Wide, +cy: C.Wide, +step: F32, fuel: Nat, phase: F32) -> Image:
  cr = C.add(cx, C.mul(C.wide((U32.to_f32(px) + 0.5 - U32.to_f32(width) * 0.5 : F32)), C.wide(step)))
  ci = C.add(cy, C.mul(C.wide((U32.to_f32(py) + 0.5 - U32.to_f32(height) * 0.5 : F32)), C.wide(step)))
  pixel(fuel, cr, ci, phase)

def tile2(+px: U32, +py: U32, +stride: U32, +width: U32, +height: U32, +cx: C.Wide, +cy: C.Wide, +step: F32, +fuel: Nat, +phase: F32) -> Image:
  Qua{sample(px, py, width, height, cx, cy, step, fuel, phase), sample((px + stride : U32), py, width, height, cx, cy, step, fuel, phase),
    sample(px, (py + stride : U32), width, height, cx, cy, step, fuel, phase), sample((px + stride : U32), (py + stride : U32), width, height, cx, cy, step, fuel, phase)}

def tile4(+px: U32, +py: U32, +stride: U32, +width: U32, +height: U32, +cx: C.Wide, +cy: C.Wide, +step: F32, +fuel: Nat, +phase: F32) -> Image:
  +jump = (stride * 2 : U32)
  Qua{tile2(px, py, stride, width, height, cx, cy, step, fuel, phase), tile2((px + jump : U32), py, stride, width, height, cx, cy, step, fuel, phase),
    tile2(px, (py + jump : U32), stride, width, height, cx, cy, step, fuel, phase), tile2((px + jump : U32), (py + jump : U32), stride, width, height, cx, cy, step, fuel, phase)}

def tile8(+px: U32, +py: U32, +stride: U32, +width: U32, +height: U32, +cx: C.Wide, +cy: C.Wide, +step: F32, +fuel: Nat, +phase: F32) -> Image:
  +jump = (stride * 4 : U32)
  Qua{tile4(px, py, stride, width, height, cx, cy, step, fuel, phase), tile4((px + jump : U32), py, stride, width, height, cx, cy, step, fuel, phase),
    tile4(px, (py + jump : U32), stride, width, height, cx, cy, step, fuel, phase), tile4((px + jump : U32), (py + jump : U32), stride, width, height, cx, cy, step, fuel, phase)}

def tile16(+px: U32, +py: U32, +stride: U32, +width: U32, +height: U32, +cx: C.Wide, +cy: C.Wide, +step: F32, +fuel: Nat, +phase: F32) -> Image:
  +jump = (stride * 8 : U32)
  Qua{tile8(px, py, stride, width, height, cx, cy, step, fuel, phase), tile8((px + jump : U32), py, stride, width, height, cx, cy, step, fuel, phase),
    tile8(px, (py + jump : U32), stride, width, height, cx, cy, step, fuel, phase), tile8((px + jump : U32), (py + jump : U32), stride, width, height, cx, cy, step, fuel, phase)}

def tile32(+px: U32, +py: U32, +stride: U32, +width: U32, +height: U32, +cx: C.Wide, +cy: C.Wide, +step: F32, +fuel: Nat, +phase: F32) -> Image:
  +jump = (stride * 16 : U32)
  Qua{tile16(px, py, stride, width, height, cx, cy, step, fuel, phase), tile16((px + jump : U32), py, stride, width, height, cx, cy, step, fuel, phase),
    tile16(px, (py + jump : U32), stride, width, height, cx, cy, step, fuel, phase), tile16((px + jump : U32), (py + jump : U32), stride, width, height, cx, cy, step, fuel, phase)}

def tile(size: U32, +px: U32, +py: U32, +width: U32, +height: U32, +cx: C.Wide, +cy: C.Wide, +step: F32, +fuel: Nat, +phase: F32) -> Image:
  match size:
    case 2:
      tile2(px, py, 1, width, height, cx, cy, step, fuel, phase)
    case 4:
      tile4(px, py, 1, width, height, cx, cy, step, fuel, phase)
    case 8:
      tile8(px, py, 1, width, height, cx, cy, step, fuel, phase)
    case 16:
      tile16(px, py, 1, width, height, cx, cy, step, fuel, phase)
    case _:
      tile32(px, py, 1, width, height, cx, cy, step, fuel, phase)

def render_tree(+depth: Nat, outside: Bool, +px: U32, +py: U32, +size: U32, +width: U32, +height: U32, +cx: C.Wide, +cy: C.Wide, +step: F32, +fuel: Nat, +phase: F32) -> Image:
  match depth outside:
    case _ True{}:
      Pix{0}
    case 0n False{}:
      tile(size, px, py, width, height, cx, cy, step, fuel, phase)
    case 1n+rest False{}:
      +half = (size / 2 : U32)
      a b c d = render_tree(rest, ((py >= height : U32) || (px >= width : U32)), px, py, half, width, height, cx, cy, step, fuel, phase)
        render_tree(rest, ((py >= height : U32) || ((px + half) >= width : U32)), (px + half : U32), py, half, width, height, cx, cy, step, fuel, phase)
        render_tree(rest, (((py + half) >= height : U32) || (px >= width : U32)), px, (py + half : U32), half, width, height, cx, cy, step, fuel, phase)
        render_tree(rest, (((py + half) >= height : U32) || ((px + half) >= width : U32)), (px + half : U32), (py + half : U32), half, width, height, cx, cy, step, fuel, phase)
      Qua{a, b, c, d}

def fork_depth(root: U32) -> Nat:
  match root:
    case 4096:
      8n
    case _:
      7n

def frame(width: U32, height: U32, +root: U32, cx: C.Wide, cy: C.Wide, step: F32, fuel: Nat, phase: F32) -> Image:
  render_tree!(fork_depth(root), False{}, 0, 0, root, width, height, cx, cy, step, fuel, phase)

def region(origin_x: U32, origin_y: U32, width: U32, height: U32, +root: U32, cx: C.Wide, cy: C.Wide, step: F32, fuel: Nat, phase: F32) -> Image:
  render_tree!(fork_depth(root), False{}, origin_x, origin_y, root, width, height, cx, cy, step, fuel, phase)
