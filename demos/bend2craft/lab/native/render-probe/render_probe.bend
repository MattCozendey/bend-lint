import Base
import ../../../world/world.bend as World

def chunk_index(+x: U32, +z: U32, +y: U32) -> U32:
  +size = U32.from_nat(World.chunk_size())
  (x + z * size + y * size * size : U32)

def chunk_area() -> Nat:
  Nat.mul(World.chunk_size(), World.chunk_size())

# The chunk array is affine; copy its U32 leaves so each image branch can read them.
def share_blocks(blocks: List<&1, U32>) -> List<&2, U32>:
  match blocks:
    case Nil{}:
      []
    case +block <> rest:
      block <> share_blocks(rest)

def surface_fill(
  remaining: Nat, +index: Nat, blocks: List<&2, U32>,
  +surfaces: List<&2, U32>
) -> List<&2, U32>:
  match remaining:
    case 0n:
      surfaces
    case 1n++p:
      match blocks:
        case Nil{}:
          surfaces
        case +block <> rest:
          # Scanning y-major lets each solid block replace the lower surface.
          +column = Nat.mod(index, chunk_area())
          updated = Bool.pick(List<&2, U32>, U32.is_ne(block, 0),
            List.set(&2, U32, surfaces, column, block), surfaces)
          surface_fill(p, Nat.add(index, 1n), rest, updated)

def surface_map(blocks: List<&2, U32>) -> List<&2, U32>:
  surface_fill(
    Nat.mul(World.max_y(), chunk_area()), 0n, blocks,
    List.replicate(U32, chunk_area(), 0)
  )

def block_color(+block: U32) -> U32:
  Bool.pick(U32, U32.is_eq(block, 1), 7370367,
    Bool.pick(U32, U32.is_eq(block, 2), 7951674,
      Bool.pick(U32, U32.is_eq(block, 3), 5875274,
        Bool.pick(U32, U32.is_eq(block, 4), 3705667,
          Bool.pick(U32, U32.is_eq(block, 5), 8082480,
            Bool.pick(U32, U32.is_eq(block, 6), 13812341,
              Bool.pick(U32, U32.is_eq(block, 7), 3831748,
                Bool.pick(U32, U32.is_eq(block, 8), 3289655,
                  Bool.pick(U32, U32.is_eq(block, 9), 11631194,
                    Bool.pick(U32, U32.is_eq(block, 10), 3594458,
                       Bool.pick(U32, U32.is_eq(block, 0), 1842204, 11184810)))))))))))

def surface_block(
  +pixels: List<&2, U32>, +x: U32, +z: U32, remaining_y: Nat
) -> U32:
  match remaining_y:
    case 0n:
      0
    case 1n++p:
      +block = Maybe.default(&2, U32,
        List.get(&2, U32, pixels,
          U32.to_nat(chunk_index(x, z, U32.from_nat(p)))), 0)
      Bool.pick(U32, U32.is_eq(block, 0),
        surface_block(pixels, x, z, p), block)

def draw(
  +depth: Nat, +x: U32, +z: U32, +pixels: List<&2, U32>
) -> Image:
  match depth:
    case 0n:
      Pix{block_color(surface_block(pixels, x, z, World.max_y()))}
    case 1n++p:
      +half = U32.shln(1, p)
      tl tr bl br = draw(p, x, z, pixels)
        draw(p, (x + half : U32), z, pixels)
        draw(p, x, (z + half : U32), pixels)
        draw(p, (x + half : U32), (z + half : U32), pixels)
      Qua{tl, tr, bl, br}

def fingerprint_step(+hash: U32, +color: U32) -> U32:
  U32.mul(U32.xor(hash, color), 16777619)

def fingerprint_go(image: Image, +hash: U32) -> U32:
  match image:
    case Pix{color}:
      fingerprint_step(hash, color)
    case Qua{tl, tr, bl, br}:
      +a = fingerprint_go(tl, hash)
      +b = fingerprint_go(tr, a)
      +c = fingerprint_go(bl, b)
      fingerprint_go(br, c)

def fingerprint(image: Image) -> U32:
  fingerprint_go(image, 2166136261)

def overhead(chunk: Array<U32>) -> Image:
  draw(4n, 0, 0, surface_map(share_blocks(Array.to_list(~U32, chunk))))
