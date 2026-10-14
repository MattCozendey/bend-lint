# A measurement, not a test: a random read from 2^21 entries through a
# copyable Vec tree against one through a linear Array read by a helper
# chain, ten million reads each. Build natively and time both:
#
#   bend bench/lookup.bend -o lookup
#   BENCH=vec ./lookup --threads 1; BENCH=array ./lookup --threads 1
#
# The sums differ because the two fills run in opposite orders.
import Base
import ../src/vec.bend as V

def Bench.reads() -> Nat:
  U32.to_nat(10000000)

def Bench.size() -> U32:
  2097152

def Bench.lcg(+x: U32) -> U32:
  (x * 1664525 + 1013904223 : U32)

def Bench.fill.go(n: Nat, +x: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+m:
      Bench.fill.go(m, Bench.lcg(x), ((x >> 24n : U32) <> acc))

def Bench.vec.go(n: Nat, +v: V.Vec, +x: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+m:
      Bench.vec.go(m, v, Bench.lcg(x), (acc + V.Vec.get(v, (x >> 11n : U32)) : U32))

def Bench.vec() -> U32:
  Bench.vec.go(Bench.reads(), V.Vec.of_list(Bench.fill.go(U32.to_nat(Bench.size()), 7, []),
    Bench.size()), 1, 0)

def Bench.afill(n: Nat, a: Array<U32>, +x: U32, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+m:
      Bench.afill(m, Array.set(U32, a, i, (x >> 24n : U32)), Bench.lcg(x), (i + 1 : U32))

# The array loop's state: the array has one owner, so the read's pair is
# taken apart by a helper that rebuilds the state.
type Bench.St is Type:
  St{a: Array<U32>, x: U32, acc: U32}

def Bench.arr.fin(+x: U32, +acc: U32, p: Array<U32> & U32) -> Bench.St:
  (a, v) = p
  St{a, Bench.lcg(x), (acc + v : U32)}

def Bench.arr.step(st: Bench.St) -> Bench.St:
  St{a, +x, acc} = st
  Bench.arr.fin(x, acc, a[(x >> 11n : U32)])

def Bench.arr.go(n: Nat, st: Bench.St) -> U32:
  match n:
    case 0n:
      St{a, x, acc} = st
      acc
    case 1n+m:
      Bench.arr.go(m, Bench.arr.step(st))

def Bench.arr() -> U32:
  a = [0 : U32^21n]
  Bench.arr.go(Bench.reads(), St{Bench.afill(U32.to_nat(Bench.size()), a, 7, 0), 1, 0})

def Bench.run(arr: Bool) -> IO(Unit):
  match arr:
    case True{}:
      IO.print("array " ++ U32.show(Bench.arr()))
    case False{}:
      IO.print("vec " ++ U32.show(Bench.vec()))

def main() -> IO(Unit):
  do IO<Unit>:
    which : String <- IO.try(String, IO.get_env("BENCH"))
    Bench.run(String.eq(which, "array"))
