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
      x = or_zero(List.get(&2, U32, xs, i))
      y = or_zero(List.get(&2, U32, ys, i))
      dot(k, xs, ys, Nat.add(i, 1n), U32.add(acc, U32.mul(x, y)))

def main() -> IO(Unit):
  +n: Nat = 16000n
  IO.print(U32.show(dot(n, make(n, 1), make(n, 2), 0n, 0)))
