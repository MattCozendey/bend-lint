import Base

# Fork/join workload used to verify the native Bend runtime's parallel lane.
def pow2(d: Nat) -> Nat:
  match d:
    case 0n:
      1n
    case 1n+p:
      +half = pow2(p)
      Nat.add(half, half)

def sum(d: Nat, +start: Nat) -> Nat:
  match d:
    case 0n:
      start
    case 1n++p:
      left right = sum(p, start) sum(p, Nat.add(pow2(p), start))
      Nat.add(left, right)

def main() -> IO(Unit):
  IO.print(Nat.show(sum!(20n, 0n)))
