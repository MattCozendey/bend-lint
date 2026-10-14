# The render named by BENDOOM_MUSIC streamed as the game streams it, in
# pieces of varying frame counts, printing the frames where the song
# begins, at each end of a pass and at each start after one, each
# sample as Audio.write takes it, turned back into 16 bits. Freedoom's
# passes are 5,759,883 and 5,759,888 frames, so the pull after the last
# three frames of a pass reads none: that empty read is the pass's end,
# and the second pass opens again on it. The expected frames are read
# from the render's files in nushell:
#
#   def frames [file: path, off: int, n: int] {
#     open --raw $file | bytes at $off..<($off + $n * 4) | chunks 4 | each {|c|
#       let l = ($c | bytes at 0..<2 | into int --endian little)
#       let r = ($c | bytes at 2..<4 | into int --endian little)
#       [(if $l >= 32768 { $l - 65536 } else { $l }) (if $r >= 32768 { $r - 65536 } else { $r })]
#     } | flatten | str join " "
#   }
#   frames $"($env.BENDOOM_MUSIC)/first.raw" 0 3
#   frames $"($env.BENDOOM_MUSIC)/first.raw" (23039532 - 12) 3
#   frames $"($env.BENDOOM_MUSIC)/second.raw" 0 3
#   frames $"($env.BENDOOM_MUSIC)/second.raw" (23039552 - 12) 3
#
# Then the samples of the bytes 00 80, FF 7F, FF FF and 00 00: -32768,
# 32767, -1 and 0, the ends of the range and either side of zero.
import Base
import ../src/stream.bend as A

# A sample as the device takes it, back in 16 bits: x times 32768,
# offset by 32768 so that it converts as a Nat.
def int(+x: F32) -> String:
  +half = U32.to_f32(32768)
  +n = U32.from_nat(F32.to_nat(((x * half : F32) + half : F32)))
  Bool.pick(String, U32.is_ge(n, 32768), U32.show((n - 32768 : U32)), "-" ++ U32.show((32768 - n : U32)))

def ints(samples: List<&2, F32>) -> String:
  match samples:
    case x <> rest:
      " " ++ int(x) ++ ints(rest)
    case []:
      ""

# The samples of a read as Audio.write takes them, left then right.
def samples(bytes: List<&2, U32>) -> String:
  ints(A.Stream.samples(A.Stream.words(bytes)))

def told(tag: String, p: A.Stream.Tape & List<&2, U32>) -> IO(A.Stream.Tape):
  (tape, bytes) = p
  do IO<A.Stream.Tape>:
    IO.print(tag ++ samples(bytes))
    return tape

# A pull of so many frames, its samples printed.
def show(tag: String, k: U32, tape: A.Stream.Tape) -> IO(A.Stream.Tape):
  IO.bind(A.Stream.Tape & List<&2, U32>, A.Stream.Tape, A.Stream.pull(k, tape), p => told(tag, p))

def dropped(p: A.Stream.Tape & List<&2, U32>, rest: A.Stream.Tape -> IO(A.Stream.Tape)) ->
  IO(A.Stream.Tape):
  (tape, fs) = p
  rest(tape)

# The piece counts a span takes in turn; once they run out it goes in
# pieces of 3072 frames.
def sizes() -> List<&2, U32>:
  [1, 7, 100, 2048, 33, 999, 3072, 5]

def next(ss: List<&2, U32>) -> U32 & List<&2, U32>:
  match ss:
    case []:
      (3072, [])
    case s <> rest:
      (s, rest)

# One piece of a span, cut to what is left of it, dropped; then what is
# left, the piece counts after it and the tape.
def piece(+n: Nat, q: U32 & List<&2, U32>, tape: A.Stream.Tape,
  rest: Bool -> Nat -> List<&2, U32> -> A.Stream.Tape -> IO(A.Stream.Tape)) -> IO(A.Stream.Tape):
  (s, ss) = q
  +k = U32.from_nat(Nat.min(n, U32.to_nat(s)))
  +left = Nat.sub(n, U32.to_nat(k))
  IO.bind(A.Stream.Tape & List<&2, U32>, A.Stream.Tape, A.Stream.pull(k, tape),
    p => dropped(p, t => rest(Nat.is_eq(left, 0n), left, ss, t)))

# The next n frames read and thrown away.
def span(fuel: Nat, done: Bool, n: Nat, ss: List<&2, U32>, tape: A.Stream.Tape) -> IO(A.Stream.Tape):
  match fuel done:
    case _ True{}:
      IO.pure(A.Stream.Tape, tape)
    case 0n _:
      IO.die(A.Stream.Tape, 1, "tests/stream.bend: the span outran its fuel")
    case 1n+f False{}:
      piece(n, next(ss), tape, d => m => more => t => span(f, d, m, more, t))

def opened(m: Maybe<A.Stream.Tape>) -> IO(A.Stream.Tape):
  match m:
    case None{}:
      IO.die(A.Stream.Tape, 1, "tests/stream.bend: BENDOOM_MUSIC names no render")
    case Some{t}:
      IO.pure(A.Stream.Tape, t)

def shut(tape: A.Stream.Tape) -> IO(Unit):
  A.Tape{file, path} = tape
  File.close(file)

def main() -> IO(Unit):
  do IO<Unit>:
    dir : String <- IO.try(String, IO.get_env("BENDOOM_MUSIC"))
    first : Maybe<A.Stream.Tape> <- A.Stream.tape(dir)
    t0 : A.Stream.Tape <- opened(first)
    t1 : A.Stream.Tape <- show("start", 3, t0)
    t2 : A.Stream.Tape <- span(U32.to_nat(4294967295), False{}, U32.to_nat(5759877), sizes(), t1)
    t3 : A.Stream.Tape <- show("first end", 3, t2)
    t4 : A.Stream.Tape <- show("boundary", 3, t3)
    t5 : A.Stream.Tape <- show("second start", 3, t4)
    t6 : A.Stream.Tape <- span(U32.to_nat(4294967295), False{}, U32.to_nat(5759882), sizes(), t5)
    t7 : A.Stream.Tape <- show("second end", 3, t6)
    t8 : A.Stream.Tape <- show("wrap", 3, t7)
    t9 : A.Stream.Tape <- show("again", 3, t8)
    IO.print("edges" ++ samples([0, 128, 255, 127, 255, 255, 0, 0]))
    shut(t9)

#|start 0 0 0 0 0 0
#|first end 268 286 249 264 233 247
#|boundary
#|second start 216 229 204 215 196 204
#|second end 167 186 159 179 156 172
#|wrap
#|again 216 229 204 215 196 204
#|edges -32768 32767 -1 0
