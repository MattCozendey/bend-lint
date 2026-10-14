import Base

def sel(c: Bool, a: Nat, b: Nat) -> Nat:
  match c:
    case True{}:
      a
    case False{}:
      b

def work(k: Nat, +n: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      work(p, n, ((acc * 1664525 + n) .^. (acc >> 7n) : U32))

def tree(+d: Nat, +x: U32) -> U32:
  match d:
    case 0n:
      work(sel(U32.is_eq((x >> 14n : U32), 4) || U32.is_eq((x >> 14n : U32), 5), 4000n, 1n), x, x)
    case 1n+p:
      a b c e = tree(p, (x * 4 : U32)) tree(p, (x * 4 + 1 : U32)) tree(p, (x * 4 + 2 : U32)) tree(p, (x * 4 + 3 : U32))
      (a + b + c + e : U32)

def main() -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    r : U32 = tree(8n, 1)
    t1 : Nat <- IO.now()
    IO.print(U32.show(r) ++ " in " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
