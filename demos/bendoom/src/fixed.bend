# Doom's fixed_t: two's complement on U32 with sixteen fraction bits.
# U32's arithmetic wraps, so add and sub are U32's own; the signed
# operations are built on the sign bit.
import Base

def Fixed.unit() -> U32:
  65536

def Fixed.neg(x: U32) -> U32:
  (0 - x : U32)

def Fixed.is_neg(x: U32) -> Bool:
  U32.is_ge(x, 2147483648)

def Fixed.abs(+x: U32) -> U32:
  Bool.pick(U32, Fixed.is_neg(x), Fixed.neg(x), x)

# Flipping the sign bit maps the signed order onto the unsigned one.
def Fixed.lt(a: U32, b: U32) -> Bool:
  U32.is_lt((a .^. 2147483648 : U32), (b .^. 2147483648 : U32))

def Fixed.le(a: U32, b: U32) -> Bool:
  U32.is_le((a .^. 2147483648 : U32), (b .^. 2147483648 : U32))

def Fixed.gt(a: U32, b: U32) -> Bool:
  Fixed.lt(b, a)

def Fixed.ge(a: U32, b: U32) -> Bool:
  Fixed.le(b, a)

def Fixed.min(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, Fixed.lt(a, b), a, b)

def Fixed.max(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, Fixed.lt(a, b), b, a)

# Arithmetic shift right by n: the logical shift, with the top n bits
# set when the value is negative.
def Fixed.sarn(+x: U32, +n: Nat) -> U32:
  ((x >> n) .|. Bool.pick(U32, Fixed.is_neg(x), U32.not((4294967295 >> n : U32)), 0) : U32)

def Fixed.sar(x: U32) -> U32:
  Fixed.sarn(x, 1n)

# Division by two toward zero, as C's, against the shift's floor.
def Fixed.half(+x: U32) -> U32:
  Bool.pick(U32, Fixed.is_neg(x), Fixed.neg((Fixed.neg(x) >> 1n : U32)), (x >> 1n : U32))

# Doom's P_AproxDistance: the longer leg plus half the shorter.
def Fixed.approx(+dx: U32, +dy: U32) -> U32:
  +ax = Fixed.abs(dx)
  +ay = Fixed.abs(dy)
  Bool.pick(U32, Fixed.lt(ax, ay), (ax + ay - (ax >> 1n) : U32), (ax + ay - (ay >> 1n) : U32))

# A signed 16-bit map coordinate as fixed: the sign extension is shifted
# out, so the plain shift is the conversion.
def Fixed.of_map(w: U32) -> U32:
  (w << 16n : U32)

# The exact product of two unsigned words, shifted right by sixteen,
# modulo 2^32: the halves' partial products, each exact in 32 bits.
def Fixed.mul.u(+a: U32, +b: U32) -> U32:
  +al = (a .&. 65535 : U32)
  +ah = (a >> 16n : U32)
  +bl = (b .&. 65535 : U32)
  +bh = (b >> 16n : U32)
  (((ah * bh : U32) << 16n) + (al * bh : U32) + (ah * bl : U32) + ((al * bl : U32) >> 16n) : U32)

# A negative operand's two's complement reading is its unsigned one less
# 2^32; the product loses 2^32 times the other operand, which lands as
# the other operand shifted left by sixteen.
def Fixed.mul.fix(neg: Bool, other: U32) -> U32:
  match neg:
    case True{}:
      (other << 16n : U32)
    case False{}:
      0

# Doom's FixedMul: the signed 64-bit product shifted right by sixteen.
def Fixed.mul(+a: U32, +b: U32) -> U32:
  (Fixed.mul.u(a, b) - Fixed.mul.fix(Fixed.is_neg(a), b) - Fixed.mul.fix(Fixed.is_neg(b), a) : U32)

# Sixteen steps of shift-subtract long division on the remainder: it
# stays below the divisor, which is at most 2^31, so doubling it fits.
def Fixed.div.go(n: Nat, +d: U32, +q: U32, +r: U32) -> U32:
  match n:
    case 0n:
      q
    case 1n+p:
      +r2 = (r << 1n : U32)
      +hit = U32.is_ge(r2, d)
      Fixed.div.go(p, d, ((q << 1n) + Bool.to_u32(hit) : U32), Bool.pick(U32, hit, (r2 - d : U32), r2))

def Fixed.div.mag(+a: U32, +d: U32) -> U32:
  Fixed.div.go(16n, d, (a / d : U32), (a % d : U32))

def Fixed.div.sign(neg: Bool, q: U32) -> U32:
  match neg:
    case True{}:
      Fixed.neg(q)
    case False{}:
      q

def Fixed.div.if(sat: Bool, +a: U32, +b: U32) -> U32:
  match sat:
    case True{}:
      Bool.pick(U32, Fixed.is_neg((a .^. b : U32)), 2147483648, 2147483647)
    case False{}:
      Fixed.div.sign(Fixed.is_neg((a .^. b : U32)), Fixed.div.mag(Fixed.abs(a), Fixed.abs(b)))

# Doom's FixedDiv: (a << 16) / b, truncated toward zero, saturating to
# the signed extremes when the quotient would not fit (or b is zero).
def Fixed.div(+a: U32, +b: U32) -> U32:
  Fixed.div.if(U32.is_ge((Fixed.abs(a) >> 14n : U32), Fixed.abs(b)), a, b)

# C's a / n for a signed a and a positive n: truncated toward zero.
def Fixed.quot(+a: U32, n: U32) -> U32:
  Fixed.div.sign(Fixed.is_neg(a), (Fixed.abs(a) / n : U32))

def Fixed.show.pad(+f: U32) -> String:
  Bool.pick(String, U32.is_lt(f, 10), "00000",
    Bool.pick(String, U32.is_lt(f, 100), "0000",
      Bool.pick(String, U32.is_lt(f, 1000), "000",
        Bool.pick(String, U32.is_lt(f, 10000), "00",
          Bool.pick(String, U32.is_lt(f, 100000), "0", ""))))) ++ U32.show(f)

# The magnitude's integer part, a point, and six decimals of its
# fraction (f * 1000000 / 65536, as f * 15625 >> 10, which fits).
def Fixed.show.mag(+m: U32) -> String:
  U32.show((m >> 16n : U32)) ++ "." ++ Fixed.show.pad((((m .&. 65535 : U32) * 15625 : U32) >> 10n : U32))

def Fixed.show(+x: U32) -> String:
  Bool.pick(String, Fixed.is_neg(x), "-" ++ Fixed.show.mag(Fixed.neg(x)), Fixed.show.mag(x))

