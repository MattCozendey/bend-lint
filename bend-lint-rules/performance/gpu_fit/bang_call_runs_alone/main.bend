import Base

type T is Data:
  Leaf{v: U32}
  Node{l: T, r: T}

type P is Data:
  P{x: F32, y: F32}

def walk(t: T) -> U32:
  match t:
    case Leaf{v}:
      v
    case Node{l, r}:
      a b = walk(l) walk(r)
      (a + b : U32)

def grow(d: Nat, +s: U32, p: P) -> U32:
  match d:
    case 0n:
      s
    case 1n++e:
      a b = grow(e, (s * 2 : U32), P{1.0, 2.0}) grow(e, (s * 2 + 1 : U32), P{1.0, 2.0})
      (a + b : U32)

def sum(xs: List<&2, U32>, acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{x, rest}:
      sum(rest, (acc + x : U32))

def main() -> U32:
  # bend-lint: expect-next performance/gpu_fit@warning -- sum! runs on one GPU thread
  sum!([1, 2, 3], 0)
