# The same tree, but each leaf builds a three-field node first.
#
# If the cost of the uneven workload were allocation, this would change the
# cpu/wall ratio; docs/benchmarks.md records that it does not.
import Base

type Node is Data:
  Node{a: Nat, b: Nat, c: Nat}


def leaf.node(n: Node) -> Nat:
  Node{a, b, c} = n
  Nat.add(a, Nat.add(b, c))


def leaf(+i: Nat) -> Nat:
  leaf.node(Node{Nat.add(i, 1n), Nat.add(i, 2n), Nat.add(i, 3n)})


def tree(+d: Nat, +i: Nat) -> Nat:
  match d:
    case 0n:
      leaf(i)
    case 1n+e:
      a b = tree(e, i) tree(e, Nat.add(i, 1n))
      Nat.add(a, b)


def main() -> IO(Unit):
  IO.print(Nat.show(tree(21n, 0n)) ++ "\n")
