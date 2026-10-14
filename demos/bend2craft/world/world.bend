import Base
import ./structures.bend as Structures

# Block IDs: 0 air, 1 stone, 2 dirt, 3 grass, 4 leaves, 5 wood, 6 sand, 7 water,
# 8 coal ore, 9 iron ore, 10 diamond ore, 11 furnace, 12 torch, 13 bed,
# 14 closed door, 15 open door, 16-19 wheat growth stages, 20 farmland, 21 lava,
# 22 cobblestone, 23 obsidian, 25 glass, 26 chest, 27 crafting table.
# The redstone blocks continue that contract from 28; see world/redstone.bend,
# which owns their ids and the single ordered list `block_ids` that keeps the
# browser's BLOCK_INFO in step.

# The blocks that hold something, named once so that a client and a room do not each keep
# their own number: `world/multiplayer.bend` asks them what a dug cell held, and the native
# client asks them which block opens a screen.
def furnace_block() -> U32:
  11

def chest_block() -> U32:
  26

def crafting_table_block() -> U32:
  27

def default_seed() -> Nat:
  1337n

def chunk_size() -> Nat:
  16n

def width() -> Nat:
  48n

def depth() -> Nat:
  48n

def max_y() -> Nat:
  64n

def sea_level() -> Nat:
  7n

# Negative world coordinates are stored at negative_origin() + x (see
# web/world-coordinates.js, which pins the same constant). 45 * 2^21 is a
# multiple of every terrain period, so the world continues seamlessly below 0.
def negative_origin() -> Nat:
  94371840n

# The stored cell of a signed world position: floor(value), with a negative
# cell moved to negative_origin() + cell. Entity queries against the generated
# world go through this, so a mob at x < 0 reads its own column instead of 0.
def cell(+value: F32) -> Nat:
  +floor = F32.floor(value)
  Bool.pick(Nat, F32.is_lt(floor, 0.0),
    Nat.sub(negative_origin(), F32.to_nat(F32.neg(floor))),
    F32.to_nat(floor))

def plains_limit() -> Nat:
  96n

def same(+a: Nat, +b: Nat) -> Bool:
  Nat.is_eq(a, b)

def near(+a: Nat, +b: Nat) -> Bool:
  Nat.is_eq(a, b) || Nat.is_eq(a, Nat.add(b, 1n))
    || Nat.is_eq(Nat.add(a, 1n), b)

def triangle(+value: Nat, +period: Nat) -> Nat:
  +phase = Nat.mod(value, period)
  Nat.min(phase, Nat.sub(period, phase))

# ---------------------------------------------------------------------------
# U32 terrain core
#
# The browser runs Bend on the JavaScript target, where every `Nat` is a
# BigInt and every `Nat` operator is a trampolined call. Terrain generation
# evaluates the same few formulas for every cell of every chunk, so the hot
# path is written in `U32` (a native 32-bit integer on every target) and the
# `Nat` API keeps its signatures as thin conversions around it.
#
# Domain: coordinates below 2^28. The encoded negative chunks sit near 1.6e7,
# and every intermediate below (the largest is `mix`, under 1.1e9) then stays
# inside 32 bits, so the U32 formulas equal the Nat ones exactly.
# ---------------------------------------------------------------------------

# Every seed-dependent constant the terrain formulas read, reduced once. The
# seed itself is an unbounded Nat, so it is reduced in Nat before it narrows.
type Terms is Data:
  Terms{mix: U32, s24: U32, s18: U32, s48: U32, s40: U32, s32: U32, s17: U32, s9: U32, s89: U32}

def terms(+seed: Nat) -> Terms:
  Terms{
    U32.from_nat(Nat.mul(Nat.mod(seed, 997n), 7n)),
    U32.from_nat(Nat.mod(seed, 24n)),
    U32.from_nat(Nat.mod(seed, 18n)),
    U32.from_nat(Nat.mod(seed, 48n)),
    U32.from_nat(Nat.mod(seed, 40n)),
    U32.from_nat(Nat.mod(seed, 32n)),
    U32.from_nat(Nat.mod(seed, 17n)),
    U32.from_nat(Nat.mod(seed, 9n)),
    U32.from_nat(Nat.mod(seed, 89n))
  }

# `Nat.sub` saturates at zero; the U32 core must too, or `x - 1` at the world
# edge would wrap to 2^32 - 1 and hash a different column.
def sat_sub32(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_lt(a, b), 0, (a - b : U32))

def terms.mix(+t: Terms) -> U32:
  Terms{+mix, +s24, +s18, +s48, +s40, +s32, +s17, +s9, +s89} = t
  mix

def terms.s89(+t: Terms) -> U32:
  Terms{+mix, +s24, +s18, +s48, +s40, +s32, +s17, +s9, +s89} = t
  s89

def triangle32(+value: U32, +period: U32) -> U32:
  +phase = U32.mod(value, period)
  U32.min(phase, (period - phase : U32))

def mix32(+seed_mix: U32, +x: U32, +z: U32) -> U32:
  +sx = U32.mod(x, 4096)
  +sz = U32.mod(z, 4096)
  U32.mod((sx * sx * 17 + sz * sz * 31 + sx * sz * 13 + seed_mix : U32), 97)

def plains_at32(+x: U32, +z: U32) -> Bool:
  Bool.and(U32.is_lt(x, 96), U32.is_lt(z, 96))

def biome32.if(+seed_mix: U32, +x: U32, +z: U32, plains: Bool) -> U32:
  match plains:
    case True{}:
      0
    case False{}:
      U32.mod(mix32(seed_mix, U32.div(x, 32), U32.div(z, 32)), 4)

def biome32(+t: Terms, +x: U32, +z: U32) -> U32:
  Terms{+mix, +s24, +s18, +s48, +s40, +s32, +s17, +s9, +s89} = t
  biome32.if(mix, x, z, plains_at32(x, z))

def rolling_height32(+t: Terms, +x: U32, +z: U32) -> U32:
  Terms{+mix, +s24, +s18, +s48, +s40, +s32, +s17, +s9, +s89} = t
  +macro = triangle32((x + z + s24 : U32), 24)
  +ridge = triangle32((x * 2 + z * 3 + s18 : U32), 18)
  +detail = U32.mod(mix32(mix, x, z), 3)
  (5 + U32.div(macro, 3) + U32.div(ridge, 2) + detail : U32)

def plains_height32(+t: Terms, +x: U32, +z: U32) -> U32:
  Terms{+mix, +s24, +s18, +s48, +s40, +s32, +s17, +s9, +s89} = t
  +macro = triangle32((x + z + s48 : U32), 48)
  +ridge = triangle32((x * 2 + z + s40 : U32), 40)
  +region = U32.mod(mix32(mix, U32.div(x, 4), U32.div(z, 4)), 2)
  (7 + U32.div(macro, 12) + U32.div(ridge, 20) + region : U32)

def desert_height32(+t: Terms, +x: U32, +z: U32) -> U32:
  Terms{+mix, +s24, +s18, +s48, +s40, +s32, +s17, +s9, +s89} = t
  +macro = triangle32((x + z + s32 : U32), 32)
  +detail = U32.mod(mix32(mix, U32.div(x, 4), U32.div(z, 4)), 2)
  (6 + U32.div(macro, 16) + detail : U32)

def mountain_height32(+t: Terms, +x: U32, +z: U32) -> U32:
  Terms{+mix, +s24, +s18, +s48, +s40, +s32, +s17, +s9, +s89} = t
  +macro = triangle32((x + z + s32 : U32), 32)
  +ridge = triangle32((x * 3 + z + s24 : U32), 24)
  (10 + U32.div(macro, 4) + U32.div(ridge, 3) : U32)

# Only the selected biome's formula runs; `Bool.pick` would evaluate all four.
def height32.mountain(+t: Terms, +x: U32, +z: U32, mountain: Bool) -> U32:
  match mountain:
    case True{}:
      mountain_height32(t, x, z)
    case False{}:
      rolling_height32(t, x, z)

def height32.desert(+t: Terms, +x: U32, +z: U32, +biome: U32, desert: Bool) -> U32:
  match desert:
    case True{}:
      desert_height32(t, x, z)
    case False{}:
      height32.mountain(t, x, z, U32.is_eq(biome, 3))

def height32.biome(+t: Terms, +x: U32, +z: U32, +biome: U32, plains: Bool) -> U32:
  match plains:
    case True{}:
      plains_height32(t, x, z)
    case False{}:
      height32.desert(t, x, z, biome, U32.is_eq(biome, 2))

def height32.with_biome(+t: Terms, +x: U32, +z: U32, +biome: U32) -> U32:
  height32.biome(t, x, z, biome, plains_at32(x, z))

def height32(+t: Terms, +x: U32, +z: U32) -> U32:
  height32.with_biome(t, x, z, biome32(t, x, z))

def tree32(+t: Terms, +x: U32, +z: U32, +h: U32, +biome: U32, +mixed: U32) -> Bool:
  Terms{+mix, +s24, +s18, +s48, +s40, +s32, +s17, +s9, +s89} = t
  +forest = U32.is_eq(biome, 1)
  +hash = U32.mod((mixed + s17 : U32), 37)
  +forest_hash = U32.mod((mixed + s9 : U32), 9)
  +selected = Bool.pick(Bool, forest, U32.is_eq(forest_hash, 0), U32.is_eq(hash, 0))
  +highland = U32.is_gt(h, 8)
  +woodland = Bool.or(U32.is_eq(biome, 0), forest)
  highland && woodland && U32.is_gt(x, 1) && U32.is_gt(z, 1) && selected

def mix(+seed: Nat, +x: Nat, +z: Nat) -> Nat:
  +seed_mix = U32.from_nat(Nat.mul(Nat.mod(seed, 997n), 7n))
  U32.to_nat(mix32(seed_mix, U32.from_nat(x), U32.from_nat(z)))

def plains_at(+x: Nat, +z: Nat) -> Bool:
  Nat.is_lt(x, plains_limit()) && Nat.is_lt(z, plains_limit())

def biome_at(+seed: Nat, +x: Nat, +z: Nat) -> U32:
  biome32(terms(seed), U32.from_nat(x), U32.from_nat(z))

def column_height(+seed: Nat, +x: Nat, +z: Nat) -> Nat:
  U32.to_nat(height32(terms(seed), U32.from_nat(x), U32.from_nat(z)))

def tree_at_height(+seed: Nat, +x: Nat, +z: Nat, +h: Nat) -> Bool:
  +biome = biome_at(seed, x, z)
  +forest = U32.is_eq(biome, 1)
  +hash = Nat.mod(Nat.add(mix(seed, x, z), Nat.mod(seed, 17n)), 37n)
  +forest_hash = Nat.mod(Nat.add(mix(seed, x, z), Nat.mod(seed, 9n)), 9n)
  +selected = Bool.pick(Bool, forest, Nat.is_eq(forest_hash, 0n), Nat.is_eq(hash, 0n))
  +highland = Nat.is_gt(h, Nat.add(sea_level(), 1n))
  +away_x = Nat.is_gt(x, 1n)
  +away_z = Nat.is_gt(z, 1n)
  +woodland = Bool.or(U32.is_eq(biome, 0), forest)
  highland && woodland && away_x && away_z && selected

def tree_at(+seed: Nat, +x: Nat, +z: Nat) -> Bool:
  tree_at_height(seed, x, z, column_height(seed, x, z))

def trunk_at_height(+seed: Nat, +x: Nat, +y: Nat, +z: Nat, +h: Nat) -> Bool:
  +trunk_y = same(y, h) || same(y, Nat.add(h, 1n))
    || same(y, Nat.add(h, 2n))
  tree_at_height(seed, x, z, h) && trunk_y

def trunk_at(+seed: Nat, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  +h = column_height(seed, x, z)
  trunk_at_height(seed, x, y, z, h)

def canopy_at(
  +seed: Nat, +cx: Nat, +cz: Nat, +x: Nat, +y: Nat, +z: Nat
) -> Bool:
  +h = column_height(seed, cx, cz)
  +near_x = near(x, cx)
  +near_z = near(z, cz)
  +lower_canopy = same(y, Nat.add(h, 2n)) && near_x && near_z
  +upper_arm = same(y, Nat.add(h, 3n)) && near_x && near_z
    && (same(x, cx) || same(z, cz))
  tree_at_height(seed, cx, cz, h) && (lower_canopy || upper_arm)

def canopy(+seed: Nat, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  +xm = Nat.sub(x, 1n)
  +xp = Nat.add(x, 1n)
  +zm = Nat.sub(z, 1n)
  +zp = Nat.add(z, 1n)
  canopy_at(seed, xm, zm, x, y, z) || canopy_at(seed, xm, z, x, y, z)
    || canopy_at(seed, xm, zp, x, y, z) || canopy_at(seed, x, zm, x, y, z)
    || canopy_at(seed, x, z, x, y, z) || canopy_at(seed, x, zp, x, y, z)
    || canopy_at(seed, xp, zm, x, y, z) || canopy_at(seed, xp, z, x, y, z)
    || canopy_at(seed, xp, zp, x, y, z)

# Caves are two 3D noise fields read on a four-cell lattice, and a cell is a cave
# only where both fields sit in their own band. That is the cheap two-field
# ("spaghetti") rule: every lattice cell that passes becomes one 4x4x4 pocket of
# air, and neighbouring pockets share a face, so caves run and join instead of
# speckling the way a single per-cell hash did.
def cave_lattice_at(+seed: Nat, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  +cell_x = Nat.div(x, 4n)
  +cell_y = Nat.div(y, 4n)
  +cell_z = Nat.div(z, 4n)
  +column = mix(seed, cell_x, cell_z)
  +first = Nat.mod(Nat.add(Nat.add(column, Nat.mul(cell_y, 17n)), Nat.mod(seed, 13n)), 97n)
  +second = Nat.mod(Nat.add(Nat.add(column, Nat.mul(cell_y, 31n)), Nat.mod(seed, 29n)), 97n)
  Nat.is_lt(first, 12n) && Nat.is_lt(second, 13n)

def cave_lattice_when(enclosed: Bool, +seed: Nat, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match enclosed:
    case False{}:
      False{}
    case True{}:
      cave_lattice_at(seed, x, y, z)

def cave_at_height(+seed: Nat, +x: Nat, +y: Nat, +z: Nat, +h: Nat) -> Bool:
  cave_lattice_when(Nat.is_gt(y, 1n) && Nat.is_lt(Nat.add(y, 2n), h), seed, x, y, z)

def cave_at(+seed: Nat, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  cave_at_height(seed, x, y, z, column_height(seed, x, z))

def water_at_height(+h: Nat, +y: Nat) -> Bool:
  Nat.is_le(h, y) && Nat.is_lt(y, Nat.add(sea_level(), 1n))

def water_at(+seed: Nat, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  water_at_height(column_height(seed, x, z), y)

def lava_at(+seed: Nat, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  +height = column_height(seed, x, z)
  +deep = Bool.and(Nat.is_gt(y, 1n), Nat.is_le(y, 3n))
  +inside = Nat.is_lt(y, height)
  +hash = Nat.mod(Nat.add(mix(seed, x, z), Nat.mul(y, 13n)), 29n)
  Bool.and(Bool.and(deep, inside), Nat.is_eq(hash, 0n))

# ---------------------------------------------------------------------------
# Ores
#
# Every ore generates in a band of its own and at a density of its own, and
# both come from vanilla's ore table
# (https://minecraft.wiki/w/Ore_(feature), Java 1.18+):
#
#   ore     layers above bedrock   vein   tries/chunk   blocks/chunk
#   coal    0..192                 17     20            ~280
#   iron    -64..72                 9     10            ~60
#   diamond -64..16                 4     7             ~20
#
# A column here is five to eighteen cells tall (sea level 7, `max_y` 64), so a
# vanilla band cannot be copied as a layer count: it is taken as a fraction of
# the column instead, which is what the player reads as depth. Diamond
# generates in the bottom quarter and concentrates in the bottom eighth, and
# coal and iron generate through the whole column. Densities are vanilla's per
# rock cell, about 1.7% coal, 0.4% iron and 0.13% diamond.
#
# Ores come in veins. One vein is placed per eight-cell lattice cell: the lattice
# cell's hash says which ore the vein holds, and three more say where inside it
# the vein sits, far enough from the cell's edge that it never reaches across.
# A cell is ore when it falls within the vein's reach, which is what makes a vein
# a pocket you can find rather than one block per hash.
# ---------------------------------------------------------------------------

def ore_lattice() -> Nat:
  8n

# The ore a vein holds, rarest first, so a lattice cell holds one ore and not a
# mixture. The three thresholds are the share of lattice cells each ore takes,
# calibrated against vanilla's densities (see tests/ore-distribution.test.mjs).
def ore_vein_of(+seed: Nat, +column: Nat, +cell_y: Nat) -> U32:
  +first = Nat.mod(Nat.add(Nat.add(column, Nat.mul(cell_y, 17n)), Nat.mod(seed, 13n)), 97n)
  +second = Nat.mod(Nat.add(Nat.add(column, Nat.mul(cell_y, 53n)), Nat.mod(seed, 29n)), 97n)
  +rare = Nat.add(Nat.mul(first, 97n), second)
  Bool.pick(U32, Nat.is_lt(rare, 1750n), 10,
    Bool.pick(U32, Nat.is_lt(rare, 2175n), 9,
      Bool.pick(U32, Nat.is_lt(rare, 5150n), 8, 1)))

# Whether an ore generates at this height in this column. Stone, and so every
# vein of no ore, is in every band.
def ore_band(+ore: U32, +y: Nat, +h: Nat) -> Bool:
  Bool.or(U32.is_ne(ore, 10), Nat.is_le(Nat.mul(y, 4n), h))

# How far a vein of an ore reaches, in cells, which is what makes it its size: a
# diamond vein of reach one is the seven cells vanilla's size-4 vein holds, and
# coal and iron at reach two are the big ones.
def ore_reach(+ore: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(ore, 10), 1n, 2n)

# Where a vein sits on one axis of its lattice cell: held far enough from the
# cell's edge that a vein of this reach stays inside it, so a vein never reaches
# across a cell it was not placed in.
def ore_offset(+cell: Nat, +reach: Nat, +spread: Nat) -> Nat:
  +inside = Nat.mod(spread, Nat.sub(ore_lattice(), Nat.mul(reach, 2n)))
  Nat.add(Nat.mul(cell, ore_lattice()), Nat.add(reach, inside))

def abs_nat(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_gt(a, b), Nat.sub(a, b), Nat.sub(b, a))

def ore_filled(+seed: Nat, +x: Nat, +y: Nat, +z: Nat, +h: Nat) -> Bool:
  +cell_x = Nat.div(x, ore_lattice())
  +cell_y = Nat.div(y, ore_lattice())
  +cell_z = Nat.div(z, ore_lattice())
  +column = mix(seed, cell_x, cell_z)
  +ore = ore_vein_of(seed, column, cell_y)
  +reach = ore_reach(ore)
  +across_x = Nat.add(Nat.mul(column, 17n), Nat.mul(cell_y, 71n))
  +across_y = Nat.add(Nat.mul(column, 53n), Nat.mul(cell_z, 71n))
  +across_z = Nat.add(Nat.mul(column, 29n), Nat.mul(cell_x, 71n))
  +distance = Nat.add(
    Nat.add(abs_nat(x, ore_offset(cell_x, reach, across_x)),
      abs_nat(y, ore_offset(cell_y, reach, across_y))),
    abs_nat(z, ore_offset(cell_z, reach, across_z)))
  Bool.and(Bool.not(U32.is_eq(ore, 1)),
    Bool.and(ore_band(ore, y, h), Nat.is_le(distance, reach)))

def ore_block(+seed: Nat, +x: Nat, +y: Nat, +z: Nat, +h: Nat) -> U32:
  +cell_x = Nat.div(x, ore_lattice())
  +cell_y = Nat.div(y, ore_lattice())
  +cell_z = Nat.div(z, ore_lattice())
  +column = mix(seed, cell_x, cell_z)
  Bool.pick(U32, ore_filled(seed, x, y, z, h), ore_vein_of(seed, column, cell_y), 1)

def deep_block(+seed: Nat, +x: Nat, +y: Nat, +z: Nat, +h: Nat) -> U32:
  Bool.pick(U32, Bool.and(Nat.is_gt(y, 0n), Nat.is_lt(y, Nat.sub(h, 3n))), ore_block(seed, x, y, z, h), 2)

def terrain_block_height(+h: Nat, +y: Nat) -> U32:
  +inside = Nat.is_lt(y, h)
  +top = same(y, Nat.sub(h, 1n))
  +second = same(y, Nat.sub(h, 2n))
  +deep = Nat.is_lt(y, Nat.sub(h, 3n))
  +beach = Nat.is_le(h, sea_level())
  +top_block = Bool.pick(U32, beach, 6, 3)
  +soil_block = Bool.pick(U32, beach, 6, 2)
  Bool.pick(U32, inside,
    Bool.pick(U32, top, top_block,
      Bool.pick(U32, second, soil_block,
        Bool.pick(U32, deep, 1, 2))),
    0)

def shoreline_at(+seed: Nat, +x: Nat, +z: Nat, +h: Nat) -> Bool:
  +west = Nat.is_lt(column_height(seed, Nat.sub(x, 1n), z), h)
  +east = Nat.is_lt(column_height(seed, Nat.add(x, 1n), z), h)
  +north = Nat.is_lt(column_height(seed, x, Nat.sub(z, 1n)), h)
  +south = Nat.is_lt(column_height(seed, x, Nat.add(z, 1n)), h)
  +low_neighbor = Bool.or(west, Bool.or(east, Bool.or(north, south)))
  Bool.and(low_neighbor, Nat.is_le(h, Nat.add(sea_level(), 1n)))

def terrain_block_at(
  +seed: Nat, +x: Nat, +y: Nat, +z: Nat, +h: Nat
) -> U32:
  +biome = biome_at(seed, x, z)
  +desert = U32.is_eq(biome, 2)
  +beach = Nat.is_le(h, sea_level())
  +shore = shoreline_at(seed, x, z, h)
  +sand_surface = Bool.or(beach, Bool.or(shore, desert))
  +inside = Nat.is_lt(y, h)
  +top = same(y, Nat.sub(h, 1n))
  +second = same(y, Nat.sub(h, 2n))
  +deep = Nat.is_lt(y, Nat.sub(h, 3n))
  +top_block = Bool.pick(U32, sand_surface, 6, 3)
  +soil_block = Bool.pick(U32, sand_surface, 6, 2)
  Bool.pick(U32, inside,
    Bool.pick(U32, top, top_block,
      Bool.pick(U32, second, soil_block,
        Bool.pick(U32, deep, deep_block(seed, x, y, z, h), 2))),
    0)

def terrain_block(+seed: Nat, +x: Nat, +y: Nat, +z: Nat) -> U32:
  terrain_block_at(seed, x, y, z, column_height(seed, x, z))

def block(+seed: Nat, +x: Nat, +y: Nat, +z: Nat) -> U32:
  +height = column_height(seed, x, z)
  +village_height = column_height(seed, Structures.village_origin_x(seed), Structures.village_origin_z(seed))
  +structure = Structures.block(seed, x, y, z, village_height)
  +wood = trunk_at(seed, x, y, z)
  +leaf = canopy(seed, x, y, z)
  +lava = lava_at(seed, x, y, z)
  +cave = cave_at(seed, x, y, z)
  +water = water_at(seed, x, y, z)
  +bedrock = Nat.is_eq(y, 0n)
  Bool.pick(U32, bedrock, 41,
    Bool.pick(U32, U32.is_ne(structure, 0), structure,
    Bool.pick(U32, wood, 5,
      Bool.pick(U32, leaf, 4,
        Bool.pick(U32, lava, 21,
          Bool.pick(U32, cave, 0,
            Bool.pick(U32, water, 7, terrain_block(seed, x, y, z))))))))

# Above the terrain surface only generated structures, trunks, and canopy can
# provide shade. Keep this narrower query separate from the full block rule so
# sunlight does not repeatedly evaluate caves, water, lava, and ore generation.
def generated_tree_cover_at(
  +seed: Nat, +center_x: Nat, +center_z: Nat, +x: Nat, +z: Nat, +cell_y: Nat
) -> Bool:
  +h = column_height(seed, center_x, center_z)
  +lower_y = Nat.add(h, 2n)
  +upper_y = Nat.add(h, 3n)
  Bool.or(
    Bool.and(Nat.is_gt(lower_y, cell_y), canopy_at(seed, center_x, center_z, x, lower_y, z)),
    Bool.and(Nat.is_gt(upper_y, cell_y), canopy_at(seed, center_x, center_z, x, upper_y, z))
  )

def generated_tree_cover(+seed: Nat, +x: Nat, +z: Nat, +cell_y: Nat) -> Bool:
  Bool.or(
    generated_tree_cover_at(seed, Nat.sub(x, 1n), Nat.sub(z, 1n), x, z, cell_y),
    Bool.or(
      generated_tree_cover_at(seed, Nat.sub(x, 1n), z, x, z, cell_y),
      Bool.or(
        generated_tree_cover_at(seed, Nat.sub(x, 1n), Nat.add(z, 1n), x, z, cell_y),
        Bool.or(
          generated_tree_cover_at(seed, x, Nat.sub(z, 1n), x, z, cell_y),
          Bool.or(
            generated_tree_cover_at(seed, x, z, x, z, cell_y),
            Bool.or(
              generated_tree_cover_at(seed, x, Nat.add(z, 1n), x, z, cell_y),
              Bool.or(
                generated_tree_cover_at(seed, Nat.add(x, 1n), Nat.sub(z, 1n), x, z, cell_y),
                Bool.or(
                  generated_tree_cover_at(seed, Nat.add(x, 1n), z, x, z, cell_y),
                  generated_tree_cover_at(seed, Nat.add(x, 1n), Nat.add(z, 1n), x, z, cell_y)
                )
              )
            )
          )
        )
      )
    )
  )

def generated_cover_above(+seed: Nat, +x: Nat, +cell_y: Nat, +z: Nat) -> U32:
  +village_height = column_height(seed, Structures.village_origin_x(seed), Structures.village_origin_z(seed))
  +structure_1 = Structures.block(seed, x, Nat.add(cell_y, 1n), z, village_height)
  +structure_2 = Structures.block(seed, x, Nat.add(cell_y, 2n), z, village_height)
  +structure_3 = Structures.block(seed, x, Nat.add(cell_y, 3n), z, village_height)
  +structure_4 = Structures.block(seed, x, Nat.add(cell_y, 4n), z, village_height)
  +structure = Bool.pick(U32, U32.is_ne(structure_1, 0), structure_1,
    Bool.pick(U32, U32.is_ne(structure_2, 0), structure_2,
      Bool.pick(U32, U32.is_ne(structure_3, 0), structure_3, structure_4)))
  +tree_cover = generated_tree_cover(seed, x, z, cell_y)
  Bool.pick(U32, U32.is_ne(structure, 0), structure, Bool.pick(U32, tree_cover, 4, 0))

type SpawnCell is Data:
  SpawnCell{x: Nat, z: Nat, height: Nat}

def spawn_tree_row_left(+seed: Nat, +x: Nat, +row_z: Nat) -> Bool:
  +a = tree_at(seed, Nat.sub(x, 7n), row_z)
  +b = tree_at(seed, Nat.sub(x, 6n), row_z)
  +c = tree_at(seed, Nat.sub(x, 5n), row_z)
  +d = tree_at(seed, Nat.sub(x, 4n), row_z)
  +e = tree_at(seed, Nat.sub(x, 3n), row_z)
  +f = tree_at(seed, Nat.sub(x, 2n), row_z)
  +g = tree_at(seed, Nat.sub(x, 1n), row_z)
  Bool.or(a, Bool.or(b, Bool.or(c, Bool.or(d, Bool.or(e,
    Bool.or(f, g))))))

def spawn_tree_row_right(+seed: Nat, +x: Nat, +row_z: Nat) -> Bool:
  +h = tree_at(seed, x, row_z)
  +i = tree_at(seed, Nat.add(x, 1n), row_z)
  +j = tree_at(seed, Nat.add(x, 2n), row_z)
  +k = tree_at(seed, Nat.add(x, 3n), row_z)
  +l = tree_at(seed, Nat.add(x, 4n), row_z)
  +m = tree_at(seed, Nat.add(x, 5n), row_z)
  +n = tree_at(seed, Nat.add(x, 6n), row_z)
  +o = tree_at(seed, Nat.add(x, 7n), row_z)
  Bool.or(h, Bool.or(i, Bool.or(j, Bool.or(k, Bool.or(l,
    Bool.or(m, Bool.or(n, o)))))))

def spawn_tree_row(+seed: Nat, +x: Nat, +row_z: Nat) -> Bool:
  Bool.or(spawn_tree_row_left(seed, x, row_z), spawn_tree_row_right(seed, x, row_z))

def spawn_tree_band(+seed: Nat, +x: Nat, +row_z: Nat) -> Bool:
  +row0 = spawn_tree_row(seed, x, row_z)
  +row1 = spawn_tree_row(seed, x, Nat.add(row_z, 1n))
  +row2 = spawn_tree_row(seed, x, Nat.add(row_z, 2n))
  +row3 = spawn_tree_row(seed, x, Nat.add(row_z, 3n))
  +row4 = spawn_tree_row(seed, x, Nat.add(row_z, 4n))
  Bool.or(row0, Bool.or(row1, Bool.or(row2, Bool.or(row3, row4))))

def spawn_tree_near(+seed: Nat, +x: Nat, +z: Nat) -> Bool:
  +north = spawn_tree_band(seed, x, Nat.sub(z, 7n))
  +middle = spawn_tree_band(seed, x, Nat.sub(z, 2n))
  +south = spawn_tree_band(seed, x, Nat.add(z, 3n))
  Bool.or(north, Bool.or(middle, south))

def spawn_tree_free(+seed: Nat, +x: Nat, +z: Nat) -> Bool:
  Bool.not(spawn_tree_near(seed, x, z))

def spawn_structure_open(+seed: Nat, +x: Nat, +y: Nat, +z: Nat, +village_height: Nat) -> Bool:
  U32.is_eq(Structures.block(seed, x, y, z, village_height), 0)

def spawn_structure_row(+seed: Nat, +x: Nat, +y: Nat, +row_z: Nat, +village_height: Nat) -> Bool:
  +a = spawn_structure_open(seed, Nat.sub(x, 4n), y, row_z, village_height)
  +b = spawn_structure_open(seed, Nat.sub(x, 3n), y, row_z, village_height)
  +c = spawn_structure_open(seed, Nat.sub(x, 2n), y, row_z, village_height)
  +d = spawn_structure_open(seed, Nat.sub(x, 1n), y, row_z, village_height)
  +e = spawn_structure_open(seed, x, y, row_z, village_height)
  +f = spawn_structure_open(seed, Nat.add(x, 1n), y, row_z, village_height)
  +g = spawn_structure_open(seed, Nat.add(x, 2n), y, row_z, village_height)
  +h = spawn_structure_open(seed, Nat.add(x, 3n), y, row_z, village_height)
  +i = spawn_structure_open(seed, Nat.add(x, 4n), y, row_z, village_height)
  Bool.and(a, Bool.and(b, Bool.and(c, Bool.and(d, Bool.and(e,
    Bool.and(f, Bool.and(g, Bool.and(h, i))))))))

def spawn_structure_band(+seed: Nat, +x: Nat, +y: Nat, +row_z: Nat, +village_height: Nat) -> Bool:
  +row0 = spawn_structure_row(seed, x, y, row_z, village_height)
  +row1 = spawn_structure_row(seed, x, y, Nat.add(row_z, 1n), village_height)
  +row2 = spawn_structure_row(seed, x, y, Nat.add(row_z, 2n), village_height)
  Bool.and(row0, Bool.and(row1, row2))

def spawn_structures_free(+seed: Nat, +x: Nat, +y: Nat, +z: Nat, +village_height: Nat) -> Bool:
  +north = spawn_structure_band(seed, x, y, Nat.sub(z, 4n), village_height)
  +middle = spawn_structure_band(seed, x, y, Nat.sub(z, 1n), village_height)
  +south = spawn_structure_band(seed, x, y, Nat.add(z, 2n), village_height)
  Bool.and(north, Bool.and(middle, south))

def spawn_structure_front_left(+seed: Nat, +x: Nat, +y: Nat, +row_z: Nat, +village_height: Nat) -> Bool:
  +a = spawn_structure_open(seed, Nat.sub(x, 6n), y, row_z, village_height)
  +b = spawn_structure_open(seed, Nat.sub(x, 5n), y, row_z, village_height)
  +c = spawn_structure_open(seed, Nat.sub(x, 4n), y, row_z, village_height)
  +d = spawn_structure_open(seed, Nat.sub(x, 3n), y, row_z, village_height)
  +e = spawn_structure_open(seed, Nat.sub(x, 2n), y, row_z, village_height)
  +f = spawn_structure_open(seed, Nat.sub(x, 1n), y, row_z, village_height)
  Bool.and(a, Bool.and(b, Bool.and(c, Bool.and(d, Bool.and(e, f)))))

def spawn_structure_front_right(+seed: Nat, +x: Nat, +y: Nat, +row_z: Nat, +village_height: Nat) -> Bool:
  +h = spawn_structure_open(seed, Nat.add(x, 1n), y, row_z, village_height)
  +i = spawn_structure_open(seed, Nat.add(x, 2n), y, row_z, village_height)
  +j = spawn_structure_open(seed, Nat.add(x, 3n), y, row_z, village_height)
  +k = spawn_structure_open(seed, Nat.add(x, 4n), y, row_z, village_height)
  +l = spawn_structure_open(seed, Nat.add(x, 5n), y, row_z, village_height)
  +m = spawn_structure_open(seed, Nat.add(x, 6n), y, row_z, village_height)
  Bool.and(h, Bool.and(i, Bool.and(j, Bool.and(k, Bool.and(l, m)))))

def spawn_structure_front_row(+seed: Nat, +x: Nat, +y: Nat, +row_z: Nat, +village_height: Nat) -> Bool:
  +center = spawn_structure_open(seed, x, y, row_z, village_height)
  Bool.and(spawn_structure_front_left(seed, x, y, row_z, village_height),
    Bool.and(center, spawn_structure_front_right(seed, x, y, row_z, village_height)))

def spawn_structure_front(+seed: Nat, +x: Nat, +y: Nat, +z: Nat, +village_height: Nat) -> Bool:
  +far = spawn_structure_front_row(seed, x, y, Nat.sub(z, 6n), village_height)
  +middle = spawn_structure_front_row(seed, x, y, Nat.sub(z, 5n), village_height)
  +front_near = spawn_structure_front_row(seed, x, y, Nat.sub(z, 4n), village_height)
  Bool.and(far, Bool.and(middle, front_near))

def spawn_ground_level(+seed: Nat, +x: Nat, +z: Nat, +low: Nat, +high: Nat) -> Bool:
  +h = column_height(seed, x, z)
  Bool.and(Nat.is_ge(h, low), Nat.is_le(h, high))

def spawn_ground_free(+seed: Nat, +x: Nat, +z: Nat, +height: Nat) -> Bool:
  +xm = Nat.sub(x, 1n)
  +xp = Nat.add(x, 1n)
  +zm = Nat.sub(z, 1n)
  +zp = Nat.add(z, 1n)
  +low = Nat.sub(height, 1n)
  +high = height
  +row_north = Bool.and(spawn_ground_level(seed, xm, zm, low, high), Bool.and(spawn_ground_level(seed, x, zm, low, high), spawn_ground_level(seed, xp, zm, low, high)))
  +row_middle = Bool.and(spawn_ground_level(seed, xm, z, low, high), Bool.and(spawn_ground_level(seed, x, z, low, high), spawn_ground_level(seed, xp, z, low, high)))
  +row_south = Bool.and(spawn_ground_level(seed, xm, zp, low, high), Bool.and(spawn_ground_level(seed, x, zp, low, high), spawn_ground_level(seed, xp, zp, low, high)))
  Bool.and(row_north, Bool.and(row_middle, row_south))

def spawn_clear(+seed: Nat, +x: Nat, +z: Nat) -> Bool:
  +height = column_height(seed, x, z)
  +village_height = column_height(seed, Structures.village_origin_x(seed), Structures.village_origin_z(seed))
  +trees = spawn_tree_free(seed, x, z)
  +struct_feet = spawn_structures_free(seed, x, height, z, village_height)
  +struct_head = spawn_structures_free(seed, x, Nat.add(height, 1n), z, village_height)
  +struct_upper = spawn_structures_free(seed, x, Nat.add(height, 2n), z, village_height)
  +struct_front = spawn_structure_front(seed, x, height, z, village_height)
  +ground = spawn_ground_free(seed, x, z, height)
  +open = Bool.and(Bool.and(trees, struct_feet), Bool.and(struct_head,
    Bool.and(struct_upper, Bool.and(struct_front, ground))))
  Bool.and(open, Nat.is_gt(height, sea_level()))

def spawn_search(+seed: Nat, +remaining: Nat, +index: Nat) -> SpawnCell:
  match remaining:
    case 0n:
      SpawnCell{8n, 8n, column_height(seed, 8n, 8n)}
    case 1n+p:
      +x = Nat.mod(index, width())
      +z = Nat.div(index, width())
      +height = column_height(seed, x, z)
      +valid = spawn_clear(seed, x, z)
      +next_index = Nat.mod(Nat.add(index, 1n), Nat.mul(width(), depth()))
      Bool.pick(SpawnCell, valid, SpawnCell{x, z, height}, spawn_search(seed, p, next_index))

def spawn_cell(+seed: Nat) -> SpawnCell:
  spawn_search(
    seed,
    Nat.mul(width(), depth()),
    Nat.add(Nat.mul(Nat.div(depth(), 3n), width()), Nat.div(width(), 2n)),
  )

# ---------------------------------------------------------------------------
# Bulk chunk generation
#
# The cell rule below is the chunk rule the browser has always streamed
# (structures, trunks, canopy above y = 10, caves, sea water, terrain; no
# generated lava), evaluated through the U32 core. Everything a cell needs that
# only depends on its column (height, biome hash, sand surface, tree, the canopy
# layers of the 3x3 neighbourhood, village proximity) is computed once per
# column instead of once per cell. `tests/world-chunk-golden.test.mjs` pins the
# output to fingerprints taken from the original per-cell Nat implementation.
# ---------------------------------------------------------------------------

type Column is Data:
  Column{height: U32, mixed: U32, sand: Bool, tree: Bool, leaves: U32, village: Bool}

def column.leaves(+column: Column) -> U32:
  Column{+height, +mixed, +sand, +tree, +leaves, +village} = column
  leaves

def chunk32.bit(+y: U32) -> U32:
  U32.shln(1, U32.to_nat(y))

# Canopy layers contributed by the tree rooted at (cx, cz) to the column
# (x, z), as a bit per y. The lower canopy fills the whole 3x3 ring at h + 2;
# the upper arm at h + 3 only reaches the plus-shaped neighbours.
def chunk32.leaf_bits(+t: Terms, +x: U32, +z: U32, +cx: U32, +cz: U32) -> U32:
  Terms{+mix, +s24, +s18, +s48, +s40, +s32, +s17, +s9, +s89} = t
  +biome = biome32(t, cx, cz)
  +h = height32.with_biome(t, cx, cz, biome)
  +tree = tree32(t, cx, cz, h, biome, mix32(mix, cx, cz))
  +plus = Bool.or(U32.is_eq(cx, x), U32.is_eq(cz, z))
  +lower = chunk32.bit((h + 2 : U32))
  +upper = Bool.pick(U32, plus, chunk32.bit((h + 3 : U32)), 0)
  Bool.pick(U32, tree, U32.or(lower, upper), 0)

# Shoreline sand only changes the answer for a column exactly one block above
# sea level: lower columns are beach sand and higher ones never qualify.
def chunk32.shore(+t: Terms, +x: U32, +z: U32, +h: U32, check: Bool) -> Bool:
  match check:
    case False{}:
      False{}
    case True{}:
      +west = U32.is_lt(height32(t, sat_sub32(x, 1), z), h)
      +east = U32.is_lt(height32(t, (x + 1 : U32), z), h)
      +north = U32.is_lt(height32(t, x, sat_sub32(z, 1)), h)
      +south = U32.is_lt(height32(t, x, (z + 1 : U32)), h)
      Bool.or(Bool.or(west, east), Bool.or(north, south))

def chunk32.column(
  +t: Terms, +x: U32, +z: U32, +origin_x: U32, +origin_z: U32, +village_valid: Bool
) -> Column:
  Terms{+mix, +s24, +s18, +s48, +s40, +s32, +s17, +s9, +s89} = t
  +biome = biome32(t, x, z)
  +h = height32.with_biome(t, x, z, biome)
  +mixed = mix32(mix, x, z)
  +tree = tree32(t, x, z, h, biome, mixed)
  +desert = U32.is_eq(biome, 2)
  +shore = chunk32.shore(t, x, z, h, Bool.and(U32.is_eq(h, 8), Bool.not(desert)))
  +sand = Bool.or(U32.is_le(h, 7), Bool.or(desert, shore))
  +xm = sat_sub32(x, 1)
  +xp = (x + 1 : U32)
  +zm = sat_sub32(z, 1)
  +zp = (z + 1 : U32)
  +west = U32.or(chunk32.leaf_bits(t, x, z, xm, zm), U32.or(chunk32.leaf_bits(t, x, z, xm, z), chunk32.leaf_bits(t, x, z, xm, zp)))
  +middle = U32.or(chunk32.leaf_bits(t, x, z, x, zm), U32.or(chunk32.leaf_bits(t, x, z, x, z), chunk32.leaf_bits(t, x, z, x, zp)))
  +east = U32.or(chunk32.leaf_bits(t, x, z, xp, zm), U32.or(chunk32.leaf_bits(t, x, z, xp, z), chunk32.leaf_bits(t, x, z, xp, zp)))
  # Chunk canopy is only emitted above y = 10 (bits 11 and up).
  +leaves = U32.and(U32.or(west, U32.or(middle, east)), 4294965248)
  +near_x = Bool.and(U32.is_ge(x, sat_sub32(origin_x, 8)), U32.is_lt(x, (origin_x + 14 : U32)))
  +near_z = Bool.and(U32.is_ge(z, sat_sub32(origin_z, 8)), U32.is_lt(z, (origin_z + 14 : U32)))
  Column{h, mixed, sand, tree, leaves, Bool.and(village_valid, Bool.and(near_x, near_z))}

def chunk32.structure(
  +seed: Nat, +x: U32, +y: U32, +z: U32, +village_height: Nat, village: Bool
) -> U32:
  match village:
    case False{}:
      0
    case True{}:
      Structures.block(seed, U32.to_nat(x), U32.to_nat(y), U32.to_nat(z), village_height)

# The U32 reading of the vein rule: the same lattice, the same thresholds, the
# same centre and the same reach as the Nat rules above, so the per-chunk path
# and the per-cell query carve one world and not two.
def chunk32.ore_vein(+mix: U32, +cell_y: U32, +s13: U32, +s29: U32) -> U32:
  +first = U32.mod((mix + cell_y * 17 + s13 : U32), 97)
  +second = U32.mod((mix + cell_y * 53 + s29 : U32), 97)
  +rare = (first * 97 + second : U32)
  Bool.pick(U32, U32.is_lt(rare, 1750), 10,
    Bool.pick(U32, U32.is_lt(rare, 2175), 9,
      Bool.pick(U32, U32.is_lt(rare, 5150), 8, 1)))

def chunk32.ore_offset(+cell: U32, +reach: U32, +spread: U32) -> U32:
  +inside = U32.mod(spread, (8 - reach * 2 : U32))
  (cell * 8 + reach + inside : U32)

def chunk32.ore_abs(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_gt(a, b), (a - b : U32), (b - a : U32))

def chunk32.ore(
  +mix: U32, +x: U32, +y: U32, +z: U32, +s13: U32, +s29: U32, +h: U32
) -> U32:
  +cell_x = U32.div(x, 8)
  +cell_y = U32.div(y, 8)
  +cell_z = U32.div(z, 8)
  +column = mix32(mix, cell_x, cell_z)
  +ore = chunk32.ore_vein(column, cell_y, s13, s29)
  +reach = Bool.pick(U32, U32.is_eq(ore, 10), 1, 2)
  +across_x = (column * 17 + cell_y * 71 : U32)
  +across_y = (column * 53 + cell_z * 71 : U32)
  +across_z = (column * 29 + cell_x * 71 : U32)
  +distance = (chunk32.ore_abs(x, chunk32.ore_offset(cell_x, reach, across_x))
    + chunk32.ore_abs(y, chunk32.ore_offset(cell_y, reach, across_y))
    + chunk32.ore_abs(z, chunk32.ore_offset(cell_z, reach, across_z)) : U32)
  +band = Bool.or(U32.is_ne(ore, 10), U32.is_le((y * 4 : U32), h))
  +inside = Bool.and(Bool.not(U32.is_eq(ore, 1)), Bool.and(band, U32.is_le(distance, reach)))
  Bool.pick(U32, inside, ore, 1)

def chunk32.terrain(
  +mix: U32, +x: U32, +z: U32, +h: U32, +sand: Bool, +s13: U32, +s29: U32, +y: U32, inside: Bool
) -> U32:
  match inside:
    case False{}:
      0
    case True{}:
      +deep_limit = sat_sub32(h, 3)
      +deep = Bool.pick(U32, Bool.and(U32.is_gt(y, 0), U32.is_lt(y, deep_limit)), chunk32.ore(mix, x, y, z, s13, s29, h), 2)
      Bool.pick(U32, U32.is_eq(y, sat_sub32(h, 1)), Bool.pick(U32, sand, 6, 3),
        Bool.pick(U32, U32.is_eq(y, sat_sub32(h, 2)), Bool.pick(U32, sand, 6, 2),
          Bool.pick(U32, U32.is_lt(y, deep_limit), deep, 2)))

# The U32 reading of `cave_lattice_at`: the same two banded fields on the same
# four-cell lattice, so the per-chunk path and the per-cell query carve one
# world and not two.
def chunk32.cave_lattice(+mix: U32, +x: U32, +y: U32, +z: U32, +s13: U32, +s29: U32) -> Bool:
  +cell_x = U32.div(x, 4)
  +cell_y = U32.div(y, 4)
  +cell_z = U32.div(z, 4)
  +lattice_column = mix32(mix, cell_x, cell_z)
  +first = U32.mod((lattice_column + cell_y * 17 + s13 : U32), 97)
  +second = U32.mod((lattice_column + cell_y * 31 + s29 : U32), 97)
  U32.is_lt(first, 12) && U32.is_lt(second, 13)

# The same short-circuit as `cave_lattice_when`: rows above the surface, the
# bedrock row and the sea floor never pay for the lattice.
def chunk32.cave_when(
  enclosed: Bool, +mix: U32, +x: U32, +y: U32, +z: U32, +s13: U32, +s29: U32
) -> Bool:
  match enclosed:
    case False{}:
      False{}
    case True{}:
      chunk32.cave_lattice(mix, x, y, z, s13, s29)

def chunk32.cell(
  +seed: Nat, +mix: U32, +s89: U32, +s13: U32, +s29: U32, +village_height: Nat,
  +column: Column,
  +x: U32, +z: U32, +y: U32, +leaf_mask: U32
) -> U32:
  Column{+height, +mixed, +sand, +tree, +leaves, +village} = column
  # Village blocks only exist from the floor (village height) to the roof.
  +vh = U32.from_nat(village_height)
  +in_band = Bool.and(U32.is_ge(y, vh), U32.is_le(y, (vh + 4 : U32)))
  +structure = chunk32.structure(seed, x, y, z, village_height, Bool.and(village, in_band))
  +wood = Bool.and(tree, Bool.and(U32.is_ge(y, height), U32.is_lt(y, (height + 3 : U32))))
  +leaf = U32.is_ne(U32.and(leaf_mask, 1), 0)
  +cave = chunk32.cave_when(
    Bool.and(U32.is_gt(y, 1), U32.is_lt((y + 2 : U32), height)),
    mix, x, y, z, s13, s29)
  +water = Bool.and(U32.is_le(height, y), U32.is_lt(y, 8))
  +terrain = chunk32.terrain(mix, x, z, height, sand, s13, s29, y, U32.is_lt(y, height))
  # Bedrock is the same bottom row `World.block` gives, so the fast per-chunk
  # path and the cell query never disagree about the floor of the world.
  +bedrock = U32.is_eq(y, 0)
  Bool.pick(U32, bedrock, 41,
    Bool.pick(U32, U32.is_ne(structure, 0), structure,
      Bool.pick(U32, wood, 5,
        Bool.pick(U32, leaf, 4,
          Bool.pick(U32, cave, 0,
            Bool.pick(U32, water, 7, terrain))))))

def chunk32.fill(
  +seed: Nat, +mix: U32, +s89: U32, +s13: U32, +s29: U32, +village_height: Nat,
  +column: Column,
  +x: U32, +z: U32, +local: U32, +remaining: Nat, +y: U32, +leaf_mask: U32,
  blocks: Array<U32>
) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      +index = (local + y * 256 : U32)
      updated = blocks[index] <- chunk32.cell(seed, mix, s89, s13, s29, village_height, column, x, z, y, leaf_mask)
      chunk32.fill(seed, mix, s89, s13, s29, village_height, column, x, z, local, p, (y + 1 : U32), U32.shr(leaf_mask), updated)

def chunk32.columns.x(
  +seed: Nat, +t: Terms, +village_height: Nat, +origin_x: U32, +origin_z: U32,
  +village_valid: Bool, +base_x: U32, +base_z: U32, +remaining: Nat,
  +local_x: U32, +local_z: U32, blocks: Array<U32>
) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      +x = (base_x + local_x : U32)
      +z = (base_z + local_z : U32)
      +column = chunk32.column(t, x, z, origin_x, origin_z, village_valid)
      updated = chunk32.fill(seed, terms.mix(t), terms.s89(t),
        U32.from_nat(Nat.mod(seed, 13n)), U32.from_nat(Nat.mod(seed, 29n)),
        village_height, column, x, z, (local_x + local_z * 16 : U32), max_y(), 0, column.leaves(column), blocks)
      chunk32.columns.x(seed, t, village_height, origin_x, origin_z, village_valid, base_x, base_z, p, (local_x + 1 : U32), local_z, updated)

def chunk32.columns.z(
  +seed: Nat, +t: Terms, +village_height: Nat, +origin_x: U32, +origin_z: U32,
  +village_valid: Bool, +base_x: U32, +base_z: U32, +remaining: Nat,
  +local_z: U32, blocks: Array<U32>
) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      updated = chunk32.columns.x(seed, t, village_height, origin_x, origin_z, village_valid, base_x, base_z, chunk_size(), 0, local_z, blocks)
      chunk32.columns.z(seed, t, village_height, origin_x, origin_z, village_valid, base_x, base_z, p, (local_z + 1 : U32), updated)

def chunk(+seed: Nat, +chunk_x: Nat, +chunk_z: Nat) -> Array<U32>:
  +origin_x = Structures.village_origin_x(seed)
  +origin_z = Structures.village_origin_z(seed)
  +village_height = column_height(seed, origin_x, origin_z)
  chunk32.columns.z(
    seed, terms(seed), village_height,
    U32.from_nat(origin_x), U32.from_nat(origin_z),
    Structures.village_height_valid(village_height),
    U32.from_nat(Nat.mul(chunk_x, chunk_size())), U32.from_nat(Nat.mul(chunk_z, chunk_size())),
    chunk_size(), 0, Array.new(U32, 14n, 0)
  )
