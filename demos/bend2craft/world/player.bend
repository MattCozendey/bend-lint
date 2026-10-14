import Base

type State is Data:
  State{x: F32, y: F32, z: F32, yaw: F32, pitch: F32, velocity_y: F32, grounded: Bool, health: F32, hunger: F32, air: F32, fall: F32, poison: F32}

type Direction is Data:
  Direction{x: F32, y: F32, z: F32}

def fraction(+numerator: U32, +denominator: U32) -> F32:
  F32.div(U32.to_f32(numerator), U32.to_f32(denominator))

def choose_f32(c: Bool, yes: F32, no: F32) -> F32:
  Bool.pick(F32, c, yes, no)

def clamp_f32(+value: F32, +low: F32, +high: F32) -> F32:
  +below = F32.is_lt(value, low)
  +above = F32.is_lt(high, value)
  choose_f32(below, low, choose_f32(above, high, value))

def create(+spawn_x: Nat, +spawn_z: Nat, +spawn_height: Nat) -> State:
  +x = F32.add(U32.to_f32(U32.from_nat(spawn_x)), fraction(1, 2))
  +y = F32.add(U32.to_f32(U32.from_nat(spawn_height)), fraction(5, 100))
  +z = F32.add(U32.to_f32(U32.from_nat(spawn_z)), fraction(1, 2))
  State{x, y, z, 0.0, F32.neg(fraction(18, 100)), 0.0, False{}, 20.0, 20.0, 10.0, 0.0, 0.0}

def state(
  x: F32, y: F32, z: F32, yaw: F32, pitch: F32, velocity_y: F32, grounded: Bool,
  health: F32, hunger: F32
) -> State:
  State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, 10.0, 0.0, 0.0}

def state_full(
  x: F32, y: F32, z: F32, yaw: F32, pitch: F32, velocity_y: F32, grounded: Bool,
  health: F32, hunger: F32, air: F32, fall: F32, poison: F32
) -> State:
  State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall, poison}

def clamp_world(state: State, +width: Nat, +depth: Nat) -> State:
  state

def solid(+block: U32) -> Bool:
  +crop = Bool.or(Bool.or(U32.is_eq(block, 16), U32.is_eq(block, 17)), Bool.or(U32.is_eq(block, 18), U32.is_eq(block, 19)))
  Bool.and(Bool.and(Bool.and(U32.is_ne(block, 0), U32.is_ne(block, 7)), Bool.and(U32.is_ne(block, 12), Bool.and(U32.is_ne(block, 15), Bool.and(U32.is_ne(block, 21), U32.is_ne(block, 24))))), Bool.not(crop))

def block_height(+block: U32) -> F32:
  Bool.pick(F32, U32.is_eq(block, 20), fraction(15, 16), 1.0)

def block_collides(+block: U32, +block_y: Nat, +player_y: F32) -> Bool:
  +base = U32.to_f32(U32.from_nat(block_y))
  +top = F32.add(base, block_height(block))
  Bool.and(solid(block), F32.is_lt(player_y, top))

def direction(state: State) -> Direction:
  State{x, y, z, +yaw, +pitch, velocity_y, grounded, health, hunger, air, fall, poison} = state
  +cos_pitch = F32.cos(pitch)
  Direction{
    F32.mul(F32.sin(yaw), cos_pitch),
    F32.sin(pitch),
    F32.neg(F32.mul(F32.cos(yaw), cos_pitch))
  }

def overlaps(state: State, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  State{+px, +py, +pz, yaw, pitch, velocity_y, grounded, health, hunger, air, fall, poison} = state
  +fx = U32.to_f32(U32.from_nat(x))
  +fy = U32.to_f32(U32.from_nat(y))
  +fz = U32.to_f32(U32.from_nat(z))
  +radius = fraction(3, 10)
  +height = fraction(18, 10)
  Bool.and(
    Bool.and(F32.is_lt(F32.sub(px, radius), F32.add(fx, 1.0)), F32.is_lt(fx, F32.add(px, radius))),
    Bool.and(
      Bool.and(F32.is_lt(py, F32.add(fy, 1.0)), F32.is_lt(fy, F32.add(py, height))),
      Bool.and(F32.is_lt(F32.sub(pz, radius), F32.add(fz, 1.0)), F32.is_lt(fz, F32.add(pz, radius)))
    )
  )

def floor_nat(value: F32) -> Nat:
  U32.to_nat(F32.to_u32(value))

# The region is stored one y-plane at a time: a list of `height` planes, each a list
# of `width * depth` cells in x-major order within the plane.
#
# It was one flat list, and `region_block` walked it to the cell's index. That is a
# linear walk over every cell below the one asked for, so the cost of a lookup was the
# cell's position and the cost of a tick was the position of the player's own cells: a
# 2x2 chunk region is 32 x 20 x 32 cells, the player stands about a third of the way
# down, and every one of the roughly fifteen lookups a step makes walked the same
# several thousand cells. Measured, one tick cost 0.25 ms against a 16 x 20 x 16 region
# and 1.00 ms against the 32 x 20 x 32 one — a factor of four for a factor of four in
# cells, which is the signature of the index rather than of the work.
#
# Two levels cost `height + width * depth` in the worst case and about `height / 2 +
# width * depth / 2` in practice, which is 522 cells for the region the client ships
# against 6,272 for the flat walk. A lookup outside the region is also cheaper now: it
# runs off the end of the plane list and finds an empty plane, where the flat walk ran
# off the end of all 20,480 cells.
def list_at(index: Nat, blocks: List<&2, U32>) -> U32:
  match index blocks:
    case 0n Nil{}:
      1
    case 0n h <> t:
      h
    case 1n+p Nil{}:
      1
    case 1n+p h <> t:
      list_at(p, t)

# The plane at this height, or an empty plane when the height is outside the region.
def plane_at(+index: Nat, planes: List<&2, List<&2, U32>>) -> List<&2, U32>:
  match index planes:
    case 0n Nil{}:
      []
    case 0n h <> t:
      h
    case 1n+p Nil{}:
      []
    case 1n+p h <> t:
      plane_at(p, t)

def region_index(+width: Nat, +x: Nat, +z: Nat) -> Nat:
  Nat.add(x, Nat.mul(width, z))

def region_block.if(block: U32, valid: Bool) -> U32:
  match valid:
    case True{}:
      block
    case False{}:
      1

def region_block(
  planes: List<&2, List<&2, U32>>, +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat, +x: Nat, +y: Nat, +z: Nat
) -> U32:
  +valid_x = Nat.is_ge(x, origin_x) && Nat.is_lt(x, Nat.add(origin_x, width))
  +valid_y = Nat.is_ge(y, origin_y) && Nat.is_lt(y, Nat.add(origin_y, height))
  +valid_z = Nat.is_ge(z, origin_z) && Nat.is_lt(z, Nat.add(origin_z, depth))
  +valid = Bool.and(Bool.and(valid_x, valid_y), valid_z)
  +local_x = Nat.sub(x, origin_x)
  +local_y = Nat.sub(y, origin_y)
  +local_z = Nat.sub(z, origin_z)
  region_block.if(
    list_at(region_index(width, local_x, local_z), plane_at(local_y, planes)),
    valid
  )

def scan_z(
  +remaining: Nat, +x: Nat, +y: Nat, +z: Nat,
  +blocks: List<&2, List<&2, U32>>, +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat, +player_y: F32
) -> Bool:
  match remaining:
    case 0n:
      False{}
    case 1n+p:
      Bool.or(
        block_collides(region_block(blocks, origin_x, origin_y, origin_z, width, height, depth, x, y, z), y, player_y),
        scan_z(p, x, y, Nat.add(z, 1n), blocks, origin_x, origin_y, origin_z, width, height, depth, player_y)
      )

def scan_y(
  +remaining: Nat, +x: Nat, +y: Nat, +min_z: Nat, +z_count: Nat,
  +blocks: List<&2, List<&2, U32>>, +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat, +player_y: F32
) -> Bool:
  match remaining:
    case 0n:
      False{}
    case 1n+p:
      Bool.or(
        scan_z(z_count, x, y, min_z, blocks, origin_x, origin_y, origin_z, width, height, depth, player_y),
        scan_y(p, x, Nat.add(y, 1n), min_z, z_count, blocks, origin_x, origin_y, origin_z, width, height, depth, player_y)
      )

def scan_x(
  +remaining: Nat, +x: Nat, +min_y: Nat, +y_count: Nat,
  +min_z: Nat, +z_count: Nat, +blocks: List<&2, List<&2, U32>>,
  +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat, +player_y: F32
) -> Bool:
  match remaining:
    case 0n:
      False{}
    case 1n+p:
      Bool.or(
        scan_y(y_count, x, min_y, min_z, z_count, blocks, origin_x, origin_y, origin_z, width, height, depth, player_y),
        scan_x(p, Nat.add(x, 1n), min_y, y_count, min_z, z_count, blocks, origin_x, origin_y, origin_z, width, height, depth, player_y)
      )

def collides(
  state: State, +x: F32, +y: F32, +z: F32, +blocks: List<&2, List<&2, U32>>,
  +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat
) -> Bool:
  +min_x = floor_nat(F32.sub(x, fraction(3, 10)))
  +max_x = floor_nat(F32.add(x, fraction(3, 10)))
  +min_y = floor_nat(F32.add(y, fraction(1, 10000)))
  +max_y = floor_nat(F32.sub(F32.add(y, fraction(18, 10)), fraction(1, 10000)))
  +min_z = floor_nat(F32.sub(z, fraction(3, 10)))
  +max_z = floor_nat(F32.add(z, fraction(3, 10)))
  scan_x(
    Nat.add(Nat.sub(max_x, min_x), 1n), min_x, min_y,
    Nat.add(Nat.sub(max_y, min_y), 1n), min_z,
    Nat.add(Nat.sub(max_z, min_z), 1n), blocks,
    origin_x, origin_y, origin_z, width, height, depth, y
  )

def held(+keys: U32, +mask: U32) -> Bool:
  U32.is_ne(U32.and(keys, mask), 0)

def input_axis(positive: Bool, negative: Bool) -> F32:
  choose_f32(positive, 1.0, choose_f32(negative, F32.neg(1.0), 0.0))

def step.vertical.hit(
  x: F32, y: F32, z: F32, yaw: F32, pitch: F32, next_y: F32, falling: Bool,
  +health: F32, +hunger: F32, +air: F32, +fall: F32, +poison: F32, +in_water: Bool
) -> State:
  match falling:
    case True{}:
      +impact = choose_f32(in_water, 0.0, choose_f32(F32.is_gt(fall, 3.0), F32.sub(fall, 3.0), 0.0))
      +next_health = clamp_f32(F32.sub(health, impact), 0.0, 20.0)
      State{x, F32.add(U32.to_f32(U32.from_nat(floor_nat(next_y))), 1.0), z, yaw, pitch, 0.0, True{}, next_health, hunger, air, 0.0, poison}
    case False{}:
      +top = floor_nat(F32.add(next_y, fraction(18, 10)))
      State{x, F32.sub(U32.to_f32(U32.from_nat(top)), fraction(18, 10)), z, yaw, pitch, 0.0, False{}, health, hunger, air, 0.0, poison}

def step.vertical(
  x: F32, y: F32, z: F32, yaw: F32, pitch: F32, velocity_y: F32,
  next_y: F32, falling: Bool, blocked: Bool, health: F32, hunger: F32,
  air: F32, fall: F32, poison: F32, in_water: Bool
) -> State:
  match blocked:
    case False{}:
      State{x, next_y, z, yaw, pitch, velocity_y, False{}, health, hunger, air, fall, poison}
    case True{}:
      step.vertical.hit(x, y, z, yaw, pitch, next_y, falling, health, hunger, air, fall, poison, in_water)

def step.respawn(
  state: State, +spawn_x: Nat, +spawn_z: Nat, +spawn_height: Nat, fallen: Bool
) -> State:
  match fallen:
    case False{}:
      state
    case True{}:
      create(spawn_x, spawn_z, spawn_height)

def step.fallen(state: State) -> Bool:
  State{ x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall, poison } = state
  F32.is_lt(y, F32.neg(10.0))

def is_water(+block: U32) -> Bool:
  U32.is_eq(block, 7)

def water_contact(blocks: List<&2, U32>) -> Bool:
  match blocks:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Bool.or(is_water(head), water_contact(tail))

def head_in_water(
  blocks: List<&2, List<&2, U32>>, +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat, +x: F32, +y: F32, +z: F32
) -> Bool:
  is_water(region_block(blocks, origin_x, origin_y, origin_z, width, height, depth,
    floor_nat(x), floor_nat(F32.add(y, fraction(162, 100))), floor_nat(z)))

# The feet cell controls swim buoyancy; using the upper body would stop the
# upward impulse before the player can clear a one-block shoreline.
def body_in_water(
  blocks: List<&2, List<&2, U32>>, +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat, +x: F32, +y: F32, +z: F32
) -> Bool:
  is_water(region_block(blocks, origin_x, origin_y, origin_z, width, height, depth,
    floor_nat(x), floor_nat(y), floor_nat(z)))

def poison_duration() -> F32:
  10.0

def poison_tick(state: State, +seconds: F32) -> State:
  State{+x, +y, +z, +yaw, +pitch, +velocity_y, grounded, +health, +hunger, +air, +fall, +old_poison} = state
  State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall, F32.add(old_poison, seconds)}

def drown_tick(state: State, +dt: F32, +head_under: Bool) -> State:
  State{+x, +y, +z, +yaw, +pitch, +velocity_y, grounded, +health, +hunger, +air, +fall, +poison} = state
  +next_air = choose_f32(head_under, F32.sub(air, dt), choose_f32(F32.is_lt(air, 10.0), F32.add(air, F32.mul(dt, 5.0)), air))
  +clamped_air = clamp_f32(next_air, 0.0, 10.0)
  +drowning = Bool.and(head_under, F32.is_eq(clamped_air, 0.0))
  +next_health = choose_f32(drowning, F32.sub(health, F32.mul(dt, 2.0)), health)
  State{x, y, z, yaw, pitch, velocity_y, grounded, clamp_f32(next_health, 0.0, 20.0), hunger, clamped_air, fall, poison}

def tick_survival(state: State, +dt: F32, +sprinting: Bool) -> State:
  State{+x, +y, +z, +yaw, +pitch, +velocity_y, grounded, +health, +hunger, +air, +fall, +poison} = state
  +loss_rate = choose_f32(sprinting, fraction(1, 10), fraction(1, 50))
  +hunger_loss = F32.mul(dt, loss_rate)
  +raw_hunger = F32.sub(hunger, hunger_loss)
  +starving = Bool.or(F32.is_lt(raw_hunger, 0.0), F32.is_eq(raw_hunger, 0.0))
  +next_hunger = clamp_f32(raw_hunger, 0.0, 20.0)
  +damage = F32.mul(dt, fraction(1, 5))
  +raw_health = choose_f32(starving, F32.sub(health, damage), health)
  +poisoned = F32.is_gt(poison, 0.0)
  +after_poison = choose_f32(poisoned, F32.sub(raw_health, F32.mul(dt, 1.0)), raw_health)
  +next_poison = choose_f32(poisoned, F32.sub(poison, dt), 0.0)
  +clamped_poison = choose_f32(F32.is_lt(next_poison, 0.0), 0.0, next_poison)
  +well_fed = Bool.and(F32.is_ge(next_hunger, 18.0), Bool.and(F32.is_lt(after_poison, 20.0), Bool.not(poisoned)))
  +regen = choose_f32(well_fed, F32.mul(dt, fraction(1, 4)), 0.0)
  +regen_drain = choose_f32(well_fed, F32.mul(dt, fraction(3, 10)), 0.0)
  +already_dead = F32.is_le(health, 0.0)
  +next_health = choose_f32(already_dead, health, clamp_f32(F32.add(after_poison, regen), 0.0, 20.0))
  +final_hunger = clamp_f32(F32.sub(next_hunger, regen_drain), 0.0, 20.0)
  State{x, y, z, yaw, pitch, velocity_y, grounded, next_health, final_hunger, air, fall, clamped_poison}

def alive(state: State) -> Bool:
  State{+x, +y, +z, +yaw, +pitch, +velocity_y, grounded, +health, +hunger, +air, +fall, +poison} = state
  F32.is_gt(health, 0.0)

def damage(state: State, +amount: F32) -> State:
  State{+x, +y, +z, +yaw, +pitch, +velocity_y, grounded, +health, +hunger, +air, +fall, +poison} = state
  +already_dead = F32.is_le(health, 0.0)
  +next_health = choose_f32(already_dead, health, clamp_f32(F32.sub(health, amount), 0.0, 20.0))
  State{x, y, z, yaw, pitch, velocity_y, grounded, next_health, hunger, air, fall, poison}

def lava_contact(blocks: List<&2, U32>) -> Bool:
  match blocks:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Bool.or(U32.is_eq(head, 21), lava_contact(tail))

def lava_damage(state: State, +dt: F32) -> State:
  damage(state, F32.mul(dt, 4.0))

def eat(state: State, +nutrition: F32) -> State:
  State{+x, +y, +z, +yaw, +pitch, +velocity_y, grounded, +health, +hunger, +air, +fall, +poison} = state
  +space = F32.sub(20.0, hunger)
  +amount = choose_f32(F32.is_lt(space, nutrition), space, nutrition)
  +valid = Bool.and(F32.is_gt(nutrition, 0.0), F32.is_lt(hunger, 20.0))
  +next_hunger = choose_f32(valid, F32.add(hunger, amount), hunger)
  State{x, y, z, yaw, pitch, velocity_y, grounded, health, next_hunger, air, fall, poison}

def step.values(
  +x: F32, +y: F32, +z: F32, +yaw: F32, +pitch: F32, +velocity_y: F32, +grounded: Bool,
  +health: F32, +hunger: F32, +air: F32, +fall: F32, +poison: F32,
  +keys: U32, +dt: F32, +blocks: List<&2, List<&2, U32>>,
  +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat,
  +spawn_x: Nat, +spawn_z: Nat, +spawn_height: Nat
) -> State:
  +forward = input_axis(held(keys, 1), held(keys, 4))
  +strafe = input_axis(held(keys, 8), held(keys, 2))
  +length = F32.sqrt(F32.add(F32.mul(forward, forward), F32.mul(strafe, strafe)))
  +safe_length = choose_f32(F32.is_eq(length, 0.0), 1.0, length)
  +normal_forward = F32.div(forward, safe_length)
  +normal_strafe = F32.div(strafe, safe_length)
  +moving = Bool.not(F32.is_eq(length, 0.0))
  +sneaking = held(keys, 64)
  +sprinting = Bool.and(held(keys, 32), Bool.and(moving, Bool.not(sneaking)))
  +in_water = body_in_water(blocks, origin_x, origin_y, origin_z, width, height, depth, x, y, z)
  +head_under = head_in_water(blocks, origin_x, origin_y, origin_z, width, height, depth, x, y, z)
  +swim_speed = choose_f32(sprinting, 4.0, 2.5)
  +walk_speed = choose_f32(sneaking, fraction(13, 10), choose_f32(sprinting, fraction(135, 20), fraction(45, 10)))
  +speed = choose_f32(in_water, swim_speed, walk_speed)
  +dx = F32.mul(
    F32.add(F32.mul(F32.sin(yaw), normal_forward), F32.mul(F32.cos(yaw), normal_strafe)),
    F32.mul(speed, dt)
  )
  +dz = F32.mul(
    F32.add(F32.mul(F32.neg(F32.cos(yaw)), normal_forward), F32.mul(F32.sin(yaw), normal_strafe)),
    F32.mul(speed, dt)
  )
  +candidate_x = F32.add(x, dx)
  +x_blocked = collides(State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall, poison}, candidate_x, y, z, blocks, origin_x, origin_y, origin_z, width, height, depth)
  +next_x = choose_f32(x_blocked, x, candidate_x)
  +candidate_z = F32.add(z, dz)
  +z_blocked = collides(State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall, poison}, next_x, y, candidate_z, blocks, origin_x, origin_y, origin_z, width, height, depth)
  +next_z = choose_f32(z_blocked, z, candidate_z)
  +jumping = Bool.and(held(keys, 16), Bool.or(grounded, in_water))
  +surface_kick = Bool.and(in_water, Bool.and(moving, Bool.not(held(keys, 16))))
  # Preserve the land-jump impulse while swimming so the feet can clear a bank.
  +jump_velocity = choose_f32(jumping, fraction(70, 10), velocity_y)
  +kick_up = F32.add(velocity_y, F32.mul(8.0, dt))
  +kick = choose_f32(F32.is_lt(kick_up, 1.0), kick_up, 1.0)
  +rise = choose_f32(jumping, jump_velocity, choose_f32(surface_kick, kick, velocity_y))
  +gravity = choose_f32(in_water, 4.0, fraction(20, 1))
  +next_velocity = F32.sub(rise, F32.mul(gravity, dt))
  +sink_cap = choose_f32(in_water, F32.neg(3.0), F32.neg(30.0))
  +capped_velocity = choose_f32(F32.is_lt(next_velocity, sink_cap), sink_cap, next_velocity)
  +dy = F32.mul(capped_velocity, dt)
  +next_y = F32.add(y, dy)
  +blocked_y = collides(State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall, poison}, next_x, next_y, next_z, blocks, origin_x, origin_y, origin_z, width, height, depth)
  +falling_down = F32.is_lt(dy, 0.0)
  +fall_next = choose_f32(in_water, 0.0, choose_f32(blocked_y, fall, choose_f32(falling_down, F32.add(fall, F32.neg(dy)), fall)))
  +resolved = step.vertical(next_x, y, next_z, yaw, pitch, capped_velocity, next_y, F32.is_lt(dy, 0.0), blocked_y, health, hunger, air, fall_next, poison, in_water)
  +breathed = drown_tick(step.respawn(resolved, spawn_x, spawn_z, spawn_height, step.fallen(resolved)), dt, head_under)
  tick_survival(breathed, dt, Bool.and(sprinting, Bool.not(in_water)))

def step(
  state: State, keys: U32, dt: F32, blocks: List<&2, List<&2, U32>>,
  +origin_x: Nat, +origin_y: Nat, +origin_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat,
  +spawn_x: Nat, +spawn_z: Nat, +spawn_height: Nat
) -> State:
  State{+x, +y, +z, +yaw, +pitch, +velocity_y, grounded, +health, +hunger, +air, +fall, +poison} = state
  step.values(x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall, poison, keys, dt, blocks,
    origin_x, origin_y, origin_z, width, height, depth, spawn_x, spawn_z, spawn_height)

type RayResult is Data:
  NoHit{}
  Hit{hit_x: Nat, hit_y: Nat, hit_z: Nat, place_x: Nat, place_y: Nat, place_z: Nat, has_place: Bool}

def raycast.loop(
  +remaining: Nat, +index: Nat, +dx: F32, +dy: F32, +dz: F32,
  +origin_x: F32, +origin_y: F32, +origin_z: F32,
  +blocks: List<&2, List<&2, U32>>, +region_x: Nat, +region_y: Nat, +region_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat,
  same_cell: Bool, empty: Bool, block_value: U32, +cell_x: Nat, +cell_y: Nat, +cell_z: Nat,
  +last_x: Nat, +last_y: Nat, +last_z: Nat, has_last: Bool
) -> RayResult:
  match remaining:
    case 0n:
      NoHit{}
    case 1n+p:
      match same_cell:
        case True{}:
          +next_index = Nat.add(index, 1n)
          +distance = F32.add(fraction(1, 10), F32.mul(U32.to_f32(U32.from_nat(next_index)), fraction(5, 100)))
          +next_x = floor_nat(F32.add(origin_x, F32.mul(dx, distance)))
          +next_y = floor_nat(F32.add(origin_y, F32.mul(dy, distance)))
          +next_z = floor_nat(F32.add(origin_z, F32.mul(dz, distance)))
          +same_next = Bool.and(Bool.and(Nat.is_eq(next_x, cell_x), Nat.is_eq(next_y, cell_y)), Nat.is_eq(next_z, cell_z))
          +next_block = region_block(blocks, region_x, region_y, region_z, width, height, depth, next_x, next_y, next_z)
          raycast.loop(p, next_index, dx, dy, dz, origin_x, origin_y, origin_z, blocks, region_x, region_y, region_z, width, height, depth, same_next, U32.is_eq(next_block, 0), next_block, next_x, next_y, next_z, last_x, last_y, last_z, has_last)
        case False{}:
          match empty:
            case True{}:
              +next_index = Nat.add(index, 1n)
              +distance = F32.add(fraction(1, 10), F32.mul(U32.to_f32(U32.from_nat(next_index)), fraction(5, 100)))
              +next_x = floor_nat(F32.add(origin_x, F32.mul(dx, distance)))
              +next_y = floor_nat(F32.add(origin_y, F32.mul(dy, distance)))
              +next_z = floor_nat(F32.add(origin_z, F32.mul(dz, distance)))
              +same_next = Bool.and(Bool.and(Nat.is_eq(next_x, cell_x), Nat.is_eq(next_y, cell_y)), Nat.is_eq(next_z, cell_z))
              +next_block = region_block(blocks, region_x, region_y, region_z, width, height, depth, next_x, next_y, next_z)
              raycast.loop(p, next_index, dx, dy, dz, origin_x, origin_y, origin_z, blocks, region_x, region_y, region_z, width, height, depth, same_next, U32.is_eq(next_block, 0), next_block, next_x, next_y, next_z, cell_x, cell_y, cell_z, True{})
            case False{}:
              Hit{cell_x, cell_y, cell_z, last_x, last_y, last_z, has_last}

def raycast.start(
  state: State, direction_value: Direction, +blocks: List<&2, List<&2, U32>>,
  +region_x: Nat, +region_y: Nat, +region_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat
) -> RayResult:
  State{+px, +py, +pz, yaw, pitch, velocity_y, grounded, health, hunger, air, fall, poison} = state
  Direction{+dx, +dy, +dz} = direction_value
  +origin_y = F32.add(py, fraction(162, 100))
  +cell_x = floor_nat(px)
  +cell_y = floor_nat(origin_y)
  +cell_z = floor_nat(pz)
  +block = region_block(blocks, region_x, region_y, region_z, width, height, depth, cell_x, cell_y, cell_z)
  raycast.loop(160n, 0n, dx, dy, dz, px, origin_y, pz, blocks, region_x, region_y, region_z, width, height, depth, False{}, U32.is_eq(block, 0), block, cell_x, cell_y, cell_z, 0n, 0n, 0n, False{})

def raycast(
  +state: State, blocks: List<&2, List<&2, U32>>,
  +region_x: Nat, +region_y: Nat, +region_z: Nat,
  +width: Nat, +height: Nat, +depth: Nat
) -> RayResult:
  raycast.start(state, direction(state), blocks, region_x, region_y, region_z, width, height, depth)
