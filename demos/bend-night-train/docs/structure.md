*English | [Русский](ru/structure.md)*

# How the renderer is put together

One frame is a quadtree of tiles. A leaf owns an 8x8 block of pixels and carries only
the triangles and billboards whose screen box reaches it, so every pixel is shaded once,
by the triangle that won it.

![Five stages of a frame: the scene, back-face culling, the four-way split, one shade pass per pixel, and PPM output](../assets/readme/frame-pipeline.svg)

## The frame, split four ways

![The frame dividing into four, then sixteen, then sixty-four tiles of 8x8 pixels, with one leaf highlighted](../assets/readme/quadtree.gif)

At depth 6 the frame is 64x64 pixels, so the tree is three levels of four-way split and
its 64 leaves are 8x8 pixels each. Both counts are laws — `frame_tiles` and
`frame_pixels` — and `frame8` pins a single leaf at 64 pixels. The statements live in
`src/shape.bend`, the same recursion with a constant in place of the colour; see
[laws.md](laws.md) for why the pixels themselves cannot be stated as laws.

## Why the four-way split pays

![One Quad node fanning out into four branches; wall time falls from 1.66 s on one thread to 0.31 s on 32](../assets/readme/parallel-four.gif)

The four branches of a `Quad` node are four calls in the source, and the runtime decides
where they run. At depth 10 the wall time falls from 1.66 s on one thread to 0.31 s on 32
threads — 5.4x, with no ceiling visible yet — and the frame digest is identical at every
thread count, so the picture does not depend on the walk order. The numbers, the method
and the limits of the measurement are in [benchmarks.md](benchmarks.md).

## The modules

| | |
|---|---|
| `src/raster.bend` | the tile quadtree: descend, render, PPM text |
| `src/rt.bend` | triangles, camera, projection, back-face culling |
| `src/shade.bend` | the fragment shader: windows, fog, tonemapping, sky |
| `src/world.bend` | track, ballast, ground, forest, hedges |
| `src/inst.bend` | the instanced scenery: poles, bushes, signals, dust |
| `src/carriage.bend` | the consist, carriage by carriage |
| `src/ride.bend` | the demo's camera: sway, bob, auto-look, lights |
| `src/geo.bend`, `src/trk.bend` | vector maths and the track's own geometry |
| `src/shape.bend` | the tile recursion without pixels — the laws are stated on it |
| `src/main.bend` | driver: environment, scene, frame, live stream |
| `LAWS.bend` / `PROOF.bend` | laws and proofs, the commit gate |

`tools/order.py` sorts the `def`s topologically before a build: declaration order is part
of a Bend program, so the order in the files is not free.

The ray-marching renderer this project started with lives on the branch
`legacy/raymarch` (tag `raymarch-legacy`). It is the only renderer whose pixel is a pure
function of the pixel, and the first laws were stated on it.
