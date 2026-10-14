import Base
import ./face.bend as Face
import ./frame.bend as Frame
import ./paint.bend as Paint
import ./player.bend as PlayerProbe
import ./shade.bend as Shade
import ../world/world.bend as World
import ../world/world_state.bend as WorldState

# The client's world as the painter takes it: the view region's exposed faces, kept one chunk
# at a time and rebuilt only for the chunks whose edits changed. `native/play.bend` holds one
# and asks it for the frame; `native/room.bend` changes the edits it is built from.

# The client's world, kept between frames: the view region's exposed faces, and the edit log
# they were extracted from. Re-extracting the region every frame costs more than the whole
# rest of the frame put together, so the client holds the faces and rebuilds a chunk's only
# when the edits that fall in it change (`mark_of`).
#
# One chunk of the view region: where it is, in window chunks; a mark of the edits that fall
# in it; and its exposed faces, in the chunk's own cells.
type Slab is Data:
  Slab{x: Nat, z: Nat, mark: U32, faces: List<&2, Face.Face>}

# `faces` is every slab's faces in the region's cells, which is what the painter reads. The
# slabs are what it is kept from.
type World is Data:
  World{faces: List<&2, Face.Face>, edits: List<&2, WorldState.Edit>, home: Frame.Home,
    slabs: List<&2, Slab>}

def w_faces(world: World) -> List<&2, Face.Face>:
  match world:
    case World{faces, edits, home, slabs}:
      faces

def w_edits(world: World) -> List<&2, WorldState.Edit>:
  match world:
    case World{faces, edits, home, slabs}:
      edits

def w_home(world: World) -> Frame.Home:
  match world:
    case World{faces, edits, home, slabs}:
      home

def w_slabs(world: World) -> List<&2, Slab>:
  match world:
    case World{faces, edits, home, slabs}:
      slabs

def same_edit(a: WorldState.Edit, b: WorldState.Edit) -> Bool:
  WorldState.Edit{ax, ay, az, ablock} = a
  WorldState.Edit{bx, by, bz, bblock} = b
  Bool.and(Bool.and(Nat.is_eq(ax, bx), Nat.is_eq(ay, by)),
    Bool.and(Nat.is_eq(az, bz), U32.is_eq(ablock, bblock)))

def same_edits(+a: List<&2, WorldState.Edit>, +b: List<&2, WorldState.Edit>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Con{ah, at} Con{bh, bt}:
      Bool.and(same_edit(ah, bh), same_edits(at, bt))
    case _ _:
      False{}

# --- the world, one chunk at a time ---------------------------------------------
#
# The view region's faces are kept per chunk, as slabs, and a slab is built from its own
# chunk and nothing else. So an edit rebuilds the one slab it is in, and a region that moved
# a chunk over builds the five slabs that came into view, one a frame: the two things that
# used to rebuild the whole region at once, 21 ms against a 16.67 ms tick when it was nine
# chunks, and were the late frame after every dig and every sixteenth cell walked.
#
# A slab's faces carry the light their corners take (`native/shade.bend`), worked out from
# the same chunk in the same build, so the light costs nothing in a frame.
#
# What makes a slab its own is that its faces are extracted with air outside the chunk, so
# a block on a chunk's edge always has its outward face, whether or not the next chunk has
# a block against it. Those extra faces are between two solid blocks, so nothing can see
# them: any ray that reaches one has already entered the block in front of it through a
# face that is nearer, and the painter writes a pixel once, nearest first. They cost a place
# in the sort and are never painted. Extracting the region as one piece instead leaves them
# out, and then every chunk's faces depend on its four neighbours.

# The edits that fall in one chunk, folded to a word: a slab whose mark still matches was
# built from the same edits. `cx` and `cz` are the chunk as storage spells it, which is how
# an edit's own cells are spelled.
def mark.step(edit: WorldState.Edit, +cx: Nat, +cz: Nat, +hash: U32) -> U32:
  WorldState.Edit{+x, +y, +z, block} = edit
  Bool.pick(U32, Bool.and(Nat.is_eq(Nat.div(x, World.chunk_size()), cx),
      Nat.is_eq(Nat.div(z, World.chunk_size()), cz)),
    U32.mul(U32.xor(U32.mul(U32.xor(U32.mul(U32.xor(U32.mul(U32.xor(hash, U32.from_nat(x)),
      16777619), U32.from_nat(y)), 16777619), U32.from_nat(z)), 16777619), block), 16777619),
    hash)

def mark.go(edits: List<&2, WorldState.Edit>, +cx: Nat, +cz: Nat, +hash: U32) -> U32:
  match edits:
    case Nil{}:
      hash
    case edit <> rest:
      mark.go(rest, cx, cz, mark.step(edit, cx, cz, hash))

# `x` and `z` are window chunks.
def mark_of(edits: List<&2, WorldState.Edit>, +x: Nat, +z: Nat) -> U32:
  mark.go(edits, PlayerProbe.stored_chunk(x), PlayerProbe.stored_chunk(z), 2166136261)

def slab_built(+x: Nat, +z: Nat, +edits: List<&2, WorldState.Edit>) -> Slab:
  Slab{x, z, mark_of(edits, x, z),
    Shade.faces_from_chunk(WorldState.chunk(Frame.seed(), PlayerProbe.stored_chunk(x),
      PlayerProbe.stored_chunk(z), edits))}

def slab_is(slab: Slab, +x: Nat, +z: Nat, +mark: U32) -> Bool:
  Slab{sx, sz, smark, faces} = slab
  Bool.and(Bool.and(Nat.is_eq(sx, x), Nat.is_eq(sz, z)), U32.is_eq(smark, mark))

# What walking the region's chunks left: the slabs it has, how many more it may still
# build this frame, and whether anything is not as it was.
type Kept is Data:
  Kept{slabs: List<&2, Slab>, budget: Nat, changed: Bool}

def slab_pick(found: Bool, slab: Slab, later: Maybe<&2, Slab>) -> Maybe<&2, Slab>:
  match found:
    case True{}:
      Some{slab}
    case False{}:
      later

def slab_find(slabs: List<&2, Slab>, +x: Nat, +z: Nat, +mark: U32) -> Maybe<&2, Slab>:
  match slabs:
    case Nil{}:
      None{}
    case +slab <> rest:
      slab_pick(slab_is(slab, x, z, mark), slab, slab_find(rest, x, z, mark))

# One wanted chunk: the slab already held for it, or a new one while the frame's budget
# lasts, or nothing this frame.
def slab_wanted(held: Maybe<&2, Slab>, kept: Kept, +x: Nat, +z: Nat,
  +edits: List<&2, WorldState.Edit>) -> Kept:
  match held kept:
    case Some{slab} Kept{slabs, budget, changed}:
      Kept{slab <> slabs, budget, changed}
    case None{} Kept{slabs, 0n, changed}:
      Kept{slabs, 0n, True{}}
    case None{} Kept{slabs, 1n+left, changed}:
      Kept{slab_built(x, z, edits) <> slabs, left, True{}}

def slabs.go(remaining: Nat, +index: Nat, +hx: Nat, +hz: Nat, +old: List<&2, Slab>,
  +edits: List<&2, WorldState.Edit>, kept: Kept) -> Kept:
  match remaining:
    case 0n:
      kept
    case 1n+r:
      +x = Nat.add(hx, Nat.mod(index, Frame.view_columns()))
      +z = Nat.add(hz, Nat.div(index, Frame.view_columns()))
      slabs.go(r, Nat.add(index, 1n), hx, hz, old, edits,
        slab_wanted(slab_find(old, x, z, mark_of(edits, x, z)), kept, x, z, edits))

# A slab's faces moved into the region's cells and put in front of `acc`.
def merge.faces(faces: List<&2, Face.Face>, +dx: U32, +dz: U32,
  acc: List<&2, Face.Face>) -> List<&2, Face.Face>:
  match faces:
    case Nil{}:
      acc
    case Face.Face{x, y, z, dir, block} <> rest:
      merge.faces(rest, dx, dz, Face.Face{U32.add(x, dx), y, U32.add(z, dz), dir, block} <> acc)

def merge.go(slabs: List<&2, Slab>, +hx: Nat, +hz: Nat,
  acc: List<&2, Face.Face>) -> List<&2, Face.Face>:
  match slabs:
    case Nil{}:
      acc
    case Slab{x, z, mark, faces} <> rest:
      merge.go(rest, hx, hz, merge.faces(faces,
        U32.from_nat(Nat.mul(Nat.sub(x, hx), World.chunk_size())),
        U32.from_nat(Nat.mul(Nat.sub(z, hz), World.chunk_size())), acc))

def merged(+slabs: List<&2, Slab>, +edits: List<&2, WorldState.Edit>, +home: Frame.Home) -> World:
  World{merge.go(slabs, Frame.home_x(home), Frame.home_z(home), []), edits, home, slabs}

def world_changed(changed: Bool, slabs: List<&2, Slab>, world: World,
  edits: List<&2, WorldState.Edit>, home: Frame.Home) -> World:
  match changed:
    case True{}:
      merged(slabs, edits, home)
    case False{}:
      world

# The world after the walk. Nothing changed and it is the world it was, list and all; else
# the slabs are merged again into the list the painter reads.
def world_kept(kept: Kept, +world: World, +edits: List<&2, WorldState.Edit>,
  +home: Frame.Home, moved: Bool) -> World:
  Kept{slabs, budget, changed} = kept
  world_changed(Bool.or(changed, moved), slabs, world, edits, home)

def region_cells_wide() -> Nat:
  Nat.mul(Frame.view_columns(), Frame.view_rows())

# The world for this frame: every slab still wanted is kept, and at most `budget` of the
# missing ones are built.
def world_with(+budget: Nat, +world: World, +edits: List<&2, WorldState.Edit>,
  +home: Frame.Home) -> World:
  world_kept(slabs.go(region_cells_wide(), 0n, Frame.home_x(home), Frame.home_z(home),
      w_slabs(world), edits, Kept{[], budget, False{}}),
    world, edits, home, Bool.not(Frame.same_home(w_home(world), home)))

# One slab a frame: a slab is about 2.5 ms to build and merge, which a frame has room for
# and five would not have. A chunk that has just come into view at the region's far edge is
# missing for a few frames before it is terrain, and that edge is past where the air has
# already hidden most of what is there.
def world_for(+world: World, +edits: List<&2, WorldState.Edit>, +home: Frame.Home) -> World:
  world_with(1n, world, edits, home)

# The whole region at once, which is what the client starts on.
def world_built(+edits: List<&2, WorldState.Edit>, +home: Frame.Home) -> World:
  world_with(region_cells_wide(), World{[], edits, home, []}, edits, home)

# The slabs as the painter takes them: each chunk's faces, in the chunk's own cells, beside
# where the chunk is in the region. The painter tests a chunk's box before it reads a face of
# it, and does the chunks it keeps at the same time.
def groups.go(slabs: List<&2, Slab>, +hx: Nat, +hz: Nat,
  acc: List<&2, Paint.Group>) -> List<&2, Paint.Group>:
  match slabs:
    case Nil{}:
      acc
    case Slab{x, z, mark, faces} <> rest:
      groups.go(rest, hx, hz,
        Paint.Group{U32.from_nat(Nat.mul(Nat.sub(x, hx), World.chunk_size())),
          U32.from_nat(Nat.mul(Nat.sub(z, hz), World.chunk_size())), True{}, faces} <> acc)

def w_groups(+world: World) -> List<&2, Paint.Group>:
  groups.go(w_slabs(world), Frame.home_x(w_home(world)), Frame.home_z(w_home(world)), [])
