# lab/native

Everything here is an experiment or a measurement. None of it is compiled into
the game: `native/` holds the client that ships, and this tree holds the
questions asked of it and the numbers the answers produced.

Nothing in `native/` imports from this directory. The dependency runs the other
way, because every probe here prices or pins a rule that `native/` owns: a
module in this tree that stopped matching its client would be measuring a
different program.

## Layout

A `lab/native/<module>/` directory is the measurement of the
`native/<module>.bend` it is named for. It holds that module's benchmarks, the
script that runs them, and a README recording what was measured. The module
itself is **not** here; it ships in `native/`.

| directory | measures |
| --- | --- |
| `voxel/` | `native/voxel.bend` - the camera, the region grid and the per-pixel DDA reference raycaster |
| `face/` | `native/face.bend` - the visible-face renderer: extraction, bucketing, projection |
| `frame/` | `native/frame.bend` - frame assembly, the camera basis and the dirty check |
| `paint/` | `native/paint.bend` - the two painters at every window size and thread count, held to the same picture |
| `pointer/` | `native/pointer.bend` - what a display delivers for the mouse, and the client's look end to end on the runtime's grab and on the Windows host |
| `player/` | `native/player.bend` - the player region, collision and the chunk seam |
| `save/` | `native/save.bend` - the `B2CW` snapshot codec and the legacy migration |
| `client-probe/` | `native/client.bend` end to end: the live presented frame rate, every frame's pacing while the player walks, the painter's-algorithm alternative, and the output/array costs underneath it |
| `bench-probe/` | the 16x16 CPU baseline and startup cost |
| `render-probe/` | a 16x16 world-derived image, the smallest thing that renders at all |
| `save-probe/` | the old two-byte `B2CS` cursor codec, superseded by `native/save.bend` |
| `protocol-probe/` | the versioned 28-byte multiplayer frame |
| `tcp-probe/` | that frame inside a bounded ASCII-hex socket envelope |
| `window-probe/` | the 16x16 window/input/frame slice end to end under a real display |

`2026-09-30-native-renderer-investigation.md` is the investigation log: what was
tried, what was measured, and which earlier conclusions the measurements
corrected. It is kept because the measurements are the useful part and because
several of its conclusions contradict what the code looks like at a glance.

## Running one

Each directory has its own `run.sh` or `run-bench.sh`, run from the repository
root:

```bash
bash lab/native/face/run.sh
bash lab/native/voxel/run-parallel.sh
bash lab/native/client-probe/run-fps.sh
```

They need the pinned Bend 2.0.32 CLI from `scripts/bootstrap-native-bend.sh`,
and a graphical display for the ones that open a window.

## What is not in the gate

`scripts/test-suite.sh` runs the focused regressions for the modules that
ship, and the lab benchmarks are not among them. Two of them do not currently
pass their own assertions, and both predate this tree:

- `voxel/voxel_probe_parallel_test.bend` reports `parallel render ignored the
  eye at size 32` and exits non-zero. It also fails at the commit before the
  split, at the module's old path.
- `client-probe/span_probe.bend` passes `span-probe=pass` and then dies with a
  machine stack overflow in the uniform-block walk that follows. This is
  uncommitted work in progress, and it fails the same way at the old path.

Neither is a gate, so neither blocks the build. They are recorded here rather
than fixed, because a measurement that cannot run is a measurement nobody can
check.
