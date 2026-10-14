import Base
import ../world/world_state.bend as WorldState
import ./player.bend as PlayerProbe
import ./voxel.bend as Voxel
import ./frame.bend as Frame
import ./face.bend as Face
import ./paint.bend as Paint
import ./texture.bend as Texture

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, message)

# The painter is held to the walk, on the walk's own terms.
#
# `native/face_test.bend` holds the *walk* against the ray renderer and classifies every pixel
# into `same` / `face_only` / `block_diff` / `only_face` / `only_ray`, limiting three of those
# classes separately at `pixels / 100` and deliberately **not** limiting `face_only`. This file
# holds the *painter* against the walk with the same classes and the same three limits,
# because the walk is what the client used to draw with, the painter is what it draws with
# now, and the walk is a sound reference: `face_test.bend` reports `wrong_block=0` against
# the ray on every frame it measures.
#
#   same          the painter wrote the colour the walk wrote
#   face_only     another face's shade of the walk's own block — a shading difference on the
#                 right block. Counted and printed, not gated, exactly as `face_test.bend`
#                 does not gate it.
#   wrong_block   a different block is showing: a hole in the image. Gated at 1%.
#   spurious      the painter wrote sky where the walk writes ground. Gated at 1%.
#   missing       the painter left sky where the walk writes ground. Gated at 1%, and this
#                 is the class its near-plane rule is expected to produce at the frame
#                 border — which is why the limit is a percentage and not zero.
#
# `face_only` is the honest measure of how much the two renderers differ *visibly*: every
# other class is a wrong pixel, and this one is a right pixel in the wrong shade.

type Tally is Data:
  Tally{size: U32, pixels: U32, same: U32, face_only: U32, wrong_block: U32,
    spurious: U32, missing: U32}

def t_size(+t: Tally) -> U32:
  match t:
    case Tally{size, pixels, same, face_only, wrong_block, spurious, missing}:
      size

def t_pixels(+t: Tally) -> U32:
  match t:
    case Tally{size, pixels, same, face_only, wrong_block, spurious, missing}:
      pixels

def t_same(+t: Tally) -> U32:
  match t:
    case Tally{size, pixels, same, face_only, wrong_block, spurious, missing}:
      same

def t_face_only(+t: Tally) -> U32:
  match t:
    case Tally{size, pixels, same, face_only, wrong_block, spurious, missing}:
      face_only

def t_wrong(+t: Tally) -> U32:
  match t:
    case Tally{size, pixels, same, face_only, wrong_block, spurious, missing}:
      wrong_block

def t_spurious(+t: Tally) -> U32:
  match t:
    case Tally{size, pixels, same, face_only, wrong_block, spurious, missing}:
      spurious

def t_missing(+t: Tally) -> U32:
  match t:
    case Tally{size, pixels, same, face_only, wrong_block, spurious, missing}:
      missing

def line(+t: Tally) -> String:
  "paint_vs_walk size=" ++ U32.show(t_size(t))
    ++ " pixels=" ++ U32.show(t_pixels(t))
    ++ " same=" ++ U32.show(t_same(t))
    ++ " wrong_block=" ++ U32.show(t_wrong(t))
    ++ " spurious=" ++ U32.show(t_spurious(t))
    ++ " missing=" ++ U32.show(t_missing(t))
    ++ " face_only=" ++ U32.show(t_face_only(t)) ++ " (ungated)"

def sky_at(+py: U32, +size: U32) -> U32:
  Voxel.sky_color_at(py, size)

def shade_of(+block: U32, +dir: Nat) -> U32:
  Voxel.shade_color(Voxel.block_color(block), U32.from_nat(dir))

# Does this colour belong to this block at all, on any face?
#
# `Voxel.shade_color` takes its light from `face mod 3`, so a block has **three** distinct
# shades and not six, and asking for the three is three compares rather than a walk over the
# faces. That matters only because a `match` cannot scrutinize a computed value and a
# recursive scan over the six faces needs a helper that calls its caller back, which Bend 2
# has no cycles for — three compares is the shape that compiles.
def is_any_shade(+block: U32, +want: U32) -> Bool:
  Bool.or(Bool.or(U32.is_eq(want, shade_of(block, 0n)), U32.is_eq(want, shade_of(block, 1n))),
    U32.is_eq(want, shade_of(block, 2n)))

# Which class this pixel is, as a number, so one `match` can read it.
#
# The order matters and is the order of the classes above: `same` first because it is the
# overwhelmingly common case, then the one the near-plane rule produces, then the shading
# difference, then the two that cannot both apply.
def classify_code(+block: U32, dir: Nat, +paint: U32, +py: U32, +size: U32) -> Nat:
  +empty = U32.is_eq(block, 0)
  +paint_sky = U32.is_eq(paint, sky_at(py, size))
  +same_shade = Bool.and(Bool.not(empty), U32.is_eq(paint, shade_of(block, dir)))
  +both_sky = Bool.and(empty, paint_sky)
  +dropped = Bool.and(Bool.not(empty), paint_sky)
  +other_face = Bool.and(Bool.not(empty), Bool.and(Bool.not(paint_sky), is_any_shade(block,
    paint)))
  +invented = Bool.and(empty, Bool.not(paint_sky))
  Bool.pick(Nat, same_shade, 0n,
    Bool.pick(Nat, both_sky, 0n,
      Bool.pick(Nat, dropped, 4n,
        Bool.pick(Nat, other_face, 1n, Bool.pick(Nat, invented, 3n, 2n)))))

def classify(code: Nat, same: U32, face_only: U32, wrong_block: U32, spurious: U32,
  missing: U32) -> Tally:
  match code:
    case 1n:
      Tally{0, 0, same, U32.add(face_only, 1), wrong_block, spurious, missing}
    case 2n:
      Tally{0, 0, same, face_only, U32.add(wrong_block, 1), spurious, missing}
    case 3n:
      Tally{0, 0, same, face_only, wrong_block, U32.add(spurious, 1), missing}
    case 4n:
      Tally{0, 0, same, face_only, wrong_block, spurious, U32.add(missing, 1)}
    case _:
      Tally{0, 0, U32.add(same, 1), face_only, wrong_block, spurious, missing}

# The walk's answer at one pixel, as its block and its face. `Face.Best` is `Data`, so it is
# read once here and the two fields this needs are carried out. A `Seen` rather than two
# `U32` and a `Nat`, because a `def` returns one value and a match case cannot bind two.
type Seen is Data:
  Seen{block: U32, dir: Nat}

def seen.of(best: Face.Best) -> Seen:
  Face.Best{block, dir, depth} = best
  Seen{block, dir}

def code_of(seen: Seen, +paint: U32, +py: U32, +size: U32) -> Nat:
  Seen{block, dir} = seen
  classify_code(block, dir, paint, py, size)

# The counters ride along as five arguments and the class is added to each with one compare,
# rather than a `Tally` being built and read back: reading it back needs a helper this def
# calls which then calls this one, and Bend 2 has no cycles. `Face`'s own agreement fold uses
# the same shape for the same reason.
def hit(code: Nat, want: Nat) -> U32:
  Bool.pick(U32, Nat.is_eq(code, want), (1 : U32), 0)

def fold_pixels(count: Nat, +px: U32, +py: U32, +size: U32, +tiles: Face.Tiles,
  read: Array<U32> & U32, same: U32, face_only: U32, wrong_block: U32, spurious: U32,
  missing: U32) -> Tally:
  match count:
    case 0n:
      Tally{size, U32.mul(size, size), same, face_only, wrong_block, spurious, missing}
    case 1n+r:
      (pixels, +paint) = read
      +code = code_of(seen.of(Face.face_at_pixel(tiles, px, py)), paint, py, size)
      +last = U32.is_eq(px, U32.sub(size, 1))
      +next_px = Bool.pick(U32, last, 0, (px + 1 : U32))
      +next_py = Bool.pick(U32, last, (py + 1 : U32), py)
      fold_pixels(r, next_px, next_py, size, tiles,
        pixels[U32.add(U32.mul(next_py, size), next_px)], U32.add(same, hit(code, 0n)),
        U32.add(face_only, hit(code, 1n)), U32.add(wrong_block, hit(code, 2n)),
        U32.add(spurious, hit(code, 3n)), U32.add(missing, hit(code, 4n)))

def tally_of(+faces: List<&2, Face.Face>, +camera: Voxel.Camera, +depth: Nat,
  +size: U32) -> Tally:
  Voxel.Camera{eye, forward, right, up} = camera
  fold_pixels(U32.to_nat(U32.mul(size, size)), 0, 0, size,
    Face.bucket_faces(faces, eye, right, up, forward, Voxel.projection_half(depth),
      F32.mul(1.5, Voxel.projection_half(depth)), size),
    Paint.frame_pixels(faces, camera, Voxel.projection_half(depth),
      F32.mul(1.5, Voxel.projection_half(depth)), size, depth)[0], 0, 0, 0, 0, 0)

# --- the gate ----------------------------------------------------------------
#
# Three limits, split across defs because a `do` block is one bind and one term.
def wrong_message(+tally: Tally, +limit: U32) -> String:
  "the painter shows the wrong block on " ++ U32.show(t_wrong(tally)) ++ " of "
    ++ U32.show(t_pixels(tally)) ++ " pixels at size " ++ U32.show(t_size(tally))
    ++ ", against the " ++ U32.show(limit) ++ " it is held to"

def spurious_message(+tally: Tally, +limit: U32) -> String:
  "the painter painted sky where the walk paints ground on " ++ U32.show(t_spurious(tally))
    ++ " pixels at size " ++ U32.show(t_size(tally)) ++ ", against the " ++ U32.show(limit)

def missing_message(+tally: Tally, +limit: U32) -> String:
  "the painter left sky where the walk paints ground on " ++ U32.show(t_missing(tally))
    ++ " pixels at size " ++ U32.show(t_size(tally)) ++ ", against the " ++ U32.show(limit)

def gate_final(missing_ok: Bool, +text: String) -> IO(Unit):
  check(missing_ok, text)

def gate_missing(+tally: Tally, +limit: U32, wrong_ok: Bool, spurious_ok: Bool) -> IO(Unit):
  do IO<Unit>:
    said : Unit <- check(spurious_ok, spurious_message(tally, limit))
    gate_final(U32.is_le(t_missing(tally), limit), missing_message(tally, limit))

def gate_spurious(+tally: Tally, +limit: U32, wrong_ok: Bool) -> IO(Unit):
  gate_missing(tally, limit, wrong_ok, U32.is_le(t_spurious(tally), limit))

def gate_wrong(+tally: Tally, +limit: U32) -> IO(Unit):
  gate_spurious(tally, limit, U32.is_le(t_wrong(tally), limit))

def gate(+tally: Tally) -> IO(Unit):
  gate_wrong(tally, U32.div(t_pixels(tally), 100))

def gate_line(+label: String, +tally: Tally) -> IO(Unit):
  do IO<Unit>:
    said : Unit <- IO.print(label ++ " " ++ line(tally))
    gate(tally)

# --- the frame does not depend on how it is divided ---------------------------
#
# The client draws in 64-pixel tiles, and the tallies above are read from the frame painted
# as one tile. The two are the same polygons in the same order, dealt differently, so they
# are held to each other exactly rather than to a limit: the same quadtree, node for node,
# which is what `Voxel.fingerprint` folds. A single pixel of difference, or a tile that
# collapsed where the frame did not, fails this.
def whole_digest(+faces: List<&2, Face.Face>, +camera: Voxel.Camera, +depth: Nat,
  +size: U32) -> U32:
  Voxel.fingerprint(Paint.image.of(Paint.tiles_frame_at(faces, camera,
    Voxel.projection_half(depth), F32.mul(1.5, Voxel.projection_half(depth)), size, depth,
    depth)))

def tiles_digest(+faces: List<&2, Face.Face>, +camera: Voxel.Camera, +depth: Nat,
  +size: U32) -> U32:
  Voxel.fingerprint(Paint.image.of(Paint.tiles_frame(faces, camera,
    Voxel.projection_half(depth), F32.mul(1.5, Voxel.projection_half(depth)), size, depth)))

def tiles_at(+label: String, +faces: List<&2, Face.Face>, +camera: Voxel.Camera, +depth: Nat,
  +size: U32) -> IO(Unit):
  check(U32.is_eq(tiles_digest(faces, camera, depth, size),
      whole_digest(faces, camera, depth, size)),
    "the tiled frame is not the one-tile frame on " ++ label
      ++ " at size " ++ U32.show(size))

def gate_at(+label: String, +faces: List<&2, Face.Face>, +camera: Voxel.Camera, +depth: Nat,
  +size: U32) -> IO(Unit):
  do IO<Unit>:
    held : Unit <- gate_line(label, tally_of(faces, camera, depth, size))
    tiles_at(label, faces, camera, depth, size)

# --- a wall the eye is standing against ----------------------------------------
#
# One face, with the eye 0.3 of a cell off its plane and level with its middle, looking along
# it: two of its corners are in front of the eye and two are behind. That is every wall a
# player walks up to. A painter that skips a face with a corner behind the eye draws this
# frame as sky, and the player then walks into a wall the picture says is not there. Cut at
# the near plane, the part in front is a band down the frame's left edge: the far corners
# are 0.5 ahead and 0.3 to the left, which at a focal of 96 is 57.6 pixels left of centre,
# so the band is the six columns from there to the edge, 768 pixels of 16384.
def beside_faces() -> List<&2, Face.Face>:
  [Face.Face{5, 5, 5, 0n, 1}]

def beside_camera() -> Voxel.Camera:
  Voxel.Camera.look(Voxel.Vec{6.3, 5.5, 5.5}, 0.0, 0.0)

def painted.go(count: Nat, +at: U32, +size: U32, read: Array<U32> & U32, +total: U32) -> U32:
  match count:
    case 0n:
      total
    case 1n+r:
      (pixels, +paint) = read
      +sky = U32.is_eq(paint, sky_at(U32.div(at, size), size))
      painted.go(r, U32.add(at, 1), size, pixels[U32.add(at, 1)],
        U32.add(total, Bool.pick(U32, sky, 0, 1)))

def painted(+faces: List<&2, Face.Face>, +camera: Voxel.Camera, +depth: Nat, +size: U32) -> U32:
  painted.go(U32.to_nat(U32.mul(size, size)), 0, size,
    Paint.frame_pixels(faces, camera, Voxel.projection_half(depth),
      F32.mul(1.5, Voxel.projection_half(depth)), size, depth)[0], 0)

def wall_beside_the_eye() -> IO(Unit):
  +covered : U32 = painted(beside_faces(), beside_camera(), 7n, 128)
  do IO<Unit>:
    said : Unit <- IO.print("beside painted=" ++ U32.show(covered) ++ " of 16384")
    check(U32.is_ge(covered, 700),
      "a face with corners behind the eye was not drawn: the wall beside the camera is sky")

# --- a texture lies on its face ------------------------------------------------
#
# One stone face, square on to an eye two cells in front of its middle. At a focal of 96 the
# face is 48 pixels across, from pixel 39.5 to 87.5, so a texel is three pixels and the
# pixel a hair inside each corner sees that corner's texel: (0, 0) at the top left, (15, 15)
# at the bottom right, and (8, 8) just past the middle. A texture that slid, flipped or
# stretched would put another texel there.
def facing_faces() -> List<&2, Face.Face>:
  [Face.Face{5, 5, 5, 2n, 1}]

def facing_camera() -> Voxel.Camera:
  Voxel.Camera.look(Voxel.Vec{5.5, 5.5, 8.0}, 0.0, 0.0)

def pixel_of(read: Array<U32> & U32) -> U32:
  (pixels, value) = read
  value

def textured_at(+x: U32, +y: U32) -> U32:
  pixel_of(Paint.frame_pixels_with(facing_faces(), facing_camera(), Voxel.projection_half(7n),
    F32.mul(1.5, Voxel.projection_half(7n)), 128, 7n, Paint.QNil{},
    True{})[U32.add(U32.mul(y, 128), x)])

def texture_lies_on_the_face() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(textured_at(40, 40), Texture.texel(1, 2, 0, 0)),
      "the face's top left pixel is not its top left texel")
    Unit <- check(U32.is_eq(textured_at(87, 87), Texture.texel(1, 2, 15, 15)),
      "the face's bottom right pixel is not its bottom right texel")
    Unit <- check(U32.is_eq(textured_at(64, 64), Texture.texel(1, 2, 8, 8)),
      "the face's middle pixel is not its middle texel")
    check(U32.is_eq(textured_at(87, 40), Texture.texel(1, 2, 15, 0)),
      "the face's top right pixel is not its top right texel")

# A textured frame covers exactly what the flat frame covers: the texture changes what a
# pixel is painted with and never whether it is painted.
def painted_with(+textured: Bool, +faces: List<&2, Face.Face>, +camera: Voxel.Camera) -> U32:
  painted.go(16384n, 0, 128, Paint.frame_pixels_with(faces, camera, Voxel.projection_half(7n),
    F32.mul(1.5, Voxel.projection_half(7n)), 128, 7n, Paint.QNil{}, textured)[0], 0)

# --- the scene and the cameras -----------------------------------------------
#
# The chunk the client spawns on, so the numbers here are the numbers the client draws. The
# cameras are the ones the investigation gate uses: `spawn` is where the client stands and
# the one the resolution table is measured at; `down` looks steeply at the ground where
# visible faces barely overlap; `level` looks across the village where they overlap heavily
# and where 932 of the 1654 faces straddle the eye; `inside` puts the eye among the blocks.
def scene_faces() -> List<&2, Face.Face>:
  Face.faces_from_chunk(WorldState.chunk(Frame.seed(), Frame.chunk_x(), Frame.chunk_z(),
    WorldState.empty()))

def camera_of_pose(pose: Frame.Pose) -> Voxel.Camera:
  Frame.Pose{eye, yaw, pitch} = pose
  Voxel.Camera.look(eye, yaw, pitch)

def spawn_camera() -> Voxel.Camera:
  camera_of_pose(Frame.pose(PlayerProbe.create_player(25n, 25n, 9n), Frame.origin_x(),
    Frame.origin_z()))

def level_camera() -> Voxel.Camera:
  Voxel.Camera.look(Voxel.Vec{9.5, 10.67, 9.5}, 3.1415927, 0.0)

def down_camera() -> Voxel.Camera:
  Voxel.Camera.look(Voxel.Vec{9.5, 14.0, 9.5}, 0.7853982, F32.neg(1.2))

def inside_camera() -> Voxel.Camera:
  Voxel.Camera.look(Voxel.Vec{9.5, 9.2, 9.5}, 0.7853982, 0.4)

def texture_covers_the_same_pixels() -> IO(Unit):
  check(U32.is_eq(painted_with(True{}, scene_faces(), spawn_camera()),
      painted_with(False{}, scene_faces(), spawn_camera())),
    "the textured frame does not cover the pixels the flat frame covers")

def frames() -> IO(Unit):
  do IO<Unit>:
    +faces : List<&2, Face.Face> = scene_faces()
    beside : Unit <- wall_beside_the_eye()
    lies : Unit <- texture_lies_on_the_face()
    covers : Unit <- texture_covers_the_same_pixels()
    IO.print("faces=" ++ U32.show(Face.face_total(faces)))
    a : Unit <- gate_at("spawn", faces, spawn_camera(), 7n, 128)
    b : Unit <- gate_at("level", faces, level_camera(), 7n, 128)
    c : Unit <- gate_at("down", faces, down_camera(), 7n, 128)
    d : Unit <- gate_at("inside", faces, inside_camera(), 7n, 128)
    e : Unit <- gate_at("spawn", faces, spawn_camera(), 8n, 256)
    f : Unit <- gate_at("level", faces, level_camera(), 8n, 256)
    g : Unit <- gate_at("spawn", faces, spawn_camera(), 9n, 512)
    h : Unit <- gate_at("down", faces, down_camera(), 9n, 512)
    # 1024 is held to the one-tile frame only: the walk it would be tallied against is a ray
    # per pixel over a million pixels.
    i : Unit <- tiles_at("spawn", faces, spawn_camera(), 10n, 1024)
    j : Unit <- tiles_at("level", faces, level_camera(), 10n, 1024)
    IO.print("paint_probe=pass gate=pixels/100 wrong_block,spurious,missing tiles=whole")

def main() -> IO(Unit):
  frames()
