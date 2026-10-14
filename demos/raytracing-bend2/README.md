# raytracing-bend2

Ray tracing in a weekend in [Bend 2](https://github.com/bendlang/bend), ported from
[raytracing-nim](https://github.com/aguspiza/raytracing-nim).

![64 samples per pixel](ray.png)

## Run

Bend compiles through clang, so build and run it in WSL or on Linux:

```
bend PROOF.bend       # check every law: prints "All terms check."
bend main.bend -o ray
./ray                 # 64 samples per pixel -> ray.tga
./ray 16              # 16 samples per pixel
./ray 16 ppm          # also write ray.ppm (P3, as with -d:ppm in Nim)
./ray 16 --threads 8  # cap the worker threads (default: every CPU)
```

## Parallelism

Nim's version spawns one threadpool task per image line. This port uses
Bend's parallel let instead: `render` forks into two calls, one level per
call, down to `Depth()` levels (2^9 = 512 leaves).

```python
a b = render(p, evens(ys), w, ns, cam, scene)
  render(p, odds(ys), w, ns, cam, scene)
interleave(a, b)
```

`ys` is the list of row indices still to render. Each fork sends the rows
at even positions to one branch and the rows at odd positions to the
other. A leaf therefore gets rows spread over the whole image, so the
cheap sky rows and the expensive sphere rows are shared evenly. Bend's
scheduler never moves a task after dealing it, so that balance matters.
Each leaf renders its rows in flat loops, and each join interleaves its
two halves back into order.

Fewer leaves left threads idle on a 16-thread machine: 128 leaves kept only
about 8 of them busy.

## Laws and proofs

`LAWS.bend` states what the render guarantees, and `PROOF.bend` proves it.
`bend PROOF.bend` checks every law in about 0.3 s and prints "All terms
check."

| Law             | Claim                                                   |
| --------------- | ------------------------------------------------------- |
| `split_merge`   | Merging the even-position and odd-position rows gives back the rows, in order. |
| `render_is_seq` | The parallel fork tree returns the same rows as the sequential loop, at any depth. |
| `row_len`       | A row loop of n steps adds exactly n pixels.            |
| `line_len`      | Every line holds w pixels.                              |

The laws hold for any row list and any width `w`. The width is a
parameter, not the constant `W()`, so the checker never unrolls a line's
1,200 pixels. The shading math is not claimed: F32 operations are
primitives the checker cannot see into, so pixel values stay abstract.
That also means nothing proves a pixel byte stays under 256.

A deliberate bug shows the proof has teeth. Swapping each pair in
`interleave` makes `bend PROOF.bend` fail at `split_merge`, showing the
rows out of order.

To make the parallel law provable, `render` splits a list of row indices.
It used to compute row numbers with U32 arithmetic (`y + stride`), which
the checker cannot equate across the two ways of reaching a row. The
refactor did not change the output or the speed:

| 1200x600, 16 threads | Before       | After        |
| -------------------- | ------------ | ------------ |
| 4 samples, 3 runs    | 4.5, 5.2, 4.8 s | 4.7, 4.7, 4.8 s |
| 64 samples, run 1    | 76.1 s       | 77.7 s       |
| 64 samples, run 2    | 78.9 s       | 78.8 s       |
| Peak RAM             | 73 MB        | 73 MB        |

Both builds wrote byte-identical images at 4 and 64 samples per pixel.

## What changed from the Nim code

- **Randomness.** Bend is pure, so there is no global `rand()`. A xorshift32
  state is threaded through every call that draws, and each pixel seeds its
  own from its index. The small spheres are laid out differently from the
  Nim run for the same reason.
- **Loops.** Every `while` loop becomes a recursion with a fuel count, since
  Bend requires termination. `randInSphere` and `randInDisk` give up after 64
  redraws.
- **Fixed.** Nim's `cross` had a flipped sign on its y component, which
  its camera cancelled out. Both are fixed here, and in raytracing-nim on
  the [`fix-threads-and-cross`](https://github.com/aguspiza/raytracing-nim/tree/fix-threads-and-cross)
  branch.
- **Kept on purpose.** `randInSphere` accepts points *outside* the unit
  ball, as in the Nim code, so the image matches the original.

## Timing

1200x600, WSL2 on a 16-thread CPU, 4 samples per pixel. "Nim fixed" is the
`fix-threads-and-cross` branch, built with Nim 2.2.12.

| Build                        | Wall time |
| ---------------------------- | --------- |
| Nim original, 1 thread       | 39.6 s    |
| Nim fixed, `--threads:off`   | 17.5 s    |
| Nim fixed, `--threads:on`    | 2.9 s     |
| Bend, `--threads 1`          | 30.1 s    |
| Bend, 16 threads             | 4.6 s     |

At the default 64 samples per pixel, Bend takes 78 s on 16 threads.

The original Nim `--threads:on` build crashes, because `color` reads the
global `world`, whose materials are refs. The fixed branch passes `world` in
and makes materials plain values. It also spawns one task per horizontal
line instead of four per pixel.

## Compile time

A full rebuild from source, median of three runs. Nim builds with `-f` and
an empty cache, and compiles its C with gcc. Bend's time includes its own
Bun startup and type check.

| Build                                  | Wall time | Compiler peak RAM |
| -------------------------------------- | --------- | ----------------- |
| Nim 2.2.12, `-d:release --threads:off` | 2.1 s     | 87 MB             |
| Nim 2.2.12, `-d:release --threads:on`  | 2.3 s     | 90 MB             |
| Bend, check and emit C (`-o ray.c`)    | 1.3 s     | 176 MB            |
| Bend, full build (`-o ray`)            | 3.3 s     | 181 MB            |

Bend spends about 1.3 s checking the program and emitting C, and clang
takes the other 2 s. Checking the laws is separate: `bend PROOF.bend`
takes about 0.3 s.

## Binary size

| Executable, stripped   | Size    |
| ---------------------- | ------- |
| Bend `ray`             | 1.1 MB  |
| Nim, `--threads:off`   | 107 KB  |
| Nim, `--threads:on`    | 127 KB  |

Bend's binary carries its whole runtime: the scheduler, the heap and the
IO effects. Stripping it saves only about 10 KB.

## Memory

Peak resident memory, measured with `/usr/bin/time -f %M`, two runs each:

| Run, 4 samples per pixel     | Peak RAM |
| ---------------------------- | -------- |
| Nim fixed, `--threads:off`   | 12 MB    |
| Nim fixed, `--threads:on`    | 15 MB    |
| Bend, `--threads 1`          | 72 MB    |
| Bend, 16 threads             | 73 MB    |
| Bend hello world             | 2.6 MB   |

Bend uses about 5 times Nim's memory. Its peak stays the same with 1 or 16
threads, and at 64 samples per pixel. The runtime itself is small, as the
hello world shows, so the rest is the image data.

The likely cause is how the port holds the image. It is a linked list with
one cell per pixel, and the output is another list with one cell per byte,
because `File.write_bytes` takes a list. That is about 2.2 million cells at
once. This breakdown is an estimate from those cell counts, not a
measurement. Nim keeps the same pixels in a flat array of about 2 MB.

Writing the file one row at a time would lower Bend's peak, because the
whole byte list would never exist at once.
