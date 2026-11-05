import Base

def count(xs: List<&2, U32>, +n: Nat) -> Nat:
  match xs:
    case Nil{}:
      n
    case Con{x, t}:
      count(t, 1n+n)

def twice(+n: Nat) -> Nat:
  Nat.add(n, n)

def f(k: Nat, +xs: List<&2, U32>, +acc: Nat) -> Nat:
  match k:
    case 0n:
      acc
    case 1n+p:
      f(p, xs, count(xs, acc))

def g(k: Nat, +xs: List<&2, U32>, +acc: Nat) -> Nat:
  match k:
    case 0n:
      count(xs, 0n)
    case 1n+p:
      g(p, xs, twice(acc))

def h(k: Nat, +xs: List<&2, U32>, +acc: Nat) -> Nat:
  match k:
    case 0n:
      acc
    case 1n+p:
      h(p, xs, Nat.add(acc, twice(3n)))

def proof(k: Nat, +xs: List<&2, U32>) -> {count(xs, 0n) == count(xs, 0n) : Nat}:
  match k:
    case 0n:
      {==}
    case 1n+p:
      _ = count(xs, 0n)
      proof(p, xs)
