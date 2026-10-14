import Base
import ./voxel.bend as Voxel

# The blocks' surfaces: one colour per texel of a 16x16 face, as a rule and not a picture.
#
# The browser paints its materials into an atlas and samples it on the GPU. The native
# client has no atlas to sample: a tile of the painter owns its own array and nothing is
# shared between tiles, so a texel is computed where it is needed, from the block, the side
# of the block and the texel's place on the face. Everything is whole-number arithmetic on
# the block's base colour from `Voxel.block_color`, so a texture is that colour with
# structure in it and a block still reads as the colour it always was from a distance.
#
# `texel` answers the lit colour: the side's light is folded into the same multiply the
# texture's own shading uses, so a pixel costs one scale and not two.

# A well-mixed word from a texel's place and a salt. It only has to look unordered at
# sixteen texels a side.
def mix(+a: U32, +b: U32, +salt: U32) -> U32:
  +h = U32.xor(U32.xor(U32.mul(a, 73856093), U32.mul(b, 19349663)), U32.mul(salt, 83492791))
  +i = U32.mul(U32.xor(h, U32.shrn(h, 13n)), 1274126177)
  U32.xor(i, U32.shrn(i, 16n))

# A colour scaled by `factor` over 256, each channel held at 255.
def scaled(+color: U32, +factor: U32) -> U32:
  +r = U32.min(U32.shrn(U32.mul(U32.and(U32.shrn(color, 16n), 255), factor), 8n), 255)
  +g = U32.min(U32.shrn(U32.mul(U32.and(U32.shrn(color, 8n), 255), factor), 8n), 255)
  +b = U32.min(U32.shrn(U32.mul(U32.and(color, 255), factor), 8n), 255)
  U32.or(U32.shln(r, 16n), U32.or(U32.shln(g, 8n), b))

# The light a side takes, over 256: `Voxel.shade_color`'s 100, 72 and 84 percent for the
# sides that face along y, x and z.
def light(+dir: U32) -> U32:
  +axis = U32.mod(dir, 3)
  Bool.pick(U32, U32.is_eq(axis, 1), 256, Bool.pick(U32, U32.is_eq(axis, 0), 184, 215))

# A grain: the factor moved up or down by up to `spread` over 256, by the texel's own word.
def grain(+tx: U32, +ty: U32, +salt: U32, +spread: U32) -> U32:
  U32.sub(U32.add(256, U32.mod(mix(tx, ty, salt), U32.add(U32.mul(spread, 2), 1))), spread)

def speckled(+color: U32, +tx: U32, +ty: U32, +salt: U32, +spread: U32, +lit: U32) -> U32:
  scaled(color, U32.shrn(U32.mul(grain(tx, ty, salt, spread), lit), 8n))

# --- the materials -------------------------------------------------------------

# Stone: a coarse two-texel mottle under a fine grain, so it reads as rock and not as noise.
def stone(+color: U32, +tx: U32, +ty: U32, +lit: U32) -> U32:
  scaled(color, U32.shrn(U32.mul(U32.shrn(U32.mul(grain(U32.shrn(tx, 1n), U32.shrn(ty, 1n), 11, 22),
    grain(tx, ty, 12, 10)), 8n), lit), 8n))

# Grass from above is green grain. From the side it is dirt under a ragged green lip two to
# four texels deep, and from below it is dirt.
def grass_side(+tx: U32, +ty: U32, +lit: U32) -> U32:
  Bool.pick(U32, U32.is_lt(ty, U32.add(2, U32.mod(mix(tx, 0, 31), 3))),
    speckled(Voxel.block_color(3), tx, ty, 32, 26, lit),
    speckled(Voxel.block_color(2), tx, ty, 21, 22, lit))

def grass(+dir: U32, +tx: U32, +ty: U32, +lit: U32) -> U32:
  Bool.pick(U32, U32.is_eq(dir, 1), speckled(Voxel.block_color(3), tx, ty, 32, 30, lit),
    Bool.pick(U32, U32.is_eq(dir, 4), speckled(Voxel.block_color(2), tx, ty, 21, 22, lit),
      grass_side(tx, ty, lit)))

# A trunk's bark runs in vertical streaks, so its grain is by column; its cut ends are
# pale rings around the middle.
def ring(+tx: U32, +ty: U32) -> U32:
  +dx = Bool.pick(U32, U32.is_lt(tx, 8), U32.sub(7, tx), U32.sub(tx, 8))
  +dy = Bool.pick(U32, U32.is_lt(ty, 8), U32.sub(7, ty), U32.sub(ty, 8))
  U32.max(dx, dy)

def wood(+dir: U32, +tx: U32, +ty: U32, +lit: U32) -> U32:
  Bool.pick(U32, U32.is_eq(U32.mod(dir, 3), 1),
    scaled(Voxel.rgb(184, 137, 90), U32.shrn(U32.mul(
      Bool.pick(U32, U32.is_eq(U32.mod(ring(tx, ty), 2), 0), 256, 208), lit), 8n)),
    scaled(Voxel.block_color(5), U32.shrn(U32.mul(U32.shrn(U32.mul(grain(tx, 0, 51, 40),
      grain(tx, ty, 52, 12)), 8n), lit), 8n)))

# Leaves are a strong grain with dark gaps, which is what makes a canopy read as foliage.
def leaves(+tx: U32, +ty: U32, +lit: U32) -> U32:
  Bool.pick(U32, U32.is_lt(U32.mod(mix(tx, ty, 41), 256), 46),
    scaled(Voxel.block_color(4), U32.shrn(U32.mul(150, lit), 8n)),
    speckled(Voxel.block_color(4), tx, ty, 42, 44, lit))

# An ore is stone with flecks of its own colour, in clumps two texels wide.
def ore(+block: U32, +tx: U32, +ty: U32, +lit: U32) -> U32:
  Bool.pick(U32, U32.is_lt(U32.mod(mix(U32.shrn(tx, 1n), U32.shrn(ty, 1n), U32.add(80, block)), 256), 58),
    speckled(Bool.pick(U32, U32.is_eq(block, 8), Voxel.rgb(34, 34, 38),
      Bool.pick(U32, U32.is_eq(block, 9), Voxel.rgb(206, 160, 122), Voxel.rgb(96, 224, 216))),
      tx, ty, 81, 16, lit),
    stone(Voxel.block_color(1), tx, ty, lit))

# Cobblestone: stones four texels across with dark joints between them, offset row to row.
def cobble(+tx: U32, +ty: U32, +lit: U32) -> U32:
  +shift = U32.mul(U32.mod(U32.shrn(ty, 2n), 2), 2)
  +joint = Bool.or(U32.is_eq(U32.mod(ty, 4), 0), U32.is_eq(U32.mod(U32.add(tx, shift), 4), 0))
  Bool.pick(U32, joint, scaled(Voxel.block_color(22), U32.shrn(U32.mul(150, lit), 8n)),
    stone(Voxel.block_color(22), tx, ty, lit))

# A made block — a table, a chest, a furnace, a door, a bed — is its colour inside a darker
# one-texel frame, with a second line across the middle.
def framed(+color: U32, +tx: U32, +ty: U32, +salt: U32, +lit: U32) -> U32:
  +edge = Bool.or(Bool.or(U32.is_eq(tx, 0), U32.is_eq(tx, 15)),
    Bool.or(U32.is_eq(ty, 0), U32.is_eq(ty, 15)))
  +bar = Bool.or(U32.is_eq(ty, 7), U32.is_eq(ty, 8))
  Bool.pick(U32, Bool.or(edge, bar), scaled(color, U32.shrn(U32.mul(160, lit), 8n)),
    speckled(color, tx, ty, salt, 14, lit))

# Glass is a pale frame around a clear pane with one streak of light across it.
def glass(+tx: U32, +ty: U32, +lit: U32) -> U32:
  +edge = Bool.or(Bool.or(U32.is_eq(tx, 0), U32.is_eq(tx, 15)),
    Bool.or(U32.is_eq(ty, 0), U32.is_eq(ty, 15)))
  +streak = Bool.and(U32.is_eq(U32.add(tx, ty), 9), U32.is_lt(tx, 8))
  Bool.pick(U32, Bool.or(edge, streak), scaled(Voxel.rgb(232, 244, 248), lit),
    scaled(Voxel.block_color(25), lit))

# Water and lava move too little at sixteen texels to need more than a slow ripple.
def liquid(+color: U32, +tx: U32, +ty: U32, +lit: U32) -> U32:
  scaled(color, U32.shrn(U32.mul(grain(U32.shrn(tx, 1n), ty, 71, 14), lit), 8n))

def material(block: U32, +dir: U32, +tx: U32, +ty: U32, +lit: U32) -> U32:
  match block:
    case 1:
      stone(Voxel.block_color(1), tx, ty, lit)
    case 2:
      speckled(Voxel.block_color(2), tx, ty, 21, 22, lit)
    case 3:
      grass(dir, tx, ty, lit)
    case 4:
      leaves(tx, ty, lit)
    case 5:
      wood(dir, tx, ty, lit)
    case 6:
      speckled(Voxel.block_color(6), tx, ty, 61, 12, lit)
    case 7:
      liquid(Voxel.block_color(7), tx, ty, lit)
    case 8:
      ore(8, tx, ty, lit)
    case 9:
      ore(9, tx, ty, lit)
    case 10:
      ore(10, tx, ty, lit)
    case 11:
      framed(Voxel.block_color(11), tx, ty, 111, lit)
    case 13:
      framed(Voxel.block_color(13), tx, ty, 113, lit)
    case 14:
      framed(Voxel.block_color(14), tx, ty, 114, lit)
    case 20:
      speckled(Voxel.block_color(20), tx, ty, 120, 18, lit)
    case 21:
      liquid(Voxel.block_color(21), tx, ty, lit)
    case 22:
      cobble(tx, ty, lit)
    case 23:
      stone(Voxel.block_color(23), tx, ty, lit)
    case 25:
      glass(tx, ty, lit)
    case 26:
      framed(Voxel.block_color(26), tx, ty, 126, lit)
    case 27:
      framed(Voxel.block_color(27), tx, ty, 127, lit)
    case _:
      speckled(Voxel.block_color(block), tx, ty, 99, 16, lit)

# The lit colour of texel (`tx`, `ty`) on side `dir` of `block`, both in 0..15 with `ty`
# counted down the face.
def texel(+block: U32, +dir: U32, +tx: U32, +ty: U32) -> U32:
  material(block, dir, tx, ty, light(dir))

# --- the light a face's corners take ---------------------------------------------
#
# `levels` is four numbers of four bits, one per corner of the face in the texture's own
# order — across then down — each how far that corner is below full light, as
# `native/shade.bend` works them out. A texel takes the four in proportion to how near it is
# to each corner, so the light runs smoothly across the face and meets the next face's at
# the edge they share.
#
# A corner fully dark keeps a little over a quarter of the light, so the darkest crease still
# reads as its material.
def corner_dark(+levels: U32, +tx: U32, +ty: U32) -> U32:
  +right = U32.add(U32.mul(tx, 2), 1)
  +down = U32.add(U32.mul(ty, 2), 1)
  +left = U32.sub(32, right)
  +up = U32.sub(32, down)
  U32.add(
    U32.add(U32.mul(U32.mul(U32.and(levels, 15), left), up),
      U32.mul(U32.mul(U32.and(U32.shrn(levels, 4n), 15), right), up)),
    U32.add(U32.mul(U32.mul(U32.and(U32.shrn(levels, 8n), 15), left), down),
      U32.mul(U32.mul(U32.and(U32.shrn(levels, 12n), 15), right), down)))

def corner_light.at(full: Bool, +levels: U32, +tx: U32, +ty: U32) -> U32:
  match full:
    case True{}:
      256
    case False{}:
      U32.sub(256, U32.shrn(U32.mul(corner_dark(levels, tx, ty), 99), 13n))

# The light at a texel over 256. A face with every corner fully lit is most faces, so that
# case does no arithmetic.
def corner_light(+levels: U32, +tx: U32, +ty: U32) -> U32:
  corner_light.at(U32.is_eq(levels, 0), levels, tx, ty)

# `texel` under the corner levels of its face and at an hour: `level` is how bright the hour
# is, 0 to 31, and 31 is full day. With every corner fully lit at full day it is `texel`.
def texel_lit(+block: U32, +dir: U32, +tx: U32, +ty: U32, +levels: U32, level: U32) -> U32:
  material(block, dir, tx, ty,
    U32.shrn(U32.mul(U32.shrn(U32.mul(light(dir), corner_light(levels, tx, ty)), 8n),
      U32.mul(U32.add(level, 1), 8)), 8n))
