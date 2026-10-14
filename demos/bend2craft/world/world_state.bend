import Base
import ./world.bend as World

type Edit is Data:
  Edit{x: Nat, y: Nat, z: Nat, block: U32}

# Every walk over a whole edit list is tail recursive. The JavaScript target
# (the browser, the Node server and the Durable Object) runs a tail call as a
# loop, while a walk that recursed before combining its result used one stack
# frame per edit and overflowed a little past 15,000 edits, so a long-lived
# world stopped loading. `tests/world-state-bend.test.mjs` pins this with a
# 60,000-edit log.

def empty() -> List<&2, Edit>:
  Nil{}

# `acc` reversed, followed by `rest`.
def rev_append(acc: List<&2, Edit>, rest: List<&2, Edit>) -> List<&2, Edit>:
  List.reverse.go(&2, Edit, acc, rest)

def torches.go(edits: List<&2, Edit>, +acc: List<&2, Edit>) -> List<&2, Edit>:
  match edits:
    case Nil{}:
      rev_append(acc, Nil{})
    case Con{+head, tail}:
      Edit{+x, +y, +z, +block} = head
      torches.go(tail, Bool.pick(List<&2, Edit>, U32.is_eq(block, 12), Con{head, acc}, acc))

def torches(edits: List<&2, Edit>) -> List<&2, Edit>:
  torches.go(edits, Nil{})

def light_source(+block: U32) -> Bool:
  Bool.or(U32.is_eq(block, 12), U32.is_eq(block, 21))

def light_sources.go(edits: List<&2, Edit>, +acc: List<&2, Edit>) -> List<&2, Edit>:
  match edits:
    case Nil{}:
      rev_append(acc, Nil{})
    case Con{+head, tail}:
      Edit{+x, +y, +z, +block} = head
      light_sources.go(tail, Bool.pick(List<&2, Edit>, light_source(block), Con{head, acc}, acc))

def light_sources(edits: List<&2, Edit>) -> List<&2, Edit>:
  light_sources.go(edits, Nil{})

def edit_matches(edit: Edit, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Edit{ex, ey, ez, block} = edit
  Bool.and(Bool.and(Nat.is_eq(ex, x), Nat.is_eq(ey, y)), Nat.is_eq(ez, z))

def edit_value(edit: Edit) -> U32:
  Edit{x, y, z, block} = edit
  block

def make_edit(x: Nat, y: Nat, z: Nat, block: U32) -> Edit:
  Edit{x, y, z, block}

def cons_edit(edit: Edit, tail: List<&2, Edit>) -> List<&2, Edit>:
  Con{edit, tail}

type Position is Data:
  At{index: Nat}
  Missing{}

# Where (x, y, z) sits in the log, stopping at the first match. `stop` is the
# previous entry's match, so the walk ends right after it without a helper
# (a def may not call back into its caller).
def position.go(edits: List<&2, Edit>, +stop: Bool, +x: Nat, +y: Nat, +z: Nat, +index: Nat) -> Position:
  match edits stop:
    case _ True{}:
      At{Nat.sub(index, 1n)}
    case Nil{} False{}:
      Missing{}
    case Con{+head, tail} False{}:
      position.go(tail, edit_matches(head, x, y, z), x, y, z, Nat.add(index, 1n))

def replace_at(edits: List<&2, Edit>, +index: Nat, +acc: List<&2, Edit>, +edit: Edit) -> List<&2, Edit>:
  match edits index:
    case Nil{} _:
      rev_append(acc, Nil{})
    case Con{head, tail} 0n:
      rev_append(acc, Con{edit, tail})
    case Con{+head, tail} 1n+p:
      replace_at(tail, p, Con{head, acc}, edit)

def set.at(position: Position, +edits: List<&2, Edit>, +edit: Edit) -> List<&2, Edit>:
  match position:
    case At{+index}:
      replace_at(edits, index, Nil{}, edit)
    case Missing{}:
      Con{edit, edits}

# The log with (x, y, z) holding `block`: the cell's entry is replaced where it
# stands, or a new entry goes to the front. A log holds one entry per cell, so
# its order carries no meaning. Only the entries before the cell are copied.
def set(+edits: List<&2, Edit>, +x: Nat, +y: Nat, +z: Nat, +block: U32) -> List<&2, Edit>:
  set.at(position.go(edits, False{}, x, y, z, 0n), edits, make_edit(x, y, z, block))

def block.go(
  edits: List<&2, Edit>, +stop: Bool, +value: U32, +seed: Nat, +x: Nat, +y: Nat, +z: Nat
) -> U32:
  match edits stop:
    case _ True{}:
      value
    case Nil{} False{}:
      World.block(seed, x, y, z)
    case Con{+head, tail} False{}:
      block.go(tail, edit_matches(head, x, y, z), edit_value(head), seed, x, y, z)

# The block at (x, y, z): the cell's edit, else the generated block.
def block(
  edits: List<&2, Edit>, +seed: Nat, +x: Nat, +y: Nat, +z: Nat
) -> U32:
  block.go(edits, False{}, 0, seed, x, y, z)

# Batches -----------------------------------------------------------------------
#
# `set_many` folds a whole batch into the log in one pass instead of one pass
# per edit. Only log entries inside the batch's bounding box are compared with
# the batch, so a 64-cell fluid step costs about one walk of the log.

type Box is Data:
  Box{min_x: Nat, max_x: Nat, min_y: Nat, max_y: Nat, min_z: Nat, max_z: Nat}

type Probe is Data:
  Probe{found: Bool, value: U32}

# Base's Nat.min and Nat.max count down both arguments one step at a time;
# stored coordinates sit near 2^15, so compare instead.
def nat_min(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_le(a, b), a, b)

def nat_max(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_le(a, b), b, a)

def box.grow(box: Box, edit: Edit) -> Box:
  Box{+min_x, +max_x, +min_y, +max_y, +min_z, +max_z} = box
  Edit{+x, +y, +z, block} = edit
  Box{nat_min(min_x, x), nat_max(max_x, x), nat_min(min_y, y), nat_max(max_y, y), nat_min(min_z, z), nat_max(max_z, z)}

def box.go(batch: List<&2, Edit>, box: Box) -> Box:
  match batch:
    case Nil{}:
      box
    case Con{+head, tail}:
      box.go(tail, box.grow(box, head))

def box.of(+first: Edit, rest: List<&2, Edit>) -> Box:
  Edit{+x, +y, +z, block} = first
  box.go(rest, Box{x, x, y, y, z, z})

def box.inside(+box: Box, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Box{+min_x, +max_x, +min_y, +max_y, +min_z, +max_z} = box
  Bool.and(
    Bool.and(Bool.and(Nat.is_ge(x, min_x), Nat.is_le(x, max_x)), Bool.and(Nat.is_ge(y, min_y), Nat.is_le(y, max_y))),
    Bool.and(Nat.is_ge(z, min_z), Nat.is_le(z, max_z))
  )

# The last value the batch gives (x, y, z), if any.
def probe.go(batch: List<&2, Edit>, +x: Nat, +y: Nat, +z: Nat, +found: Bool, +value: U32) -> Probe:
  match batch:
    case Nil{}:
      Probe{found, value}
    case Con{+head, tail}:
      +same = edit_matches(head, x, y, z)
      probe.go(tail, x, y, z, Bool.or(found, same), Bool.pick(U32, same, edit_value(head), value))

def probe_found(result: Probe) -> Bool:
  Probe{+found, value} = result
  found

def probe(+inside: Bool, +batch: List<&2, Edit>, +x: Nat, +y: Nat, +z: Nat) -> Probe:
  match inside:
    case True{}:
      probe.go(batch, x, y, z, False{}, 0)
    case False{}:
      Probe{False{}, 0}

# The batch without any entry for (x, y, z).
def without.go(batch: List<&2, Edit>, +x: Nat, +y: Nat, +z: Nat, +acc: List<&2, Edit>) -> List<&2, Edit>:
  match batch:
    case Nil{}:
      rev_append(acc, Nil{})
    case Con{+head, tail}:
      without.go(tail, x, y, z, Bool.pick(List<&2, Edit>, edit_matches(head, x, y, z), acc, Con{head, acc}))

def without(+hit: Bool, pending: List<&2, Edit>, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Edit>:
  match hit:
    case True{}:
      without.go(pending, x, y, z, Nil{})
    case False{}:
      pending

# The batch with only the last entry of each cell, in batch order.
def dedupe.go(batch: List<&2, Edit>, +acc: List<&2, Edit>) -> List<&2, Edit>:
  match batch:
    case Nil{}:
      rev_append(acc, Nil{})
    case Con{+head, +tail}:
      Edit{+x, +y, +z, block} = head
      +later = probe_found(probe(True{}, tail, x, y, z))
      dedupe.go(tail, Bool.pick(List<&2, Edit>, later, acc, Con{head, acc}))

def set_many.step(+hit: Probe, +head: Edit) -> Edit:
  Probe{+found, +value} = hit
  Edit{+x, +y, +z, block} = head
  Bool.pick(Edit, found, make_edit(x, y, z, value), head)

def set_many.go(
  edits: List<&2, Edit>, acc: List<&2, Edit>, +batch: List<&2, Edit>, +box: Box, pending: List<&2, Edit>
) -> List<&2, Edit>:
  match edits:
    case Nil{}:
      rev_append(acc, pending)
    case Con{+head, tail}:
      Edit{+x, +y, +z, block} = head
      +hit = probe(box.inside(box, x, y, z), batch, x, y, z)
      set_many.go(tail, Con{set_many.step(hit, head), acc}, batch, box, without(probe_found(hit), pending, x, y, z))

# One edit is a plain `set`; a longer batch takes the single pass.
def set_many.more(rest: List<&2, Edit>, +edits: List<&2, Edit>, +batch: List<&2, Edit>, +first: Edit) -> List<&2, Edit>:
  match rest:
    case Nil{}:
      Edit{+x, +y, +z, +block} = first
      set(edits, x, y, z, block)
    case Con{second, more}:
      set_many.go(edits, Nil{}, batch, box.of(first, rest), dedupe.go(batch, Nil{}))

def set_many.start(+edits: List<&2, Edit>, +batch: List<&2, Edit>) -> List<&2, Edit>:
  match batch:
    case Nil{}:
      edits
    case Con{+first, rest}:
      set_many.more(rest, edits, batch, first)

# `set` for every edit of `batch` in order (a later edit of a cell wins), in
# one pass over the log.
def set_many(edits: List<&2, Edit>, +batch: List<&2, Edit>) -> List<&2, Edit>:
  set_many.start(edits, batch)

def chunk.apply.write(
  edit: Edit, +chunk_x: Nat, +chunk_z: Nat, blocks: Array<U32>, inside: Bool
) -> Array<U32>:
  Edit{x, y, z, value} = edit
  match inside:
    case False{}:
      blocks
    case True{}:
      +local_x = Nat.sub(x, Nat.mul(chunk_x, World.chunk_size()))
      +local_z = Nat.sub(z, Nat.mul(chunk_z, World.chunk_size()))
      +index = U32.from_nat(Nat.add(local_x, Nat.mul(World.chunk_size(), Nat.add(local_z, Nat.mul(World.chunk_size(), y)))))
      Array.set(U32, blocks, index, value)

def chunk.apply(
  edits: List<&2, Edit>, +seed: Nat, +chunk_x: Nat, +chunk_z: Nat,
  blocks: Array<U32>
) -> Array<U32>:
  match edits:
    case Nil{}:
      blocks
    case Con{+head, tail}:
      Edit{x, y, z, value} = head
      +base_x = Nat.mul(chunk_x, World.chunk_size())
      +base_z = Nat.mul(chunk_z, World.chunk_size())
      +inside = Bool.and(
        Bool.and(Nat.is_ge(x, base_x), Nat.is_lt(x, Nat.add(base_x, World.chunk_size()))),
        Bool.and(
          Bool.and(Nat.is_ge(z, base_z), Nat.is_lt(z, Nat.add(base_z, World.chunk_size()))),
          Nat.is_lt(y, World.max_y())
        )
      )
      updated = chunk.apply.write(head, chunk_x, chunk_z, blocks, inside)
      chunk.apply(tail, seed, chunk_x, chunk_z, updated)

def chunk(
  +seed: Nat, +chunk_x: Nat, +chunk_z: Nat, edits: List<&2, Edit>
) -> Array<U32>:
  chunk.apply(edits, seed, chunk_x, chunk_z, World.chunk(seed, chunk_x, chunk_z))
