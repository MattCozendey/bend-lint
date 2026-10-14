# PROOF.bend -- the proofs of LAWS.bend.
#
# Every def here fills the law of the same name.  `bend PROOF.bend` fails
# while any law is open or false and prints "All terms check." once every
# one holds.  This file is the AI's side of the bargain: the claims above are
# not negotiable, only the proofs are.
import Base
import ./LAWS.bend as Laws
import ./src/scene.bend as Scene
import ./src/shape.bend as Shape

# Induction on k.  `slots(1n+p)` is the cons `p <> slots(p)`, and
# `List.length` of a cons is `1n + length(tail)` by definition, so the step
# is the induction hypothesis followed by reflexivity.
def Laws.consist_slots(k):
  match k:
    case 0n:
      {==}
    case 1n+p:
      %Laws.consist_slots(p) : {1n+List.length(&2, Nat, Scene.slots(p))
        == 1n+_ : Nat}
      {==}

# True by computation: both sides are the same four-way sum.
def Laws.quad_pixels(a, b, c, e):
  {==}

# True by computation: the checker normalises the depth-3 frame to its single
# tile and unfolds `Tile.side()` into the tile's pixel count.
def Laws.frame8():
  {==}

# True by computation: the checker normalises the depth-6 tree to 64 tiles.
def Laws.frame_tiles():
  {==}

# True by computation: the checker normalises the depth-6 tree, counts its 64
# tiles at 64 pixels each, and reduces `Nat.pow(2n, 6n)` to the same number.
def Laws.frame_pixels():
  {==}
