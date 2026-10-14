import Base
import ../world/light.bend as Light
import ./face.bend as Face

# Shade: the light each corner of a face takes, worked out once when a chunk's faces are.
#
# The painter gives a face one brightness per side, so a wall, the ground under a tree and
# the back of a cave all read as the same flat colour. What makes a block world read as
# solid is two things a face cannot know by itself: whether the sky reaches the cell in
# front of it, and which of the cells around each of its corners are filled. Both are
# questions about the chunk's blocks and neither changes with the camera, so they are asked
# here, once per chunk, and travel with the face.
#
# ## The cells
#
# `sky` gives every cell of the chunk a level. A filled cell is 0. An open one holds what
# the sky sends down its column: 15 under open sky, less under leaves and through water,
# and `cover()` under anything solid. What lets light through is `Light.transparent_block`,
# which is the world's own answer, so the renderer and the light rule agree on what a wall
# is. Leaves are the one difference: they fill their cell and still let some sky by.
#
# ## The corners
#
# A corner of a face touches four cells of the layer in front of the face: the one the face
# looks into and the three around the corner. Its level is their mean, with a filled cell
# counting as nothing — and the far one counting as nothing when both near ones are filled,
# because no light gets round a closed corner. That one rule is both the dark crease where
# a wall meets the ground and the soft edge of a shadow.
#
# A cell outside the chunk is not known here: a slab is built from its own chunk and nothing
# else (`native/client.bend`). It is read as the cell the face looks into, which leaves the
# corner neither darker nor lighter for it.
#
# ## The word
#
# The four levels ride in the face's `block` above the block id, four bits each, as how far
# each is **below** full light. So a face with no levels is a fully lit face, and everything
# that reads a plain block id keeps working on faces this module never saw.

type Axes is Data:
  Axes{nx: U32, ny: U32, nz: U32, ux: U32, uy: U32, uz: U32, wx: U32, wy: U32, wz: U32}

# One step back along an axis, as a word that wraps.
def back() -> U32:
  4294967295

# A side's outward step, and the two ways the painter's texture runs on it: `u` across and
# `w` down. `Paint.ink.turned` is the same table: a face across x runs along z and down y,
# one across y along x and along z, one across z along x and down y.
def axes(dir: Nat) -> Axes:
  match dir:
    case 0n:
      Axes{1, 0, 0, 0, 0, 1, 0, back(), 0}
    case 1n:
      Axes{0, 1, 0, 1, 0, 0, 0, 0, 1}
    case 2n:
      Axes{0, 0, 1, 1, 0, 0, 0, back(), 0}
    case 3n:
      Axes{back(), 0, 0, 0, 0, 1, 0, back(), 0}
    case 4n:
      Axes{0, back(), 0, 1, 0, 0, 0, 0, 1}
    case _:
      Axes{0, 0, back(), 1, 0, 0, 0, back(), 0}

def index(+x: U32, +y: U32, +z: U32) -> U32:
  U32.add(U32.add(x, U32.mul(z, 16)), U32.mul(y, 256))

def inside(+x: U32, +y: U32, +z: U32) -> Bool:
  Bool.and(Bool.and(U32.is_lt(x, 16), U32.is_lt(z, 16)), U32.is_lt(y, 20))

# --- the cells -------------------------------------------------------------------

def full() -> U32:
  15

# What an open cell under a solid one holds.
def cover() -> U32:
  5

# A block as what it does to the sky: 0 fills its cell and stops it, 1 is open, 2 is leaves
# and 3 is water.
def kind(+block: U32) -> U32:
  Bool.pick(U32, U32.is_eq(block, 4), 2,
    Bool.pick(U32, U32.is_eq(block, 7), 3,
      Bool.pick(U32, Light.transparent_block(block), 1, 0)))

def kinds(blocks: List<&2, U32>, +at: U32, cells: Array<U32>) -> Array<U32>:
  match blocks:
    case Nil{}:
      cells
    case +block <> rest:
      kinds(rest, U32.add(at, 1), cells[at] <- kind(block))

def sat_sub(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_lt(a, b), 0, U32.sub(a, b))

# What a cell holds, by its kind and the level that reached it.
def held(+kind: U32, +level: U32) -> U32:
  Bool.pick(U32, Bool.or(U32.is_eq(kind, 0), U32.is_eq(kind, 2)), 0, level)

# The level that goes on down past a cell. Nothing a cell does raises it.
def passed(+kind: U32, +level: U32) -> U32:
  Bool.pick(U32, U32.is_eq(kind, 0), U32.min(level, cover()),
    Bool.pick(U32, U32.is_eq(kind, 2), U32.min(level, U32.max(sat_sub(level, 4), 7)),
      Bool.pick(U32, U32.is_eq(kind, 3), U32.min(level, U32.max(sat_sub(level, 1), 6)), level)))

# One column, top to bottom. `read` is the cell at height `remaining - 1` and what it holds,
# which is its kind; it is written with its level and the cell below is read.
def column(+remaining: Nat, +offset: U32, +level: U32, read: Array<U32> & U32) -> Array<U32>:
  match remaining:
    case 0n:
      (cells, kind) = read
      cells
    case 1n+below:
      (cells, +kind) = read
      +at = U32.add(offset, U32.mul(U32.from_nat(below), 256))
      column(below, offset, passed(kind, level), (cells[at] <- held(kind, level))[U32.sub(at, 256)])

def columns(remaining: Nat, +offset: U32, cells: Array<U32>) -> Array<U32>:
  match remaining:
    case 0n:
      cells
    case 1n+rest:
      columns(rest, U32.add(offset, 1), column(20n, offset, full(), cells[U32.add(offset, 4864)]))

# Every cell of a chunk as the level it holds.
def sky(blocks: List<&2, U32>) -> Array<U32>:
  columns(256n, 0, kinds(blocks, 0, Array.new(U32, 14n, 1)))

# --- the corners -----------------------------------------------------------------

def at.if(known: Bool, cells: Array<U32>, +at: U32, +unknown: U32) -> Array<U32> & U32:
  match known:
    case True{}:
      Array.get(U32, cells, at)
    case False{}:
      (cells, unknown)

# What a cell holds, or `unknown` for a cell outside the chunk.
def at(cells: Array<U32>, +x: U32, +y: U32, +z: U32, +unknown: U32) -> Array<U32> & U32:
  at.if(inside(x, y, z), cells, index(x, y, z), unknown)

# A corner's level from the cell the face looks into, the two beside it and the far one.
def corner_level(+centre: U32, +beside: U32, +below: U32, +far: U32) -> U32:
  +closed = Bool.and(U32.is_eq(beside, 0), U32.is_eq(below, 0))
  U32.shrn(U32.add(U32.add(U32.add(centre, beside), U32.add(below, Bool.pick(U32, closed, 0, far))), 2), 2n)

def corner.far(read: Array<U32> & U32, +word: U32, +shift: Nat, +centre: U32, +beside: U32,
  +below: U32) -> Array<U32> & U32:
  (cells, far) = read
  (cells, U32.or(word, U32.shln(U32.sub(full(), corner_level(centre, beside, below, far)), shift)))

def corner.below(read: Array<U32> & U32, +word: U32, +shift: Nat, +centre: U32, +beside: U32,
  +fx: U32, +fy: U32, +fz: U32) -> Array<U32> & U32:
  (cells, +below) = read
  corner.far(at(cells, fx, fy, fz, centre), word, shift, centre, beside, below)

def corner.beside(read: Array<U32> & U32, +word: U32, +shift: Nat, +centre: U32,
  +bx: U32, +by: U32, +bz: U32, +fx: U32, +fy: U32, +fz: U32) -> Array<U32> & U32:
  (cells, +beside) = read
  corner.below(at(cells, bx, by, bz, centre), word, shift, centre, beside, fx, fy, fz)

# One corner of the face that looks into (`ax`, `ay`, `az`): the cells one step along `u` and
# one along `w` from it, and the one that is both. `state` is the cells and the face's word
# so far, and the corner's level goes into the word at `shift`.
def corner(state: Array<U32> & U32, +shift: Nat, +centre: U32, +ax: U32, +ay: U32, +az: U32,
  +ux: U32, +uy: U32, +uz: U32, +wx: U32, +wy: U32, +wz: U32) -> Array<U32> & U32:
  (cells, word) = state
  corner.beside(at(cells, U32.add(ax, ux), U32.add(ay, uy), U32.add(az, uz), centre), word,
    shift, centre, U32.add(ax, wx), U32.add(ay, wy), U32.add(az, wz),
    U32.add(U32.add(ax, ux), wx), U32.add(U32.add(ay, uy), wy), U32.add(U32.add(az, uz), wz))

def neg(+step: U32) -> U32:
  U32.sub(0, step)

# The four corners in the order the painter's texture names them: across then down, so the
# first is where `u` and `v` are both 0 and the last where both are 1.
def side.corners(read: Array<U32> & U32, +block: U32, +ax: U32, +ay: U32, +az: U32,
  axes: Axes) -> Array<U32> & U32:
  (cells, +centre) = read
  Axes{nx, ny, nz, +ux, +uy, +uz, +wx, +wy, +wz} = axes
  corner(corner(corner(corner((cells, block),
          8n, centre, ax, ay, az, neg(ux), neg(uy), neg(uz), neg(wx), neg(wy), neg(wz)),
        12n, centre, ax, ay, az, ux, uy, uz, neg(wx), neg(wy), neg(wz)),
      16n, centre, ax, ay, az, neg(ux), neg(uy), neg(uz), wx, wy, wz),
    20n, centre, ax, ay, az, ux, uy, uz, wx, wy, wz)

def side.into(cells: Array<U32>, +block: U32, +x: U32, +y: U32, +z: U32, +axes: Axes) ->
  Array<U32> & U32:
  Axes{+nx, +ny, +nz, ux, uy, uz, wx, wy, wz} = axes
  side.corners(at(cells, U32.add(x, nx), U32.add(y, ny), U32.add(z, nz), full()), block,
    U32.add(x, nx), U32.add(y, ny), U32.add(z, nz), axes)

# A face's block with its four corner levels above it.
def side(cells: Array<U32>, +x: U32, +y: U32, +z: U32, +dir: Nat, +block: U32) ->
  Array<U32> & U32:
  side.into(cells, block, x, y, z, axes(dir))

# Every face with its levels. `state` is the cells and the word of the face before, whose
# place is `px`, `py`, `pz` and `pdir`: a face is put out one step after it is worked out,
# so the cells have one owner all the way down the list.
def lit.go(faces: List<&2, Face.Face>, state: Array<U32> & U32, +px: U32, +py: U32, +pz: U32,
  +pdir: Nat, acc: List<&2, Face.Face>) -> List<&2, Face.Face>:
  match faces:
    case Nil{}:
      (cells, word) = state
      Face.Face{px, py, pz, pdir, word} <> acc
    case Face.Face{+x, +y, +z, +dir, +block} <> rest:
      (cells, word) = state
      lit.go(rest, side(cells, x, y, z, dir, block), x, y, z, dir,
        Face.Face{px, py, pz, pdir, word} <> acc)

def lit(faces: List<&2, Face.Face>, cells: Array<U32>) -> List<&2, Face.Face>:
  match faces:
    case Nil{}:
      []
    case Face.Face{+x, +y, +z, +dir, +block} <> rest:
      lit.go(rest, side(cells, x, y, z, dir, block), x, y, z, dir, [])

def faces_of(+blocks: List<&2, U32>) -> List<&2, Face.Face>:
  lit(Face.faces_from_layers(Face.padded_layers(blocks, Face.extent_x(1n), Face.extent_z(1n)),
    Face.extent_x(1n), Face.extent_z(1n)), sky(blocks))

# A chunk's exposed faces, each with the light its corners take.
def faces_from_chunk(chunk: Array<U32>) -> List<&2, Face.Face>:
  faces_of(Face.share_blocks(Array.to_list(~U32, chunk)))

# --- reading the word ------------------------------------------------------------

def block_of(+word: U32) -> U32:
  U32.and(word, 255)

# The four levels as the painter carries them: sixteen bits, each four how far below full
# light a corner is.
def levels_of(+word: U32) -> U32:
  U32.and(U32.shrn(word, 8n), 65535)

# One corner's level out of the sixteen bits: `corner` is 0 to 3 in the texture's order.
def level_of(+levels: U32, +corner: U32) -> U32:
  U32.sub(full(), U32.and(U32.shrn(levels, U32.to_nat(U32.mul(corner, 4))), 15))
