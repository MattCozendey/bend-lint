# Two F32 components retain about 48 significant binary bits.
# Error-free TwoSum / Dekker TwoProduct; no fast-math or fused contraction.
import Base

type Number is Data:
  Number{hi: F32, lo: F32}

def of(x: F32) -> Number:
  Number{x, 0.0}

def sum(+a: F32, +b: F32) -> Number:
  +s = (a + b : F32)
  +v = (s - a : F32)
  Number{s, ((a - (s - v)) + (b - v) : F32)}

def with_low(s: Number, low: F32) -> Number:
  Number{sh, sl} = s
  sum(sh, (sl + low : F32))

def add(a: Number, b: Number) -> Number:
  Number{ah, al} = a
  Number{bh, bl} = b
  with_low(sum(ah, bh), (al + bl : F32))

def neg(a: Number) -> Number:
  Number{h, l} = a
  Number{(0.0 - h : F32), (0.0 - l : F32)}

def sub(a: Number, b: Number) -> Number:
  add(a, neg(b))

def split(+a: F32) -> Number:
  +t = (4097.0 * a : F32)
  +h = (t - (t - a) : F32)
  Number{h, (a - h : F32)}

def product_parts(+p: F32, a: Number, b: Number) -> Number:
  Number{+ah, +al} = a
  Number{+bh, +bl} = b
  Number{p, ((((ah * bh - p) + ah * bl) + al * bh) + al * bl : F32)}

def product(+a: F32, +b: F32) -> Number:
  product_parts((a * b : F32), split(a), split(b))

def mul(a: Number, b: Number) -> Number:
  Number{+ah, +al} = a
  Number{+bh, +bl} = b
  with_low(product(ah, bh), ((ah * bl + al * bh) + al * bl : F32))

def high(a: Number) -> F32:
  Number{h, l} = a
  h

def div(+a: Number, +b: Number) -> Number:
  +q = of((high(a) / high(b) : F32))
  r = sub(a, mul(b, q))
  +q2 = of((high(r) / high(b) : F32))
  add(q, q2)

def negative(a: Number) -> Bool:
  Number{+h, l} = a
  (h < 0.0 : F32) || (F32.is_eq(h, 0.0) && (l < 0.0 : F32))

def nonpositive(a: Number) -> Bool:
  Bool.not(negative(neg(a)))

def tenth(n: Nat) -> Number:
  match n:
    case 0n:
      of(1.0)
    case 1n+p:
      div(tenth(p), of(10.0))
