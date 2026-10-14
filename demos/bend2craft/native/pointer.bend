import Base

# The host's pointer, for a display that cannot report a mouse's movement.
#
# A first-person look needs relative motion: how far the mouse travelled, wherever the
# cursor is. On a real X server the runtime's own grab provides it — `Window.grab` confines
# and warps the pointer and each frame's travel arrives as one `Look`, which
# `lab/native/pointer/census-xvfb.sh` measures. Under WSLg it cannot. The window is a remote
# application window carried over RDP by FreeRDP 2.4, which has no relative pointer input,
# so the display only ever learns an absolute cursor position while the cursor is over the
# window, the warp never reaches the Windows cursor, and the measured result was one `Look`
# for a whole session.
#
# So under WSL the movement is read where it exists, on the Windows side. `host_open` starts
# `native/pointer-host.ps1` through WSL interop; that script holds the Windows cursor at the
# centre of the client's window while the window is in front, and writes each displacement
# as a line of text. `host_read` hands the client the lines that arrived since the last
# frame. Everything after the bytes is here, in Bend: the lines are summed into one delta
# and given to the frame fold as the same `Look` a working grab would have produced, in
# place of whatever pointer events the display did manage to send.
#
# The two effects are the whole of what is not Bend, and they carry bytes, not rules:
# `pointer.c` owns a pipe and a child process, and the script owns the Windows cursor. A
# display that is not WSL answers `0` from `host_open`, and the client keeps the runtime's
# grab.

# `1` when the host's pointer is being read, `0` when this display has none to read. The
# title is the client window's own, which is how the script knows which window to hold the
# cursor in.
def host_open(title: String) -> IO(U32):
  import "./pointer.c"
  import "./pointer_open.js"

# The complete lines the host wrote since the last read, each `dx dy` in pixels.
def host_read() -> IO(String):
  import "./pointer.c"
  import "./pointer_read.js"

type Delta is Data:
  Delta{dx: F32, dy: F32}

def delta_x(delta: Delta) -> F32:
  Delta{dx, dy} = delta
  dx

def delta_y(delta: Delta) -> F32:
  Delta{dx, dy} = delta
  dy

# The sums are kept as two's-complement words, because a line may be negative and a `U32`
# is what the digits fold into. A word with its top bit set is a negative sum.
def negated(+value: U32, negative: Bool) -> U32:
  Bool.pick(U32, negative, U32.sub(0, value), value)

def to_f32(+sum: U32) -> F32:
  Bool.pick(F32, U32.is_ge(sum, 2147483648), F32.neg(U32.to_f32(U32.sub(0, sum))),
    U32.to_f32(sum))

# One pass over the text, one character at a time. A digit extends the number being read, a
# minus marks it negative, a space ends the `dx` of a line and a newline ends its `dy`; each
# end adds the number to its sum. Anything else — the carriage return a Windows writer may
# add — is skipped. The step is arithmetic rather than a branch per character class because
# a `match` cannot scrutinize a computed value and a helper that matched it could not call
# this def back.
def delta.go(text: String, +x: U32, +y: U32, +value: U32, +negative: Bool) -> Delta:
  match text:
    case SNil{}:
      Delta{to_f32(x), to_f32(y)}
    case SCon{Chr{+c}, rest}:
      +digit = Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57))
      +space = U32.is_eq(c, 32)
      +newline = U32.is_eq(c, 10)
      +ends = Bool.or(space, newline)
      +number = negated(value, negative)
      delta.go(rest,
        Bool.pick(U32, space, U32.add(x, number), x),
        Bool.pick(U32, newline, U32.add(y, number), y),
        Bool.pick(U32, digit, U32.add(U32.mul(value, 10), U32.sub(c, 48)),
          Bool.pick(U32, ends, 0, value)),
        Bool.and(Bool.not(ends), Bool.or(negative, U32.is_eq(c, 45))))

# The host's lines as one movement: the sum of every `dx` and of every `dy`.
def delta(text: String) -> Delta:
  delta.go(text, 0, 0, 0, False{})

# What the display says about the pointer. Under a host-read pointer these are dropped: the
# display's view of a cursor the host is holding still is not a movement.
def is_pointer(event: Event) -> Bool:
  match event:
    case Look{dx, dy}:
      True{}
    case Move{x, y}:
      True{}
    case _:
      False{}

def kept(drop: Bool, event: Event, rest: List<&2, Event>) -> List<&2, Event>:
  match drop:
    case True{}:
      rest
    case False{}:
      event <> rest

def without_pointer(events: List<&2, Event>) -> List<&2, Event>:
  match events:
    case Nil{}:
      Nil{}
    case +event <> rest:
      kept(is_pointer(event), event, without_pointer(rest))

def look(delta: Delta) -> Event:
  Delta{dx, dy} = delta
  Look{dx, dy}

# The frame's events as the fold should read them. A hosted pointer replaces the display's
# pointer events with the one `Look` the host measured; an unhosted one leaves the display's
# own events alone, because there the runtime's grab is what measures.
def events(hosted: Bool, text: String, events: List<&2, Event>) -> List<&2, Event>:
  match hosted:
    case True{}:
      look(delta(text)) <> without_pointer(events)
    case False{}:
      events
