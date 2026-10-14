import Base
import ./world.bend as World
import ./player.bend as Player
import ./world_state.bend as WorldState

type Mob is Data:
  Mob{id: Nat, kind: U32, x: F32, y: F32, z: F32, heading_x: F32, heading_z: F32, health: F32, alive: Bool, burning: Bool, panic: F32}

# The mob roster, in one place. 1 pig, 2 zombie, 3 sheep, 4 brute, 5 cow,
# 6 chicken. A farm animal walks around, runs from the player for a while after
# the player hits it, and never fights back. A hostile hunts the player and
# burns in open daylight. Every rule below asks `kind_is_hostile` instead of
# repeating a kind number, so a new animal cannot inherit the hunter's rules and
# a new monster cannot inherit the animal's.
def kind_is_hostile(+kind: U32) -> Bool:
  Bool.or(U32.is_eq(kind, 2), U32.is_eq(kind, 4))

def kind_is_animal(+kind: U32) -> Bool:
  Bool.or(
    Bool.or(U32.is_eq(kind, 1), U32.is_eq(kind, 3)),
    Bool.or(U32.is_eq(kind, 5), U32.is_eq(kind, 6))
  )

# A mob is one of the roster's: an animal or a hostile. Anything else a client draws in a room
# — a villager, an item on the ground — is not a mob and is not hit like one.
def kind_is_mob(+kind: U32) -> Bool:
  Bool.or(kind_is_hostile(kind), kind_is_animal(kind))

# How many kinds the roster holds. `spawn` draws from it, so the spawn table and
# the roster cannot drift apart.
def kind_count() -> Nat:
  6n

# Panic is how many seconds of running an animal has left. `attack` starts it and
# the step functions are the only things that spend it, so an animal walks around
# until the player strikes it and then bolts, instead of fleeing a player who
# never touched it.
def panic_seconds() -> F32:
  6.0

def next_panic(+panic: F32, +dt: F32) -> F32:
  Bool.pick(F32, F32.is_gt(panic, dt), F32.sub(panic, dt), 0.0)

# Item 12 is wool, 13 rotten flesh, 48 raw porkchop, 49 raw beef, 50 raw
# chicken. Loot follows the animal: the sheep shears, the rest leave meat.
def drop_item(+kind: U32) -> U32:
  Bool.pick(U32, U32.is_eq(kind, 3), 12,
    Bool.pick(U32, U32.is_eq(kind, 1), 48,
      Bool.pick(U32, U32.is_eq(kind, 5), 49,
        Bool.pick(U32, U32.is_eq(kind, 6), 50, 13))))

type Region is Data:
  Region{blocks: List<&2, List<&2, U32>>, origin_x: Nat, origin_y: Nat, origin_z: Nat, width: Nat, height: Nat, depth: Nat}

type Drop is Data:
  Drop{id: Nat, item: U32, x: F32, y: F32, z: F32, amount: U32, velocity_y: F32, settled: Bool}

type Ground is Data:
  Ground{x: F32, z: F32, y: F32}

type CombatResult is Data:
  CombatResult{mobs: List<&2, Mob>, drops: List<&2, Drop>, hit: Bool}

type DropTarget is Data:
  DropFound{id: Nat, item: U32, amount: U32}
  DropMissing{}

def fraction(+numerator: U32, +denominator: U32) -> F32:
  F32.div(U32.to_f32(numerator), U32.to_f32(denominator))

def choose_f32(c: Bool, yes: F32, no: F32) -> F32:
  Bool.pick(F32, c, yes, no)

def make_mob(
  id: Nat, kind: U32, x: F32, y: F32, z: F32, health: F32, alive: Bool
) -> Mob:
  Mob{id, kind, x, y, z, 0.0, F32.neg(1.0), health, alive, False{}, 0.0}

# `burning` is the authoritative "this body is on fire right now" flag. The
# sunlight tick is the only writer that sets it; every other tick that rebuilds a
# Mob has to hand the current value straight through, so a mob on fire does not
# flicker every time it takes a step or gets knocked back. `panic` is carried the
# same way: `attack` is the only writer that sets it, and the steps only spend it.
# The browser presents both flags; it never infers fire or fear of its own.
def make_mob_heading(
  id: Nat, kind: U32, x: F32, y: F32, z: F32,
  heading_x: F32, heading_z: F32, health: F32, alive: Bool, burning: Bool, panic: F32
) -> Mob:
  Mob{id, kind, x, y, z, heading_x, heading_z, health, alive, burning, panic}

def cons_mob(mob: Mob, tail: List<&2, Mob>) -> List<&2, Mob>:
  Con{mob, tail}

def cons_drop(drop: Drop, tail: List<&2, Drop>) -> List<&2, Drop>:
  Con{drop, tail}

def empty_drops() -> List<&2, Drop>:
  Nil{}

def wander_dir(+id: Nat, +tick: Nat) -> U32:
  U32.from_nat(Nat.mod(Nat.add(Nat.mul(id, 7n), Nat.div(tick, 24n)), 8n))

# --- aiming at a body ---------------------------------------------------------
#
# What a player's ray is tested against: an upright box on the body's feet, 0.4 to each side
# and as tall as its kind. The heights are the roster's (`web/mob-kinds.js` holds the same
# numbers for the browser, whose `web/aim.js` is this rule's older copy and a migration
# target; `tests/entities-bend.test.mjs` holds the two together). A kind the roster does not
# know is as tall as the tallest.
def body_half_width() -> F32:
  fraction(4, 10)

def body_height(+kind: U32) -> F32:
  Bool.pick(F32, U32.is_eq(kind, 1), fraction(12, 10),
    Bool.pick(F32, U32.is_eq(kind, 3), fraction(13, 10),
      Bool.pick(F32, U32.is_eq(kind, 5), fraction(14, 10),
        Bool.pick(F32, U32.is_eq(kind, 6), fraction(8, 10), fraction(19, 10)))))

# One axis of the slab test: where along the ray it enters the span from `lo` to `hi`. A ray
# that runs along the span is inside it for all of its length or for none.
def aim.enter(+o: F32, +d: F32, +lo: F32, +hi: F32) -> F32:
  +flat = F32.is_lt(F32.abs(d), 0.000000001)
  +safe = choose_f32(flat, 1.0, d)
  +inside = Bool.and(F32.is_ge(o, lo), F32.is_le(o, hi))
  choose_f32(flat, choose_f32(inside, F32.neg(1000000000.0), 1000000000.0),
    F32.min(F32.div(F32.sub(lo, o), safe), F32.div(F32.sub(hi, o), safe)))

# And where it leaves.
def aim.leave(+o: F32, +d: F32, +lo: F32, +hi: F32) -> F32:
  +flat = F32.is_lt(F32.abs(d), 0.000000001)
  +safe = choose_f32(flat, 1.0, d)
  +inside = Bool.and(F32.is_ge(o, lo), F32.is_le(o, hi))
  choose_f32(flat, choose_f32(inside, 1000000000.0, F32.neg(1000000000.0)),
    F32.max(F32.div(F32.sub(lo, o), safe), F32.div(F32.sub(hi, o), safe)))

# How far along a ray from (`ox`, `oy`, `oz`) toward (`dx`, `dy`, `dz`) the body standing at
# (`x`, `y`, `z`) is, when the ray meets it within `reach`; and less than nothing when it
# does not.
def aim_distance(
  +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  +x: F32, +y: F32, +z: F32, +height: F32, +reach: F32
) -> F32:
  +w = body_half_width()
  +near = F32.max(F32.max(0.0, aim.enter(ox, dx, F32.sub(x, w), F32.add(x, w))),
    F32.max(aim.enter(oy, dy, y, F32.add(y, height)), aim.enter(oz, dz, F32.sub(z, w), F32.add(z, w))))
  +far = F32.min(F32.min(reach, aim.leave(ox, dx, F32.sub(x, w), F32.add(x, w))),
    F32.min(aim.leave(oy, dy, y, F32.add(y, height)), aim.leave(oz, dz, F32.sub(z, w), F32.add(z, w))))
  choose_f32(F32.is_le(near, far), near, F32.neg(1.0))

# The mob a player's ray has found so far: its id, how far along the ray it is, and whether
# there is one. `away` starts at the reach and is the limit the next body is tested out to.
type Aimed is Data:
  Aimed{id: U32, away: F32, found: Bool}

def aim_none(reach: F32) -> Aimed:
  Aimed{0, reach, False{}}

def aim_found(aimed: Aimed) -> Bool:
  Aimed{id, away, found} = aimed
  found

def aim_id(aimed: Aimed) -> U32:
  Aimed{id, away, found} = aimed
  id

# One more body tested against the ray: it is the mob under the crosshair when it is a mob and
# the ray meets it nearer than the one found so far, and otherwise nothing changes. The caller
# walks its bodies and keeps the answer between them.
def aim_step(+best: Aimed, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
  +id: U32, +kind: U32, +x: F32, +y: F32, +z: F32) -> Aimed:
  Aimed{best_id, +best_away, best_found} = best
  +away = aim_distance(ox, oy, oz, dx, dy, dz, x, y, z, body_height(kind), best_away)
  Bool.pick(Aimed, Bool.and(kind_is_mob(kind), F32.is_ge(away, 0.0)), Aimed{id, away, True{}}, best)

def combat_mobs(state: CombatResult) -> List<&2, Mob>:
  CombatResult{mobs, drops, hit} = state
  mobs

def combat_drops(state: CombatResult) -> List<&2, Drop>:
  CombatResult{mobs, drops, hit} = state
  drops

def combat_hit(state: CombatResult) -> Bool:
  CombatResult{mobs, drops, hit} = state
  hit

def make_drop(id: Nat, item: U32, x: F32, y: F32, z: F32, amount: U32) -> Drop:
  Drop{id, item, x, y, z, amount, 0.0, False{}}

def drop_for(mob: Mob) -> Drop:
  Mob{id, +kind, x, y, z, heading_x, heading_z, health, alive, burning, panic} = mob
  Drop{id, drop_item(kind), x, y, z, 1, 0.0, False{}}

# The generated-world half of sun_exposed: a cell is lit when it sits at or above
# its terrain column and nothing generated overhead blocks the sky. Spawn reads
# this same predicate, so a mob can never be placed on ground the sunlight tick
# would burn it on the very next step.
def sun_exposed_generated(+seed: Nat, +x: F32, +y: F32, +z: F32) -> Bool:
  +cell_x = World.cell(x)
  +cell_y = Player.floor_nat(y)
  +cell_z = World.cell(z)
  +terrain_height = World.column_height(seed, cell_x, cell_z)
  +above_terrain = Nat.is_ge(cell_y, terrain_height)
  +generated_cover = Bool.and(
    above_terrain,
    Player.solid(World.generated_cover_above(seed, cell_x, cell_y, cell_z))
  )
  Bool.and(above_terrain, Bool.not(generated_cover))

# The spawn grid. A cell is four blocks on a side, so the 48x48 world offers 144
# candidate spots rather than 36: a coarser grid made the population a lottery
# where a handful of draws could all land inside the spawn clearing or on a
# hillside, and the player met no animals at all.
def spawn_cell_size() -> Nat:
  4n

# How many of those cells carry a mob. One in eight puts five to fourteen bodies
# on the map - most of them farm animals, since a hostile may only appear under a
# blocked sky or after nightfall.
def spawn_cell_divisor() -> Nat:
  8n

def spawn_x(
  +seed: Nat, +daylight: F32, +remaining: Nat, +x: Nat, +z: Nat, +next_id: Nat,
  +mobs: List<&2, Mob>
) -> List<&2, Mob>:
  match remaining:
    case 0n:
      mobs
    case 1n+p:
      +height = World.column_height(seed, x, z)
      +hash = World.mix(seed, x, z)
      +selected = Nat.is_eq(Nat.mod(hash, spawn_cell_divisor()), 0n)
      +feet_open = U32.is_eq(World.block(seed, x, height, z), 0)
      +head_open = U32.is_eq(World.block(seed, x, Nat.add(height, 1n), z), 0)
      +foot_x = F32.add(U32.to_f32(U32.from_nat(x)), fraction(1, 2))
      +foot_y = U32.to_f32(U32.from_nat(height))
      +foot_z = F32.add(U32.to_f32(U32.from_nat(z)), fraction(1, 2))
      +kind = U32.add(U32.from_nat(Nat.mod(World.mix(seed, z, x), kind_count())), 1)
      +hostile = kind_is_hostile(kind)
      +tough = U32.is_eq(kind, 4)
      # A hostile standing in open daylight would burn on the first tick, so it
      # may only appear under a blocked sky or after nightfall. An animal never
      # burns, and the open surface is the only place a player meets one, so it
      # only needs room for its body.
      +dark = Bool.not(F32.is_gt(daylight, 0.5))
      +shaded = Bool.not(sun_exposed_generated(seed, foot_x, foot_y, foot_z))
      +unlit = Bool.or(dark, shaded)
      +fit = Bool.and(feet_open, head_open)
      +clear = Bool.and(fit, Bool.or(Bool.not(hostile), unlit))
      +mob = make_mob(
        next_id,
        kind,
        F32.add(U32.to_f32(U32.from_nat(x)), fraction(1, 2)),
        U32.to_f32(U32.from_nat(height)),
        F32.add(U32.to_f32(U32.from_nat(z)), fraction(1, 2)),
        Bool.pick(F32, tough, 40.0, 20.0),
        True{}
      )
      +updated = Bool.pick(List<&2, Mob>, Bool.and(selected, clear), cons_mob(mob, mobs), mobs)
      spawn_x(seed, daylight, p, Nat.add(x, spawn_cell_size()), z, Nat.add(next_id, 1n), updated)

def spawn_z(
  +seed: Nat, +daylight: F32, +remaining: Nat, +x: Nat, +z: Nat, +x_count: Nat,
  +next_id: Nat, +mobs: List<&2, Mob>
) -> List<&2, Mob>:
  match remaining:
    case 0n:
      mobs
    case 1n+p:
      +row = spawn_x(seed, daylight, x_count, x, z, next_id, mobs)
      spawn_z(seed, daylight, p, x, Nat.add(z, spawn_cell_size()), x_count, Nat.add(next_id, x_count), row)

def spawn(
  +seed: Nat, +daylight: F32, +origin_x: Nat, +origin_z: Nat,
  +width: Nat, +depth: Nat
) -> List<&2, Mob>:
  spawn_z(
    seed,
    daylight,
    Nat.div(depth, spawn_cell_size()),
    origin_x,
    origin_z,
    Nat.div(width, spawn_cell_size()),
    0n,
    Nil{}
  )

def peaceful_mobs(+mobs: List<&2, Mob>) -> List<&2, Mob>:
  match mobs:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Mob{+id, +kind, +x, +y, +z, heading_x, heading_z, +health, +alive, burning, panic} = head
      +rest = peaceful_mobs(tail)
      Bool.pick(List<&2, Mob>, kind_is_animal(kind), cons_mob(head, rest), rest)

def spawn_for_mode(
  +seed: Nat, +daylight: F32, +origin_x: Nat, +origin_z: Nat,
  +width: Nat, +depth: Nat, peaceful: Bool
) -> List<&2, Mob>:
  +mobs = spawn(seed, daylight, origin_x, origin_z, width, depth)
  Bool.pick(List<&2, Mob>, peaceful, peaceful_mobs(mobs), mobs)

def spawn_area_cell(+value: F32, +cell: Nat) -> Bool:
  +lower = U32.to_f32(U32.from_nat(Nat.sub(cell, 8n)))
  +upper = U32.to_f32(U32.from_nat(Nat.add(cell, 9n)))
  Bool.and(F32.is_lt(lower, value), F32.is_lt(value, upper))

def remove_spawn_area(
  +mobs: List<&2, Mob>, +safe_x: Nat, +safe_z: Nat
) -> List<&2, Mob>:
  match mobs:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Mob{+id, +kind, +x, +y, +z, heading_x, heading_z, +health, +alive, burning, panic} = head
      +rest = remove_spawn_area(tail, safe_x, safe_z)
      +same_area = Bool.and(spawn_area_cell(x, safe_x), spawn_area_cell(z, safe_z))
      Bool.pick(List<&2, Mob>, same_area, rest, cons_mob(head, rest))

def spawn_for_player(
  +seed: Nat, +daylight: F32, +origin_x: Nat, +origin_z: Nat,
  +width: Nat, +depth: Nat, +safe_x: Nat, +safe_z: Nat, peaceful: Bool
) -> List<&2, Mob>:
  +mobs = remove_spawn_area(
    spawn(seed, daylight, origin_x, origin_z, width, depth), safe_x, safe_z
  )
  Bool.pick(List<&2, Mob>, peaceful, peaceful_mobs(mobs), mobs)

def max_f32(+a: F32, +b: F32) -> F32:
  Bool.pick(F32, F32.is_lt(a, b), b, a)

def mob_support(
  +blocks: List<&2, List<&2, U32>>, +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat,
  +x: Nat, +z: Nat, +bottom: Nat, +ceiling: F32, +remaining: Nat
) -> F32:
  match remaining:
    case 0n:
      F32.neg(1000.0)
    case 1n+p:
      +y = Nat.add(bottom, p)
      +block = Player.region_block(blocks, origin_x, origin_y, origin_z, width, height, depth, x, y, z)
      +top = F32.add(U32.to_f32(U32.from_nat(y)), Player.block_height(block))
      +usable = Bool.and(Player.solid(block), F32.is_le(top, ceiling))
      Bool.pick(F32, usable, top, mob_support(blocks, origin_x, origin_y, origin_z, width, height, depth, x, z, bottom, ceiling, p))

def mob_footprint(
  +blocks: List<&2, List<&2, U32>>, +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat,
  +x0: Nat, +x1: Nat, +z0: Nat, +z1: Nat,
  +bottom: Nat, +ceiling: F32, +remaining: Nat
) -> F32:
  +south_west = mob_support(blocks, origin_x, origin_y, origin_z, width, height, depth, x0, z0, bottom, ceiling, remaining)
  +south_east = mob_support(blocks, origin_x, origin_y, origin_z, width, height, depth, x1, z0, bottom, ceiling, remaining)
  +north_west = mob_support(blocks, origin_x, origin_y, origin_z, width, height, depth, x0, z1, bottom, ceiling, remaining)
  +north_east = mob_support(blocks, origin_x, origin_y, origin_z, width, height, depth, x1, z1, bottom, ceiling, remaining)
  max_f32(max_f32(south_west, south_east), max_f32(north_west, north_east))

type AxisStep is Data:
  AxisStep{pos: F32, base: F32}

def axis_pos(result: AxisStep) -> F32:
  AxisStep{+pos, base} = result
  pos

def axis_base(result: AxisStep) -> F32:
  AxisStep{pos, +base} = result
  base

def step_rise(
  +blocks: List<&2, List<&2, U32>>, +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat, +offset_f: F32,
  +at_x: F32, +at_y: F32, +at_z: F32
) -> F32:
  +dummy = Player.state(F32.add(at_x, offset_f), at_y, F32.add(at_z, offset_f), 0.0, 0.0, 0.0, False{}, 20.0, 20.0)
  +blocked = Player.collides(dummy, F32.add(at_x, offset_f), at_y, F32.add(at_z, offset_f), blocks, origin_x, origin_y, origin_z, width, height, depth)
  +rise = mob_footprint(blocks, origin_x, origin_y, origin_z, width, height, depth,
    Player.floor_nat(F32.sub(F32.add(at_x, offset_f), fraction(3, 10))),
    Player.floor_nat(F32.add(F32.add(at_x, offset_f), fraction(3, 10))),
    Player.floor_nat(F32.sub(F32.add(at_z, offset_f), fraction(3, 10))),
    Player.floor_nat(F32.add(F32.add(at_z, offset_f), fraction(3, 10))),
    origin_y, F32.add(at_y, fraction(11, 10)), height)
  +found = F32.is_gt(rise, F32.neg(999.0))
  +headroom = Player.collides(dummy, F32.add(at_x, offset_f), rise, F32.add(at_z, offset_f), blocks, origin_x, origin_y, origin_z, width, height, depth)
  +step_up = Bool.and(blocked, Bool.and(found, Bool.not(headroom)))
  Bool.pick(F32, step_up, rise, F32.neg(1000.0))

def step_x(
  +blocks: List<&2, List<&2, U32>>, +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat, +offset_f: F32, +alive: Bool,
  +from_x: F32, +from_y: F32, +from_z: F32, +to_x: F32
) -> AxisStep:
  +dummy = Player.state(F32.add(from_x, offset_f), from_y, F32.add(from_z, offset_f), 0.0, 0.0, 0.0, False{}, 20.0, 20.0)
  +blocked = Player.collides(dummy, F32.add(to_x, offset_f), from_y, F32.add(from_z, offset_f), blocks, origin_x, origin_y, origin_z, width, height, depth)
  +floor = step_rise(blocks, origin_x, origin_y, origin_z, width, height, depth, offset_f, to_x, from_y, from_z)
  +step_ok = F32.is_gt(floor, F32.neg(999.0))
  +next = Bool.pick(F32, Bool.not(alive), from_x,
    Bool.pick(F32, step_ok, to_x, Bool.pick(F32, blocked, from_x, to_x)))
  +base = Bool.pick(F32, Bool.not(alive), from_y,
    Bool.pick(F32, step_ok, floor, from_y))
  AxisStep{next, base}

def step_z(
  +blocks: List<&2, List<&2, U32>>, +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat, +offset_f: F32, +alive: Bool,
  +from_x: F32, +from_y: F32, +from_z: F32, +to_z: F32
) -> AxisStep:
  +dummy = Player.state(F32.add(from_x, offset_f), from_y, F32.add(from_z, offset_f), 0.0, 0.0, 0.0, False{}, 20.0, 20.0)
  +blocked = Player.collides(dummy, F32.add(from_x, offset_f), from_y, F32.add(to_z, offset_f), blocks, origin_x, origin_y, origin_z, width, height, depth)
  +floor = step_rise(blocks, origin_x, origin_y, origin_z, width, height, depth, offset_f, from_x, from_y, to_z)
  +step_ok = F32.is_gt(floor, F32.neg(999.0))
  +next = Bool.pick(F32, Bool.not(alive), from_z,
    Bool.pick(F32, step_ok, to_z, Bool.pick(F32, blocked, from_z, to_z)))
  +base = Bool.pick(F32, Bool.not(alive), from_y,
    Bool.pick(F32, step_ok, floor, from_y))
  AxisStep{next, base}

def step_grounded(
  mob: Mob, player_x: F32, player_z: F32, +dt: F32, +time: F32, +offset: Nat,
  +region: Region
) -> Mob:
  Mob{+id, +kind, +x, +y, +z, +heading_x, +heading_z, +health, +alive, +burning, +panic} = mob
  Region{+blocks, +origin_x, +origin_y, +origin_z, +width, +height, +depth} = region
  +offset_f = U32.to_f32(U32.from_nat(offset))
  +hostile = kind_is_hostile(kind)
  +panicked = Bool.and(alive, F32.is_gt(panic, 0.0))
  +phase = F32.add(F32.mul(time, fraction(6, 10)), F32.mul(U32.to_f32(U32.from_nat(id)), fraction(24, 10)))
  +to_player_x = F32.sub(player_x, x)
  +to_player_z = F32.sub(player_z, z)
  +dir_x = Bool.pick(F32, hostile, to_player_x,
    Bool.pick(F32, panicked, F32.neg(to_player_x), F32.sin(phase)))
  +dir_z = Bool.pick(F32, hostile, to_player_z,
    Bool.pick(F32, panicked, F32.neg(to_player_z), F32.cos(phase)))
  +distance = Bool.pick(F32, Bool.or(hostile, panicked),
    F32.sqrt(F32.add(F32.mul(to_player_x, to_player_x), F32.mul(to_player_z, to_player_z))), 1.0)
  +safe_distance = Bool.pick(F32, F32.is_eq(distance, 0.0), 1.0, distance)
  +rate = Bool.pick(F32, U32.is_eq(kind, 4), fraction(1, 2),
    Bool.pick(F32, U32.is_eq(kind, 2), fraction(8, 10),
      Bool.pick(F32, panicked, fraction(12, 10), fraction(4, 10))))
  +stride = F32.mul(rate, dt)
  +try_x = F32.add(x, F32.mul(F32.div(dir_x, safe_distance), stride))
  +moved_x = step_x(blocks, origin_x, origin_y, origin_z, width, height, depth, offset_f, alive, x, y, z, try_x)
  +next_x = axis_pos(moved_x)
  +base_x = axis_base(moved_x)
  +try_z = F32.add(z, F32.mul(F32.div(dir_z, safe_distance), stride))
  +moved_z = step_z(blocks, origin_x, origin_y, origin_z, width, height, depth, offset_f, alive, next_x, base_x, z, try_z)
  +next_z = axis_pos(moved_z)
  +base_z = axis_base(moved_z)
  +ground = mob_footprint(blocks, origin_x, origin_y, origin_z, width, height, depth,
    Player.floor_nat(F32.sub(F32.add(next_x, offset_f), fraction(3, 10))),
    Player.floor_nat(F32.add(F32.add(next_x, offset_f), fraction(3, 10))),
    Player.floor_nat(F32.sub(F32.add(next_z, offset_f), fraction(3, 10))),
    Player.floor_nat(F32.add(F32.add(next_z, offset_f), fraction(3, 10))),
    origin_y, F32.add(base_z, fraction(11, 10)), height)
  +fall = F32.sub(base_z, F32.mul(5.0, dt))
  +next_y = Bool.pick(F32, Bool.not(alive), base_z,
    Bool.pick(F32, F32.is_gt(ground, F32.neg(999.0)), ground, fall))
  +next_heading_x = Bool.pick(F32, alive, F32.div(dir_x, safe_distance), heading_x)
  +next_heading_z = Bool.pick(F32, alive, F32.div(dir_z, safe_distance), heading_z)
  +panic_left = Bool.pick(F32, alive, next_panic(panic, dt), panic)
  make_mob_heading(id, kind, next_x, next_y, next_z, next_heading_x, next_heading_z, health, alive, burning, panic_left)

def step_world(
  +mobs: List<&2, Mob>, +player_x: F32, +player_z: F32,
  +dt: F32, +time: F32, +offset: Nat, +regions: List<&2, Region>
) -> List<&2, Mob>:
  match mobs:
    case Nil{}:
      Nil{}
    case Con{+head, tail}:
      match regions:
        case Nil{}:
          Nil{}
        case Con{+region, rest}:
          cons_mob(step_grounded(head, player_x, player_z, dt, time, offset, region),
            step_world(tail, player_x, player_z, dt, time, offset, rest))

def step_mob_budgeted(
  +mob: Mob, player_x: F32, player_z: F32, +dt: F32, +active_radius: F32
) -> Mob:
  Mob{+id, +kind, +x, +y, +z, +heading_x, +heading_z, +health, +alive, +burning, +panic} = mob
  +dx = F32.sub(player_x, x)
  +dz = F32.sub(player_z, z)
  +distance = F32.sqrt(F32.add(F32.mul(dx, dx), F32.mul(dz, dz)))
  +near = F32.is_lt(distance, active_radius)
  +far_dt = F32.div(dt, 5.0)
  +effective_dt = Bool.pick(F32, near, dt, far_dt)
  +hostile = kind_is_hostile(kind)
  +chaser = Bool.and(hostile, alive)
  +panicked = Bool.and(F32.is_gt(panic, 0.0), alive)
  +safe_distance = Bool.pick(F32, F32.is_eq(distance, 0.0), 1.0, distance)
  +speed = F32.mul(fraction(8, 10), effective_dt)
  +chase_x = F32.add(x, F32.mul(F32.div(dx, safe_distance), speed))
  +chase_z = F32.add(z, F32.mul(F32.div(dz, safe_distance), speed))
  +flee_x = F32.sub(x, F32.mul(F32.div(dx, safe_distance), speed))
  +flee_z = F32.sub(z, F32.mul(F32.div(dz, safe_distance), speed))
  +next_x = Bool.pick(F32, chaser, chase_x, Bool.pick(F32, panicked, flee_x, x))
  +next_z = Bool.pick(F32, chaser, chase_z, Bool.pick(F32, panicked, flee_z, z))
  +face_x = Bool.pick(F32, panicked, F32.neg(F32.div(dx, safe_distance)), F32.div(dx, safe_distance))
  +face_z = Bool.pick(F32, panicked, F32.neg(F32.div(dz, safe_distance)), F32.div(dz, safe_distance))
  +next_heading_x = Bool.pick(F32, Bool.or(chaser, panicked), face_x, heading_x)
  +next_heading_z = Bool.pick(F32, Bool.or(chaser, panicked), face_z, heading_z)
  +panic_left = Bool.pick(F32, alive, next_panic(panic, effective_dt), panic)
  make_mob_heading(id, kind, next_x, y, next_z, next_heading_x, next_heading_z, health, alive, burning, panic_left)

def step_budgeted(
  +mobs: List<&2, Mob>, +player_x: F32, +player_z: F32,
  +dt: F32, +active_radius: F32
) -> List<&2, Mob>:
  match mobs:
    case Nil{}:
      Nil{}
    case Con{+head, tail}:
      cons_mob(
        step_mob_budgeted(head, player_x, player_z, dt, active_radius),
        step_budgeted(tail, player_x, player_z, dt, active_radius)
      )

# Melee threat is a world query, not a distance check. A hostile may only
# damage a player it can actually see, and only from inside its attack cone.
# The cone is wider for the brute so a heavy mob still connects off-axis while
# a turning mob can no longer hit the player behind it.
def attack_cone_cosine(+kind: U32) -> F32:
  Bool.pick(F32, U32.is_eq(kind, 4), fraction(1, 6), fraction(1, 2))

def facing_player(
  +heading_x: F32, +heading_z: F32, +to_x: F32, +to_z: F32, +kind: U32
) -> Bool:
  +reach = F32.sqrt(F32.add(F32.mul(to_x, to_x), F32.mul(to_z, to_z)))
  +overlapping = F32.is_lt(reach, fraction(1, 10))
  +safe = Bool.pick(F32, F32.is_eq(reach, 0.0), 1.0, reach)
  +alignment = F32.add(
    F32.mul(heading_x, F32.div(to_x, safe)),
    F32.mul(heading_z, F32.div(to_z, safe))
  )
  Bool.or(overlapping, F32.is_ge(alignment, attack_cone_cosine(kind)))

# The eye ray runs above the feet so a one-block step under the target is not
# mistaken for a wall; the endpoint cells are skipped so a body pressed against
# a wall still resolves instead of becoming permanently invulnerable.
def melee_eye() -> F32:
  fraction(12, 10)

# Face-adjacent bodies share a face, so no cell can sit strictly between them.
# The fast path keeps the common melee case free; only a diagonal stand-off
# pays for the ray.
def line_of_sight.crosses_cell(
  +start_x: Nat, +start_y: Nat, +start_z: Nat,
  +end_x: Nat, +end_y: Nat, +end_z: Nat
) -> Bool:
  +dx = Nat.is_ne(start_x, end_x)
  +dy = Nat.is_ne(start_y, end_y)
  +dz = Nat.is_ne(start_z, end_z)
  Bool.or(Bool.and(dx, Bool.or(dy, dz)), Bool.and(dy, dz))

def line_of_sight.blocked(
  +blocks: List<&2, List<&2, U32>>, +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat,
  +cell_x: Nat, +cell_y: Nat, +cell_z: Nat,
  +start_x: Nat, +start_y: Nat, +start_z: Nat,
  +end_x: Nat, +end_y: Nat, +end_z: Nat
) -> Bool:
  +at_start = Bool.and(
    Bool.and(Nat.is_eq(cell_x, start_x), Nat.is_eq(cell_y, start_y)),
    Nat.is_eq(cell_z, start_z)
  )
  +at_end = Bool.and(
    Bool.and(Nat.is_eq(cell_x, end_x), Nat.is_eq(cell_y, end_y)),
    Nat.is_eq(cell_z, end_z)
  )
  +block = Player.region_block(blocks, origin_x, origin_y, origin_z, width, height, depth, cell_x, cell_y, cell_z)
  Bool.and(Bool.not(Bool.or(at_start, at_end)), Player.solid(block))

def line_of_sight.step(
  +blocks: List<&2, List<&2, U32>>, +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat,
  +from_x: F32, +from_y: F32, +from_z: F32,
  +delta_x: F32, +delta_y: F32, +delta_z: F32, +denominator: F32, +index: Nat,
  +start_x: Nat, +start_y: Nat, +start_z: Nat,
  +end_x: Nat, +end_y: Nat, +end_z: Nat
) -> Bool:
  +t = F32.div(F32.add(U32.to_f32(U32.from_nat(index)), 1.0), denominator)
  line_of_sight.blocked(
    blocks, origin_x, origin_y, origin_z, width, height, depth,
    Player.floor_nat(F32.add(from_x, F32.mul(delta_x, t))),
    Player.floor_nat(F32.add(from_y, F32.mul(delta_y, t))),
    Player.floor_nat(F32.add(from_z, F32.mul(delta_z, t))),
    start_x, start_y, start_z, end_x, end_y, end_z
  )

def line_of_sight.hit(
  +blocks: List<&2, List<&2, U32>>, +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat,
  +from_x: F32, +from_y: F32, +from_z: F32,
  +delta_x: F32, +delta_y: F32, +delta_z: F32, +denominator: F32, +index: Nat,
  +start_x: Nat, +start_y: Nat, +start_z: Nat,
  +end_x: Nat, +end_y: Nat, +end_z: Nat
) -> Bool:
  line_of_sight.step(blocks, origin_x, origin_y, origin_z, width, height, depth,
    from_x, from_y, from_z, delta_x, delta_y, delta_z, denominator, index,
    start_x, start_y, start_z, end_x, end_y, end_z)

def line_of_sight.loop(
  +remaining: Nat, hit: Bool,
  +blocks: List<&2, List<&2, U32>>, +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat,
  +from_x: F32, +from_y: F32, +from_z: F32,
  +delta_x: F32, +delta_y: F32, +delta_z: F32, +denominator: F32, +index: Nat,
  +start_x: Nat, +start_y: Nat, +start_z: Nat,
  +end_x: Nat, +end_y: Nat, +end_z: Nat
) -> Bool:
  match remaining:
    case 0n:
      False{}
    case 1n+p:
      match hit:
        case True{}:
          True{}
        case False{}:
          line_of_sight.loop(p,
            line_of_sight.hit(blocks, origin_x, origin_y, origin_z, width, height, depth,
              from_x, from_y, from_z, delta_x, delta_y, delta_z, denominator, index,
              start_x, start_y, start_z, end_x, end_y, end_z),
            blocks, origin_x, origin_y, origin_z, width, height, depth,
            from_x, from_y, from_z, delta_x, delta_y, delta_z, denominator,
            Nat.add(index, 1n), start_x, start_y, start_z, end_x, end_y, end_z)

# Eight samples keep the eye ray finer than a single cell across the whole
# melee radius; the caller passes zero samples to skip the scan entirely.
def line_of_sight(
  +blocks: List<&2, List<&2, U32>>, +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat,
  +mob_x: F32, +mob_y: F32, +mob_z: F32,
  +player_x: F32, +player_y: F32, +player_z: F32,
  +samples: Nat
) -> Bool:
  +eye = melee_eye()
  +from_x = mob_x
  +from_y = F32.add(mob_y, eye)
  +from_z = mob_z
  +to_x = player_x
  +to_y = F32.add(player_y, eye)
  +to_z = player_z
  Bool.not(line_of_sight.loop(
    samples, False{},
    blocks, origin_x, origin_y, origin_z, width, height, depth,
    from_x, from_y, from_z,
    F32.sub(to_x, from_x), F32.sub(to_y, from_y), F32.sub(to_z, from_z),
    U32.to_f32(U32.from_nat(Nat.add(samples, 1n))), 0n,
    Player.floor_nat(from_x), Player.floor_nat(from_y), Player.floor_nat(from_z),
    Player.floor_nat(to_x), Player.floor_nat(to_y), Player.floor_nat(to_z)
  ))

def threat_damage.cell(
  +kind: U32, +heading_x: F32, +heading_z: F32, +alive: Bool,
  +mob_x: F32, +mob_y: F32, +mob_z: F32,
  region: Region, +player_x: F32, +player_y: F32, +player_z: F32, +offset: Nat
) -> F32:
  Region{+blocks, +origin_x, +origin_y, +origin_z, +width, +height, +depth} = region
  +offset_f = U32.to_f32(U32.from_nat(offset))
  +to_x = F32.sub(player_x, mob_x)
  +to_y = F32.sub(player_y, mob_y)
  +to_z = F32.sub(player_z, mob_z)
  +distance = F32.sqrt(F32.add(F32.mul(to_x, to_x), F32.mul(to_z, to_z)))
  +vertical_close = F32.is_lt(F32.abs(to_y), fraction(3, 2))
  +close = Bool.and(F32.is_lt(distance, fraction(3, 2)), vertical_close)
  +brute = Bool.and(U32.is_eq(kind, 4), alive)
  +hostile = Bool.and(kind_is_hostile(kind), alive)
  +here = Bool.pick(F32, brute, 4.0, Bool.pick(F32, hostile, 2.0, 0.0))
  +contact = Bool.and(close, F32.is_gt(here, 0.0))
  +facing = facing_player(heading_x, heading_z, to_x, to_z, kind)
  +eye = melee_eye()
  +crosses = line_of_sight.crosses_cell(
    Player.floor_nat(F32.add(mob_x, offset_f)),
    Player.floor_nat(F32.add(mob_y, eye)),
    Player.floor_nat(F32.add(mob_z, offset_f)),
    Player.floor_nat(F32.add(player_x, offset_f)),
    Player.floor_nat(F32.add(player_y, eye)),
    Player.floor_nat(F32.add(player_z, offset_f))
  )
  # Only a hostile that is in reach, in a diagonal, pays for the eye-ray scan.
  +samples = Bool.pick(Nat, Bool.and(contact, crosses), 8n, 0n)
  +visible = line_of_sight(
    blocks, origin_x, origin_y, origin_z, width, height, depth,
    F32.add(mob_x, offset_f), mob_y, F32.add(mob_z, offset_f),
    F32.add(player_x, offset_f), player_y, F32.add(player_z, offset_f),
    samples
  )
  choose_f32(Bool.and(contact, Bool.and(facing, visible)), here, 0.0)

def threat_damage(
  mobs: List<&2, Mob>, +player_x: F32, +player_y: F32, +player_z: F32,
  +offset: Nat, +regions: List<&2, Region>
) -> F32:
  match mobs:
    case Nil{}:
      0.0
    case Con{+head, tail}:
      Mob{+id, +kind, +x, +y, +z, +heading_x, +heading_z, +health, +alive, burning, panic} = head
      match regions:
        case Nil{}:
          0.0
        case Con{+region, rest}:
          +local = threat_damage.cell(kind, heading_x, heading_z, alive, x, y, z, region, player_x, player_y, player_z, offset)
          +rest_damage = threat_damage(tail, player_x, player_y, player_z, offset, rest)
          choose_f32(F32.is_lt(local, rest_damage), rest_damage, local)

def attack.go(
  mobs: List<&2, Mob>, +target_id: Nat, +damage: F32,
  +from_x: F32, +from_y: F32, +from_z: F32, +max_range: F32,
  +drops: List<&2, Drop>
) -> CombatResult:
  match mobs:
    case Nil{}:
      CombatResult{Nil{}, drops, False{}}
    case Con{+head, tail}:
      Mob{+id, +kind, +x, +y, +z, heading_x, heading_z, +health, +alive, +burning, +panic} = head
      +from_dx = F32.sub(x, from_x)
      +from_dy = F32.sub(y, from_y)
      +from_dz = F32.sub(z, from_z)
      +from_distance = F32.sqrt(F32.add(
        F32.add(F32.mul(from_dx, from_dx), F32.mul(from_dy, from_dy)),
        F32.mul(from_dz, from_dz)
      ))
      +in_range = F32.is_le(from_distance, max_range)
      +target = Bool.and(Bool.and(Nat.is_eq(id, target_id), alive), in_range)
      +next_health = Bool.pick(F32, target, F32.sub(health, damage), health)
      +next_alive = Bool.pick(Bool, target, F32.is_gt(next_health, 0.0), alive)
      +killed = Bool.and(target, Bool.not(next_alive))
      +next_drops = Bool.pick(List<&2, Drop>, killed, cons_drop(drop_for(head), drops), drops)
      +away_x = F32.sub(x, from_x)
      +away_z = F32.sub(z, from_z)
      +push_distance = F32.sqrt(F32.add(F32.mul(away_x, away_x), F32.mul(away_z, away_z)))
      +safe_push = Bool.pick(F32, F32.is_eq(push_distance, 0.0), 1.0, push_distance)
      +knock_x = F32.add(x, F32.mul(F32.div(away_x, safe_push), fraction(9, 10)))
      +knock_z = F32.add(z, F32.mul(F32.div(away_z, safe_push), fraction(9, 10)))
      +next_heading_x = Bool.pick(F32, target, F32.div(away_x, safe_push), heading_x)
      +next_heading_z = Bool.pick(F32, target, F32.div(away_z, safe_push), heading_z)
      # Being struck is what makes an animal run. A hostile has nowhere to run
      # to, so the hit buys it panic instead of a head start.
      +startled = Bool.and(target, kind_is_animal(kind))
      +next_panic = Bool.pick(F32, startled, panic_seconds(), panic)
      +updated = make_mob_heading(
        id, kind, Bool.pick(F32, target, knock_x, x), y,
        Bool.pick(F32, target, knock_z, z), next_heading_x, next_heading_z,
        next_health, next_alive, burning, next_panic
      )
      +rest = attack.go(tail, target_id, damage, from_x, from_y, from_z, max_range, next_drops)
      CombatResult{cons_mob(updated, combat_mobs(rest)), combat_drops(rest), Bool.or(target, combat_hit(rest))}

def attack(
  +mobs: List<&2, Mob>, +target_id: Nat, +damage: F32,
  +from_x: F32, +from_y: F32, +from_z: F32, +max_range: F32,
  +drops: List<&2, Drop>
) -> CombatResult:
  attack.go(mobs, target_id, damage, from_x, from_y, from_z, max_range, drops)

def hostile_kind(+kind: U32, +alive: Bool) -> Bool:
  Bool.and(alive, kind_is_hostile(kind))

type BodyCells is Data:
  BodyCells{shaded: Bool, placed_water: Bool}

# A single pass over the persistent edits answers both questions the sunlight
# tick asks about a body: whether an edit shades the column it stands in, and
# whether one of its two body cells holds water. One traversal keeps the per-mob
# cost of a growing edit list unchanged by the water rule.
def body_cells.go(
  +edits: List<&2, WorldState.Edit>, +cell_x: Nat, +cell_y: Nat, +cell_z: Nat,
  +shaded: Bool, +placed_water: Bool
) -> BodyCells:
  match edits:
    case Nil{}:
      BodyCells{shaded, placed_water}
    case Con{+head, tail}:
      WorldState.Edit{+edit_x, +edit_y, +edit_z, +block} = head
      +same_column = Bool.and(Nat.is_eq(edit_x, cell_x), Nat.is_eq(edit_z, cell_z))
      +above = Bool.and(same_column, Nat.is_ge(edit_y, cell_y))
      +next_shaded = Bool.or(shaded, Bool.and(above, Player.solid(block)))
      # Feet and head count as one body, so a mob that has waded into the
      # shallows is out of the fire before it is fully submerged.
      +body = Bool.and(
        same_column,
        Bool.or(Nat.is_eq(edit_y, cell_y), Nat.is_eq(edit_y, Nat.add(cell_y, 1n)))
      )
      +next_water = Bool.or(placed_water, Bool.and(body, Player.is_water(block)))
      body_cells.go(tail, cell_x, cell_y, cell_z, next_shaded, next_water)

def body_cells(
  +edits: List<&2, WorldState.Edit>, +cell_x: Nat, +cell_y: Nat, +cell_z: Nat
) -> BodyCells:
  body_cells.go(edits, cell_x, cell_y, cell_z, False{}, False{})

# Water is not direct sun. A body standing in it is neither lit nor burning, so
# the sea puts a fire out and keeps a mob from catching one, and water the player
# poured with a bucket reads the same way. This is the generated half, the same
# sea query the world generator answers with, so the tick still needs no
# materialized block.
def water_contact_generated(
  +seed: Nat, +cell_x: Nat, +cell_y: Nat, +cell_z: Nat
) -> Bool:
  Bool.or(
    World.water_at(seed, cell_x, cell_y, cell_z),
    World.water_at(seed, cell_x, Nat.add(cell_y, 1n), cell_z)
  )

# Use the generated terrain height for the bulk sky query; only persistent
# edits need a per-column scan, keeping the simulation tick independent of
# world-generation cost for every mob. The generated half is shared with spawn.
def sun_exposed.cells(
  +cells: BodyCells, +seed: Nat, +cell_x: Nat, +cell_y: Nat, +cell_z: Nat
) -> Bool:
  BodyCells{+shaded, +placed_water} = cells
  +water = Bool.or(placed_water, water_contact_generated(seed, cell_x, cell_y, cell_z))
  Bool.not(Bool.or(shaded, water))

def sun_exposed.lit(
  +lit: Bool, +edits: List<&2, WorldState.Edit>, +seed: Nat,
  +cell_x: Nat, +cell_y: Nat, +cell_z: Nat
) -> Bool:
  match lit:
    case False{}:
      False{}
    case True{}:
      sun_exposed.cells(body_cells(edits, cell_x, cell_y, cell_z), seed, cell_x, cell_y, cell_z)

def sun_exposed(
  +edits: List<&2, WorldState.Edit>, +seed: Nat, +x: F32, +y: F32, +z: F32
) -> Bool:
  sun_exposed.lit(
    sun_exposed_generated(seed, x, y, z),
    edits,
    seed,
    World.cell(x),
    Player.floor_nat(y),
    World.cell(z),
  )

def sun_burning.hostile(
  +hostile: Bool, +edits: List<&2, WorldState.Edit>, +seed: Nat,
  +x: F32, +y: F32, +z: F32
) -> Bool:
  match hostile:
    case False{}:
      False{}
    case True{}:
      sun_exposed(edits, seed, x, y, z)

def sun_burning(
  +day: Bool, +kind: U32, +alive: Bool,
  +edits: List<&2, WorldState.Edit>, +seed: Nat, +x: F32, +y: F32, +z: F32
) -> Bool:
  match day:
    case False{}:
      False{}
    case True{}:
      sun_burning.hostile(hostile_kind(kind, alive), edits, seed, x, y, z)

def sunlight_damage.go(
  +mobs: List<&2, Mob>, +edits: List<&2, WorldState.Edit>, +seed: Nat,
  +daylight: F32, +dt: F32, +drops: List<&2, Drop>
) -> CombatResult:
  match mobs:
    case Nil{}:
      CombatResult{Nil{}, drops, False{}}
    case Con{+head, tail}:
      Mob{+id, +kind, +x, +y, +z, +heading_x, +heading_z, +health, +alive, _, +panic} = head
      +day = F32.is_gt(daylight, 0.5)
      +exposed = sun_burning(day, kind, alive, edits, seed, x, y, z)
      +next_health = choose_f32(exposed, F32.sub(health, F32.mul(dt, 1.0)), health)
      +next_alive = Bool.pick(Bool, exposed, F32.is_gt(next_health, 0.0), alive)
      # A body the sun just finished off is not on fire any more, so the flag is
      # published per mob rather than left as the bare exposure test. That is the
      # only place it is set, and it is what the browser draws flames from.
      +burning = Bool.and(exposed, next_alive)
      +killed = Bool.and(exposed, Bool.not(next_alive))
      +next_drops = Bool.pick(List<&2, Drop>, killed, cons_drop(drop_for(head), drops), drops)
      +updated = make_mob_heading(id, kind, x, y, z, heading_x, heading_z, next_health, next_alive, burning, panic)
      +rest = sunlight_damage.go(tail, edits, seed, daylight, dt, next_drops)
      CombatResult{cons_mob(updated, combat_mobs(rest)), combat_drops(rest), Bool.or(exposed, combat_hit(rest))}

def sunlight_damage(
  +mobs: List<&2, Mob>, +edits: List<&2, WorldState.Edit>, +seed: Nat,
  +daylight: F32, +dt: F32, +drops: List<&2, Drop>
) -> CombatResult:
  sunlight_damage.go(mobs, edits, seed, daylight, dt, drops)

def make_drop_target(id: Nat, item: U32, amount: U32) -> DropTarget:
  DropFound{id, item, amount}

# A drop sits at a fractional x and z while the ground is keyed by cell, so
# the two are compared through the cell they are both in rather than as equal
# F32 values. The comparison stays in F32: this world uses a negative domain
# offset, and F32.to_nat folds every negative coordinate onto 0.
def same_ground_column(+gx: F32, +gz: F32, +x: F32, +z: F32) -> Bool:
  Bool.and(
  F32.is_eq(F32.floor(gx), F32.floor(x)), F32.is_eq(F32.floor(gz), F32.floor(z))
  )

def ground_y(grounds: List<&2, Ground>, +x: F32, +z: F32) -> F32:
  match grounds:
    case Nil{}:
      F32.neg(100.0)
    case Con{+head, +tail}:
      Ground{+gx, +gz, +gy} = head
      Bool.pick(
      F32, same_ground_column(gx, gz, x, z), gy, ground_y(tail, x, z)
      )

def step_drop(drop: Drop, +dt: F32, +grounds: List<&2, Ground>) -> Drop:
  Drop{+id, +item, +x, +y, +z, +amount, +velocity_y, +settled} = drop
  +floor = ground_y(grounds, x, z)
  +next_velocity = F32.sub(velocity_y, F32.mul(20.0, dt))
  +next_y = F32.add(y, F32.mul(next_velocity, dt))
  +landed = F32.is_le(next_y, floor)
  +resolved_y = Bool.pick(F32, landed, floor, next_y)
  +resolved_velocity = Bool.pick(F32, landed, 0.0, next_velocity)
  +resolved_settled = Bool.or(settled, landed)
  Bool.pick(Drop, settled, drop, Drop{id, item, x, resolved_y, z, amount, resolved_velocity, resolved_settled})

def step_drops(
  +drops: List<&2, Drop>, +dt: F32, +grounds: List<&2, Ground>
) -> List<&2, Drop>:
  match drops:
    case Nil{}:
      Nil{}
    case Con{+head, tail}:
      cons_drop(step_drop(head, dt, grounds), step_drops(tail, dt, grounds))

def nearest_drop(
  drops: List<&2, Drop>, +player_x: F32, +player_y: F32, +player_z: F32
) -> DropTarget:
  match drops:
    case Nil{}:
      DropMissing{}
    case Con{+head, tail}:
      Drop{id, item, x, y, z, amount, velocity_y, settled} = head
      +dx = F32.sub(player_x, x)
      +dy = F32.sub(player_y, y)
      +dz = F32.sub(player_z, z)
      +distance = F32.sqrt(F32.add(F32.add(F32.mul(dx, dx), F32.mul(dy, dy)), F32.mul(dz, dz)))
      Bool.pick(DropTarget, F32.is_lt(distance, fraction(15, 10)), make_drop_target(id, item, amount), nearest_drop(tail, player_x, player_y, player_z))

def remove_drop(drops: List<&2, Drop>, +target_id: Nat) -> List<&2, Drop>:
  match drops:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Drop{id, item, x, y, z, amount, velocity_y, settled} = head
      +rest = remove_drop(tail, target_id)
      Bool.pick(List<&2, Drop>, Nat.is_eq(id, target_id), tail, cons_drop(head, rest))

def far_away(+x: F32, +z: F32, +player_x: F32, +player_z: F32, +radius: F32) -> Bool:
  +dx = F32.sub(player_x, x)
  +dz = F32.sub(player_z, z)
  +distance = F32.sqrt(F32.add(F32.mul(dx, dx), F32.mul(dz, dz)))
  F32.is_lt(radius, distance)

def despawn(
  +mobs: List<&2, Mob>, +player_x: F32, +player_z: F32, +radius: F32
) -> List<&2, Mob>:
  match mobs:
    case Nil{}:
      Nil{}
    case Con{+head, tail}:
      Mob{+id, +kind, +x, +y, +z, +heading_x, +heading_z, +health, +alive, burning, panic} = head
      +rest = despawn(tail, player_x, player_z, radius)
      +gone = far_away(x, z, player_x, player_z, radius)
      Bool.pick(List<&2, Mob>, gone, rest, cons_mob(head, rest))

def count_alive(mobs: List<&2, Mob>, +total: Nat) -> Nat:
  match mobs:
    case Nil{}:
      total
    case Con{+head, tail}:
      Mob{id, kind, x, y, z, heading_x, heading_z, health, +alive, burning, panic} = head
      count_alive(tail, Bool.pick(Nat, alive, Nat.add(total, 1n), total))
