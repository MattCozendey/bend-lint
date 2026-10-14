import Base

# The window's size, chosen before it opens, and the table that says what each choice costs.
#
# What bounds a window is the pinned runtime rather than the renderer. `window_pace` in the
# runtime's `effs/window.c` sleeps every presented frame to the next 16.67 ms tick, so the
# client is capped at 60 Hz however fast the frame is, and `vendor/bend` is not ours to edit.
# What is ours is the frame cost, and therefore how large a window fits inside the cap.
# `lab/native/paint/run.sh` re-measures it and `lab/native/client-probe/run-fps.sh` measures
# the live loop; both are recorded in `lab/native/paint/README.md`.
#
# Bend 2.0.32 cannot read a key from a terminal. `IO` offers `print`, `args`, `get_env`,
# `sleep`, `now`, `thread_count` and `random_u32`, and nothing that reads stdin, so a
# selector that waited for a keystroke would wait forever. The choice therefore comes from
# `IO.args()` as `--size=<n>`, and it is echoed to stdout before the window opens.

# A size is its width, the depth of the frame's quadtree (the window and the image it is asked
# for cannot disagree about how big they are), and the cost of one client frame in tenths of
# a millisecond: the precision the measurement has, and the only one Bend can hold without a
# float. The label and the slack the table shows are worked out from these.
type Size is Data:
  Size{width: U32, depth: Nat, tenths: U32}

# The costs are the client's own frame — over its five-by-five view region from the spawn
# pose, lit, through the air, under the sky's clouds and sun — on the machine named in
# `lab/native/2026-09-30-native-renderer-investigation.md`, native C, `--gpu off`, on the
# eight threads the runtime starts by default there. Every row is the `client` phase of
# `lab/native/paint/run.sh` (medians of five samples) plus the measured 0.03 ms tick, so the
# rows are comparable to each other.
#
#   size    draw      + tick     tenths
#    32     1.07      1.10        11
#    64     1.30      1.33        13
#   128     1.98      2.01        20
#   256     2.25      2.28        23
#   512     3.17      3.20        32
#  1024     6.10      6.13        61
#
# The spawn is inside a house, facing a wall, which is the cheapest frame there is. The
# dearest measured is from open ground looking down across the terrain: 8.47 ms at 1024.
# The part of a row that does not shrink with the window is the front half of a frame: the
# chunks that can be seen have their faces found and projected, each chunk its own task, and
# the polygons are put in order by counting. From the spawn it is under a millisecond and
# looking across open ground a millisecond and a half. The rest is a division, a texel, its
# light and its air for every pixel a face is seen in, once.
def size_32() -> Size:
  Size{(32 : U32), 5n, (11 : U32)}

def size_64() -> Size:
  Size{(64 : U32), 6n, (13 : U32)}

def size_128() -> Size:
  Size{(128 : U32), 7n, (20 : U32)}

def size_256() -> Size:
  Size{(256 : U32), 8n, (23 : U32)}

def size_512() -> Size:
  Size{(512 : U32), 9n, (32 : U32)}

def size_1024() -> Size:
  Size{(1024 : U32), 10n, (61 : U32)}

def width_of(+size: Size) -> U32:
  Size{width, depth, tenths} = size
  width

def depth_of(size: Size) -> Nat:
  Size{width, depth, tenths} = size
  depth

def tenths_of(size: Size) -> U32:
  Size{width, depth, tenths} = size
  tenths

# Smallest first: the bill gets worse as the window grows, so a reader scanning down the
# table sees the cost rise.
#
# The thread count is the runtime's, read before `main`, and the client's frame is measured
# at each. One frame, in milliseconds, from `lab/native/paint/run.sh`:
#
#   size    1 thread    2 threads    4 threads    8 threads
#    128       1.55        1.52         1.68         1.98
#    256       2.90        2.23         2.12         2.25
#    512       7.55        4.83         3.62         3.17
#   1024      24.52       13.93         8.40         6.10
#
# **1024 needs the pool.** On one thread it is 24.52 ms at the spawn and 27.20 looking down
# across open ground, which miss the tick; on two it is 13.93 at the spawn and 16.25 looking
# down, which is within half a millisecond of it; on four or eight it fits everywhere it was
# measured. The epilogue says so. Every other size fits at every count. A small window has
# few tiles to share out and pays for waking the pool; at 1024 the tiles are the work and
# the pool divides it.
def sizes() -> List<&2, Size>:
  [size_32(), size_64(), size_128(), size_256(), size_512(), size_1024()]

# --- the table ---------------------------------------------------------------
#
# `rate` divides out the rate the work allows and then caps it at what the pacing allows, so
# a 4.1 ms frame reads as 60 and not as 244: the cap is what a player actually sees.

def tick_tenths() -> U32:
  167

# 16.666667 ms is the runtime's own pacing interval, and 1000 ms over it is 60 frames a
# second. The literal is the ceiling rather than a division because 10000 / 167 truncates to
# 59, and quoting the pacing a player actually gets is better than quoting the floor of a
# rounded interval.
def fps_ceiling() -> U32:
  60

# 1000 ms in a second over tenths of a millisecond is 10000 / tenths: the rate the work
# allows. The pacing then holds the frame to the tick, so the rate a player sees is the
# smaller of the two.
def rate(tenths: U32) -> U32:
  U32.min(U32.div((10000 : U32), tenths), fps_ceiling())

def ms_text.at(whole: U32, tenth: U32) -> String:
  U32.show(whole) ++ "." ++ U32.show(tenth)

# `tenths` is shared rather than linear because the figure needs both halves of the
# division and a value is spent once. There is no `U32.divmod` to read it in one go: the
# prelude only exposes `U32.div` and `U32.mod`, and each of those spends its argument.
def ms_text(+tenths: U32) -> String:
  ms_text.at(U32.div(tenths, (10 : U32)), U32.mod(tenths, (10 : U32)))

# The label is padded to a fixed column so the costs line up, which is why a two-digit width
# gets a space in front. The flag is built from the width and not from this, so neither the
# pad nor the x reaches something a player types.
def label_of(+width: U32) -> String:
  Bool.pick(String, U32.is_lt(width, 100), " ", "") ++ U32.show(width) ++ "x" ++ U32.show(width)

# What a size does to the tick, from its cost: the time left over, or the time missed by.
def note_of(+tenths: U32) -> String:
  Bool.pick(String, U32.is_lt(tenths, tick_tenths()),
    "fits 60 Hz with " ++ ms_text(U32.sub(tick_tenths(), U32.min(tenths, tick_tenths()))) ++ " ms to spare",
    "misses 60 Hz by " ++ ms_text(U32.sub(tenths, U32.min(tenths, tick_tenths()))) ++ " ms")

def row.at(chosen: Bool, label: String, ms: String, fps: U32, note: String) -> String:
  Bool.pick(String, chosen, "  * ", "    ") ++ label ++ "   " ++ ms ++ " ms   ~"
    ++ U32.show(fps) ++ " FPS   " ++ note ++ "\n"

# The chosen row is marked in place rather than moved to the top, so the table a player
# reads is the table the measurement produced.
def row(size: Size, chosen: U32) -> String:
  Size{+width, _, +tenths} = size
  row.at(U32.is_eq(width, chosen), label_of(width), ms_text(tenths), rate(tenths), note_of(tenths))

def rows.at(sizes: List<&2, Size>, +chosen: U32) -> String:
  match sizes:
    case Nil{}:
      ""
    case size <> rest:
      row(size, chosen) ++ rows.at(rest, chosen)

def rows(chosen: U32) -> String:
  rows.at(sizes(), chosen)

def headline() -> String:
  "Bend2Craft native - resolution\n"
    ++ "  The runtime paces every presented frame to a 16.67 ms tick, so 60 FPS is the\n"
    ++ "  ceiling and not a budget. Costs are measured at the client's own spawn\n"
    ++ "  camera, native C target, --gpu off, 8 threads.\n\n"

def epilogue() -> String:
  "\n  Pass --size=32, --size=64, --size=128, --size=256, --size=512 or --size=1024."
    ++ " Default 128.\n  1024 needs the default thread pool: on --threads 1 it is 24.5 ms a"
    ++ " frame.\n"

# What is printed before the window opens, with the size the player chose marked.
def table(chosen: U32) -> String:
  headline() ++ rows(chosen) ++ epilogue()

# --- choosing the size -------------------------------------------------------
#
# The set of valid sizes is closed, so a flag is recognised by being exactly one of them
# rather than by parsing a number and range-checking it. A closed set has no invalid member
# to reject, and comparing a string is exact where a hand-written digit parser is one more
# thing to get wrong.

# The flag is the bare width, not the label.
def flag_at(+width: U32) -> String:
  "--size=" ++ U32.show(width)

def flag_of(size: Size) -> String:
  flag_at(width_of(size))

# No size.
def unchosen() -> U32:
  (4294967295 : U32)

# The width one argument asks for, or `unchosen` when it asks for none.
def asked(sizes: List<&2, Size>, +arg: String) -> U32:
  match sizes:
    case Nil{}:
      unchosen()
    case Size{+width, depth, tenths} <> rest:
      Bool.pick(U32, String.eq(arg, flag_at(width)), width, asked(rest, arg))

# More than one flag is a mistake rather than a request, and the smallest wins because a
# window that misses the tick is the one a player cannot un-choose once the window is up.
def smallest(args: List<&1, String>, +best: U32) -> U32:
  match args:
    case Nil{}:
      best
    case +arg <> rest:
      smallest(rest, U32.min(best, asked(sizes(), arg)))

# A width with no size here is 128: the shipped size, and the only one measured as a whole
# frame rather than as a render plus a tick.
def of_width.among(sizes: List<&2, Size>, +width: U32) -> Size:
  match sizes:
    case Nil{}:
      size_128()
    case +size <> rest:
      Bool.pick(Size, U32.is_eq(width_of(size), width), size, of_width.among(rest, width))

def of_width(width: U32) -> Size:
  of_width.among(sizes(), width)

# The size the arguments choose.
def chosen(args: List<&1, String>) -> Size:
  of_width(smallest(args, unchosen()))

def from_args() -> IO(Size):
  do IO<Size>:
    args : List<&1, String> <- IO.args()
    return chosen(args)
