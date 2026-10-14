import Base
import ../../../world/world.bend as World
import ../../../native/world.bend as Native
import ../render-probe/render_probe.bend as Render

def fingerprint_step(+hash: U32, +value: U32) -> U32:
  U32.mul(U32.xor(hash, value), 16777619)

def fingerprint_values(values: List<&1, U32>, hash: U32) -> U32:
  match values:
    case Nil{}:
      hash
    case value <> rest:
      fingerprint_values(rest, fingerprint_step(hash, value))

def fingerprint_chunk(blocks: Array<U32>) -> U32:
  fingerprint_values(Array.to_list(~U32, blocks), 2166136261)

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, message)

def check_sample(clones: Array<U32> & Array<U32>) -> IO(Unit):
  (chunk_for_hash, chunk_for_image) = clones
  +chunk_fingerprint = fingerprint_chunk(chunk_for_hash)
  pixels = Native.surface(chunk_for_image)
  image = Native.image(4n, pixels, 0, 0, Native.Cursor{8, 8}, None{})
  +image_fingerprint = Render.fingerprint(image)
  do IO<Unit>:
    report : Unit <- IO.print("correctness seed=1337 chunk=(0,0) block_fp="
      ++ U32.show(chunk_fingerprint) ++ " image_fp=" ++ U32.show(image_fingerprint))
    # The block fingerprint moved on 2026-10-03 when max_y went from 20 to 64, the
    # bottom row became bedrock, the cave rule became a two-field lattice, and the
    # ores became veins on an eight-cell lattice with vanilla's bands and densities.
    # The image fingerprint never moved, because the spawn pose's ray render does
    # not see the floor the ores are in.
    chunk_check : Unit <- check(U32.is_eq(chunk_fingerprint, 1714614001),
      "chunk fingerprint changed")
    image_check : Unit <- check(U32.is_eq(image_fingerprint, 3748750826),
      "native image fingerprint changed")
    IO.print("correctness=pass")

def check_correctness() -> IO(Unit):
  check_sample(Array.clone(U32, World.chunk(1337n, 0n, 0n)))

def repeated_chunk_fingerprint(remaining: Nat, hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      chunk_fingerprint = fingerprint_chunk(World.chunk(1337n, 0n, 0n))
      repeated_chunk_fingerprint(p, fingerprint_step(hash, chunk_fingerprint))

def repeated_image_fingerprint(
  remaining: Nat, +pixels: List<&2, U32>, hash: U32
) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      image = Native.image(4n, pixels, 0, 0, Native.Cursor{8, 8}, None{})
      image_fingerprint = Render.fingerprint(image)
      repeated_image_fingerprint(p, pixels,
        fingerprint_step(hash, image_fingerprint))

def chunk_repetitions() -> Nat:
  2048n

def image_repetitions() -> Nat:
  512n

def run_chunk_phase() -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = repeated_chunk_fingerprint(chunk_repetitions(), 2166136261)
    # The effect forces the pure workload before the ending clock read.
    consumed : Unit <- IO.print("consume=chunk:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=chunk repetitions=" ++ Nat.show(chunk_repetitions())
      ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finished, started))
      ++ " digest=" ++ U32.show(digest))

def run_image_phase(+pixels: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = repeated_image_fingerprint(image_repetitions(), pixels,
      2166136261)
    # The effect forces the pure workload before the ending clock read.
    consumed : Unit <- IO.print("consume=image:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=image repetitions=" ++ Nat.show(image_repetitions())
      ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finished, started))
      ++ " digest=" ++ U32.show(digest))

def main() -> IO(Unit):
  do IO<Unit>:
    check_correctness()
    +pixels : List<&2, U32> = Native.surface(World.chunk(1337n, 0n, 0n))
    run_chunk_phase()
    run_image_phase(pixels)
