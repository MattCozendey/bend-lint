import Base

type Sample is Data:
  Sample{x: Nat, y: Nat, z: Nat, block: U32}

type Flow is Data:
  Flow{x: Nat, y: Nat, z: Nat, level: U32, source: Bool, block: U32}

type State is Data:
  State{flows: List<&2, Flow>}

type Current is Data:
  Current{x: F32, z: F32}

type Edit is Data:
  Edit{x: Nat, y: Nat, z: Nat, block: U32}

def sample(x: Nat, y: Nat, z: Nat, block: U32) -> Sample:
  Sample{x, y, z, block}

def water_block() -> U32:
  7

def lava_block() -> U32:
  21

def cobblestone_block() -> U32:
  22

def obsidian_block() -> U32:
  23

def is_fluid(+block: U32) -> Bool:
  Bool.or(U32.is_eq(block, water_block()), U32.is_eq(block, lava_block()))

def flow(x: Nat, y: Nat, z: Nat, level: U32) -> Flow:
  Flow{x, y, z, level, False{}, water_block()}

def lava_flow(x: Nat, y: Nat, z: Nat, level: U32) -> Flow:
  Flow{x, y, z, level, False{}, lava_block()}

def sample_matches(sample: Sample, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Sample{+sx, +sy, +sz, block} = sample
  Bool.and(Bool.and(Nat.is_eq(sx, x), Nat.is_eq(sy, y)), Nat.is_eq(sz, z))

def sample_value(sample: Sample) -> U32:
  Sample{sx, sy, sz, +block} = sample
  block

# The first sample of (x, y, z), in one tail-recursive pass that stops there;
# an unsampled cell reads as stone.
def sample_block.go(samples: List<&2, Sample>, stop: Bool, +value: U32, +x: Nat, +y: Nat, +z: Nat) -> U32:
  match samples stop:
    case _ True{}:
      value
    case Nil{} False{}:
      1
    case Con{+head, tail} False{}:
      sample_block.go(tail, sample_matches(head, x, y, z), sample_value(head), x, y, z)

def sample_block(
  samples: List<&2, Sample>, +x: Nat, +y: Nat, +z: Nat
) -> U32:
  sample_block.go(samples, False{}, 1, x, y, z)

def open_cell(samples: List<&2, Sample>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  +block = sample_block(samples, x, y, z)
  Bool.or(U32.is_eq(block, 0), is_fluid(block))

def append_if(
  flows: List<&2, Flow>, +x: Nat, +y: Nat, +z: Nat, +level: U32,
  +block: U32, valid: Bool
) -> List<&2, Flow>:
  match valid:
    case True{}:
      Con{Flow{x, y, z, level, False{}, block}, flows}
    case False{}:
      flows

def can_fall(samples: List<&2, Sample>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Bool.and(Nat.is_gt(y, 0n), open_cell(samples, x, Nat.sub(y, 1n), z))

def spread(source: Flow, +samples: List<&2, Sample>) -> List<&2, Flow>:
  Flow{+x, +y, +z, +level, source, +source_block} = source
  +can_down = can_fall(samples, x, y, z)
  +side_valid = Bool.and(Bool.not(can_down), U32.is_gt(level, 1))
  +side_level = U32.sub(level, 1)
  +down = append_if(Nil{}, x, Nat.sub(y, 1n), z, level, source_block, can_down)
  +south = append_if(down, x, y, Nat.add(z, 1n), side_level, source_block,
    Bool.and(side_valid, open_cell(samples, x, y, Nat.add(z, 1n))))
  +north = append_if(south, x, y, Nat.sub(z, 1n), side_level, source_block,
    Bool.and(side_valid, open_cell(samples, x, y, Nat.sub(z, 1n))))
  +east = append_if(north, Nat.add(x, 1n), y, z, side_level, source_block,
    Bool.and(side_valid, open_cell(samples, Nat.add(x, 1n), y, z)))
  append_if(east, Nat.sub(x, 1n), y, z, side_level, source_block,
    Bool.and(side_valid, open_cell(samples, Nat.sub(x, 1n), y, z)))

def empty() -> State:
  State{Nil{}}

def state_flows(state: State) -> List<&2, Flow>:
  State{flows} = state
  flows

def same_position(flow: Flow, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Flow{+fx, +fy, +fz, level, source, block} = flow
  Bool.and(Bool.and(Nat.is_eq(fx, x), Nat.is_eq(fy, y)), Nat.is_eq(fz, z))

def contains(flows: List<&2, Flow>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match flows:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Bool.or(same_position(head, x, y, z), contains(tail, x, y, z))

def remove_entries(flows: List<&2, Flow>, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Flow>:
  match flows:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      +rest = remove_entries(tail, x, y, z)
      Bool.pick(
        List<&2, Flow>,
        same_position(head, x, y, z),
        rest,
        Con{head, rest}
      )

def append_unique(+flows: List<&2, Flow>, +candidate: Flow) -> List<&2, Flow>:
  Flow{+x, +y, +z, level, source, block} = candidate
  Bool.pick(List<&2, Flow>, contains(flows, x, y, z), flows, Con{candidate, flows})

def append_spread(
  +candidates: List<&2, Flow>, +flows: List<&2, Flow>
) -> List<&2, Flow>:
  match candidates:
    case Nil{}:
      flows
    case Con{+head, +tail}:
      append_spread(tail, append_unique(flows, head))

def append_at_end(+flows: List<&2, Flow>, +candidate: Flow) -> List<&2, Flow>:
  match flows:
    case Nil{}:
      Con{candidate, Nil{}}
    case Con{head, tail}:
      Con{head, append_at_end(tail, candidate)}

def take(+remaining: Nat, +flows: List<&2, Flow>) -> List<&2, Flow>:
  match remaining:
    case 0n:
      Nil{}
    case 1n+p:
      match flows:
        case Nil{}:
          Nil{}
        case Con{+head, +tail}:
          Con{head, take(p, tail)}

def max_flow_cells() -> Nat:
  256n

def limit(+state: State) -> State:
  State{+flows} = state
  State{take(max_flow_cells(), flows)}

def append_edits(
  edits: List<&2, Edit>, +tail: List<&2, Edit>
) -> List<&2, Edit>:
  match edits:
    case Nil{}:
      tail
    case Con{+head, +rest}:
      Con{head, append_edits(rest, tail)}

def removed_edits(
  +before: List<&2, Flow>, +after: List<&2, Flow>
) -> List<&2, Edit>:
  match before:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Flow{+x, +y, +z, level, source, block} = head
      +rest = removed_edits(tail, after)
      Bool.pick(
        List<&2, Edit>,
        contains(after, x, y, z),
        rest,
        Con{Edit{x, y, z, 0}, rest}
      )

def added_edits(
  +after: List<&2, Flow>, +before: List<&2, Flow>
) -> List<&2, Edit>:
  match after:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Flow{+x, +y, +z, level, source, block} = head
      +rest = added_edits(tail, before)
      Bool.pick(
        List<&2, Edit>,
        contains(before, x, y, z),
        rest,
        Con{Edit{x, y, z, block}, rest}
      )

def opposite_block(+block: U32) -> U32:
  Bool.pick(U32, U32.is_eq(block, lava_block()), water_block(), lava_block())

def opposite_near(
  +samples: List<&2, Sample>, +x: Nat, +y: Nat, +z: Nat, +block: U32
) -> Bool:
  +opposite = opposite_block(block)
  Bool.or(
    Bool.or(
      U32.is_eq(sample_block(samples, Nat.sub(x, 1n), y, z), opposite),
      U32.is_eq(sample_block(samples, Nat.add(x, 1n), y, z), opposite)
    ),
    Bool.or(
      U32.is_eq(sample_block(samples, x, y, Nat.sub(z, 1n)), opposite),
      U32.is_eq(sample_block(samples, x, y, Nat.add(z, 1n)), opposite)
    )
  )

def reactive(flow: Flow, +samples: List<&2, Sample>) -> Bool:
  Flow{+x, +y, +z, level, source, +block} = flow
  Bool.and(is_fluid(block), opposite_near(samples, x, y, z, block))

def reaction_block(+source: Bool) -> U32:
  Bool.pick(U32, source, obsidian_block(), cobblestone_block())

def reaction_entries(
  +flows: List<&2, Flow>, +samples: List<&2, Sample>,
  +result: List<&2, Edit>
) -> List<&2, Edit>:
  match flows:
    case Nil{}:
      result
    case Con{+head, +tail}:
      Flow{+x, +y, +z, +level, +source, block} = head
      +rest = reaction_entries(tail, samples, result)
      Bool.pick(List<&2, Edit>, reactive(head, samples), Con{Edit{x, y, z, reaction_block(source)}, rest}, rest)

def remove_reactive(
  +flows: List<&2, Flow>, +samples: List<&2, Sample>
) -> List<&2, Flow>:
  match flows:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      +rest = remove_reactive(tail, samples)
      Bool.pick(List<&2, Flow>, reactive(head, samples), rest, Con{head, rest})

def reactions(+state: State, +samples: List<&2, Sample>) -> List<&2, Edit>:
  State{+flows} = state
  reaction_entries(flows, samples, Nil{})

def react(+state: State, +samples: List<&2, Sample>) -> State:
  State{+flows} = state
  State{remove_reactive(flows, samples)}

def changes(+before: State, +after: State) -> List<&2, Edit>:
  State{+old_flows} = before
  State{+new_flows} = after
  append_edits(removed_edits(old_flows, new_flows), added_edits(new_flows, old_flows))

# --- whether a flow is still fed --------------------------------------------------
#
# A flow stands while something feeds it: a source always does, a falling flow
# does not (it moves down instead), and a flow that cannot fall needs a stronger
# neighbour beside it or water on top of it. Nothing else is kept, so a pool
# drains when its source goes and a stray flow dries up rather than sitting
# there forever.
#
# The level of a cell says how far that cell is from its source, so a cell that
# is still fed keeps the level it had. Taking the level a neighbour offered
# instead would ratchet a whole pool down one step every tick.

# The level of the flow standing at a cell, or 0 when none does: a level is never
# 0, so 0 answers "nothing here".
def level_at(flows: List<&2, Flow>, +x: Nat, +y: Nat, +z: Nat, +fallback: U32) -> U32:
  match flows:
    case Nil{}:
      fallback
    case Con{+head, +tail}:
      Flow{+fx, +fy, +fz, +level, source, block} = head
      Bool.pick(
        U32,
        Bool.and(Bool.and(Nat.is_eq(fx, x), Nat.is_eq(fy, y)), Nat.is_eq(fz, z)),
        level,
        level_at(tail, x, y, z, fallback)
      )

# Bend's Nat cannot go below zero, so the cell one north and one west of the
# origin has no neighbour to ask about and answers 0.
def level_east(flows: List<&2, Flow>, +x: Nat, +y: Nat, +z: Nat) -> U32:
  level_at(flows, Nat.add(x, 1n), y, z, 0)

def level_west(flows: List<&2, Flow>, +x: Nat, +y: Nat, +z: Nat) -> U32:
  Bool.pick(U32, Nat.is_gt(x, 0n), level_at(flows, Nat.sub(x, 1n), y, z, 0), 0)

def level_south(flows: List<&2, Flow>, +x: Nat, +y: Nat, +z: Nat) -> U32:
  level_at(flows, x, y, Nat.add(z, 1n), 0)

def level_north(flows: List<&2, Flow>, +x: Nat, +y: Nat, +z: Nat) -> U32:
  Bool.pick(U32, Nat.is_gt(z, 0n), level_at(flows, x, y, Nat.sub(z, 1n), 0), 0)

def strongest_of(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_gt(a, b), a, b)

def strongest_beside(+flows: List<&2, Flow>, +x: Nat, +y: Nat, +z: Nat) -> U32:
  strongest_of(
    level_east(flows, x, y, z),
    strongest_of(
      level_west(flows, x, y, z),
      strongest_of(level_south(flows, x, y, z), level_north(flows, x, y, z))
    )
  )

def fed_from_above(samples: List<&2, Sample>, +x: Nat, +y: Nat, +z: Nat, +block: U32) -> Bool:
  U32.is_eq(sample_block(samples, x, Nat.add(y, 1n), z), block)

def still_fed(flow: Flow, +flows: List<&2, Flow>, +samples: List<&2, Sample>) -> Bool:
  Flow{+x, +y, +z, +level, source, +block} = flow
  match source:
    case True{}:
      True{}
    case False{}:
      Bool.and(
        Bool.not(can_fall(samples, x, y, z)),
        Bool.or(
          U32.is_gt(strongest_beside(flows, x, y, z), level),
          fed_from_above(samples, x, y, z, block)
        )
      )

# A tick walks the field once and leaves two lists: the flows that are still fed,
# and every cell the field reaches this tick. A Bend value is consumed once, so
# one walk has to build both rather than walk the list twice.
type Spread is Data:
  Spread{kept: List<&2, Flow>, offers: List<&2, Flow>}

def spread_field(
  +remaining: List<&2, Flow>, +flows: List<&2, Flow>, +samples: List<&2, Sample>,
  +kept: List<&2, Flow>, +offers: List<&2, Flow>
) -> Spread:
  match remaining:
    case Nil{}:
      Spread{kept, offers}
    case Con{+head, +tail}:
      +reached = spread(head, samples)
      spread_field(
        tail, flows, samples,
        Bool.pick(List<&2, Flow>, still_fed(head, flows, samples), Con{head, kept}, kept),
        append_spread(reached, offers)
      )

# A cell the field already holds keeps its own level: the level says how far
# that cell is from its source, and an offer that reaches it this tick is
# always a lower one, so taking the offer would ratchet the whole pool down a
# step every tick.
def merge_offers(+offers: List<&2, Flow>, +kept: List<&2, Flow>) -> List<&2, Flow>:
  match offers:
    case Nil{}:
      kept
    case Con{+head, +tail}:
      Flow{+x, +y, +z, level, source, block} = head
      +next = Bool.pick(
        List<&2, Flow>,
        contains(kept, x, y, z),
        kept,
        append_at_end(kept, head)
      )
      merge_offers(tail, next)

def seed(+state: State, +x: Nat, +y: Nat, +z: Nat, +level: U32) -> State:
  State{+flows} = state
  State{take(max_flow_cells(), append_unique(flows, Flow{x, y, z, level, True{}, water_block()}))}

def seed_lava(+state: State, +x: Nat, +y: Nat, +z: Nat, +level: U32) -> State:
  State{+flows} = state
  State{take(max_flow_cells(), append_unique(flows, Flow{x, y, z, level, True{}, lava_block()}))}

def merge_spread(+spread: Spread) -> State:
  Spread{+kept, +offers} = spread
  State{take(max_flow_cells(), merge_offers(offers, kept))}

# Every flow in the field is advanced, not the first sixty-four: bounding the
# walk used to drop the rest of the field, and the world then cleared those
# cells, so any pool wider than the bound lost water every tick. New cells land
# at the end, so the cap drops the newest arrivals rather than water that was
# already standing: past the cap a field stops spreading instead of vanishing.
def tick(+state: State, +samples: List<&2, Sample>) -> State:
  State{+flows} = state
  merge_spread(spread_field(flows, flows, samples, Nil{}, Nil{}))

def remove(+state: State, +x: Nat, +y: Nat, +z: Nat) -> State:
  State{+flows} = state
  State{remove_entries(flows, x, y, z)}

def current_contribution(
  flow: Flow, +player_x: F32, +player_y: F32, +player_z: F32
) -> Current:
  Flow{+x, +y, +z, +level, source, block} = flow
  +flow_x = U32.to_f32(U32.from_nat(x))
  +flow_y = U32.to_f32(U32.from_nat(y))
  +flow_z = U32.to_f32(U32.from_nat(z))
  +dx = F32.sub(player_x, flow_x)
  +dy = F32.sub(player_y, flow_y)
  +dz = F32.sub(player_z, flow_z)
  +distance = F32.sqrt(F32.add(F32.mul(dx, dx), F32.mul(dz, dz)))
  +near = Bool.and(
    Bool.and(F32.is_le(F32.abs(dx), 2.5), F32.is_le(F32.abs(dz), 2.5)),
    F32.is_le(F32.abs(dy), 1.5)
  )
  +valid = Bool.and(Bool.and(near, U32.is_gt(level, 1)), F32.is_gt(distance, 0.001))
  +weight = F32.mul(F32.div(U32.to_f32(level), 8.0), 0.6)
  Current{
    Bool.pick(F32, valid, F32.mul(F32.div(dx, distance), weight), 0.0),
    Bool.pick(F32, valid, F32.mul(F32.div(dz, distance), weight), 0.0)
  }

def current_contribution_x(
  flow: Flow, +player_x: F32, +player_y: F32, +player_z: F32
) -> F32:
  Flow{+x, +y, +z, +level, source, block} = flow
  +dx = F32.sub(player_x, U32.to_f32(U32.from_nat(x)))
  +dy = F32.sub(player_y, U32.to_f32(U32.from_nat(y)))
  +dz = F32.sub(player_z, U32.to_f32(U32.from_nat(z)))
  +distance = F32.sqrt(F32.add(F32.mul(dx, dx), F32.mul(dz, dz)))
  +near = Bool.and(Bool.and(F32.is_le(F32.abs(dx), 2.5), F32.is_le(F32.abs(dz), 2.5)), F32.is_le(F32.abs(dy), 1.5))
  +valid = Bool.and(Bool.and(near, U32.is_gt(level, 1)), F32.is_gt(distance, 0.001))
  +weight = F32.mul(F32.div(U32.to_f32(level), 8.0), 0.6)
  Bool.pick(F32, valid, F32.mul(F32.div(dx, distance), weight), 0.0)

def current_contribution_z(
  flow: Flow, +player_x: F32, +player_y: F32, +player_z: F32
) -> F32:
  Flow{+x, +y, +z, +level, source, block} = flow
  +dx = F32.sub(player_x, U32.to_f32(U32.from_nat(x)))
  +dy = F32.sub(player_y, U32.to_f32(U32.from_nat(y)))
  +dz = F32.sub(player_z, U32.to_f32(U32.from_nat(z)))
  +distance = F32.sqrt(F32.add(F32.mul(dx, dx), F32.mul(dz, dz)))
  +near = Bool.and(Bool.and(F32.is_le(F32.abs(dx), 2.5), F32.is_le(F32.abs(dz), 2.5)), F32.is_le(F32.abs(dy), 1.5))
  +valid = Bool.and(Bool.and(near, U32.is_gt(level, 1)), F32.is_gt(distance, 0.001))
  +weight = F32.mul(F32.div(U32.to_f32(level), 8.0), 0.6)
  Bool.pick(F32, valid, F32.mul(F32.div(dz, distance), weight), 0.0)

def current_scan(
  +flows: List<&2, Flow>, +player_x: F32, +player_y: F32, +player_z: F32,
  +sum_x: F32, +sum_z: F32
) -> Current:
  match flows:
    case Nil{}:
      Current{sum_x, sum_z}
    case Con{+head, +tail}:
      +x = current_contribution_x(head, player_x, player_y, player_z)
      +z = current_contribution_z(head, player_x, player_y, player_z)
      current_scan(tail, player_x, player_y, player_z, F32.add(sum_x, x), F32.add(sum_z, z))

def current_limited(+sum_x: F32, +sum_z: F32) -> Current:
  +magnitude = F32.sqrt(F32.add(F32.mul(sum_x, sum_x), F32.mul(sum_z, sum_z)))
  +safe_magnitude = Bool.pick(F32, F32.is_gt(magnitude, 0.0), magnitude, 1.0)
  +limited = F32.is_gt(magnitude, 1.2)
  Current{
    Bool.pick(F32, limited, F32.mul(F32.div(sum_x, safe_magnitude), 1.2), sum_x),
    Bool.pick(F32, limited, F32.mul(F32.div(sum_z, safe_magnitude), 1.2), sum_z)
  }

def current_scan_x(
  +flows: List<&2, Flow>, +player_x: F32, +player_y: F32, +player_z: F32,
  +sum_x: F32
) -> F32:
  match flows:
    case Nil{}:
      sum_x
    case Con{+head, +tail}:
      current_scan_x(tail, player_x, player_y, player_z,
        F32.add(sum_x, current_contribution_x(head, player_x, player_y, player_z)))

def current_scan_z(
  +flows: List<&2, Flow>, +player_x: F32, +player_y: F32, +player_z: F32,
  +sum_z: F32
) -> F32:
  match flows:
    case Nil{}:
      sum_z
    case Con{+head, +tail}:
      current_scan_z(tail, player_x, player_y, player_z,
        F32.add(sum_z, current_contribution_z(head, player_x, player_y, player_z)))

def current(
  +flows: List<&2, Flow>, +player_x: F32, +player_y: F32, +player_z: F32
) -> Current:
  +sum_x = current_scan_x(flows, player_x, player_y, player_z, 0.0)
  +sum_z = current_scan_z(flows, player_x, player_y, player_z, 0.0)
  current_limited(sum_x, sum_z)

def current_x(state: Current) -> F32:
  Current{+x, z} = state
  x

def current_z(state: Current) -> F32:
  Current{x, +z} = state
  z
