import Base

def deep(n: Nat) -> U32:
  match n:
    case 0n:
      0
    case 1n+p:
      (deep(p) + 1 : U32)

def spin(n: Nat, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      spin(p, (acc + 1 : U32))

def one() -> U32:
  1

def e(c: Bool) -> U32:
  Bool.pick(U32, c, 7, spin(9n, 0))

def f(c: Bool) -> U32:
  Bool.pick(U32, c, 7, one())

def g(c: Bool) -> U32 -> U32:
  Bool.pick(U32 -> U32, c, x => x, x => deep(9n))

def h(c: Bool) -> U32:
  match c:
    case True{}:
      7
    case False{}:
      deep(9n)

def k(c: Bool) -> {Bool.pick(U32, c, 7, deep(9n)) == Bool.pick(U32, c, 7, deep(9n)) : U32}:
  {==}
