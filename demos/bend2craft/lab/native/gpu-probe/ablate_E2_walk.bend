import Base
import ../../../world/world_state.bend as WorldState
import ../../../native/voxel.bend as Voxel
import ../../../native/frame.bend as Frame
import ../../../native/paint.bend as Paint
import ../../../native/sky.bend as Sky
import ../../../native/scenery.bend as Scenery
import ../../../native/play.bend as Play
import ../../../native/slabs.bend as Slabs

# THROWAWAY SPIKE. Can a device-shaped leaf draw the client's textured frame, and what does it cost?
#
# The host half is the painter's own (`Paint.frame_quads`, `Paint.deal`, `Paint.span_edges`,
# `Paint.texel_of`): nothing about which polygon wins a pixel or what it is painted with is
# re-derived here. What is new is the shape the vendored `guide/SHADERS.md` asks for: the polygons
# are dealt on the host into a quadtree of lists, one per 64-pixel cell; one bang forks it to
# 16-pixel tiles; a tile is straight-line `Qua{...}` over pixels; a pixel is one flat loop over
# the cell's list that carries the colour so far (a `def` may only call itself, so there is no
# early exit, as in the reference's `Blk.go`). No `Array` anywhere on the device side.

def fold_hash(+hash: U32, +value: U32) -> U32:
  U32.mul(U32.xor(hash, value), 16777619)

# --- the scene: what the client hands the painter, for one camera -------------------------------

type Scene is Data:
  Scene{groups: List<&2, Paint.Group>, camera: Voxel.Camera, half: F32, focal: F32, size: U32,
    depth: Nat, behind: Paint.Quads, air: U32, level: U32, sky: U32}

def scene_of(+world: Slabs.World, +pose: Frame.Pose, +depth: Nat) -> Scene:
  +home = Slabs.w_home(world)
  +camera : Voxel.Camera = Voxel.Camera.look(Frame.view_eye(Frame.eye_of(pose), home),
    Frame.yaw_of(pose), Frame.pitch_of(pose))
  +half = Voxel.projection_half(depth)
  +focal = F32.mul(1.5, half)
  +size = U32.shln((1 : U32), depth)
  +hour = Sky.clock_start()
  Scene{Slabs.w_groups(world), camera, half, focal, size, depth,
    Scenery.backdrop_at(camera, half, focal, size, Play.region_shift(Frame.home_x(home)),
      Play.region_shift(Frame.home_z(home)), hour, hour),
    Sky.air_at(hour), Sky.level_at(hour), Paint.sky_of(True{}, camera, half, focal)}

def scene_depth(+scene: Scene) -> Nat:
  Scene{+groups, +camera, +half, +focal, +size, +depth, +behind, +air, +level, +sky} = scene
  depth

def outdoor_pose(+yaw: F32, +pitch: F32) -> Frame.Pose:
  Frame.Pose{Voxel.Vec{40.5, 10.62, 25.5}, yaw, pitch}

# The polygons of the frame, nearest first: the host half both painters share.
def quads_of(+scene: Scene) -> Paint.Quads:
  Scene{+groups, +camera, +half, +focal, +size, +depth, +behind, +air, +level, +sky} = scene
  Paint.frame_quads(groups, camera, half, focal, size, Paint.QNil{}, [], behind, True{}, air, level)

def quads_len(quads: Paint.Quads, +n: U32) -> U32:
  match quads:
    case Paint.QNil{}:
      n
    case Paint.QCons{ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, first, stop, left, right, next}:
      quads_len(next, U32.add(n, 1))

# --- the CPU painter, as the client runs it ------------------------------------------------------

def cpu_image(+scene: Scene) -> Image:
  Scene{+groups, +camera, +half, +focal, +size, +depth, +behind, +air, +level, +sky} = scene
  Paint.image.of(Paint.tiles_frame_among(groups, camera, half, focal, size, depth,
    Paint.tile_of(depth), Paint.QNil{}, [], behind, True{}, air, level))

# --- host: the polygons dealt into one list per 64-pixel cell -------------------------------------

type Cells is Data:
  CNil{}
  CLeaf{quads: Paint.Quads}
  CQua{tl: Cells, tr: Cells, bl: Cells, br: Cells}

# `k` counts half-levels, as `Paint.node` does: one step from a node to its dealt quarters and
# one from those to its children.
def cells_build(+k: Nat, +log: Nat, +x0: U32, +y0: U32, work: Paint.Work) -> Cells:
  match k work:
    case _ Paint.Whole{Paint.QNil{}}:
      CNil{}
    case 0n Paint.Whole{quads}:
      CLeaf{quads}
    case 1n+r Paint.Whole{quads}:
      +half = U32.shr(U32.shln((1 : U32), log))
      cells_build(r, log, x0, y0, Paint.deal(quads, U32.add(x0, half), U32.add(y0, half),
        Paint.QNil{}, Paint.QNil{}, Paint.QNil{}, Paint.QNil{}))
    case 1n+r Paint.Dealt{qa, qb, qc, qd}:
      +half = U32.shr(U32.shln((1 : U32), log))
      +xm = U32.add(x0, half)
      +ym = U32.add(y0, half)
      +kid = Nat.sub(log, 1n)
      a b c d = cells_build(r, kid, x0, y0, Paint.Whole{qa}) cells_build(r, kid, xm, y0, Paint.Whole{qb})
        cells_build(r, kid, x0, ym, Paint.Whole{qc}) cells_build(r, kid, xm, ym, Paint.Whole{qd})
      CQua{a, b, c, d}
    case 0n Paint.Dealt{qa, qb, qc, qd}:
      CNil{}

def cells_of(+scene: Scene) -> Cells:
  Scene{+groups, +camera, +half, +focal, +size, +depth, +behind, +air, +level, +sky} = scene
  +levels = Nat.sub(depth, Paint.tile_log())
  cells_build(Nat.mul(2n, levels), depth, 0, 0,
    Paint.Whole{Paint.quads.turned(Paint.odd(levels),
      Paint.frame_quads(groups, camera, half, focal, size, Paint.QNil{}, [], behind, True{}, air, level))})

def cells_count(cells: Cells, +n: U32) -> U32:
  match cells:
    case CNil{}:
      n
    case CLeaf{quads}:
      quads_len(quads, n)
    case CQua{tl, tr, bl, br}:
      cells_count(br, cells_count(bl, cells_count(tr, cells_count(tl, n))))

# --- device: a pixel is one flat loop over its cell's list ---------------------------------------

# What a polygon paints at a pixel: the painter's own rule, with the plane evaluated at the
# pixel directly. (The CPU fills a span by stepping the planes from the span's first pixel, which
# rounds differently; that difference is what this probe measures.)
def ink_at(flat: Bool, ink: Paint.Ink, +x: F32, +y: F32) -> U32:
  match flat ink:
    case True{} Paint.Ink{color, tex, d0, dx, dy, u0, ux, uy, v0, vx, vy, fog}:
      Paint.written(color)
    case False{} Paint.Ink{color, +tex, +d0, +dx, +dy, +u0, +ux, +uy, +v0, +vx, +vy, +fog}:
      Paint.written(Paint.texel_of(F32.add(d0, F32.add(F32.mul(dx, x), F32.mul(dy, y))),
        F32.add(u0, F32.add(F32.mul(ux, x), F32.mul(uy, y))),
        F32.add(v0, F32.add(F32.mul(vx, x), F32.mul(vy, y))), tex, fog, color))

def pixel_paint(covered: Bool, +ink: Paint.Ink, +x: F32, +y: F32) -> U32:
  match covered:
    case True{}:
      ink_at(Paint.ink_flat(ink), ink, x, y)
    case False{}:
      0

def pixel_span(span: Paint.Span, +ink: Paint.Ink, +x: U32, +y: U32) -> U32:
  Paint.Span{sx0, sx1} = span
  pixel_paint(Bool.and(U32.is_le(sx0, x), U32.is_le(x, sx1)), ink, U32.to_f32(x), U32.to_f32(y))

def pixel_inside(boxed: Bool, +ax: F32, +ay: F32, +bx: F32, +by: F32, +cx: F32, +cy: F32,
  +dx: F32, +dy: F32, +ex: F32, +ey: F32, +ink: Paint.Ink, +x: U32, +y: U32, +size: U32) -> U32:
  0

# One polygon over one pixel: nothing once the pixel is painted, else its box and then its span.
def pixel_step(open: Bool, +acc: U32, +ax: F32, +ay: F32, +bx: F32, +by: F32, +cx: F32, +cy: F32,
  +dx: F32, +dy: F32, +ex: F32, +ey: F32, +ink: Paint.Ink, +first: U32, +stop: U32, +left: U32,
  +right: U32, +x: U32, +y: U32, +size: U32) -> U32:
  match open:
    case False{}:
      acc
    case True{}:
      pixel_inside(Bool.and(Bool.and(U32.is_le(first, y), U32.is_lt(y, stop)),
          Bool.and(U32.is_le(left, x), U32.is_le(x, right))),
        ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, x, y, size)

def pixel_go(quads: Paint.Quads, +x: U32, +y: U32, +size: U32, +acc: U32) -> U32:
  match quads:
    case Paint.QNil{}:
      acc
    case Paint.QCons{ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, first, stop, left, right, next}:
      pixel_go(next, x, y, size, pixel_step(U32.is_eq(acc, 0), acc, ax, ay, bx, by, cx, cy, dx, dy,
        ex, ey, ink, first, stop, left, right, x, y, size))

# v2: the reference's leaf. One loop over the cell's list serves a 2x2 block of pixels and carries
# their four colours, so an entry is read once for four pixels and a pixel is not a call.
def go4(quads: Paint.Quads, +x: U32, +y: U32, +size: U32, +x1: U32, +y1: U32, +c0: U32, +c1: U32,
  +c2: U32, +c3: U32) -> Image:
  match quads:
    case Paint.QNil{}:
      Qua{Pix{c0}, Pix{c1}, Pix{c2}, Pix{c3}}
    case Paint.QCons{+ax, +ay, +bx, +by, +cx, +cy, +dx, +dy, +ex, +ey, +ink, +first, +stop, +left, +right, next}:
      go4(next, x, y, size, x1, y1,
        pixel_step(U32.is_eq(c0, 0), c0, ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, first, stop, left, right, x, y, size),
        pixel_step(U32.is_eq(c1, 0), c1, ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, first, stop, left, right, x1, y, size),
        pixel_step(U32.is_eq(c2, 0), c2, ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, first, stop, left, right, x, y1, size),
        pixel_step(U32.is_eq(c3, 0), c3, ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, first, stop, left, right, x1, y1, size))

# The block's colours as the painter shows them: a pixel nothing painted is the sky on its row.
def b2_done(img: Image, +y: U32, +size: U32, +sky: U32, +air: U32) -> Image:
  match img:
    case Qua{Pix{c0}, Pix{c1}, Pix{c2}, Pix{c3}}:
      Qua{Pix{U32.and(c0, 16777215)}, Pix{U32.and(c1, 16777215)}, Pix{U32.and(c2, 16777215)}, Pix{U32.and(c3, 16777215)}}
    case _:
      Pix{0}

def b2(+quads: Paint.Quads, +x: U32, +y: U32, +size: U32, +sky: U32, +air: U32) -> Image:
  b2_done(go4(quads, x, y, size, U32.add(x, 1), U32.add(y, 1), 0, 0, 0, 0), y, size, sky, air)

def b4(+quads: Paint.Quads, +x: U32, +y: U32, +size: U32, +sky: U32, +air: U32) -> Image:
  +x1 = U32.add(x, 2)
  +y1 = U32.add(y, 2)
  Qua{b2(quads, x, y, size, sky, air), b2(quads, x1, y, size, sky, air),
    b2(quads, x, y1, size, sky, air), b2(quads, x1, y1, size, sky, air)}

def b8(+quads: Paint.Quads, +x: U32, +y: U32, +size: U32, +sky: U32, +air: U32) -> Image:
  +x1 = U32.add(x, 4)
  +y1 = U32.add(y, 4)
  Qua{b4(quads, x, y, size, sky, air), b4(quads, x1, y, size, sky, air),
    b4(quads, x, y1, size, sky, air), b4(quads, x1, y1, size, sky, air)}

def b16(+quads: Paint.Quads, +x: U32, +y: U32, +size: U32, +sky: U32, +air: U32) -> Image:
  +x1 = U32.add(x, 8)
  +y1 = U32.add(y, 8)
  Qua{b8(quads, x, y, size, sky, air), b8(quads, x1, y, size, sky, air),
    b8(quads, x, y1, size, sky, air), b8(quads, x1, y1, size, sky, air)}

# The leaf of the fork tree: `d` more levels of forks than the 16-pixel tile, so the leaf is `16 >> d`
# pixels square, straight-line below the fork. The guide aims for one leaf per lane, 16384 of them: a
# 1024x1024 frame is that at 8 pixels (d = 1), and 4096 leaves at 16, which leaves three lanes in four
# idle. Structural matches only: a literal `match` is a tree the device compiles badly.
# The polygons of the cell's list that touch a leaf's square, in the same order: the guide's per-tile
# list, so a leaf walks a handful of polygons it owns and not the cell's, which every leaf of the cell
# would share. The list is built backwards and turned once.
def filter(quads: Paint.Quads, +x0: U32, +y0: U32, +x1: U32, +y1: U32, +acc: Paint.Quads) -> Paint.Quads:
  match quads:
    case Paint.QNil{}:
      acc
    case Paint.QCons{+ax, +ay, +bx, +by, +cx, +cy, +dx, +dy, +ex, +ey, +ink, +first, +stop, +left, +right, next}:
      filter(next, x0, y0, x1, y1, Paint.quads.keep(
        Bool.and(Bool.and(U32.is_le(first, y1), U32.is_gt(stop, y0)),
          Bool.and(U32.is_le(left, x1), U32.is_ge(right, x0))),
        ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, first, stop, left, right, acc))

def own(quads: Paint.Quads, +x: U32, +y: U32, +edge: U32) -> Paint.Quads:
  Paint.quads.rev(filter(quads, x, y, U32.add(x, U32.sub(edge, 1)), U32.add(y, U32.sub(edge, 1)),
    Paint.QNil{}), Paint.QNil{})

def leaf(+d: Nat, +quads: Paint.Quads, +x: U32, +y: U32, +size: U32, +sky: U32, +air: U32) -> Image:
  b8(own(quads, x, y, 8), x, y, size, sky, air)

# A 64-pixel cell down to its leaves: `k` levels of four-way forks, `2 + d` of them.
def cell_fork(+k: Nat, +d: Nat, +quads: Paint.Quads, +x: U32, +y: U32, +size: U32, +sky: U32,
  +air: U32) -> Image:
  match k:
    case 0n:
      leaf(d, quads, x, y, size, sky, air)
    case 1n+e:
      +h = U32.shln(U32.shrn((16 : U32), d), e)
      +x1 = U32.add(x, h)
      +y1 = U32.add(y, h)
      a b c e1 = cell_fork(e, d, quads, x, y, size, sky, air) cell_fork(e, d, quads, x1, y, size, sky, air)
        cell_fork(e, d, quads, x, y1, size, sky, air) cell_fork(e, d, quads, x1, y1, size, sky, air)
      Qua{a, b, c, e1}

# A region of 64 << k: an empty one is its sky, a cell forks to leaves, a node forks.
def frame_node(c: Cells, +k: Nat, +m: Nat, +x: U32, +y: U32, +size: U32, +sky: U32, +air: U32) -> Image:
  match c:
    case CNil{}:
      Paint.image.of(Paint.sky.flat(Nat.add(6n, k), y, size, sky, air))
    case CLeaf{ts}:
      cell_fork(Nat.add(2n, m), m, ts, x, y, size, sky, air)
    case CQua{tl, tr, bl, br}:
      match k:
        case 0n:
          Pix{0}
        case 1n+e:
          +s = U32.shln((64 : U32), e)
          +x1 = U32.add(x, s)
          +y1 = U32.add(y, s)
          a b c d = frame_node(tl, e, m, x, y, size, sky, air) frame_node(tr, e, m, x1, y, size, sky, air)
            frame_node(bl, e, m, x, y1, size, sky, air) frame_node(br, e, m, x1, y1, size, sky, air)
          Qua{a, b, c, d}

# A frame's two stages: the tree waiting to be drawn, and the image drawn from it. They are one
# type because a `def` may only call itself, and the loop has to hand the next stage back to itself.
type Stage is Data:
  Fresh{cells: Cells}
  Shown{image: Image, cells: Cells}

# One bang for the frame; the tree is borrowed and handed back for the host to keep.
def frame_show(+cells: Cells, +root: Nat, +m: Nat, +size: U32, +sky: U32, +air: U32) -> Stage:
  Shown{frame_node!(cells, root, m, 0, 0, size, sky, air), cells}

# --- reading a pixel back out of a quadtree, and comparing two frames ------------------------------

def pixel_in(+log: Nat, image: Image, +x: U32, +y: U32) -> U32:
  match log image:
    case _ Pix{color}:
      color
    case 0n Qua{tl, tr, bl, br}:
      0
    case 1n+e Qua{tl, tr, bl, br}:
      +h = U32.shln((1 : U32), e)
      +mask = U32.sub(h, (1 : U32))
      pixel_in(e, Bool.pick(Image, U32.is_lt(y, h), Bool.pick(Image, U32.is_lt(x, h), tl, tr),
        Bool.pick(Image, U32.is_lt(x, h), bl, br)), U32.and(x, mask), U32.and(y, mask))

def channel(+a: U32, +b: U32, +shift: Nat) -> U32:
  +ca = U32.and(U32.shrn(a, shift), (255 : U32))
  +cb = U32.and(U32.shrn(b, shift), (255 : U32))
  U32.sub(U32.max(ca, cb), U32.min(ca, cb))

def delta(+a: U32, +b: U32) -> U32:
  U32.max(U32.max(channel(a, b, 0n), channel(a, b, 8n)), channel(a, b, 16n))

# Pixels that differ at all, pixels that differ by more than 3 in some channel, the most any one
# does, and the first such pixel.
type Diff is Data:
  Diff{any: U32, large: U32, most: U32, at: U32}

def diff_add(+diff: Diff, +d: U32, +i: U32) -> Diff:
  Diff{any, large, most, at} = diff
  Diff{U32.add(any, Bool.pick(U32, U32.is_gt(d, 0), 1, 0)),
    U32.add(large, Bool.pick(U32, U32.is_gt(d, 3), 1, 0)), U32.max(most, d),
    Bool.pick(U32, Bool.and(U32.is_gt(d, 3), U32.is_eq(large, 0)), i, at)}

def compare_go(+remaining: Nat, +i: U32, +log: Nat, +a: Image, +b: Image, +diff: Diff) -> Diff:
  match remaining:
    case 0n:
      diff
    case 1n+r:
      +size = U32.shln((1 : U32), log)
      +x = U32.mod(i, size)
      +y = U32.div(i, size)
      compare_go(r, U32.add(i, 1), log, a, b,
        diff_add(diff, delta(pixel_in(log, a, x, y), pixel_in(log, b, x, y)), i))

def compare_text(diff: Diff) -> String:
  Diff{any, large, most, at} = diff
  "differ=" ++ U32.show(any) ++ " differ_by_more_than_3=" ++ U32.show(large)
    ++ " most=" ++ U32.show(most) ++ " first_large_at=" ++ U32.show(at)

# --- timing --------------------------------------------------------------------------------------

def phase_line(name: String, +size: U32, +iterations: Nat, started: Nat, finished: Nat,
  +digest: U32) -> String:
  "phase=" ++ name ++ " size=" ++ U32.show(size) ++ " iterations=" ++ Nat.show(iterations)
    ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finished, started)) ++ " digest=" ++ U32.show(digest)

def cpu_go(+remaining: Nat, +scene: Scene, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+r:
      +image = cpu_image(scene)
      +digest : U32 = Voxel.fingerprint(image)
      released : Unit = Image.drop(image)
      cpu_go(r, scene, fold_hash(hash, digest))

def quads_go(+remaining: Nat, +scene: Scene, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+r:
      quads_go(r, scene, fold_hash(hash, quads_len(quads_of(scene), 0)))

def cells_go(+remaining: Nat, +scene: Scene, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+r:
      cells_go(r, scene, fold_hash(hash, cells_count(cells_of(scene), 0)))

# Two steps a frame: the bang follows an `IO.now`, because a bang that follows the host's forks in
# one evaluation runs on the CPU pool (`SHADERS.md`), and then the image is read back.
def device_loop(+fuel: Nat, stage: Stage, +root: Nat, +m: Nat, +size: U32, +sky: U32, +air: U32,
  +hash: U32) -> IO(U32):
  match fuel stage:
    case 0n _:
      IO.pure(U32, hash)
    case 1n+r Fresh{cells}:
      do IO<U32>:
        now : Nat <- IO.now()
        device_loop(r, frame_show(cells, root, m, size, sky, air), root, m, size, sky, air, hash)
    case 1n+r Shown{image, cells}:
      device_loop(r, Fresh{cells}, root, m, size, sky, air, fold_hash(hash, Voxel.fingerprint(image)))

def line_of(+label: String, +name: String, +iterations: Nat, +size: U32, started: Nat, finished: Nat,
  +digest: U32) -> String:
  phase_line(label ++ "_" ++ name, size, iterations, started, finished, digest)

def cpu_phase(+label: String, +iterations: Nat, +scene: Scene) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, cpu_go(iterations, scene, 2166136261))
    consumed : Unit <- IO.print("consume=cpu:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(line_of(label, "cpu_full", iterations, U32.shln((1 : U32), scene_depth(scene)), started, finished, digest))

def cells_phase(+label: String, +iterations: Nat, +scene: Scene) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, cells_go(iterations, scene, 2166136261))
    consumed : Unit <- IO.print("consume=cells:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(line_of(label, "host_quads_and_cells", iterations, U32.shln((1 : U32), scene_depth(scene)), started, finished, digest))

def device_phase(+label: String, +iterations: Nat, +cells: Cells, +scene: Scene, +m: Nat) -> IO(Unit):
  Scene{+groups, +camera, +half, +focal, +size, +depth, +behind, +air, +level, +sky} = scene
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- device_loop(Nat.mul(2n, iterations), Fresh{cells}, Nat.sub(depth, Paint.tile_log()), m, size, sky, air, 2166136261)
    consumed : Unit <- IO.print("consume=device:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(line_of(label, "device_draw", iterations, size, started, finished, digest))

# The frame through the device path, from a scene and its cells.
def show_scene(+cells: Cells, +scene: Scene, +m: Nat) -> Stage:
  Scene{+groups, +camera, +half, +focal, +size, +depth, +behind, +air, +level, +sky} = scene
  frame_show(cells, Nat.sub(depth, Paint.tile_log()), m, size, sky, air)

def compare_scene(+cpu: Image, shown: Stage, +depth: Nat) -> String:
  match shown:
    case Shown{image, cells}:
      compare_text(compare_go(U32.to_nat(U32.shln((1 : U32), Nat.mul(2n, depth))), 0, depth, cpu, image,
        Diff{0, 0, 0, 0}))
    case Fresh{cells}:
      "nothing was drawn"

# One view at one size: the picture compared, then each part timed.
def view(+label: String, +world: Slabs.World, +yaw: F32, +pitch: F32, +depth: Nat, +m: Nat) -> IO(Unit):
  +scene : Scene = scene_of(world, outdoor_pose(yaw, pitch), depth)
  +cells : Cells = cells_of(scene)
  +cpu : Image = cpu_image(scene)
  do IO<Unit>:
    said : Unit <- IO.print(label ++ " polygons=" ++ U32.show(quads_len(quads_of(scene), 0)))
    shown : Stage <- IO.pure(Stage, show_scene(cells, scene, m))
    compared : Unit <- IO.print(label ++ " compare " ++ compare_scene(cpu, shown, depth))
    warm : Unit <- cpu_phase(label, 2n, scene)
    a : Unit <- cpu_phase(label, 10n, scene)
    b : Unit <- cells_phase(label, 10n, scene)
    +again : Cells = cells_of(scene)
    # The first frames on the device load its program and set up its heap: not part of a frame.
    warmed : Unit <- device_phase(label ++ "_warm", 3n, again, scene, m)
    device_phase(label, 10n, again, scene, m)

def main() -> IO(Unit):
  do IO<Unit>:
    +world : Slabs.World = Slabs.world_built(WorldState.empty(), Frame.Home{2048n, 2047n})
    a : Unit <- view("east10_leaf8", world, 1.5708, 0.0, 10n, 1n)
    b : Unit <- view("east8_leaf8", world, 1.5708, 0.0, 8n, 1n)
    IO.print("gpu-probe=done")
