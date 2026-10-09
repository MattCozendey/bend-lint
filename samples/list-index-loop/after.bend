# The dot product of two lists by index, as an LLM writes it: each step
# looks both lists up from their heads.
import Base

def make(n: Nat, +s: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      U32.shrn(U32.mul(s, 2654435761), 24n) <> make(p, U32.add(s, 1))

def or_zero(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}:
      0
    case Some{x}:
      x

# the sum of xs[i] * ys[i] for the next n indexes from i
def dot(n: Nat, +xs: List<&2, U32>, +ys: List<&2, U32>, +i: Nat, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      match xs:
      # agent: match xs instead of List.get(&2, U32, xs, i) (list-index-loop finding on xs)
        case []:
        # agent: empty xs: every later x is 0, so the sum stays acc (list-index-loop finding on xs)
          acc
          # agent: return acc, as or_zero gave 0 for every remaining x (list-index-loop finding on xs)
        case x <> xt:
        # agent: use the head of xs as x (list-index-loop finding on xs)
          match ys:
          # agent: match ys instead of List.get(&2, U32, ys, i) (list-index-loop finding on ys)
            case []:
            # agent: empty ys: every later y is 0, so the sum stays acc (list-index-loop finding on ys)
              acc
              # agent: return acc, as or_zero gave 0 for every remaining y (list-index-loop finding on ys)
            case y <> yt:
            # agent: use the head of ys as y (list-index-loop finding on ys)
              dot(k, xt, yt, Nat.add(i, 1n), U32.add(acc, U32.mul(x, y)))
              # agent: pass the tails xt and yt to the next call (list-index-loop findings on xs and ys)

def main() -> IO(Unit):
  +n: Nat = 16000n
  IO.print(U32.show(dot(n, make(n, 1), make(n, 2), 0n, 0)))
