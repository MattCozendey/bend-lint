# Native Bend benchmark probe

Run from the repository root in WSL on Windows, or from a native shell on
macOS/Linux:

```bash
bash lab/native/bench-probe/run.sh
```

The script uses the repository-local `.tools/bend-local/bin/bend` executable
by default, or a Bend 2.0.32 executable supplied through `BEND_BIN`. Provision
the compiler separately; the local executable was built from pinned
`vendor/bend` with Bun once, so a fresh checkout is not yet Bun-free. The
script builds three native binaries into ignored `scratchpad/bench-probe/` and
runs the correctness pin before collecting any timings.

The pin covers every block in `World.chunk(1337n, 0n, 0n)` and the fingerprint
of `Native.image` built from that chunk's y=8 surface with cursor `(8, 8)`. The
chunk phase repeats `World.chunk` 2,048 times; the image phase repeats native
`Image` construction 512 times using a surface materialized before the timer.
Both phases use `IO.now`, which has millisecond precision in the native C lane.

Each timed phase also fingerprints the complete result and performs one small
`IO.print` before reading the ending timestamp. Those effects force the pure
work to finish before the second clock read, avoiding optimizer elision. The
reported phase numbers therefore mean **chunk build plus full-block
fingerprint**, and **native image construction plus image fingerprint**; they
are not bare-kernel timings. The startup control is a separately launched
minimal program that performs one `IO.print`. Full benchmark process wall time
includes correctness validation and setup, but excludes compilation.

The binary runs with `--threads 1 --gpu off` and has no parallel `!` calls.
These measurements support only a native single-thread CPU baseline on the
reported machine; they do not demonstrate browser GPU or multithread
acceleration.
