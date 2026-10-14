import Base
import ./simulation.bend as S
import ../shared/config.bend as Config

def main() -> IO(Unit):
  do IO<Unit>:
    +n : U32 <- Config.read("PI_SAMPLES",1000000)
    +kind : U32 <- Config.read("PI_NEEDLE",0)
    seed : U32 <- Config.read("PI_SEED",42)
    inner : U32 <- Config.read("TREE_DEPTH",5)
    start : Nat <- IO.now()
    +replay : S.Replay = S.run!(8n,0,n,U32.to_nat(inner),U32.is_eq(kind,1),seed)
    end : Nat <- IO.now()
    IO.print_err("COMPUTE_MS " ++ Nat.show((end - start)))
    IO.print("PROBABILITY " ++ U32.show(S.failures(replay)))
    IO.print(S.text(replay,0,0,U32.is_eq(kind,1)))
