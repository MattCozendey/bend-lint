import Base
import ../world/world_state.bend as WorldState
import ./net.bend as Net

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "net: " ++ message)

def edit(x: Nat, y: Nat, z: Nat, block: U32) -> WorldState.Edit:
  WorldState.make_edit(x, y, z, block)

def same(a: WorldState.Edit, b: WorldState.Edit) -> Bool:
  WorldState.Edit{ax, ay, az, ablock} = a
  WorldState.Edit{bx, by, bz, bblock} = b
  Bool.and(Bool.and(Nat.is_eq(ax, bx), Nat.is_eq(ay, by)),
    Bool.and(Nat.is_eq(az, bz), U32.is_eq(ablock, bblock)))

def same_list(a: List<&2, WorldState.Edit>, b: List<&2, WorldState.Edit>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case ah <> at bh <> bt:
      Bool.and(same(ah, bh), same_list(at, bt))
    case _ _:
      False{}

def same_lines(a: List<&2, String>, b: List<&2, String>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case ah <> at bh <> bt:
      Bool.and(String.eq(ah, bh), same_lines(at, bt))
    case _ _:
      False{}

# What the client writes is what `server/native-bridge.mjs` reads, character for character:
# `tests/native-bridge.test.mjs` sends the same two lines.
def the_client_writes_its_lines() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(String.eq(Net.hello("Ana"), "H 1 Ana\n"), "the hello is not `H 1 Ana`")
    Unit <- check(String.eq(Net.edit_line(edit(94371839n, 9n, 25n, 0)), "E 94371839 9 25 0\n"),
      "an edit west of the origin is not written in stored coordinates")
    check(String.eq(Net.edit_lines([edit(1n, 2n, 3n, 4), edit(5n, 6n, 7n, 8)], ""), "E 5 6 7 8\nE 1 2 3 4\n"),
      "two edits are not two lines")

def fed_is(fed: Net.Fed, lines: List<&2, String>, rest: String) -> Bool:
  Net.Fed{got, left} = fed
  Bool.and(same_lines(got, lines), String.eq(left, rest))

# TCP hands over bytes, not lines: a chunk can end in the middle of one, hold several, or
# hold none. The unfinished end is kept and goes in front of the next chunk.
def chunks_become_lines() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(fed_is(Net.feed("", "B 1 2 3 4\nB 5 6"), ["B 1 2 3 4"], "B 5 6"),
      "a chunk that ends mid-line did not keep its end")
    Unit <- check(fed_is(Net.feed("B 5 6", " 7 8\n"), ["B 5 6 7 8"], ""),
      "the kept end did not finish with the next chunk")
    Unit <- check(fed_is(Net.feed("", "W 3 1337\nB 1 2 3 4\nB 5 6 7 8\n"), ["W 3 1337", "B 1 2 3 4", "B 5 6 7 8"], ""),
      "three lines in one chunk are not three lines in order")
    check(fed_is(Net.feed("B 1", ""), [], "B 1"), "an empty chunk changed the buffer")

def is_block(line: Net.Line, want: WorldState.Edit) -> Bool:
  match line:
    case Net.Block{got}:
      same(got, want)
    case _:
      False{}

def is_welcome(line: Net.Line, want_id: U32, want_seed: Nat) -> Bool:
  match line:
    case Net.Welcome{id, seed}:
      Bool.and(U32.is_eq(id, want_id), Nat.is_eq(seed, want_seed))
    case _:
      False{}

def is_refused(line: Net.Line, want: String) -> Bool:
  match line:
    case Net.Refused{reason}:
      String.eq(reason, want)
    case _:
      False{}

def is_noise(line: Net.Line) -> Bool:
  match line:
    case Net.Noise{}:
      True{}
    case _:
      False{}

# A line is what its tag and its fields say, and anything else is dropped: too few fields, a
# field that is not a number, a tag the client does not know.
def lines_are_read() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(is_block(Net.parse("B 94371839 9 25 5"), edit(94371839n, 9n, 25n, 5)), "a block line is not its edit")
    Unit <- check(is_welcome(Net.parse("W 3 1337"), 3, 1337n), "a welcome is not its id and seed")
    Unit <- check(is_refused(Net.parse("X the server is full"), "the server is full"), "a refusal lost its reason")
    Unit <- check(is_noise(Net.parse("B 1 2 3")), "a block line with three fields was read")
    Unit <- check(is_noise(Net.parse("B 1 2 x 4")), "a block line with a word for a number was read")
    Unit <- check(is_noise(Net.parse("Q 1 2 3 4")), "an unknown tag was read")
    check(is_noise(Net.parse("")), "an empty line was read")

def inbox_is(inbox: Net.Inbox, edits: List<&2, WorldState.Edit>, has_seed: Bool, is_refused: Bool) -> Bool:
  Net.Inbox{got, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers} = inbox
  Bool.and(same_list(got, edits),
    Bool.and(Bool.not(Bool.xor(Maybe.is_some(&2, Nat, seed), has_seed)),
      Bool.not(Bool.xor(Maybe.is_some(&2, String, refused), is_refused))))

# A frame's lines come to the cells the room set, in the order it set them, the world's
# seed if it said, and its refusal if it refused.
def a_frame_of_lines_is_an_inbox() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(inbox_is(Net.inbox(["W 3 1337", "B 1 2 3 4", "noise", "B 1 2 3 9"], [], Net.Sights{[], []}),
        [edit(1n, 2n, 3n, 4), edit(1n, 2n, 3n, 9)], True{}, False{}),
      "a welcome and two blocks are not a seed and two edits in order")
    Unit <- check(inbox_is(Net.inbox([], [], Net.Sights{[], []}), [], False{}, False{}), "no lines are not an empty inbox")
    check(inbox_is(Net.inbox(["X go away"], [], Net.Sights{[], []}), [], False{}, True{}), "a refusal is not in the inbox")

def near(+a: F32, +b: F32) -> Bool:
  F32.is_lt(F32.abs(F32.sub(a, b)), 0.0005)

def place_is(place: Net.Place, wx: F32, wy: F32, wz: F32, wyaw: F32, wpitch: F32) -> Bool:
  Net.Place{x, y, z, yaw, pitch} = place
  Bool.and(Bool.and(near(x, wx), near(y, wy)),
    Bool.and(near(z, wz), Bool.and(near(yaw, wyaw), near(pitch, wpitch))))

def is_posed(line: Net.Line, want: U32, wx: F32, wy: F32, wz: F32, wyaw: F32, wpitch: F32) -> Bool:
  match line:
    case Net.Posed{id, place}:
      Bool.and(U32.is_eq(id, want), place_is(place, wx, wy, wz, wyaw, wpitch))
    case _:
      False{}

def is_parted(line: Net.Line, want: U32) -> Bool:
  match line:
    case Net.Parted{id}:
      U32.is_eq(id, want)
    case _:
      False{}

def is_recalled(line: Net.Line, wx: F32, wy: F32, wz: F32) -> Bool:
  match line:
    case Net.Recalled{Net.Stand{x, y, z}}:
      Bool.and(near(x, wx), Bool.and(near(y, wy), near(z, wz)))
    case _:
      False{}

# Where a player is goes over the wire as whole thousandths, signed: world coordinates, feet
# first, as the browser's wire has them. `tests/native-bridge.test.mjs` sends and reads the
# same lines.
def poses_are_written_and_read() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(String.eq(Net.place_line(Net.Place{25.5, 9.05, F32.neg(3.25), F32.neg(0.5), 0.0}),
        "P 25500 9050 -3250 -500 0\n"), "a pose is not written in signed thousandths")
    Unit <- check(String.eq(Net.place_line(Net.Place{F32.neg(0.0001), 0.0, 0.0, 0.0, 0.0}), "P 0 0 0 0 0\n"),
      "a pose a hair under zero is written as minus nothing")
    Unit <- check(is_posed(Net.parse("P 7 30500 10000 -26500 1500 -250"), 7, 30.5, 10.0, F32.neg(26.5), 1.5, F32.neg(0.25)),
      "another player's pose is not its id and its place")
    Unit <- check(is_parted(Net.parse("L 7"), 7), "a leaving is not its id")
    Unit <- check(is_recalled(Net.parse("C 25500 9000 -1500"), 25.5, 9.0, F32.neg(1.5)), "a correction is not where to stand")
    Unit <- check(is_noise(Net.parse("P 7 1 2 3 4")), "a pose with a field missing was read")
    Unit <- check(is_noise(Net.parse("P 7 1 2 - 4 5")), "a pose with a bare sign for a number was read")
    check(is_noise(Net.parse("C 1 2")), "a correction with two fields was read")

def other_at(others: List<&2, Net.Other>, +want: U32, +wx: F32) -> Bool:
  match others:
    case Nil{}:
      False{}
    case Net.Other{id, name, Net.Place{x, y, z, yaw, pitch}, seen} <> rest:
      Bool.or(Bool.and(seen, Bool.and(U32.is_eq(id, want), near(x, wx))), other_at(rest, want, wx))

def others_of(inbox: Net.Inbox) -> List<&2, Net.Other>:
  Net.Inbox{got, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers} = inbox
  others

def back_of(inbox: Net.Inbox) -> Maybe<&2, Net.Stand>:
  Net.Inbox{got, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers} = inbox
  back

# The other players are a list a frame's lines change: a pose puts a player in it or moves
# the one already there, a leaving takes one out, and a frame that says nothing about them
# leaves them where they were. A correction is where the room says this player stands.
def the_inbox_keeps_the_other_players() -> IO(Unit):
  do IO<Unit>:
    +one : List<&2, Net.Other> = others_of(Net.inbox(["P 1 1000 0 0 0 0", "P 2 2000 0 0 0 0"], [], Net.Sights{[], []}))
    Unit <- check(Bool.and(other_at(one, 1, 1.0), other_at(one, 2, 2.0)), "two poses are not two players")
    +two : List<&2, Net.Other> = others_of(Net.inbox(["P 1 5000 0 0 0 0"], one, Net.Sights{[], []}))
    Unit <- check(Bool.and(other_at(two, 1, 5.0), other_at(two, 2, 2.0)), "a second pose did not move the player")
    Unit <- check(Nat.is_eq(List.length(&2, Net.Other, two), 2n), "a player that moved is in the list twice")
    Unit <- check(Nat.is_eq(List.length(&2, Net.Other, others_of(Net.inbox(["B 1 2 3 4"], two, Net.Sights{[], []}))), 2n),
      "a frame with no poses dropped the players")
    +three : List<&2, Net.Other> = others_of(Net.inbox(["L 1"], two, Net.Sights{[], []}))
    Unit <- check(Bool.and(Bool.not(other_at(three, 1, 5.0)), other_at(three, 2, 2.0)), "a player that left is still there")
    Unit <- check(Maybe.is_none(&2, Net.Stand, back_of(Net.inbox(["P 1 1000 0 0 0 0"], [], Net.Sights{[], []}))), "a pose is a correction")
    check(Maybe.is_some(&2, Net.Stand, back_of(Net.inbox(["C 1000 2000 3000"], [], Net.Sights{[], []}))), "a correction is not in the inbox")

# What the room has not heard: an edit to a new cell, which `WorldState.set` puts at the
# head; an edit to a cell already in the log, which it replaces in place; and nothing when
# nothing changed. The log the room knows and the client's are the same log otherwise.
def the_client_sends_what_changed() -> IO(Unit):
  do IO<Unit>:
    +known : List<&2, WorldState.Edit> = WorldState.set(WorldState.set(WorldState.empty(), 1n, 2n, 3n, 4), 5n, 6n, 7n, 8)
    Unit <- check(same_list(Net.unheard(known, known), []), "an unchanged log has something to send")
    Unit <- check(same_list(Net.unheard(WorldState.set(known, 9n, 9n, 9n, 1), known), [edit(9n, 9n, 9n, 1)]),
      "a new cell is not what is sent")
    Unit <- check(same_list(Net.unheard(WorldState.set(known, 1n, 2n, 3n, 0), known), [edit(1n, 2n, 3n, 0)]),
      "a cell replaced in the log is not what is sent")
    Unit <- check(same_list(Net.unheard(WorldState.set(WorldState.set(known, 9n, 9n, 9n, 1), 1n, 2n, 3n, 0), known),
        [edit(1n, 2n, 3n, 0), edit(9n, 9n, 9n, 1)]),
      "a new cell and a replaced one are not both sent")
    check(same_list(Net.unheard(known, WorldState.empty()), [edit(1n, 2n, 3n, 4), edit(5n, 6n, 7n, 8)]),
      "against a room that has heard nothing, the whole log is not sent oldest first")

def address_is(maybe: Maybe<&2, Net.Address>, want_host: String, want_port: U32) -> Bool:
  match maybe:
    case Some{Net.Address{host, port}}:
      Bool.and(String.eq(host, want_host), U32.is_eq(port, want_port))
    case None{}:
      False{}

def addresses_are_read() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(address_is(Net.address("127.0.0.1:8081"), "127.0.0.1", 8081), "host:port is not an address")
    Unit <- check(Maybe.is_none(&2, Net.Address, Net.address("localhost")), "a host with no port is an address")
    check(Maybe.is_none(&2, Net.Address, Net.address("localhost:http")), "a port that is not a number is an address")

def is_timed(line: Net.Line, want_turn: U32, want_length: U32) -> Bool:
  match line:
    case Net.Timed{Net.Day{turn, length}}:
      Bool.and(U32.is_eq(turn, want_turn), U32.is_eq(length, want_length))
    case _:
      False{}

def hour_of(inbox: Net.Inbox) -> Maybe<&2, Net.Day>:
  Net.Inbox{got, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers} = inbox
  hour

# The room's hour is how far round its day it is and how long that day lasts. A day of no
# length is not one.
def the_hour_is_read() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(is_timed(Net.parse("T 1571 78540"), 1571, 78540), "the hour is not its turn and its day")
    Unit <- check(is_noise(Net.parse("T 1571 0")), "a day of no length was read")
    Unit <- check(is_noise(Net.parse("T 1571")), "an hour with no day was read")
    Unit <- check(Maybe.is_some(&2, Net.Day, hour_of(Net.inbox(["B 1 2 3 4", "T 0 78540"], [], Net.Sights{[], []}))), "the hour is not in the inbox")
    check(Maybe.is_none(&2, Net.Day, hour_of(Net.inbox(["B 1 2 3 4"], [], Net.Sights{[], []}))), "a frame with no hour has one")

def thing_is(thing: Net.Thing, want_id: U32, want: U32, want_count: U32, wx: F32, wyaw: F32) -> Bool:
  Net.Thing{id, kind, count, x, y, z, yaw} = thing
  Bool.and(Bool.and(U32.is_eq(id, want_id), U32.is_eq(count, want_count)),
    Bool.and(U32.is_eq(kind, want), Bool.and(near(x, wx), near(yaw, wyaw))))

def is_sighted(line: Net.Line, want_id: U32, want: U32, want_count: U32, wx: F32, wyaw: F32) -> Bool:
  match line:
    case Net.Sighted{thing}:
      thing_is(thing, want_id, want, want_count, wx, wyaw)
    case _:
      False{}

def is_tallied(line: Net.Line) -> Bool:
  match line:
    case Net.Tallied{}:
      True{}
    case _:
      False{}

def sights_of(inbox: Net.Inbox) -> Net.Sights:
  Net.Inbox{got, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers} = inbox
  sights

def counts(sights: Net.Sights, shown: Nat, pending: Nat) -> Bool:
  Net.Sights{now, next} = sights
  Bool.and(Nat.is_eq(List.length(&2, Net.Thing, now), shown), Nat.is_eq(List.length(&2, Net.Thing, next), pending))

# A mob, an item on the ground and a villager are each a kind and a place: a mob's kind is
# its own, a villager's is ten and its profession, an item's a thousand and its id.
def what_the_room_simulates_is_read() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(is_sighted(Net.parse("M 7 5 12500 9000 -3000 1571"), 7, 5, 1, 12.5, 1.571), "a mob is not its name, its kind, its place and its yaw")
    Unit <- check(is_sighted(Net.parse("D 3 4 2 12500 9000 -3000"), 3, 1004, 2, 12.5, 0.0), "an item on the ground is not its name, a thousand and its id, and how many")
    Unit <- check(is_sighted(Net.parse("V 2 12500 9000 -3000"), 0, 12, 1, 12.5, 0.0), "a villager is not ten and its profession")
    Unit <- check(is_tallied(Net.parse("N")), "the end of the list is not read")
    Unit <- check(is_noise(Net.parse("M 5 12500 9000 -3000 1571")), "a mob with no name was read")
    check(is_noise(Net.parse("D 4 12500 9000 -3000")), "an item with no name was read")

# The list the client shows changes only when the room has told all of the next one: a list
# cut in two by the read is not drawn half, and an empty list empties it.
def the_list_is_swapped_whole() -> IO(Unit):
  do IO<Unit>:
    +half : Net.Sights = sights_of(Net.inbox(["M 1 1 0 0 0 0", "D 2 4 1 0 0 0"], [], Net.Sights{[], []}))
    Unit <- check(counts(half, 0n, 2n), "a list that has not ended is already shown")
    +whole : Net.Sights = sights_of(Net.inbox(["V 1 0 0 0", "N", "M 3 2 0 0 0 0"], [], half))
    Unit <- check(counts(whole, 3n, 1n), "the list did not become the one shown at its end")
    Unit <- check(counts(sights_of(Net.inbox(["B 1 2 3 4"], [], whole)), 3n, 1n), "a frame with nothing in it changed the list")
    check(counts(sights_of(Net.inbox(["N", "N"], [], whole)), 0n, 0n), "an empty list did not empty the one shown")

def hurt_of(inbox: Net.Inbox) -> F32:
  Net.Inbox{got, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers} = inbox
  hurt

def gains_of(inbox: Net.Inbox) -> List<&2, Net.Gain>:
  Net.Inbox{got, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers} = inbox
  gains

def gain_is(gains: List<&2, Net.Gain>, want_item: U32, want_amount: U32) -> Bool:
  match gains:
    case Net.Gain{item, amount} <> Nil{}:
      Bool.and(U32.is_eq(item, want_item), U32.is_eq(amount, want_amount))
    case _:
      False{}

# A hit names the mob and the damage in thousandths, and a pickup the item on the ground.
# What comes back is how much the player was hurt, summed over a frame, and each item the
# room handed over.
def hits_and_pickups() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(String.eq(Net.strike_line(7, 4), "A 7 4000\n"), "a hit is not the mob and the damage in thousandths")
    Unit <- check(String.eq(Net.pickup_line(3), "K 3\n"), "a pickup is not the item's name")
    Unit <- check(near(hurt_of(Net.inbox(["U 1500", "B 1 2 3 4", "U 2000"], [], Net.Sights{[], []})), 3.5), "two hurts in a frame are not their sum")
    Unit <- check(near(hurt_of(Net.inbox(["B 1 2 3 4"], [], Net.Sights{[], []})), 0.0), "a frame with no hurt hurts")
    Unit <- check(gain_is(gains_of(Net.inbox(["G 13 2"], [], Net.Sights{[], []})), 13, 2), "an item handed over is not in the inbox")
    check(is_noise(Net.parse("G 13")), "an item with no amount was read")

def is_named(line: Net.Line, want: U32, want_name: String) -> Bool:
  match line:
    case Net.Named{id, name}:
      Bool.and(U32.is_eq(id, want), String.eq(name, want_name))
    case _:
      False{}

def called(others: List<&2, Net.Other>, +want: U32, +want_name: String, +want_seen: Bool) -> Bool:
  match others:
    case Nil{}:
      False{}
    case Net.Other{id, name, place, seen} <> rest:
      Bool.or(Bool.and(U32.is_eq(id, want), Bool.and(String.eq(name, want_name), Bool.not(Bool.xor(seen, want_seen)))),
        called(rest, want, want_name, want_seen))

# A player has a name, which is the rest of its line. One who has only joined is a name
# the client knows and does not draw; where it stands comes with its first move, and
# neither a move nor a name takes the other away.
def players_have_names() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(is_named(Net.parse("J 3 Ana Lua"), 3, "Ana Lua"), "a name is not the rest of its line")
    Unit <- check(is_noise(Net.parse("J")), "a name with no player was read")
    +joined : List<&2, Net.Other> = others_of(Net.inbox(["J 3 Ana"], [], Net.Sights{[], []}))
    Unit <- check(called(joined, 3, "Ana", False{}), "a player who only joined is not a name with no place")
    Unit <- check(Bool.not(other_at(joined, 3, 0.0)), "a player who only joined stands somewhere")
    +moved : List<&2, Net.Other> = others_of(Net.inbox(["P 3 5000 0 0 0 0"], joined, Net.Sights{[], []}))
    Unit <- check(Bool.and(called(moved, 3, "Ana", True{}), other_at(moved, 3, 5.0)), "a move took the name away")
    +renamed : List<&2, Net.Other> = others_of(Net.inbox(["J 3 Bia"], moved, Net.Sights{[], []}))
    check(Bool.and(called(renamed, 3, "Bia", True{}), other_at(renamed, 3, 5.0)), "a name took the place away")

def same_numbers(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case ah <> at bh <> bt:
      Bool.and(U32.is_eq(ah, bh), same_numbers(at, bt))
    case _ _:
      False{}

def is_boxed(line: Net.Line, want_furnace: Bool, wx: Nat, want: List<&2, U32>) -> Bool:
  match line:
    case Net.Boxed{Net.Box{furnace, x, y, z, values}}:
      Bool.and(Bool.not(Bool.xor(furnace, want_furnace)), Bool.and(Nat.is_eq(x, wx), same_numbers(values, want)))
    case _:
      False{}

def is_answered(line: Net.Line, want_ok: Bool, want_item: U32, want_amount: U32) -> Bool:
  match line:
    case Net.Answered{Net.Answer{ok, item, amount, durability}}:
      Bool.and(Bool.not(Bool.xor(ok, want_ok)), Bool.and(U32.is_eq(item, want_item), U32.is_eq(amount, want_amount)))
    case _:
      False{}

def boxes_of(inbox: Net.Inbox) -> List<&2, Net.Box>:
  Net.Inbox{got, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers} = inbox
  boxes

# A room's chests and furnaces: what the client asks of one, what the room says one holds,
# and the room's answer.
def chests_and_furnaces() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(String.eq(Net.deposit_line(94371839n, 9n, 25n, 1, 10, 0), "CD 94371839 9 25 1 10 0\n"), "a deposit is not its cell, its item, how many and its wear")
    Unit <- check(String.eq(Net.withdraw_line(30n, 9n, 25n, 4n, 16), "CW 30 9 25 4 16\n"), "a withdrawal is not its cell, its slot and how many")
    Unit <- check(String.eq(Net.furnace_line(0n, 30n, 9n, 25n, 6), "FI 30 9 25 6\n"), "loading a furnace is not its cell and the item")
    Unit <- check(String.eq(Net.furnace_line(2n, 30n, 9n, 25n, 0), "FO 30 9 25\n"), "emptying a furnace is not its cell")
    Unit <- check(is_boxed(Net.parse("S 30 9 25 1 10 0 0 0 0"), False{}, 30n, [1, 10, 0, 0, 0, 0]), "a chest is not its cell and its slots")
    Unit <- check(is_boxed(Net.parse("S 30 9 25"), False{}, 30n, []), "a chest that is gone is not its cell alone")
    Unit <- check(is_boxed(Net.parse("O 30 9 25 6 5 14 2 40 1 3 7"), True{}, 30n, [6, 5, 14, 2, 40, 1, 3, 7]), "a furnace is not its cell and its eight numbers")
    Unit <- check(is_noise(Net.parse("S 30 9 25 1 x 0")), "a chest with a word for a number was read")
    Unit <- check(is_answered(Net.parse("R 1 6 5 0"), True{}, 6, 5), "an answer is not whether, what and how many")
    Unit <- check(is_answered(Net.parse("R 0 0 0 0"), False{}, 0, 0), "a refusal is not read as one")
    check(Nat.is_eq(List.length(&2, Net.Box, boxes_of(Net.inbox(["S 30 9 25", "B 1 2 3 4", "O 31 9 25"], [], Net.Sights{[], []}))), 2n), "two boxes in a frame are not two in the inbox")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- the_client_writes_its_lines()
    Unit <- chunks_become_lines()
    Unit <- lines_are_read()
    Unit <- a_frame_of_lines_is_an_inbox()
    Unit <- poses_are_written_and_read()
    Unit <- the_inbox_keeps_the_other_players()
    Unit <- players_have_names()
    Unit <- the_hour_is_read()
    Unit <- what_the_room_simulates_is_read()
    Unit <- the_list_is_swapped_whole()
    Unit <- hits_and_pickups()
    Unit <- chests_and_furnaces()
    Unit <- the_client_sends_what_changed()
    Unit <- addresses_are_read()
    IO.print("net: writing, chunks, lines, the inbox, poses, the other players, their names, the hour, what the room simulates, hits and pickups, chests and furnaces, what changed and addresses passed")
