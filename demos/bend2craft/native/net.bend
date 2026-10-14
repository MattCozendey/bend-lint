import Base
import ../world/world_state.bend as WorldState

# Net: what the native client says to a multiplayer room, and what it hears back.
#
# The room is the browser's room. Its authority is `world/multiplayer.bend` and its players
# speak JSON over a WebSocket; a native client cannot, cheaply: the pinned runtime's sockets
# carry text and it has no JSON, no SHA-1 and no HTTP. So the server has a second door,
# `server/native-bridge.mjs`, a plain TCP port that speaks the lines below and hands what
# they say to the same room. Nothing about the world is decided on either side of that
# door: an edit a native client sends is validated by the room exactly as a browser's is.
#
# ## The lines
#
# ASCII, one message a line, fields separated by one space, ended by a newline.
#
#   client to server    H <version> <name>                  join the room
#                       E <x> <y> <z> <block>               this cell is now this block
#                       P <x> <y> <z> <yaw> <pitch>         this is where I am
#                       A <mob> <damage>                    I hit that mob, this hard
#                       K <drop>                            I pick that item up
#                       CD <x> <y> <z> <item> <count> <wear>  put this in that chest
#                       CW <x> <y> <z> <slot> <amount>        take this many from that slot of it
#                       FI <x> <y> <z> <item>               put one of this in that furnace to smelt
#                       FF <x> <y> <z> <item>               put one of this in it to burn
#                       FO <x> <y> <z>                      take what it made
#   server to client    W <id> <seed>                       joined: the player's id and the world's seed
#                       B <x> <y> <z> <block>               this cell is this block, on the room's word
#                       P <id> <x> <y> <z> <yaw> <pitch>    this is where that player is
#                       J <id> <name>                       that player is in the room, by that name
#                       L <id>                              that player left
#                       C <x> <y> <z>                       that move was refused: stand here
#                       T <turn> <day>                      the hour: how far round the day, and a day's length
#                       M <id> <kind> <x> <y> <z> <yaw>     a mob of that kind stands there, facing that way
#                       D <id> <item> <amount> <x> <y> <z>  that many of that item lie there
#                       V <profession> <x> <y> <z>          a villager of that profession stands there
#                       N                                   and those are all of them
#                       U <amount>                          you were hurt by that much
#                       G <item> <amount>                   the item you asked for is yours
#                       S <x> <y> <z> <slots>               that chest holds this; none: it is gone
#                       O <x> <y> <z> <eight numbers>       that furnace is this; none: it is gone
#                       R <ok> <item> <amount> <wear>       the answer to a chest or furnace request
#                       X <reason>                          refused, and the connection ends
#
# A cell's coordinates are `WorldState`'s stored ones, which are what the room's edit log and
# the browser's wire use too. A `B` is every way the room tells a client about a cell: the
# world's log when it joins, another player's edit, the client's own edit coming back
# accepted, and the room's value for a cell whose edit it refused. So the client does one
# thing with all of them, which is to set the cell.
#
# A pose is the world's own coordinates, feet first, and radians — what a browser relays —
# as whole thousandths with a sign, because the pinned Bend neither reads nor writes a
# decimal. A `P` from the room is every way it says where a player is: the players already
# there when a client joins, and each move after. The room is `world/multiplayer.bend`'s
# `valid_pose` and `world/multiplayer_moves.bend`'s `step`, and a move they refuse comes
# back as a `C`.
#
# The hour is the room's clock as an angle — thousandths of a radian round its day, from the
# morning the day starts on — and the length of a day in milliseconds. The room says it when
# a client joins and when someone calls the morning; `Sky.clock_of_turn` and
# `Sky.clock_after` are what it means for the frame.
#
# What the room simulates comes whole, five times a second: every living mob, every item on
# the ground, every villager, one line each, and an `N` after the last. The client keeps the
# list it is being told apart from the one it shows, and swaps them at the `N`, so a list
# that arrives over two reads is never drawn half. The rules that move them are the room's,
# `world/entities.bend` and `world/villagers.bend`; a client is told where they are.
#
# A hit names the mob and the damage, in thousandths; a pickup names the item on the ground.
# The room judges both from where it holds the player to be (`world/multiplayer_mobs.bend`):
# a hit out of reach misses and a pickup out of reach is refused. What a hit did is in the
# next list. An item the room gave is a `G`, and what a mob did to the player is a `U`.
#
# A room's chests and furnaces are the room's (`Multiplayer.deposit`, `withdraw`,
# `furnace_op`). The room says what each holds when a client joins and whenever one changes,
# as an `S` or an `O`, so the client's copy is the room's. A click on one is a request, and
# its answer is an `R`: whether the room did it, and for a withdrawal or a furnace emptied,
# what came out. A cell is spelled as storage spells it.
#
# This module is the lines and nothing else: it owns no socket. `native/client.bend` reads
# and writes the bytes and calls these to decide what they mean.

def version() -> U32:
  1

def space() -> Char:
  Chr{32}

def newline() -> Char:
  Chr{10}

# Where a player is: its feet in the world's coordinates, and the way it faces.
type Place is Data:
  Place{x: F32, y: F32, z: F32, yaw: F32, pitch: F32}

# Another player of the room: the room's name for it, what it is called, where it stands,
# and whether the room has said where that is. A player is named when it joins and placed
# when it first moves, so one that has only joined is a name with nowhere to draw it.
type Other is Data:
  Other{id: U32, name: String, place: Place, seen: Bool}

# Where the room says this player stands, after a move it refused.
type Stand is Data:
  Stand{x: F32, y: F32, z: F32}

# The room's hour: how far round its day it is, and how long a day lasts.
type Day is Data:
  Day{turn: U32, length: U32}

# Something the room simulates, where it is in the world's coordinates and the way it
# faces. `kind` is `native/body.bend`'s: 1 to 6 a mob of `world/entities.bend`'s kinds, 10
# and a profession a villager, 1000 and an item's id that item on the ground.
#
# `id` is the room's name for a mob or for an item on the ground, which is what a hit or a
# pickup names, and `count` how many of the item lie there. A villager has neither.
type Thing is Data:
  Thing{id: U32, kind: U32, count: U32, x: F32, y: F32, z: F32, yaw: F32}

# An item the room handed over.
type Gain is Data:
  Gain{item: U32, amount: U32}

def villager_base() -> U32:
  10

def drop_base() -> U32:
  1000

# What the room simulates, as the client holds it: the list it shows, and the one it is in
# the middle of being told.
type Sights is Data:
  Sights{shown: List<&2, Thing>, pending: List<&2, Thing>}

# What the room says a chest or a furnace holds: which of the two, its cell, and its numbers
# in order — a chest's slots as triples, a furnace's eight fields — or none when it is gone.
type Box is Data:
  Box{furnace: Bool, x: Nat, y: Nat, z: Nat, values: List<&2, U32>}

# The room's answer to a chest or furnace request.
type Answer is Data:
  Answer{ok: Bool, item: U32, amount: U32, durability: U32}

type Line is Data:
  Welcome{id: U32, seed: Nat}
  Block{edit: WorldState.Edit}
  Refused{reason: String}
  Posed{id: U32, place: Place}
  Parted{id: U32}
  Named{id: U32, name: String}
  Recalled{stand: Stand}
  Timed{day: Day}
  Sighted{thing: Thing}
  Tallied{}
  Hurt{amount: F32}
  Boxed{box: Box}
  Answered{answer: Answer}
  Granted{gain: Gain}
  Noise{}

# --- writing -----------------------------------------------------------------------

def hello(name: String) -> String:
  "H " ++ U32.show(version()) ++ " " ++ name ++ "\n"

def edit_line(edit: WorldState.Edit) -> String:
  WorldState.Edit{x, y, z, block} = edit
  "E " ++ Nat.show(x) ++ " " ++ Nat.show(y) ++ " " ++ Nat.show(z) ++ " " ++ U32.show(block) ++ "\n"

# Every edit as its line, one after another: what one send carries.
def edit_lines(edits: List<&2, WorldState.Edit>, acc: String) -> String:
  match edits:
    case Nil{}:
      acc
    case edit <> rest:
      edit_lines(rest, edit_line(edit) ++ acc)

# A number as whole thousandths, signed. One that rounds to nothing is `0`, not `-0`.
def milli(+value: F32) -> String:
  +scaled = F32.round(F32.mul(value, 1000.0))
  +whole = U32.show(F32.to_u32(F32.abs(scaled)))
  Bool.pick(String, F32.is_lt(scaled, 0.0), "-" ++ whole, whole)

# A hit on a mob, with the damage a whole number of points.
def strike_line(+mob: U32, +damage: U32) -> String:
  "A " ++ U32.show(mob) ++ " " ++ U32.show(U32.mul(damage, 1000)) ++ "\n"

def pickup_line(+drop: U32) -> String:
  "K " ++ U32.show(drop) ++ "\n"

def cell_text(+x: Nat, +y: Nat, +z: Nat) -> String:
  Nat.show(x) ++ " " ++ Nat.show(y) ++ " " ++ Nat.show(z)

def deposit_line(+x: Nat, +y: Nat, +z: Nat, +item: U32, +count: U32, +durability: U32) -> String:
  "CD " ++ cell_text(x, y, z) ++ " " ++ U32.show(item) ++ " " ++ U32.show(count) ++ " " ++ U32.show(durability) ++ "\n"

def withdraw_line(+x: Nat, +y: Nat, +z: Nat, +index: Nat, +amount: U32) -> String:
  "CW " ++ cell_text(x, y, z) ++ " " ++ Nat.show(index) ++ " " ++ U32.show(amount) ++ "\n"

# `which` is 0 to smelt, 1 to burn and 2 to take what was made.
def furnace_line(which: Nat, +x: Nat, +y: Nat, +z: Nat, +item: U32) -> String:
  match which:
    case 0n:
      "FI " ++ cell_text(x, y, z) ++ " " ++ U32.show(item) ++ "\n"
    case 1n:
      "FF " ++ cell_text(x, y, z) ++ " " ++ U32.show(item) ++ "\n"
    case _:
      "FO " ++ cell_text(x, y, z) ++ "\n"

def place_line(place: Place) -> String:
  Place{x, y, z, yaw, pitch} = place
  "P " ++ milli(x) ++ " " ++ milli(y) ++ " " ++ milli(z) ++ " " ++ milli(yaw) ++ " " ++ milli(pitch) ++ "\n"

# --- reading: the bytes into lines -------------------------------------------------

# What a chunk off the socket came to: the whole lines in it, in order, and the start of a
# line whose end has not arrived.
type Fed is Data:
  Fed{lines: List<&2, String>, rest: String}

def unreversed(lines: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}:
      acc
    case line <> rest:
      unreversed(rest, String.reverse(line) <> acc)

# The text split at its newlines, as a loop: `current` is the line being read, backwards,
# and `lines` the whole ones so far, newest first and each backwards too. A chunk can be
# thousands of characters, and a call per character would be a stack that deep.
def feed.go(text: String, +current: String, +lines: List<&2, String>) -> Fed:
  match text:
    case SNil{}:
      Fed{unreversed(lines, []), String.reverse(current)}
    case SCon{+head, tail}:
      +ended = Char.is_eq(head, newline())
      feed.go(tail, Bool.pick(String, ended, "", SCon{head, current}),
        Bool.pick(List<&2, String>, ended, current <> lines, lines))

# `buffer` is what the last chunk left unfinished.
def feed(buffer: String, chunk: String) -> Fed:
  feed.go(String.append(buffer, chunk), "", [])

# --- reading: a line into what it says ---------------------------------------------

def block.at(mx: Maybe<&2, Nat>, my: Maybe<&2, Nat>, mz: Maybe<&2, Nat>,
  mb: Maybe<&2, U32>) -> Line:
  match mx my mz mb:
    case Some{x} Some{y} Some{z} Some{block}:
      Block{WorldState.make_edit(x, y, z, block)}
    case _ _ _ _:
      Noise{}

def welcome.at(mid: Maybe<&2, U32>, mseed: Maybe<&2, Nat>) -> Line:
  match mid mseed:
    case Some{id} Some{seed}:
      Welcome{id, seed}
    case _ _:
      Noise{}

def tagged(tag: String, name: String) -> Bool:
  String.eq(tag, name)

# The fields after the tag, as what the tag says they are. A line with the wrong number of
# fields, or a field that is not a number, is noise: the room is trusted to be the room, and
# a line it did not write is dropped rather than guessed at.
def parse.block(fields: List<&2, String>) -> Line:
  match fields:
    case x <> y <> z <> block <> Nil{}:
      block.at(Nat.read(x), Nat.read(y), Nat.read(z), U32.read(block))
    case _:
      Noise{}

def parse.welcome(fields: List<&2, String>) -> Line:
  match fields:
    case id <> seed <> Nil{}:
      welcome.at(U32.read(id), Nat.read(seed))
    case _:
      Noise{}

# Whole thousandths, signed, as the number they are: what `milli` wrote.
def milli.signed(+negative: Bool, digits: Maybe<&2, U32>) -> Maybe<&2, F32>:
  match digits:
    case None{}:
      None{}
    case Some{+count}:
      Some{F32.div(Bool.pick(F32, negative, F32.neg(U32.to_f32(count)), U32.to_f32(count)), 1000.0)}

def milli.read(text: String) -> Maybe<&2, F32>:
  match text:
    case SNil{}:
      None{}
    case SCon{+head, +tail}:
      +negative = Char.is_eq(head, Chr{45})
      milli.signed(negative, U32.read(Bool.pick(String, negative, tail, SCon{head, tail})))

def posed.at(mid: Maybe<&2, U32>, mx: Maybe<&2, F32>, my: Maybe<&2, F32>, mz: Maybe<&2, F32>,
  myaw: Maybe<&2, F32>, mpitch: Maybe<&2, F32>) -> Line:
  match mid mx my mz myaw mpitch:
    case Some{id} Some{x} Some{y} Some{z} Some{yaw} Some{pitch}:
      Posed{id, Place{x, y, z, yaw, pitch}}
    case _ _ _ _ _ _:
      Noise{}

def parse.posed(fields: List<&2, String>) -> Line:
  match fields:
    case id <> x <> y <> z <> yaw <> pitch <> Nil{}:
      posed.at(U32.read(id), milli.read(x), milli.read(y), milli.read(z), milli.read(yaw),
        milli.read(pitch))
    case _:
      Noise{}

def parted.at(mid: Maybe<&2, U32>) -> Line:
  match mid:
    case Some{id}:
      Parted{id}
    case None{}:
      Noise{}

def parse.parted(fields: List<&2, String>) -> Line:
  match fields:
    case id <> Nil{}:
      parted.at(U32.read(id))
    case _:
      Noise{}

def recalled.at(mx: Maybe<&2, F32>, my: Maybe<&2, F32>, mz: Maybe<&2, F32>) -> Line:
  match mx my mz:
    case Some{x} Some{y} Some{z}:
      Recalled{Stand{x, y, z}}
    case _ _ _:
      Noise{}

def parse.recalled(fields: List<&2, String>) -> Line:
  match fields:
    case x <> y <> z <> Nil{}:
      recalled.at(milli.read(x), milli.read(y), milli.read(z))
    case _:
      Noise{}

# A day of no length is not a day.
def timed.kept(lasting: Bool, turn: U32, length: U32) -> Line:
  match lasting:
    case True{}:
      Timed{Day{turn, length}}
    case False{}:
      Noise{}

def timed.at(mturn: Maybe<&2, U32>, mlength: Maybe<&2, U32>) -> Line:
  match mturn mlength:
    case Some{turn} Some{+length}:
      timed.kept(U32.is_gt(length, 0), turn, length)
    case _ _:
      Noise{}

def parse.timed(fields: List<&2, String>) -> Line:
  match fields:
    case turn <> length <> Nil{}:
      timed.at(U32.read(turn), U32.read(length))
    case _:
      Noise{}

def parse.tagged(block: Bool, welcome: Bool, refused: Bool, posed: Bool, parted: Bool,
  recalled: Bool, timed: Bool, fields: List<&2, String>) -> Line:
  match block welcome refused posed parted recalled timed:
    case True{} _ _ _ _ _ _:
      parse.block(fields)
    case False{} True{} _ _ _ _ _:
      parse.welcome(fields)
    case False{} False{} True{} _ _ _ _:
      Refused{String.join(fields, " ")}
    case False{} False{} False{} True{} _ _ _:
      parse.posed(fields)
    case False{} False{} False{} False{} True{} _ _:
      parse.parted(fields)
    case False{} False{} False{} False{} False{} True{} _:
      parse.recalled(fields)
    case False{} False{} False{} False{} False{} False{} True{}:
      parse.timed(fields)
    case False{} False{} False{} False{} False{} False{} False{}:
      Noise{}

def thing.at(+base: U32, mid: Maybe<&2, U32>, mkind: Maybe<&2, U32>, mcount: Maybe<&2, U32>,
  mx: Maybe<&2, F32>, my: Maybe<&2, F32>, mz: Maybe<&2, F32>, myaw: Maybe<&2, F32>) -> Line:
  match mid mkind mcount mx my mz myaw:
    case Some{id} Some{kind} Some{count} Some{x} Some{y} Some{z} Some{yaw}:
      Sighted{Thing{id, U32.add(base, kind), count, x, y, z, yaw}}
    case _ _ _ _ _ _ _:
      Noise{}

def parse.mob(fields: List<&2, String>) -> Line:
  match fields:
    case id <> kind <> x <> y <> z <> yaw <> Nil{}:
      thing.at(0, U32.read(id), U32.read(kind), Some{1}, milli.read(x), milli.read(y),
        milli.read(z), milli.read(yaw))
    case _:
      Noise{}

# An item on the ground faces no way of its own.
def parse.item(fields: List<&2, String>) -> Line:
  match fields:
    case id <> item <> count <> x <> y <> z <> Nil{}:
      thing.at(drop_base(), U32.read(id), U32.read(item), U32.read(count), milli.read(x),
        milli.read(y), milli.read(z), Some{0.0})
    case _:
      Noise{}

# A villager has no name a client uses, and faces whoever looks at it.
def parse.villager(fields: List<&2, String>) -> Line:
  match fields:
    case profession <> x <> y <> z <> Nil{}:
      thing.at(villager_base(), Some{0}, U32.read(profession), Some{1}, milli.read(x),
        milli.read(y), milli.read(z), Some{0.0})
    case _:
      Noise{}

def hurt.at(mamount: Maybe<&2, F32>) -> Line:
  match mamount:
    case Some{amount}:
      Hurt{amount}
    case None{}:
      Noise{}

def parse.hurt(fields: List<&2, String>) -> Line:
  match fields:
    case amount <> Nil{}:
      hurt.at(milli.read(amount))
    case _:
      Noise{}

def granted.at(mitem: Maybe<&2, U32>, mamount: Maybe<&2, U32>) -> Line:
  match mitem mamount:
    case Some{item} Some{amount}:
      Granted{Gain{item, amount}}
    case _ _:
      Noise{}

def parse.granted(fields: List<&2, String>) -> Line:
  match fields:
    case item <> amount <> Nil{}:
      granted.at(U32.read(item), U32.read(amount))
    case _:
      Noise{}

# The lines of what the room simulates and of what it did to this player, or `other`, which
# is what the line was otherwise.
def parse.sight(mob: Bool, item: Bool, villager: Bool, tally: Bool, hurt: Bool, granted: Bool,
  fields: List<&2, String>, other: Line) -> Line:
  match mob item villager tally hurt granted:
    case True{} _ _ _ _ _:
      parse.mob(fields)
    case False{} True{} _ _ _ _:
      parse.item(fields)
    case False{} False{} True{} _ _ _:
      parse.villager(fields)
    case False{} False{} False{} True{} _ _:
      Tallied{}
    case False{} False{} False{} False{} True{} _:
      parse.hurt(fields)
    case False{} False{} False{} False{} False{} True{}:
      parse.granted(fields)
    case False{} False{} False{} False{} False{} False{}:
      other

def named.at(mid: Maybe<&2, U32>, name: String) -> Line:
  match mid:
    case Some{id}:
      Named{id, name}
    case None{}:
      Noise{}

# A name is the rest of the line, spaces and all, and `other` is what the line was otherwise.
def parse.named(named: Bool, fields: List<&2, String>, other: Line) -> Line:
  match named fields:
    case True{} id <> name:
      named.at(U32.read(id), String.join(name, " "))
    case True{} Nil{}:
      Noise{}
    case False{} _:
      other

# Every field a whole number, or the line is noise.
type Wholes is Data:
  Wholes{values: List<&2, U32>, sound: Bool}

def wholes.one(value: Maybe<&2, U32>, wholes: Wholes) -> Wholes:
  match value:
    case Some{number}:
      Wholes{values, sound} = wholes
      Wholes{number <> values, sound}
    case None{}:
      Wholes{values, sound} = wholes
      Wholes{values, False{}}

def wholes.go(fields: List<&2, String>, wholes: Wholes) -> Wholes:
  match fields:
    case Nil{}:
      wholes
    case field <> rest:
      wholes.go(rest, wholes.one(U32.read(field), wholes))

def boxed.at(wholes: Wholes, furnace: Bool, x: Nat, y: Nat, z: Nat) -> Line:
  Wholes{values, sound} = wholes
  match sound:
    case True{}:
      Boxed{Box{furnace, x, y, z, List.reverse(&2, U32, values)}}
    case False{}:
      Noise{}

def boxed.cell(mx: Maybe<&2, Nat>, my: Maybe<&2, Nat>, mz: Maybe<&2, Nat>, furnace: Bool,
  rest: List<&2, String>) -> Line:
  match mx my mz:
    case Some{x} Some{y} Some{z}:
      boxed.at(wholes.go(rest, Wholes{[], True{}}), furnace, x, y, z)
    case _ _ _:
      Noise{}

def parse.boxed(furnace: Bool, fields: List<&2, String>) -> Line:
  match fields:
    case x <> y <> z <> rest:
      boxed.cell(Nat.read(x), Nat.read(y), Nat.read(z), furnace, rest)
    case _:
      Noise{}

def answered.at(mok: Maybe<&2, U32>, mitem: Maybe<&2, U32>, mamount: Maybe<&2, U32>,
  mwear: Maybe<&2, U32>) -> Line:
  match mok mitem mamount mwear:
    case Some{ok} Some{item} Some{amount} Some{durability}:
      Answered{Answer{U32.is_ne(ok, 0), item, amount, durability}}
    case _ _ _ _:
      Noise{}

def parse.answered(fields: List<&2, String>) -> Line:
  match fields:
    case ok <> item <> amount <> durability <> Nil{}:
      answered.at(U32.read(ok), U32.read(item), U32.read(amount), U32.read(durability))
    case _:
      Noise{}

# The lines about a room's chests and furnaces, or `other`.
def parse.stored(chest: Bool, furnace: Bool, answer: Bool, fields: List<&2, String>, other: Line) -> Line:
  match chest furnace answer:
    case True{} _ _:
      parse.boxed(False{}, fields)
    case False{} True{} _:
      parse.boxed(True{}, fields)
    case False{} False{} True{}:
      parse.answered(fields)
    case False{} False{} False{}:
      other

def parse.words(words: List<&2, String>) -> Line:
  match words:
    case Nil{}:
      Noise{}
    case +tag <> +fields:
      parse.stored(tagged(tag, "S"), tagged(tag, "O"), tagged(tag, "R"), fields, parse.named(tagged(tag, "J"), fields,
        parse.sight(tagged(tag, "M"), tagged(tag, "D"), tagged(tag, "V"), tagged(tag, "N"),
          tagged(tag, "U"), tagged(tag, "G"), fields,
          parse.tagged(tagged(tag, "B"), tagged(tag, "W"), tagged(tag, "X"), tagged(tag, "P"),
            tagged(tag, "L"), tagged(tag, "C"), tagged(tag, "T"), fields))))

def parse(line: String) -> Line:
  parse.words(String.split(line, space()))

# --- what a frame's lines come to ---------------------------------------------------

# The cells the room set, oldest first, which is the order `WorldState.set_many` wants; the
# seed of the world the room is, once it has said; why it refused, if it did; the room's
# other players as they now stand; where the room put this player back to, if it did; and
# the room's hour, if it said; what the room simulates, as far as it has been told; how much
# the player was hurt; the items the room handed over; what the room said its chests and
# furnaces hold, in the order it said it; and its answers to this player's requests.
type Inbox is Data:
  Inbox{edits: List<&2, WorldState.Edit>, seed: Maybe<&2, Nat>, refused: Maybe<&2, String>,
    others: List<&2, Other>, back: Maybe<&2, Stand>, hour: Maybe<&2, Day>, sights: Sights,
    hurt: F32, gains: List<&2, Gain>, boxes: List<&2, Box>, answers: List<&2, Answer>}

# One more thing in the list being told.
def sights.seen(sights: Sights, thing: Thing) -> Sights:
  Sights{shown, pending} = sights
  Sights{shown, thing <> pending}

# The list is all told: it is the one to show, and the next starts empty.
def sights.tallied(sights: Sights) -> Sights:
  Sights{shown, pending} = sights
  Sights{pending, []}

# The players without one of them. The order of the others is nobody's to read.
def others.without(others: List<&2, Other>, +id: U32, +acc: List<&2, Other>) -> List<&2, Other>:
  match others:
    case Nil{}:
      acc
    case Other{+other, name, place, seen} <> rest:
      others.without(rest, id,
        Bool.pick(List<&2, Other>, U32.is_eq(other, id), acc, Other{other, name, place, seen} <> acc))

# The player the room calls `id`, or `fallback` when the client has not heard of it.
def others.found(others: List<&2, Other>, +id: U32, +fallback: Other) -> Other:
  match others:
    case Nil{}:
      fallback
    case Other{+other, name, place, seen} <> rest:
      others.found(rest, id, Bool.pick(Other, U32.is_eq(other, id), Other{other, name, place, seen}, fallback))

def nowhere() -> Place:
  Place{0.0, 0.0, 0.0, 0.0, 0.0}

def other.placed(other: Other, place: Place) -> Other:
  Other{id, name, old, seen} = other
  Other{id, name, place, True{}}

def other.named(other: Other, name: String) -> Other:
  Other{id, old, place, seen} = other
  Other{id, name, place, seen}

# A pose is a player the client had not heard of, or the same player somewhere else. It
# keeps the name it had.
def others.posed(+others: List<&2, Other>, +id: U32, place: Place) -> List<&2, Other>:
  other.placed(others.found(others, id, Other{id, "", nowhere(), False{}}), place)
    <> others.without(others, id, [])

# A name is a player who joined, or the name of one already there. It keeps where it stood.
def others.named(+others: List<&2, Other>, +id: U32, name: String) -> List<&2, Other>:
  other.named(others.found(others, id, Other{id, "", nowhere(), False{}}), name)
    <> others.without(others, id, [])

def inbox.with(line: Line, inbox: Inbox) -> Inbox:
  match line inbox:
    case Welcome{id, world} Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers}:
      Inbox{edits, Some{world}, refused, others, back, hour, sights, hurt, gains, boxes, answers}
    case Block{edit} Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers}:
      Inbox{edit <> edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers}
    case Refused{reason} Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers}:
      Inbox{edits, seed, Some{reason}, others, back, hour, sights, hurt, gains, boxes, answers}
    case Posed{id, place} Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers}:
      Inbox{edits, seed, refused, others.posed(others, id, place), back, hour, sights, hurt, gains, boxes, answers}
    case Named{id, name} Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers}:
      Inbox{edits, seed, refused, others.named(others, id, name), back, hour, sights, hurt, gains, boxes, answers}
    case Parted{id} Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers}:
      Inbox{edits, seed, refused, others.without(others, id, []), back, hour, sights, hurt, gains, boxes, answers}
    case Recalled{stand} Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers}:
      Inbox{edits, seed, refused, others, Some{stand}, hour, sights, hurt, gains, boxes, answers}
    case Timed{day} Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers}:
      Inbox{edits, seed, refused, others, back, Some{day}, sights, hurt, gains, boxes, answers}
    case Sighted{thing} Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers}:
      Inbox{edits, seed, refused, others, back, hour, sights.seen(sights, thing), hurt, gains, boxes, answers}
    case Tallied{} Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers}:
      Inbox{edits, seed, refused, others, back, hour, sights.tallied(sights), hurt, gains, boxes, answers}
    case Hurt{amount} Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers}:
      Inbox{edits, seed, refused, others, back, hour, sights, F32.add(hurt, amount), gains, boxes, answers}
    case Granted{gain} Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers}:
      Inbox{edits, seed, refused, others, back, hour, sights, hurt, gain <> gains, boxes, answers}
    case Boxed{box} Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers}:
      Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, box <> boxes, answers}
    case Answered{answer} Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers}:
      Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answer <> answers}
    case Noise{} Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers}:
      Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers}

def inbox.go(lines: List<&2, String>, inbox: Inbox) -> Inbox:
  match lines:
    case Nil{}:
      inbox
    case line <> rest:
      inbox.go(rest, inbox.with(parse(line), inbox))

def inbox.ordered(inbox: Inbox) -> Inbox:
  Inbox{edits, seed, refused, others, back, hour, sights, hurt, gains, boxes, answers} = inbox
  Inbox{List.reverse(&2, WorldState.Edit, edits), seed, refused, others, back, hour, sights, hurt,
    gains, List.reverse(&2, Box, boxes), List.reverse(&2, Answer, answers)}

# `others` is the room's other players as the last frame left them, and `sights` what the
# room simulates.
def inbox(lines: List<&2, String>, others: List<&2, Other>, sights: Sights) -> Inbox:
  inbox.ordered(inbox.go(lines, Inbox{[], None{}, None{}, others, None{}, None{}, sights, 0.0, [], [], []}))

# --- what the room has not heard ----------------------------------------------------
#
# `known` is the edit log as the room last heard it and `local` the log now. Between two
# frames the client's own tick is the only thing that changes one and not the other, and
# `WorldState.set` changes a log in one of two ways: it puts a new entry at the head, or it
# replaces a cell's entry where it stands. So the two logs are walked side by side: an
# entry of `local` that is not `known`'s entry at that place is new and is walked past on
# `local` alone, and one that is the same cell with another block was replaced. Both are
# what the room has not heard. It is one pass, however long the log is.

def same_cell(a: WorldState.Edit, b: WorldState.Edit) -> Bool:
  WorldState.Edit{ax, ay, az, ablock} = a
  WorldState.Edit{bx, by, bz, bblock} = b
  Bool.and(Bool.and(Nat.is_eq(ax, bx), Nat.is_eq(ay, by)), Nat.is_eq(az, bz))

def same_block(a: WorldState.Edit, b: WorldState.Edit) -> Bool:
  U32.is_eq(WorldState.edit_value(a), WorldState.edit_value(b))

def unheard.go(local: List<&2, WorldState.Edit>, +known: List<&2, WorldState.Edit>,
  +acc: List<&2, WorldState.Edit>) -> List<&2, WorldState.Edit>:
  match local:
    case Nil{}:
      acc
    case +head <> rest:
      match known:
        case Nil{}:
          unheard.go(rest, [], head <> acc)
        case +heard <> older:
          +aligned = same_cell(head, heard)
          unheard.go(rest, Bool.pick(List<&2, WorldState.Edit>, aligned, older, known),
            Bool.pick(List<&2, WorldState.Edit>, Bool.and(aligned, same_block(head, heard)),
              acc, head <> acc))

# The edits of `local` the room has not heard, oldest first.
def unheard(local: List<&2, WorldState.Edit>, +known: List<&2, WorldState.Edit>) ->
  List<&2, WorldState.Edit>:
  unheard.go(local, known, [])

# --- where to join ------------------------------------------------------------------

type Address is Data:
  Address{host: String, port: U32}

def address.at(host: String, port: Maybe<&2, U32>) -> Maybe<&2, Address>:
  match port:
    case Some{number}:
      Some{Address{host, number}}
    case None{}:
      None{}

def address.of(parts: List<&2, String>) -> Maybe<&2, Address>:
  match parts:
    case host <> port <> Nil{}:
      address.at(host, U32.read(port))
    case _:
      None{}

# `host:port` as an address, or nothing when it is not one.
def address(text: String) -> Maybe<&2, Address>:
  address.of(String.split(text, Chr{58}))
