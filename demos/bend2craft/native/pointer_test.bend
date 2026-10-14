import Base
import ./pointer.bend as Pointer
import ./frame.bend as Frame

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, message)

def same(+a: F32, +b: F32) -> Bool:
  Bool.and(F32.is_le(a, b), F32.is_ge(a, b))

# --- the host's lines ---------------------------------------------------------
#
# `native/pointer-host.ps1` writes one `dx dy` per displacement, so a frame's text is zero or
# more lines and the frame's movement is their sum.

def check_delta(+label: String, text: String, +dx: F32, +dy: F32) -> IO(Unit):
  +delta : Pointer.Delta = Pointer.delta(text)
  do IO<Unit>:
    Unit <- check(same(Pointer.delta_x(delta), dx), label ++ ": the dx is wrong")
    check(same(Pointer.delta_y(delta), dy), label ++ ": the dy is wrong")

def lines_are_summed() -> IO(Unit):
  do IO<Unit>:
    Unit <- check_delta("no line", "", 0.0, 0.0)
    Unit <- check_delta("one line", "3 7\n", 3.0, 7.0)
    Unit <- check_delta("a negative dx", "-12 5\n", F32.neg(12.0), 5.0)
    Unit <- check_delta("a negative dy", "4 -9\n", 4.0, F32.neg(9.0))
    Unit <- check_delta("two lines", "3 -2\n-10 5\n", F32.neg(7.0), 3.0)
    Unit <- check_delta("lines that cancel", "40 -40\n-40 40\n", 0.0, 0.0)
    Unit <- check_delta("three digits", "250 -128\n", 250.0, F32.neg(128.0))
    # A Windows writer may end a line with a carriage return before the newline.
    check_delta("a carriage return", "6 1\r\n-1 1\r\n", 5.0, 2.0)

# --- the frame's events -------------------------------------------------------
#
# Under a hosted pointer the display's own pointer events are noise: the host is holding the
# cursor still, so whatever position the display reports is not a movement. They are
# replaced by the one `Look` the host measured. The other events are the player's and stay.

def turn_of(events: List<&2, Event>) -> F32:
  Frame.turn_delta(Frame.input(events))

def mask_of(events: List<&2, Event>) -> U32:
  Frame.keys_mask(Frame.input(events))

def display_events() -> List<&2, Event>:
  [Look{100.0, 100.0}, Key{119, True{}}, Move{3, 4}]

def hosted_replaces_the_display() -> IO(Unit):
  +want : F32 = F32.mul(5.0, Frame.look_sensitivity())
  do IO<Unit>:
    Unit <- check(same(turn_of(Pointer.events(True{}, "5 0\n", display_events())), want),
      "a hosted pointer did not turn by the host's delta alone")
    Unit <- check(same(turn_of(Pointer.events(True{}, "", display_events())), 0.0),
      "a hosted pointer that did not move still turned, so a display event got through")
    check(U32.is_eq(mask_of(Pointer.events(True{}, "5 0\n", display_events())), 1),
      "a hosted pointer dropped a key event along with the pointer events")

def unhosted_keeps_the_display() -> IO(Unit):
  +want : F32 = F32.mul(100.0, Frame.look_sensitivity())
  do IO<Unit>:
    Unit <- check(same(turn_of(Pointer.events(False{}, "5 0\n", display_events())), want),
      "an unhosted pointer did not turn by the display's own look")
    check(U32.is_eq(mask_of(Pointer.events(False{}, "", display_events())), 1),
      "an unhosted pointer lost a key event")

# --- the effects on this lane -------------------------------------------------
#
# This test runs on the JS lane, which has no window, so the host is never opened and never
# has anything to say. The native lane's answers are measured by
# `lab/native/pointer/host-probe.sh`.

def opened_is(opened: U32) -> IO(Unit):
  check(U32.is_eq(opened, 0), "the JS lane claimed to read the host's pointer")

def read_is(text: String) -> IO(Unit):
  check(String.is_empty(text), "the JS lane read pointer lines from a host it never opened")

def js_lane_is_unhosted() -> IO(Unit):
  do IO<Unit>:
    opened : U32 <- Pointer.host_open("Bend2Craft native")
    Unit <- opened_is(opened)
    text : String <- Pointer.host_read()
    read_is(text)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- lines_are_summed()
    Unit <- hosted_replaces_the_display()
    Unit <- unhosted_keeps_the_display()
    Unit <- js_lane_is_unhosted()
    IO.print("pointer: host lines, hosted events and the unhosted lane passed")
