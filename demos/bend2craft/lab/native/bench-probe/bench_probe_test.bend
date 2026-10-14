import Base
import ./bench_probe.bend as Bench

def main() -> IO(Unit):
  Bench.check_correctness()
