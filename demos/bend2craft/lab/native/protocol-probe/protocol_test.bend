import Base
import ../../../world/world.bend as World
import ../../../world/world_state.bend as WorldState
import ../../../world/multiplayer.bend as Multiplayer
import ./protocol.bend as Protocol

def require(condition: Bool, message: String) -> IO(Unit):
  match condition:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "native-protocol: " ++ message)

def same_bytes(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Con{head_a, tail_a} Con{head_b, tail_b}:
      U32.is_eq(head_a, head_b) && same_bytes(tail_a, tail_b)
    case _ _:
      False{}

def same_frame(a: Protocol.Frame, b: Protocol.Frame) -> Bool:
  match a b:
    case Protocol.Join{client_a} Protocol.Join{client_b}:
      U32.is_eq(client_a, client_b)
    case Protocol.Welcome{client_a, seq_a} Protocol.Welcome{client_b, seq_b}:
      U32.is_eq(client_a, client_b) && U32.is_eq(seq_a, seq_b)
    case Protocol.Edit{client_a, expected_a, x_a, y_a, z_a, block_a}
      Protocol.Edit{client_b, expected_b, x_b, y_b, z_b, block_b}:
      U32.is_eq(client_a, client_b) && U32.is_eq(expected_a, expected_b)
        && U32.is_eq(x_a, x_b) && U32.is_eq(y_a, y_b)
        && U32.is_eq(z_a, z_b) && U32.is_eq(block_a, block_b)
    case Protocol.Ack{client_a, seq_a, x_a, y_a, z_a, block_a}
      Protocol.Ack{client_b, seq_b, x_b, y_b, z_b, block_b}:
      U32.is_eq(client_a, client_b) && U32.is_eq(seq_a, seq_b)
        && U32.is_eq(x_a, x_b) && U32.is_eq(y_a, y_b)
        && U32.is_eq(z_a, z_b) && U32.is_eq(block_a, block_b)
    case Protocol.Reject{client_a, seq_a, x_a, y_a, z_a, block_a}
      Protocol.Reject{client_b, seq_b, x_b, y_b, z_b, block_b}:
      U32.is_eq(client_a, client_b) && U32.is_eq(seq_a, seq_b)
        && U32.is_eq(x_a, x_b) && U32.is_eq(y_a, y_b)
        && U32.is_eq(z_a, z_b) && U32.is_eq(block_a, block_b)
    case _ _:
      False{}

def maybe_is_none(value: Maybe<&2, Protocol.Frame>) -> Bool:
  match value:
    case None{}:
      True{}
    case Some{frame}:
      False{}

def maybe_matches(value: Maybe<&2, Protocol.Frame>, expected: Protocol.Frame) -> Bool:
  match value:
    case None{}:
      False{}
    case Some{frame}:
      same_frame(frame, expected)

def roundtrip(value: Maybe<&2, Protocol.Frame>) -> Maybe<&2, Protocol.Frame>:
  match value:
    case None{}:
      None{}
    case Some{frame}:
      Protocol.decode(Protocol.encode(frame))

def dispatch.decoded(room: Multiplayer.Room, +seed: Nat,
  value: Maybe<&2, Protocol.Frame>) -> Maybe<&2, Protocol.Server>:
  match value:
    case None{}:
      None{}
    case Some{frame}:
      Protocol.handle(room, seed, frame)

def dispatch(room: Multiplayer.Room, +seed: Nat,
  bytes: List<&2, U32>) -> Maybe<&2, Protocol.Server>:
  dispatch.decoded(room, seed, Protocol.decode(bytes))

def response_of(value: Maybe<&2, Protocol.Server>) -> Maybe<&2, Protocol.Frame>:
  match value:
    case None{}:
      None{}
    case Some{server}:
      Some{Protocol.server_response(server)}

def room_of(value: Maybe<&2, Protocol.Server>, fallback: Multiplayer.Room) -> Multiplayer.Room:
  match value:
    case None{}:
      fallback
    case Some{server}:
      Protocol.server_room(server)

def merge_ack(edits: List<&2, WorldState.Edit>, response: Maybe<&2, Protocol.Frame>) -> List<&2, WorldState.Edit>:
  match response:
    case Some{Protocol.Ack{client, seq, x, y, z, block}}:
      Multiplayer.merge([WorldState.make_edit(U32.to_nat(x), U32.to_nat(y),
        U32.to_nat(z), block)], edits)
    case _:
      edits

def apply_reject(edits: List<&2, WorldState.Edit>, response: Maybe<&2, Protocol.Frame>) -> List<&2, WorldState.Edit>:
  match response:
    case Some{Protocol.Reject{client, seq, x, y, z, block}}:
      Multiplayer.merge([WorldState.make_edit(U32.to_nat(x), U32.to_nat(y),
        U32.to_nat(z), block)], edits)
    case _:
      edits

def codec_checks() -> Bool:
  +join: Protocol.Frame = Protocol.Join{17}
  +welcome: Protocol.Frame = Protocol.Welcome{17, 9}
  +edit: Protocol.Frame = Protocol.Edit{17, 9, 1, 2, 3, 4}
  +ack: Protocol.Frame = Protocol.Ack{17, 10, 1, 2, 3, 4}
  +reject: Protocol.Frame = Protocol.Reject{17, 10, 1, 2, 3, 4}
  +maximum: Protocol.Frame = Protocol.Edit{
    4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295}
  Nat.is_eq(List.length(&2, U32, Protocol.encode(join)), 28n)
    && maybe_matches(Protocol.decode(Protocol.encode(join)), join)
    && maybe_matches(Protocol.decode(Protocol.encode(welcome)), welcome)
    && maybe_matches(Protocol.decode(Protocol.encode(edit)), edit)
    && maybe_matches(Protocol.decode(Protocol.encode(ack)), ack)
    && maybe_matches(Protocol.decode(Protocol.encode(reject)), reject)
    && maybe_matches(Protocol.decode(Protocol.encode(maximum)), maximum)
    && same_bytes(Protocol.encode(edit), [66, 50, 1, 3, 0, 0, 0, 17, 0, 0, 0, 9,
      0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4])
    && maybe_is_none(Protocol.decode(List.append(&2, U32, Protocol.encode(join), [0])))
    && maybe_is_none(Protocol.decode([66, 50, 1, 1, 0, 0, 0, 17]))
    && maybe_is_none(Protocol.decode([66, 50, 2, 1, 0, 0, 0, 17,
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
    && maybe_is_none(Protocol.decode([66, 50, 1, 99, 0, 0, 0, 17,
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
    && maybe_is_none(Protocol.decode([66, 50, 1, 1, 0, 0, 0, 17,
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]))
    && maybe_is_none(Protocol.decode([256, 50, 1, 1, 0, 0, 0, 17,
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))

def two_client_converges() -> Bool:
  +empty = Multiplayer.empty()
  +seed: Nat = World.default_seed()
  +edit_a: Protocol.Frame = Protocol.Edit{101, 0, 4, 10, 5, 2}
  +edit_b: Protocol.Frame = Protocol.Edit{202, 3, 7, 10, 8, 5}
  +join_a = dispatch(empty, seed, Protocol.encode(Protocol.Join{101}))
  +join_b = dispatch(empty, seed, Protocol.encode(Protocol.Join{202}))
  +welcome_a = roundtrip(response_of(join_a))
  +welcome_b = roundtrip(response_of(join_b))
  +room_a = room_of(join_a, empty)
  +step_a = dispatch(room_a, seed, Protocol.encode(edit_a))
  +ack_a = roundtrip(response_of(step_a))
  +room_after_a = room_of(step_a, room_a)
  +client_a_after_a = merge_ack(Nil{}, ack_a)
  +client_b_after_a = merge_ack(Nil{}, ack_a)
  +client_b_prediction = Multiplayer.merge([WorldState.make_edit(4n, 10n, 5n, 5)], client_b_after_a)
  +stale_b = dispatch(room_after_a, seed, Protocol.encode(Protocol.Edit{202, 0, 4, 10, 5, 5}))
  +reject_b = roundtrip(response_of(stale_b))
  +room_after_stale = room_of(stale_b, room_after_a)
  +client_b_after_stale = apply_reject(client_b_prediction, reject_b)
  +client_b_invalid_prediction = Multiplayer.merge([WorldState.make_edit(4n, 10n, 5n, 99)], client_b_after_stale)
  +invalid_b = dispatch(room_after_stale, seed, Protocol.encode(Protocol.Edit{202, 1, 4, 10, 5, 99}))
  +reject_invalid = roundtrip(response_of(invalid_b))
  +room_after_invalid = room_of(invalid_b, room_after_stale)
  +client_b_after_invalid = apply_reject(client_b_invalid_prediction, reject_invalid)
  +outside = dispatch(room_after_invalid, seed,
    Protocol.encode(Protocol.Edit{202, 2, 4294967295, 10, 5, 7}))
  +reject_outside = roundtrip(response_of(outside))
  +room_after_outside = room_of(outside, room_after_invalid)
  +step_b = dispatch(room_after_outside, seed, Protocol.encode(edit_b))
  +ack_b = roundtrip(response_of(step_b))
  +room_final = room_of(step_b, room_after_outside)
  +client_a_final = merge_ack(client_a_after_a, ack_b)
  +client_b_final = merge_ack(client_b_after_invalid, ack_b)
  maybe_matches(welcome_a, Protocol.Welcome{101, 0})
    && maybe_matches(welcome_b, Protocol.Welcome{202, 0})
    && maybe_matches(ack_a, Protocol.Ack{101, 1, 4, 10, 5, 2})
    && maybe_matches(reject_b, Protocol.Reject{202, 1, 4, 10, 5, 2})
    && maybe_matches(reject_invalid, Protocol.Reject{202, 2, 4, 10, 5, 2})
    && maybe_matches(reject_outside, Protocol.Reject{202, 3, 4294967295, 10, 5, 0})
    && maybe_matches(ack_b, Protocol.Ack{202, 4, 7, 10, 8, 5})
    && U32.is_eq(WorldState.block(client_b_prediction, World.default_seed(), 4n, 10n, 5n), 5)
    && U32.is_eq(WorldState.block(client_b_after_stale, World.default_seed(), 4n, 10n, 5n), 2)
    && U32.is_eq(WorldState.block(client_b_invalid_prediction, World.default_seed(), 4n, 10n, 5n), 99)
    && U32.is_eq(WorldState.block(client_b_after_invalid, World.default_seed(), 4n, 10n, 5n), 2)
    && U32.is_eq(Multiplayer.room_seq(room_after_stale), 1)
    && U32.is_eq(Multiplayer.room_seq(room_after_invalid), 2)
    && U32.is_eq(Multiplayer.room_seq(room_after_outside), 3)
    && U32.is_eq(Multiplayer.room_seq(room_final), 4)
    && U32.is_eq(WorldState.block(Multiplayer.room_edits(room_after_stale), World.default_seed(), 4n, 10n, 5n), 2)
    && U32.is_eq(WorldState.block(Multiplayer.room_edits(room_after_invalid), World.default_seed(), 4n, 10n, 5n), 2)
    && U32.is_eq(WorldState.block(Multiplayer.room_edits(room_after_outside), World.default_seed(), 4n, 10n, 5n), 2)
    && U32.is_eq(WorldState.block(client_a_final, World.default_seed(), 4n, 10n, 5n), 2)
    && U32.is_eq(WorldState.block(client_b_final, World.default_seed(), 4n, 10n, 5n), 2)
    && U32.is_eq(WorldState.block(client_a_final, World.default_seed(), 7n, 10n, 8n), 5)
    && U32.is_eq(WorldState.block(client_b_final, World.default_seed(), 7n, 10n, 8n), 5)
    && U32.is_eq(WorldState.block(Multiplayer.room_edits(room_final), World.default_seed(), 4n, 10n, 5n), 2)
    && U32.is_eq(WorldState.block(Multiplayer.room_edits(room_final), World.default_seed(), 7n, 10n, 8n), 5)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- require(codec_checks(), "bounded versioned frame codec contract failed")
    Unit <- require(two_client_converges(), "two-client sequence or world convergence failed")
    IO.print("native-protocol: codec and two-client assertions passed")

#|native-protocol: codec and two-client assertions passed
