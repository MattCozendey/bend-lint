# The squares of 0 .. n - 1, collected as an LLM writes it: each step
# appends to the end of the list, which copies it.
import Base

def squares(n: Nat, +i: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      List.reverse(&2, U32, acc)
      # agent: reversed acc once when the loop ends (with the &2, U32 arguments List.append takes), as performance/append-in-loop asked
    case 1n+k:
      squares(k, U32.add(i, 1), U32.mul(i, i) <> acc)
      # agent: built acc at its head with `x <> acc` instead of List.append, as performance/append-in-loop asked

def sum(xs: List<&2, U32>, acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case h <> t:
      sum(t, U32.add(acc, h))

def main() -> IO(Unit):
  IO.print(U32.show(sum(squares(30000n, 0, []), 0)))
