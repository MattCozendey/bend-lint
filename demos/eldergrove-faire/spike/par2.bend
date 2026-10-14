import Base

def mk(k: Nat, +x: U32, acc: +List<U32>) -> +List<U32>:
  match k:
    case 0n:
      acc
    case 1n+p:
      mk(p, (x * 3 + 1 : U32), x <> acc)

def sum(xs: +List<U32>, +acc: U32) -> U32:
  match xs:
    case []:
      acc
    case h <> t:
      sum(t, (acc + h : U32))

def tree(+d: Nat, +x: U32) -> U32:
  match d:
    case 0n:
      sum(mk(2000n, x, []), 0)
    case 1n+p:
      a b c e = tree(p, (x * 4 : U32)) tree(p, (x * 4 + 1 : U32)) tree(p, (x * 4 + 2 : U32)) tree(p, (x * 4 + 3 : U32))
      (a + b + c + e : U32)

def main() -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    r : U32 = tree(8n, 1)
    t1 : Nat <- IO.now()
    IO.print(U32.show(r) ++ " in " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
