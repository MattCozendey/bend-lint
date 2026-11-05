import Base

def build(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+m:
      build(m, 1 <> acc)

def then(-R: Type, xs: List<&2, U32>, k: List<&2, U32> -> U32 -> R) -> R:
  k(xs, 7)

def h(n: Nat, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+m:
      then(U32, build(3n, []), xs => k => h(m, (acc + U32.from_nat(List.length(&2, U32, xs)) : U32)))

def once() -> U32:
  then(U32, build(3n, []), xs => k => k)

def io(n: Nat) -> IO(Unit):
  match n:
    case 0n:
      IO.print("done")
    case 1n+m:
      do IO<Unit>:
        args : List<String> <- IO.args()
        io(m)
