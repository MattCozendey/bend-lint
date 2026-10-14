#!/usr/bin/env python3
"""Run a command several times and report wall and CPU time.

`/usr/bin/time` gives centisecond resolution here, which is too coarse for
the small runs that isolate scheduler behaviour.  This measures with
perf_counter and reads the child's CPU time from getrusage, so a run can be
split into "how long did it take" and "how much CPU did it burn" -- the
second is what exposes a spinning scheduler.

  python3 bench/measure.py --reps 5 -- ./out/night-train --threads 32
  python3 bench/measure.py --env NT_DEPTH=8 --env NT_PPM=0 --reps 5 \
      -- ./out/night-train --threads 8
"""

import argparse
import os
import resource
import statistics
import subprocess
import sys
import time


def run_once(cmd, env):
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    t0 = time.perf_counter()
    proc = subprocess.run(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    wall = time.perf_counter() - t0
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    cpu = (after.ru_utime - before.ru_utime) + (after.ru_stime - before.ru_stime)
    return wall, cpu, proc.returncode, proc.stdout.decode().strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--reps", type=int, default=5)
    ap.add_argument("--env", action="append", default=[])
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    args = ap.parse_args()

    cmd = args.cmd[1:] if args.cmd and args.cmd[0] == "--" else args.cmd
    if not cmd:
        print(__doc__)
        return 2

    env = dict(os.environ)
    for kv in args.env:
        k, _, v = kv.partition("=")
        env[k] = v

    walls, cpus, outs = [], [], set()
    for _ in range(args.reps):
        w, c, rc, out = run_once(cmd, env)
        if rc != 0:
            print(f"failed with exit {rc}", file=sys.stderr)
            return rc
        walls.append(w)
        cpus.append(c)
        outs.add(out)

    wall = statistics.median(walls)
    cpu = statistics.median(cpus)
    label = " ".join(args.env)
    print(f"{label} {' '.join(cmd)}")
    print(f"  wall {wall * 1000:9.1f} ms   cpu {cpu * 1000:9.1f} ms   "
          f"cpu/wall {cpu / wall:5.2f}x   runs {args.reps}")
    if len(outs) != 1:
        print(f"  WARNING: non-deterministic output across runs: {sorted(outs)}")
    else:
        print(f"  out  {next(iter(outs))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
