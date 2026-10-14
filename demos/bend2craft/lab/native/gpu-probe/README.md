# lab/native/gpu-probe

**A throwaway spike, not a painter.** Read the control below before the tables. The question: can the client's textured frame be drawn by a leaf
shaped the way `vendor/bend/guide/SHADERS.md` asks for a device, and what does it cost on a GPU?
Nothing in `native/` imports from here and nothing here is meant to be kept as it is.

`device_probe.bend` reuses the painter's own host half unchanged (`Paint.frame_quads`, `Paint.deal`,
`Paint.span_edges`, `Paint.texel_of`) and adds only the shape the guide asks for: the polygons are dealt on
the host into a quadtree of lists, one per 64-pixel cell; **one bang** forks it to leaves; a leaf is
straight-line `Qua{...}`; a 2x2 block of pixels is one flat loop over a list that carries four colours (a
`def` may only call itself, so there is no early exit, as in the reference's `Blk.go`). No `Array` is on the
device side. `filtered_8.bend` is the same with 8-pixel leaves that each build their own short list of the
polygons that touch them. `bash lab/native/gpu-probe/run.sh` builds both and runs each with `--gpu off` and
`--gpu on`, and prints the power state first.

Measured on an Apple M1 Pro, macOS 27.0, Bend 2.0.35, **on AC power with Low Power Mode off** (the first
runs, on battery with Low Power Mode on, gave the same GPU numbers within 5%, so power was not the cause).
Milliseconds per frame, medians of ten, the textured east view, including the host's read-back walk of the
image, as `lab/native/paint/run.sh` does.

## What it answered

1. **It builds for Metal and draws the right picture.** Bend 2.0.35 compiles the device program in under
   30 seconds. Against the client's own CPU painter, over 1,048,576 pixels at 1024x1024, 54 pixels differ and
   2 by more than 3 in a channel (the most is 12); at 256x256 none differ. Which polygon wins a pixel is
   reproduced exactly, because the probe asks `Paint.span_edges`; the residue is float rounding: the CPU fills a
   span by stepping the texture planes from its first pixel and the device evaluates them at the pixel.
   **A digest-equal textured frame is not available without changing the CPU rule too**, which is a decision.
2. **No version of this is faster than the CPU painter; the first was 45 times slower and the best, after the
   optimizing below, is about 14 times slower.** That is a
   statement about this probe, which keeps the painter's own pixel rules, and not about Bend on a GPU: see 5.

| size | CPU painter (today) | straightforward leaf, CPU pool | `filtered_8`, CPU pool | straightforward leaf, GPU | `filtered_8`, GPU |
| --- | ---: | ---: | ---: | ---: | ---: |
| 256 | 1.4 | 5.5 | 2.1 | 113 | 14.5 |
| 1024 | 6.0 | 17 | 13 | 246 | 134 |

3. **Parallelism was part of it, and then it was not.** The first probe forked to 16-pixel tiles: 4096 leaves
   at 1024x1024 and 256 at 256x256, against the guide's 16384 lanes. Making the leaf smaller (GPU, per frame):

| leaf | 256x256 straightforward | 256x256 filtered | 1024x1024 straightforward | 1024x1024 filtered |
| ---: | ---: | ---: | ---: | ---: |
| 16 px | 116 | 41 | 263 | 185 |
| 8 px | 36 | 14 | 218 | 136 |
| 4 px | 14 | 9.7 | 217 | 174 |
| 2 px | 8.4 | 8.1 | 225 | 248 |

   At 256x256 more leaves took the frame from 116 ms to 8 ms, so the first version did leave the device mostly
   idle. At 1024x1024 the time stops improving at about 130 ms once there are enough leaves, and that is about
   125 ns a pixel at both sizes, so some per-pixel cost is serial and is not occupancy.
4. **Where the time goes, by taking things out** (`filtered_8` at 1024x1024, per frame, GPU against CPU pool;
   the files are `ablate_*.bend`):

| what is left in the leaf | file | GPU | CPU pool |
| --- | --- | ---: | ---: |
| the fork tree and 1M image nodes, an empty list | `ablate_E1_structure` | 25 | 7 |
| + the filtered list built and walked, box test only | `ablate_E2_walk` | 62 | 8 |
| + the coverage test (`span_edges`), flat colour | `ablate_nosky_flat` | 78 | 11 |
| + the texel, light and haze | `ablate_nosky` | 133 | 11 |
| + the sky colour of every unpainted pixel | `filtered_8` | 134 | 13 |

   Not the cause, each measured the same way: allocating a node per pixel (collapsing blocks of four equal
   pixels, 136 to 131 ms), the host walking the 1.4M-node image (reading only its root, 132 ms), the sky (above),
   and power (AC against battery, the same). Every layer is several times slower on the device than on the CPU
   pool, and the empty structure alone costs more than the reference's whole draw of a larger frame.

5. **What the reference does that this does not** (`demos/app_slash_boss_3d/bend3d.bend`, which draws 1920x1200
   at about 6 ms on an M4). This is the difference to explain, and each line is a thing to try, not a finding:
   - A triangle is **two barycentric planes and a depth plane**, so coverage is multiply-adds and compares and
     the nearest wins by comparing depth, in any order. This probe covers a pixel with `Paint.span_edges`, which
     divides five times per candidate, and depends on the polygons being walked nearest first.
   - A colour is **three planes** and a pack. This probe's colour is a texel lookup, a light and a haze, with
     `U32` division and ladders of branches that diverge between lanes.
   - A tile no triangle touches is **one `Pix`**. This probe builds the whole pixel tree of every leaf.
   - The list is walked **once per 4x4 square** (the guide measured 6.6 to 5.6 ms against per 2x2 block); this
     probe walks it once per 2x2 block.
   - The last image is dropped **inside the fork tree**, a dead `Four` per tile, which the guide measures at
     35% faster than dropping it on the host; this probe's host walks and frees it.
   - The guide's own summary of what a GPU is for: "uniform numeric work like mandelbrot or nbody; divergent
     work like n-queens stays faster on the CPU". Per-pixel lists of different lengths, early outs and branch
     ladders are divergent work.

## Optimizing the device path

Starting from `filtered_8` (139 ms on the device at 1024x1024), one change at a time, GPU, plugged in, medians of
ten; each was checked against the CPU painter's picture and for reference counts in the emitted C (63 `term_keep`,
236 `rfc_seal`, 51 `ctr_take` in the baseline, never more):

| change | file | 1024x1024 | 256x256 | picture |
| --- | --- | ---: | ---: | --- |
| baseline: a leaf filters the cell's list into its own, then walks it per 2x2 block | `filtered_8` | 139 | 14 | 54 pixels differ |
| the list is read once per 4x4 square, and a polygon whose box misses the square is skipped for all sixteen | (in `opt3_hostdeal`) | 106 | 118 | same |
| the host deals the polygons down to the 8-pixel leaves, so the device builds no list | `opt3_hostdeal` | 87 | 15 | same |
| coverage by half-planes (multiply-adds) instead of `Paint.span_edges` (five divisions) | `opt4_planes` | 77 | 13 | 855 differ, all on polygon edges |

The host side of a frame, which the device numbers leave out, is 1.0 ms for `filtered_8`, 5.3 for `opt3_hostdeal`
and 4.8 for `opt4_planes` (dealing three more levels). Per frame at 1024x1024 that is 140, 93 and 82 ms, against
the CPU painter's 6 to 8. The first probe was 267. **The best version is about 44% faster than where this
section started, 70% faster than the first probe, and still about 14 times slower than the CPU painter.**

Tried and no faster, so left out: an untouched leaf as one `Pix` (129 to 128 ms), one reciprocal for the three
perspective divisions (the same picture, 106 to 105), and every `U32.mod` by a power of two as an `and`
(the same picture, 75 to 76). Where the texel cost sits, by removing parts (ms, `ablate_texel_*`): the material's
own arithmetic about 25, the perspective divisions and haze about 15 together, and the rest decoding and the
three plane evaluations.

## The control: Bend's own reference on this machine

`bash lab/native/gpu-probe/control.sh` builds `vendor/bend/demos/app_slash_boss_3d`, the rasterizer the guide's
"about 6 ms at 1920x1200 on a 10-core M4" refers to, and runs its own headless probe (`SLASH_PROBE`) on the
CPU pool and on the GPU. On this M1 Pro, plugged in, Bend 2.0.35, microseconds a frame, medians of 292:

| reference rasterizer, 1920x1200 | CPU pool (`--gpu off`) | GPU (`--gpu on`) |
| --- | ---: | ---: |
| draw | 5,700 | 11,000 |
| whole frame | 7,500 | 13,900 |

**On this machine the reference itself is about twice as slow on the GPU as on the CPU pool.** The guide's figure
was taken on a different chip, and nothing carries over from it to a 10-core M1 Pro, whose CPU pool does the
same frame in 5.7 ms. So "Bend is optimized for GPU parallelism" holds for the workload and the hardware it was
measured on, and here the best-case GPU rasterizer does not beat the CPU. What is this probe's own is the gap
on top: the reference is 2x slower on the GPU than on the CPU pool and the probe is 10x slower, and the
reference's draw is about 5 ns a pixel on the GPU where the probe's is about 125.

## Further things tried, and ruled out

- **An untouched leaf as one node** (the reference's `Tile.pick` for a plain tile, here `Paint.sky.flat`):
  129 to 128 ms. Few leaves are untouched in this view, because the backdrop's polygons cover the sky.
- **Reference counts.** The guide says a `+` value read by every lane costs an atomic per read, and to count
  `term_keep`, `rfc_seal` and `ctr_take` in the emitted C. They are the same in every variant, from the empty
  structure (`ablate_E1_structure`) to the full leaf: 63, 236 and 51. The device leaf adds none.

## What it did not answer

- **Why the probe is 5x worse than the reference relative to the CPU pool.** The reference counts are ruled
  out; what is left is the list above (coverage by planes, colour by planes, a walk per 4x4 square, the image
  dropped inside the tree), each not yet tried.
- **Other hardware.** One machine, one view family, ten frames. An M3 or M4 (which 2.0.35 says never had the
  M1 compile problem), or a CUDA card on native Linux, may behave differently. The CPU painter is already
  6 ms at 1024x1024 here.
- **Choosing the leaf at run time.** A `match` on a `Nat` that picked among the 16-, 8-, 4- and 2-pixel
  leaves built and ran on the CPU but the runtime stopped it on the device with "a function the device does
  not hold", even for the 16-pixel case. A def that can reach more than one block size is what changed. So each
  leaf size was its own file for the sweep, and only two are kept here. The sweep's other variants were each a
  few lines from `filtered_8.bend`: the leaf function, `U32.shln` in `cell_fork`, and `b2_done` for the
  collapse and flat-colour experiments.
- **No change was made to `native/`.** The client still has no GPU painter, and nothing here shows that it
  runs on a GPU faster than the CPU painter does.

## What would be needed to go further

Trying the reference's shapes one at a time against the ladder above (a one-`Pix` tile for an empty leaf, a
walk per 4x4 square, the image dropped inside the tree); then a coverage test by planes, which changes which
pixels a polygon covers by a fraction of a pixel and so is a decision; then division-free texel math, which also
benefits the CPU painter; then, only if the device pass gets within a small multiple of the CPU painter, the
decision about the float-rounding difference (change the CPU painter to evaluate the planes at the pixel too, or accept a tolerance gate instead
of a digest). Selecting the painter is also open: a Bend program cannot ask whether a GPU is present, so it
would be a flag, with the CPU painter the default.
