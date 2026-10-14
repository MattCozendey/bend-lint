# AGENTS.md — bend-night-train

Research project: a **Bend 2** language study, built around a translation of the
WebGL demo «Ночной поезд — из окна» into Bend 2. The port is the vehicle; the
deliverable is knowledge about the language.

When using Bend:
- run `bend guide` to learn it
- use `LAWS.bend` to keep important rules
- run `bend PROOF.bend` before committing
- parallelize the code whenever possible

## Ground rules

- **Parallelize by default.** Bend's only concurrency primitive is the parallel
  let (`a b = f(x) g(y)`) and the `!` GPU/CPU-parallel call. Any pure work that
  splits into independent halves must be written as a parallel call. Sequential
  code must be justifiable: divergent control flow, a single reduction, or a
  measurement baseline.
- **Laws before features.** A property that must never break belongs in
  `LAWS.bend` (human-owned, never weakened to make a build pass) and is proven
  in `PROOF.bend`. Never edit a law to accommodate an implementation bug; fix
  the implementation or report the law as unprovable and explain why.
- **`bend PROOF.bend` is the gate.** It must print `All terms check.` before
  anything is committed. A proof left as `?TODO` is a commit blocker unless the
  commit message says which law is open and why.
- **Measure, don't claim.** Every performance statement in `docs/` must have a
  command the reader can re-run and a recorded number produced by it.

## Toolchain

The shell is sandboxed and `$HOME` is read-only, so a bare `bend` fails when it
tries to touch `~/.bend`. Always use the wrapper:

```sh
./tools/bend <file.bend>              # type-check, then run on the JS backend
./tools/bend <file.bend> -o out       # native binary (clang)
./tools/bend <file.bend> -o out.c     # emit C
./tools/bend <file.bend> -o out.js    # emit JS
./tools/bend PROOF.bend               # the laws gate
```

`tools/bend` sets `BEND_HOME` inside the workspace and disables telemetry.

The host has an **RTX 4090 Laptop (16 GB, driver 580.178.04, CUDA 13.0)** and
the device is reachable from the shell: `nvidia-smi` answers and `/dev/nvidia*`
exists.  The CUDA toolkit is the distro package -- `nvcc` 12.0 at
`/usr/bin/nvcc`, `cuda.h`/`nvrtc.h` in `/usr/include`, `libcuda`/`libnvrtc` in
`/usr/lib/x86_64-linux-gnu` -- and there is **no** `/usr/local/cuda`, which is
where Bend looks by default.  `tools/bend` therefore sets `CUDA_HOME=/usr` when
that path is missing, so a `!` program builds its device program beside the
binary as `<binary>.gpu` and `--gpu` runs the quadtree on the device.

Two failure modes are easy to confuse.  `bend: --gpu on, but this binary
found no GPU device` means the *binary* was built without CUDA (the `.gpu`
file is absent), not that the machine lacks a GPU.  And the GPU lane needs
**clang 19+**: Bend picks `clang-19` itself when it is installed, but clang 18
silently produces a CPU-only build.  Verify the device with `lspci`,
`/proc/driver/nvidia/gpus/` and `nvidia-smi` before claiming anything about it.

The renderer in `src/` contains **no `!` call**: measured on this host, the tag
gave the rasteriser the same digest and the same host CPU time, while costing
about 0.3 s per process to load the device program -- a factor of three for the
live view, which starts one process per frame.  It was removed.  The notes above
stay because they are what a `!` experiment needs; `probes/bench/bang.bend` is
the probe that measures the lane, and `docs/journal.md` has the numbers.

## Never publish

`tools/bend` refuses `--publish`, and so should you.  hub.bend-lang.com has no
accounts, no names and no versions: a package is named by the hash of its
contents and served immutable, so there is nothing to delete it with.  Anything
uploaded stays public for good.  The guard can be lifted with
`BEND_ALLOW_PUBLISH=1`, and **only a human may set it** -- an agent must not,
not even to "test" the publish path.

The general rule behind this one: anything irreversible that leaves this
machine -- publishing, pushing to a registry, sending mail, opening a public
issue -- happens only because the human asked for it, in words, in the current
conversation.  Not because a past summary said the toolchain should be probed.

## Layout

- `src/` — the Bend implementation, a CPU rasteriser: `raster.bend` (the frame
  and the tile loop), `rt.bend` (types and camera), `shade.bend` (fragment and
  sky shading), `world.bend`, `inst.bend`, `carriage.bend` (triangle soup),
  `ride.bend` (the demo's camera and lights), `geo.bend` and `trk.bend`
  (geometry and the track curve), `color.bend` (F32 triple to `U32`),
  `main.bend` (the headless driver).  `shape.bend` is the pixel-free frame
  skeleton the laws are stated on.  `scene.bend` is the ray marcher's world:
  the renderer no longer imports it, and the only thing still reached from it is
  `Scene.slots`, which `consist_slots` is a law about.  The ray marcher itself
  is on the branch `legacy/raymarch`.
- `LAWS.bend`, `PROOF.bend` — the laws gate at the repo root, by convention.
- `bench/` — benchmark drivers and their raw output.
- `docs/` — research output in **English** (the primary copy): `journal.md`
  (chronological), `language-notes.md` (verified language behaviour),
  `reference-demo-spec.md` (what the original WebGL demo does), `benchmarks.md`
  (numbers), `laws.md` (what is provable).  The Russian originals live under
  `docs/ru/`; `README.md` is English with `README.ru.md` beside it.
- `reference/` — the original HTML demo, kept verbatim for provenance.
- `tools/` — the `bend` wrapper, the reference renderer/comparison tools, and
  small scripts.

## Writing

- User-facing documents are **English** (the primary copy): `README.md`,
  `docs/**`.  The Russian translations live under `docs/ru/`, with
  `README.ru.md` beside `README.md`.
- Code comments, `AGENTS.md`, and commit messages are **English**.
- `docs/journal.md` is append-only: every session adds a dated entry with what
  was tried, what worked, what broke, and the exact command that showed it.

## Commits

- One logical change per commit; `bend PROOF.bend` must pass first.
- Never `--no-verify`.
