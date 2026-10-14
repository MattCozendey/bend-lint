import Base
import ./entities.bend as Entities

# Server-owned mobs and drops for multiplayer.
#
# The single-player rules in entities.bend chase and threaten one player. A
# shared world has several, so each mob steps toward the nearest player, a mob
# is only despawned when it is far from every player, and attacks and pickups
# come from a player whose pose the server knows. The server (never a browser)
# calls these with the mob list it owns.

type Target is Data:
  Target{x: F32, y: F32, z: F32}

type Pickup is Data:
  Pickup{drops: List<&2, Entities.Drop>, ok: Bool, item: U32, amount: U32}

def make_target(x: F32, y: F32, z: F32) -> Target:
  Target{x, y, z}

def cons_target(target: Target, tail: List<&2, Target>) -> List<&2, Target>:
  Con{target, tail}

# The strongest hit a player can deal (the diamond sword); anything above it
# is clamped, so a client cannot one-shot a mob by claiming a bigger number.
def max_damage() -> F32:
  7.0

def melee_range() -> F32:
  4.0

def ranged_range() -> F32:
  16.0

# A pickup reaches a little further than single player's 1.5 so the pose the
# server last heard of still counts on a busy network.
def pickup_range() -> F32:
  2.5

def far_coordinate() -> F32:
  1000000.0

def distance_sq(+ax: F32, +az: F32, +bx: F32, +bz: F32) -> F32:
  +dx = F32.sub(ax, bx)
  +dz = F32.sub(az, bz)
  F32.add(F32.mul(dx, dx), F32.mul(dz, dz))

def target_x(target: Target) -> F32:
  Target{+x, y, z} = target
  x

def target_z(target: Target) -> F32:
  Target{x, y, +z} = target
  z

def closer(+a: Target, +b: Target, +x: F32, +z: F32) -> Target:
  Bool.pick(Target,
    F32.is_lt(distance_sq(target_x(a), target_z(a), x, z), distance_sq(target_x(b), target_z(b), x, z)),
    a, b)

# The target nearest to (x, z); `best` when the list is empty.
def nearest(targets: List<&2, Target>, +x: F32, +z: F32, +best: Target) -> Target:
  match targets:
    case Nil{}:
      best
    case Con{+head, tail}:
      nearest(tail, x, z, closer(head, best, x, z))

def mob_x(mob: Entities.Mob) -> F32:
  Entities.Mob{id, kind, +x, y, z, heading_x, heading_z, health, alive, burning, panic} = mob
  x

def mob_z(mob: Entities.Mob) -> F32:
  Entities.Mob{id, kind, x, y, +z, heading_x, heading_z, health, alive, burning, panic} = mob
  z

def far_target() -> Target:
  Target{far_coordinate(), 0.0, far_coordinate()}

def step.one(
  +mob: Entities.Mob, target: Target, +dt: F32, +time: F32, +offset: Nat, +region: Entities.Region
) -> Entities.Mob:
  Target{+x, y, +z} = target
  Entities.step_grounded(mob, x, z, dt, time, offset, region)

# Entities.step_world, with each mob chasing (or fleeing) the nearest player.
# `regions` holds one block window per mob, in the same order.
def step_world(
  mobs: List<&2, Entities.Mob>, +targets: List<&2, Target>, +dt: F32, +time: F32, +offset: Nat,
  regions: List<&2, Entities.Region>
) -> List<&2, Entities.Mob>:
  match mobs:
    case Nil{}:
      Nil{}
    case Con{+head, tail}:
      match regions:
        case Nil{}:
          Nil{}
        case Con{+region, rest}:
          +target = nearest(targets, mob_x(head), mob_z(head), far_target())
          Entities.cons_mob(
            step.one(head, target, dt, time, offset, region),
            step_world(tail, targets, dt, time, offset, rest)
          )

def near_any(targets: List<&2, Target>, +x: F32, +z: F32, +radius: F32) -> Bool:
  match targets:
    case Nil{}:
      False{}
    case Con{+head, tail}:
      Bool.or(
        F32.is_le(distance_sq(target_x(head), target_z(head), x, z), F32.mul(radius, radius)),
        near_any(tail, x, z, radius)
      )

# Removes the mobs farther than `radius` from every player.
def despawn(
  mobs: List<&2, Entities.Mob>, +targets: List<&2, Target>, +radius: F32
) -> List<&2, Entities.Mob>:
  match mobs:
    case Nil{}:
      Nil{}
    case Con{+head, tail}:
      +rest = despawn(tail, targets, radius)
      Bool.pick(List<&2, Entities.Mob>, near_any(targets, mob_x(head), mob_z(head), radius), Entities.cons_mob(head, rest), rest)

def clamp_damage(+damage: F32) -> F32:
  F32.max(0.0, F32.min(damage, max_damage()))

# A player's hit, from the pose the server holds for that player: the damage
# is clamped and the reach is melee or bow range.
def attack(
  +mobs: List<&2, Entities.Mob>, +target_id: Nat, +damage: F32,
  +x: F32, +y: F32, +z: F32, +ranged: Bool, +drops: List<&2, Entities.Drop>
) -> Entities.CombatResult:
  Entities.attack(mobs, target_id, clamp_damage(damage), x, y, z,
    Bool.pick(F32, ranged, ranged_range(), melee_range()), drops)

def pickup.take(
  +drops: List<&2, Entities.Drop>, +id: Nat, +item: U32, +amount: U32, +within: Bool
) -> Pickup:
  match within:
    case True{}:
      Pickup{Entities.remove_drop(drops, id), True{}, item, amount}
    case False{}:
      Pickup{drops, False{}, 0, 0}

def pickup.find(
  scan: List<&2, Entities.Drop>, +drops: List<&2, Entities.Drop>, +id: Nat, +x: F32, +y: F32, +z: F32
) -> Pickup:
  match scan:
    case Nil{}:
      Pickup{drops, False{}, 0, 0}
    case Con{+head, tail}:
      Entities.Drop{+drop_id, +item, +dx, +dy, +dz, +amount, velocity_y, settled} = head
      +ex = F32.sub(dx, x)
      +ey = F32.sub(dy, y)
      +ez = F32.sub(dz, z)
      +reach = F32.mul(pickup_range(), pickup_range())
      +within = F32.is_le(F32.add(F32.add(F32.mul(ex, ex), F32.mul(ey, ey)), F32.mul(ez, ez)), reach)
      Bool.pick(Pickup, Nat.is_eq(drop_id, id),
        pickup.take(drops, id, item, amount, within),
        pickup.find(tail, drops, id, x, y, z))

# A player picking up one drop: it must exist and be within reach of the
# player's pose; it then leaves the world.
def pickup(+drops: List<&2, Entities.Drop>, +id: Nat, +x: F32, +y: F32, +z: F32) -> Pickup:
  pickup.find(drops, drops, id, x, y, z)

def pickup_drops(result: Pickup) -> List<&2, Entities.Drop>:
  Pickup{+drops, ok, item, amount} = result
  drops

def pickup_ok(result: Pickup) -> Bool:
  Pickup{drops, +ok, item, amount} = result
  ok

def pickup_item(result: Pickup) -> U32:
  Pickup{drops, ok, +item, amount} = result
  item

def pickup_amount(result: Pickup) -> U32:
  Pickup{drops, ok, item, +amount} = result
  amount
