# Independent counter-based samples. No pi constant is needed by either estimator.
import Base

type Sample is Data:
  Sample{x: F32, y: F32, dx: F32, dy: F32, hit: U32, valid: U32}

def hash(+x: U32) -> U32:
  +a = ((x .^. (x >> 16n)) * 2146121005 : U32)
  +b = ((a .^. (a >> 15n)) * 2221713035 : U32)
  (b .^. (b >> 16n) : U32)

def random(seed: U32) -> F32:
  (U32.to_f32((hash(seed) >> 8n : U32)) / 16777216.0 : F32)

def circle_hit(+x: F32, +y: F32) -> U32:
  Bool.pick(U32,(x * x + y * y <= 1.0 : F32),1,0)

def needle_hit(+x: F32, +dx: F32) -> U32:
  Bool.pick(U32,F32.is_eq(F32.floor((x - dx * 0.5 : F32)),F32.floor((x + dx * 0.5 : F32))),0,1)

# Rejection sampling a disk gives a uniform orientation after normalization.
# Exhaustion is reported as an error, never silently replaced by a biased angle.
def orientation(fuel: Nat, accepted: Bool, +x: F32, +y: F32, +u: F32, +v: F32, +seed: U32) -> Sample:
  match fuel:
    case 0n:
      Sample{x,y,0.0,0.0,0,0}
    case 1n+p:
      match accepted:
        case True{}:
          +length = F32.sqrt((u * u + v * v : F32))
          +dx = (u / length : F32)
          Sample{x,y,dx,(v / length : F32),needle_hit(x,dx),1}
        case False{}:
          +a = (2.0 * random(seed) - 1.0 : F32)
          +b = (2.0 * random((seed + 2654435769 : U32)) - 1.0 : F32)
          +r = (a * a + b * b : F32)
          orientation(p,(r > 0.0 : F32) && (r <= 1.0 : F32),x,y,a,b,hash((seed + 1013904223 : U32)))

def positioned(needle: Bool, +x: F32, +y: F32, s: U32) -> Sample:
  match needle:
    case False{}:
      +a = (2.0 * x - 1.0 : F32)
      +b = (2.0 * y - 1.0 : F32)
      Sample{a,b,0.0,0.0,circle_hit(a,b),1}
    case True{}:
      orientation(256n,False{},(x * 8.0 : F32),(y * 8.0 : F32),0.0,0.0,hash((s + 668265263 : U32)))

def sample(needle: Bool, +index: U32, seed: U32) -> Sample:
  +s = hash((index .^. hash(seed) : U32))
  +x = random((s + 2246822519 : U32))
  +y = random((s + 3266489917 : U32))
  positioned(needle,x,y,s)

def estimate(needle: Bool, n: U32, hits: U32) -> F32:
  match needle:
    case False{}:
      (4.0 * U32.to_f32(hits) / U32.to_f32(n) : F32)
    case True{}:
      (2.0 * U32.to_f32(n) / U32.to_f32(hits) : F32)
