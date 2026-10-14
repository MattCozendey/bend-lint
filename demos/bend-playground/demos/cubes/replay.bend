# Independent collision snapshots derived from the same two-float rotation
# used by the counter. Positions use the contact coordinates of physics.bend.
import Base
import ../../accelerated.bend as A
import ../../precise.bend as D

type Snapshot is Data:
  Snapshot{count: Nat, x: F32, y: F32, v: F32, w: F32, time: F32, u: F32, wall: Bool}

type Replay is Data:
  Empty{}
  Frame{state: Snapshot}
  Branch{left: Replay, right: Replay}

# Invariants for initial x=1, y=3, v=0, w=-1:
# |x*w-y*v| = 1, and t*t*x*v+y*w = time-3, where t=1/sqrt(M).
# These locate each event without marching through every preceding impact.
def locate(wall: Bool, r: A.Rotation, +t: D.Number, count: Nat) -> Snapshot:
  match wall:
    case True{}:
      A.Rotation{+re, +im} = r
      +y = D.div(t, im)
      time = D.sub(D.of(3.0), D.mul(y, re))
      Snapshot{count, 0.0, D.high(y), D.high(D.div(im, t)), D.high(D.neg(re)), D.high(time), D.high(im), True{}}
    case False{}:
      A.Rotation{+re, +im} = r
      +contact = D.div(t, D.sub(im, D.mul(t, re)))
      time = D.sub(D.of(3.0), D.mul(contact, D.add(re, D.mul(t, im))))
      Snapshot{count, D.high(contact), D.high(contact), D.high(D.neg(D.div(im, t))), D.high(D.neg(re)), D.high(time), D.high(D.neg(im)), False{}}

def snapshot(+count: Nat, base: A.Rotation, t: D.Number) -> Snapshot:
  match count:
    case 0n:
      Snapshot{0n, 1.0, 3.0, 0.0, (0.0 - 1.0 : F32), 0.0, 0.0, False{}}
    case 1n+p:
      +n = {1n+p : Nat}
      locate(Nat.is_eq((n % 2n), 0n), A.power(base, ((n + 1n) / 2n)), t, n)

# floor(length*i/n) without overflowing the 48-bit Nat product length*i.
def spread(+length: Nat, +i: Nat, +n: Nat) -> Nat:
  ((length / n) * i + ((length % n) * i) / n)

# Keep block/wall pairs together when sampling so each visible bounce has
# its counterpart. The first and last pair are always included.
def collision(index: Nat, pairs: Nat, samples: Nat) -> Nat:
  match index:
    case 0n:
      0n
    case 1n+ +p:
      k = (1n + spread((pairs - 1n), (p / 2n), (samples - 1n)))
      (2n * k - 1n + p % 2n)

def valid_frame(valid: Bool, count: Nat, base: A.Rotation, t: D.Number) -> Replay:
  match valid:
    case False{}:
      Empty{}
    case True{}:
      Frame{snapshot(count, base, t)}

def candidate(valid: Bool, index: Nat, pairs: Nat, samples: Nat, +total: Nat, base: A.Rotation, t: D.Number) -> Replay:
  match valid:
    case False{}:
      Empty{}
    case True{}:
      +n = collision(index, pairs, samples)
      valid_frame((n <= total), n, base, t)

def tree(depth: Nat, +offset: Nat, +pairs: Nat, +samples: Nat, +total: Nat, +base: A.Rotation, +t: D.Number) -> Replay:
  match depth:
    case 0n:
      candidate((offset <= 2n * samples), offset, pairs, samples, total, base, t)
    case 1n+ +p:
      a b = tree(p, offset, pairs, samples, total, base, t) tree(p, (offset + Nat.pow(2n, p)), pairs, samples, total, base, t)
      Branch{a, b}

def make(places: Nat, +total: Nat) -> Replay:
  +t = D.tenth(places)
  +pairs = ((total + 1n) / 2n)
  samples = Nat.min(pairs, U32.to_nat(1024))
  tree(12n, 0n, pairs, samples, total, A.rotation(t), t)

# Physical-time samples for large counts. Searching event times skips work,
# not elapsed time: all display samples use the same seconds-per-frame.
def event_time(wall: Bool, r: A.Rotation, +t: D.Number) -> D.Number:
  match wall:
    case True{}:
      A.Rotation{re, im} = r
      D.sub(D.of(3.0), D.div(D.mul(t, re), im))
    case False{}:
      A.Rotation{+re, +im} = r
      contact = D.div(t, D.sub(im, D.mul(t, re)))
      D.sub(D.of(3.0), D.mul(contact, D.add(re, D.mul(t, im))))

def before(+n: Nat, base: A.Rotation, +t: D.Number, clock: D.Number) -> Bool:
  time = event_time(Nat.is_eq((n % 2n), 0n), A.power(base, ((n + 1n) / 2n)), t)
  D.nonpositive(D.sub(time, clock))

def bracket(fuel: Nat, done: Bool, +lo: Nat, +hi: Nat, +base: A.Rotation, +t: D.Number, +clock: D.Number) -> Nat:
  match fuel:
    case 0n:
      lo
    case 1n+p:
      match done:
        case True{}:
          lo
        case False{}:
          +mid = (lo + (hi - lo + 1n) / 2n)
          +passed = before(mid, base, t, clock)
          +left = Bool.pick(Nat, passed, mid, lo)
          +right = Bool.pick(Nat, passed, hi, (mid - 1n))
          bracket(p, Nat.is_eq(left, right), left, right, base, t, clock)

def position(+clock: F32, r: A.Rotation, +t: D.Number, +n: Nat) -> Snapshot:
  A.Rotation{+re, +im} = r
  +even = Nat.is_eq((n % 2n), 0n)
  +dt = D.sub(D.of(clock), D.of(3.0))
  +v = D.div(im, t)
  +x = D.add(re, D.mul(v, dt))
  y = D.sub(D.mul(t, im), D.mul(re, dt))
  Snapshot{n, D.high(Bool.pick(D.Number, even, x, D.neg(x))), D.high(y), D.high(Bool.pick(D.Number, even, v, D.neg(v))), D.high(D.neg(re)), clock, D.high(Bool.pick(D.Number, even, im, D.neg(im))), even}

def at_time(+clock: F32, +base: A.Rotation, +t: D.Number, +total: Nat) -> Snapshot:
  +n = bracket(48n, Nat.is_eq(total, 0n), 0n, total, base, t, D.of(clock))
  position(clock, A.power(base, ((n + 1n) / 2n)), t, n)

def time_tree(depth: Nat, +offset: U32, +duration: F32, +base: A.Rotation, +t: D.Number, +total: Nat) -> Replay:
  match depth:
    case 0n:
      clock = (U32.to_f32(offset) / 1023.0 * duration : F32)
      Frame{at_time(clock, base, t, total)}
    case 1n+ +p:
      a b = time_tree(p, offset, duration, base, t, total) time_tree(p, (offset + (1 << p) : U32), duration, base, t, total)
      Branch{a, b}

def motion(sampled: Bool, places: Nat, +total: Nat) -> Replay:
  match sampled:
    case False{}:
      Empty{}
    case True{}:
      +t = D.tenth(places)
      +base = A.rotation(t)
      duration = D.high(D.add(event_time(Nat.is_eq((total % 2n), 0n), A.power(base, ((total + 1n) / 2n)), t), D.of(2.0)))
      time_tree(10n, 0, duration, base, t, total)

def line(s: Snapshot) -> String:
  Snapshot{count, x, y, v, w, time, u, wall} = s
  Nat.show(count) ++ " " ++ F32.show(x) ++ " " ++ F32.show(y) ++ " " ++ F32.show(v) ++ " " ++ F32.show(w) ++ " " ++ F32.show(time) ++ " " ++ F32.show(u) ++ " " ++ U32.show(Bool.to_u32(wall))

def print(r: Replay) -> IO(Unit):
  match r:
    case Empty{}:
      IO.pure(Unit, Unit{})
    case Frame{s}:
      IO.print(line(s))
    case Branch{left, right}:
      do IO<Unit>:
        print(left)
        print(right)
