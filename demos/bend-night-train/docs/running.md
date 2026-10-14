*English | [Русский](ru/running.md)*

# Running it

```sh
make proof                  # laws gate: must print "All terms check."
make build                  # native binary via clang
make frame                  # 512x512 frame to out/frame.png
make bench                  # sweep into bench/results.csv
make compare                # render + reference + metrics, 1024x1024
make video                  # record the clip: mp4, poster, gif

./tools/live.sh             # watch it render, in a window
./tools/bend src/main.bend  # check and run on the JS backend
```

The binary takes `--threads N`; the renderer itself reads its scene from the environment:

| | |
|---|---|
| `NT_DEPTH` | quadtree depth; frame `2^d × 2^d` |
| `NT_S` | position along the track, metres |
| `NT_T` | animation clock, seconds (particles, window lights) |
| `NT_MOTION` | `1` — the ride's sway and bob, `0` — frozen |
| `NT_YAW`, `NT_PITCH` | pin the head; unset, the demo's auto-look decides |
| `NT_HEAD` | `1` — the head is out of the window |
| `NT_PPM` | `1` — write `out/frame.ppm`, `0` — only compute |
| `NT_VIEW` | `1` — stream frames to stdout instead of one file |
| `NT_FRAMES`, `NT_MS`, `NT_STEP` | frames, first frame's time, step between them |

```sh
NT_DEPTH=10 NT_S=150 NT_MOTION=0 NT_PPM=0 ./out/night-train --threads 16
```

## Watching it render

The renderer is headless and writes PPM text, so `tools/live.sh` is what puts it on
screen: it runs one process per frame, streams the frames to stdout and pipes them into
`ffplay`. On 24 threads that is **5.6 fps at 256x256** and **4.4 fps at 512x512** — slow
enough to see, fast enough to follow. `NT_VIEW=1` with `NT_FRAMES`, `NT_MS` and
`NT_STEP` drives the same stream by hand; `tools/clip.sh` shoots a clip off-line, where
the renderer is not tied to the wall clock.

## Comparing against the original

`tools/render_reference.py` renders the original demo headlessly at a pinned camera and a
seeded PRNG, so a frame is reproducible; `tools/compare.py` puts a Bend frame and a
reference frame side by side and prints the error metrics, and `make compare` runs both.
`tools/compare_video.sh` does the same along the ride and writes the clip, the poster and
the GIF that the README embeds. One page per frame is deliberate: the demo's particles
and smoke carry state across draws, so frames of a single browser session would not be
the stills they claim to be.

## The `tools/bend` wrapper

In this environment `$HOME` is read-only and a bare `bend` cannot write to `~/.bend`, so
everything goes through the wrapper. The wrapper also **forbids `--publish`**: Bend's hub
is a content-addressed store with no accounts and no deletion, so a published package
stays public forever. Only a human can lift the ban, by setting `BEND_ALLOW_PUBLISH=1`.
