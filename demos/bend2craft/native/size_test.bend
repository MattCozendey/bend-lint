import Base
import ./size.bend as Size

# The resolution selector, headless. It is the one part of the client that decides something
# a player chose rather than something a rule answered, so it is tested like a rule: each
# size's cost, the rate the pacing turns that into, the depth the renderer is asked for, the
# flag each size answers to, which flag wins when there are several, and the table a player
# reads.
#
# The rate is divided from the cost field rather than read out of a table, so a cost that
# drifts fails the test instead of quietly disagreeing with a comment.

def require(condition: Bool, message: String) -> IO(Unit):
  match condition:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "size: " ++ message)

def check(condition: Bool, message: String) -> IO(Unit):
  require(condition, message)

def width_is(size: Size.Size, want: U32) -> Bool:
  U32.is_eq(Size.width_of(size), want)

def fits_tick(size: Size.Size) -> Bool:
  U32.is_lt(Size.tenths_of(size), Size.tick_tenths())

# 10000 tenths of a millisecond is 1000 ms, so a frame of `t` tenths allows 10000 / t frames
# a second before the runtime's pacing is considered at all. The 60 is that pacing:
# `window_pace` holds every frame to a 16.666667 ms tick.
def verify_costs.at(+size: Size.Size, want_tenths: U32, want_fps: U32) -> IO(Unit):
  do IO<Unit>:
    Unit <- require(U32.is_eq(Size.tenths_of(size), want_tenths),
      "a size's cost is not the measured one")
    check(U32.is_eq(Size.rate(Size.tenths_of(size)), want_fps),
      "a size's estimated FPS is not 10000 over its cost, capped at the pacing")

# Every size the selector offers fits the tick, the largest included: 1024x1024 used to miss
# it by 31.4 ms and is the row this pins.
def verify_fits(+size: Size.Size) -> IO(Unit):
  check(fits_tick(size), "a size the selector offers does not fit the 16.67 ms tick")

def verify_depths() -> IO(Unit):
  do IO<Unit>:
    Unit <- require(Nat.is_eq(Size.depth_of(Size.size_32()), 5n), "32x32 is not depth 5")
    Unit <- require(Nat.is_eq(Size.depth_of(Size.size_64()), 6n), "64x64 is not depth 6")
    Unit <- require(Nat.is_eq(Size.depth_of(Size.size_128()), 7n), "128x128 is not depth 7")
    Unit <- require(Nat.is_eq(Size.depth_of(Size.size_256()), 8n), "256x256 is not depth 8")
    Unit <- require(Nat.is_eq(Size.depth_of(Size.size_512()), 9n), "512x512 is not depth 9")
    check(Nat.is_eq(Size.depth_of(Size.size_1024()), 10n), "1024x1024 is not depth 10")

# The flag is the bare width. Built from the label it would be `--size=256x256`, which is
# what this pins: the label is padded for the table and neither the pad nor the x belongs in
# something a player types.
def verify_flags() -> IO(Unit):
  do IO<Unit>:
    Unit <- require(String.eq(Size.flag_of(Size.size_32()), "--size=32"), "the 32 flag is wrong")
    Unit <- require(String.eq(Size.flag_of(Size.size_64()), "--size=64"), "the 64 flag is wrong")
    Unit <- require(String.eq(Size.flag_of(Size.size_128()), "--size=128"), "the 128 flag is wrong")
    Unit <- require(String.eq(Size.flag_of(Size.size_256()), "--size=256"), "the 256 flag is wrong")
    Unit <- require(String.eq(Size.flag_of(Size.size_512()), "--size=512"), "the 512 flag is wrong")
    check(String.eq(Size.flag_of(Size.size_1024()), "--size=1024"), "the 1024 flag is wrong")

# A width the client does not offer falls back to the shipped size rather than to nothing, so
# a typo cannot open a window nobody asked for.
def verify_fallback() -> IO(Unit):
  do IO<Unit>:
    Unit <- require(width_is(Size.of_width((32 : U32)), (32 : U32)), "32 did not reach its own size")
    Unit <- require(width_is(Size.of_width((512 : U32)), (512 : U32)), "512 did not reach its own size")
    Unit <- require(width_is(Size.of_width((256 : U32)), (256 : U32)),
      "a known width did not reach its own size")
    check(width_is(Size.of_width((999 : U32)), (128 : U32)),
      "an unknown width did not fall back to 128")

# What the arguments choose: one flag is that size, no flag and a flag nobody offers are the
# shipped size, and a flag among other arguments is still found. More than one flag is a
# mistake rather than a request, and the smallest wins, because a window that misses the tick
# is the one a player cannot un-choose once it is up.
def verify_args() -> IO(Unit):
  do IO<Unit>:
    Unit <- require(width_is(Size.chosen([]), (128 : U32)), "no flag did not choose the shipped size")
    Unit <- require(width_is(Size.chosen(["--size=64"]), (64 : U32)), "--size=64 did not choose 64")
    Unit <- require(width_is(Size.chosen(["--join=host:9", "--size=512"]), (512 : U32)),
      "a flag among other arguments was not found")
    Unit <- require(width_is(Size.chosen(["--size=1024", "--size=256"]), (256 : U32)),
      "the smaller of two flags did not win")
    Unit <- require(width_is(Size.chosen(["--size=32", "--size=1024"]), (32 : U32)),
      "the smaller of two flags did not win, in the other order")
    Unit <- require(width_is(Size.chosen(["--size=999"]), (128 : U32)),
      "a size nobody offers did not fall back to the shipped size")
    check(width_is(Size.chosen(["--size=1024x1024"]), (128 : U32)),
      "the label was taken for the flag")

def table_at_128() -> String:
  "     32x32   1.1 ms   ~60 FPS   fits 60 Hz with 15.6 ms to spare\n"
    ++ "     64x64   1.3 ms   ~60 FPS   fits 60 Hz with 15.4 ms to spare\n"
    ++ "  * 128x128   2.0 ms   ~60 FPS   fits 60 Hz with 14.7 ms to spare\n"
    ++ "    256x256   2.3 ms   ~60 FPS   fits 60 Hz with 14.4 ms to spare\n"
    ++ "    512x512   3.2 ms   ~60 FPS   fits 60 Hz with 13.5 ms to spare\n"
    ++ "    1024x1024   6.1 ms   ~60 FPS   fits 60 Hz with 10.6 ms to spare\n"

# The table is what the player reads: the measured costs are in it, the slack is the tick less
# the cost, and the chosen row is the one marked. The text is held whole, as the table was
# printed before the slack was worked out rather than typed.
def verify_table.at(+chosen: U32) -> IO(Unit):
  do IO<Unit>:
    Unit <- require(String.eq(Size.rows((128 : U32)), table_at_128()),
      "the table is not the one a player was shown")
    +rows : String = Size.rows(chosen)
    Unit <- require(String.contains(rows, "2.0 ms"),
      "the table does not show the measured 128x128 frame cost")
    Unit <- require(String.contains(rows, "6.1 ms"),
      "the table does not show the measured 1024x1024 frame cost")
    marked : String = Size.row(Size.of_width(chosen), chosen)
    check(String.contains(marked, "* "), "the chosen row is not the one marked")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- verify_costs.at(Size.size_32(), (11 : U32), (60 : U32))
    Unit <- verify_costs.at(Size.size_64(), (13 : U32), (60 : U32))
    Unit <- verify_costs.at(Size.size_128(), (20 : U32), (60 : U32))
    Unit <- verify_costs.at(Size.size_256(), (23 : U32), (60 : U32))
    Unit <- verify_costs.at(Size.size_512(), (32 : U32), (60 : U32))
    Unit <- verify_costs.at(Size.size_1024(), (61 : U32), (60 : U32))
    Unit <- verify_fits(Size.size_512())
    Unit <- verify_fits(Size.size_1024())
    Unit <- verify_depths()
    Unit <- verify_flags()
    Unit <- verify_fallback()
    Unit <- verify_args()
    Unit <- verify_table.at((128 : U32))
    Unit <- verify_table.at((32 : U32))
    Unit <- verify_table.at((256 : U32))
    IO.print("size: costs, depths, flags, the flag among arguments, fallback and the table passed")

#|size: costs, depths, flags, the flag among arguments, fallback and the table passed
