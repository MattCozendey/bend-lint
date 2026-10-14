import Base

type Scaled is Data:
  Complex{re: F32, im: F32, exponent: F32}

def float_bits(word: U32) -> F32:
  match word:
    case U32{bits}:
      F32{bits}

def power_of_two(exponent: F32) -> F32:
  float_bits((F32.to_u32((127.0 + exponent : F32)) << 23n : U32))

def select(underflow: Bool, exponent: F32) -> F32:
  match underflow:
    case True{}:
      0.0
    case False{}:
      power_of_two(exponent)

def scale_factor(+difference: F32) -> F32:
  select((difference < (0.0 - 100.0 : F32) : F32), difference)

def normalize_nonzero(zero: Bool, +re: F32, +im: F32, exponent: F32) -> Scaled:
  match zero:
    case True{}:
      Complex{0.0, 0.0, 0.0}
    case False{}:
      +encoded = ((F32.bits(F32.max(F32.abs(re), F32.abs(im))) >> 23n) .&. 255 : U32)
      +factor = float_bits(((254 - encoded) << 23n : U32))
      Complex{(re * factor : F32), (im * factor : F32), (exponent + U32.to_f32(encoded) - 127.0 : F32)}

def normalize(+re: F32, +im: F32, exponent: F32) -> Scaled:
  normalize_nonzero((F32.max(F32.abs(re), F32.abs(im)) < 1.0e-35 : F32), re, im, exponent)

def add_parts(azero: Bool, bzero: Bool, +ar: F32, +ai: F32, +ae: F32, +br: F32, +bi: F32, +be: F32) -> Scaled:
  match azero bzero:
    case True{} _:
      Complex{br, bi, be}
    case False{} True{}:
      Complex{ar, ai, ae}
    case False{} False{}:
      +exp = F32.max(ae, be)
      +af = scale_factor((ae - exp : F32))
      +bf = scale_factor((be - exp : F32))
      normalize((ar * af + br * bf : F32), (ai * af + bi * bf : F32), exp)

def add(a: Scaled, b: Scaled) -> Scaled:
  Complex{+ar, +ai, +ae} = a
  Complex{+br, +bi, +be} = b
  add_parts((F32.max(F32.abs(ar), F32.abs(ai)) < 1.0e-35 : F32), (F32.max(F32.abs(br), F32.abs(bi)) < 1.0e-35 : F32), ar, ai, ae, br, bi, be)

def multiply(a: Scaled, b: Scaled) -> Scaled:
  Complex{+ar, +ai, ae} = a
  Complex{+br, +bi, be} = b
  normalize((ar * br - ai * bi : F32), (ar * bi + ai * br : F32), (ae + be : F32))

def zero() -> Scaled:
  Complex{0.0, 0.0, 0.0}

def magnitude(a: Scaled) -> F32:
  Complex{+ar, +ai, +ae} = a
  ((ar * ar + ai * ai) * scale_factor(F32.min(100.0, (2.0 * ae : F32))) : F32)

# Combine the linear and quadratic terms before normalization, preserving
# a separate path for a zero linear term and the existing constant addition.
def advance_terms(zero_linear: Bool, lr: F32, li: F32, qr: F32, qi: F32, +de: F32, dc: Scaled) -> Scaled:
  match zero_linear:
    case True{}:
      add(normalize(qr, qi, (2.0 * de : F32)), dc)
    case False{}:
      +exponent = F32.max(de, (2.0 * de : F32))
      +linear = scale_factor((de - exponent : F32))
      +quadratic = scale_factor((2.0 * de - exponent : F32))
      add(normalize((lr * linear + qr * quadratic : F32), (li * linear + qi * quadratic : F32), exponent), dc)

def advance_nonzero(+zr: F32, +zi: F32, dc: Scaled, delta: Scaled) -> Scaled:
  Complex{+dr, +di, +de} = delta
  +lr = (2.0 * zr * dr - 2.0 * zi * di : F32)
  +li = (2.0 * zr * di + 2.0 * zi * dr : F32)
  advance_terms((F32.max(F32.abs(lr), F32.abs(li)) < 1.0e-35 : F32), lr, li, (dr * dr - di * di : F32), (dr * di + di * dr : F32), de, dc)

def word_zero(value: U32) -> Bool:
  match value:
    case 0:
      True{}
    case _:
      False{}

def float_zero(value: F32) -> Bool:
  F32{bits} = value
  word_zero(U32{bits})

def delta_zero(value: Scaled) -> Bool:
  Complex{r, i, exponent} = value
  (float_zero(r) && float_zero(i))

def advance_select(zero: Bool, zr: F32, zi: F32, dc: Scaled, delta: Scaled) -> Scaled:
  match zero:
    case True{}:
      dc
    case False{}:
      advance_nonzero(zr, zi, dc, delta)

def advance(zr: F32, zi: F32, dc: Scaled, +delta: Scaled) -> Scaled:
  advance_select(delta_zero(delta), zr, zi, dc, delta)
