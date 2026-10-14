import Base

type F is Data:
  F{a: F32, b: F32}

def F.iw(f: F) -> F32:
  F{+a, +b} = f
  a

def pick(yes: Bool, +v: F32, old: F) -> F:
  match yes:
    case True{}:
      F{v, 0.0}
    case False{}:
      old

# a `+` parameter, used twice on the same path
def upd.ok(+old: F, +v: F32) -> F:
  pick(F32.is_gt(v, F.iw(old)), v, old)


# and a struct parameter used three times through separate calls
type C is Data:
  C{p: F32, q: F32}


def C.sum(+c: C, +x: F32) -> F32:
  C{p, q} = c
  (p + q + x : F32)


def C.thrice(+c: C) -> F32:
  (C.sum(c, 1.0) + C.sum(c, 2.0) + C.sum(c, 3.0) : F32)


def F.a(f: F) -> F32:
  F{+a, b} = f
  a


def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(F32.show(F.a(upd.ok(F{1.0, 2.0}, 3.0))) ++ "\n")
    IO.print(F32.show(C.thrice(C{1.0, 2.0})) ++ "\n")
