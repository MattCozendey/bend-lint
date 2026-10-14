import Base
import ./frame.bend as Frame

# The F3 toggle, folded the way the tick folds it: a key is an edge, not a level.
#
# `native/debug_test.bend` proves what the overlay draws and that it reaches the frame.
# This proves the rule that opens it, which is the part a picture cannot show: a held F3
# must flip it once and not sixty times a second, and a tick without F3 in it must leave
# it exactly as it was.

def check(passed: Bool, message: String) -> IO(Unit):
  match passed:
    case True{}:
      IO.print("ok " ++ message)
    case False{}:
      IO.die(Unit, 1, "debug_toggle FAILED: " ++ message)

# The tick's own rule for the overlay, applied to a mask that went down and came up.
# The overlay's next state, in the exact shape `Play.tick.folded` computes it: an affine
# pair of masks read twice, so this is the same rule rather than a restatement of it.
def shown_after(+previous: U32, +keys: U32, was: Bool) -> Bool:
  Bool.pick(Bool, was, Bool.not(Frame.wants_debug(previous, keys)),
    Frame.wants_debug(previous, keys))

def main() -> IO(Unit):
  do IO<Unit>:
    +bit : U32 = Frame.key_bit(Frame.debug_code())
    # A press is an edge: down now, up in the mask the tick started from.
    Unit <- check(Frame.wants_debug(0, bit), "a press of F3 asks for the overlay")
    # Held into the next tick, the same bit is not an edge: the mask it is read against
    # already has it, so the overlay does not flicker sixty times a second.
    Unit <- check(Bool.not(Frame.wants_debug(bit, bit)), "a held F3 is not another press")
    # And the client's own answer flips once and stays.
    Unit <- check(shown_after(0, bit, False{}), "the overlay comes on")
    Unit <- check(shown_after(bit, bit, True{}), "and a held key leaves it on")
    # A tick with no F3 in it leaves the overlay alone, either way round.
    Unit <- check(Bool.not(shown_after(bit, 32, False{})), "another key leaves it off")
    Unit <- check(shown_after(bit, 32, True{}), "and leaves it on")
    IO.print("debug_toggle ok")