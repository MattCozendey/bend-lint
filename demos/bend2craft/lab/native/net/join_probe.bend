import Base
import ../../../world/world_state.bend as WorldState
import ../../../native/frame.bend as Frame
import ../../../native/net.bend as Net
import ../../../native/size.bend as Size
import ../../../native/bag.bend as Bag
import ../../../world/inventory.bend as Inventory
import ../../../world/world.bend as World
import ../../../native/screen.bend as Screen
import ../../../native/stores.bend as Stores
import ../../../native/hour.bend as Hour
import ../../../native/play.bend as Play
import ../../../native/room.bend as Room

# The native client in a room, without its window.
#
# `tests/native-join.test.mjs` opens a room with a browser player in it, starts this, and
# plays the other side. This is the client's own session: `Room.room_client`,
# `Room.join.at` and `Room.session.tick`, which is the tick the window's loop runs. What
# it leaves out is the window and the frame.
#
# It joins the room named by `B2C_JOIN`, waits to hear the block the browser dug before it
# arrived and where the browser's player stands, picks up the two stone the browser threw
# down where it stands, takes five dirt out of the chest the browser stocked beside it, places a block of its own, and waits to
# hear the block the browser places once it has seen that one. Its own pose goes to the room
# on its first tick, which the test reads on the browser's side. Each wait is bounded: a
# room that never says it fails the probe.

def block_at(client: Play.Client, +x: Nat, +y: Nat, +z: Nat) -> U32:
  WorldState.block(Play.edits_of(client), Frame.seed(), x, y, z)

def looked(session: Room.Session, +x: Nat, +y: Nat, +z: Nat, +want: U32) -> Room.Session & Bool:
  Room.Session{+client, link} = session
  (Room.Session{client, link}, U32.is_eq(block_at(client, x, y, z), want))

def after(next: Maybe<Room.Session>, rest: Room.Session -> IO(Room.Session)) -> IO(Room.Session):
  match next:
    case Some{session}:
      rest(session)
    case None{}:
      IO.die(Room.Session, 1, "join_probe: the client quit")

def waited(seen: Room.Session & Bool, rest: Room.Session -> IO(Room.Session)) -> IO(Room.Session):
  (session, ok) = seen
  match ok:
    case True{}:
      IO.pure(Room.Session, session)
    case False{}:
      do IO<Room.Session>:
        slept : Unit <- IO.sleep(20)
        IO.bind(Maybe<Room.Session>, Room.Session, Room.session.tick([], session), next => after(next, rest))

# Ticks the session until the cell holds `want`, twenty milliseconds apart.
def until(fuel: Nat, session: Room.Session, +x: Nat, +y: Nat, +z: Nat, +want: U32, +what: String) -> IO(Room.Session):
  match fuel:
    case 0n:
      IO.die(Room.Session, 1, "join_probe: never heard " ++ what)
    case 1n+f:
      waited(looked(session, x, y, z, want), s => until(f, s, x, y, z, want, what))

# Whether the room has said player `want` stands at `wx` along x and is called "Browser".
def other_at(others: List<&2, Net.Other>, +want: U32, +wx: F32) -> Bool:
  match others:
    case Nil{}:
      False{}
    case Net.Other{id, name, Net.Place{x, y, z, yaw, pitch}, seen} <> rest:
      Bool.or(Bool.and(Bool.and(seen, String.eq(name, "Browser")),
          Bool.and(U32.is_eq(id, want), F32.is_lt(F32.abs(F32.sub(x, wx)), 0.001))),
        other_at(rest, want, wx))

def seen.among(told: Room.Told, +want: U32, +wx: F32) -> Bool:
  Room.Told{others, hour, sights} = told
  other_at(others, want, wx)

def seen.at(heard: Room.Session & Room.Told, +want: U32, +wx: F32) -> Room.Session & Bool:
  (session, told) = heard
  (session, seen.among(told, want, wx))

def seen(session: Room.Session, +want: U32, +wx: F32) -> Room.Session & Bool:
  seen.at(Room.session.told(session), want, wx)

# Ticks the session until the room has said player `want` stands at `wx` along x.
def until_seen(fuel: Nat, session: Room.Session, +want: U32, +wx: F32) -> IO(Room.Session):
  match fuel:
    case 0n:
      IO.die(Room.Session, 1, "join_probe: never heard where the browser's player is")
    case 1n+f:
      waited(seen(session, want, wx), s => until_seen(f, s, want, wx))

def timed.among(told: Room.Told) -> Bool:
  Room.Told{others, hour, sights} = told
  Hour.hour.running(hour)

def timed.at(heard: Room.Session & Room.Told) -> Room.Session & Bool:
  (session, told) = heard
  (session, timed.among(told))

# Ticks the session until the room has said its hour and a tick has timed it.
def until_timed(fuel: Nat, session: Room.Session) -> IO(Room.Session):
  match fuel:
    case 0n:
      IO.die(Room.Session, 1, "join_probe: never heard the room's hour")
    case 1n+f:
      waited(timed.at(Room.session.told(session)), s => until_timed(f, s))

def sighted.at(heard: Room.Session & Room.Told) -> Room.Session & Bool:
  (session, told) = heard
  (session, Bool.not(List.is_empty(&2, Net.Thing, Room.told_things(told))))

# Ticks the session until the room has told a whole list of what it simulates with
# something in it.
def until_sighted(fuel: Nat, session: Room.Session) -> IO(Room.Session):
  match fuel:
    case 0n:
      IO.die(Room.Session, 1, "join_probe: never heard what the room simulates")
    case 1n+f:
      waited(sighted.at(Room.session.told(session)), s => until_sighted(f, s))

def carried.go(slots: List<&2, Inventory.Slot>, +total: U32) -> U32:
  match slots:
    case Nil{}:
      total
    case slot <> rest:
      carried.go(rest, U32.add(total, Inventory.slot_count_value(slot)))

# How many items a bag holds, of every kind.
def carried(bag: Bag.Bag) -> U32:
  carried.go(Bag.slots_of(bag), 0)

def gained.at(session: Room.Session, +more: U32) -> Room.Session & Bool:
  Room.Session{+client, link} = session
  (Room.Session{client, link}, U32.is_ge(carried(Play.bag_of(client)), U32.add(carried(Bag.start()), more)))

# Ticks the session until the bag holds `more` items than it started with: the session saw
# an item on the ground beside it, asked the room for it, and was handed it.
def until_gained(fuel: Nat, session: Room.Session, +more: U32) -> IO(Room.Session):
  match fuel:
    case 0n:
      IO.die(Room.Session, 1, "join_probe: never picked up the item beside it")
    case 1n+f:
      waited(gained.at(session, more), s => until_gained(f, s, more))

# The session with one cell set by the player, as a dig or a placing leaves it.
def placed(session: Room.Session, x: Nat, y: Nat, z: Nat, block: U32) -> Room.Session:
  Room.Session{client, link} = session
  Play.Client{avatar, Play.Ground{edits, region, world, home, world_ms}, setup, bag, clock, dig} = client
  Room.Session{Play.Client{avatar, Play.Ground{WorldState.set(edits, x, y, z, block), region, world, home, world_ms},
    setup, bag, clock, dig}, link}

def target(result: Result<&1, &1, U32 & String, String>) -> IO(String):
  match result:
    case Done{text}:
      IO.pure(String, text)
    case Fail{error}:
      IO.die(String, 1, "join_probe: B2C_JOIN is not set")

# The cell of the chest the browser puts beside where the client stands.
def chest_y() -> Nat:
  World.column_height(Frame.seed(), 58n, 41n)

def chest_first(bag: Bag.Bag) -> Inventory.Slot:
  Bag.held.of(Inventory.lookup(Stores.chest_shown(Stores.aimed(Bag.store_of(bag), 58n, chest_y(), 41n)), 0n))

def stocked.at(session: Room.Session, +want: U32) -> Room.Session & Bool:
  Room.Session{+client, link} = session
  (Room.Session{client, link}, U32.is_eq(Inventory.slot_count_value(chest_first(Play.bag_of(client))), want))

# Ticks the session until the room has said the chest's first slot holds `want` items.
def until_stocked(fuel: Nat, session: Room.Session, +want: U32) -> IO(Room.Session):
  match fuel:
    case 0n:
      IO.die(Room.Session, 1, "join_probe: the room's chest never held what was expected")
    case 1n+f:
      waited(stocked.at(session, want), s => until_stocked(f, s, want))

# The bag with the chest's screen open and the arrow on its first slot.
def at_chest.bag(bag: Bag.Bag, +size: Size.Size) -> Bag.Bag:
  Screen.aimed(Screen.opened_at(bag, Screen.chest(), 58n, chest_y(), 41n, Size.width_of(size)), 46,
    Size.width_of(size))

# The session with the chest's screen open and the arrow on its first slot.
def at_chest(session: Room.Session) -> Room.Session:
  Room.Session{+client, link} = session
  Room.Session{Play.with_bag(client, at_chest.bag(Play.bag_of(client), Play.size_of(client))), link}

def desk_held(bag: Bag.Bag) -> Inventory.Slot:
  Bag.Bag{slots, selected, Bag.Desk{mode, x, y, held, grid}, store} = bag
  held

def carrying.at(session: Room.Session, +want: U32) -> Room.Session & Bool:
  Room.Session{+client, link} = session
  (Room.Session{client, link}, U32.is_eq(Inventory.slot_count_value(desk_held(Play.bag_of(client))), want))

# Ticks the session until its arrow carries `want` items: the room answered the click.
def until_carrying(fuel: Nat, session: Room.Session, +want: U32) -> IO(Room.Session):
  match fuel:
    case 0n:
      IO.die(Room.Session, 1, "join_probe: the room never handed over what was taken from its chest")
    case 1n+f:
      waited(carrying.at(session, want), s => until_carrying(f, s, want))

def clicked(next: Maybe<Room.Session>) -> IO(Room.Session):
  match next:
    case Some{session}:
      IO.pure(Room.Session, session)
    case None{}:
      IO.die(Room.Session, 1, "join_probe: the click closed the client")

# Open ground east of the spawn, which is inside a house: an item thrown down at the spawn
# comes to rest on the roof. The client stands here from before it joins, so the first pose
# the room hears is this one.
def outside(client: Play.Client) -> Play.Client:
  Room.recalled(Some{Net.Stand{56.5, F32.from_nat(World.column_height(Frame.seed(), 56n, 41n)), 41.5}}, client)

def main() -> IO(Unit):
  do IO<Unit>:
    named : Result<&1, &1, U32 & String, String> <- IO.get_env("B2C_JOIN")
    text : String <- target(named)
    client : Play.Client <- Room.room_client(Size.size_32())
    joined : Room.Session <- Room.join.at(Net.address(text), outside(client))
    heard : Room.Session <- until(250n, joined, 25n, 9n, 25n, 0, "the block the browser dug before the join")
    one : Unit <- IO.print("join_probe: heard the room's log")
    met : Room.Session <- until_seen(250n, heard, 1, 30.5)
    two : Unit <- IO.print("join_probe: saw the browser's player")
    timed : Room.Session <- until_timed(250n, met)
    three : Unit <- IO.print("join_probe: heard the room's hour")
    sighted : Room.Session <- until_sighted(500n, timed)
    four : Unit <- IO.print("join_probe: saw what the room simulates")
    richer : Room.Session <- until_gained(500n, sighted, 2)
    five : Unit <- IO.print("join_probe: picked up the item beside it")
    stocked : Room.Session <- until_stocked(500n, richer, 5)
    press : Maybe<Room.Session> <- Room.session.tick([Mouse{0, 0, 0, True{}}], at_chest(stocked))
    pressed : Room.Session <- clicked(press)
    handed : Room.Session <- until_carrying(500n, pressed, 5)
    emptied : Room.Session <- until_stocked(500n, handed, 0)
    six : Unit <- IO.print("join_probe: took the dirt out of the room's chest")
    mine : Room.Session <- until(250n, placed(emptied, 30n, 9n, 25n, 1), 31n, 9n, 25n, 1, "the block the browser placed after ours")
    IO.print("join_probe=pass")
