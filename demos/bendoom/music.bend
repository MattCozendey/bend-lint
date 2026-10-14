# E1M1's song from the WAD named by BENDOOM_IWAD, as Chocolate Doom
# plays it looping, written to two files in the current directory: the
# first pass to first.hex, from the song's start to the sample where its
# restart runs, and the second pass to second.hex, up to the next. Both
# are 16-bit little-endian stereo at 44100 Hz, left then right, as hex
# text that basenc --base16 -d makes first.raw and second.raw of, and
# written a buffer at a time as it is made. With BENDOOM_IDLE set, the
# first pass starts with Chocolate Doom's idle first buffer, as a
# capture does; tools/listen.nu sets it to compare the passes with one.
#
#   bend music.bend -o music
import Base
import ./src/bytes.bend as B
import ./src/song.bend as S

# The buffers a pass can take: a pass longer than this has made more
# frames than the song counts.
def Music.buffers() -> Nat:
  U32.to_nat((4294967295 / S.Song.buffer() : U32))

# Frames, latest first, as bytes in order.
def Music.bytes(frames: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match frames:
    case []:
      acc
    case +lr <> rest:
      Music.bytes(rest, lr <> (lr >> 8n : U32) <> (lr >> 16n : U32) <> (lr >> 24n : U32) <> acc)

def Music.put(+m: S.Song, file: File) -> IO(File):
  B.Bytes.put_hex(file, Music.bytes(S.Song.out(m), []))

# The song run a buffer further.
def Music.turn(+env: S.Song.Env, +m: S.Song) -> S.Song.Turn:
  S.Song.turn((S.Song.made(m) + S.Song.buffer() : U32), env, m)

# The pass from a turn on, each buffer written as it is made, until the
# restart is due.
def Music.pass.go(n: Nat, t: S.Song.Turn, +env: S.Song.Env, file: File) -> IO(S.Song):
  match n t:
    case _ S.Stuck{}:
      IO.die(S.Song, 1, "D_E1M1: a song whose callbacks outran the events a lump holds")
    case _ S.Ended{+m}:
      do IO<S.Song>:
        kept : File <- Music.put(m, file)
        File.close(kept)
        return S.Song.clear(m)
    case 0n S.More{m}:
      IO.die(S.Song, 1, "D_E1M1: a pass of more frames than the song counts")
    case 1n+f S.More{+m}:
      do IO<S.Song>:
        kept : File <- Music.put(m, file)
        Music.pass.go(f, Music.turn(env, S.Song.clear(m)), env, kept)

def Music.pass(path: String, +env: S.Song.Env, +m: S.Song) -> IO(S.Song):
  do IO<S.Song>:
    file : File <- IO.try(File, File.open(path, "w"))
    Music.pass.go(Music.buffers(), Music.turn(env, m), env, file)

def Music.render(+env: S.Song.Env, +idle: Bool) -> IO(Unit):
  do IO<Unit>:
    first : S.Song <- Music.pass("first.hex", env, S.Song.start(idle, env))
    second : S.Song <- Music.pass("second.hex", env, S.Song.restart(env, first))
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    env : S.Song.Env <- S.Song.load()
    idle : Result<&1, &1, U32 & String, String> <- IO.get_env("BENDOOM_IDLE")
    Music.render(env, Result.is_done(&1, &1, U32 & String, String, idle))
