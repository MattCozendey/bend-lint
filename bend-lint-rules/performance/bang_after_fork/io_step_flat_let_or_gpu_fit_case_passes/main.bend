import Base

def host(+d: Nat, +i: U32) -> U32:
  match d:
    case 0n:
      i
    case 1n+e:
      a b = host(e, (i * 2 : U32)) host(e, (i * 2 + 1 : U32))
      (a + b : U32)

def spin(n: Nat, +x: U32) -> U32:
  match n:
    case 0n:
      x
    case 1n+m:
      spin(m, (x + 1 : U32))

def walk(n: Nat, x: U32) -> U32:
  spin(n, x)

def f() -> U32:
  +s = spin(9n, 1)
  host!(4n, s)

def g() -> IO(Unit):
  do IO<Unit>:
    s : U32 = host(4n, 1)
    t : Nat <- IO.now()
    IO.print(U32.show(host!(4n, s)))

def h() -> U32:
  +s = host(4n, 1)
  walk!(3n, s)
