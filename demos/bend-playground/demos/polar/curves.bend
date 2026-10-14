import Base

type Point is Data:
  Point{x: F32, y: F32}

def polar(radius: F32, +theta: F32) -> Point:
  +r = radius
  Point{(r * F32.cos(theta) : F32),(r * F32.sin(theta) : F32)}

# t is normalized progress. Parameters are runtime values, never generated code.
def point(kind: Nat, +t: F32, +petals: F32, turns: F32) -> Point:
  match kind:
    case 0n:
      +a = (t * 6.283185307 : F32)
      +s = F32.sin(a)
      Point{(s * s * s : F32),((0.0 - (13.0 * F32.cos(a) - 5.0 * F32.cos((2.0 * a : F32)) - 2.0 * F32.cos((3.0 * a : F32)) - F32.cos((4.0 * a : F32)))) / 16.0 : F32)}
    case 1n:
      polar((t * t : F32),(t * 6.283185307 * turns : F32))
    case 2n:
      +a = (t * 6.283185307 : F32)
      polar(F32.cos((petals * a : F32)),a)
    case 3n:
      +a = (t * 6.283185307 : F32)
      polar(((1.0 - F32.cos(a)) / 2.0 : F32),a)
    case _:
      polar(t,(t * 6.283185307 * turns : F32))
