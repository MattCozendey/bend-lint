# Doom's binary angle measure: a turn is 2^32, so U32's wraparound is the
# angle's. The fine tables are indexed by the top thirteen bits.
import Base
import ./vec.bend as V
import ./fixed.bend as F

def Angle.ang45() -> U32:
  536870912

def Angle.ang90() -> U32:
  1073741824

def Angle.ang180() -> U32:
  2147483648

def Angle.ang270() -> U32:
  3221225472

def Angle.fine(+a: U32) -> U32:
  (a >> 19n : U32)

# The fine sine table runs a quarter turn past the whole one, so the
# cosine is the sine 2048 entries on.
def Angle.sin(sine: V.Vec, +f: U32) -> U32:
  V.Vec.get(sine, f)

def Angle.cos(sine: V.Vec, +f: U32) -> U32:
  V.Vec.get(sine, (f + 2048 : U32))

# Doom's SlopeDiv: the slope y/x of the first octant as an index into
# the arctangent table.
def Angle.slope.if(small: Bool, +num: U32, +den: U32) -> U32:
  match small:
    case True{}:
      2048
    case False{}:
      U32.min(((num << 3n) / (den >> 8n) : U32), 2048)

def Angle.slope(num: U32, +den: U32) -> U32:
  Angle.slope.if(U32.is_lt(den, 512), num, den)

def Angle.octant(+tanto: V.Vec, +x: U32, +y: U32, xneg: Bool, yneg: Bool) -> U32:
  match xneg yneg:
    case False{} False{}:
      Bool.pick(U32, F.Fixed.gt(x, y), V.Vec.get(tanto, Angle.slope(y, x)),
        (Angle.ang90() - 1 - V.Vec.get(tanto, Angle.slope(x, y)) : U32))
    case False{} True{}:
      Bool.pick(U32, F.Fixed.gt(x, y), F.Fixed.neg(V.Vec.get(tanto, Angle.slope(y, x))),
        (Angle.ang270() + V.Vec.get(tanto, Angle.slope(x, y)) : U32))
    case True{} False{}:
      Bool.pick(U32, F.Fixed.gt(x, y),
        (Angle.ang180() - 1 - V.Vec.get(tanto, Angle.slope(y, x)) : U32),
        (Angle.ang90() + V.Vec.get(tanto, Angle.slope(x, y)) : U32))
    case True{} True{}:
      Bool.pick(U32, F.Fixed.gt(x, y),
        (Angle.ang180() + V.Vec.get(tanto, Angle.slope(y, x)) : U32),
        (Angle.ang270() - 1 - V.Vec.get(tanto, Angle.slope(x, y)) : U32))

def Angle.of.if(zero: Bool, +tanto: V.Vec, +x: U32, +y: U32) -> U32:
  match zero:
    case True{}:
      0
    case False{}:
      Angle.octant(tanto, F.Fixed.abs(x), F.Fixed.abs(y), F.Fixed.is_neg(x), F.Fixed.is_neg(y))

# Doom's R_PointToAngle2 from the origin: the angle of a vector, by
# octant and the arctangent table.
def Angle.of(tanto: V.Vec, +x: U32, +y: U32) -> U32:
  Angle.of.if(Bool.and(U32.is_zero(x), U32.is_zero(y)), tanto, x, y)

# A thing's angle is degrees in steps of 45.
def Angle.of_thing(+deg: U32) -> U32:
  ((deg / 45 : U32) * Angle.ang45() : U32)

def Angle.show.pad(+f: U32) -> String:
  Bool.pick(String, U32.is_lt(f, 10), "00",
    Bool.pick(String, U32.is_lt(f, 100), "0", "")) ++ U32.show(f)

# Degrees with three decimals: the top sixteen bits times 360 over 65536.
def Angle.show(+a: U32) -> String:
  +d = ((a >> 16n : U32) * 360 : U32)
  U32.show((d >> 16n : U32)) ++ "." ++ Angle.show.pad((((d .&. 65535 : U32) * 1000 : U32) >> 16n : U32))
