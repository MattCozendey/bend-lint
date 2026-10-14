import Base
import ./world.bend as World

def array_depth() -> Nat:
  13n

def grid.fill(
  +seed: Nat, +remaining: Nat, +index: Nat,
  +min_x: Nat, +min_z: Nat, +columns: Nat, +step: Nat,
  blocks: Array<U32>
) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      +sample_x = Nat.mod(index, columns)
      +sample_z = Nat.div(index, columns)
      +x = Nat.add(min_x, Nat.mul(sample_x, step))
      +z = Nat.add(min_z, Nat.mul(sample_z, step))
      +height = U32.from_nat(World.column_height(seed, x, z))
      updated = blocks[U32.from_nat(index)] <- height
      grid.fill(seed, p, Nat.add(index, 1n), min_x, min_z, columns, step, updated)

def grid(
  +seed: Nat, +min_x: Nat, +min_z: Nat,
  +columns: Nat, +rows: Nat, +step: Nat
) -> Array<U32>:
  +cells = Nat.mul(columns, rows)
  +depth = array_depth()
  grid.fill(seed, cells, 0n, min_x, min_z, columns, step, Array.new(U32, depth, 0))

def surface_grid.fill(
  +seed: Nat, +remaining: Nat, +index: Nat,
  +min_x: Nat, +min_z: Nat, +columns: Nat, +step: Nat,
  blocks: Array<U32>
) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      +sample_x = Nat.mod(index, columns)
      +sample_z = Nat.div(index, columns)
      +x = Nat.add(min_x, Nat.mul(sample_x, step))
      +z = Nat.add(min_z, Nat.mul(sample_z, step))
      +height = World.column_height(seed, x, z)
      +water = World.water_at(seed, x, World.sea_level(), z)
      +surface = Bool.pick(U32, water, U32.add(U32.from_nat(World.sea_level()), 33), U32.from_nat(height))
      updated = blocks[U32.from_nat(index)] <- surface
      surface_grid.fill(seed, p, Nat.add(index, 1n), min_x, min_z, columns, step, updated)

def surface_grid(
  +seed: Nat, +min_x: Nat, +min_z: Nat,
  +columns: Nat, +rows: Nat, +step: Nat
) -> Array<U32>:
  +cells = Nat.mul(columns, rows)
  +depth = array_depth()
  surface_grid.fill(seed, cells, 0n, min_x, min_z, columns, step, Array.new(U32, depth, 0))

type SurfacePoint is Data:
  SurfacePoint{x: Nat, z: Nat}

def surface_points.fill(
  +seed: Nat, +remaining: Nat, +index: Nat,
  points: List<&2, SurfacePoint>, blocks: Array<U32>
) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      match points:
        case Nil{}:
          blocks
        case Con{+head, +tail}:
          SurfacePoint{+x, +z} = head
          +height = World.column_height(seed, x, z)
          +water = World.water_at(seed, x, World.sea_level(), z)
          +surface = Bool.pick(U32, water, U32.add(U32.from_nat(World.sea_level()), 33), U32.from_nat(height))
          updated = blocks[U32.from_nat(index)] <- surface
          surface_points.fill(seed, p, Nat.add(index, 1n), tail, updated)

def surface_points(
  +seed: Nat, +count: Nat, points: List<&2, SurfacePoint>
) -> Array<U32>:
  surface_points.fill(seed, count, 0n, points, Array.new(U32, array_depth(), 0))

# ---------------------------------------------------------------------------
# Distant terrain (LOD) samples
#
# The browser draws terrain far beyond the streamed chunks as coarse columns,
# in the spirit of the Distant Horizons mod. Each sampled column is described
# by one U32 so a whole tile crosses the worker boundary as one array:
#
#   bits  0..7   ground height (the y of the ground's top face)
#   bits  8..15  ground surface block (6 sand, 3 grass)
#   bits 16..23  canopy top face y, or 0 when no leaves cover the column
#   bit  24      sea water covers the ground (surface at sea level + 1)
#
# Surface and canopy follow the chunk rule: sand on beaches, shores and in the
# desert, grass elsewhere, and leaves only above y = 10.
# ---------------------------------------------------------------------------

def lod.canopy_layer(+t: World.Terms, +x: U32, +z: U32, +cx: U32, +cz: U32) -> U32:
  +biome = World.biome32(t, cx, cz)
  +h = World.height32.with_biome(t, cx, cz, biome)
  +tree = World.tree32(t, cx, cz, h, biome, World.mix32(World.terms.mix(t), cx, cz))
  +plus = Bool.or(U32.is_eq(cx, x), U32.is_eq(cz, z))
  +top = Bool.pick(U32, plus, (h + 3 : U32), (h + 2 : U32))
  Bool.pick(U32, Bool.and(tree, U32.is_gt(top, 10)), top, 0)

def lod.canopy(+t: World.Terms, +x: U32, +z: U32) -> U32:
  +xm = World.sat_sub32(x, 1)
  +xp = (x + 1 : U32)
  +zm = World.sat_sub32(z, 1)
  +zp = (z + 1 : U32)
  +west = U32.max(lod.canopy_layer(t, x, z, xm, zm), U32.max(lod.canopy_layer(t, x, z, xm, z), lod.canopy_layer(t, x, z, xm, zp)))
  +middle = U32.max(lod.canopy_layer(t, x, z, x, zm), U32.max(lod.canopy_layer(t, x, z, x, z), lod.canopy_layer(t, x, z, x, zp)))
  +east = U32.max(lod.canopy_layer(t, x, z, xp, zm), U32.max(lod.canopy_layer(t, x, z, xp, z), lod.canopy_layer(t, x, z, xp, zp)))
  U32.max(west, U32.max(middle, east))

def lod.column(+t: World.Terms, +x: U32, +z: U32) -> U32:
  +biome = World.biome32(t, x, z)
  +h = World.height32.with_biome(t, x, z, biome)
  +desert = U32.is_eq(biome, 2)
  +shore = World.chunk32.shore(t, x, z, h, Bool.and(U32.is_eq(h, 8), Bool.not(desert)))
  +sand = Bool.or(U32.is_le(h, 7), Bool.or(desert, shore))
  +water = U32.is_le(h, 7)
  +canopy = lod.canopy(t, x, z)
  +canopy_face = Bool.pick(U32, U32.is_gt(canopy, 0), (canopy + 1 : U32), 0)
  +surface = Bool.pick(U32, sand, 6, 3)
  (h + surface * 256 + canopy_face * 65536 + Bool.pick(U32, water, 16777216, 0) : U32)

def lod_points.fill(
  +t: World.Terms, +remaining: Nat, +index: U32,
  points: List<&2, SurfacePoint>, blocks: Array<U32>
) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      match points:
        case Nil{}:
          blocks
        case Con{+head, +tail}:
          SurfacePoint{+x, +z} = head
          updated = blocks[index] <- lod.column(t, U32.from_nat(x), U32.from_nat(z))
          lod_points.fill(t, p, (index + 1 : U32), tail, updated)

# One encoded column per point, in list order. At most 8192 points per call.
def lod_points(+seed: Nat, +count: Nat, points: List<&2, SurfacePoint>) -> Array<U32>:
  lod_points.fill(World.terms(seed), count, 0, points, Array.new(U32, array_depth(), 0))
