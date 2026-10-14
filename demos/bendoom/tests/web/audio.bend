import Base

def Samples(n: Nat) -> List<&2, F32>:
  match n:
    case 0n:
      []
    case 1n+m:
      0.25 <> F32.neg(0.5) <> Samples(m)

def Kept(p: Audio & U32) -> Audio:
  (a, q) = p
  a

def Report(p: Audio & U32) -> IO(Audio):
  (a, q) = p
  do IO<Audio>:
    shown : Unit <- IO.print(U32.show(q))
    return a

def Feed(n: Nat, a: Audio) -> IO(Unit):
  match n:
    case 0n:
      do IO<Unit>:
        closed : Unit <- Audio.close(a)
        IO.print("closed")
    case 1n+m:
      do IO<Unit>:
        waited : Unit <- IO.sleep(5)
        next : Audio & U32 <- Audio.write(a, Samples(128n))
        Feed(m, Kept(next))

def Invalid(r: Result<&1, &1, U32 & String, Audio>) -> IO(Unit):
  match r:
    case Fail{err}:
      IO.print("invalid rate rejected")
    case Done{a}:
      Audio.close(a)

def main() -> IO(Unit):
  do IO<Unit>:
    bad : Result<&1, &1, U32 & String, Audio> <- Audio.open(0)
    checked : Unit <- Invalid(bad)
    a : Audio <- IO.try(Audio, Audio.open(44100))
    full : Audio & U32 <- Audio.write(a, Samples(4096n))
    first : Audio <- Report(full)
    overflow : Audio & U32 <- Audio.write(first, Samples(1n))
    second : Audio <- Report(overflow)
    Feed(1000n, second)

#|invalid rate rejected
#|4096
#|4096
#|closed
