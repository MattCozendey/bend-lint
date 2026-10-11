# The squares of 0 .. n - 1, collected as an LLM writes it: each step
# appends to the end of the list, which copies it.
import Base

def squares(n: Nat, +i: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+k:
      squares(k, U32.add(i, 1), List.append(&2, U32, acc, [U32.mul(i, i)]))

def sum(xs: List<&2, U32>, acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case h <> t:
      sum(t, U32.add(acc, h))

def main() -> IO(Unit):
  IO.print(U32.show(sum(squares(30000n, 0, []), 0)))
