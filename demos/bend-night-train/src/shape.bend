# shape: the frame's structure without its pixels.
#
# F32 is opaque to Bend's checker: every F32 operation is a `law` with no
# definition, so no equation about a rendered colour or a camera position can
# be proven.  What is provable is the shape of the tree the renderer builds --
# and that is where the parallel split lives, so the laws about the frame are
# stated here, on the same recursion the renderer uses.
#
# This mirrors `Raster.Frame` and `Frame.build`, not the old ray marcher's
# one-pixel `Image`: a leaf owns a TILE x TILE block of pixels, not one pixel.
# Only the parallel decomposition is reproduced -- a node is a four-way join
# and shaves one level of depth per split; the triangle lists and the screen
# boxes that `Frame.build` filters are dropped, because a count law does not
# need them and none of them is computable over opaque F32.
import Base

# The leaf's pixel block, `Tile.side()` pixels on a side.  `Tile.levels()` is
# the fixed depth reserved for a tile: the tree's own depth is the frame depth
# minus it, exactly as in `Raster`.  Duplicated rather than imported so the
# skeleton stays free of F32.
def Tile.side() -> Nat:
  8n

def Tile.levels() -> Nat:
  3n

def Nat.tile.levels(+d: Nat) -> Nat:
  Nat.sub(d, Tile.levels())

# A tile of pixels, or four children: the same two cases as `Raster.Frame`.
type Frame is Data:
  Tile{px: U32}
  Quad{a: Frame, b: Frame, c: Frame, d: Frame}

# The tree's skeleton over its own depth (the depth `Frame.build` recurses
# on), painting 0 instead of shading a tile.  Nothing here calls F32.
def frame(+d: Nat) -> Frame:
  match d:
    case 0n:
      Tile{0}
    case 1n+e:
      a b c d = frame(e) frame(e) frame(e) frame(e)
      Quad{a, b, c, d}

# The tree at the renderer's frame depth `d`, shaving the tile's fixed levels
# the same way `Raster.frame` does before it calls `Frame.build`.
def frame.at(+d: Nat) -> Frame:
  frame(Nat.tile.levels(d))

# How many tiles the tree holds.
def tiles(+f: Frame) -> Nat:
  match f:
    case Tile{px}:
      1n
    case Quad{a, b, c, d}:
      Nat.add(tiles(a),
        Nat.add(tiles(b), Nat.add(tiles(c),
          tiles(d))))

# How many pixels the tree covers: a tile is `Tile.side()` squared.
def pixels(+f: Frame) -> Nat:
  match f:
    case Tile{px}:
      Nat.mul(Tile.side(), Tile.side())
    case Quad{a, b, c, d}:
      Nat.add(pixels(a),
        Nat.add(pixels(b), Nat.add(pixels(c),
          pixels(d))))
