*English | [Русский](ru/journal.md)*

# Journal

A chronology of the work: what we tried, what broke, how we fixed it. Errors are
quoted verbatim — that is what people search for later. The detailed reference on
the language, gathered by a separate investigation, lives in
`docs/language-notes.md`; here there is only what this project stumbled over.

## 2026-09-18

### Installation and the stand

`curl -fsSL https://bend-lang.com/install.sh | sh` installed Bend 2.0.5. The
launcher writes its state to `~/.bend` (`rep`, `last`, `id`), and this working
environment keeps `$HOME` read-only, so every run printed
`cannot create /home/user/.bend/last`. We made `tools/bend` — a wrapper that
moves `BEND_HOME` inside the working copy and disables telemetry.

Checked straight away: `!` (the GPU call) built with clang 18, although the guide
asks for 19+; no `.gpu` file was created. The cause is a silent CPU-only build
under clang 18, not a missing GPU — the host has an RTX 4090 Laptop. The CUDA
setup and the two easy-to-confuse failure modes are written out in `AGENTS.md`.

### Laws and proofs: the gate works

The first thing we assembled was the minimal `LAWS`/`PROOF` pair from the guide
(`add_zero` on `Nat`). `All terms check.` — and, more importantly, a deliberately
wrong law fails with a clear message:

```
- expected : Nat.add(x, 1n)
- observed : x
```

That is the main reason the language is interesting at all: an error prints
`expected`/`observed` and a location, not "type mismatch".

### The port: what broke and why

We wrote the renderer incrementally, compiling after every step. Below are the
errors in the order they appeared. Almost every one is not a "bug" but a
consequence of a rule you have to know in advance.

**1. Operators without an annotation belong to `Nat`.**
`F32.abs(px - tx : F32)` — error `expected : a term / observed : ':'`. The
annotation must be in parentheses: `F32.abs((px - tx : F32))`. And conversely,
`(a : F32) * b` is also wrong: `*` ends up **outside** the annotation and goes to
`Nat`. The rule: every arithmetic argument of a call and every arithmetic body of
a `def` is wrapped in `( … : T )` as a whole.

**2. `>=` comparisons inside `( … : Bool )`.**
`(ax >= ay : Bool)` is expanded by the compiler into `Bool.is_ge`, which does not
exist: `expected : a defined name / observed : Bool.is_ge`. A comparison on F32
must be named explicitly: `F32.is_ge(ax, ay)`. The `: Bool` parentheses are only
needed for `&&`/`||`.

**3. Destructuring — parameter only.**
Three different errors in a row:

```
- a match cannot scrutinize a computed value: give it its own def
- a match cannot scrutinize a local binder: give it its own def
```

That is, `V3{x, y, z} = call()` and `V3{x, y, z} = local` are forbidden, while
`V3{x, y, z} = parameter` is allowed. The workaround: accessor functions
(`V3.px`, `V3.py`, `V3.pz`) or a separate `def` with the right parameter.

**4. `let` before a `match` on a parameter.**
`+h2 = …` then `match up:` →
`match scrutinees in binder order (this variable is unbound, consumed, or out
of order: reorder the match)`. First `match`, then `let` inside the branch.

**5. Mutual recursion is forbidden, and this breaks the usual refactoring.**
The most expensive finding. We wanted to move the `Bool` dispatch into a
separate `def`:

```python
def march(...):
  march.if(stop, ...)          # not allowed
def march.if(stop, ...):
  march(...)                   # and this is not allowed either
```

`expected : a defined name / observed : Scene.march.if` — definitions must come
**before** use, and the "wrapper ↔ helper" pair forms a cycle. The right way is a
nested `match` in a single `def` that takes the `Bool` **as a parameter**:

```python
def march(+i: Nat, +stop: Bool, …):
  match i:
    case 0n: t
    case 1n+k:
      match stop:
        case True{}: t
        case False{}: … march(k, …)   # itself — allowed
```

The same had to be done when walking a quadtree row (`Px.row`).

**6. A multi-scrutinee `match` requires all combinations.**
`match d img:` with branches `0n Pix{c}` and `1n+e Qua{…}` fails:
`expected : cases for Qua`. All four combinations are needed, or (simpler)
`match`es nested in each other.

**7. `match` is not an expression.**
In a `do` block:
`expected : a term (a match heads a def body, not a term)`.
The cure is to move it into a separate `def`.

**8. `do` block: a `let` without an annotation breaks the block silently.**
```python
do IO<Unit>:
  +v = F.c(1, 2)      # the block ends here
  IO.print(...)        # expected 'def', 'type' or 'law', observed 'I'
  IO.print(...)        # and this is already outside the block
```
With `v : U32 = F.c(1, 2)` the same block works. Separately: **tuple
destructuring in `do` is not a statement.** `(f, r) = fr` is parsed as the
block's return value, and the block's tail falls off. The cure is to move the
unpacking into a `def` where the tuple is a parameter.

**9. Name algebra on import.**
`import ./scene.bend as Scene` gives access to the name `Scene.` + the **full**
name of the `def`. That is, `import ./color.bend as Color` and `def Color.pack`
give `Color.Color.pack`, while the short `Color.pack` gives
`expected : a defined name`. We had to drop the inner prefixes: in `color.bend`
it is `pack`, `red`, `green`, and outside it is `Color.pack`.

**10. Argument types of shifts.**
`U32.shln(a: U32, n: Nat)`, `U32.shrn(a: U32, n: Nat)`. The literal `1` is
`U32`, so `U32.shrn(half, 1)` does not compile: you need `1n`.

**11. Declaration order is part of the program.**
After every edit we had to reorder `def`s, so `tools/order.py` appeared: it
builds a reference graph between a file's top-level items and sorts them
topologically, and on a cycle it prints the guilty chain. It was precisely this
that caught `Px.row → Px.row.sel → Px.row`.

**12. Syntax trivia, each costing one compilation.**
- `Qua{tl: a, tr: b, …}` — named fields in a constructor are not supported, only
  positional: `Qua{a, b, c, f}`.
- `def Laws.frame8:` — parentheses needed: `def Laws.frame8():`.
- Equality in a `law` must be on one line: a line break inside `{ … : Nat}` gives
  `expected : a term / observed : ':'`.

**13. Affine use is the most common error.**
`expected : cars / observed : cars (consumed more than once)`. Everything used
twice is marked `+`: parameters (`+cars`), fields in a pattern
(`Car{+cc, +ss, …}`), bindings (`+img : Image = …`). At the same time `+`
requires `Data`: it cannot be put on a function.

### What came out of it

The first frame came out white: `Cam.fit` rewrote the camera but took `cx`/`cy`
(the screen centre) from the **input** camera, where they are zero — division by
zero gave `dir=nan,nan,nan`, and `F32.clamp` of NaN returned 1.0, that is, white.
The second frame came out flipped: the PPM rows were assembled from last to
first, while `++` appends to the end. Both errors were found in a single run,
because the renderer prints a checksum and dumps the PPM — there was something to
look at.

### The day's outcome

- `bend PROOF.bend` → `All terms check.` in 0.25–0.34 s.
- 108 benchmark runs of the ray marcher: the same checksum at any thread count
  and with both call variants.
- The ray marcher's speed-up on 32 cores — 2.7×, while total CPU grows 8×. The
  rasteriser that replaced it does better and is re-measured in
  `docs/benchmarks.md`: 5.4× at 1024x1024, with no ceiling at 32 threads.
- The overall picture on provability is in `docs/laws.md`: the structure is
  checked, the numbers are not.

### Publishing to the hub: how one process mistake got out

The agent writing `docs/language-notes.md`, while investigating the toolchain,
ran `bend tiny.bend --publish`. The file is 79 bytes, `import Base` and
`IO.print("compile me")`, nothing project-related. But it **stayed in the public
hub forever**:
`https://hub.bend-lang.com/0xdc5e239cf0bf288e1735d5852f820f34/tiny.bend`.

It cannot be revoked by the service's design, not by an oversight: "no accounts,
no names, no versions", responses are served with `cache-control: immutable`, and
there is no identity that could authorise deletion. The client has no inverse
operation.

What was done: `tools/bend` now refuses `--publish` (exit code 2) and allows it
only with `BEND_ALLOW_PUBLISH=1`, which a human sets. The rule is written in
`AGENTS.md`.

What was done wrong: a subagent got access to a tool with an irreversible public
action, and there was no guard on it. That it was a harmless hello that flew out
is luck.

### A second renderer: the ray marcher becomes the rasteriser

The ray marcher renders a 512x512 frame in 0.30 s at 16 threads. That is a still
every three seconds, and the request was a version that can be watched. The old
renderer was moved to the branch `legacy/raymarch` (tag `raymarch-legacy`) and
the main branch got a tile rasteriser: `src/raster.bend` with `rt.bend` (types,
camera, projection, cull), `shade.bend` (the fragment and the sky),
`world.bend`, `inst.bend`, `carriage.bend` (triangle soups), `ride.bend` (camera
and lights), `geo.bend`, `trk.bend`. The frame is still one quadtree and still
the only place work is divided, but the leaf is a tile of 8x8 pixels carrying the
triangles whose screen bounding box reaches it, and a pixel is shaded exactly
once, by the triangle that won it.

The ray marcher is not dead weight on that branch: it is the only renderer whose
pixel is a pure function of the pixel, and the laws were stated on it.

### Anti-aliasing, which was the largest single error

The demo asks WebGL for `antialias: true`, which is 4x MSAA, and the rasteriser
of course had none: its edges were hard, and the difference from the reference
was concentrated exactly there. Four samples per pixel at +-0.25 in `Tile.px`,
averaged in the packed `U32` (`Px.avg4`) rather than in floats, was the whole
change. At 1024x1024: MAE 0.002187 -> 0.001850, PSNR 40.71 -> 43.17 dB. At
512x512: 0.002716 -> 0.002056, PSNR 42.24 dB. It costs about 12% of a depth-8
frame.

### The text emitter cost more than the render

The live view writes P3 (ASCII) PPM, and the numbers it writes are not free:
text was 70-80% of a live frame. Three changes, each measured against an
unchanged image (byte-identical PPMs at depth 6):

- a per-tile `IO.write` instead of concatenating a row's tiles at every level of
  the tree (`String.concat` is a right fold, so the row builder was copying the
  row once per tile);
- a decimal emitter that writes the digits straight onto the rest of the line
  (`Px.dig.one/two/three`), instead of going through `U32.show`, which costs
  about four times as much per pixel;
- one right-to-left cons pass per tile (`Tile.text(xs, tail)`), so no channel
  string is built and then copied.

Depth 9 went from about 0.64 s to 0.34 s per frame, depth 8 from 0.27 to 0.19.

### `!` compiles, changes nothing, and costs a third of a second a process

`probes/bench/bang.bend` settles what `!` does here: a uniform F32 tree under
`!` reports 0.00-0.01 s of host CPU at any thread count, while the same tree
without `!` reports 0.17-0.20 s and scales with `--threads`. The device holds the
recursion; that is the signature.

The rasteriser's own tree does not behave that way. `Frame.build!(...)` builds a
498 KB cubin as `out/night-train.gpu` and returns the *same digest* at every
depth -- depth 10: `3959815329` either way -- but the host CPU time is the same
with and without it (depth 10, 32 threads: 4.12 s against 4.43 s). The
renderer's leaf is divergent -- every tile walks a different number of triangles
-- which is the shape the guide says stays on the CPU, while this probe's tree is
uniform.

What decided it was the price of the tag itself. A program that contains `!`
builds a device program and **loads it at every process start**: the same
renderer with the tag ran a depth-8 frame in 0.45-0.51 s and without it in
0.15-0.16 s, at every thread count -- about 0.3 s per process, spent before any
work begins. `tools/live.sh` starts one process per frame, so the tag bought
nothing and cost a factor of three. The driver, the `bang` parameter on
`frame.chunks`, `Frame.build.at` and all the `NT_BANG` plumbing were deleted,
the stale `out/night-train.gpu` removed, and the digests re-checked unchanged
(depth 8 `299380445`, depth 9 `1065901264`, depth 10 `3959815329`). The probe
stays: it is the only place the device lane is still measured.

That dispatch cost one language finding on the way. A `match` must scrutinise
its binders in the order they were bound, so a two-arm match on the flag could
not sit after the camera and the scene, where it belonged:

```
- message  : match scrutinees in binder order (this variable is unbound,
             consumed, or out of order: reorder the match)
```

It went into a `def` of its own, `Frame.build.at`, whose body is the match and
whose first parameter is the flag -- and that def is exactly what the
measurement above then deleted.

### The live view, and what a frame costs

`tools/live.sh` renders the demo's own ride to stdout as a P3 PPM stream, one
frame per process, and pipes it into `ffplay`: the renderer can be watched while
it runs. On the binary without `!`, at 24 threads:

| | depth 8 (256x256) | depth 9 (512x512) |
|---|---|---|
| one process per frame | 178 ms | 228 ms |
| ten frames in one process | 205 ms | 309 ms |

So the live view runs at **5.6 fps at 256x256 and 4.4 fps at 512x512**, and at
depth 8 the process-per-frame shape is the faster one -- the frame is short
enough that re-parsing costs less than the batch's extra state. Of those 178 ms
the render itself is 155 ms and the ASCII decimal emitter the remaining 23 ms:
after the emitter work above, writing the PPM is no longer the bottleneck.

### The comparison video

A still apiece was not convincing, so `tools/compare_video.sh` records the ride
twice -- the Bend renderer and the original demo -- and stacks the two clips
frame against frame into `assets/video/compare-512.mp4`, with a poster frame
and an animated GIF beside it. Both cameras are the pinned comparison camera
(`s = 110 + 24.5 t`, yaw 0, pitch -0.02, no sway), and the clip is 25 fps
because 1000/25 is 40 ms exactly: at 24 fps the render's integer-millisecond
time step rounds to 41 ms and the two sides drift three metres apart by the end
of eight seconds.

Two tooling problems had to be solved to shoot it:

- `tools/render_reference.py` grew a `--frames` sequence. One frame per process
  cost 5.5 s, of which about 4 s is launching the browser; a sequence shares one
  browser and pays about 0.4 s a frame, so 200 frames take two minutes instead
  of eighteen.
- `tools/video_frames.py` stacks the frames with the same labelled side-by-side
  that `tools/compare.py` draws for a still, so the video and the still
  comparison are the same picture and cannot drift apart.

The first attempt at the sequence was wrong, and the numbers caught it. Frame
0 of the clip agreed with the still to the digit (MAE 0.002056), and the error
then climbed along the clip -- 0.0036, 0.0093, 0.0516 -- while the render side
of every frame was byte-identical to a single-frame render at that camera. The
reference side was the one drifting: the demo's motes and smoke are **stateful**
arrays that its draw call updates, so rendering frame *i* after frame *i-1* is
not the same picture as a fresh page at the same camera. Seeding does not help
-- restoring the PRNG between frames changes nothing, because the state is in
the arrays, not in the generator. A page per frame does: the frames are then
byte-identical to the stills, at 0.4 s each. The comparison is only as honest
as the reference is, and a clip of a drifting reference would have shown the
drift as our error.

Re-shot that way, all 200 frames of the clip land between 0.0021 and 0.0037 MAE
against the reference -- the frame-to-frame wobble is the scene riding past, not
a drift.

### The demo culls the consist, and culling it here is worse

The reference enables `CULL_FACE` for everything except the track
(`docs/reference-demo-spec.md` §5.4). The rasteriser only culled the ground, so
the fix looked obvious: split the scene three ways (ground, track, the rest) and
cull the last. It is measurably *worse* -- 512x512 MAE 0.002056 -> 0.004961,
PSNR 42.24 -> 37.19 dB -- which says the winding of the consist and of the
instanced meshes is not the demo's, and that both of their faces have to be drawn
to land on the same picture. Reverted, with the number recorded in
`Raster.frame`.

### What is still wrong: one band of the near carriage

At 512x512 the frame agrees with the reference to 1/255 almost everywhere, and
the residual is concentrated in one band of the near carriage's side (x 0..56,
y 168..194) plus the lit window edges. In that band the fragment's normal points
straight up -- measured by returning the normal from `Shade.Sh.v` in a scratch
build: `N = (+0.14, +1.00, +0.01)` -- where the reference shows a green wall.
An up normal takes the top of the hemisphere ambient, which is the blue end, and
no window light at all, which is exactly the wrong colour and the missing warmth.
So the cause is not the shading (the same shader is right one tile away) but
which triangle wins those pixels. Culling does not fix it -- see above -- and the
mesh's own winding has to be understood first. Recorded, not fixed.
