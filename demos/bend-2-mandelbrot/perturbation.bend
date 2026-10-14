import Base
import ./core.bend as Core
import ./scaled.bend as S

type Reference is Data:
  RefEnd{}
  RefPoint{real: F32, imaginary: F32, next: Reference}

type Outcome is Data:
  Escaped{steps: U32, radius: F32}
  Bounded{}
  Repair{}

def select_delta(rebase: Bool, total: S.Scaled, delta: S.Scaled) -> S.Scaled:
  match rebase:
    case True{}:
      total
    case False{}:
      delta

def iterate(fuel: Nat, remaining: Nat, reference: Reference, +root: Reference, escaped: Bool, glitch: Bool, rebase: Bool, +zr: F32, +zi: F32, +dc: S.Scaled, +delta: S.Scaled, +count: U32, radius: F32) -> Outcome:
  match fuel remaining reference escaped glitch rebase:
    case _ _ _ True{} _ _:
      Escaped{count, radius}
    case _ _ _ False{} True{} _:
      Repair{}
    case 0n _ _ False{} False{} _:
      Bounded{}
    case _ 0n _ False{} False{} _:
      Bounded{}
    case 1n+rest 1n+budget _ False{} False{} True{}:
      iterate(rest, 1n+budget, root, root, False{}, False{}, False{}, 0.0, 0.0, dc, delta, count, radius)
    case 1n+rest 1n+budget RefEnd{} False{} False{} False{}:
      Repair{}
    case 1n+rest 1n+budget RefPoint{+nr, +ni, tail} False{} False{} False{}:
      +next = S.advance(zr, zi, dc, delta)
      +total = S.add(S.Complex{nr, ni, 0.0}, next)
      +mag = S.magnitude(total)
      +again = (mag < S.magnitude(next) : F32)
      iterate(rest, budget, tail, root, (mag > 256.0 : F32), (mag < 0.00000001 * (nr * nr + ni * ni) : F32), again, nr, ni, dc, select_delta(again, total, next), (count + 1 : U32), mag)

def choose_float(choose: Bool, yes: F32, no: F32) -> F32:
  match choose:
    case True{}:
      yes
    case False{}:
      no

def iterate_float(fuel: Nat, remaining: Nat, reference: Reference, +root: Reference, escaped: Bool, glitch: Bool, rebase: Bool, +zr: F32, +zi: F32, +cr: F32, +ci: F32, +dr: F32, +di: F32, +count: U32, radius: F32) -> Outcome:
  match fuel remaining reference escaped glitch rebase:
    case _ _ _ True{} _ _:
      Escaped{count, radius}
    case _ _ _ False{} True{} _:
      Repair{}
    case 0n _ _ False{} False{} _:
      Bounded{}
    case _ 0n _ False{} False{} _:
      Bounded{}
    case 1n+rest 1n+budget _ False{} False{} True{}:
      iterate_float(rest, 1n+budget, root, root, False{}, False{}, False{}, 0.0, 0.0, cr, ci, dr, di, count, radius)
    case 1n+rest 1n+budget RefEnd{} False{} False{} False{}:
      Repair{}
    case 1n+rest 1n+budget RefPoint{+nr, +ni, tail} False{} False{} False{}:
      +rr = ((2.0 * zr * dr - 2.0 * zi * di) + (dr * dr - di * di) + cr : F32)
      +ri = ((2.0 * zr * di + 2.0 * zi * dr) + (dr * di + di * dr) + ci : F32)
      +tr = (nr + rr : F32)
      +ti = (ni + ri : F32)
      +mag = (tr * tr + ti * ti : F32)
      +again = (mag < (rr * rr + ri * ri) : F32)
      iterate_float(rest, budget, tail, root, (mag > 256.0 : F32), (mag < 0.00000001 * (nr * nr + ni * ni) : F32), again, nr, ni, cr, ci, choose_float(again, tr, rr), choose_float(again, ti, ri), (count + 1 : U32), mag)

def start_float(fast: Bool, +reference: Reference, +fuel: Nat, +dc: S.Scaled) -> Outcome:
  match fast:
    case True{}:
      S.Complex{r, i, +e} = dc
      +factor = S.power_of_two(e)
      iterate_float((fuel + fuel), fuel, reference, reference, False{}, False{}, False{}, 0.0, 0.0, (r * factor : F32), (i * factor : F32), 0.0, 0.0, 0, 0.0)
    case False{}:
      iterate((fuel + fuel), fuel, reference, reference, False{}, False{}, False{}, 0.0, 0.0, dc, S.zero(), 0, 0.0)

def color(result: Outcome, phase: F32) -> U32:
  match result:
    case Escaped{n, radius}:
      Core.color(Core.Escaped{n, radius}, phase)
    case Bounded{}:
      330001
    case Repair{}:
      16777214

def sample(+px: U32, +py: U32, +width: U32, +height: U32, +mantissa: F32, +exponent: F32, +offset_x: F32, +offset_y: F32, +reference: Reference, +fuel: Nat, phase: F32) -> Image:
  dc = S.normalize(((U32.to_f32(px) + 0.5 - U32.to_f32(width) * 0.5 + offset_x) * mantissa : F32), ((U32.to_f32(py) + 0.5 - U32.to_f32(height) * 0.5 + offset_y) * mantissa : F32), exponent)
  Pix{color(start_float((exponent >= (0.0 - 60.0 : F32) : F32), reference, fuel, dc), phase)}
def tile2(+px: U32, +py: U32, +stride: U32, +width: U32, +height: U32, +mantissa: F32, +exponent: F32, +offset_x: F32, +offset_y: F32, +reference: Reference, +fuel: Nat, +phase: F32) -> Image:
  Qua{sample(px, py, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase), sample((px + stride : U32), py, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase),
    sample(px, (py + stride : U32), width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase), sample((px + stride : U32), (py + stride : U32), width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase)}

def tile4(+px: U32, +py: U32, +stride: U32, +width: U32, +height: U32, +mantissa: F32, +exponent: F32, +offset_x: F32, +offset_y: F32, +reference: Reference, +fuel: Nat, +phase: F32) -> Image:
  +jump = (stride * 2 : U32)
  Qua{tile2(px, py, stride, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase), tile2((px + jump : U32), py, stride, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase),
    tile2(px, (py + jump : U32), stride, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase), tile2((px + jump : U32), (py + jump : U32), stride, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase)}

def tile8(+px: U32, +py: U32, +stride: U32, +width: U32, +height: U32, +mantissa: F32, +exponent: F32, +offset_x: F32, +offset_y: F32, +reference: Reference, +fuel: Nat, +phase: F32) -> Image:
  +jump = (stride * 4 : U32)
  Qua{tile4(px, py, stride, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase), tile4((px + jump : U32), py, stride, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase),
    tile4(px, (py + jump : U32), stride, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase), tile4((px + jump : U32), (py + jump : U32), stride, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase)}

def tile16(+px: U32, +py: U32, +stride: U32, +width: U32, +height: U32, +mantissa: F32, +exponent: F32, +offset_x: F32, +offset_y: F32, +reference: Reference, +fuel: Nat, +phase: F32) -> Image:
  +jump = (stride * 8 : U32)
  Qua{tile8(px, py, stride, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase), tile8((px + jump : U32), py, stride, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase),
    tile8(px, (py + jump : U32), stride, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase), tile8((px + jump : U32), (py + jump : U32), stride, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase)}

def tile32(+px: U32, +py: U32, +stride: U32, +width: U32, +height: U32, +mantissa: F32, +exponent: F32, +offset_x: F32, +offset_y: F32, +reference: Reference, +fuel: Nat, +phase: F32) -> Image:
  +jump = (stride * 16 : U32)
  Qua{tile16(px, py, stride, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase), tile16((px + jump : U32), py, stride, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase),
    tile16(px, (py + jump : U32), stride, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase), tile16((px + jump : U32), (py + jump : U32), stride, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase)}

def tile(size: U32, +px: U32, +py: U32, +width: U32, +height: U32, +mantissa: F32, +exponent: F32, +offset_x: F32, +offset_y: F32, +reference: Reference, +fuel: Nat, +phase: F32) -> Image:
  match size:
    case 2:
      tile2(px, py, 1, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase)
    case 4:
      tile4(px, py, 1, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase)
    case 8:
      tile8(px, py, 1, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase)
    case 16:
      tile16(px, py, 1, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase)
    case _:
      tile32(px, py, 1, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase)

def render_tree(+depth: Nat, outside: Bool, +px: U32, +py: U32, +size: U32, +width: U32, +height: U32, +mantissa: F32, +exponent: F32, +offset_x: F32, +offset_y: F32, +reference: Reference, +fuel: Nat, +phase: F32) -> Image:
  match depth outside:
    case _ True{}:
      Pix{0}
    case 0n False{}:
      tile(size, px, py, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase)
    case 1n+rest False{}:
      +half = (size / 2 : U32)
      a b c d = render_tree(rest, ((py >= height : U32) || (px >= width : U32)), px, py, half, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase)
        render_tree(rest, ((py >= height : U32) || ((px + half) >= width : U32)), (px + half : U32), py, half, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase)
        render_tree(rest, (((py + half) >= height : U32) || (px >= width : U32)), px, (py + half : U32), half, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase)
        render_tree(rest, (((py + half) >= height : U32) || ((px + half) >= width : U32)), (px + half : U32), (py + half : U32), half, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase)
      Qua{a, b, c, d}

def frame(+reference: Reference, width: U32, height: U32, +root: U32, mantissa: F32, exponent: F32, offset_x: F32, offset_y: F32, fuel: Nat, phase: F32) -> Image & Reference:
  (render_tree!(Core.fork_depth(root), False{}, 0, 0, root, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase), reference)

def region(+reference: Reference, origin_x: U32, origin_y: U32, width: U32, height: U32, +root: U32, mantissa: F32, exponent: F32, offset_x: F32, offset_y: F32, fuel: Nat, phase: F32) -> Image & Reference:
  (render_tree!(Core.fork_depth(root), False{}, origin_x, origin_y, root, width, height, mantissa, exponent, offset_x, offset_y, reference, fuel, phase), reference)
