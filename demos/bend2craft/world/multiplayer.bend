import Base
import ./world.bend as World
import ./world_state.bend as WorldState
import ./chest.bend as Chest
import ./chests.bend as Chests
import ./furnace.bend as Furnace
import ./furnaces.bend as Furnaces

# Multiplayer authority.
#
# A multiplayer server holds one Room: the ordered edit log of the shared world
# and a sequence number that advances once per submitted batch. Clients submit
# block edits in stored (Bend) coordinates, the same encoding WorldState uses;
# the room accepts the valid edits in arrival order and folds them into its log
# with WorldState.set, so every client that replays the accepted batches in
# sequence order converges on the same world as the room.
#
# Player poses are validated here as well: the server relays only poses that
# are finite and inside the world's vertical band, with the pitch clamped.
#
# Chests belong to the room too, keyed by the same stored coordinates as the
# edits. An accepted edit that places a chest block (26) opens an empty chest
# there, and one that replaces it removes the chest; an edit that would replace
# a chest still holding items is refused, so contents are never lost or
# duplicated. Deposits and withdrawals are room transitions as well.
#
# Furnaces work the same way: placing a furnace block (11) opens an empty
# furnace, replacing it removes it (with its contents, as in single player),
# loading and emptying are room transitions, and the server ticks every
# furnace with Furnaces.tick_world.

type Change is Data:
  ChestPlaced{x: Nat, y: Nat, z: Nat}
  ChestBroken{x: Nat, y: Nat, z: Nat}
  FurnacePlaced{x: Nat, y: Nat, z: Nat}
  FurnaceBroken{x: Nat, y: Nat, z: Nat}

type Room is Data:
  Room{seq: U32, edits: List<&2, WorldState.Edit>, chests: Chests.World, furnaces: Furnaces.World}

type Split is Data:
  Split{
    edits: List<&2, WorldState.Edit>, chests: Chests.World, furnaces: Furnaces.World,
    accepted: List<&2, WorldState.Edit>, rejected: List<&2, WorldState.Edit>,
    changes: List<&2, Change>
  }

type Step is Data:
  Step{chests: Chests.World, changes: List<&2, Change>}

type FurnaceStep is Data:
  FurnaceStep{furnaces: Furnaces.World, changes: List<&2, Change>}

type Submission is Data:
  Submission{
    room: Room, accepted: List<&2, WorldState.Edit>, rejected: List<&2, WorldState.Edit>,
    changes: List<&2, Change>
  }

type Outcome is Data:
  Outcome{room: Room, ok: Bool, item: U32, amount: U32, durability: U32}

# The highest block ID a client may place (27: crafting table). IDs are listed
# in world.bend and web/inventory.js.
def max_block() -> U32:
  27

# The largest batch a client may submit in one message.
def max_batch() -> Nat:
  4096n

def empty() -> Room:
  Room{0, Nil{}, Chests.empty(), Furnaces.empty()}

def restore(
  seq: U32, edits: List<&2, WorldState.Edit>, chests: Chests.World, furnaces: Furnaces.World
) -> Room:
  Room{seq, edits, chests, furnaces}

def room_seq(room: Room) -> U32:
  Room{+seq, edits, chests, furnaces} = room
  seq

def room_edits(room: Room) -> List<&2, WorldState.Edit>:
  Room{seq, +edits, chests, furnaces} = room
  edits

def room_chests(room: Room) -> Chests.World:
  Room{seq, edits, +chests, furnaces} = room
  chests

def room_furnaces(room: Room) -> Furnaces.World:
  Room{seq, edits, chests, +furnaces} = room
  furnaces

def submission_room(result: Submission) -> Room:
  Submission{+room, accepted, rejected, changes} = result
  room

def submission_accepted(result: Submission) -> List<&2, WorldState.Edit>:
  Submission{room, +accepted, rejected, changes} = result
  accepted

def submission_rejected(result: Submission) -> List<&2, WorldState.Edit>:
  Submission{room, accepted, +rejected, changes} = result
  rejected

def submission_changes(result: Submission) -> List<&2, Change>:
  Submission{room, accepted, rejected, +changes} = result
  changes

def outcome_room(result: Outcome) -> Room:
  Outcome{+room, ok, item, amount, durability} = result
  room

def outcome_ok(result: Outcome) -> Bool:
  Outcome{room, +ok, item, amount, durability} = result
  ok

def outcome_item(result: Outcome) -> U32:
  Outcome{room, ok, +item, amount, durability} = result
  item

def outcome_amount(result: Outcome) -> U32:
  Outcome{room, ok, item, +amount, durability} = result
  amount

def outcome_durability(result: Outcome) -> U32:
  Outcome{room, ok, item, amount, +durability} = result
  durability

# A stored coordinate is a non-negative world coordinate, or a negative one
# moved to negative_origin() + x. Values at or past negative_origin() never
# come from a signed world coordinate, so they are refused.
def valid_coordinate(+value: Nat) -> Bool:
  Nat.is_lt(value, World.negative_origin())

def valid_position(+x: Nat, +y: Nat, +z: Nat) -> Bool:
  Bool.and(Bool.and(valid_coordinate(x), Nat.is_lt(y, World.max_y())), valid_coordinate(z))

def valid_block(+block: U32) -> Bool:
  U32.is_le(block, max_block())

def valid_edit(edit: WorldState.Edit) -> Bool:
  WorldState.Edit{+x, +y, +z, +block} = edit
  Bool.and(valid_position(x, y, z), valid_block(block))

# Counts up to one past the limit, in a loop, so an oversized batch is refused
# without walking all of it.
def batch_fits(edits: List<&2, WorldState.Edit>, +left: Nat) -> Bool:
  match edits left:
    case Nil{} _:
      True{}
    case Con{head, tail} 0n:
      False{}
    case Con{head, tail} 1n+p:
      batch_fits(tail, p)

def valid_batch_size(+batch: List<&2, WorldState.Edit>) -> Bool:
  batch_fits(batch, max_batch())

def keep_if(+ok: Bool, edit: WorldState.Edit, rest: List<&2, WorldState.Edit>) -> List<&2, WorldState.Edit>:
  match ok:
    case True{}:
      Con{edit, rest}
    case False{}:
      rest

# Chests ----------------------------------------------------------------------

def slots_empty(slots: List<&2, Chest.Slot>) -> Bool:
  match slots:
    case Nil{}:
      True{}
    case Con{+head, tail}:
      Bool.and(U32.is_eq(Chest.slot_count_value(head), 0), slots_empty(tail))

def chest_allows.found(lookup: Chests.Lookup, +block: U32) -> Bool:
  match lookup:
    case Chests.ChestMissing{}:
      True{}
    case Chests.ChestFound{+slots}:
      Bool.or(U32.is_eq(block, World.chest_block()), slots_empty(slots))

# An edit may replace a chest only while the chest is empty.
def chest_allows(+chests: Chests.World, edit: WorldState.Edit) -> Bool:
  WorldState.Edit{+x, +y, +z, +block} = edit
  chest_allows.found(Chests.at(chests, x, y, z), block)

def step.placed(+x: Nat, +y: Nat, +z: Nat, result: Chests.WorldResult) -> Step:
  Chests.WorldResult{+world, +ok} = result
  Step{world, Bool.pick(List<&2, Change>, ok, Con{ChestPlaced{x, y, z}, Nil{}}, Nil{})}

def step.broken(+x: Nat, +y: Nat, +z: Nat, result: Chests.WorldResult) -> Step:
  Chests.WorldResult{+world, +ok} = result
  Step{world, Bool.pick(List<&2, Change>, ok, Con{ChestBroken{x, y, z}, Nil{}}, Nil{})}

def step.block(+placing: Bool, +x: Nat, +y: Nat, +z: Nat, +chests: Chests.World) -> Step:
  match placing:
    case True{}:
      step.placed(x, y, z, Chests.add(chests, x, y, z))
    case False{}:
      step.broken(x, y, z, Chests.remove(chests, x, y, z))

# The chest bookkeeping of one edit: placing a chest block opens a chest there,
# anything else removes the chest the cell held, if any.
def chest_step(+ok: Bool, +edit: WorldState.Edit, +chests: Chests.World) -> Step:
  match ok:
    case True{}:
      WorldState.Edit{+x, +y, +z, +block} = edit
      step.block(U32.is_eq(block, World.chest_block()), x, y, z, chests)
    case False{}:
      Step{chests, Nil{}}

def step_chests(step: Step) -> Chests.World:
  Step{+chests, changes} = step
  chests

def step_changes(step: Step) -> List<&2, Change>:
  Step{chests, +changes} = step
  changes

def append_changes(first: List<&2, Change>, rest: List<&2, Change>) -> List<&2, Change>:
  match first:
    case Nil{}:
      rest
    case Con{head, tail}:
      Con{head, append_changes(tail, rest)}

# Furnaces ---------------------------------------------------------------------

def furnace_step.placed(+x: Nat, +y: Nat, +z: Nat, result: Furnaces.WorldResult) -> FurnaceStep:
  Furnaces.WorldResult{+world, +ok} = result
  FurnaceStep{world, Bool.pick(List<&2, Change>, ok, Con{FurnacePlaced{x, y, z}, Nil{}}, Nil{})}

def furnace_step.broken(+x: Nat, +y: Nat, +z: Nat, result: Furnaces.WorldResult) -> FurnaceStep:
  Furnaces.WorldResult{+world, +ok} = result
  FurnaceStep{world, Bool.pick(List<&2, Change>, ok, Con{FurnaceBroken{x, y, z}, Nil{}}, Nil{})}

def furnace_step.block(+placing: Bool, +x: Nat, +y: Nat, +z: Nat, +furnaces: Furnaces.World) -> FurnaceStep:
  match placing:
    case True{}:
      furnace_step.placed(x, y, z, Furnaces.add(furnaces, x, y, z))
    case False{}:
      furnace_step.broken(x, y, z, Furnaces.remove(furnaces, x, y, z))

# The furnace bookkeeping of one edit, the counterpart of chest_step.
def furnace_step(+ok: Bool, +edit: WorldState.Edit, +furnaces: Furnaces.World) -> FurnaceStep:
  match ok:
    case True{}:
      WorldState.Edit{+x, +y, +z, +block} = edit
      furnace_step.block(U32.is_eq(block, World.furnace_block()), x, y, z, furnaces)
    case False{}:
      FurnaceStep{furnaces, Nil{}}

def furnace_step_furnaces(step: FurnaceStep) -> Furnaces.World:
  FurnaceStep{+furnaces, changes} = step
  furnaces

def furnace_step_changes(step: FurnaceStep) -> List<&2, Change>:
  FurnaceStep{furnaces, +changes} = step
  changes

# Edit batches -----------------------------------------------------------------

def split.finish(
  +ok: Bool, +head: WorldState.Edit, changes: List<&2, Change>, result: Split
) -> Split:
  Split{+edits, +chests, +furnaces, +accepted, +rejected, +later} = result
  Split{
    edits, chests, furnaces,
    keep_if(ok, head, accepted), keep_if(Bool.not(ok), head, rejected),
    append_changes(changes, later)
  }

# Folds a batch into an edit log and the chests in order. Accepted and rejected
# keep the batch's order, so a later edit of the same cell still wins
# downstream.
def split(
  batch: List<&2, WorldState.Edit>, edits: List<&2, WorldState.Edit>, +chests: Chests.World,
  +furnaces: Furnaces.World
) -> Split:
  match batch:
    case Nil{}:
      Split{edits, chests, furnaces, Nil{}, Nil{}, Nil{}}
    case Con{+head, tail}:
      +ok = Bool.and(valid_edit(head), chest_allows(chests, head))
      +step = chest_step(ok, head, chests)
      +fstep = furnace_step(ok, head, furnaces)
      +changes = append_changes(step_changes(step), furnace_step_changes(fstep))
      split.finish(ok, head, changes, split(tail, edits, step_chests(step), furnace_step_furnaces(fstep)))

# The accepted edits are folded into the log in one pass (WorldState.set_many);
# validity never depends on the log, only on the edit and the chests.
def submit.wrap(+seq: U32, result: Split) -> Submission:
  Split{+edits, +chests, +furnaces, +accepted, +rejected, +changes} = result
  Submission{Room{(seq + 1 : U32), WorldState.set_many(edits, accepted), chests, furnaces}, accepted, rejected, changes}

def submit.checked(+fits: Bool, +room: Room, +batch: List<&2, WorldState.Edit>) -> Submission:
  match fits:
    case True{}:
      Room{+seq, +log, +chests, +furnaces} = room
      submit.wrap(seq, split(batch, log, chests, furnaces))
    case False{}:
      Submission{room, Nil{}, batch, Nil{}}

# Submits one client batch. An oversized batch is refused whole and leaves the
# room untouched; otherwise every valid edit is applied in order.
def submit(+room: Room, +batch: List<&2, WorldState.Edit>) -> Submission:
  submit.checked(valid_batch_size(batch), room, batch)

# Chest transitions ------------------------------------------------------------

def refused(room: Room) -> Outcome:
  Outcome{room, False{}, 0, 0, 0}

# One slot's worth: a real item, one to a full stack.
def valid_stack(+item: U32, +count: U32) -> Bool:
  Bool.and(U32.is_ne(item, 0), Bool.and(U32.is_ne(count, 0), U32.is_le(count, Chest.max_stack())))

def deposit.apply(
  +valid: Bool, +seq: U32, +edits: List<&2, WorldState.Edit>, +chests: Chests.World, +furnaces: Furnaces.World, +x: Nat, +y: Nat, +z: Nat,
  +item: U32, +count: U32, +durability: U32, result: Chest.DepositResult
) -> Outcome:
  Chest.DepositResult{+slots, +fits} = result
  +ok = Bool.and(valid, fits)
  Outcome{
    Room{seq, edits, Bool.pick(Chests.World, ok, Chests.set(chests, x, y, z, slots), chests), furnaces},
    ok, item, Bool.pick(U32, ok, count, 0), durability
  }

def deposit.found(
  lookup: Chests.Lookup, +valid: Bool, +seq: U32, +edits: List<&2, WorldState.Edit>, +chests: Chests.World,
  +furnaces: Furnaces.World,
  +x: Nat, +y: Nat, +z: Nat, +item: U32, +count: U32, +durability: U32
) -> Outcome:
  match lookup:
    case Chests.ChestMissing{}:
      refused(Room{seq, edits, chests, furnaces})
    case Chests.ChestFound{+slots}:
      +stored = Bool.pick(List<&2, Chest.Slot>, valid, slots, Nil{})
      deposit.apply(valid, seq, edits, chests, furnaces, x, y, z, item, count, durability, Chest.deposit(stored, item, count, durability))

# Puts `count` of `item` into the chest at a stored position. Refused when
# there is no chest there, the stack is not valid, or it does not fit.
def deposit(
  +room: Room, +x: Nat, +y: Nat, +z: Nat, +item: U32, +count: U32, +durability: U32
) -> Outcome:
  Room{+seq, +edits, +chests, +furnaces} = room
  deposit.found(Chests.at(chests, x, y, z), valid_stack(item, count), seq, edits, chests, furnaces, x, y, z, item, count, durability)

def withdraw.apply(
  +seq: U32, +edits: List<&2, WorldState.Edit>, +chests: Chests.World, +furnaces: Furnaces.World, +x: Nat, +y: Nat, +z: Nat,
  result: Chest.WithdrawResult
) -> Outcome:
  Chest.WithdrawResult{+slots, +item, +amount, +durability, +ok} = result
  Outcome{
    Room{seq, edits, Bool.pick(Chests.World, ok, Chests.set(chests, x, y, z, slots), chests), furnaces},
    ok, item, amount, durability
  }

def withdraw.found(
  lookup: Chests.Lookup, +seq: U32, +edits: List<&2, WorldState.Edit>, +chests: Chests.World,
  +furnaces: Furnaces.World,
  +x: Nat, +y: Nat, +z: Nat, +index: Nat, +amount: U32
) -> Outcome:
  match lookup:
    case Chests.ChestMissing{}:
      refused(Room{seq, edits, chests, furnaces})
    case Chests.ChestFound{+slots}:
      withdraw.apply(seq, edits, chests, furnaces, x, y, z, Chest.withdraw(slots, index, amount))

# Takes up to `amount` from one slot of the chest at a stored position.
def withdraw(+room: Room, +x: Nat, +y: Nat, +z: Nat, +index: Nat, +amount: U32) -> Outcome:
  Room{+seq, +edits, +chests, +furnaces} = room
  withdraw.found(Chests.at(chests, x, y, z), seq, edits, chests, furnaces, x, y, z, index, amount)

# The slots of the chest at a stored position (an empty list when none).
def chest_slots(+room: Room, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Chest.Slot>:
  Room{seq, edits, +chests, furnaces} = room
  Chests.lookup_slots(Chests.at(chests, x, y, z))

def has_chest.found(lookup: Chests.Lookup) -> Bool:
  match lookup:
    case Chests.ChestMissing{}:
      False{}
    case Chests.ChestFound{slots}:
      True{}

def has_chest(+room: Room, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Room{seq, edits, +chests, furnaces} = room
  has_chest.found(Chests.at(chests, x, y, z))

# Furnace transitions ----------------------------------------------------------

def furnace_result(
  +seq: U32, +edits: List<&2, WorldState.Edit>, +chests: Chests.World, +furnaces: Furnaces.World,
  +x: Nat, +y: Nat, +z: Nat, +item: U32, result: Furnace.FurnaceResult
) -> Outcome:
  Furnace.FurnaceResult{+furnace, +ok} = result
  Outcome{
    Room{seq, edits, chests, Bool.pick(Furnaces.World, ok, Furnaces.set(furnaces, x, y, z, furnace), furnaces)},
    ok, item, Bool.pick(U32, ok, 1, 0), 0
  }

def furnace_transfer(
  +seq: U32, +edits: List<&2, WorldState.Edit>, +chests: Chests.World, +furnaces: Furnaces.World,
  +x: Nat, +y: Nat, +z: Nat, result: Furnace.TransferResult
) -> Outcome:
  Furnace.TransferResult{+furnace, +item, +amount, +ok} = result
  Outcome{
    Room{seq, edits, chests, Bool.pick(Furnaces.World, ok, Furnaces.set(furnaces, x, y, z, furnace), furnaces)},
    ok, item, amount, 0
  }

# 0: load one input item, 1: load one fuel item, 2: take the output.
def furnace_op.found(
  lookup: Furnaces.Lookup, +op: U32, +seq: U32, +edits: List<&2, WorldState.Edit>, +chests: Chests.World,
  +furnaces: Furnaces.World, +x: Nat, +y: Nat, +z: Nat, +item: U32
) -> Outcome:
  match lookup:
    case Furnaces.FurnaceMissing{}:
      refused(Room{seq, edits, chests, furnaces})
    case Furnaces.FurnaceFound{+furnace}:
      Bool.pick(Outcome, U32.is_eq(op, 2),
        furnace_transfer(seq, edits, chests, furnaces, x, y, z, Furnace.take_output(furnace)),
        furnace_result(seq, edits, chests, furnaces, x, y, z, item,
          Bool.pick(Furnace.FurnaceResult, U32.is_eq(op, 0),
            Furnace.load_input(furnace, item, 1n),
            Furnace.load_fuel(furnace, item, 1n))))

# One furnace transition at a stored position; refused when there is no
# furnace there or the furnace refuses it.
def furnace_op(+room: Room, +op: U32, +x: Nat, +y: Nat, +z: Nat, +item: U32) -> Outcome:
  Room{+seq, +edits, +chests, +furnaces} = room
  furnace_op.found(Furnaces.at(furnaces, x, y, z), op, seq, edits, chests, furnaces, x, y, z, item)

# Advances every furnace one smelting step.
def tick(+room: Room) -> Room:
  Room{+seq, +edits, +chests, +furnaces} = room
  Room{seq, edits, chests, Furnaces.tick_world(furnaces)}

def furnace_at(+room: Room, +x: Nat, +y: Nat, +z: Nat) -> Furnaces.Lookup:
  Room{seq, edits, chests, +furnaces} = room
  Furnaces.at(furnaces, x, y, z)

def has_furnace.found(lookup: Furnaces.Lookup) -> Bool:
  match lookup:
    case Furnaces.FurnaceMissing{}:
      False{}
    case Furnaces.FurnaceFound{furnace}:
      True{}

def has_furnace(+room: Room, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  has_furnace.found(furnace_at(room, x, y, z))

def furnace_state.found(lookup: Furnaces.Lookup) -> Furnace.Furnace:
  match lookup:
    case Furnaces.FurnaceMissing{}:
      Furnace.empty()
    case Furnaces.FurnaceFound{+furnace}:
      furnace

# The furnace at a stored position (an empty furnace when there is none).
def furnace_state(+room: Room, +x: Nat, +y: Nat, +z: Nat) -> Furnace.Furnace:
  furnace_state.found(furnace_at(room, x, y, z))

def revert.pick(
  +inside: Bool, +x: Nat, +y: Nat, +z: Nat, +edits: List<&2, WorldState.Edit>, +seed: Nat,
  rest: List<&2, WorldState.Edit>
) -> List<&2, WorldState.Edit>:
  match inside:
    case True{}:
      Con{WorldState.make_edit(x, y, z, WorldState.block(edits, seed, x, y, z)), rest}
    case False{}:
      rest

# The authoritative value of every in-world cell a rejected batch named, so the
# submitting client can undo its local prediction.
def revert(
  rejected: List<&2, WorldState.Edit>, +edits: List<&2, WorldState.Edit>, +seed: Nat
) -> List<&2, WorldState.Edit>:
  match rejected:
    case Nil{}:
      Nil{}
    case Con{+head, tail}:
      WorldState.Edit{+x, +y, +z, block} = head
      +rest = revert(tail, edits, seed)
      revert.pick(valid_position(x, y, z), x, y, z, edits, seed, rest)

# Replays accepted batches on a client: the room already validated them, so
# they fold into the local edit log in order.
def merge(+batch: List<&2, WorldState.Edit>, edits: List<&2, WorldState.Edit>) -> List<&2, WorldState.Edit>:
  WorldState.set_many(edits, batch)

# Player poses ----------------------------------------------------------------

# Horizontal bound on a relayed position: half the negative origin, past which
# the stored-coordinate encoding stops being unambiguous.
def pose_horizontal_limit() -> F32:
  47185920.0

def pose_lowest_y() -> F32:
  F32.neg(64.0)

def pose_highest_y() -> F32:
  256.0

def finite_within(+value: F32, +limit: F32) -> Bool:
  Bool.and(F32.is_lt(value, limit), F32.is_gt(value, F32.neg(limit)))

# NaN fails every comparison and an infinity fails the bound, so both are
# refused along with positions outside the world.
def valid_pose(+x: F32, +y: F32, +z: F32, +yaw: F32, +pitch: F32) -> Bool:
  +horizontal = pose_horizontal_limit()
  Bool.and(
    Bool.and(finite_within(x, horizontal), finite_within(z, horizontal)),
    Bool.and(
      Bool.and(F32.is_ge(y, pose_lowest_y()), F32.is_le(y, pose_highest_y())),
      Bool.and(finite_within(yaw, 1000000.0), finite_within(pitch, 1000000.0))
    )
  )

# How far from a player's feet a world interaction (a bucket, a hoe, seeds, a
# harvest) may land, measured to the cell's centre. Generous against network
# lag; the client's own raycast is shorter.
def interaction_reach() -> F32:
  8.0

def within_reach(+px: F32, +py: F32, +pz: F32, +x: F32, +y: F32, +z: F32) -> Bool:
  +dx = F32.sub(x, px)
  +dy = F32.sub(y, py)
  +dz = F32.sub(z, pz)
  F32.is_le(
    F32.add(F32.add(F32.mul(dx, dx), F32.mul(dy, dy)), F32.mul(dz, dz)),
    F32.mul(interaction_reach(), interaction_reach())
  )

def pitch_limit() -> F32:
  1.5533

def clamp_pitch(+pitch: F32) -> F32:
  F32.max(F32.neg(pitch_limit()), F32.min(pitch, pitch_limit()))
