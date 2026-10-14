import Base
import ./world.bend as World
import ./world_state.bend as WorldState
import ./structures.bend as Structures
import ./village_path.bend as Path

type Villager is Data:
  Villager{id: Nat, profession: U32, x: F32, y: F32, z: F32, home_x: Nat, home_z: Nat, resting: Bool}

type VillagerLookup is Data:
  VillagerFound{villager: Villager}
  VillagerMissing{}

type TradeOffer is Data:
  TradeOffer{cost_item: U32, cost_amount: U32, reward_item: U32, reward_amount: U32, ok: Bool}

type DoorResult is Data:
  DoorResult{edits: List<&2, WorldState.Edit>, changed: Bool}

type SleepResult is Data:
  SleepResult{ok: Bool, next_tick: Nat}


def half() -> F32:
  F32.div(1.0, 2.0)

def coordinate(+value: Nat) -> F32:
  U32.to_f32(U32.from_nat(value))

def make_villager(
  id: Nat, profession: U32, home_x: Nat, home_z: Nat,
  +x: Nat, +z: Nat, +base: Nat, resting: Bool
) -> Villager:
  Villager{
    id,
    profession,
    F32.add(coordinate(x), half()),
    U32.to_f32(U32.from_nat(Nat.add(base, 1n))),
    F32.add(coordinate(z), half()),
    home_x,
    home_z,
    resting
  }

def spawn(+seed: Nat) -> List<&2, Villager>:
  +origin_x = Structures.village_origin_x(seed)
  +origin_z = Structures.village_origin_z(seed)
  +base = World.column_height(seed, origin_x, origin_z)
  +first = make_villager(0n, 1, origin_x, origin_z, Nat.add(origin_x, 1n), origin_z, base, True{})
  +second = make_villager(1n, 1, origin_x, origin_z, Nat.add(origin_x, 2n), origin_z, base, True{})
  +third = make_villager(2n, 2, origin_x, origin_z, origin_x, Nat.add(origin_z, 10n), base, True{})
  Con{third, Con{second, Con{first, Nil{}}}}

def path_grid.row(
  +remaining: Nat, +local_x: Nat, +seed: Nat, +edits: List<&2, WorldState.Edit>, +y: Nat,
  +x: Nat, +z: Nat, +mask: U32
) -> U32:
  match remaining:
    case 0n:
      mask
    case 1n+p:
      +feet = WorldState.block(edits, seed, x, y, z)
      +head = WorldState.block(edits, seed, x, Nat.add(y, 1n), z)
      +feet_open = Bool.or(Bool.or(U32.is_eq(feet, 0), U32.is_eq(feet, 13)), Bool.or(U32.is_eq(feet, 14), U32.is_eq(feet, 15)))
      +head_open = Bool.or(U32.is_eq(head, 0), Bool.or(U32.is_eq(head, 14), U32.is_eq(head, 15)))
      +open = Bool.and(feet_open, head_open)
      +bit = U32.shln(1, local_x)
      +next_mask = Bool.pick(U32, open, U32.or(mask, bit), mask)
      path_grid.row(p, Nat.add(local_x, 1n), seed, edits, y, Nat.add(x, 1n), z, next_mask)

def path_grid.fill(
  +remaining_rows: Nat, +row: Nat, +seed: Nat, +edits: List<&2, WorldState.Edit>, +y: Nat,
  +min_x: Nat, +min_z: Nat, +width: Nat, +rows: List<&2, U32>
) -> List<&2, U32>:
  match remaining_rows:
    case 0n:
      rows
    case 1n+p:
      +mask = path_grid.row(width, 0n, seed, edits, y, min_x, Nat.add(min_z, row), 0)
      path_grid.fill(p, Nat.sub(row, 1n), seed, edits, y, min_x, min_z, width, Con{mask, rows})

def path_grid(+seed: Nat, +edits: List<&2, WorldState.Edit>) -> List<&2, U32>:
  +origin_x = Structures.village_origin_x(seed)
  +origin_z = Structures.village_origin_z(seed)
  +base = World.column_height(seed, origin_x, origin_z)
  path_grid.fill(26n, 25n, seed, edits, Nat.add(base, 1n), 17n, 19n, 28n, Nil{})

def nighttime(+tick: Nat) -> Bool:
  +phase = Nat.mod(tick, 24n)
  Bool.or(Nat.is_lt(phase, 6n), Nat.is_ge(phase, 18n))

def target_offset(+tick: Nat, +id: Nat) -> F32:
  +phase = Nat.mod(Nat.add(tick, id), 5n)
  F32.sub(U32.to_f32(U32.from_nat(phase)), 2.0)

def floor_nat(value: F32) -> Nat:
  U32.to_nat(F32.to_u32(value))

def walkable(+seed: Nat, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  +feet = World.block(seed, x, y, z)
  +head = World.block(seed, x, Nat.add(y, 1n), z)
  Bool.and(Bool.or(Bool.or(U32.is_eq(feet, 0), U32.is_eq(feet, 13)), Bool.or(U32.is_eq(feet, 14), U32.is_eq(feet, 15))), U32.is_eq(head, 0))

def move_toward(+current: F32, +target: F32, +dt: F32) -> F32:
  +delta = F32.sub(target, current)
  +distance = F32.abs(delta)
  +step = F32.mul(0.8, dt)
  Bool.pick(F32, F32.is_lt(distance, step), target,
    F32.add(current, Bool.pick(F32, F32.is_lt(delta, 0.0), F32.neg(step), step)))

def step_one(villager: Villager, +seed: Nat, +grid: List<&2, U32>, +tick: Nat, +dt: F32) -> Villager:
  Villager{+id, +profession, +x, +y, +z, +home_x, +home_z, +resting} = villager
  +sleeping = nighttime(tick)
  +offset = target_offset(tick, id)
  +home_f = F32.add(coordinate(home_x), half())
  +bed_f_x = F32.add(coordinate(Nat.add(home_x, 2n)), half())
  +bed_f_z = F32.add(coordinate(Nat.add(home_z, 2n)), half())
  +target_x = Bool.pick(F32, sleeping, bed_f_x, F32.add(home_f, offset))
  +target_z = Bool.pick(F32, sleeping, bed_f_z, F32.sub(F32.add(coordinate(home_z), half()), offset))
  +path = Path.next(grid, floor_nat(x), floor_nat(z), floor_nat(target_x), floor_nat(target_z), 17n, 19n, 28n, 26n)
  Villager{
    id,
    profession,
    move_toward(x, Path.target_x(x, path), dt),
    y,
    move_toward(z, Path.target_z(z, path), dt),
    home_x,
    home_z,
    sleeping
  }

def step(
  +villagers: List<&2, Villager>, +seed: Nat, +grid: List<&2, U32>, +tick: Nat, +dt: F32
) -> List<&2, Villager>:
  match villagers:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Con{step_one(head, seed, grid, tick, dt), step(tail, seed, grid, tick, dt)}

def within_radius(
  +x: F32, +z: F32, +player_x: F32, +player_z: F32, +radius: F32
) -> Bool:
  +dx = F32.sub(x, player_x)
  +dz = F32.sub(z, player_z)
  +distance = F32.add(F32.mul(dx, dx), F32.mul(dz, dz))
  F32.is_lt(distance, F32.mul(radius, radius))

def step_near(
  +villagers: List<&2, Villager>, +seed: Nat, +grid: List<&2, U32>, +tick: Nat, +dt: F32,
  +player_x: F32, +player_z: F32, +radius: F32
) -> List<&2, Villager>:
  match villagers:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Villager{+id, +profession, +x, +y, +z, +home_x, +home_z, +resting} = head
      +near = within_radius(x, z, player_x, player_z, radius)
      +next = Bool.pick(Villager, near, step_one(head, seed, grid, tick, dt), head)
      Con{next, step_near(tail, seed, grid, tick, dt, player_x, player_z, radius)}

def open_door(
  +edits: List<&2, WorldState.Edit>, +seed: Nat, +x: Nat, +y: Nat, +z: Nat
) -> List<&2, WorldState.Edit>:
  +closed = U32.is_eq(WorldState.block(edits, seed, x, y, z), 14)
  +with_bottom = WorldState.set(edits, x, y, z, 15)
  +with_top = WorldState.set(with_bottom, x, Nat.add(y, 1n), z, 15)
  Bool.pick(List<&2, WorldState.Edit>, closed, with_top, edits)

def open_for(villager: Villager, +seed: Nat, +edits: List<&2, WorldState.Edit>) -> List<&2, WorldState.Edit>:
  Villager{+id, +profession, +x, +y, +z, +home_x, +home_z, +resting} = villager
  +cx = floor_nat(x)
  +cy = floor_nat(y)
  +cz = floor_nat(z)
  +left = open_door(edits, seed, Nat.sub(cx, 1n), cy, cz)
  +right = open_door(left, seed, Nat.add(cx, 1n), cy, cz)
  +back = open_door(right, seed, cx, cy, Nat.sub(cz, 1n))
  open_door(back, seed, cx, cy, Nat.add(cz, 1n))

def open_doors(
  +villagers: List<&2, Villager>, +seed: Nat, +edits: List<&2, WorldState.Edit>
) -> List<&2, WorldState.Edit>:
  match villagers:
    case Nil{}:
      edits
    case Con{+head, +tail}:
      open_doors(tail, seed, open_for(head, seed, edits))

def near_position(+x: F32, +z: F32, +door_x: Nat, +door_z: Nat) -> Bool:
  +door_f_x = F32.add(coordinate(door_x), half())
  +door_f_z = F32.add(coordinate(door_z), half())
  +dx = F32.sub(x, door_f_x)
  +dz = F32.sub(z, door_f_z)
  F32.is_lt(F32.add(F32.mul(dx, dx), F32.mul(dz, dz)), 2.25)

def villager_near(
  +villagers: List<&2, Villager>, +door_x: Nat, +door_z: Nat
) -> Bool:
  match villagers:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Villager{+id, +profession, +x, +y, +z, +home_x, +home_z, +resting} = head
      Bool.or(near_position(x, z, door_x, door_z), villager_near(tail, door_x, door_z))

def door_edits(result: DoorResult) -> List<&2, WorldState.Edit>:
  DoorResult{edits, changed} = result
  edits

def door_changed(result: DoorResult) -> Bool:
  DoorResult{edits, changed} = result
  changed

# The open door cells (block 15) of the log, last edit first.
def open_door_cells(edits: List<&2, WorldState.Edit>, +acc: List<&2, WorldState.Edit>) -> List<&2, WorldState.Edit>:
  match edits:
    case Nil{}:
      acc
    case Con{+head, tail}:
      WorldState.Edit{+x, +y, +z, +block} = head
      open_door_cells(tail, Bool.pick(List<&2, WorldState.Edit>, U32.is_eq(block, 15), Con{head, acc}, acc))

def close_door(+close: Bool, +edits: List<&2, WorldState.Edit>, +seed: Nat, +x: Nat, +y: Nat, +z: Nat) -> List<&2, WorldState.Edit>:
  match close:
    case True{}:
      +has_lower = Bool.and(Nat.is_gt(y, 0n), U32.is_eq(WorldState.block(edits, seed, x, Nat.sub(y, 1n), z), 15))
      +bottom = Bool.pick(Nat, has_lower, Nat.sub(y, 1n), y)
      WorldState.set_many(edits, Con{WorldState.make_edit(x, bottom, z, 14), Con{WorldState.make_edit(x, Nat.add(bottom, 1n), z, 14), Nil{}}})
    case False{}:
      edits

def close_doors(
  doors: List<&2, WorldState.Edit>, +villagers: List<&2, Villager>, +seed: Nat,
  +player_x: F32, +player_z: F32, +edits: List<&2, WorldState.Edit>, +changed: Bool
) -> DoorResult:
  match doors:
    case Nil{}:
      DoorResult{edits, changed}
    case Con{+head, tail}:
      WorldState.Edit{+x, +y, +z, block} = head
      +clear = Bool.not(Bool.or(near_position(player_x, player_z, x, z), villager_near(villagers, x, z)))
      +still_open = U32.is_eq(WorldState.block(edits, seed, x, y, z), 15)
      +close = Bool.and(clear, still_open)
      close_doors(tail, villagers, seed, player_x, player_z, close_door(close, edits, seed, x, y, z), Bool.or(changed, close))

# Closes every open door no player or villager stands next to (both halves),
# and reports whether any closed. One pass collects the open door cells, then
# each is closed against the log: O(doors x edits) instead of re-walking the
# rest of the log for every edit, and every walk is a loop on the JavaScript
# target (benchmarks/edit-log.mjs measures it).
def update_doors_result(
  +villagers: List<&2, Villager>, +seed: Nat,
  +edits: List<&2, WorldState.Edit>, +player_x: F32, +player_z: F32
) -> DoorResult:
  close_doors(open_door_cells(edits, Nil{}), villagers, seed, player_x, player_z, edits, False{})

def update_doors(
  +villagers: List<&2, Villager>, +seed: Nat,
  +edits: List<&2, WorldState.Edit>, +player_x: F32, +player_z: F32
) -> List<&2, WorldState.Edit>:
  door_edits(update_doors_result(villagers, seed, edits, player_x, player_z))

def sleep(
  +villagers: List<&2, Villager>, +seed: Nat,
  +edits: List<&2, WorldState.Edit>, +player_x: F32, +player_z: F32, +tick: Nat
) -> SleepResult:
  +origin_x = Structures.village_origin_x(seed)
  +origin_z = Structures.village_origin_z(seed)
  +base = World.column_height(seed, origin_x, origin_z)
  +bed_x = Nat.add(origin_x, 2n)
  +bed_z = Nat.add(origin_z, 2n)
  +bed = WorldState.block(edits, seed, bed_x, Nat.add(base, 1n), bed_z)
  +ok = Bool.and(Bool.and(nighttime(tick), U32.is_eq(bed, 13)), near_position(player_x, player_z, bed_x, bed_z))
  SleepResult{ok, Bool.pick(Nat, ok, 6n, tick)}

def find(+villagers: List<&2, Villager>, +id: Nat) -> VillagerLookup:
  match villagers:
    case Nil{}:
      VillagerMissing{}
    case Con{+head, +tail}:
      Villager{+villager_id, profession, x, y, z, home_x, home_z, resting} = head
      Bool.pick(VillagerLookup, Nat.is_eq(villager_id, id), VillagerFound{head}, find(tail, id))

def near_player(villager: Villager, +player_x: F32, +player_z: F32) -> Bool:
  Villager{id, profession, +x, y, +z, home_x, home_z, resting} = villager
  +dx = F32.sub(player_x, x)
  +dz = F32.sub(player_z, z)
  F32.is_lt(F32.sqrt(F32.add(F32.mul(dx, dx), F32.mul(dz, dz))), 3.0)

def trade_found(+villager: Villager, +player_x: F32, +player_z: F32) -> TradeOffer:
  Villager{+id, +profession, +x, +y, +z, +home_x, +home_z, +resting} = villager
  +close = near_player(villager, player_x, player_z)
  TradeOffer{13, 4, 20, 1, Bool.and(close, U32.is_eq(profession, 1))}

def trade.lookup(
  lookup: VillagerLookup, +player_x: F32, +player_z: F32
) -> TradeOffer:
  match lookup:
    case VillagerMissing{}:
      TradeOffer{13, 4, 20, 1, False{}}
    case VillagerFound{villager}:
      trade_found(villager, player_x, player_z)

def trade(
  villagers: List<&2, Villager>, +target_id: Nat, player_x: F32, player_z: F32
) -> TradeOffer:
  trade.lookup(find(villagers, target_id), player_x, player_z)
