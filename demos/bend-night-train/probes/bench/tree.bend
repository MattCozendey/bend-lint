# Balanced parallel work with a constant per leaf.
#
# Every leaf does the same tiny sum: no branching, no allocation, no spread in
# the work per leaf.  This isolates the fork-join scheduler from the uneven
# ray-marching of the real renderer (see docs/benchmarks.md).
import Base

def leaf(+i: Nat) -> Nat:
  Nat.add(i, 1n)


def tree(+d: Nat, +i: Nat) -> Nat:
  match d:
    case 0n:
      leaf(i)
    case 1n+e:
      a b = tree(e, i) tree(e, Nat.add(i, 1n))
      Nat.add(a, b)


def main() -> IO(Unit):
  IO.print(Nat.show(tree(21n, 0n)) ++ "\n")
