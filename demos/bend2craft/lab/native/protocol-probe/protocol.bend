import Base
import ../../../world/world_state.bend as WorldState
import ../../../world/multiplayer.bend as Multiplayer
import ../../../world/chests.bend as Chests
import ../../../world/furnaces.bend as Furnaces

# A native protocol v1 frame is exactly 28 bytes: "B2", version, tag, then six
# big-endian U32 words. Fixed-width frames make TCP buffering unambiguous; this
# module decodes one complete frame and does not implement socket reassembly.
# Tags 1..5 are Join, Welcome, Edit, Ack, Reject. Join/Welcome reserve unused
# words as zero. Edit carries an expected room sequence; replies carry the
# resulting sequence. Ack.block echoes an accepted edit; Reject.block is the
# authoritative room value at the requested cell, or zero when it is out of
# world. A stale sequence is rejected without changing the room;
# Multiplayer.submit owns all world-edit validation.
# Edit coordinates use WorldState's stored, non-negative coordinate encoding.
# Client ids are correlation labels, not authentication credentials. This
# protocol has no authentication or confidentiality.
type Frame is Data:
  Join{client: U32}
  Welcome{client: U32, seq: U32}
  Edit{client: U32, expected: U32, x: U32, y: U32, z: U32, block: U32}
  Ack{client: U32, seq: U32, x: U32, y: U32, z: U32, block: U32}
  Reject{client: U32, seq: U32, x: U32, y: U32, z: U32, block: U32}

type Server is Data:
  Server{room: Multiplayer.Room, response: Frame}

def server_room(server: Server) -> Multiplayer.Room:
  Server{+room, response} = server
  room

def server_response(server: Server) -> Frame:
  Server{room, +response} = server
  response

def word_bytes(+word: U32) -> List<&2, U32>:
  [U32.div(word, 16777216), U32.mod(U32.div(word, 65536), 256),
    U32.mod(U32.div(word, 256), 256), U32.mod(word, 256)]

def encode_words(words: List<&2, U32>) -> List<&2, U32>:
  match words:
    case Nil{}:
      Nil{}
    case Con{+head, tail}:
      List.append(&2, U32, word_bytes(head), encode_words(tail))

def frame_bytes(+tag: U32, words: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, [66, 50, 1, tag], encode_words(words))

def encode(frame: Frame) -> List<&2, U32>:
  match frame:
    case Join{client}:
      frame_bytes(1, [client, 0, 0, 0, 0, 0])
    case Welcome{client, seq}:
      frame_bytes(2, [client, seq, 0, 0, 0, 0])
    case Edit{client, expected, x, y, z, block}:
      frame_bytes(3, [client, expected, x, y, z, block])
    case Ack{client, seq, x, y, z, block}:
      frame_bytes(4, [client, seq, x, y, z, block])
    case Reject{client, seq, x, y, z, block}:
      frame_bytes(5, [client, seq, x, y, z, block])

def valid_bytes(bytes: List<&2, U32>, +remaining: Nat) -> Bool:
  match bytes remaining:
    case Nil{} _:
      True{}
    case Con{head, tail} 0n:
      False{}
    case Con{+head, tail} 1n+p:
      U32.is_lt(head, 256) && valid_bytes(tail, p)

def read_words(bytes: List<&2, U32>, +remaining: Nat,
  +acc: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match bytes remaining:
    case Nil{} 0n:
      Some{List.reverse(&2, U32, acc)}
    case _ 0n:
      None{}
    case a <> b <> c <> d <> rest 1n+p:
      +word = (a * 16777216 + b * 65536 + c * 256 + d : U32)
      read_words(rest, p, word <> acc)
    case _ _:
      None{}

def decode.join(words: Maybe<&2, List<&2, U32>>) -> Maybe<&2, Frame>:
  match words:
    case Some{[client, 0, 0, 0, 0, 0]}:
      Some{Join{client}}
    case _:
      None{}

def decode.welcome(words: Maybe<&2, List<&2, U32>>) -> Maybe<&2, Frame>:
  match words:
    case Some{[client, seq, 0, 0, 0, 0]}:
      Some{Welcome{client, seq}}
    case _:
      None{}

def decode.edit(words: Maybe<&2, List<&2, U32>>) -> Maybe<&2, Frame>:
  match words:
    case Some{[client, expected, x, y, z, block]}:
      Some{Edit{client, expected, x, y, z, block}}
    case _:
      None{}

def decode.ack(words: Maybe<&2, List<&2, U32>>) -> Maybe<&2, Frame>:
  match words:
    case Some{[client, seq, x, y, z, block]}:
      Some{Ack{client, seq, x, y, z, block}}
    case _:
      None{}

def decode.reject(words: Maybe<&2, List<&2, U32>>) -> Maybe<&2, Frame>:
  match words:
    case Some{[client, seq, x, y, z, block]}:
      Some{Reject{client, seq, x, y, z, block}}
    case _:
      None{}

def decode.tag(+tag: U32, words: Maybe<&2, List<&2, U32>>) -> Maybe<&2, Frame>:
  match tag:
    case 1:
      decode.join(words)
    case 2:
      decode.welcome(words)
    case 3:
      decode.edit(words)
    case 4:
      decode.ack(words)
    case 5:
      decode.reject(words)
    case _:
      None{}

def decode.header.valid(+tag: U32, rest: List<&2, U32>, valid: Bool) -> Maybe<&2, Frame>:
  match valid:
    case False{}:
      None{}
    case True{}:
      decode.tag(tag, read_words(rest, 6n, Nil{}))

def decode.header(+magic_a: U32, +magic_b: U32, +version: U32, +tag: U32,
  rest: List<&2, U32>) -> Maybe<&2, Frame>:
  decode.header.valid(tag, rest, U32.is_eq(magic_a, 66) && U32.is_eq(magic_b, 50)
    && U32.is_eq(version, 1))

def decode.exact(bytes: List<&2, U32>) -> Maybe<&2, Frame>:
  match bytes:
    case magic_a <> magic_b <> version <> tag <> rest:
      decode.header(magic_a, magic_b, version, tag, rest)
    case _:
      None{}

# Stops after 29 cells, rejecting oversized input without traversing its tail.
def decode.bounded(bytes: List<&2, U32>, bounded: Bool) -> Maybe<&2, Frame>:
  match bounded:
    case True{}:
      decode.exact(bytes)
    case False{}:
      None{}

def decode(+bytes: List<&2, U32>) -> Maybe<&2, Frame>:
  decode.bounded(bytes, valid_bytes(bytes, 28n))

def authoritative_block.from_revert(reverted: List<&2, WorldState.Edit>) -> U32:
  match reverted:
    case Nil{}:
      0
    case Con{+head, tail}:
      WorldState.edit_value(head)

def authoritative_block(edits: List<&2, WorldState.Edit>, +seed: Nat,
  +x: U32, +y: U32, +z: U32) -> U32:
  +cell = WorldState.make_edit(U32.to_nat(x), U32.to_nat(y), U32.to_nat(z), 0)
  authoritative_block.from_revert(Multiplayer.revert([cell], edits, seed))

def handle.edit.reject.state(+seq: U32, +edits: List<&2, WorldState.Edit>, chests: Chests.World,
  furnaces: Furnaces.World, +seed: Nat, +client: U32, +x: U32, +y: U32, +z: U32) -> Server:
  +block = authoritative_block(edits, seed, x, y, z)
  Server{Multiplayer.restore(seq, edits, chests, furnaces), Reject{client, seq, x, y, z, block}}

def handle.edit.reject(room: Multiplayer.Room, +seed: Nat, +client: U32,
  +x: U32, +y: U32, +z: U32) -> Server:
  match room:
    case Multiplayer.Room{+seq, +edits, +chests, +furnaces}:
      handle.edit.reject.state(seq, edits, chests, furnaces, seed, client, x, y, z)

def handle.edit.ack(room: Multiplayer.Room, +client: U32, +x: U32, +y: U32,
  +z: U32, +block: U32) -> Server:
  match room:
    case Multiplayer.Room{+seq, +edits, +chests, +furnaces}:
      Server{Multiplayer.restore(seq, edits, chests, furnaces), Ack{client, seq, x, y, z, block}}

def handle.edit.result(room: Multiplayer.Room, accepted: List<&2, WorldState.Edit>,
  +seed: Nat, +client: U32, +x: U32, +y: U32, +z: U32, +block: U32) -> Server:
  match accepted:
    case Nil{}:
      handle.edit.reject(room, seed, client, x, y, z)
    case Con{head, tail}:
      handle.edit.ack(room, client, x, y, z, block)

def handle.edit.submitted(submission: Multiplayer.Submission, +seed: Nat, +client: U32,
  +x: U32, +y: U32, +z: U32, +block: U32) -> Server:
  Multiplayer.Submission{+room, +accepted, rejected, changes} = submission
  handle.edit.result(room, accepted, seed, client, x, y, z, block)

def handle.edit.checked(+seq: U32, edits: List<&2, WorldState.Edit>, chests: Chests.World,
  furnaces: Furnaces.World, +seed: Nat, +client: U32, +expected: U32, +x: U32, +y: U32,
  +z: U32, +block: U32, current: Bool) -> Server:
  match current:
    case False{}:
      handle.edit.reject.state(seq, edits, chests, furnaces, seed, client, x, y, z)
    case True{}:
      +edit = WorldState.make_edit(U32.to_nat(x), U32.to_nat(y), U32.to_nat(z), block)
      handle.edit.submitted(Multiplayer.submit(
        Multiplayer.restore(seq, edits, chests, furnaces), [edit]), seed, client, x, y, z, block)

def handle.edit.current(room: Multiplayer.Room, +seed: Nat, +client: U32, +expected: U32,
  +x: U32, +y: U32, +z: U32, +block: U32) -> Server:
  match room:
    case Multiplayer.Room{+seq, +edits, +chests, +furnaces}:
      handle.edit.checked(seq, edits, chests, furnaces, seed, client, expected, x, y, z, block,
        U32.is_eq(expected, seq))

def handle.join(room: Multiplayer.Room, +client: U32) -> Server:
  match room:
    case Multiplayer.Room{+seq, +edits, +chests, +furnaces}:
      Server{Multiplayer.restore(seq, edits, chests, furnaces), Welcome{client, seq}}

def handle(room: Multiplayer.Room, +seed: Nat, frame: Frame) -> Maybe<&2, Server>:
  match frame:
    case Join{+client}:
      Some{handle.join(room, client)}
    case Edit{+client, +expected, +x, +y, +z, +block}:
      Some{handle.edit.current(room, seed, client, expected, x, y, z, block)}
    case _:
      None{}
