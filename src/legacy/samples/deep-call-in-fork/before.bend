# The sum of a 2000-round xorshift hash of every seed in 0 .. 2^d - 1, as an
# LLM writes it: the range forks in halves, but each fork first computes
# the half's size with a power of two that recurses without a tail call.
import Base

def pow2(d: Nat) -> Nat:
  match d:
    case 0n:
      1n
    case 1n+p:
      +h = pow2(p)
      Nat.add(h, h)

def xorshift(+x: U32) -> U32:
  +a = U32.xor(x, U32.shln(x, 13n))
  +b = U32.xor(a, U32.shrn(a, 17n))
  U32.xor(b, U32.shln(b, 5n))

def hash(rounds: Nat, +x: U32) -> U32:
  match rounds:
    case 0n:
      x
    case 1n+r:
      hash(r, xorshift(U32.add(x, 1)))

# the hashes of lo .. lo + 2^d - 1, summed
def total(d: Nat, +lo: U32) -> U32:
  match d:
    case 0n:
      hash(2000n, lo)
    case 1n++p:
      left right = total(p, lo) total(p, U32.add(lo, U32.from_nat(pow2(p))))
      U32.add(left, right)

def main() -> IO(Unit):
  IO.print(U32.show(total(18n, 0)))
