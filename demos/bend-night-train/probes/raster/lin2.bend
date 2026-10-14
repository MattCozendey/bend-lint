import Base

type F is Data:
  F{a: F32, b: F32}

def F.iw(f: F) -> F32:
  F{+a, b} = f
  a

def pick(yes: Bool, +v: F32, old: F) -> F:
  match yes:
    case True{}:
      F{v, 0.0}
    case False{}:
      old

# two uses of `old` on the same path: expected to be rejected
def upd.bad(old: F, +v: F32) -> F:
  pick(F32.is_gt(v, F.iw(old)), v, old)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(Nat.show(1n) ++ "\n")
