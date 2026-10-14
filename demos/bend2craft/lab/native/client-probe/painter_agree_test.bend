import Base
import ../../../world/world_state.bend as WorldState
import ../../../native/player.bend as PlayerProbe
import ../../../native/voxel.bend as Voxel
import ../../../native/frame.bend as Frame
import ../../../native/face.bend as Face
import ../../../native/client.bend as Client

# ---------------------------------------------------------------------------
# Would a painter ship without costing quality?
#
# The investigation log prices a painter's algorithm as the way past the walk: order
# 0 ms, fill 0.49 ms, fold 6 ms at 256x256, against the walk's 44.33 ms measured at
# the client's own spawn camera. Those are sound timings. What was never asked is
# whether the painter draws the same picture, and this file asks it.
#
# **The bar is the walk's own bar, not pixel-exactness.** `native/face_test.bend`
# gates the walk against the ray renderer at 1% (`error_limit = pixels / 100`), so the
# shipped renderer is already allowed to disagree with geometric truth on one pixel in
# a hundred. A painter that matched the walk exactly would be a stronger guarantee than
# the repository asks for; what it has to do is pass the same gate the walk passes, on
# the same scenes. So every camera here is scored twice — once for the walk and once
# for the painter — and the question is whether the painter's error rate is in the same
# place as the walk's.
#
# Two renderers are compared against the ray renderer here, and against each other:
#
# - the **walk** is the bucket walk, `Face.face_at_pixel` over the bucketed tiles. It
#   is the shipping renderer, so its numbers are the reference and the gate it already
#   passes is the gate the painter is measured against.
# - the **painter** is `span_probe`'s: order the faces back to front by each face's
#   farthest corner, then fill each projected quad's scanlines into a flat frame, last
#   write wins, no depth buffer. It is restated here rather than imported, because a
#   gate that imported the thing it judges would only report that the thing agrees with
#   itself.
#
# The cameras are chosen to break the painter rather than to flatter it. The spawn
# camera is the frame the painter was priced on and it is mostly one flat ground plane,
# which is the easiest case available. The rest put faces against each other at the same
# depth, put the camera inside the geometry, and point it straight up. A painter's
# correctness rests on its ordering being a total order and on faces never
# interpenetrating, and a normal view tests neither.
#
# One camera here is *not* a fair test and is kept only to say so: `up` puts the eye at
# y=8, which is inside the terrain at spawn, so every ray starts inside solid. Both
# renderers score 0 of 16384 there because the ray renderer reports the block it starts
# in. That is a property of asking a ray tracer about a camera buried in the world, not
# a property of either renderer, and the number is printed rather than hidden so the
# table below is not read as five failures.
#
# What this found is recorded at the end of this header, and it is not what the timing
# suggested.

# **The ordering is not the defect.** Two cubes sharing a face, at 32x32 and again at
# 64x64, score *exactly* the same as one cube alone: 3 wrong pixels of 1024, and 8 of
# 4096. Adding a second overlapping face changed nothing, so the depth key separates
# overlapping faces as well as the walk does on these fixtures. The lexicographic
# tie-break that the textbook answer suggests was measured and discarded: it scored 0 of
# 16384 on the `down` camera, against 16384 of 16384 for the bare depth key.
#
# **The coverage rule is a real but small defect.** One cube, nothing overlapping, at
# 32x32: 3 of 1024 pixels wrong, every one a pixel the painter painted where the walk
# reports sky. That is 0.29% against a 1% gate, so it is inside it. Rounding the left
# bound up instead of truncating it took this from 7 to 3, so the direction is right and
# the three that remain are the per-pixel ray test the painter cannot make. At 64x64 the
# count is 8 of 4096, so it grows with the silhouette rather than with the area, which is
# what an edge-only defect looks like.
#
# **So the painter is close on an isolated scene and badly wrong on the real one.** The
# same painter that scores 0.29% on a cube scores 39% at the spawn camera: 396 of 1024
# wrong at 32x32, 6400 of 16384 at 128x128, against a 163-pixel gate. Those two facts
# cannot both be true of a renderer whose only defect is edge coverage, and what differs
# between the two scenes is the face count: 6 against 1654. The failure scales with the
# face count and is not exercised by a fixture of six faces.
#
# `cube-away` is the other half and is a genuine defect on its own: the camera turned
# away from the cube, the walk reports sky at every pixel, and the painter reports a face
# at every one of the 1024 — `phantom=0` because the reference also says sky, so nothing
# here is geometry invented in front of the ray. A face behind the eye is clamped into
# the frame and painted; the walk rejects the same candidate because its plane distance
# is not positive.
#
# **A row of cubes reproduces it, and the error grows faster than the face count.** A
# line of cubes along z is the smallest scene with many faces at similar depths: each
# cube's front face is one cell along z from the last, so none is a whole cell nearer than
# another. At 32x32: 1 cube 3 wrong, 4 cubes 4 wrong, 8 cubes 12 wrong. At 64x64 the
# 8-cube row reads 39 wrong. So 4 to 8 cubes roughly doubles the error while the face
# count doubles, but 8 cubes to the real scene multiplies it by two orders of magnitude
# at a face count that grows by a factor of fifty. Edge coverage would be linear in the
# silhouette and ordering ties would be a constant per pair; neither is superlinear.
#
# **And the failure is binary, not gradual.** The `down` camera reads 16384 of 16384
# correct while `level`, `inside` and `ceiling` read **0** of 16384, on the same scene at
# the same size. A renderer with a small coverage defect cannot be perfect on one camera
# and wrong on every pixel of another. `phantom=0` throughout, so nothing here is
# geometry invented where the ray sees sky.
#
# What separates the two sets of cameras: `down` looks steeply at the ground, where the
# visible faces barely overlap, and the others look level or up through the village, where
# they do. Combined with the row fixture that is the shape of the answer — the painter
# fails where many faces cover the same pixel, and the cube fixtures do not make enough
# overlap to show it. **That is a hypothesis, not a measurement**: what would confirm it
# is a count, per camera, of how many faces cover each pixel, which this file does not
# take. The `down` camera's perfect score and the row fixture's growth are the two facts
# that make it the thing to check next.
#
# Note also that the walk is not perfect on every fixture either: the 4-cube row reads
# `walk wrong=1`. That is inside the gate and it is why the gate is a limit rather than
# zero.
# ---------------------------------------------------------------------------

# Reports rather than dies, because one camera's failure must not hide the next
# camera's numbers: the question is how the painter fails across the set, not only
# whether it fails. `painter-agree=done` at the end is the exit; the verdict is in the
# `PAINTER-AGREE-FAIL` lines.
def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.print("PAINTER-AGREE-FAIL: " ++ message)

# A face's identity the way both comparisons spell it: `block * 8 + dir`, 0 for sky.
# Comparing identities rather than colours keeps a disagreement legible — two blocks
# can shade alike and one block can shade two ways, and neither is agreement.
def key_of(+block: U32, +dir: U32) -> U32:
  Bool.pick(U32, U32.is_eq(block, 0), (0 : U32), U32.add(U32.mul(block, 8), dir))

def half_at(depth: Nat) -> F32:
  Voxel.projection_half(depth)

def focal_at(depth: Nat) -> F32:
  F32.mul(1.5, Voxel.projection_half(depth))

# --- the painter, from span_probe -------------------------------------------

def far() -> F32:
  1.0e30

def near() -> F32:
  F32.neg(1.0e30)

def crossing_x(+y: F32, +ax: F32, +ay: F32, +bx: F32, +by: F32) -> F32:
  F32.add(ax, F32.mul(F32.div(F32.sub(y, ay), F32.sub(by, ay)), F32.sub(bx, ax)))

def straddles(+y: F32, +ay: F32, +by: F32) -> Bool:
  Bool.or(Bool.and(F32.is_ge(y, ay), F32.is_lt(y, by)),
    Bool.and(F32.is_ge(y, by), F32.is_lt(y, ay)))

def keep_left(crossed: Bool, +x: F32, +best: F32) -> F32:
  match crossed:
    case True{}:
      F32.min(best, x)
    case False{}:
      best

def keep_right(crossed: Bool, +x: F32, +best: F32) -> F32:
  match crossed:
    case True{}:
      F32.max(best, x)
    case False{}:
      best

type Span is Data:
  Span{x0: U32, x1: U32}

type Rows is Data:
  Rows{first: U32, stop: U32}

# The x-range of one scanline of the quad, from the two of its four edges that
# straddle the line, clamped into the frame.
def corner_x(q: Face.Q) -> F32:
  Face.Q{x, y, z} = q
  x

def corner_y(q: Face.Q) -> F32:
  Face.Q{x, y, z} = q
  y

# The quad's eight corner coordinates, as a record rather than a product: a product
# handed out of a call cannot be destructured by its caller, and an eight-wide `&` is not
# a shape this language has.
type Corners is Data:
  Corners{ax: F32, ay: F32, bx: F32, by: F32, cx: F32, cy: F32, dx: F32, dy: F32}

# One corner's two coordinates. `Face.Q` is `Data`, so it is read once here and the
# pair is carried out as a product; the caller takes it apart at its own call site, where
# the destructuring statement is opening a parameter.
type XY is Data:
  XY{x: F32, y: F32}

def corner(q: Face.Q) -> XY:
  Face.Q{x, y, z} = q
  XY{x, y}

def xy_x(p: XY) -> F32:
  match p:
    case XY{x, y}:
      x

def xy_y(p: XY) -> F32:
  match p:
    case XY{x, y}:
      y

def span_corners(+qa: XY, +qb: XY, +qc: XY, +qd: XY) -> Corners:
  Corners{xy_x(qa), xy_y(qa), xy_x(qb), xy_y(qb), xy_x(qc), xy_y(qc), xy_x(qd), xy_y(qd)}

# The scanline's two bounds, and **this is where the painter and the walk disagree.**
#
# The walk asks whether the pixel's *ray* meets the face's quad, so a pixel is inside
# when the ray through the pixel's centre crosses the quad: `left <= px < right` on a
# crossing at `left` and `right`. A painter cannot ask per pixel -- asking per pixel *is*
# the walk -- so it resolves the quad once to an integer range, and this is where the
# two rules have to meet.
#
# `span_probe` truncates both bounds with `F32.to_u32`, which floors a positive value,
# and so claims both the pixel the crossing sits inside and the one it sits outside: a
# crossing at 40.7 becomes 40, where the walk would have started at 41. Every quad is
# therefore one pixel too wide at each end, and at 1024 a face is one or two pixels
# across, so the ends are most of the face. `half_open_bounds` below rounds the left
# bound up instead, which is the half-open rule the walk uses.

def half_open_bounds(+e4: F32, +f4: F32, +last: F32) -> Span:
  # The scanline's two integer bounds. `ceil` on the left and `floor` on the right is the
  # rule that scored best, and it was chosen by measurement rather than by derivation,
  # because two better-argued rules both lost to it:
  #
  #   rule                        cube   row-8   spawn wrong blocks   `inside`
  #   ceil(e4) .. floor(f4)         3      12        0                  131
  #   ceil(e4) .. ceil(f4)          7      26        0                  521
  #   ceil(e4-.5) .. floor(f4-.5)+1 3      26        104                199
  #
  # The third is derived from the two renderers' actual conventions — `ray_for` samples
  # pixel `px` at `px + 0.5` (`native/voxel.bend:81`) while `Face.project` emits
  # `half - 0.5 + focal * lateral / depth` (`native/face.bend:468`), so `project.sx` is the
  # walk coordinate plus 0.5 and the span should be `[ceil(e4 - 0.5), floor(f4 - 0.5) + 1)`.
  # Deriving it and measuring it disagree, which means the residual is not the span's
  # placement at all: it is a per-edge coverage bias of a fraction of a pixel on each of a
  # quad's four edges, and moving the window trades one edge's loss for another's. The
  # plain cube — six faces, no overlap, no straddling — is 3 pixels out of 1024, which is
  # 0.3% and inside the gate.
  +left = F32.to_u32(F32.ceil(F32.min(F32.max(e4, 0.0), last)))
  +right = F32.to_u32(F32.max(F32.min(f4, last), 0.0))
  Span{left, U32.max(right, left)}


# Five rules were measured for a face the eye is inside of, and **skipping it wins**. The
# block_wrong totals across the six cameras that have a nonzero answer are:
#
#   rule                                             block_wrong
#   skip                                                  214
#   clamp the hull into the frame                         483
#   clamp the hull, and sort straddling faces first       483
#   per-row near-plane test on each edge's crossing        483
#
# The per-row test is the interesting failure, because it is the one that looked like a real
# clip. At row `y` the clipped quad's boundary is the extreme crossing among the edges that
# are in front of the eye, and an edge's crossing depth looks like the corners' depths
# interpolated the same way `crossing_x` interpolates x. That is wrong: `crossing_x`
# interpolates linearly in *screen* y, and screen y is `half - 0.5 - focal * u / z`, which
# is not linear in the edge's own parameter. So the depth test over- and under-includes, and
# it lost exactly where skipping was perfect — `ceiling` 0 -> 128, `inside` 131 -> 240,
# `cube-away` 0 -> 32 — while halving `spawn`'s face-only count from 256 to 128. Doing this
# exactly needs the 3D edge parameter, which is the walk.
#
# So the painter draws a face only when all four of its projected corners are in front of
# the eye, and a face the eye is inside of costs its visible sliver. That sliver is the
# whole of the residual: 83 wrong blocks on `level` and 131 on `inside`, both inside the
# gate, and zero on the spawn camera the client ships at every size it offers.
def span_edges(+ax: F32, +ay: F32, +bx: F32, +by: F32, +cx: F32, +cy: F32, +dx: F32,
  +dy: F32, +y: F32, +size: U32) -> Span:
  +last = F32.from_nat(U32.to_nat(U32.sub(size, (1 : U32))))
  +e1 = keep_left(straddles(y, ay, by), crossing_x(y, ax, ay, bx, by), far())
  +e2 = keep_left(straddles(y, by, cy), crossing_x(y, bx, by, cx, cy), e1)
  +e3 = keep_left(straddles(y, cy, dy), crossing_x(y, cx, cy, dx, dy), e2)
  +e4 = keep_left(straddles(y, dy, ay), crossing_x(y, dx, dy, ax, ay), e3)
  +f1 = keep_right(straddles(y, ay, by), crossing_x(y, ax, ay, bx, by), near())
  +f2 = keep_right(straddles(y, by, cy), crossing_x(y, bx, by, cx, cy), f1)
  +f3 = keep_right(straddles(y, cy, dy), crossing_x(y, cx, cy, dx, dy), f2)
  +f4 = keep_right(straddles(y, dy, ay), crossing_x(y, dx, dy, ax, ay), f3)
  half_open_bounds(e4, f4, last)

# The two bounds, resolved by the rule the walk uses.
#
# The walk asks whether the pixel's *ray* meets the quad, so a pixel is inside when the
# ray through the pixel's centre crosses the quad: that is `left <= px < right` on a
# crossing at `left` and `right`. A painter cannot ask per pixel — asking per pixel *is*
# the walk — so it resolves the quad once to an integer range, and this is where the two
# rules have to meet.
#
# `span_probe` truncates both bounds with `F32.to_u32`, which is a floor for a positive
# value, and so claims both the pixel the crossing sits inside and the one it sits
# outside: a crossing at 40.7 becomes 40, and the walk would have started at 41. Every
# quad is therefore one pixel too wide at each end, and at 1024 a face is one or two
# pixels across, so the ends are most of the face. This is the change the numbers below
# measure.
def span_of(+qa: XY, +qb: XY, +qc: XY, +qd: XY, +y: F32, +size: U32) -> Span:
  span_edges(xy_x(qa), xy_y(qa), xy_x(qb), xy_y(qb), xy_x(qc), xy_y(qc), xy_x(qd),
    xy_y(qd), y, size)

def span_x(s: Face.Square, +y: F32, +size: U32) -> Span:
  Face.Square{a, b, c, d} = s
  span_of(corner(a), corner(b), corner(c), corner(d), y, size)

# The scanline's two bounds, and **this is where the painter and the walk disagree.**
#
# The walk asks whether the pixel's *ray* meets the face's quad, so a pixel belongs to
# the quad when the ray through the pixel's centre crosses it. A painter cannot ask that
# per pixel, because asking it per pixel is the walk. It resolves the quad once to an
# integer x-range and fills it, and the two bounds come from `F32.to_u32`, which
# truncates toward zero — so a quad whose crossing is at x = 40.7 claims pixels 40 and
# 41 while the walk claims 41 only. Every quad boundary is one pixel wider than it
# should be, and at 1024 a face is one or two pixels across, so the boundaries are most
# of the face.
#
# `ceil` on the left bound and `floor` on the right, rather than truncation on both,
# reproduces the walk's rule and costs one `F32.floor` and one `F32.ceil` per scanline
# rather than a ray test per pixel. That is the change this file's numbers would have to
# be re-measured against, and it is the next thing worth trying.

# The quad's vertical extent as whole rows inside the frame. A quad that misses the
# frame yields no rows, which is what a painter skips and a per-pixel walk does not.
def span_bounds(+top: F32, +bottom: F32, +size: U32) -> Rows:
  +last = U32.sub(size, (1 : U32))
  +misses = Bool.or(F32.is_ge(top, F32.from_nat(U32.to_nat(size))), F32.is_le(bottom, 0.0))
  +first = Bool.pick(U32, misses, (0 : U32), F32.to_u32(F32.max(F32.floor(top), 0.0)))
  +stop = Bool.pick(U32, misses, first,
    U32.add(F32.to_u32(F32.min(F32.floor(bottom), F32.from_nat(U32.to_nat(last)))),
      (1 : U32)))
  Rows{U32.min(first, last), U32.max(stop, U32.min(first, last))}

def span_rows(s: Face.Square, +size: U32) -> Rows:
  Face.Square{a, b, c, d} = s
  Face.Q{_, +ay, _} = a
  Face.Q{_, +by, _} = b
  Face.Q{_, +cy, _} = c
  Face.Q{_, +dy, _} = d
  span_bounds(F32.min(F32.min(ay, by), F32.min(cy, dy)),
    F32.max(F32.max(ay, by), F32.max(cy, dy)), size)

def rows_stop(r: Rows) -> U32:
  match r:
    case Rows{first, stop}:
      stop

def rows_first(r: Rows) -> U32:
  match r:
    case Rows{first, stop}:
      first

def span_left_at(s: Span) -> U32:
  match s:
    case Span{x0, x1}:
      x0

def span_right_at(s: Span) -> U32:
  match s:
    case Span{x0, x1}:
      x1

# How many scanlines a row range covers, and the first of them. Both take the range
# `+`, so it is computed once and read twice: `Rows` is `Data`, and a value that is
# spent cannot be asked for two fields in two separate calls.
def scan_lines(+rows: Rows) -> Nat:
  Nat.sub(U32.to_nat(rows_stop(rows)), U32.to_nat(rows_first(rows)))

def scan_first(+rows: Rows) -> U32:
  rows_first(rows)

def fill_span(remaining: Nat, +at: U32, +key: U32, frame: Array<U32>) -> Array<U32>:
  match remaining:
    case 0n:
      frame
    case 1n+r:
      fill_span(r, (at + 1 : U32), key, frame[at] <- key)

def fill_row(+span: Span, +row: U32, +size: U32, +key: U32, frame: Array<U32>) -> Array<U32>:
  Span{x0, x1} = span
  +width = U32.add(U32.sub(x1, x0), (1 : U32))
  fill_span(U32.to_nat(width), U32.add(U32.mul(row, size), x0), key, frame)

def fill.row(remaining: Nat, +y: U32, +square: Face.Square, +size: U32, +key: U32,
  frame: Array<U32>) -> Array<U32>:
  match remaining:
    case 0n:
      frame
    case 1n+r:
      fill.row(r, (y + 1 : U32), square, size, key,
        fill_row(span_x(square, F32.from_nat(U32.to_nat(y)), size), y, size, key, frame))

def square_at(+dir: Nat, f: Face.Face, +eye: Voxel.Vec, +right: Voxel.Vec,
  +up: Voxel.Vec, +forward: Voxel.Vec, +half: F32, +focal: F32) -> Face.Square:
  Face.Face{fx, fy, fz, label, kind} = f
  Face.square_of(dir, U32.to_f32(fx), U32.to_f32(fy), U32.to_f32(fz), eye, right, up,
    forward, half, focal)
def q_behind(q: Face.Q) -> Bool:
  F32.is_le(Face.q_depth(q), 0.0)

def square_behind(+s: Face.Square) -> Bool:
  Face.Square{a, b, c, d} = s
  Bool.or(Bool.or(q_behind(a), q_behind(b)), Bool.or(q_behind(c), q_behind(d)))
def fill.rows_of(+square: Face.Square, +size: U32, +key: U32,
  frame: Array<U32>) -> Array<U32>:
  fill.row(scan_lines(span_rows(square, size)), scan_first(span_rows(square, size)), square,
    size, key, frame)



# A face the eye is inside or behind part of. `Face.project` divides by
# `max(depth, 0.0001)`, which is a clamp and not a clip, so a corner behind the eye
# projects to a coordinate of tens of millions of pixels; `crossing_x` interpolates that
# against a normal corner and `half_open_bounds` clamps the span into the frame, which
# makes the face cover the whole row. That is the whole of the painter's failure on the
# scene cameras — see the `behind` lines, where 0 straddling faces scores 0.3% and 932
# scores 100%.
#
# Skipping the face instead was measured first, and it is not enough: the walk resolves a
# straddling face exactly, by intersecting the pixel's ray with the face's plane, so it
# keeps the sliver that is genuinely visible. Skipping that sliver costs 83 wrong blocks
# on `level` and 131 on `inside`, both of which are inside the 1% gate, but it also costs
# 256 pixels of face direction on `spawn` and `ceiling`, where the image is otherwise
# perfect.
#
# A face is drawn only when all four of its projected corners are in front of the eye.
# `span_edges` above records the five rules that were measured against this one; skipping
# wins, and it is what makes `cube-away` perfect, where the camera faces away from the cube
# and all six faces straddle.
def fill.draw(straddling: Bool, +square: Face.Square, +size: U32, +key: U32,
  frame: Array<U32>) -> Array<U32>:
  match straddling:
    case True{}:
      frame
    case False{}:
      fill.rows_of(square, size, key, frame)

def fill.go(faces: List<&2, Face.Face>, +eye: Voxel.Vec, +right: Voxel.Vec, +up: Voxel.Vec,
  +forward: Voxel.Vec, +half: F32, +focal: F32, +size: U32, frame: Array<U32>) -> Array<U32>:
  match faces:
    case Nil{}:
      frame
    case +f <> rest:
      Face.Face{fx, fy, fz, +dir, block} = f
      +square : Face.Square = square_at(dir, f, eye, right, up, forward, half, focal)
      fill.go(rest, eye, right, up, forward, half, focal, size,
        fill.draw(square_behind(square), square, size, key_of(block, U32.from_nat(dir)),
          frame))



# --- how many faces straddle the eye -----------------------------------------
#
# The diff lines say the painter is not choosing the wrong *face* of the right block — it
# is stamping a different block, and a different one again at the left edge of the row. A
# per-pixel ordering error cannot produce that; a *coordinate* error can.
#
# `Face.project` guards the division with `safe_depth = max(depth, 0.0001)`, which is a
# clamp, not a clip. A corner behind the eye has negative depth, so its screen coordinate
# becomes `half + focal * lateral / 0.0001` — tens of millions of pixels. `crossing_x`
# then interpolates that against a normal corner, `half_open_bounds` clamps the result
# into `[0, size-1]`, and the span covers **the entire row**. One such face paints a
# full-width band, and since `fill.go` sorts by depth and writes unconditionally, it
# overwrites whatever the correct faces put there.
#
# This counts those faces per camera. It is the test that separates the two explanations
# that the overlap count could not: if the failing cameras have straddling faces and the
# correct ones do not, the failure is the projection and not the ordering.
#
def behind.count(faces: List<&2, Face.Face>, +eye: Voxel.Vec, +right: Voxel.Vec,
  +up: Voxel.Vec, +forward: Voxel.Vec, +half: F32, +focal: F32, n: U32) -> U32:
  match faces:
    case Nil{}:
      n
    case +f <> rest:
      Face.Face{fx, fy, fz, +dir, block} = f
      +hit : U32 = Bool.pick(U32,
        square_behind(square_at(dir, f, eye, right, up, forward, half, focal)), (1 : U32), 0)
      behind.count(rest, eye, right, up, forward, half, focal, U32.add(n, hit))

def behind_of(+label: String, +faces: List<&2, Face.Face>, +camera: Voxel.Camera,
  +depth: Nat, +size: U32) -> U32:
  Voxel.Camera{eye, forward, right, up} = camera
  behind.count(faces, eye, right, up, forward, half_at(depth), focal_at(depth), 0)

def behind_report(+label: String, +faces: List<&2, Face.Face>, +camera: Voxel.Camera,
  +depth: Nat, +size: U32) -> IO(Unit):
  IO.print("behind " ++ label ++ " faces_of_" ++ U32.show(Face.face_total(faces))
    ++ " straddling_eye=" ++ U32.show(behind_of(label, faces, camera, depth, size)))

# --- ordering ---------------------------------------------------------------

def far_step(+along: F32) -> F32:
  Bool.pick(F32, F32.is_gt(along, 0.0), 1.0, 0.0)

def far_corner.x(+plane: F32, +fx: F32, +fy: F32, +fz: F32, +forward: Voxel.Vec) -> F32:
  Face.dot3(forward, Voxel.Vec{F32.add(plane, far_step(Face.vx(forward))),
    F32.add(fy, far_step(Face.vy(forward))), F32.add(fz, far_step(Face.vz(forward)))})

def far_corner.y(+plane: F32, +fx: F32, +fy: F32, +fz: F32, +forward: Voxel.Vec) -> F32:
  Face.dot3(forward, Voxel.Vec{F32.add(fx, far_step(Face.vx(forward))),
    F32.add(plane, far_step(Face.vy(forward))), F32.add(fz, far_step(Face.vz(forward)))})

def far_corner.z(+plane: F32, +fx: F32, +fy: F32, +fz: F32, +forward: Voxel.Vec) -> F32:
  Face.dot3(forward, Voxel.Vec{F32.add(fx, far_step(Face.vx(forward))),
    F32.add(fy, far_step(Face.vy(forward))), F32.add(plane, far_step(Face.vz(forward)))})

def far_corner.at(axis: Nat, +plane: F32, +fx: F32, +fy: F32, +fz: F32,
  +forward: Voxel.Vec) -> F32:
  match axis:
    case 0n:
      far_corner.x(plane, fx, fy, fz, forward)
    case 1n:
      far_corner.y(plane, fx, fy, fz, forward)
    case _:
      far_corner.z(plane, fx, fy, fz, forward)

def depth_key.at(+dir: Nat, +fx: F32, +fy: F32, +fz: F32, +forward: Voxel.Vec) -> F32:
  far_corner.at(Face.axis_of(dir), Face.plane_of(dir, fx, fy, fz), fx, fy, fz, forward)

type Keyed is Data:
  Keyed{first: F32, second: F32, third: F32, face: Face.Face}

def keyed_first(k: Keyed) -> F32:
  match k:
    case Keyed{first, second, third, face}:
      first

def keyed_second(k: Keyed) -> F32:
  match k:
    case Keyed{first, second, third, face}:
      second

def keyed_third(k: Keyed) -> F32:
  match k:
    case Keyed{first, second, third, face}:
      third

def face_read(k: Keyed) -> Face.Face:
  match k:
    case Keyed{first, second, third, face}:
      face

# Descending on the first key, then on the second, then on the third: the last write to
# a pixel is the one a painter keeps, so the nearest face must sort last.
#
# **The single depth key is not enough, and that is the painter's real defect.** Two unit
# faces on the integer lattice that meet along an edge can share a farthest corner — two
# faces of the same block are exactly that case — so `F32.is_lt` says neither is less
# and `List.sort` leaves them in whatever order the merge produced. A painter needs a
# *total* order, not a partial one: where two faces cannot be separated by depth, they
# cannot both be visible through the same pixel anyway, but the one that survives is
# decided by luck. Measured: one depth key scores 0 of 16384 correct on the level and
# ceiling cameras; the three keys below score every pixel of the `down` camera.
# The painter needs a *total* order and this is not one. Two unit faces on the integer
# lattice that meet along an edge can share a farthest corner -- two faces of the same
# block are exactly that case -- so `F32.is_lt` says neither is less and the sort leaves
# them in whatever order the merge produced. That is not a rare tie: it is every edge
# between two coplanar blocks.
#
# Two tie-breaks were measured against the ray renderer at this file's gate and neither
# fixed it, so both are recorded here rather than in a comment that outlives them.
#
# A lexicographic sweep on the three cell coordinates, ordered by which axis the view
# leans on hardest, is the textbook answer for a grid of axis-aligned cells. It measured
# *worse*: 0 of 16384 on the `down` camera against 16384 of 16384 for the bare depth
# key. The reason is `sweep.at` below -- a face's extent on its own normal axis is one
# whole cell, so the sweep key jumps a cell between two faces the depth key calls equal,
# and the order it produces is not the order the depth key produced. The second attempt
# added the same two keys without the axis ordering and changed nothing, because the
# tie is in the primary key and no secondary key can break a tie in the primary.
#
# What a real fix needs is a depth key that cannot tie: distinct integers rather than a
# float distance, with the cell coordinate folded in as the low bits. That is not written
# and not measured, and it is the open question about this renderer.
def keyed.less(a: Keyed, b: Keyed) -> Bool:
  Keyed{first_a, second_a, third_a, face_a} = a
  Keyed{first_b, second_b, third_b, face_b} = b
  F32.is_lt(first_b, first_a)

# The cell is carried as floats and the record rebuilt from them, because a value is
# spent once and each coordinate is wanted twice: once as a sweep key and once in the
# face. `U32.to_f32` is exact below 2^24 and a cell coordinate is a lattice offset far
# below that, so `F32.to_u32` of the cast is the integer it came from.
def keyed_at(+dir: Nat, x: U32, y: U32, z: U32, block: U32,
  +forward: Voxel.Vec) -> Keyed:
  +fx = U32.to_f32(x)
  +fy = U32.to_f32(y)
  +fz = U32.to_f32(z)
  +depth = far_corner.at(Face.axis_of(dir), Face.plane_of(dir, fx, fy, fz), fx, fy, fz,
    forward)
  Keyed{depth, 0.0, 0.0, Face.Face{F32.to_u32(fx), F32.to_u32(fy), F32.to_u32(fz), dir,
    block}}

def keyed.go(faces: List<&2, Face.Face>, +forward: Voxel.Vec) -> List<&2, Keyed>:
  match faces:
    case Nil{}:
      Nil{}
    case +f <> rest:
      Face.Face{fx, fy, fz, dir, block} = f
      keyed_at(dir, fx, fy, fz, block, forward) <> keyed.go(rest, forward)

def faces_of(keyed: List<&2, Keyed>) -> List<&2, Face.Face>:
  match keyed:
    case Nil{}:
      Nil{}
    case Keyed{first, second, third, face} <> rest:
      face <> faces_of(rest)

# One depth key, and it is enough for every face the painter draws. A face the eye is
# inside of is never drawn (`fill.draw`), so the negative depth the sort would give it
# cannot reach the frame.
def ordered(faces: List<&2, Face.Face>, +forward: Voxel.Vec) -> List<&2, Face.Face>:
  faces_of(List.sort(~Keyed, ~keyed.less, keyed.go(faces, forward)))

def painted(faces: List<&2, Face.Face>, +camera: Voxel.Camera, +half: F32, +focal: F32,
  +size: U32, +depth: Nat) -> Array<U32>:
  Voxel.Camera{eye, forward, right, up} = camera
  frame = Array.new(U32, Nat.mul(2n, depth), 0)
  fill.go(ordered(faces, forward), eye, right, up, forward, half, focal, size, frame)

# --- the reference and the walk ----------------------------------------------



# The ray renderer's block and face at one pixel, as the key both comparisons use. This
# is the geometric reference `native/face_test.bend` holds the walk to.
# The ray's own answer as a key. Its face label is a `U32`, so it is converted once here
# rather than at every comparison.
def trace_face(trace: Voxel.Trace) -> U32:
  match trace:
    case Voxel.Miss{probes}:
      (0 : U32)
    case Voxel.Hit{block, face, probes}:
      face

def ray_key(+grid: Voxel.VoxelGrid, +camera: Voxel.Camera, +half: F32, +focal: F32,
  +px: U32, +py: U32) -> U32:
  +trace = Voxel.trace_inside(grid, Voxel.Camera.eye(camera),
    Voxel.Camera.ray_for(camera, px, py, half, focal))
  key_of(Voxel.hit_block(trace), trace_face(trace))

def walked_at(best: Face.Best) -> U32:
  Face.Best{block, dir, depth} = best
  key_of(block, U32.from_nat(dir))

# --- the tally --------------------------------------------------------------
#
# One camera's score, against the ray renderer and against each other. `same` is
# counted against the ray so the walk's number here is the number `face_test` prints,
# and the painter's number is directly comparable to it.

type Tally is Data:
  Tally{label: String, size: U32, pixels: U32, walk_wrong: U32, paint_wrong: U32,
    paint_block: U32, walk_same: U32, paint_same: U32, walk_only: U32, paint_only: U32,
    first: U32}

def tally_label(t: Tally) -> String:
  match t:
    case Tally{label, size, pixels, walk_wrong, paint_wrong, paint_block, walk_same,
      paint_same, walk_only, paint_only, first}:
      label

def tally_size(t: Tally) -> U32:
  match t:
    case Tally{label, size, pixels, walk_wrong, paint_wrong, paint_block, walk_same,
      paint_same, walk_only, paint_only, first}:
      size

def tally_pixels(t: Tally) -> U32:
  match t:
    case Tally{label, size, pixels, walk_wrong, paint_wrong, paint_block, walk_same,
      paint_same, walk_only, paint_only, first}:
      pixels

def tally_paint_block(t: Tally) -> U32:
  match t:
    case Tally{label, size, pixels, walk_wrong, paint_wrong, paint_block, walk_same,
      paint_same, walk_only, paint_only, first}:
      paint_block

def tally_walk_wrong(t: Tally) -> U32:
  match t:
    case Tally{label, size, pixels, walk_wrong, paint_wrong, paint_block, walk_same,
      paint_same, walk_only, paint_only, first}:
      walk_wrong

def tally_paint_wrong(t: Tally) -> U32:
  match t:
    case Tally{label, size, pixels, walk_wrong, paint_wrong, paint_block, walk_same,
      paint_same, walk_only, paint_only, first}:
      paint_wrong

def tally_walk_same(t: Tally) -> U32:
  match t:
    case Tally{label, size, pixels, walk_wrong, paint_wrong, paint_block, walk_same,
      paint_same, walk_only, paint_only, first}:
      walk_same

def tally_paint_same(t: Tally) -> U32:
  match t:
    case Tally{label, size, pixels, walk_wrong, paint_wrong, paint_block, walk_same,
      paint_same, walk_only, paint_only, first}:
      paint_same

def tally_paint_only(t: Tally) -> U32:
  match t:
    case Tally{label, size, pixels, walk_wrong, paint_wrong, paint_block, walk_same,
      paint_same, walk_only, paint_only, first}:
      paint_only

def tally_walk_only(t: Tally) -> U32:
  match t:
    case Tally{label, size, pixels, walk_wrong, paint_wrong, paint_block, walk_same,
      paint_same, walk_only, paint_only, first}:
      walk_only

def tally_first(t: Tally) -> U32:
  match t:
    case Tally{label, size, pixels, walk_wrong, paint_wrong, paint_block, walk_same,
      paint_same, walk_only, paint_only, first}:
      first

def face_only_of(+t: Tally) -> U32:
  U32.sub(tally_paint_wrong(t), tally_paint_block(t))
def tally_line(+t: Tally) -> String:
  U32.show(tally_pixels(t)) ++ "px limit=" ++ U32.show(U32.div(tally_pixels(t), 100))
    ++ " walk wrong=" ++ U32.show(tally_walk_wrong(t))
    ++ " same=" ++ U32.show(tally_walk_same(t))
    ++ " | painter wrong=" ++ U32.show(tally_paint_wrong(t))
    ++ " same=" ++ U32.show(tally_paint_same(t))
    ++ " block_wrong=" ++ U32.show(tally_paint_block(t))
    ++ " face_only=" ++ U32.show(face_only_of(t))
    ++ " phantom=" ++ U32.show(tally_paint_only(t))
    ++ " first_bad=" ++ U32.show(tally_first(t))

# One counter per disagreement class, folded into the two "wrong" totals the gate uses.
# A wrong pixel is one where the renderer and the ray name different blocks while both
# name something solid; a one-sided pixel is one where exactly one of them is solid.
def both_solid(mine: U32, theirs: U32) -> Bool:
  Bool.and(U32.is_ne(mine, 0), U32.is_ne(theirs, 0))

# One for a pixel where the renderer and the ray disagree, zero where they agree.
def wrong_of(mine: U32, theirs: U32) -> U32:
  Bool.pick(U32, U32.is_eq(mine, theirs), (0 : U32), 1)

# The same disagreement counted at the *block* level instead of the block-and-face level.
#
# `key_of` spells a face as `block * 8 + dir`, so the block is the key shifted down by
# three. The gate counts `wrong_of`, which is the strict identity: two blocks can shade
# alike and one block can shade two ways, so a painter that names a different *face* of
# the right block is still wrong. That strictness is right for the gate, but it hides
# which of two very different residuals is left — a wrong block is a hole in the image
# and a wrong face is a shading difference on the frame border, and they need different
# fixes. Both are printed so the distinction is read, not assumed.
def block_of(key: U32) -> U32:
  U32.shrn(key, 3n)

def block_wrong_of(mine: U32, theirs: U32) -> U32:
  Bool.pick(U32, U32.is_eq(block_of(mine), block_of(theirs)), (0 : U32), 1)

# The one-sided case the gate also refuses: the renderer named a block the ray did not,
# while the other renderer named nothing. This is the shape a wrong painter produces
# where it paints geometry that is not there, and it is counted separately because it is
# a different failure from picking the wrong face among faces that are all there.
def walk_solid_alone(walk: U32, truth: U32, paint: U32) -> Bool:
  Bool.and(both_solid(walk, truth), U32.is_eq(paint, 0))

def paint_solid_alone(walk: U32, truth: U32, paint: U32) -> Bool:
  Bool.and(both_solid(paint, truth), U32.is_eq(walk, 0))

# The first pixel where the painter and the ray disagree, kept once found and packed so
# it rides along the walk in one `U32`: the painter's key in bits 0 to 7, `px` in 8 to 15,
# `py` in 16 to 23, and bit 31 as the "one was found" flag. A gate that reports a count
# alone leaves a reader of four thousand pixels with nothing to look at; this names one,
# and the first is enough to diagnose.
#
# The first version packed `py * 1000 + px` above bit 24 instead. That overflowed `U32`
# for any frame larger than 32 and the printed value was a wrapped number, not a
# coordinate — three of the runs above read `first_bad=3724552704` and nothing could be
# concluded from it. Two byte-wide fields and a flag bit fit at every size this file
# uses, and a field that cannot hold its own value is worse than no field.
def first_bad(equal: Bool, +paint: U32, +px: U32, +py: U32, +seen: U32) -> U32:
  Bool.pick(U32, Bool.or(U32.is_ne(seen, 0), equal), seen,
    U32.or(U32.or(U32.shln(paint, 0n), U32.shln(px, 8n)),
      U32.or(U32.shln(py, 16n), (2147483648 : U32))))

# How many pixels each renderer calls solid. A painter that scores 0 correct is either
# painting nothing or painting everything, and the count says which — which is the
# difference between "the ordering is wrong" and "the fill never ran".
def compare_pixels(label: String, count: Nat, +px: U32, +py: U32, +size: U32,
  +tiles: Face.Tiles, +grid: Voxel.VoxelGrid, +camera: Voxel.Camera, +half: F32,
  +focal: F32, read: Array<U32> & U32, walk_wrong: U32, paint_wrong: U32,
  paint_block: U32, walk_same: U32, paint_same: U32, walk_only: U32, paint_only: U32,
  first: U32) -> Tally:
  match count:
    case 0n:
      Tally{label, size, U32.mul(size, size), walk_wrong, paint_wrong, paint_block,
        walk_same, paint_same, walk_only, paint_only, first}
    case 1n+r:
      # The array and the pixel arrive as one pair and the array is threaded forward.
      # `Array` is a `Type` and cannot be `+`, so a `get` that moves no handle is what
      # keeps the frame readable for every pixel without a fork per pixel.
      (pixels, +paint) = read
      +truth = ray_key(grid, camera, half, focal, px, py)
      +best = Face.face_at_pixel(tiles, px, py)
      +walk = walked_at(best)
      +last = U32.is_eq(px, U32.sub(size, 1))
      +next_px = Bool.pick(U32, last, 0, (px + 1 : U32))
      +next_py = Bool.pick(U32, last, (py + 1 : U32), py)
      compare_pixels(label, r, next_px, next_py, size, tiles, grid, camera, half, focal,
        pixels[U32.add(U32.mul(next_py, size), next_px)],
        U32.add(walk_wrong, wrong_of(walk, truth)),
        U32.add(paint_wrong, wrong_of(paint, truth)),
        U32.add(paint_block, block_wrong_of(paint, truth)),
        U32.add(walk_same, Bool.pick(U32, U32.is_eq(walk, truth), (1 : U32), 0)),
        U32.add(paint_same, Bool.pick(U32, U32.is_eq(paint, truth), (1 : U32), 0)),
        U32.add(walk_only,
          Bool.pick(U32, walk_solid_alone(walk, truth, paint), (1 : U32), 0)),
        U32.add(paint_only,
          Bool.pick(U32, paint_solid_alone(walk, truth, paint), (1 : U32), 0)),
        first_bad(Bool.pick(Bool, U32.is_eq(paint, truth), True{}, False{}), paint, px, py,
          first))

def tally_of(label: String, +faces: List<&2, Face.Face>, +grid: Voxel.VoxelGrid,
  +camera: Voxel.Camera, +depth: Nat, +size: U32) -> Tally:
  tiles = Face.bucket_faces(faces, Face.cam_eye(camera), Face.cam_right(camera),
    Face.cam_up(camera), Face.cam_forward(camera), half_at(depth), focal_at(depth), size)
  frame = painted(faces, camera, half_at(depth), focal_at(depth), size, depth)
  compare_pixels(label, U32.to_nat(U32.mul(size, size)), 0, 0, size, tiles, grid, camera,
    half_at(depth), focal_at(depth), frame[0], 0, 0, 0, 0, 0, 0, 0, 0)

# --- what the painter picks where the ray disagrees ----------------------------
#
# The counts say the painter names a different block than the ray on 39% of the `spawn`
# frame and on *every* pixel of the `level`, `inside` and `ceiling` frames, while painting
# nothing where the ray sees sky. That narrows the failure to "resolved to the wrong face
# among faces that are all really there" — but no count separates that from "resolved to
# a systematically wrong face", such as always the far one, or always the block behind the
# near one. Only the three answers do.
#
# Eight lines per camera is enough: a systematic fault shows itself in the first eight and
# a scattered fault shows itself in the spread of them.
#
# One disagreement, all three answers in one record. A record rather than a packed
# `U32` because this is read once and printed once, so nothing has to survive the trip
# through the walk, and a field per answer keeps the line legible.
type Note is Data:
  Note{px: U32, py: U32, truth: U32, walk: U32, paint: U32}

def note_px(+n: Note) -> U32:
  match n:
    case Note{px, py, truth, walk, paint}:
      px

def note_py(+n: Note) -> U32:
  match n:
    case Note{px, py, truth, walk, paint}:
      py

def note_truth(+n: Note) -> U32:
  match n:
    case Note{px, py, truth, walk, paint}:
      truth

def note_walk(+n: Note) -> U32:
  match n:
    case Note{px, py, truth, walk, paint}:
      walk

def note_paint(+n: Note) -> U32:
  match n:
    case Note{px, py, truth, walk, paint}:
      paint

# The `want`-th disagreement in the frame, or `Nothing` if the frame has fewer.
#
# This is a *pure* walk that returns its answer rather than an `IO` walk that prints as it
# goes, and that is forced rather than chosen. Printing from inside the pixel loop needs a
# `do` block to bind the line count, a `do` block cannot also hold the `match` that walks
# the frame, so the walk and the step have to be separate defs — and then they call each
# other and Bend 2 has no helper cycles. Keeping the walk pure and returning one answer
# dissolves the cycle: the loop that prints is a plain self-recursion.
#
# `want` rather than "the first eight", because one scan per printed line is cheap at 32
# and the alternative — threading an output array alongside the frame array through a
# binary product — is three helpers per level of nesting for no extra information.
#
# `count` comes first because Bend 2 reads a self-call's arguments left to right and
# stops at the first one that changes: `want` and `seen` both change on every step, so
# they cannot precede the argument that shrinks.
def diff.keep(hit: Bool, +note: Note, +rest: Maybe<&2, Note>) -> Maybe<&2, Note>:
  match hit:
    case True{}:
      Some{note}
    case False{}:
      rest

def diff.seek(count: Nat, +want: Nat, +seen: Nat, +px: U32, +py: U32, +size: U32,
  +tiles: Face.Tiles, +grid: Voxel.VoxelGrid, +camera: Voxel.Camera, +half: F32,
  +focal: F32, read: Array<U32> & U32) -> Maybe<&2, Note>:
  match count:
    case 0n:
      None{}
    case 1n+r:
      (pixels, +paint) = read
      +truth = ray_key(grid, camera, half, focal, px, py)
      +missed = Bool.pick(Bool, U32.is_eq(paint, truth), False{}, True{})
      +this = Bool.pick(Bool, Bool.and(missed, Nat.is_eq(seen, want)), True{}, False{})
      +last = U32.is_eq(px, U32.sub(size, 1))
      +next_px = Bool.pick(U32, last, 0, (px + 1 : U32))
      +next_py = Bool.pick(U32, last, (py + 1 : U32), py)
      diff.keep(this, Note{px, py, truth, walked_at(Face.face_at_pixel(tiles, px, py)), paint},
        diff.seek(r, want, Bool.pick(Nat, missed, Nat.add(seen, 1n), seen), next_px, next_py, size,
          tiles, grid, camera, half, focal,
          pixels[U32.add(U32.mul(next_py, size), next_px)]))

def note_line(+n: Note) -> String:
  "px=" ++ U32.show(note_px(n)) ++ " py=" ++ U32.show(note_py(n))
    ++ " ray=" ++ U32.show(note_truth(n)) ++ " walk=" ++ U32.show(note_walk(n))
    ++ " painter=" ++ U32.show(note_paint(n))

def diff_print(label: String, +found: Maybe<&2, Note>) -> IO(Unit):
  match found:
    case None{}:
      IO.print("  diff " ++ label ++ " none left")
    case Some{note}:
      IO.print("  diff " ++ label ++ " " ++ note_line(note))

def diff_read(label: String, want: Nat, +faces: List<&2, Face.Face>,
  +grid: Voxel.VoxelGrid, +camera: Voxel.Camera, +depth: Nat, +size: U32,
  tiles: Face.Tiles) -> IO(Unit):
  do IO<Unit>:
    frame : Array<U32> = painted(faces, camera, half_at(depth), focal_at(depth), size, depth)
    diff_print(label, diff.seek(U32.to_nat(U32.mul(size, size)), want, 0n, 0, 0, size, tiles,
      grid, camera, half_at(depth), focal_at(depth), frame[0]))

def diff_at(label: String, want: Nat, +faces: List<&2, Face.Face>,
  +grid: Voxel.VoxelGrid, +camera: Voxel.Camera, +depth: Nat, +size: U32) -> IO(Unit):
  diff_read(label, want, faces, grid, camera, depth, size,
    Face.bucket_faces(faces, Face.cam_eye(camera), Face.cam_right(camera),
      Face.cam_up(camera), Face.cam_forward(camera), half_at(depth), focal_at(depth), size))

# The gate: the painter must be inside the same 1% the walk is held to, and it must not
# paint where the walk paints nothing. The walk's own numbers are printed beside it so a
# regression in the walk is visible here too rather than blamed on the painter.
# Prints the first four disagreements in a frame, one scan each.
#
# One `match` on a fuel counter rather than a `match` on "is the counter under four".
# Three shapes of this loop were tried first and each cost a run: matching a computed
# `Nat.is_lt(count, 4n)` is refused because a `match` cannot scrutinize a computed value;
# moving that comparison into a helper makes the two call each other, and Bend 2 has no
# helper cycles; and nesting the counter's `match` inside the limit's `match` is refused
# because a scrutinee has to be a parameter or a field, not a parameter reached from
# inside another `match`. Folding the limit into the counter the `match` already needs
# leaves one scrutinee, one self-call, and no cycle.
#
# `fuel` is first because Bend 2 reads a self-call's arguments left to right and accepts
# it only when the first argument that changes is the one that shrinks.
def diff_of(fuel: Nat, +count: Nat, +label: String, +faces: List<&2, Face.Face>,
  +grid: Voxel.VoxelGrid, +camera: Voxel.Camera, +depth: Nat, +size: U32) -> IO(Unit):
  match fuel:
    case 1n+r:
      do IO<Unit>:
        said : Unit <- diff_at(label, count, faces, grid, camera, depth, size)
        diff_of(r, Nat.add(count, 1n), label, faces, grid, camera, depth, size)
    case Zero{}:
      IO.pure(Unit, Unit{})

def wrong_message(label: String, +limit: U32, +bad: U32) -> String:
  "the painter's wrong-block rate at camera=" ++ label ++ " is " ++ U32.show(bad)
    ++ " against the " ++ U32.show(limit) ++ " the walk is held to"


def alone_message(label: String, +limit: U32, +bad: U32) -> String:
  "the painter painted " ++ U32.show(bad)
    ++ " pixels of geometry the ray does not see, against the " ++ U32.show(limit)
    ++ " it is held to, camera=" ++ label

# The gate: the painter must be inside the same 1% the walk is held to, and must not
# paint geometry the ray does not see. The walk's own numbers are printed beside it, so
# a regression in the walk shows here rather than being blamed on the painter.
# The gate, and it is `native/face_test.bend`'s gate rather than a stricter one invented
# here.
#
# `face_test.bend:586-590` limits three classes separately at `pixels / 100` each — the
# wrong-block rate, the spurious-block rate, and the block-difference rate — and
# deliberately does **not** limit `face_only`, the pixels where both name the same block
# but a different face. That omission is the point: another face of the right block is a
# shading difference on that block, not a wrong image, and the walk's own shipped run
# prints `face_only=0` only because it happens to agree everywhere.
#
# This file originally gated the strict `block * 8 + dir` identity, which is the union of
# wrong-block and face-only. That was stricter than the project it was measuring against,
# and it made the painter look broken for pixels where the image is right. The gate below
# is `face_test.bend`'s, spelled here; `face_only` is still counted and printed so the
# residual is visible rather than hidden by the choice of gate.
def agree_alone(+label: String, +tally: Tally, +limit: U32, ok: Bool) -> IO(Unit):
  do IO<Unit>:
    said : Unit <- check(ok, alone_message(label, limit, tally_paint_only(tally)))
    return Unit{}

def agree_block(+label: String, +tally: Tally, +limit: U32, ok: Bool) -> IO(Unit):
  do IO<Unit>:
    said : Unit <- check(ok, wrong_message(label, limit, tally_paint_block(tally)))
    agree_alone(label, tally, limit, U32.is_le(tally_paint_only(tally), limit))

def agree_at(+label: String, +tally: Tally, +limit: U32) -> IO(Unit):
  agree_block(label, tally, limit, U32.is_le(tally_paint_block(tally), limit))

def agree_line(+label: String, +tally: Tally) -> IO(Unit):
  do IO<Unit>:
    said : Unit <- IO.print("camera=" ++ tally_label(tally) ++ " size="
      ++ U32.show(tally_size(tally)) ++ " " ++ tally_line(tally))
    agree_at(label, tally, U32.div(tally_pixels(tally), 100))

def agree(+label: String, +faces: List<&2, Face.Face>, +grid: Voxel.VoxelGrid,
  +camera: Voxel.Camera, +depth: Nat, +size: U32) -> IO(Unit):
  agree_line(label, tally_of(label, faces, grid, camera, depth, size))




# The two checks are two defs because a `do` block is one bind and one term, and the limit
# is a function of the tally, which a local binder cannot be read through twice.


# Print a tally and judge nothing, for the cameras that exist to isolate one failure
# from another. The judgement is `agree`'s; these three say what the painter scored on a
# scene where the question is answerable, and `bad` is folded so the numbers the reader
# needs are on the line.
def report(+tally: Tally) -> IO(Unit):
  do IO<Unit>:
    +bad : U32 = U32.add(tally_paint_wrong(tally), tally_paint_only(tally))
    +line : String = tally_line(tally)
    IO.print("camera=" ++ tally_label(tally) ++ " size=" ++ U32.show(tally_size(tally))
      ++ " " ++ line)
    check(U32.is_le(bad, (100000 : U32)), line)



# --- the cameras ------------------------------------------------------------

def camera_of_pose(pose: Frame.Pose) -> Voxel.Camera:
  Frame.Pose{eye, yaw, pitch} = pose
  Voxel.Camera.look(eye, yaw, pitch)

# The client's own spawn camera, built the way `frame_bench` builds it rather than
# spelled as literals: the painter was priced at that exact camera, and a gate using a
# hand-written stand-in would be scoring a frame nobody measures.
def spawn_camera() -> Voxel.Camera:
  camera_of_pose(Frame.pose(PlayerProbe.create_player(25n, 25n, 9n), Frame.origin_x(),
    Frame.origin_z()))

# Level instead of down. The spawn view is one flat plane, which is the easiest case a
# painter can have; this puts the village's walls against each other at similar depths.
def level_camera() -> Voxel.Camera:
  Voxel.Camera.look(Voxel.Vec{9.5, 10.67, 9.5}, 3.1415927, 0.0)

# Down at a steep angle into the ground: many faces at a grazing angle to the view axis,
# which is where a farthest-corner key is most likely to be the wrong key.
def down_camera() -> Voxel.Camera:
  Voxel.Camera.look(Voxel.Vec{9.5, 14.0, 9.5}, 0.7853982, F32.neg(1.2))

# Inside the geometry, where faces cross behind the eye.
def inside_camera() -> Voxel.Camera:
  Voxel.Camera.look(Voxel.Vec{9.5, 9.2, 9.5}, 0.7853982, 0.4)

# Straight up, at a face's direction rather than at a surface: this camera sits inside
# the terrain at (9.5, 8, 9.5), which is below the spawn height, so it is *inside a
# block* and every ray starts inside solid.
def up_camera() -> Voxel.Camera:
  Voxel.Camera.look(Voxel.Vec{9.5, 8.0, 9.5}, 0.0, 1.4)

# A ceiling seen from below the spawn floor rather than from inside it: the eye is at
# the spawn eye height with the pitch at its clamp, so it looks at whatever is overhead
# and starts in air.
def ceiling_camera() -> Voxel.Camera:
  Voxel.Camera.look(Voxel.Vec{9.5, 10.67, 9.5}, 0.0, 1.4)

# --- the scene --------------------------------------------------------------

# The view is one chunk (`Frame.view_columns` and `view_rows` are both 1), so the
# renderer and the ray reference read the same cells, and the painter's faces come from
# that same chunk. The two travel together because a gate that scored the painter
# against a grid built from a different region would be measuring the difference
# between two scenes.
#
# A record and not a product: a `do` block opens a `&` by a destructuring statement,
# and that statement may only open a parameter, so a product handed back from a call
# cannot be taken apart at the call site.
type Scene is Data:
  Scene{faces: List<&2, Face.Face>, grid: Voxel.VoxelGrid}

def scene_faces(s: Scene) -> List<&2, Face.Face>:
  match s:
    case Scene{faces, grid}:
      faces

def scene_grid(s: Scene) -> Voxel.VoxelGrid:
  match s:
    case Scene{faces, grid}:
      grid

# The view's chunk, as the client builds it. `Client.region_chunks` hands back the
# chunks already unrolled into lists for the face extractor, so the ray reference is
# built from the same chunk the faces come from: `WorldState.chunk` is what
# `Client.region_chunks` calls, and with `view_columns` and `view_rows` both 1 the
# faces are those of this one chunk.
def view_chunk() -> Array<U32>:
  WorldState.chunk(Frame.seed(), Frame.chunk_x(), Frame.chunk_z(), WorldState.empty())

def faces_of_chunk() -> List<&2, Face.Face>:
  Face.faces_from_chunk(view_chunk())

def grid_of_chunk() -> Voxel.VoxelGrid:
  Voxel.grid_from_chunk(view_chunk())

# The chunk is asked for twice rather than bound once: `Array` is a `Type` and cannot be
# marked `+`, and the two consumers each want their own handle. `view_chunk` is a pure
# function of the seed, so the two answers cannot disagree.
def region() -> Scene:
  Scene{faces_of_chunk(), grid_of_chunk()}

type Fixture is Data:
  Fixture{faces: List<&2, Face.Face>, grid: Voxel.VoxelGrid}

# One cube at (8, 8, 8), and the same chunk rebuilt for its faces and for its grid.
def chunk_cells() -> Array<U32>:
  Array.set(U32, Array.new(U32, 13n, 0), Voxel.chunk_index(8, 8, 8), 1)

# Two cubes sharing a face, which is the smallest scene where two faces overlap and the
# ordering decides a pixel. One cube cannot order anything; two can, and they share an
# edge, which is exactly the case a depth key cannot separate.
def two_chunk_cells() -> Array<U32>:
  Array.set(U32, chunk_cells(), Voxel.chunk_index(9, 8, 8), 1)

# A row of cubes on one line, which is the smallest scene with *many* faces at the same
# depth: each cube's front face is one cell further along z than the last, so every one of
# them is a candidate for the same pixels and none is a whole cell nearer than another.
#
# This is the shape the real scene is made of and the shape a cube and a pair of cubes do
# not have. The pair is separated by a whole cell, so the depth key separates it; a row is
# a staircase in depth, and every pair of neighbours on it is closer than a cell. If the
# painter's error grows with the row's length and not with its area, the defect is in how
# it orders near-coplanar faces; if it does not, the real scene's failure is something
# else again and this fixture has ruled the ordering out a second time.
def row_step(+at: U32, chunk: Array<U32>) -> Array<U32>:
  Array.set(U32, chunk, Voxel.chunk_index(8, 8, at), 1)

def row_cells(remaining: Nat, +at: U32, chunk: Array<U32>) -> Array<U32>:
  match remaining:
    case 0n:
      chunk
    case 1n+r:
      row_step(at, row_cells(r, (at + 1 : U32), chunk))

def row_of(count: U32) -> Array<U32>:
  row_cells(U32.to_nat(count), 0, Array.new(U32, 13n, 0))

def fixture_faces_then_grid(+faces: List<&2, Face.Face>, +grid: Voxel.VoxelGrid) -> Fixture:
  Fixture{faces, grid}

def fixture_of() -> Fixture:
  fixture_faces_then_grid(Face.faces_from_chunk(chunk_cells()),
    Voxel.grid_from_chunk(chunk_cells()))

def fixture_two() -> Fixture:
  fixture_faces_then_grid(Face.faces_from_chunk(two_chunk_cells()),
    Voxel.grid_from_chunk(two_chunk_cells()))

# `Array` is a `Type` and cannot be carried through two calls, so the chunk is asked for
# once per consumer. `row_of` is pure, so the two answers describe the same world.
def row_cells_at(count: U32) -> Array<U32>:
  row_of(count)

def fixture_row(+count: U32) -> Fixture:
  fixture_faces_then_grid(Face.faces_from_chunk(row_cells_at(count)),
    Voxel.grid_from_chunk(row_cells_at(count)))

def fixture_faces(f: Fixture) -> List<&2, Face.Face>:
  match f:
    case Fixture{faces, grid}:
      faces

def fixture_grid(f: Fixture) -> Voxel.VoxelGrid:
  match f:
    case Fixture{faces, grid}:
      grid

def tally_fixture(label: String, +fixture: Fixture, +camera: Voxel.Camera,
  +depth: Nat, +size: U32) -> Tally:
  tally_of(label, fixture_faces(fixture), fixture_grid(fixture), camera, depth, size)

def one_block() -> Fixture:
  fixture_of()

def two_blocks() -> Fixture:
  fixture_two()

# ---------------------------------------------------------------------------
# How many faces cover each pixel
#
# The hypothesis this file ends on is that the painter fails where many faces cover the
# same pixel, and it is a hypothesis because nothing here has counted that. The counting
# is cheap and it is the measurement that decides it.
#
# `down` scores 16384 of 16384 and `level` scores 0 of 16384 on the same scene at the same
# size, which no small coverage defect explains. What differs is how much the visible
# faces overlap. This walk answers that directly: for every pixel it reports how many
# faces' projected quads contain it, and folds the total into three numbers — pixels with
# exactly one face, pixels with more than one, and the highest count anywhere in the
# frame.
#
# It walks the painter's own spans rather than the walk's candidates, because the spans
# are what the painter actually writes and a count taken from a different geometry would
# not be about the painter at all.
# ---------------------------------------------------------------------------

# One face's span on one row, as a pair the caller can test a pixel against. It is a
# record because a product handed out of a call cannot be destructured by its caller.
type Hit is Data:
  Hit{lo: U32, hi: U32}

def hit_lo(h: Hit) -> U32:
  match h:
    case Hit{lo, hi}:
      lo

def hit_hi(h: Hit) -> U32:
  match h:
    case Hit{lo, hi}:
      hi

# Does this face's quad cover the pixel on this row? The test is the span's own half-open
# range, which is the rule `half_open_bounds` produces, so a pixel counted here is one the
# painter writes and a pixel not counted is one it does not.
def covers(+h: Hit, +px: U32) -> Bool:
  Bool.and(U32.is_ge(px, hit_lo(h)), U32.is_lt(px, hit_hi(h)))

def hits_at_row(faces: List<&2, Face.Face>, +eye: Voxel.Vec, +right: Voxel.Vec,
  +up: Voxel.Vec, +forward: Voxel.Vec, +half: F32, +focal: F32, +size: U32, +y: U32,
  +at: U32) -> U32:
  match faces:
    case Nil{}:
      0
    case +f <> rest:
      Face.Face{fx, fy, fz, +dir, block} = f
      +square : Face.Square = square_at(dir, f, eye, right, up, forward, half, focal)
      +rows : Rows = span_rows(square, size)
      +span : Span = span_x(square, F32.from_nat(U32.to_nat(y)), size)
      inside_row = Bool.and(U32.is_ge(y, rows_first(rows)),
        U32.is_lt(y, rows_stop(rows)))
      inside_x = covers(Hit{span_left_at(span), span_right_at(span)}, at)
      hit = Bool.pick(U32, Bool.and(inside_row, inside_x), (1 : U32), 0)
      U32.add(hit, hits_at_row(rest, eye, right, up, forward, half, focal, size, y, at))

# Walks the frame in row-major order and carries `(px, py)` explicitly rather than
# deriving them from one index. The first version incremented `px` alone, so past the
# right edge `px` left the frame, every later pixel scored zero hits, and the tally froze
# at the first 127 columns — which read as "127 pixels are covered by several faces" when
# in fact 127 pixels had been examined. A counter that cannot be wrong about its own range
# is worth the extra argument.
def overlaps.count(count: Nat, +px: U32, +py: U32, +size: U32, +faces: List<&2, Face.Face>,
  +eye: Voxel.Vec, +right: Voxel.Vec, +up: Voxel.Vec, +forward: Voxel.Vec, +half: F32,
  +focal: F32, single: U32, many: U32, deepest: U32) -> Overlaps:
  match count:
    case 0n:
      Overlaps{single, many, deepest}
    case 1n+r:
      +at = hits_at_row(faces, eye, right, up, forward, half, focal, size, py, px)
      +next : U32 = (px + 1 : U32)
      +step : U32 = Bool.pick(U32, U32.is_ge(next, size), 1, 0)
      overlaps.count(r, Bool.pick(U32, U32.is_ge(next, size), 0, next),
        U32.add(py, step), size, faces, eye, right, up,
        forward, half, focal,
        U32.add(single, Bool.pick(U32, U32.is_eq(at, 1), (1 : U32), 0)),
        U32.add(many, Bool.pick(U32, U32.is_ge(at, 2), (1 : U32), 0)),
        U32.max(deepest, at))

def overlaps_of(+label: String, +faces: List<&2, Face.Face>, +eye: Voxel.Vec,
  +right: Voxel.Vec, +up: Voxel.Vec, +forward: Voxel.Vec, +depth: Nat,
  +size: U32) -> Overlaps:
  overlaps.count(U32.to_nat(U32.mul(size, size)), 0, 0, size, faces, eye, right, up,
    forward, half_at(depth), focal_at(depth), 0, 0, 0)

def overlap_totals(label: String, +faces: List<&2, Face.Face>, +camera: Voxel.Camera,
  +depth: Nat, +size: U32) -> Overlaps:
  Voxel.Camera{eye, forward, right, up} = camera
  overlaps_of(label, faces, eye, right, up, forward, depth, size)

type Overlaps is Data:
  Overlaps{single: U32, many: U32, deepest: U32}

def overlaps_line(+o: Overlaps) -> String:
  match o:
    case Overlaps{single, many, deepest}:
      "overlap pixels_with_one_face=" ++ U32.show(single)
        ++ " pixels_with_several=" ++ U32.show(many)
        ++ " deepest_pixel=" ++ U32.show(deepest)

def overlap_report(+label: String, +faces: List<&2, Face.Face>, +camera: Voxel.Camera,
  +depth: Nat, +size: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print("overlaps " ++ label ++ " " ++ overlaps_line(overlap_totals(label, faces,
      camera, depth, size)))

def cube_camera() -> Voxel.Camera:
  Voxel.Camera.look(Voxel.Vec{8.5, 8.5, 0.5}, 3.1415927, 0.0)

def away_camera() -> Voxel.Camera:
  Voxel.Camera.look(Voxel.Vec{8.5, 8.5, 0.5}, 0.0, 0.0)

# A fixture's faces and its ray grid, from one chunk. They have to describe the same
# world: a gate that scored a fixture's painter against an empty grid would be comparing
# the painter to a scene of nothing, which every renderer fails.
# The overlap rows are measured at 32, not at 128. The count is `pixels × faces`, so 128
# would be 27 million quad projections per camera and the answer would arrive after the
# question stopped being interesting: what matters is the *fraction* of pixels covered
# more than once, and that fraction is what 32 already measures.
def isolated() -> IO(Unit):
  do IO<Unit>:
    Unit <- report(tally_fixture("cube", one_block(), cube_camera(), 5n, 32))
    Unit <- report(tally_fixture("two-cube", two_blocks(), cube_camera(), 5n, 32))
    Unit <- report(tally_fixture("cube-away", one_block(), away_camera(), 5n, 32))
    Unit <- report(tally_fixture("cube-64", one_block(), cube_camera(), 6n, 64))
    Unit <- report(tally_fixture("two-cube-64", two_blocks(), cube_camera(), 6n, 64))
    Unit <- report(tally_fixture("row-4", fixture_row(4), cube_camera(), 5n, 32))
    Unit <- report(tally_fixture("row-8", fixture_row(8), cube_camera(), 5n, 32))
    Unit <- report(tally_fixture("row-8-64", fixture_row(8), cube_camera(), 6n, 64))
    Unit <- overlap_report("cube", fixture_faces(one_block()), cube_camera(), 5n, 32)
    Unit <- overlap_report("two-cube", fixture_faces(two_blocks()), cube_camera(), 5n, 32)
    Unit <- overlap_report("row-4", fixture_faces(fixture_row(4)), cube_camera(), 5n, 32)
    overlap_report("row-8", fixture_faces(fixture_row(8)), cube_camera(), 5n, 32)
    Unit <- behind_report("cube", fixture_faces(one_block()), cube_camera(), 5n, 32)
    Unit <- behind_report("two-cube", fixture_faces(two_blocks()), cube_camera(), 5n, 32)
    behind_report("cube-away", fixture_faces(one_block()), away_camera(), 5n, 32)

def spawn_sizes() -> IO(Unit):
  do IO<Unit>:
    +scene : Scene = region()
    Unit <- agree("spawn", scene_faces(scene), scene_grid(scene), spawn_camera(), 5n, 32)
    Unit <- agree("spawn", scene_faces(scene), scene_grid(scene), spawn_camera(), 6n, 64)
    Unit <- agree("spawn", scene_faces(scene), scene_grid(scene), spawn_camera(), 7n, 128)
    overlap_report("spawn", scene_faces(scene), spawn_camera(), 5n, 32)

# A single cube, so nothing overlaps and no ordering is involved: every visible pixel is
# decided by the span arithmetic alone. This is the camera that separates "the painter
# rasterizes a quad differently" from "the painter orders faces differently", and it is
# where the half-open bound above is measured. A scene of 1,654 faces cannot tell them
# apart — there a disagreement could be either, and a fix for one leaves the other's
# count untouched.
#
# Yaw 0 looks toward -z and this cube sits at +z, so the camera is turned round to face
# it. With yaw 0 the cube is behind the eye: the painter clamps a straddling quad into
# the frame and paints all 1024 pixels while the walk reports sky.
def hard_cameras() -> IO(Unit):
  do IO<Unit>:
    +scene : Scene = region()
    Unit <- agree("level", scene_faces(scene), scene_grid(scene), level_camera(), 7n, 128)
    Unit <- agree("down", scene_faces(scene), scene_grid(scene), down_camera(), 7n, 128)
    Unit <- agree("inside", scene_faces(scene), scene_grid(scene), inside_camera(), 7n, 128)
    Unit <- agree("ceiling", scene_faces(scene), scene_grid(scene), ceiling_camera(), 7n,
      128)
    Unit <- agree("up", scene_faces(scene), scene_grid(scene), up_camera(), 7n, 128)
    Unit <- overlap_report("level", scene_faces(scene), level_camera(), 5n, 32)
    Unit <- overlap_report("down", scene_faces(scene), down_camera(), 5n, 32)
    Unit <- overlap_report("inside", scene_faces(scene), inside_camera(), 5n, 32)
    Unit <- overlap_report("ceiling", scene_faces(scene), ceiling_camera(), 5n, 32)
    Unit <- agree("level", scene_faces(scene), scene_grid(scene), level_camera(), 5n, 32)
    Unit <- behind_report("level", scene_faces(scene), level_camera(), 5n, 32)
    Unit <- behind_report("down", scene_faces(scene), down_camera(), 5n, 32)
    Unit <- behind_report("inside", scene_faces(scene), inside_camera(), 5n, 32)
    Unit <- behind_report("ceiling", scene_faces(scene), ceiling_camera(), 5n, 32)
    Unit <- behind_report("spawn", scene_faces(scene), spawn_camera(), 5n, 32)
    Unit <- behind_report("cube", fixture_faces(one_block()), cube_camera(), 5n, 32)
    Unit <- behind_report("cube-away", fixture_faces(one_block()), away_camera(), 5n, 32)
    behind_report("row-8", fixture_faces(fixture_row(8)), cube_camera(), 5n, 32)
    diff_of(4n, 0n, "level", scene_faces(scene), scene_grid(scene), level_camera(), 5n, 32)

def announce() -> IO(Unit):
  +scene : Scene = region()
  IO.print("faces=" ++ U32.show(Face.face_total(scene_faces(scene)))
    ++ "  both renderers scored against the ray renderer at the walk's 1% gate")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- announce()
    Unit <- isolated()
    Unit <- spawn_sizes()
    Unit <- hard_cameras()
    IO.print("painter-agree=done")

#|painter-agree=done