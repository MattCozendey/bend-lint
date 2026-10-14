import Base
import ./accelerated.bend as A
import ./main.bend as Cli

def calculate(n: Nat) -> Nat:
  A.count!(n)

def main() -> IO(Unit):
  Cli.start(~calculate)
