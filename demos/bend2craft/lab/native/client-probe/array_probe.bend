import Base

# ---------------------------------------------------------------------------
# What a frame of pixels costs in Bend, against what it costs in the quadtree.
#
# `lab/native/client-probe/output_probe.bend` prices the `Image` quadtree the runtime reads
# in C. A renderer that stops walking a candidate list per pixel has to keep the frame it
# is building somewhere, and in Bend 2.0.32 that is an `Array`: its read and write are
# in-place mutations, so painting into it allocates nothing, but both descend the
# array's tree, and a 1024x1024 frame is a 2^20 array, which is twenty levels.
#
# So this prices one write and one read of one slot, in place, walked in index order —
# the shape a scanline fill has and the shape the read-back into the quadtree has. The
# pair at depth 12 and depth 20 separates the descent from the array itself: depth 12 is
# a 64x64 frame, and the difference between the two is the eight extra levels a
# 1024x1024 frame costs on every touch.
#
# An `Array` is a `Type`, not `Data`, so it cannot be a field of a record and cannot be
# bound with `+`: it is threaded through this file's own parameters instead.
# ---------------------------------------------------------------------------

def slots() -> Nat:
  1048576n

def small_slots() -> Nat:
  4096n

# `depth` is the array's tree depth: 20 for a 1024x1024 frame, 12 for a 64x64 one.
def blank(depth: Nat) -> Array<U32>:
  Array.new(U32, depth, (0 : U32))

def fill.go(remaining: Nat, +at: U32, blocks: Array<U32>) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      updated = blocks[at] <- at
      fill.go(p, (at + 1 : U32), updated)

# `salt` is folded into every value written, so a round cannot be folded away by writing
# what the round before it wrote. Without it the repeated rounds measure the same
# identical writes, which is not what the client does.
def fill.salted.go(remaining: Nat, +at: U32, +salt: U32, blocks: Array<U32>) -> Array<U32>:
  match remaining:
    case 0n:
      blocks
    case 1n+p:
      updated = blocks[at] <- (at + salt : U32)
      fill.salted.go(p, (at + 1 : U32), salt, updated)

def fill.salted(rounds: Nat, +count: Nat, +at: U32, +salt: U32, blocks: Array<U32>) ->
  Array<U32>:
  match rounds:
    case 0n:
      blocks
    case 1n+r:
      written : Array<U32> = fill.salted.go(count, at, salt, blocks)
      fill.salted(r, count, at, salt, written)

# A read hands the array back beside the element, so the walk carries the pair.
def read.go(remaining: Nat, +at: U32, read: Array<U32> & U32) -> Array<U32> & U32:
  match remaining:
    case 0n:
      read
    case 1n+p:
      (blocks, value) = read
      taken : Array<U32> & U32 = Array.get(U32, blocks, at)
      read.go(p, (at + 1 : U32), taken)

def read.rounds(rounds: Nat, +count: Nat, +at: U32, read: Array<U32> & U32) ->
  Array<U32> & U32:
  match rounds:
    case 0n:
      read
    case 1n+r:
      walked : Array<U32> & U32 = read.go(count, at, read)
      read.rounds(r, count, at, walked)

def sample.at(read: Array<U32> & U32) -> U32:
  (_, seen) = read
  seen

def sample(pixels: Array<U32>) -> U32:
  sample.at(pixels[4096])

# The read walk folds every value it reads into the digest it hands back, because a walk
# that reads and discards measures nothing: the runtime is free to drop those reads, and
# the first run of this reported 0 ms for 400 million of them for exactly that reason.
# The array travels beside the hash rather than inside it, so the walk's own cost is the
# read and nothing else.
def scan.go(remaining: Nat, +at: U32, read: Array<U32> & U32, +hash: U32) ->
  Array<U32> & U32:
  match remaining:
    case 0n:
      (rest, _) = read
      (rest, hash)
    case 1n+p:
      (blocks, value) = read
      taken : Array<U32> & U32 = Array.get(U32, blocks, at)
      scan.go(p, (at + 1 : U32), taken, U32.add(hash, value))

def scan.rounds(rounds: Nat, +count: Nat, +at: U32, read: Array<U32> & U32,
  +hash: U32) -> Array<U32> & U32:
  match rounds:
    case 0n:
      read
    case 1n+r:
      walked : Array<U32> & U32 = scan.go(count, at, read, hash)
      scan.rounds(r, count, at, walked, U32.add(hash, 1))

def phase_line(+name: String, +count: Nat, +depth: Nat, started: Nat, finished: Nat,
  +digest: U32) -> String:
  "phase=" ++ name ++ " slots=" ++ Nat.show(count) ++ " depth=" ++ Nat.show(depth)
    ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finished, started))
    ++ " touches_per_ms=" ++ Nat.show(count)
    ++ " digest=" ++ U32.show(digest)

def report(+name: String, +count: Nat, +depth: Nat, started: Nat, finished: Nat,
  done: Array<U32> & U32) -> IO(Unit):
  (pixels, digest) = done
  +seen : U32 = sample(pixels)
  +line : String = phase_line(name, count, depth, started, finished, U32.add(digest, seen))
  do IO<Unit>:
    IO.print(line)

# One timed walk of 1,048,576 writes lands inside a millisecond, which is coarser than
# the clock can report, so each phase repeats its walk enough times for the elapsed time
# to carry digits. The rounds are part of the name so the line cannot be read as one.
def fill_phase(+name: String, +count: Nat, +depth: Nat, +rounds: Nat) -> IO(Unit):
  do IO<Unit>:
    blocks : Array<U32> = blank(depth)
    started : Nat <- IO.now()
    filled : Array<U32> = fill.salted(rounds, count, 0, 7, blocks)
    finished : Nat <- IO.now()
    report(name, count, depth, started, finished, (filled, 2166136261))

def read_phase(+name: String, +count: Nat, +depth: Nat, +rounds: Nat) -> IO(Unit):
  do IO<Unit>:
    blocks : Array<U32> = blank(depth)
    filled : Array<U32> = fill.go(count, 0, blocks)
    started : Nat <- IO.now()
    walked : Array<U32> & U32 = scan.rounds(rounds, count, 0, (filled, 0), 2166136261)
    finished : Nat <- IO.now()
    report(name, count, depth, started, finished, walked)

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- fill_phase("array_fill20x40", slots(), 20n, 40n)
    b : Unit <- fill_phase("array_fill20x400", slots(), 20n, 400n)
    c : Unit <- read_phase("array_read20x40", slots(), 20n, 40n)
    d : Unit <- read_phase("array_read20x400", slots(), 20n, 400n)
    IO.print("array-probe=pass")