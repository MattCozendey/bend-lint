# A dense layer over a batch, as an LLM writes it: lists everywhere, the
# whole weight matrix shared by both calls of every fork, a row looked up
# by index, and loops that are not tail calls.
import Base

def pow2(d: Nat) -> Nat:
  match d:
    case 0n:
      1n
    case 1n+p:
      +h = pow2(p)
      Nat.add(h, h)

def make_row(m: Nat, +s: U32) -> List<&2, U32>:
  match m:
    case 0n:
      Nil{}
    case 1n+p:
      U32.shrn(U32.mul(s, 2654435761), 24n) <> make_row(p, U32.add(s, 1))

def make_matrix(n: Nat, +m: Nat, +s: U32) -> List<&2, List<&2, U32>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      make_row(m, s) <> make_matrix(p, m, U32.add(s, 7919))

def or_empty(r: Maybe<&2, List<&2, U32>>) -> List<&2, U32>:
  match r:
    case None{}:
      Nil{}
    case Some{r}:
      r

def row(w: List<&2, List<&2, U32>>, i: Nat) -> List<&2, U32>:
  or_empty(List.get(&2, List<&2, U32>, w, i))

def dot(xs: List<&2, U32>, ys: List<&2, U32>) -> U32:
  match xs ys:
    case Nil{} _:
      0
    case h <> t Nil{}:
      0
    case a <> at b <> bt:
      U32.add(U32.mul(a, b), dot(at, bt))

# rows i .. i + 2^d - 1 of w times x
def mv(d: Nat, +w: List<&2, List<&2, U32>>, +x: List<&2, U32>, +i: Nat) -> List<&2, U32>:
  match d:
    case 0n:
      [dot(row(w, i), x)]
    case 1n++p:
      a b = mv(p, w, x, i) mv(p, w, x, Nat.add(pow2(p), i))
      List.append(&2, U32, a, b)

def sum(xs: List<&2, U32>) -> U32:
  match xs:
    case Nil{}:
      0
    case h <> t:
      U32.add(h, sum(t))

# the checksum of w times each of b inputs
def batch(b: Nat, +d: Nat, +m: Nat, +w: List<&2, List<&2, U32>>) -> U32:
  match b:
    case 0n:
      0
    case 1n++p:
      U32.add(sum(mv(d, w, make_row(m, U32.from_nat(p)), 0n)), batch(p, d, m, w))

def main() -> IO(Unit):
  +d: Nat = 10n
  +m: Nat = 1024n
  IO.print(U32.show(batch(64n, d, m, make_matrix(pow2(d), m, 1))))
