# Compose a block impact and wall reflection as a velocity-space rotation.
# Parallel workers evaluate independent powers of that same transformation.
# No pi constant, trig function, or precomputed collision count is used.
import Base
import ./precise.bend as D

type Rotation is Data:
  Rotation{re: D.Number, im: D.Number}

def compose(a: Rotation, b: Rotation) -> Rotation:
  Rotation{+ar, +ai} = a
  Rotation{+br, +bi} = b
  Rotation{D.sub(D.mul(ar, br), D.mul(ai, bi)), D.add(D.mul(ar, bi), D.mul(ai, br))}

# t = sqrt(small mass / large mass), formed in extended precision.
def rotation(+t: D.Number) -> Rotation:
  +square = D.mul(t, t)
  +denom = D.add(D.of(1.0), square)
  Rotation{D.div(D.sub(D.of(1.0), square), denom), D.div(D.mul(D.of(2.0), t), denom)}

def power_loop(fuel: Nat, n: Nat, +base: Rotation, +acc: Rotation) -> Rotation:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      match n:
        case 0n:
          acc
        case 1n+q:
          +k = {1n+q : Nat}
          updated = Bool.pick(Rotation, Nat.is_eq((k % 2n), 0n), acc, compose(acc, base))
          power_loop(p, (k / 2n), compose(base, base), updated)

def power(base: Rotation, n: Nat) -> Rotation:
  power_loop(48n, n, base, Rotation{D.of(1.0), D.of(0.0)})

# In 0 < k <= 2 / t, the imaginary part crosses zero exactly once.
def imag_nonpositive(r: Rotation) -> Bool:
  Rotation{re, im} = r
  D.nonpositive(im)

def crossed(base: Rotation, k: Nat) -> Bool:
  imag_nonpositive(power(base, k))

def candidate(base: Rotation, +k: Nat, hi: Nat) -> Nat:
  Bool.pick(Nat, crossed(base, k), k, hi)

# Balanced fork/join, with 2^depth independent collision-index candidates.
def sample(depth: Nat, +base: Rotation, +lo: Nat, +hi: Nat, +stride: Nat, +offset: Nat) -> Nat:
  match depth:
    case 0n:
      +k = Nat.min(hi, (lo + (offset + 1n) * stride))
      candidate(base, k, hi)
    case 1n+ +p:
      +half = Nat.pow(2n, p)
      a b = sample(p, base, lo, hi, stride, offset) sample(p, base, lo, hi, stride, (offset + half))
      Nat.min(a, b)

# Each round narrows the bracket by up to 256x. At most 48-bit Nat indices.
def search(fuel: Nat, done: Bool, +base: Rotation, +lo: Nat, +hi: Nat) -> Nat:
  match fuel:
    case 0n:
      hi
    case 1n+p:
      match done:
        case True{}:
          hi
        case False{}:
          +stride = ((hi - lo + 255n) / 256n)
          +next_hi = sample(8n, base, lo, hi, stride, 0n)
          +next_lo = Nat.max(lo, (next_hi - stride))
          search(p, ((next_hi - next_lo) <= 1n), base, next_lo, next_hi)

def ten_power(n: Nat) -> Nat:
  match n:
    case 0n:
      1n
    case 1n+p:
      (10n * ten_power(p))

# k is the first full pair whose wall reflection would be unphysical.
# At pair k-1, v_small <= v_large means the last event was a wall impact;
# otherwise one final block impact is still required.
def finish_state(r: Rotation, t: D.Number, +k: Nat) -> Nat:
  Rotation{re, im} = r
  ended = D.nonpositive(D.add(im, D.mul(t, re)))
  Bool.pick(Nat, ended, (2n * (k - 1n)), (2n * k - 1n))

def finish(base: Rotation, t: D.Number, +k: Nat) -> Nat:
  finish_state(power(base, (k - 1n)), t, k)

# decimal_places = total digits - 1. CLI has no artificial upper cutoff;
# arithmetic is still finite precision and Nat indices are 48-bit.
def count(+decimal_places: Nat) -> Nat:
  +t = D.tenth(decimal_places)
  +base = rotation(t)
  +hi = (2n * ten_power(decimal_places))
  k = search(8n, False{}, base, 0n, hi)
  finish(base, t, k)
