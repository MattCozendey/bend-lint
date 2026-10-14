import Base
import ../world/player.bend as Player
import ../world/world_state.bend as WorldState
import ./frame.bend as Frame
import ./bag.bend as Bag
import ../world/inventory.bend as Inventory
import ./save.bend as Migration
import ./net.bend as Net
import ../world/entities.bend as Entities
import ./size.bend as Size
import ./play.bend as Play
import ./room.bend as Room

# A room, from the client's side, headless: where the room hears the client, what the client
# does with the room's corrections, which mob is under the crosshair, which item is asked
# for, and what a mob's harm and an item's pickup do to the client.

def require(condition: Bool, message: String) -> IO(Unit):
  match condition:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "room: " ++ message)

def check(condition: Bool, message: String) -> IO(Unit):
  require(condition, message)

# A client on the generated world: the save a client reads is the working directory's, so it
# is emptied first, and the one that starts is the shipped size's.
def empty_world() -> IO(Unit):
  do IO<Unit>:
    Unit <- Play.save_text.at(Play.stash_path(Play.path()), "")
    Play.save_text.at(Play.path(),
      Migration.encode(Migration.Snapshot{Frame.seed(), WorldState.empty()}))

def started() -> IO(Play.Client):
  Play.start(Size.size_128())

def client_or_die(maybe: Maybe<&1, Play.Client>) -> IO(Play.Client):
  match maybe:
    case Some{state}:
      IO.pure(Play.Client, state)
    case None{}:
      IO.die(Play.Client, 1, "room: the tick closed the client")

def looked_down(state: Play.Client) -> IO(Play.Client):
  do IO<Play.Client>:
    looked : Maybe<&1, Play.Client> <- Play.tick.events(
      [Look{0.0, F32.neg(40.0)}], state)
    client_or_die(looked)

def held_total(slots: List<&2, Inventory.Slot>, +total: U32) -> U32:
  match slots:
    case Nil{}:
      total
    case slot <> rest:
      held_total(rest, U32.add(total, Inventory.slot_count_value(slot)))

# --- a room's coordinates ------------------------------------------------------
#
# A room counts a player from the world's origin and the client from its movement window's
# first cell. What the client says of itself is the world's: it spawns in the middle of world
# cell (25, 25). And where the room puts it back to after a move it refused is where it then
# says it is, on both sides of the origin.
def place_near(place: Net.Place, wx: F32, wy: F32, wz: F32) -> Bool:
  Net.Place{x, y, z, yaw, pitch} = place
  Bool.and(F32.is_lt(F32.abs(F32.sub(x, wx)), 0.001),
    Bool.and(F32.is_lt(F32.abs(F32.sub(y, wy)), 0.001), F32.is_lt(F32.abs(F32.sub(z, wz)), 0.001)))

# Where the room would say the client's player stands.
def placed(client: Play.Client) -> Net.Place:
  Room.place_of(Play.player_of(client))

def check_places(+state: Play.Client) -> IO(Unit):
  do IO<Unit>:
    Unit <- check(place_near(placed(state), 25.5, 9.05, 25.5),
      "the spawn is not the middle of world cell (25, 25) as a room hears it")
    Unit <- check(place_near(placed(Room.recalled(None{}, state)), 25.5, 9.05, 25.5),
      "no correction moved the player")
    check(place_near(placed(Room.recalled(Some{Net.Stand{30.25, 12.0, F32.neg(4.5)}}, state)),
        30.25, 12.0, F32.neg(4.5)),
      "a correction did not put the player where the room said")


def verify_places() -> IO(Unit):
  do IO<Unit>:
    state : Play.Client <- started()
    check_places(state)

# --- a room's mobs ---------------------------------------------------------------
#
# A player at the world's (10.5, 10, 8.5) looking along -z, level. The mob under the
# crosshair is the nearest the ray meets within a hit's reach; a villager and an item are
# not mobs, and a mob past the reach or off the ray is not under it.
def looking() -> Net.Place:
  Net.Place{10.5, 10.0, 8.5, 0.0, 0.0}

def quarry_is(+quarry: Entities.Aimed, want: U32) -> Bool:
  Bool.and(Entities.aim_found(quarry), U32.is_eq(Entities.aim_id(quarry), want))

def verify_quarry() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(quarry_is(Room.quarry([Net.Thing{7, 2, 1, 10.5, 10.0, 5.5, 0.0}, Net.Thing{8, 2, 1, 10.5, 10.0, 6.5, 0.0}], looking()), 8),
      "the nearer of two mobs on the ray is not the one under the crosshair")
    Unit <- check(Bool.not(Entities.aim_found(Room.quarry([Net.Thing{7, 2, 1, 10.5, 10.0, 3.0, 0.0}], looking()))),
      "a mob past a hit's reach is under the crosshair")
    Unit <- check(Bool.not(Entities.aim_found(Room.quarry([Net.Thing{7, 2, 1, 13.5, 10.0, 6.5, 0.0}], looking()))),
      "a mob beside the ray is under the crosshair")
    Unit <- check(Bool.not(Entities.aim_found(Room.quarry([Net.Thing{0, 11, 1, 10.5, 10.0, 6.5, 0.0}, Net.Thing{3, 1001, 1, 10.5, 11.5, 7.5, 0.0}], looking()))),
      "a villager or an item on the ground is hit like a mob")
    check(Bool.not(Entities.aim_found(Room.quarry([Net.Thing{7, 6, 1, 10.5, 10.0, 6.5, 0.0}], looking()))),
      "a ray at eye height meets a chicken, which is not that tall")

def is_drop(ask: Maybe<&2, U32>, want: U32) -> Bool:
  match ask:
    case Some{id}:
      U32.is_eq(id, want)
    case None{}:
      False{}

def full_bag.go(remaining: Nat, acc: List<&2, Inventory.Slot>) -> List<&2, Inventory.Slot>:
  match remaining:
    case 0n:
      acc
    case 1n+rest:
      full_bag.go(rest, Inventory.make_slot(2, Inventory.max_stack(), 0) <> acc)

# A bag whose every slot is a full stack of dirt.
def full_bag() -> Bag.Bag:
  Bag.Bag{full_bag.go(Inventory.slot_count(), []), 0n, Bag.shut(), Bag.stores()}

# An item on the ground is asked for when it is within the rules' reach and the bag has
# room for all of it.
def verify_wanted() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(is_drop(Room.wanted([Net.Thing{3, 1001, 2, 10.5, 10.0, 7.6, 0.0}], looking(), Bag.start()), 3),
      "an item beside the player is not asked for")
    Unit <- check(Maybe.is_none(&2, U32, Room.wanted([Net.Thing{3, 1001, 2, 10.5, 10.0, 5.5, 0.0}], looking(), Bag.start())),
      "an item three cells off is asked for")
    Unit <- check(Maybe.is_none(&2, U32, Room.wanted([Net.Thing{7, 1, 1, 10.5, 10.0, 8.0, 0.0}], looking(), Bag.start())),
      "a pig is picked up")
    check(Maybe.is_none(&2, U32, Room.wanted([Net.Thing{3, 1001, 2, 10.5, 10.0, 7.6, 0.0}], looking(), full_bag())),
      "an item is asked for with no room for it")

def health_in(player: Player.State) -> F32:
  Player.State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall, poison} = player
  health

def health_of(state: Play.Client) -> F32:
  health_in(Play.player_of(state))

def stone_of(state: Play.Client) -> U32:
  held_total(Bag.slots_of(Play.bag_of(state)), 0)

# What a mob does to the player is the rules' damage, a player it kills starts again whole
# at the spawn, and an item the room hands over is in the bag. With a mob under the
# crosshair the dig key leaves the block behind it alone.
def check_harm(+state: Play.Client) -> IO(Unit):
  do IO<Unit>:
    Unit <- check(F32.is_eq(health_of(Room.harmed(3.0, state)), 17.0), "three points of harm did not take three points of health")
    Unit <- check(F32.is_eq(health_of(Room.harmed(0.0, state)), 20.0), "no harm changed the health")
    Unit <- check(F32.is_eq(health_of(Room.harmed(40.0, state)), 20.0), "a player that was killed did not start again whole")
    Unit <- check(place_near(placed(Room.harmed(40.0, Room.recalled(Some{Net.Stand{30.25, 12.0, 4.5}}, state))), 25.5, 9.05, 25.5),
      "a player that was killed did not start again at the spawn")
    check(U32.is_eq(stone_of(Room.gained([Net.Gain{1, 2}], state)), U32.add(stone_of(state), 2)),
      "two stone the room handed over are not in the bag")

def guarded_edits(maybe: Maybe<&1, Play.Client>) -> IO(Unit):
  match maybe:
    case Some{state}:
      check(List.is_empty(&2, WorldState.Edit, Play.edits_of(state)), "the dig key dug a block with a mob under the crosshair")
    case None{}:
      IO.die(Unit, 1, "room: the guarded tick closed the client")

def verify_harm() -> IO(Unit):
  do IO<Unit>:
    state : Play.Client <- started()
    Unit <- check_harm(state)
    Unit <- empty_world()
    fresh : Play.Client <- started()
    looked : Play.Client <- looked_down(fresh)
    dug : Maybe<&1, Play.Client> <- Play.tick.room([Key{Frame.dig_code(), True{}}], looked, True{}, False{})
    guarded_edits(dug)


def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- empty_world()
    Unit <- verify_places()
    Unit <- verify_quarry()
    Unit <- verify_wanted()
    Unit <- verify_harm()
    IO.print("room: places, corrections, the mob under the crosshair, pickups and harm passed")

#|room: places, corrections, the mob under the crosshair, pickups and harm passed
