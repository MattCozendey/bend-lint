*English | [Русский](README.ru.md)*

# bend-night-train

**The Night Train on Bend 2** — the self-contained WebGL demo «Ночной поезд — из окна»
rewritten in [Bend 2](https://bend-lang.com/) as a tile rasteriser, to find out by hand
what the language can do: affine dependent types, laws and proofs, automatic parallelism.
The picture stays within 0.52/255 of the original, and the renderer is fast enough to
watch.

The original lives in `reference/` and does not change — [download the original
page](https://github.com/kvcop/bend-night-train/raw/main/reference/night-train-webgl.html)
and open it in a browser.

![Bend 2 rasteriser on the left, the original WebGL demo on the right, eight seconds of the same ride](assets/video/compare-512.gif)

*Eight seconds of the same ride, both sides on the same camera —
`assets/video/compare-512.gif`; the H.264 original is `assets/video/compare-512.mp4`.*

## How close it is

Both cameras are pinned to the demo's own ride (`s = 110`, yaw 0, pitch -0.02, lean 1);
the reference is the original page rendered headlessly by `tools/render_reference.py` with
a seeded PRNG.

| | 512×512 | 1024×1024 |
|---|---|---|
| mean absolute error | 0.002056 (0.52/255) | 0.001850 (0.47/255) |
| PSNR | 42.24 dB | 43.17 dB |
| largest single-pixel error | 0.431 | 0.404 |
| pixels off by more than 4/255 | 2.80 % | 2.20 % |

Every frame of the clip stays between 0.0021 and 0.0037, so the camera does not drift out
of agreement as the ride advances. The remaining error in the still is not spread over the
frame: it sits in one band of the near carriage's side, where the wrong triangle wins those
pixels. The case is written up in `docs/journal.md` and is not fixed.

## What it is

A frame is a quadtree of tiles. A leaf owns an 8×8 block of pixels and carries only the
triangles and billboards whose screen box reaches it, so every pixel is shaded once, by
the triangle that won it.

![The frame dividing into four, then sixteen, then sixty-four tiles of 8x8 pixels, one leaf highlighted](assets/readme/quadtree.gif)

The modules, the five stages of one frame and the four-way split:
[`docs/structure.md`](docs/structure.md).

## Numbers

- **0.31 s** for a 1024×1024 frame on 32 threads — 5.4× faster than on one thread
  (1.66 s) — with the frame digest identical at every thread count. A 512×512 frame is
  0.19 s.
- **5.6 and 4.4 fps** live at 256×256 and 512×512 on 24 threads, one process per frame:
  slow enough to see, fast enough to follow.
- **The laws prove structure, not numbers.** The tile and pixel counts, the completeness
  of the four-way split and the length of the consist are checked. A pixel's colour cannot
  even be *stated* as a law: every `F32` operation is declared as a law without a body.
- **The language wants its rules known in advance:** declaration order is part of the
  program, mutual recursion is forbidden, `match` is not an expression, and only a
  parameter can be destructured.

Numbers, method and their limits: [`docs/benchmarks.md`](docs/benchmarks.md). What is
proved and why the rest cannot be: [`docs/laws.md`](docs/laws.md). The thirteen language
errors actually caught: [`docs/language-notes.md`](docs/language-notes.md).

## Run it

```sh
make proof                  # laws gate: must print "All terms check."
make build && make frame    # native binary, 512x512 frame to out/frame.png
make compare                # render + reference + metrics, 1024x1024
make video                  # the clip above: mp4, poster, gif

./tools/live.sh             # watch it render, in a window
```

Environment variables, the live stream and the comparison tools:
[`docs/running.md`](docs/running.md). Everything else is in [`docs/`](docs/README.md).

## What is not here

- **GPU numbers.** The `!` device lane was measured on this host: it changed nothing for
  this renderer — same digest, same host CPU time — and cost about 0.3 s per process, so
  it was removed. No claim is made either way about a different workload.
- **A comparison with hand-written C.** Bend already compiles to C; an honest comparison
  needs a C twin of the renderer.
- **A window of its own.** The renderer is headless and writes PPM; `tools/live.sh` is
  what puts it on screen.

## What it cost

Two AI-assisted passes produced this repository, both on **DeepSeek Flash V4.1**: the ray
marcher on a DeepSeek harness, then the rasteriser on this branch with Claude Code. The
recorded spend for both together is **≈ $6.95**.

## License

MIT — see `LICENSE`. The original demo in `reference/` is the work of kvcop and is
distributed under the same terms.
