import Base
import ../../../world/world_state.bend as WorldState
import ../../../native/frame.bend as Frame
import ../../../native/slabs.bend as Slabs
import ../../../native/face.bend as Face

# What chunk loading costs the client, a frame at a time.
#
# The client keeps the view region as one slab per chunk and builds at most one slab a
# frame (`Slabs.world_for`). A walking player therefore pays for a slab in the frames
# where a chunk comes into view and pays only for the merge in the frames after, and the
# question this answers is what each of those is worth against a 16.67 ms tick.
#
# It exists because `lab/native/client-probe/frame_bench.bend`, which used to answer this,
# stopped compiling when the client moved to slabs: it still called `Client.region_chunks`,
# which no longer exists, and rebuilt the client from a flat `Play.Client` row that has
# since become four records. Everything here is a shipping call - `WorldState.chunk`,
# `Shade.faces_from_chunk`, `Slabs.world_built`, `Slabs.world_for` - so there is nothing
# here to fall out of step with the client except the calls themselves.

# Iterations per timed figure. Three is enough for a coarse millisecond clock on a cost
# of milliseconds, and every figure folds its own output so it cannot be elided.
def rounds() -> Nat:
  3n

# Chunks the walk crosses. The region is five chunks by five, so twenty-four steps walks
# past a whole region and meets the slabs a walking player meets.
def steps() -> Nat:
  24n

def face_total(faces: List<&2, Face.Face>) -> U32:
  match faces:
    case Nil{}:
      0
    case +face <> rest:
      U32.add(1, face_total(rest))

def fold_hash(+hash: U32, +value: U32) -> U32:
  U32.add(U32.mul(hash, 16777619), value)

def home_at(+home: Nat) -> Frame.Home:
  Frame.Home{home, 0n}

# --- one slab: what a frame costs when a chunk comes into view ----------------
def slab_step(+edits: List<&2, WorldState.Edit>, +hash: U32) -> U32:
  fold_hash(hash, face_total(Slabs.w_faces(Slabs.world_with(1n, Slabs.World{[], edits,
    home_at(0n), []}, edits, home_at(0n)))))

def slab.go(remaining: Nat, +edits: List<&2, WorldState.Edit>, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      slab.go(p, edits, slab_step(edits, hash))

# --- the whole region: what a first entry into a world waits for --------------
def region_step(+edits: List<&2, WorldState.Edit>, +hash: U32) -> U32:
  fold_hash(hash, face_total(Slabs.w_faces(Slabs.world_built(edits, home_at(0n)))))

def region.go(remaining: Nat, +edits: List<&2, WorldState.Edit>, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      region.go(p, edits, region_step(edits, hash))

# --- a frame with nothing new in view: the common frame -----------------------
#
# The world is built once, outside the step, and the step only asks for the frame's
# update. A version of this that rebuilt the region inside the step would be timing the
# start-up cost and calling it the common frame, which is what the first version of this
# probe did: it read 62 ms against the 6 ms a walking frame actually costs.
def steady_step(+carried: Slabs.World, +edits: List<&2, WorldState.Edit>, +hash: U32) -> U32:
  fold_hash(hash, face_total(Slabs.w_faces(Slabs.world_for(carried, edits, home_at(0n)))))

def steady.go(remaining: Nat, +carried: Slabs.World, +edits: List<&2, WorldState.Edit>,
  +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      steady.go(p, carried, edits, steady_step(carried, edits, hash))

# --- the walk: the region moving a chunk at a time -----------------------------
#
# Each step is the client's own `world_for` on a region whose first chunk has moved, so
# a step that has to build a slab costs what a walking player's frame costs. This is the
# number to compare against the 16.67 ms tick.
def walk_step(+world: Slabs.World, +edits: List<&2, WorldState.Edit>, +home: Nat,
  +hash: U32) -> U32:
  +moved : Frame.Home = home_at(Nat.add(home, 1n))
  fold_hash(hash, face_total(Slabs.w_faces(Slabs.world_for(world, edits, moved))))

def walk.go(remaining: Nat, +world: Slabs.World, +edits: List<&2, WorldState.Edit>,
  +home: Nat, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +moved : Frame.Home = home_at(Nat.add(home, 1n))
      walk.go(p, Slabs.world_for(world, edits, moved), edits, Nat.add(home, 1n),
        walk_step(world, edits, home, hash))

# --- the clock ----------------------------------------------------------------
#
# `IO.now` counts milliseconds, so each figure is a total over `rounds()` divided by it.
# The step is a parameter rather than four copies of this, so every figure is timed the
# same way and cannot drift from the others. A warm pass runs first, so the first timed
# round is not paying for the world's first look at any of it.
def run_step(step: Nat, +carried: Slabs.World, +edits: List<&2, WorldState.Edit>,
  +hash: U32) -> U32:
  match step:
    case 0n:
      slab.go(rounds(), edits, hash)
    case 1n:
      steady.go(rounds(), carried, edits, hash)
    case _:
      region.go(rounds(), edits, hash)

# The figure, with the digest printed inside so the work is provably not elided: a Bend
# value is linear, so a digest dropped on the floor would be a build that removed itself.
def timed(+step: Nat, +carried: Slabs.World, +edits: List<&2, WorldState.Edit>,
  +hash: U32) -> IO(Nat):
  do IO<Nat>:
    warm : U32 = run_step(step, carried, edits, hash)
    started : Nat <- IO.now()
    used : U32 = run_step(step, carried, edits, warm)
    consumed : Unit <- IO.print("consume=rounds:" ++ U32.show(used))
    finished : Nat <- IO.now()
    IO.pure(Nat, Nat.div(Nat.sub(finished, started), rounds()))

def main() -> IO(Unit):
  do IO<Unit>:
    +edits : List<&2, WorldState.Edit> = WorldState.empty()
    +built : Slabs.World = Slabs.world_built(edits, home_at(0n))
    warm : U32 = walk.go(2n, built, edits, 0n, 1)
    slab_ms : Nat <- timed(0n, built, edits, 2166136261)
    steady_ms : Nat <- timed(1n, built, edits, 2166136261)
    region_ms : Nat <- timed(2n, built, edits, 2166136261)
    walk_started : Nat <- IO.now()
    digest : U32 = walk.go(steps(), built, edits, 0n, warm)
    walk_done : Nat <- IO.now()
    +walk_ms : Nat = Nat.sub(walk_done, walk_started)
    +per_step : Nat = Nat.div(walk_ms, steps())
    IO.print("chunk_probe rounds=" ++ Nat.show(rounds())
      ++ " steps=" ++ Nat.show(steps())
      ++ " slab_ms=" ++ Nat.show(slab_ms)
      ++ " steady_ms=" ++ Nat.show(steady_ms)
      ++ " region_build_ms=" ++ Nat.show(region_ms)
      ++ " walk_ms=" ++ Nat.show(walk_ms)
      ++ " walk_per_step_ms=" ++ Nat.show(per_step)
      ++ " digest=" ++ U32.show(digest))