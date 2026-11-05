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
  a b = spin(3n, 1) spin(3n, 2)
  # bend-lint: expect-next performance/bang_after_fork@warning -- runs after a fork
  host!(4n, (a + b : U32))
