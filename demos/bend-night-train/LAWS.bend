# LAWS.bend -- the laws of the night-train renderer.
#
# This file is the human's.  It states what must never break, in a form the
# compiler can check; PROOF.bend is where those claims are discharged.  The
# gate is `bend PROOF.bend`, which must print "All terms check."
#
# Read docs/laws.md for what is deliberately NOT here: F32 is opaque to the
# checker (every F32 operation is a law with no definition), so no law below
# can mention a pixel's colour, a camera position or a track coordinate.
# What can be stated and proven is the structure -- and the structure is
# where this program's parallelism lives.
#
# The structure is the tile frame, not the old one-pixel ray marcher: a leaf
# of `Shape.frame` is an 8x8 tile.  Frame depth `d` is the renderer's depth;
# `Shape.frame.at(d)` shaves the fixed tile levels exactly as `Raster.frame`
# does before `Frame.build`.
import Base
import ./src/scene.bend as Scene
import ./src/shape.bend as Shape

# LAW: the consist walks exactly the slots it claims to.  The carriage
# geometry is F32 and out of reach, but an off-by-one in the index sequence
# -- one too many cars, or one too few -- is a checked error here.
law consist_slots:
  for k: Nat
  {List.length(&2, Nat, Scene.slots(k)) == k : Nat}

# LAW: splitting the frame into its four parallel quadrants loses no pixel
# and invents none.  This is the law the scheduler relies on: the four-way
# parallel call is only sound because the join reassembles exactly the
# pixels that were handed out.  It holds for any four subtrees, not only the
# ones `frame` builds.
law quad_pixels:
  for a: Shape.Frame
  for b: Shape.Frame
  for c: Shape.Frame
  for e: Shape.Frame
  {Shape.pixels(Shape.Quad{a, b, c, e}) == Nat.add(Shape.pixels(a), Nat.add(Shape.pixels(b), Nat.add(Shape.pixels(c), Shape.pixels(e)))) : Nat}

# LAW: an 8x8 frame is exactly 64 pixels, owned by one tile.  Stated at frame
# depth 3 (the tile's own depth), a size the checker evaluates outright, so a
# change to the tile's side or to the depth shaving fails here rather than in
# a picture.
law frame8:
  {Shape.pixels(Shape.frame.at(3n)) == 64n : Nat}

# LAW: at frame depth d the tree is exactly 4^(d-3) tiles.  Evaluated outright
# at depth 6: 4^3 = 64.  A change to the four-way split or to the depth
# shaving that drops or duplicates a subtree fails here.
law frame_tiles:
  {Shape.tiles(Shape.frame.at(6n)) == Nat.pow(4n, 3n) : Nat}

# LAW: the frame covers exactly 2^d x 2^d pixels -- a tile is Tile.side()
# squared, and the four-way join neither loses nor invents.  Evaluated
# outright at depth 6: 64 x 64 = 4096.
law frame_pixels:
  {Shape.pixels(Shape.frame.at(6n)) == Nat.mul(Nat.pow(2n, 6n), Nat.pow(2n, 6n)) : Nat}
