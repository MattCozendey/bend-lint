import Base
import ./face.bend as Face
import ./shade.bend as Shade
import ./voxel.bend as Voxel
import ./paint.bend as Paint
import ./sky.bend as Sky

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "shade: " ++ message)

# Stone up to height 4, and nothing above.
def ground(x: U32, +y: U32, z: U32) -> U32:
  Bool.pick(U32, U32.is_lt(y, 4), 1, 0)

# The ground with a pillar two cells tall standing on it at (8, 8).
def pillar(+x: U32, +y: U32, +z: U32) -> U32:
  Bool.pick(U32, Bool.or(U32.is_lt(y, 4),
      Bool.and(Bool.and(U32.is_eq(x, 8), U32.is_eq(z, 8)), U32.is_lt(y, 6))), 1, 0)

# The ground with a stone roof over it at height 8, and with leaves there instead.
def roofed(x: U32, +y: U32, z: U32) -> U32:
  Bool.pick(U32, Bool.or(U32.is_lt(y, 4), U32.is_eq(y, 8)), 1, 0)

def canopy(x: U32, +y: U32, z: U32) -> U32:
  Bool.pick(U32, U32.is_lt(y, 4), 1, Bool.pick(U32, U32.is_eq(y, 8), 4, 0))

# Sand up to height 4 with a stone pillar on it at (8, 8). Sand is the evenest texture there
# is, so a difference in light across it is the light and not the grain.
def sand_pillar(+x: U32, +y: U32, +z: U32) -> U32:
  Bool.pick(U32, U32.is_lt(y, 4), 6,
    Bool.pick(U32, Bool.and(Bool.and(U32.is_eq(x, 8), U32.is_eq(z, 8)), U32.is_lt(y, 6)), 1, 0))

# A chunk as a list of its cells, built from one of the scenes above.
def scene(id: Nat, +x: U32, +y: U32, +z: U32) -> U32:
  match id:
    case 0n:
      ground(x, y, z)
    case 1n:
      pillar(x, y, z)
    case 2n:
      roofed(x, y, z)
    case 3n:
      canopy(x, y, z)
    case _:
      sand_pillar(x, y, z)

def cells.go(remaining: Nat, +at: U32, +id: Nat) -> List<&2, U32>:
  match remaining:
    case 0n:
      []
    case 1n+rest:
      scene(id, U32.mod(at, 16), U32.div(at, 256), U32.mod(U32.div(at, 16), 16))
        <> cells.go(rest, U32.add(at, 1), id)

def cells(+id: Nat) -> List<&2, U32>:
  cells.go(5120n, 0, id)

# The word of the face at a cell and a side, or 0 when the cell has no such face.
def word_at(faces: List<&2, Face.Face>, +x: U32, +y: U32, +z: U32, +dir: Nat) -> U32:
  match faces:
    case Nil{}:
      0
    case Face.Face{fx, fy, fz, fdir, +word} <> rest:
      Bool.pick(U32, Bool.and(Bool.and(U32.is_eq(fx, x), U32.is_eq(fy, y)),
          Bool.and(U32.is_eq(fz, z), Nat.is_eq(fdir, dir))),
        word, word_at(rest, x, y, z, dir))

def level(+word: U32, +corner: U32) -> U32:
  Shade.level_of(Shade.levels_of(word), corner)

def all_full(+word: U32) -> Bool:
  U32.is_eq(Shade.levels_of(word), 0)

# Under the open sky and away from everything, the top of the ground is fully lit at every
# corner, and the word still names the block.
def open_ground_is_fully_lit() -> IO(Unit):
  do IO<Unit>:
    +faces : List<&2, Face.Face> = Shade.faces_of(cells(0n))
    Unit <- check(U32.is_eq(Shade.block_of(word_at(faces, 5, 3, 5, 1n)), 1),
      "the face's word does not name its block")
    Unit <- check(all_full(word_at(faces, 5, 3, 5, 1n)),
      "open ground is not fully lit")
    check(U32.is_eq(Face.face_total(faces), Face.face_total(Shade.faces_of(cells(0n)))),
      "the same chunk has two face counts")

# A face count is the extraction's: the light adds nothing and drops nothing.
def lighting_keeps_every_face() -> IO(Unit):
  check(U32.is_eq(Face.face_total(Shade.faces_of(cells(1n))),
      Face.face_total(Face.faces_from_layers(Face.padded_layers(cells(1n), 16, 16), 16, 16))),
    "the lit faces are not the extracted faces")

# The ground beside the pillar, at (7, 3, 8): its top's two corners on the pillar's side
# touch the pillar's cell and are darker than the two away from it. Across the top the
# texture runs along x, so the pillar is at `u` = 1: corners 1 and 3.
def a_wall_darkens_the_corners_it_touches() -> IO(Unit):
  do IO<Unit>:
    +word : U32 = word_at(Shade.faces_of(cells(1n)), 7, 3, 8, 1n)
    Unit <- check(U32.is_eq(level(word, 0), 15), "the far corner by a wall is not fully lit")
    Unit <- check(U32.is_eq(level(word, 2), 15), "the other far corner by a wall is not fully lit")
    Unit <- check(U32.is_lt(level(word, 1), 15), "the corner against a wall is not darker")
    check(U32.is_lt(level(word, 3), 15), "the other corner against a wall is not darker")

# The corner where the ground and two walls would meet is the darkest a corner in the open
# gets, and one cell touching is a quarter less light: 15 * 3 / 4, rounded.
def one_filled_cell_takes_a_quarter() -> IO(Unit):
  check(U32.is_eq(level(word_at(Shade.faces_of(cells(1n)), 7, 3, 8, 1n), 1), 11),
    "a corner with one of its four cells filled is not at three quarters")

# The pillar's own side, looking back at open air, is lit at the top and dark at its foot,
# where the ground fills the cells below its lower corners. On a side `v` runs down, so the
# foot is corners 2 and 3 of the lower block.
def a_wall_is_darker_at_its_foot() -> IO(Unit):
  do IO<Unit>:
    +word : U32 = word_at(Shade.faces_of(cells(1n)), 8, 4, 8, 0n)
    Unit <- check(U32.is_eq(level(word, 0), 15), "the top of a wall's side is not fully lit")
    check(U32.is_lt(level(word, 2), 15), "the foot of a wall is not darker than its top")

# Under a stone roof the ground holds the cover's level, under leaves it holds more than
# that, and both hold less than under the sky.
def a_roof_shades_and_leaves_shade_less() -> IO(Unit):
  do IO<Unit>:
    +under_stone : U32 = level(word_at(Shade.faces_of(cells(2n)), 5, 3, 5, 1n), 0)
    +under_leaves : U32 = level(word_at(Shade.faces_of(cells(3n)), 5, 3, 5, 1n), 0)
    Unit <- check(U32.is_eq(under_stone, Shade.cover()), "the ground under a roof is not at the cover's level")
    Unit <- check(U32.is_gt(under_leaves, under_stone), "leaves shade as much as stone")
    check(U32.is_lt(under_leaves, 15), "leaves do not shade")

# The top of the roof itself is in the open.
def the_roof_is_lit_from_above() -> IO(Unit):
  check(all_full(word_at(Shade.faces_of(cells(2n)), 5, 8, 5, 1n)),
    "the top of a roof is not fully lit")

# --- the painter puts the light where the corners are -------------------------------
#
# The levels are worth nothing if the painter lays them on a face the other way round, and
# only a picture can say which way it lays them. This looks straight down on the sand from
# above the pillar, 128 pixels a side: the camera's right is +x and its up is -z, the sand is
# 8 cells below the eye, so a cell is 12 pixels and the pillar's own cell is columns 58 to 69
# of row 63. The cell west of it is columns 46 to 57, and its east edge — the one against the
# pillar — is the dark one.
def brightness(+color: U32) -> U32:
  U32.add(U32.add(U32.and(U32.shrn(color, 16n), 255), U32.and(U32.shrn(color, 8n), 255)), U32.and(color, 255))

type Lit is Type:
  Lit{frame: Array<U32>, sum: U32}

def lit.add(read: Array<U32> & U32, +sum: U32) -> Lit:
  (frame, cell) = read
  Lit{frame, U32.add(sum, brightness(cell))}

# The brightness of `count` pixels of row 63 from column `x`, summed.
def lit.row(count: Nat, +x: U32, state: Lit) -> Lit:
  match count:
    case 0n:
      state
    case 1n+rest:
      Lit{frame, +sum} = state
      lit.row(rest, U32.add(x, 1), lit.add(frame[U32.add(U32.mul(63, 128), x)], sum))

def lit.sum(state: Lit) -> U32:
  Lit{frame, sum} = state
  sum

def from_above() -> Array<U32>:
  Paint.frame_pixels_all(Paint.one_group(Shade.faces_of(cells(4n))),
    Voxel.Camera.look(Voxel.Vec{8.5, 12.0, 8.5}, 0.0, F32.neg(1.5707)), 64.0, 96.0, 128, 7n,
    Paint.QNil{}, Paint.QNil{}, True{}, Sky.day_air(), Sky.full_level())

def the_painter_darkens_the_side_the_wall_is_on() -> IO(Unit):
  do IO<Unit>:
    +by_the_pillar : U32 = lit.sum(lit.row(3n, 54, Lit{from_above(), 0}))
    +away_from_it : U32 = lit.sum(lit.row(3n, 47, Lit{from_above(), 0}))
    +north_side : U32 = lit.sum(lit.row(3n, 35, Lit{from_above(), 0}))
    Unit <- check(U32.is_lt(U32.mul(by_the_pillar, 100), U32.mul(away_from_it, 93)),
      "the sand against the pillar is not darker than the sand a cell's width from it")
    check(U32.is_gt(U32.mul(north_side, 100), U32.mul(away_from_it, 93)),
      "the sand two cells from the pillar is darker than the sand one cell from it")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- open_ground_is_fully_lit()
    Unit <- lighting_keeps_every_face()
    Unit <- a_wall_darkens_the_corners_it_touches()
    Unit <- one_filled_cell_takes_a_quarter()
    Unit <- a_wall_is_darker_at_its_foot()
    Unit <- a_roof_shades_and_leaves_shade_less()
    Unit <- the_roof_is_lit_from_above()
    Unit <- the_painter_darkens_the_side_the_wall_is_on()
    IO.print("shade: 8 checks passed")
