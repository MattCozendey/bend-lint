import Base
import ./world.bend as World
import ./lightflood.bend as Flood

type Edit is Data:
  Edit{x: Nat, y: Nat, z: Nat, block: U32}

type Point is Data:
  Point{x: Nat, y: Nat, z: Nat}

type LightField is Data:
  Field{x: Nat, y: Nat, z: Nat, light: U32}

type Cell is Data:
  Cell{x: Nat, y: Nat, z: Nat}

type LightCell is Data:
  LightCell{x: Nat, y: Nat, z: Nat, light: U32}

def max_light() -> U32:
  15

def source(+x: Nat, +y: Nat, +z: Nat) -> Edit:
  Edit{x, y, z, 12}

def lava_source(+x: Nat, +y: Nat, +z: Nat) -> Edit:
  Edit{x, y, z, 21}

def is_light_source(+block: U32) -> Bool:
  Bool.or(U32.is_eq(block, 12), U32.is_eq(block, 21))

def cave_ambient(+y: Nat) -> U32:
  U32.from_nat(Nat.min(12n, Nat.add(3n, Nat.div(y, 2n))))

def distance_component(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_ge(a, b), Nat.sub(a, b), Nat.sub(b, a))

# Generated terrain below the surface is never air and never an open door, and
# sea water only sits at or above the surface, so a generated cell is opaque
# exactly when it is below the surface and is neither cave nor lava. This is the
# wall test of every torch flood (1024 cells per source), so it runs in U32.
def opaque32(+t: World.Terms, +x: U32, +y: U32, +z: U32) -> Bool:
  +h = World.height32(t, x, z)
  +mixed = World.mix32(World.terms.mix(t), x, z)
  +cave = Bool.and(Bool.and(U32.is_gt(y, 1), U32.is_lt((y + 2 : U32), h)),
    U32.is_eq(U32.mod((mixed + y * 17 : U32), 43), 0))
  +lava = Bool.and(Bool.and(U32.is_gt(y, 1), U32.is_le(y, 3)),
    U32.is_eq(U32.mod((mixed + y * 13 : U32), 29), 0))
  Bool.and(U32.is_lt(y, h), Bool.not(Bool.or(cave, lava)))

def opaque(+seed: Nat, point: Point) -> Bool:
  Point{+x, +y, +z} = point
  opaque32(World.terms(seed), U32.from_nat(x), U32.from_nat(y), U32.from_nat(z))

def axis_coord(point: Point, +axis: U32) -> Nat:
  Point{+x, +y, +z} = point
  Bool.pick(Nat, U32.is_eq(axis, 0), x,
    Bool.pick(Nat, U32.is_eq(axis, 1), y, z))

def move_coord(+current: Nat, +forward: Bool) -> Nat:
  Bool.pick(Nat, forward, Nat.add(current, 1n), Nat.sub(current, 1n))

def move_point(point: Point, target: Point, +axis: U32, +forward: Bool) -> Point:
  Point{+x, +y, +z} = point
  Point{+tx, +ty, +tz} = target
  +on_x = U32.is_eq(axis, 0)
  +on_y = U32.is_eq(axis, 1)
  Point{
    Bool.pick(Nat, on_x, move_coord(x, forward), x),
    Bool.pick(Nat, on_y, move_coord(y, forward), y),
    Bool.pick(Nat, Bool.or(on_x, on_y), z, move_coord(z, forward))
  }

def clear_path(
  +seed: Nat, +remaining: Nat, +current: Point, +target: Point, +axis: U32, +forward: Bool,
  +same: Bool
) -> Bool:
  match remaining:
    case 0n:
      False{}
    case 1n+p:
      match same:
        case True{}:
          True{}
        case False{}:
          +next = move_point(current, target, axis, forward)
          Bool.and(Bool.not(opaque(seed, next)),
            clear_path(seed, p, next, target, axis, forward,
              Nat.is_eq(axis_coord(next, axis), axis_coord(target, axis))))

def path_clear(+seed: Nat, +current: Point, +target: Point, +axis: U32, +forward: Bool) -> Bool:
  clear_path(seed, 16n, current, target, axis, forward,
    Nat.is_eq(axis_coord(current, axis), axis_coord(target, axis)))

def make_point(x: Nat, y: Nat, z: Nat) -> Point:
  Point{x, y, z}

def source_visible(+seed: Nat, +sx: Nat, +sy: Nat, +sz: Nat, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  +source_point = make_point(sx, sy, sz)
  +x_point = make_point(x, sy, sz)
  +y_point = make_point(x, y, sz)
  +z_point = make_point(sx, sy, z)
  +yz_point = make_point(sx, y, z)
  +target = make_point(x, y, z)
  +canonical = Bool.and(
    Bool.and(path_clear(seed, source_point, x_point, 0, Nat.is_lt(sx, x)),
      path_clear(seed, x_point, y_point, 1, Nat.is_lt(sy, y))),
    path_clear(seed, y_point, target, 2, Nat.is_lt(sz, z)))
  +alternate = Bool.and(
    Bool.and(path_clear(seed, source_point, z_point, 2, Nat.is_lt(sz, z)),
      path_clear(seed, z_point, yz_point, 1, Nat.is_lt(sy, y))),
    path_clear(seed, yz_point, target, 0, Nat.is_lt(sx, x)))
  Bool.or(canonical, alternate)

def near_sources(sources: List<&2, Edit>, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Edit>:
  match sources:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Edit{+sx, +sy, +sz, block} = head
      +distance = Nat.add(Nat.add(distance_component(sx, x), distance_component(sy, y)), distance_component(sz, z))
      +rest = near_sources(tail, x, y, z)
      Bool.pick(List<&2, Edit>, Nat.is_lt(distance, 15n), Con{head, rest}, rest)

def window_walls(
  +remaining: Nat, +index: Nat, +seed: Nat, +y: Nat,
  +base_x: Nat, +base_z: Nat, +walls: List<&2, Flood.Wall>
) -> List<&2, Flood.Wall>:
  match remaining:
    case 0n:
      walls
    case 1n+p:
      +z = Nat.div(index, 32n)
      +x = Nat.mod(index, 32n)
      +global_x = Nat.add(base_x, x)
      +global_z = Nat.add(base_z, z)
      +blocked = opaque(seed, make_point(global_x, y, global_z))
      +next = Bool.pick(List<&2, Flood.Wall>, blocked, Con{Flood.Wall{x, z}, walls}, walls)
      window_walls(p, Nat.add(index, 1n), seed, y, base_x, base_z, next)

# The flood window as one array, index x + 32 z: 1 where generated terrain is
# opaque at the source's height. Same cells and order as `window_walls`.
def window_grid(
  +remaining: Nat, +index: U32, +t: World.Terms, +y: U32,
  +base_x: U32, +base_z: U32, grid: Array<U32>
) -> Array<U32>:
  match remaining:
    case 0n:
      grid
    case 1n+p:
      +x = (base_x + U32.mod(index, 32) : U32)
      +z = (base_z + U32.div(index, 32) : U32)
      updated = grid[index] <- Bool.pick(U32, opaque32(t, x, y, z), 1, 0)
      window_grid(p, (index + 1 : U32), t, y, base_x, base_z, updated)

def make_field(x: Nat, y: Nat, z: Nat, light: U32) -> LightField:
  Field{x, y, z, light}

def fields_from_cells(
  cells: List<&2, Flood.Cell>, +base_x: Nat, +y: Nat, +base_z: Nat
) -> List<&2, LightField>:
  match cells:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Flood.Cell{+x, +z, +light} = head
      make_field(Nat.add(base_x, x), y, Nat.add(base_z, z), light)
        <> fields_from_cells(tail, base_x, y, base_z)

def lava_fields.one(source: Edit) -> List<&2, LightField>:
  Edit{+x, +y, +z, block} = source
  Con{
    Field{x, y, z, 15},
    Con{
      Field{Nat.add(x, 1n), y, z, 14},
      Con{
        Field{Nat.sub(x, 1n), y, z, 14},
        Con{
          Field{x, y, Nat.add(z, 1n), 14},
          Con{Field{x, y, Nat.sub(z, 1n), 14}, Nil{}}
        }
      }
    }
  }

def source_fields.one.if(
  source: Edit, +seed: Nat, is_lava: Bool
) -> List<&2, LightField>:
  Edit{+sx, +sy, +sz, +block} = source
  match is_lava:
    case True{}:
      lava_fields.one(source)
    case False{}:
      +base_x = Nat.sub(sx, 14n)
      +base_z = Nat.sub(sz, 14n)
      walls = window_grid(1024n, 0, World.terms(seed), U32.from_nat(sy), U32.from_nat(base_x), U32.from_nat(base_z), Array.new(U32, 10n, 0))
      +local_x = Nat.sub(sx, base_x)
      +local_z = Nat.sub(sz, base_z)
      +source_cell = Bool.pick(Flood.Cell, U32.is_eq(block, 21), Flood.lava_source(local_x, local_z), Flood.source(local_x, local_z))
      +cells = Flood.run_grid(source_cell, walls)
      fields_from_cells(cells, base_x, sy, base_z)

def source_fields.one(source: Edit, +seed: Nat) -> List<&2, LightField>:
  Edit{x, y, z, +block} = source
  source_fields.one.if(source, seed, U32.is_eq(block, 21))

def source_fields_one(source: Edit, +seed: Nat) -> List<&2, LightField>:
  source_fields.one(source, seed)

# A flood fill is the most expensive thing in this module, and a chunk only
# needs the sources within reach of it. `Bool.pick` evaluates both branches, so
# selecting a source must go through a match to skip the flood of the rest.
def source_fields.one.when(source: Edit, +seed: Nat, wanted: Bool) -> List<&2, LightField>:
  match wanted:
    case True{}:
      source_fields.one(source, seed)
    case False{}:
      Nil{}

def append_fields(
  fields: List<&2, LightField>, tail: List<&2, LightField>
) -> List<&2, LightField>:
  match fields:
    case Nil{}:
      tail
    case Con{+head, +rest}:
      Con{head, append_fields(rest, tail)}

def source_fields(sources: List<&2, Edit>, +seed: Nat) -> List<&2, LightField>:
  match sources:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Edit{+x, +y, +z, +block} = head
      +rest = source_fields(tail, seed)
      append_fields(source_fields.one.when(head, seed, is_light_source(block)), rest)

def source_relevant(source: Edit, +chunk_x: Nat, +chunk_z: Nat) -> Bool:
  Edit{+x, +y, +z, block} = source
  +base_x = Nat.mul(chunk_x, 16n)
  +base_z = Nat.mul(chunk_z, 16n)
  +end_x = Nat.add(base_x, 16n)
  +end_z = Nat.add(base_z, 16n)
  Bool.and(
    Bool.and(Nat.is_ge(Nat.add(x, 14n), base_x), Nat.is_lt(x, Nat.add(end_x, 14n))),
    Bool.and(Nat.is_ge(Nat.add(z, 14n), base_z), Nat.is_lt(z, Nat.add(end_z, 14n)))
  )

def source_fields.chunk(
  sources: List<&2, Edit>, +seed: Nat, +chunk_x: Nat, +chunk_z: Nat
) -> List<&2, LightField>:
  match sources:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Edit{+x, +y, +z, +block} = head
      +rest = source_fields.chunk(tail, seed, chunk_x, chunk_z)
      +relevant = Bool.and(is_light_source(block), source_relevant(head, chunk_x, chunk_z))
      append_fields(source_fields.one.when(head, seed, relevant), rest)

def source_relevant.keep(source: Edit, +chunk_x: Nat, +chunk_z: Nat) -> Bool:
  Edit{+x, +y, +z, +block} = source
  Bool.and(is_light_source(block), source_relevant(source, chunk_x, chunk_z))

# The sources whose flood can reach a chunk, in `source_fields.chunk` order. A
# caller that caches `source_fields_one` per source (a flood only depends on the
# seed and the source) appends their fields in this order and hands them to
# `chunk_with_fields`.
def relevant_sources(
  sources: List<&2, Edit>, +chunk_x: Nat, +chunk_z: Nat
) -> List<&2, Edit>:
  match sources:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      +rest = relevant_sources(tail, chunk_x, chunk_z)
      Bool.pick(List<&2, Edit>, source_relevant.keep(head, chunk_x, chunk_z), Con{head, rest}, rest)

def source_fields_chunk(
  sources: List<&2, Edit>, +seed: Nat, +chunk_x: Nat, +chunk_z: Nat
) -> List<&2, LightField>:
  source_fields.chunk(sources, seed, chunk_x, chunk_z)

def field_light(fields: List<&2, LightField>, +x: Nat, +y: Nat, +z: Nat, +best: U32) -> U32:
  match fields:
    case Nil{}:
      best
    case Con{+head, +tail}:
      Field{+fx, +fy, +fz, +light} = head
      +same = Bool.and(Bool.and(Nat.is_eq(fx, x), Nat.is_eq(fy, y)), Nat.is_eq(fz, z))
      field_light(tail, x, y, z, Bool.pick(U32, same, U32.max(best, light), best))

def empty_edits() -> List<&2, Edit>:
  Nil{}

def base_light(+seed: Nat, +x: Nat, +y: Nat, +z: Nat) -> U32:
  +height = World.column_height(seed, x, z)
  +above_surface = Nat.is_ge(y, height)
  +cave = World.cave_at_height(seed, x, y, z, height)
  +water = World.water_at_height(height, y)
  +lava = World.lava_at(seed, x, y, z)
  +transparent = Bool.or(cave, water)
  +sky = Bool.pick(U32, above_surface, max_light(), Bool.pick(U32, transparent, cave_ambient(y), 0))
  Bool.pick(U32, lava, max_light(), sky)

def static_with_fields(fields: List<&2, LightField>, +seed: Nat, +x: Nat, +y: Nat, +z: Nat) -> U32:
  U32.max(base_light(seed, x, y, z), field_light(fields, x, y, z, 0))

def make_light_cell(x: Nat, y: Nat, z: Nat, light: U32) -> LightCell:
  LightCell{x, y, z, light}

def patch_cells(
  +fields: List<&2, LightField>, +seed: Nat, +cells: List<&2, Cell>
) -> List<&2, LightCell>:
  match cells:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Cell{+x, +y, +z} = head
      make_light_cell(x, y, z, static_with_fields(fields, seed, x, y, z))
        <> patch_cells(fields, seed, tail)

def patch(+sources: List<&2, Edit>, +seed: Nat, cells: List<&2, Cell>) -> List<&2, LightCell>:
  patch_cells(source_fields(sources, seed), seed, cells)

def patch_fields(
  +fields: List<&2, LightField>, +seed: Nat, +cells: List<&2, Cell>
) -> List<&2, LightCell>:
  patch_cells(fields, seed, cells)

def chunk.value.fields(
  fields: List<&2, LightField>, +seed: Nat, +chunk_x: Nat, +chunk_z: Nat, +index: Nat
) -> U32:
  +column = Nat.mul(World.chunk_size(), World.chunk_size())
  +y = Nat.div(index, column)
  +in_column = Nat.mod(index, column)
  +z = Nat.div(in_column, World.chunk_size())
  +x = Nat.mod(in_column, World.chunk_size())
  +global_x = Nat.add(Nat.mul(chunk_x, World.chunk_size()), x)
  +global_z = Nat.add(Nat.mul(chunk_z, World.chunk_size()), z)
  static_with_fields(fields, seed, global_x, y, global_z)

def chunk.fill.fields(
  +fields: List<&2, LightField>, +seed: Nat, +chunk_x: Nat, +chunk_z: Nat,
  +remaining: Nat, +index: Nat, blocks: Array<U32>
) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      chunk.fill.fields(fields, seed, chunk_x, chunk_z, p, Nat.add(index, 1n),
        blocks[U32.from_nat(index)] <- chunk.value.fields(fields, seed, chunk_x, chunk_z, index))

def source_light(sources: List<&2, Edit>, +seed: Nat, +x: Nat, +y: Nat, +z: Nat, +best: U32) -> U32:
  match sources:
    case Nil{}:
      best
    case Con{+head, +tail}:
      Edit{+sx, +sy, +sz, +block} = head
      +distance = Nat.add(Nat.add(distance_component(sx, x), distance_component(sy, y)), distance_component(sz, z))
      +within = Nat.is_lt(distance, 15n)
      +emission = Bool.pick(Nat, U32.is_eq(block, 21), 15n, 14n)
      +level = Nat.sub(emission, distance)
      +visible = Bool.pick(Bool, within, source_visible(seed, sx, sy, sz, x, y, z), False{})
      +candidate = Bool.pick(U32, Bool.and(Bool.and(within, visible), is_light_source(block)), U32.from_nat(level), 0)
      source_light(tail, seed, x, y, z, U32.max(best, candidate))

def block(sources: List<&2, Edit>, +seed: Nat, +x: Nat, +y: Nat, +z: Nat) -> U32:
  +height = World.column_height(seed, x, z)
  +above_surface = Nat.is_ge(y, height)
  +cave = World.cave_at_height(seed, x, y, z, height)
  +water = World.water_at_height(height, y)
  +transparent = Bool.or(cave, water)
  +sky = Bool.pick(U32, above_surface, max_light(), Bool.pick(U32, transparent, cave_ambient(y), 0))
  +near = near_sources(sources, x, y, z)
  U32.max(sky, source_light(near, seed, x, y, z, 0))

# ---------------------------------------------------------------------------
# Column-ordered chunk light
#
# The per-cell rules above ask, for every cell, whether every cell above it is
# open (`sky_visible`) and scan the whole edit list and the whole field list.
# A chunk is filled here one column at a time from the top down, so the sky
# test becomes a running flag, the edit scan only sees the edits inside this
# chunk's columns, and the torch fields are pre-binned into the output array.
# The values are those of `chunk.value.with_edits` and `chunk.value`; the
# golden fingerprints in `tests/world-chunk-golden.test.mjs` pin them.
# ---------------------------------------------------------------------------

def light32.cave_ambient(+y: U32) -> U32:
  U32.min(12, (3 + U32.div(y, 2) : U32))

def light32.cave(+h: U32, +mixed: U32, +y: U32) -> Bool:
  Bool.and(Bool.and(U32.is_gt(y, 1), U32.is_lt((y + 2 : U32), h)),
    U32.is_eq(U32.mod((mixed + y * 17 : U32), 43), 0))

def light32.water(+h: U32, +y: U32) -> Bool:
  Bool.and(U32.is_le(h, y), U32.is_lt(y, 8))

def light32.lava(+h: U32, +mixed: U32, +y: U32) -> Bool:
  Bool.and(Bool.and(Bool.and(U32.is_gt(y, 1), U32.is_le(y, 3)), U32.is_lt(y, h)),
    U32.is_eq(U32.mod((mixed + y * 13 : U32), 29), 0))

# Generated terrain below the surface is never air and never an open door, so
# `opaque` reduces to "below the surface and neither cave nor lava".
# The source-free, edit-free rule (`block` with no sources): sunlight above the
# surface, cave ambient in open caves and water, and no generated lava term.
def light32.sky.column(
  +h: U32, +mixed: U32, +offset: U32, +remaining: Nat, +y: U32, blocks: Array<U32>
) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      +transparent = Bool.or(light32.cave(h, mixed, y), light32.water(h, y))
      +value = Bool.pick(U32, U32.is_ge(y, h), 15, Bool.pick(U32, transparent, light32.cave_ambient(y), 0))
      +index = (offset + y * 256 : U32)
      updated = blocks[index] <- value
      light32.sky.column(h, mixed, offset, p, (y + 1 : U32), updated)

def light32.sky.columns.x(
  +t: World.Terms, +base_x: U32, +base_z: U32,
  +remaining: Nat, +local_x: U32, +local_z: U32, blocks: Array<U32>
) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      +x = (base_x + local_x : U32)
      +z = (base_z + local_z : U32)
      +h = World.height32(t, x, z)
      +mixed = World.mix32(World.terms.mix(t), x, z)
      light32.sky.columns.x(t, base_x, base_z, p, (local_x + 1 : U32), local_z,
        light32.sky.column(h, mixed, (local_x + local_z * 16 : U32), World.max_y(), 0, blocks))

def light32.sky.columns.z(
  +t: World.Terms, +base_x: U32, +base_z: U32,
  +remaining: Nat, +local_z: U32, blocks: Array<U32>
) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      light32.sky.columns.z(t, base_x, base_z, p, (local_z + 1 : U32),
        light32.sky.columns.x(t, base_x, base_z, World.chunk_size(), 0, local_z, blocks))

def light32.sky_chunk(+seed: Nat, +chunk_x: Nat, +chunk_z: Nat) -> Array<U32>:
  light32.sky.columns.z(World.terms(seed),
    U32.from_nat(Nat.mul(chunk_x, World.chunk_size())), U32.from_nat(Nat.mul(chunk_z, World.chunk_size())),
    World.chunk_size(), 0, Array.new(U32, 14n, 0))

def chunk_cells() -> Nat:
  Nat.mul(Nat.mul(World.chunk_size(), World.chunk_size()), World.max_y())

def chunk.value(+sources: List<&2, Edit>, +seed: Nat, +chunk_x: Nat, +chunk_z: Nat, +index: Nat) -> U32:
  +column = Nat.mul(World.chunk_size(), World.chunk_size())
  +y = Nat.div(index, column)
  +in_column = Nat.mod(index, column)
  +z = Nat.div(in_column, World.chunk_size())
  +x = Nat.mod(in_column, World.chunk_size())
  +global_x = Nat.add(Nat.mul(chunk_x, World.chunk_size()), x)
  +global_z = Nat.add(Nat.mul(chunk_z, World.chunk_size()), z)
  block(sources, seed, global_x, y, global_z)

def chunk.fill(+sources: List<&2, Edit>, +seed: Nat, +chunk_x: Nat, +chunk_z: Nat, +remaining: Nat, +index: Nat, blocks: Array<U32>) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      chunk.fill(sources, seed, chunk_x, chunk_z, p, Nat.add(index, 1n), blocks[U32.from_nat(index)] <- chunk.value(sources, seed, chunk_x, chunk_z, index))

def chunk(+sources: List<&2, Edit>, +seed: Nat, +chunk_x: Nat, +chunk_z: Nat) -> Array<U32>:
  match sources:
    case Nil{}:
      light32.sky_chunk(seed, chunk_x, chunk_z)
    case Con{head, tail}:
      +fields = source_fields.chunk(sources, seed, chunk_x, chunk_z)
      chunk.fill.fields(fields, seed, chunk_x, chunk_z, chunk_cells(), 0n, Array.new(U32, 14n, 0))

type EditOverride is Data:
  EditFound{block: U32}
  EditMissing{}

def edit_matches(edit: Edit, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Edit{+ex, +ey, +ez, block} = edit
  Bool.and(Bool.and(Nat.is_eq(ex, x), Nat.is_eq(ey, y)), Nat.is_eq(ez, z))

def edit_block(edit: Edit) -> U32:
  Edit{x, y, z, +block} = edit
  block

# The first edit of (x, y, z), in one tail-recursive pass that stops there.
def edit_override.go(
  edits: List<&2, Edit>, stop: Bool, +x: Nat, +y: Nat, +z: Nat, +found: EditOverride
) -> EditOverride:
  match edits stop:
    case _ True{}:
      found
    case Nil{} False{}:
      found
    case Con{+head, tail} False{}:
      +same = edit_matches(head, x, y, z)
      edit_override.go(tail, same, x, y, z, Bool.pick(EditOverride, same, EditFound{edit_block(head)}, found))

def edit_override(edits: List<&2, Edit>, +x: Nat, +y: Nat, +z: Nat) -> EditOverride:
  edit_override.go(edits, False{}, x, y, z, EditMissing{})

def transparent_block(+block: U32) -> Bool:
  Bool.or(
    U32.is_eq(block, 0),
    Bool.or(
      U32.is_eq(block, 7),
      Bool.or(
        U32.is_eq(block, 12),
        Bool.or(
          U32.is_eq(block, 15),
          Bool.or(U32.is_eq(block, 21), U32.is_eq(block, 24))
        )
      )
    )
  )

def opaque_override(override: EditOverride, +seed: Nat, point: Point) -> Bool:
  match override:
    case EditMissing{}:
      opaque(seed, point)
    case EditFound{+block}:
      Bool.not(transparent_block(block))

def opaque_with_edits(edits: List<&2, Edit>, +seed: Nat, point: Point) -> Bool:
  Point{+x, +y, +z} = point
  opaque_override(edit_override(edits, x, y, z), seed, point)

def transparent_override(override: EditOverride, +seed: Nat, point: Point) -> Bool:
  match override:
    case EditMissing{}:
      Point{+x, +y, +z} = point
      Bool.or(World.cave_at_height(seed, x, y, z, World.column_height(seed, x, z)),
        World.water_at_height(World.column_height(seed, x, z), y))
    case EditFound{+block}:
      transparent_block(block)

def transparent_at(edits: List<&2, Edit>, +seed: Nat, point: Point) -> Bool:
  Point{+x, +y, +z} = point
  transparent_override(edit_override(edits, x, y, z), seed, point)

def lava_override(override: EditOverride, +seed: Nat, point: Point) -> Bool:
  match override:
    case EditMissing{}:
      Point{+x, +y, +z} = point
      World.lava_at(seed, x, y, z)
    case EditFound{+block}:
      U32.is_eq(block, 21)

def lava_at(edits: List<&2, Edit>, +seed: Nat, point: Point) -> Bool:
  Point{+x, +y, +z} = point
  lava_override(edit_override(edits, x, y, z), seed, point)

# Whether the `remaining` cells from (x, y, z) up are all clear. `blocked` is
# whether (x, y, z) itself is opaque; the walk stops at the first opaque cell,
# so a cell under the ground costs one step instead of the whole column.
def sky_visible.go(
  +edits: List<&2, Edit>, +seed: Nat, +remaining: Nat, blocked: Bool, +x: Nat, +y: Nat, +z: Nat
) -> Bool:
  match remaining blocked:
    case 0n _:
      True{}
    case 1n+p True{}:
      False{}
    case 1n+p False{}:
      +next = Nat.add(y, 1n)
      sky_visible.go(edits, seed, p, opaque_with_edits(edits, seed, make_point(x, next, z)), x, next, z)

def sky_visible(
  +edits: List<&2, Edit>, +seed: Nat, +remaining: Nat, +x: Nat, +y: Nat, +z: Nat
) -> Bool:
  sky_visible.go(edits, seed, remaining, opaque_with_edits(edits, seed, make_point(x, y, z)), x, y, z)

def base_light_with_edits(
  +edits: List<&2, Edit>, +seed: Nat, +x: Nat, +y: Nat, +z: Nat
) -> U32:
  +point = make_point(x, y, z)
  +transparent = transparent_at(edits, seed, point)
  +sky = Bool.pick(U32, sky_visible(edits, seed, Nat.sub(World.max_y(), y), x, y, z),
    max_light(), Bool.pick(U32, transparent, cave_ambient(y), 0))
  Bool.pick(U32, lava_at(edits, seed, point), max_light(), sky)

def static_with_fields_with_edits(
  fields: List<&2, LightField>, edits: List<&2, Edit>, +seed: Nat,
  +x: Nat, +y: Nat, +z: Nat
) -> U32:
  U32.max(base_light_with_edits(edits, seed, x, y, z), field_light(fields, x, y, z, 0))

def patch_cells_with_edits(
  +fields: List<&2, LightField>, +edits: List<&2, Edit>, +seed: Nat,
  +cells: List<&2, Cell>
) -> List<&2, LightCell>:
  match cells:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Cell{+x, +y, +z} = head
      make_light_cell(x, y, z, static_with_fields_with_edits(fields, edits, seed, x, y, z))
        <> patch_cells_with_edits(fields, edits, seed, tail)

def patch_fields_with_edits(
  +fields: List<&2, LightField>, edits: List<&2, Edit>, +seed: Nat,
  +cells: List<&2, Cell>
) -> List<&2, LightCell>:
  match edits:
    case Nil{}:
      patch_fields(fields, seed, cells)
    case Con{head, tail}:
      patch_cells_with_edits(fields, edits, seed, cells)

def chunk.value.with_edits(
  +fields: List<&2, LightField>, edits: List<&2, Edit>, +seed: Nat,
  +chunk_x: Nat, +chunk_z: Nat, +index: Nat
) -> U32:
  +column = Nat.mul(World.chunk_size(), World.chunk_size())
  +y = Nat.div(index, column)
  +in_column = Nat.mod(index, column)
  +z = Nat.div(in_column, World.chunk_size())
  +x = Nat.mod(in_column, World.chunk_size())
  +global_x = Nat.add(Nat.mul(chunk_x, World.chunk_size()), x)
  +global_z = Nat.add(Nat.mul(chunk_z, World.chunk_size()), z)
  static_with_fields_with_edits(fields, edits, seed, global_x, y, global_z)

def chunk.fill.with_edits(
  +fields: List<&2, LightField>, +edits: List<&2, Edit>, +seed: Nat,
  +chunk_x: Nat, +chunk_z: Nat, +remaining: Nat, +index: Nat, blocks: Array<U32>
) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      chunk.fill.with_edits(
        fields, edits, seed, chunk_x, chunk_z, p, Nat.add(index, 1n),
        blocks[U32.from_nat(index)] <- chunk.value.with_edits(fields, edits, seed, chunk_x, chunk_z, index)
      )

def light32.opaque(+h: U32, +mixed: U32, +y: U32, override: EditOverride) -> Bool:
  match override:
    case EditMissing{}:
      Bool.and(U32.is_lt(y, h), Bool.not(Bool.or(light32.cave(h, mixed, y), light32.lava(h, mixed, y))))
    case EditFound{+block}:
      Bool.not(transparent_block(block))

def light32.transparent(+h: U32, +mixed: U32, +y: U32, override: EditOverride) -> Bool:
  match override:
    case EditMissing{}:
      Bool.or(light32.cave(h, mixed, y), light32.water(h, y))
    case EditFound{+block}:
      transparent_block(block)

def light32.is_lava(+h: U32, +mixed: U32, +y: U32, override: EditOverride) -> Bool:
  match override:
    case EditMissing{}:
      light32.lava(h, mixed, y)
    case EditFound{+block}:
      U32.is_eq(block, 21)

def light32.override(local: List<&2, Edit>, +x: U32, +y: U32, +z: U32) -> EditOverride:
  match local:
    case Nil{}:
      EditMissing{}
    case Con{+head, +tail}:
      edit_override(Con{head, tail}, U32.to_nat(x), U32.to_nat(y), U32.to_nat(z))

def light32.keep_edit(edit: Edit, +base_x: Nat, +base_z: Nat) -> Bool:
  Edit{+x, +y, +z, block} = edit
  Bool.and(
    Bool.and(Nat.is_ge(x, base_x), Nat.is_lt(x, Nat.add(base_x, 16n))),
    Bool.and(Nat.is_ge(z, base_z), Nat.is_lt(z, Nat.add(base_z, 16n)))
  )

# Every lookup a chunk cell makes is in its own column, so the edits outside
# the chunk's columns can never match and are dropped once per chunk.
# The filters below walk the whole persistent edit list, so they are tail
# recursive (a loop on the JavaScript target) and keep the list's order.
def light32.local_edits.go(
  edits: List<&2, Edit>, +base_x: Nat, +base_z: Nat, +acc: List<&2, Edit>
) -> List<&2, Edit>:
  match edits:
    case Nil{}:
      List.reverse.go(&2, Edit, acc, Nil{})
    case Con{+head, tail}:
      light32.local_edits.go(tail, base_x, base_z,
        Bool.pick(List<&2, Edit>, light32.keep_edit(head, base_x, base_z), Con{head, acc}, acc))

def light32.local_edits(edits: List<&2, Edit>, +base_x: Nat, +base_z: Nat) -> List<&2, Edit>:
  light32.local_edits.go(edits, base_x, base_z, Nil{})

def light32.put(+index: U32, +value: U32, read: Array<U32> & U32) -> Array<U32>:
  (blocks, current) = read
  blocks[index] <- U32.max(value, current)

def light32.bin_field(
  +local_x: Nat, +y: Nat, +local_z: Nat, +light: U32, blocks: Array<U32>, inside: Bool
) -> Array<U32>:
  match inside:
    case False{}:
      blocks
    case True{}:
      +index = U32.from_nat(Nat.add(local_x, Nat.mul(16n, Nat.add(local_z, Nat.mul(16n, y)))))
      light32.put(index, light, Array.get(U32, blocks, index))

# `field_light` is the maximum light of the fields at a cell. Folding every field
# that lands inside the chunk into the array once gives the same maximum.
def light32.bin_fields(
  fields: List<&2, LightField>, +base_x: Nat, +base_z: Nat, blocks: Array<U32>
) -> Array<U32>:
  match fields:
    case Nil{}:
      blocks
    case Con{+head, +tail}:
      Field{+x, +y, +z, +light} = head
      +inside = Bool.and(
        Bool.and(Bool.and(Nat.is_ge(x, base_x), Nat.is_lt(x, Nat.add(base_x, 16n))),
          Bool.and(Nat.is_ge(z, base_z), Nat.is_lt(z, Nat.add(base_z, 16n)))),
        Nat.is_lt(y, World.max_y())
      )
      light32.bin_fields(tail, base_x, base_z,
        light32.bin_field(Nat.sub(x, base_x), y, Nat.sub(z, base_z), light, blocks, inside))

# Top-down fill of one column. `sky` is true while every cell above is open,
# which is exactly `sky_visible` for the cell below.
def light32.column(
  +local: List<&2, Edit>, +h: U32, +mixed: U32, +x: U32, +z: U32,
  +offset: U32, +remaining: Nat, +sky: Bool, blocks: Array<U32>
) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      +y = U32.from_nat(p)
      +override = light32.override(local, x, y, z)
      +visible = Bool.and(sky, Bool.not(light32.opaque(h, mixed, y, override)))
      +ambient = Bool.pick(U32, light32.transparent(h, mixed, y, override), light32.cave_ambient(y), 0)
      +base = Bool.pick(U32, light32.is_lava(h, mixed, y, override), 15, Bool.pick(U32, visible, 15, ambient))
      +index = (offset + y * 256 : U32)
      light32.column(local, h, mixed, x, z, offset, p, visible,
        light32.put(index, base, Array.get(U32, blocks, index)))

def light32.columns.x(
  +local: List<&2, Edit>, +t: World.Terms, +base_x: U32, +base_z: U32,
  +remaining: Nat, +local_x: U32, +local_z: U32, blocks: Array<U32>
) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      +x = (base_x + local_x : U32)
      +z = (base_z + local_z : U32)
      +h = World.height32(t, x, z)
      +mixed = World.mix32(World.terms.mix(t), x, z)
      light32.columns.x(local, t, base_x, base_z, p, (local_x + 1 : U32), local_z,
        light32.column(local, h, mixed, x, z, (local_x + local_z * 16 : U32), World.max_y(), True{}, blocks))

def light32.columns.z(
  +local: List<&2, Edit>, +t: World.Terms, +base_x: U32, +base_z: U32,
  +remaining: Nat, +local_z: U32, blocks: Array<U32>
) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      light32.columns.z(local, t, base_x, base_z, p, (local_z + 1 : U32),
        light32.columns.x(local, t, base_x, base_z, World.chunk_size(), 0, local_z, blocks))

def light32.chunk(
  +fields: List<&2, LightField>, +local: List<&2, Edit>, +seed: Nat,
  +chunk_x: Nat, +chunk_z: Nat
) -> Array<U32>:
  +base_x = Nat.mul(chunk_x, World.chunk_size())
  +base_z = Nat.mul(chunk_z, World.chunk_size())
  binned = light32.bin_fields(fields, base_x, base_z, Array.new(U32, 14n, 0))
  light32.columns.z(local, World.terms(seed), U32.from_nat(base_x), U32.from_nat(base_z),
    World.chunk_size(), 0, binned)

def chunk_with_edits(
  sources: List<&2, Edit>, edits: List<&2, Edit>, +seed: Nat,
  +chunk_x: Nat, +chunk_z: Nat
) -> Array<U32>:
  match edits:
    case Nil{}:
      chunk(sources, seed, chunk_x, chunk_z)
    case Con{head, tail}:
      +fields = source_fields.chunk(sources, seed, chunk_x, chunk_z)
      +local = light32.local_edits(edits, Nat.mul(chunk_x, World.chunk_size()), Nat.mul(chunk_z, World.chunk_size()))
      light32.chunk(fields, local, seed, chunk_x, chunk_z)

# `chunk_with_edits` with the source fields supplied by the caller. `fields` must
# be the fields of `relevant_sources(light_sources(edits), chunk_x, chunk_z)`.
def chunk_with_fields(
  +fields: List<&2, LightField>, edits: List<&2, Edit>, +seed: Nat,
  +chunk_x: Nat, +chunk_z: Nat
) -> Array<U32>:
  match edits:
    case Nil{}:
      light32.sky_chunk(seed, chunk_x, chunk_z)
    case Con{head, tail}:
      +local = light32.local_edits(edits, Nat.mul(chunk_x, World.chunk_size()), Nat.mul(chunk_z, World.chunk_size()))
      light32.chunk(fields, local, seed, chunk_x, chunk_z)

def light32.keep_edit_box(edit: Edit, +min_x: Nat, +min_z: Nat, +max_x: Nat, +max_z: Nat) -> Bool:
  Edit{+x, +y, +z, block} = edit
  Bool.and(
    Bool.and(Nat.is_ge(x, min_x), Nat.is_le(x, max_x)),
    Bool.and(Nat.is_ge(z, min_z), Nat.is_le(z, max_z))
  )

def light32.box_edits.go(
  edits: List<&2, Edit>, +min_x: Nat, +min_z: Nat, +max_x: Nat, +max_z: Nat, +acc: List<&2, Edit>
) -> List<&2, Edit>:
  match edits:
    case Nil{}:
      List.reverse.go(&2, Edit, acc, Nil{})
    case Con{+head, tail}:
      light32.box_edits.go(tail, min_x, min_z, max_x, max_z,
        Bool.pick(List<&2, Edit>, light32.keep_edit_box(head, min_x, min_z, max_x, max_z), Con{head, acc}, acc))

def light32.box_edits(
  edits: List<&2, Edit>, +min_x: Nat, +min_z: Nat, +max_x: Nat, +max_z: Nat
) -> List<&2, Edit>:
  light32.box_edits.go(edits, min_x, min_z, max_x, max_z, Nil{})

# `patch_fields_with_edits` for cells whose columns all lie inside the given
# (inclusive) box. A cell only ever looks up edits in its own column, so the
# edits outside the box are dropped once instead of being scanned per cell and
# per cell above it. The Nil dispatch still sees the full edit list.
def patch_fields_box(
  +fields: List<&2, LightField>, edits: List<&2, Edit>, +seed: Nat,
  +cells: List<&2, Cell>, +min_x: Nat, +min_z: Nat, +max_x: Nat, +max_z: Nat
) -> List<&2, LightCell>:
  match edits:
    case Nil{}:
      patch_fields(fields, seed, cells)
    case Con{head, tail}:
      patch_cells_with_edits(fields, light32.box_edits(edits, min_x, min_z, max_x, max_z), seed, cells)
