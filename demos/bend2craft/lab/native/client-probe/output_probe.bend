import Base

# ---------------------------------------------------------------------------
# The output stage's floor, at every depth the client could ship.
#
# `Window.frame` takes an `Image`, and the runtime fills the pixmap by walking that tree
# in C (`window_sq` in `effs/window.c`), so a frame of `2^depth` square is one `Pix` per
# pixel and one `Qua` per four of them. Both halves are built in Bend, in `face_image`,
# and both are released in Bend, in `Image.drop`. Neither depends on the world: no face,
# no projection, no bucket and no walk is involved, and no renderer change reaches them.
#
# So this is the floor under every resolution the client can ship. If the floor at a
# depth does not fit the 16.67 ms tick, no amount of work on the renderer puts that
# depth inside the tick, and that is worth knowing before the renderer is touched.
#
# The tree is built here in one colour so the phase times the shape of the output and
# nothing else. `levels` is the number of `Qua` levels: a tree with `depth - levels`
# levels missing is what a frame whose regions are uniform at `2^(depth-levels)` pixels
# would cost, because `window_sq` fills a whole `s x s` block from a single `Pix`. The
# shipping renderer builds every pixel, which is `levels = depth`.
# ---------------------------------------------------------------------------

def fold_hash(+hash: U32, +value: U32) -> U32:
  U32.mul(U32.xor(hash, value), 16777619)

# The root's colour, so a built image is read rather than argued away. The other three
# quadrants are not read: a drop is a drop.
def root_color(image: Image) -> U32:
  match image:
    case Pix{color}:
      color
    case Qua{tl, _, _, _}:
      root_color(tl)

# The sky, which is what a frame with no world in it paints.
def sky_color() -> U32:
  4278190335

# `face_image`'s own shape, with the per-pixel colour answer replaced by a constant.
def const_image(+levels: Nat, +px: U32, +py: U32, +color: U32) -> Image:
  match levels:
    case 0n:
      Pix{color}
    case 1n+q:
      +step = U32.shln((1 : U32), q)
      tl tr bl br = const_image(q, px, py, color)
        const_image(q, (px + step : U32), py, color)
        const_image(q, px, (py + step : U32), color)
        const_image(q, (px + step : U32), (py + step : U32), color)
      Qua{tl, tr, bl, br}

# Build and release: what a frame pays for its own pixels, which is what the runtime's
# `window_show` then walks in C and `Image.drop` then walks again in Bend.
def drop_step(+levels: Nat, +hash: U32) -> U32:
  +image = const_image(levels, 0, 0, sky_color())
  +digest : U32 = root_color(image)
  released : Unit = Image.drop(image)
  fold_hash(hash, digest)

# Build and keep, without the release walk. The difference from the phase above is the
# release's own cost, at the same shape and the same depth. `Image.sink` consumes the
# image and frees nothing, so this phase trades memory for the measurement; it is only
# run at the depths where the tree is small enough for that to be honest.
def sink_step(+levels: Nat, +hash: U32) -> U32:
  +image = const_image(levels, 0, 0, sky_color())
  +digest : U32 = root_color(image)
  sunk : Unit = Image.sink(image)
  fold_hash(hash, digest)

def drop.go(remaining: Nat, +levels: Nat, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      drop.go(p, levels, drop_step(levels, hash))

def sink.go(remaining: Nat, +levels: Nat, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      sink.go(p, levels, sink_step(levels, hash))

# The nodes a tree of this many levels holds: one `Qua` per four leaves and one `Pix`
# per leaf. Printed so a phase's cost can be divided by what it built.
def quads(leaves: Nat) -> Nat:
  Nat.div(Nat.sub(leaves, 1n), 3n)

def power_of_four(level: Nat) -> Nat:
  U32.to_nat(U32.shln((1 : U32), Nat.mul(2n, level)))

def phase_line(name: String, +depth: Nat, +levels: Nat, +iterations: Nat, started: Nat,
  finished: Nat, +digest: U32) -> String:
  "phase=" ++ name ++ " depth=" ++ Nat.show(depth) ++ " size=" ++ Nat.show(power_of_four(depth))
    ++ " levels=" ++ Nat.show(levels) ++ " leaves=" ++ Nat.show(power_of_four(levels))
    ++ " quads=" ++ Nat.show(quads(power_of_four(levels)))
    ++ " iterations=" ++ Nat.show(iterations)
    ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finished, started))
    ++ " digest=" ++ U32.show(digest)

def phase_digest(release: Bool, +levels: Nat, +iterations: Nat) -> IO(U32):
  match release:
    case True{}:
      IO.pure(U32, drop.go(iterations, levels, 2166136261))
    case False{}:
      IO.pure(U32, sink.go(iterations, levels, 2166136261))

def phase(+name: String, +depth: Nat, +levels: Nat, +iterations: Nat, release: Bool) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- phase_digest(release, levels, iterations)
    consumed : Unit <- IO.print("consume=" ++ name ++ ":" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line(name, depth, levels, iterations, started, finished, digest))

def main() -> IO(Unit):
  do IO<Unit>:
    # 32x32, 64x64, 128x128, 256x256, 512x512 and 1024x1024, each built and released.
    a : Unit <- phase("output_drop", 5n, 5n, 40n, True{})
    b : Unit <- phase("output_drop", 6n, 6n, 20n, True{})
    c : Unit <- phase("output_drop", 7n, 7n, 10n, True{})
    d : Unit <- phase("output_drop", 8n, 8n, 6n, True{})
    e : Unit <- phase("output_drop", 9n, 9n, 3n, True{})
    f : Unit <- phase("output_drop", 10n, 10n, 2n, True{})
    # The same trees without the release walk, to separate building from releasing.
    g : Unit <- phase("output_keep", 7n, 7n, 10n, False{})
    h : Unit <- phase("output_keep", 8n, 8n, 6n, False{})
    i : Unit <- phase("output_keep", 9n, 9n, 3n, False{})
    j : Unit <- phase("output_keep", 10n, 10n, 2n, False{})
    # A frame whose regions are uniform at 16 pixels, and at 4: what the output costs
    # when the picture compresses, which is the shape a hierarchical renderer would aim
    # at. The full tree at each depth is the line above it.
    k : Unit <- phase("output_keep", 8n, 6n, 20n, False{})
    l : Unit <- phase("output_keep", 9n, 7n, 20n, False{})
    m : Unit <- phase("output_keep", 10n, 8n, 20n, False{})
    n : Unit <- phase("output_keep", 10n, 9n, 8n, False{})
    IO.print("output-probe=pass")