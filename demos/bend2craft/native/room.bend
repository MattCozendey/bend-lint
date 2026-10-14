import Base
import ./bag.bend as Bag
import ../world/entities.bend as Entities
import ./frame.bend as Frame
import ./hour.bend as Hour
import ../world/inventory.bend as Inventory
import ../world/multiplayer_mobs.bend as MultiplayerMobs
import ./net.bend as Net
import ./play.bend as Play
import ../world/player.bend as Player
import ./size.bend as Size
import ./stores.bend as Stores
import ../world/world_state.bend as WorldState

# A room, from the client's side: the socket, what is sent and read each tick, and what the
# room's mobs and items ask of the client. The client under it is `native/play.bend`'s and the
# lines are `native/net.bend`'s. The rules are `world/`'s (`Entities.aim_step` for the mob under
# the crosshair, `Inventory.melee_damage`, `Player.damage`); two small ones are still decided
# here and are the next to move: an item is asked for only when the whole of it fits the bag
# (`wanted`), and a player a mob kills starts again at the spawn (`revived`).

# --- a room ----------------------------------------------------------------------
#
# A client started with `--join=host:port` plays in a multiplayer room: the one the browsers
# are in, through the server's native door (`server/native-bridge.mjs`). `native/net.bend` is
# the lines; this is the socket and when it is read.
#
# The room's world is its seed and its edit log, and the client's world is exactly that too,
# so playing together is keeping the two logs the same. Once a tick, before the tick:
#
# - what the client's own tick changed since the room last heard is sent, as edits;
# - whatever the room has said is read, without waiting, and every cell it names is set.
#
# The client does not wait to be told its own dig was accepted: it has already dug, and the
# room sends the cell back to everyone, the sender included. If the room refuses an edit it
# sends back what the cell holds, and the cell goes back to that. The bag is the client's
# own and is not put back: a refused placing costs the item.
#
# The players are shared the same way, in the same exchange. The client says where it is —
# when that changed, and no more than twenty times a second — and the room says where the
# others are, who left, and where this player stands when it refuses a move
# (`world/multiplayer_moves.bend`). The others are kept beside the socket and handed to the
# view, which draws them (`native/body.bend`) and writes each one's name over its head
# (`native/tag.bend`).
#
# The hour is the room's too: its sun, its light and its night, which are the browsers'. The
# clouds keep the client's own pace.
#
# What the room simulates is drawn where the room says it is: its mobs, its villagers and
# the items on its ground, told whole five times a second and swapped when the list is
# complete (`Net.Sights`).
#
# The player acts on them through the room, as a browser does. The dig key with a mob under
# the crosshair, within `MultiplayerMobs.melee_range`, is a hit on it for
# `Inventory.melee_damage` of what is in hand, and the block behind is left alone; which
# mob that is, is `Entities.aim_distance`'s answer. An item on the ground within reach
# (`Entities.nearest_drop`) that the bag has room for is asked for, and joins the bag when
# the room hands it over. What a mob does to the player arrives as an amount and is
# `Player.damage`; a player it kills starts again at the spawn. The room judges every one
# of these from the pose it holds. A chest and a furnace are the room's too: it says what
# each holds, and a click on one is a request it answers (`native/stores.bend`).
#
# A joined client starts from the room's log and not from its own save, and `T` writes
# another file, so a room never overwrites a single-player world.

# What the room has said: the other players as it last placed them, its hour, and what it
# simulates.
type Told is Data:
  Told{others: List<&2, Net.Other>, hour: Hour.Hour, sights: Net.Sights}

# What the client has to say to the room, and when it may: the pose line it last sent, how
# many ticks it waits before it may send another, the lines the last tick left to say, and
# how many ticks it rests before it asks for another item.
type Outbox is Data:
  Outbox{posed: String, wait: U32, say: String, pause: U32}

# What the client knows of the room beside its cells.
type Peers is Data:
  Peers{told: Told, outbox: Outbox}

type Link is Type:
  Alone{}
  Online{socket: Socket, buffer: String, known: List<&2, WorldState.Edit>, peers: Peers}

type Session is Type:
  Session{client: Play.Client, link: Link}

def room_path() -> String:
  "native/client-room.b2cw"

# The ticks between two poses: a pose every third tick is twenty a second.
def pose_gap() -> U32:
  2

# The ticks between two pickups: the room's next list, which no longer has the item, is a
# fifth of a second away, and asking again before it would ask for an item already given.
def pickup_rest() -> U32:
  30

# Where a player is as the room has it: the world's coordinates, feet first.
def place_of(player: Player.State) -> Net.Place:
  Player.State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall,
    poison} = player
  Net.Place{F32.sub(x, Play.window_origin()), y, F32.sub(z, Play.window_origin()), yaw, pitch}

# The player standing where the room says, and no longer falling or rising.
def stood_at(player: Player.State, stand: Net.Stand) -> Player.State:
  Player.State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall,
    poison} = player
  Net.Stand{sx, sy, sz} = stand
  Player.State{F32.add(sx, Play.window_origin()), sy, F32.add(sz, Play.window_origin()), yaw, pitch, 0.0,
    False{}, health, hunger, air, fall, poison}

# The client put back where the room last accepted it, when the room refused a move. The
# next tick is what works out the camera and the regions from there.
def recalled(back: Maybe<&2, Net.Stand>, +client: Play.Client) -> Play.Client:
  match back:
    case None{}:
      client
    case Some{stand}:
      Play.with_player(client, stood_at(Play.player_of(client), stand))

# The client with the room's cells set. The collision region is rebuilt with them, or a
# block another player placed would be in the picture and not in the way.
def absorbed.at(nothing: Bool, +client: Play.Client, +batch: List<&2, WorldState.Edit>) -> Play.Client:
  match nothing:
    case True{}:
      client
    case False{}:
      Play.Client{avatar, Play.Ground{edits, +region, world, home, world_ms}, setup, bag, clock, dig} = client
      +next : List<&2, WorldState.Edit> = WorldState.set_many(edits, batch)
      Play.Client{avatar, Play.Ground{next, Play.region_or(Play.collision_region(next, Play.den_of(region)), region), world, home, world_ms},
        setup, bag, clock, dig}

def absorbed(+client: Play.Client, +batch: List<&2, WorldState.Edit>) -> Play.Client:
  absorbed.at(List.is_empty(&2, WorldState.Edit, batch), client, batch)

# The connection is over: the socket is closed, the player is told why, and the client goes
# on alone in the world as the room left it.
def left(reason: String, socket: Socket, client: Play.Client) -> IO(Session):
  do IO<Session>:
    closed : Unit <- Socket.close(socket)
    said : Unit <- IO.print("native-client: left the room: " ++ reason)
    return Session{client, Alone{}}

def wrong_seed(seed: Maybe<&2, Nat>) -> Bool:
  match seed:
    case None{}:
      False{}
    case Some{world}:
      Nat.is_ne(world, Frame.seed())

# --- what a room's mobs do, and what is done to them ------------------------------

# The mob under the crosshair is the world's rule (`Entities.aim_step`): each body is tested
# only out to the nearest found so far, and only a mob counts. What is here is the walk over
# what the room says stands there.
def quarry.go(things: List<&2, Net.Thing>, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32,
  +dz: F32, +best: Entities.Aimed) -> Entities.Aimed:
  match things:
    case Nil{}:
      best
    case Net.Thing{+id, +kind, count, +x, +y, +z, yaw} <> rest:
      quarry.go(rest, ox, oy, oz, dx, dy, dz,
        Entities.aim_step(best, ox, oy, oz, dx, dy, dz, id, kind, x, y, z))

# The mob a player standing at `place` looks at, within a hit's reach: the ray is from the
# eye along `Player.direction`'s way.
def quarry(things: List<&2, Net.Thing>, place: Net.Place) -> Entities.Aimed:
  Net.Place{x, y, z, +yaw, +pitch} = place
  quarry.go(things, x, F32.add(y, Frame.eye_height()), z, F32.mul(F32.sin(yaw), F32.cos(pitch)),
    F32.sin(pitch), F32.neg(F32.mul(F32.cos(yaw), F32.cos(pitch))),
    Entities.aim_none(MultiplayerMobs.melee_range()))

# The items on the ground, as the rules' own drops.
def drops.go(things: List<&2, Net.Thing>, +acc: List<&2, Entities.Drop>) -> List<&2, Entities.Drop>:
  match things:
    case Nil{}:
      acc
    case Net.Thing{id, +kind, count, x, y, z, yaw} <> rest:
      drops.go(rest, Bool.pick(List<&2, Entities.Drop>, U32.is_ge(kind, Net.drop_base()),
        Entities.cons_drop(Entities.make_drop(U32.to_nat(id), U32.sub(kind, Net.drop_base()), x, y, z, count), acc),
        acc))

# An item is asked for only when the bag has room for all of it: the room hands it over
# whole, and what did not fit would be lost.
def wanted.at(target: Entities.DropTarget, bag: Bag.Bag) -> Maybe<&2, U32>:
  match target:
    case Entities.DropMissing{}:
      None{}
    case Entities.DropFound{id, item, amount}:
      Bool.pick(Maybe<&2, U32>,
        U32.is_eq(Inventory.add_remaining(Inventory.add_items(Bag.slots_of(bag), item, amount)), 0),
        Some{U32.from_nat(id)}, None{})

# The item on the ground the player would pick up now, if any: `Entities.nearest_drop`'s.
def wanted(things: List<&2, Net.Thing>, place: Net.Place, bag: Bag.Bag) -> Maybe<&2, U32>:
  Net.Place{x, y, z, yaw, pitch} = place
  wanted.at(Entities.nearest_drop(drops.go(things, Entities.empty_drops()), x, y, z), bag)

# A player a mob has killed starts again at the spawn, as one that fell out of the world does.
def revived(alive: Bool, player: Player.State) -> Player.State:
  match alive:
    case True{}:
      player
    case False{}:
      Frame.initial_player()

def hurt_player(+hurt: F32, +player: Player.State) -> Player.State:
  revived(Player.alive(Player.damage(player, hurt)), Player.damage(player, hurt))

# The client after what a room's mobs did to it this frame.
def harmed(+hurt: F32, +client: Play.Client) -> Play.Client:
  Play.with_player(client, hurt_player(hurt, Play.player_of(client)))

def gains.go(gains: List<&2, Net.Gain>, slots: List<&2, Inventory.Slot>) -> List<&2, Inventory.Slot>:
  match gains:
    case Nil{}:
      slots
    case Net.Gain{item, amount} <> rest:
      gains.go(rest, Inventory.add_slots(Inventory.add_items(slots, item, amount)))

def bag_gained(gains: List<&2, Net.Gain>, bag: Bag.Bag) -> Bag.Bag:
  Bag.Bag{slots, selected, desk, store} = bag
  Bag.Bag{gains.go(gains, slots), selected, desk, store}

# The client with the items the room handed over in its bag.
def gained(gains: List<&2, Net.Gain>, +client: Play.Client) -> Play.Client:
  Play.with_bag(client, bag_gained(gains, Play.bag_of(client)))

# What the room said its chests and furnaces hold, in the order it said it.
def boxes.go(boxes: List<&2, Net.Box>, store: Bag.Store) -> Bag.Store:
  match boxes:
    case Nil{}:
      store
    case box <> rest:
      boxes.go(rest, Stores.put(store, box))

def answered.moved(moved: Stores.Moved, slots: List<&2, Inventory.Slot>, selected: Nat, mode: U32,
  x: F32, y: F32, grid: List<&2, Inventory.Slot>) -> Bag.Bag:
  Stores.Moved{held, store} = moved
  Bag.Bag{slots, selected, Bag.Desk{mode, x, y, held, grid}, store}

# The room's answers to this client's requests, each applied to what the arrow carries.
def answers.go(answers: List<&2, Net.Answer>, bag: Bag.Bag) -> Bag.Bag:
  match answers:
    case Nil{}:
      bag
    case Net.Answer{ok, item, amount, durability} <> rest:
      Bag.Bag{slots, selected, Bag.Desk{mode, x, y, held, grid}, store} = bag
      answers.go(rest,
        answered.moved(Stores.answered(store, held, ok, item, amount, durability), slots, selected, mode, x,
          y, grid))

def bag_stored(boxes: List<&2, Net.Box>, answers: List<&2, Net.Answer>, bag: Bag.Bag) -> Bag.Bag:
  Bag.Bag{slots, selected, desk, store} = bag
  answers.go(answers, Bag.Bag{slots, selected, desk, boxes.go(boxes, store)})

# The client with the room's word on its chests and furnaces, and on what was asked of them.
def stored(boxes: List<&2, Net.Box>, answers: List<&2, Net.Answer>, +client: Play.Client) -> Play.Client:
  Play.with_bag(client, bag_stored(boxes, answers, Play.bag_of(client)))

def heard.sorted(refused: Maybe<&2, String>, other_world: Bool, socket: Socket, rest: String,
  +client: Play.Client, +batch: List<&2, WorldState.Edit>, back: Maybe<&2, Net.Stand>,
  hurt: F32, gains: List<&2, Net.Gain>, boxes: List<&2, Net.Box>, answers: List<&2, Net.Answer>,
  peers: Peers) -> IO(Session):
  match refused other_world:
    case Some{reason} _:
      left(reason, socket, client)
    case None{} True{}:
      left("the room's world has another seed", socket, client)
    case None{} False{}:
      +next : Play.Client = absorbed(client, batch)
      IO.pure(Session, Session{stored(boxes, answers, gained(gains, harmed(hurt, recalled(back, next)))),
        Online{socket, rest, Play.edits_of(next), peers}})

# The hour after a frame's lines: what the room just said, or what it was.
def hour.heard(said: Maybe<&2, Net.Day>, old: Hour.Hour) -> Hour.Hour:
  match said:
    case Some{Net.Day{turn, length}}:
      Hour.Heard{turn, length}
    case None{}:
      old

def heard.inbox(inbox: Net.Inbox, socket: Socket, rest: String, +client: Play.Client, outbox: Outbox,
  old: Hour.Hour) -> IO(Session):
  Net.Inbox{batch, +seed, refused, others, back, hour, sights, hurt, gains, boxes, answers} = inbox
  heard.sorted(refused, wrong_seed(seed), socket, rest, client, batch, back, hurt, gains, boxes, answers,
    Peers{Told{others, hour.heard(hour, old), sights}, outbox})

def heard.fed(fed: Net.Fed, socket: Socket, +client: Play.Client, peers: Peers) -> IO(Session):
  Net.Fed{lines, rest} = fed
  Peers{Told{others, hour, sights}, outbox} = peers
  heard.inbox(Net.inbox(lines, others, sights), socket, rest, client, outbox, hour)

# An empty chunk is the peer's close, as `TCP.recv` answers it.
def heard.chunk(closed: Bool, chunk: String, socket: Socket, buffer: String,
  +client: Play.Client, peers: Peers) -> IO(Session):
  match closed:
    case True{}:
      left("the server closed the connection", socket, client)
    case False{}:
      heard.fed(Net.feed(buffer, chunk), socket, client, peers)

def heard.result(result: Result<&1, &1, U32 & String, Maybe<&1, String>>, socket: Socket,
  buffer: String, +client: Play.Client, peers: Peers) -> IO(Session):
  match result:
    case Fail{error}:
      left("the connection failed", socket, client)
    case Done{None{}}:
      IO.pure(Session, Session{client, Online{socket, buffer, Play.edits_of(client), peers}})
    case Done{Some{+chunk}}:
      heard.chunk(String.is_empty(chunk), chunk, socket, buffer, client, peers)

def heard(polled: Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>, buffer: String,
  +client: Play.Client, peers: Peers) -> IO(Session):
  (socket, result) = polled
  heard.result(result, socket, buffer, client, peers)

# How much is read off the socket in one tick. A room's whole log can be much more than this
# when a client joins; it arrives over the ticks that follow.
def read_most() -> U32:
  8192

def listened(socket: Socket, buffer: String, +client: Play.Client, peers: Peers) -> IO(Session):
  do IO<Session>:
    polled : Socket & Result<&1, &1, U32 & String, Maybe<&1, String>> <- TCP.poll(socket, read_most(), 0)
    heard(polled, buffer, client, peers)

def said(sent: Socket & Result<&1, &1, U32 & String, Unit>, buffer: String,
  +client: Play.Client, peers: Peers) -> IO(Session):
  (socket, result) = sent
  match result:
    case Fail{error}:
      left("the connection failed", socket, client)
    case Done{unit}:
      listened(socket, buffer, client, peers)

# Nothing to say is not a send.
def say(quiet: Bool, socket: Socket, text: String) ->
  IO(Socket & Result<&1, &1, U32 & String, Unit>):
  match quiet:
    case True{}:
      IO.pure(Socket & Result<&1, &1, U32 & String, Unit>, (socket, Done{Unit{}}))
    case False{}:
      TCP.send(socket, text)

def synced.text(+text: String, socket: Socket, buffer: String, +client: Play.Client,
  peers: Peers) -> IO(Session):
  do IO<Session>:
    sent : Socket & Result<&1, &1, U32 & String, Unit> <- say(String.is_empty(text), socket, text)
    said(sent, buffer, client, peers)

# The client's pose line, when the room should hear it: it is not the one last sent, and the
# wait since that one is over.
def synced.posed(+due: Bool, +line: String, +edits: String, socket: Socket, buffer: String,
  +client: Play.Client, told: Told, +posed: String, +wait: U32, pause: U32) -> IO(Session):
  synced.text(String.append(edits, Bool.pick(String, due, line, "")), socket, buffer, client,
    Peers{told, Outbox{Bool.pick(String, due, line, posed),
      Bool.pick(U32, due, pose_gap(), U32.sub(wait, U32.min(wait, 1))), "", pause}})

# One tick's exchange with the room: what it has not heard is sent — the cells the client
# changed, the hits and pickups the last tick left to say, then where it is — and what it
# has said is read. `known` is the log as the room
# last heard it.
def synced(socket: Socket, buffer: String, known: List<&2, WorldState.Edit>, peers: Peers,
  +client: Play.Client) -> IO(Session):
  Peers{told, Outbox{+posed, +wait, say, pause}} = peers
  +line = Net.place_line(place_of(Play.player_of(client)))
  synced.posed(Bool.and(U32.is_eq(wait, 0), Bool.not(String.eq(line, posed))), line,
    String.append(Net.edit_lines(Net.unheard(Play.edits_of(client), known), ""), say), socket, buffer,
    client, told, posed, wait, pause)

def link.closed(link: Link) -> IO(Maybe<Session>):
  match link:
    case Alone{}:
      IO.pure(Maybe<Session>, None{})
    case Online{socket, buffer, known, peers}:
      do IO<Maybe<Session>>:
        closed : Unit <- Socket.close(socket)
        return None{}

def session.next(link: Link, next: Maybe<Play.Client>) -> IO(Maybe<Session>):
  match next:
    case None{}:
      link.closed(link)
    case Some{client}:
      IO.pure(Maybe<Session>, Some{Session{client, link}})

def session.ticked(events: List<&1, Event>, session: Session) -> IO(Maybe<Session>):
  Session{client, link} = session
  IO.bind(Maybe<Play.Client>, Maybe<Session>, Play.tick.events(events, client), next => session.next(link, next))

def peers.timed(peers: Peers, +now: Nat) -> Peers:
  Peers{Told{others, hour, sights}, outbox} = peers
  Peers{Told{others, Hour.hour.at(hour, now), sights}, outbox}

def link.timed(link: Link, +now: Nat) -> Link:
  match link:
    case Alone{}:
      Alone{}
    case Online{socket, buffer, known, peers}:
      Online{socket, buffer, known, peers.timed(peers, now)}

# The session with the room's hour brought up to `now`.
def session.timed(session: Session, +now: Nat) -> Session:
  Session{client, link} = session
  Session{client, link.timed(link, now)}

def shown_of(sights: Net.Sights) -> List<&2, Net.Thing>:
  Net.Sights{shown, pending} = sights
  shown

def told_things(told: Told) -> List<&2, Net.Thing>:
  Told{others, hour, sights} = told
  shown_of(sights)

def told_of(peers: Peers) -> Told:
  Peers{told, outbox} = peers
  told

# What the room has said, as the session last heard it: nothing when it is alone.
def link.told(link: Link) -> Link & Told:
  match link:
    case Alone{}:
      (Alone{}, Told{[], Hour.Unheard{}, Net.Sights{[], []}})
    case Online{socket, buffer, known, +peers}:
      (Online{socket, buffer, known, peers}, told_of(peers))

def ask_line(ask: Maybe<&2, U32>) -> String:
  match ask:
    case Some{drop}:
      Net.pickup_line(drop)
    case None{}:
      ""

# The lines a tick left to say, kept for the next exchange: the hit, and the pickup when the
# rest since the last one is over.
def peers.said(peers: Peers, strike: String, +pickup: String) -> Peers:
  Peers{told, Outbox{posed, wait, say, +pause}} = peers
  +due = Bool.and(U32.is_eq(pause, 0), Bool.not(String.is_empty(pickup)))
  Peers{told, Outbox{posed, wait,
    String.append(String.append(say, strike), Bool.pick(String, due, pickup, "")),
    Bool.pick(U32, due, pickup_rest(), U32.sub(pause, U32.min(pause, 1)))}}

def link.said(link: Link, strike: String, pickup: String) -> Link:
  match link:
    case Alone{}:
      Alone{}
    case Online{socket, buffer, known, peers}:
      Online{socket, buffer, known, peers.said(peers, strike, pickup)}

# The hit a tick made: the dig key went down with a mob under the crosshair.
def strike_line(struck: Bool, +mob: U32, +damage: U32) -> String:
  match struck:
    case True{}:
      Net.strike_line(mob, damage)
    case False{}:
      ""

# The client with the request its tick left in the store marked as on its way.
def asked(+client: Play.Client) -> Play.Client:
  +bag = Play.bag_of(client)
  Play.with_bag(client, Bag.with_store(bag, Stores.sent(Bag.store_of(bag))))

def session.acted(link: Link, next: Maybe<Play.Client>, +quarry: Entities.Aimed, +before: U32,
  ask: Maybe<&2, U32>) -> IO(Maybe<Session>):
  match next:
    case None{}:
      link.closed(link)
    case Some{+client}:
      IO.pure(Maybe<Session>, Some{Session{asked(client),
        link.said(link,
          String.append(
            strike_line(Bool.and(Entities.aim_found(quarry), Frame.wants_dig(before, Play.keys_of(client))),
              Entities.aim_id(quarry), Inventory.melee_damage(Bag.held_item(Play.bag_of(client)))),
            Stores.line_of(Bag.store_of(Play.bag_of(client)))),
          ask_line(ask))}})

def session.acting.among(events: List<&1, Event>, +client: Play.Client, link: Link,
  +things: List<&2, Net.Thing>) -> IO(Maybe<Session>):
  # With the inventory screen open a click is the screen's, and hits nothing.
  +quarry : Entities.Aimed = Bool.pick(Entities.Aimed, Bag.is_open(Play.bag_of(client)),
    Entities.aim_none(MultiplayerMobs.melee_range()), quarry(things, place_of(Play.player_of(client))))
  IO.bind(Maybe<Play.Client>, Maybe<Session>, Play.tick.room(events, client, Entities.aim_found(quarry), True{}),
    next => session.acted(link, next, quarry, Play.keys_of(client),
      wanted(things, place_of(Play.player_of(client)), Play.bag_of(client))))

def session.acting.at(events: List<&1, Event>, +client: Play.Client,
  seen: Link & Told) -> IO(Maybe<Session>):
  (link, told) = seen
  session.acting.among(events, client, link, told_things(told))

# The client's tick in a room: what is under the crosshair and on the ground beside the
# player is worked out first, from the pose the tick starts with, and what the tick did
# about them is left for the next exchange to say.
def session.acting(events: List<&1, Event>, session: Session) -> IO(Maybe<Session>):
  Session{client, link} = session
  session.acting.at(events, client, link.told(link))

def session.tick.at(link: Link, events: List<&1, Event>, +client: Play.Client) -> IO(Maybe<Session>):
  match link:
    case Alone{}:
      session.ticked(events, Session{client, Alone{}})
    case Online{socket, buffer, known, peers}:
      do IO<Maybe<Session>>:
        session : Session <- synced(socket, buffer, known, peers, client)
        now : Nat <- IO.now()
        session.acting(events, session.timed(session, now))

# The session's tick: the room first, then the client's own.
def session.tick(events: List<&1, Event>, session: Session) -> IO(Maybe<Session>):
  Session{client, link} = session
  session.tick.at(link, events, client)

def session.viewed(drawn: Play.Client & Image, link: Link) -> Session & Image:
  (client, image) = drawn
  (Session{client, link}, image)

def session.told.at(client: Play.Client, seen: Link & Told) -> Session & Told:
  (link, told) = seen
  (Session{client, link}, told)

def session.told(session: Session) -> Session & Told:
  Session{client, link} = session
  session.told.at(client, link.told(link))

def session.view.told(client: Play.Client, link: Link, told: Told) -> Session & Image:
  Told{others, hour, sights} = told
  session.viewed(Play.view_among(client, others, hour, shown_of(sights)), link)

def session.view.at(client: Play.Client, seen: Link & Told) -> Session & Image:
  (link, told) = seen
  session.view.told(client, link, told)

# The session's frame: the client's, with the room's other players and what the room
# simulates standing in it, at the room's hour.
def session.view(session: Session) -> Session & Image:
  Session{client, link} = session
  session.view.at(client, link.told(link))

# --- joining ---------------------------------------------------------------------

# `--join=host:port` among the arguments, as its `host:port`.
def join_value(parts: List<&2, String>) -> Maybe<&2, String>:
  match parts:
    case flag <> value <> Nil{}:
      Bool.pick(Maybe<&2, String>, String.eq(flag, "--join"), Some{value}, None{})
    case _:
      None{}

def join_first(found: Maybe<&2, String>, later: Maybe<&2, String>) -> Maybe<&2, String>:
  match found:
    case Some{value}:
      Some{value}
    case None{}:
      later

def join_arg(args: List<&1, String>) -> Maybe<&2, String>:
  match args:
    case Nil{}:
      None{}
    case arg <> rest:
      join_first(join_value(String.split(arg, Chr{61})), join_arg(rest))

def greeted(sent: Socket & Result<&1, &1, U32 & String, Unit>, client: Play.Client) -> IO(Session):
  (socket, result) = sent
  match result:
    case Fail{error}:
      left("the hello could not be sent", socket, client)
    case Done{unit}:
      IO.pure(Session, Session{client, Online{socket, "", [], Peers{Told{[], Hour.Unheard{}, Net.Sights{[], []}}, Outbox{"", 0, "", 0}}}})

def connected(result: Result<&1, &1, U32 & String, Socket>, client: Play.Client) -> IO(Session):
  match result:
    case Fail{error}:
      do IO<Session>:
        said : Unit <- IO.print("native-client: could not join the room; playing alone")
        return Session{client, Alone{}}
    case Done{socket}:
      do IO<Session>:
        said : Unit <- IO.print("native-client: joined the room")
        sent : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send(socket, Net.hello("Native"))
        greeted(sent, client)

def join.at(address: Maybe<&2, Net.Address>, client: Play.Client) -> IO(Session):
  match address:
    case None{}:
      do IO<Session>:
        said : Unit <- IO.print("native-client: --join wants host:port; playing alone")
        return Session{client, Alone{}}
    case Some{Net.Address{host, port}}:
      do IO<Session>:
        result : Result<&1, &1, U32 & String, Socket> <- TCP.connect(host, port)
        connected(result, client)

# A client's chests and furnaces are its own world's. In a room they are the room's, told
# on joining, so the ones a stash brought along are left behind.
def unstored(+client: Play.Client) -> Play.Client:
  Play.with_bag(client, Bag.with_store(Play.bag_of(client), Bag.stores()))

# A room's client: the room's world, which is the generated one until the room says
# otherwise, and its own save file.
def room_client(+size: Size.Size) -> IO(Play.Client):
  region = Play.collision_region(WorldState.empty(), Play.den_start())
  IO.bind(Play.Client, Play.Client, Play.start.region(region, WorldState.empty(), room_path(), size),
    client => IO.pure(Play.Client, unstored(client)))

def session.started(target: Maybe<&2, String>, +size: Size.Size) -> IO(Session):
  match target:
    case None{}:
      do IO<Session>:
        client : Play.Client <- Play.start(size)
        return Session{client, Alone{}}
    case Some{text}:
      do IO<Session>:
        client : Play.Client <- room_client(size)
        join.at(Net.address(text), client)

# The client alone from its save, or in a room when `--join=host:port` was passed.
def session.start(+size: Size.Size) -> IO(Session):
  do IO<Session>:
    args : List<&1, String> <- IO.args()
    session.started(join_arg(args), size)

# The same app over a session, which is what the window runs: the client's own view and
# tick, with the room's exchange in front of the tick.
def session_app() -> App<Session>:
  App{session.view, session.tick}
