# The frame shown: its palette indices folded through the one of
# PLAYPAL's fourteen palettes the renderer named, into the window's
# image quadtree. A cell is four pixels a side, and cell
# row r shows frame row 5r/6, so the frame's 200 rows fill 240 cell rows
# of the 1280 by 960 window: Doom's 320 by 200 at the 4:3 of the monitor
# it was drawn for, by nearest neighbour.
import Base
import ./bytes.bend as B
import ./gfx.bend as G

# The fold's work: a quadrant to visit (skipped when off the window),
# or the join of the last four images into one.
type Show.Task is Data:
  Visit{off: Bool, d: Nat, x: U32, y: U32}
  Join{}

type Show.State is Type:
  State{mem: Array<U32>, tasks: List<&2, Show.Task>, images: List<&2, Image>}

def Show.off(+x: U32, +y: U32) -> Bool:
  Bool.or(U32.is_ge(x, 1280), U32.is_ge(y, 960))

def Show.visit(+e: Nat, +x: U32, +y: U32) -> Show.Task:
  Visit{Show.off(x, y), e, x, y}

def Show.leaf.rgb(tasks: List<&2, Show.Task>, images: List<&2, Image>, p: Array<U32> & U32) ->
  Show.State:
  (mem, rgb) = p
  State{mem, tasks, Pix{rgb} <> images}

def Show.colour.of(+pal: U32, p: Array<U32> & U32) -> Array<U32> & U32:
  (mem, index) = p
  B.Bytes.at(mem, (G.Gfx.palette() + pal * 256 + index : U32))

# Frame pixel i's colour, 0xRRGGBB, through the palette in force.
def Show.colour(+pal: U32, mem: Array<U32>, +i: U32) -> Array<U32> & U32:
  Show.colour.of(pal, B.Bytes.at(mem, (G.Gfx.frame() + i : U32)))

# Each index's entry in the palette in force.
def Show.rgb.offs(+pal: U32, xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case []:
      []
    case +x <> rest:
      (G.Gfx.palette() + pal * 256 + x : U32) <> Show.rgb.offs(pal, rest)

def Show.rgb.of(+pal: U32, p: Array<U32> & List<&2, U32>) -> Array<U32> & List<&2, U32>:
  (mem, xs) = p
  B.Bytes.each(~U32, ~B.Bytes.at, Show.rgb.offs(pal, xs), mem)

# The whole frame's colours, in order: what the film prints. The
# indices are read, then the entries they name, since a read planned by
# its offsets is the one loop over the array there is.
def Show.rgb(p: Array<U32> & U32) -> Array<U32> & List<&2, U32>:
  (mem, +pal) = p
  Show.rgb.of(pal, B.Bytes.each(~U32, ~B.Bytes.at,
    B.Bytes.fields(U32.to_nat(64000), G.Gfx.frame(), 1, [0]), mem))

# The cell at window pixel x, y: its frame pixel's colour.
def Show.leaf(+pal: U32, mem: Array<U32>, x: U32, y: U32, tasks: List<&2, Show.Task>,
  images: List<&2, Image>) -> Show.State:
  Show.leaf.rgb(tasks, images, Show.colour(pal, mem, (((y >> 2n) * 5 / 6) * 320 + (x >> 2n) : U32)))

def Show.quad.if(same: Bool, tl: Image, tr: Image, bl: Image, br: Image) -> Image:
  match same:
    case True{}:
      tl
    case False{}:
      Qua{tl, tr, bl, br}

# Four quadrants as one image: a single pixel when all four are one
# colour, since the window's fill pays for every level it descends, and
# a flat stretch of wall, floor or status bar is many quadrants of one
# colour.
def Show.quad(tl: Image, tr: Image, bl: Image, br: Image) -> Image:
  match tl tr bl br:
    case Pix{+a} Pix{+b} Pix{+c} Pix{+d}:
      Show.quad.if(Bool.and(U32.is_eq(a, b), Bool.and(U32.is_eq(a, c), U32.is_eq(a, d))), Pix{a}, Pix{b},
        Pix{c}, Pix{d})
    case tl tr bl br:
      Qua{tl, tr, bl, br}

def Show.join(mem: Array<U32>, tasks: List<&2, Show.Task>, images: List<&2, Image>) -> Show.State:
  match images:
    case br <> bl <> tr <> tl <> rest:
      State{mem, tasks, Show.quad(tl, tr, bl, br) <> rest}
    case _:
      State{mem, tasks, images}

def Show.done(images: List<&2, Image>) -> Image:
  match images:
    case []:
      Pix{0}
    case img <> rest:
      img

# The quadtree from the frame, with an explicit stack since the array
# has one owner: a quadrant of depth d covers 2^d pixels a side, a cell
# of depth 2 is one frame pixel, and a quadrant off the window is one
# black pixel.
def Show.fold(fuel: Nat, +pal: U32, st: Show.State) -> Array<U32> & Image:
  match fuel:
    case 0n:
      State{mem, tasks, images} = st
      (mem, Show.done(images))
    case 1n+f:
      match st:
        case State{mem, [], images}:
          (mem, Show.done(images))
        case State{mem, Join{} <> rest, images}:
          Show.fold(f, pal, Show.join(mem, rest, images))
        case State{mem, Visit{True{}, d, x, y} <> rest, images}:
          Show.fold(f, pal, State{mem, rest, Pix{0} <> images})
        case State{mem, Visit{False{}, 0n, x, y} <> rest, images}:
          Show.fold(f, pal, State{mem, rest, Pix{0} <> images})
        case State{mem, Visit{False{}, 1n, x, y} <> rest, images}:
          Show.fold(f, pal, State{mem, rest, Pix{0} <> images})
        case State{mem, Visit{False{}, 2n, x, y} <> rest, images}:
          Show.fold(f, pal, Show.leaf(pal, mem, x, y, rest, images))
        case State{mem, Visit{False{}, 3n++e, +x, +y} <> rest, images}:
          +h = U32.shln(1, 2n+e)
          Show.fold(f, pal, State{mem, Show.visit(2n+e, x, y) <> Show.visit(2n+e, (x + h : U32), y)
            <> Show.visit(2n+e, x, (y + h : U32)) <> Show.visit(2n+e, (x + h : U32), (y + h : U32))
            <> Join{} <> rest, images})

# The window's image of the frame the renderer answered, and the array
# back.
def Show.image(p: Array<U32> & U32) -> Array<U32> & Image:
  (mem, +pal) = p
  Show.fold(U32.to_nat(400000), pal, State{mem, [Show.visit(11n, 0, 0)], []})
