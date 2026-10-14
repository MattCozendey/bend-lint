# Every sound of the table in src/sound.bend, read from the WAD named by
# BENDOOM_IWAD and expanded to 44100 Hz as Chocolate Doom expands it,
# written to the current directory one file a sound: DSNOWAY.hex and the
# rest, signed 16-bit little-endian mono, as hex text that basenc
# --base16 -d makes DSNOWAY.raw of. A sound is written piece by piece as
# it is made, so no whole expansion is held. A table sound the WAD does
# not hold, CacheSFX refuses, or SDL's converter is not given stops the
# build with the lump's name.
#
#   bend sounds.bend -o sounds
import Base
import ./src/bytes.bend as B
import ./src/wad.bend as W
import ./src/sfx.bend as X
import ./src/sound.bend as Sn

# Samples in order, as bytes in order, low byte first.
def Sounds.bytes(samples: List<&2, U32>) -> List<&2, U32>:
  match samples:
    case []:
      []
    case +s <> rest:
      s <> (s >> 8n : U32) <> Sounds.bytes(rest)

# The run's pieces one after another, each made as it is written.
def Sounds.pieces(n: Nat, +r: X.Sfx.Run, file: File) -> IO(File):
  match n:
    case 0n:
      IO.pure(File, file)
    case 1n+m:
      do IO<File>:
        kept : File <- B.Bytes.put_hex(file, Sounds.bytes(X.Sfx.out(r)))
        Sounds.pieces(m, X.Sfx.next(r), kept)

def Sounds.write(+name: String, +r: X.Sfx.Run) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File, File.open(name ++ ".hex", "w"))
    kept : File <- Sounds.pieces(X.Sfx.pieces(r), r, file)
    File.close(kept)

def Sounds.run(+name: String, a: Array<U32>, m: Maybe<&2, X.Sfx.Run>) -> IO(Array<U32>):
  match m:
    case None{}:
      IO.die(Array<U32>, 1, "D_E1M1: " ++ name ++ " is at a rate the expansion does not serve")
    case Some{+r}:
      do IO<Array<U32>>:
        Sounds.write(name, r)
        return a

def Sounds.sound(+name: String, a: Array<U32>, m: Maybe<&2, X.Sfx.Sound>) -> IO(Array<U32>):
  match m:
    case None{}:
      IO.die(Array<U32>, 1, "D_E1M1: " ++ name ++ " is not in the WAD, or is a lump CacheSFX refuses")
    case Some{s}:
      Sounds.run(name, a, X.Sfx.run(s))

def Sounds.one(+name: String, p: Array<U32> & Maybe<&2, X.Sfx.Sound>) -> IO(Array<U32>):
  (a, m) = p
  Sounds.sound(name, a, m)

# Each row's sound written before the next is read, so the WAD is the
# only thing the run holds beside one piece.
def Sounds.go(rows: List<&2, Sn.Sound.Sfx>, +lumps: List<&2, W.Wad.Lump>, a: Array<U32>) -> IO(Array<U32>):
  match rows:
    case []:
      IO.pure(Array<U32>, a)
    case Sn.Sfx{id, +lump, priority} <> rest:
      do IO<Array<U32>>:
        next : Array<U32> <- Sounds.one(lump, X.Sfx.read(a, lumps, lump))
        Sounds.go(rest, lumps, next)

def Sounds.all(rows: List<&2, Sn.Sound.Sfx>, p: Array<U32> & List<&2, W.Wad.Lump>) -> IO(Array<U32>):
  (a, +lumps) = p
  Sounds.go(rows, lumps, a)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, IO.get_env("BENDOOM_IWAD"))
    bytes : Array<U32> <- IO.try(Array<U32>, B.Bytes.read(path))
    done : Array<U32> <- Sounds.all(Sn.Sound.table(), W.Wad.dir(bytes))
    IO.pure(Unit, Unit{})
