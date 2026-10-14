# The sounds node's own files, read from the directory BENDOOM_SOUNDS
# names: the use grunt DSNOWAY, at 22050 Hz in Freedoom, and the pickup
# DSITEMUP at 11025 Hz. Each file's length in bytes and the FNV-1a hash
# of its 16-bit little-endian samples, which must be the expansion
# milestone 7's ticket 03 checked against Chocolate Doom.
#
# The hashes are that ticket's "chunk" values, hashed there over the
# left samples of Chocolate Doom's own Mix_Chunk, dumped from its memory
# under gdb; tests/sfx.bend prints the same two from the WAD. The
# lengths are the lumps' sample counts, as
#
#   nu -c 'source tools/wad.nu; open --raw $env.BENDOOM_IWAD | sound-lumps | where name in [DSNOWAY DSITEMUP]'
#
# reads them, 8498 and 2173, times the 44100 / rate frames SDL's
# converter makes of each, times two bytes a frame: 33992 and 17384.
import Base
import ../src/bytes.bend as B
import ../src/fnv.bend as H

# A file read so far: its bytes counted and its samples hashed.
type Test.Sum is Data:
  Sum{n: U32, h: U32}

def Test.mix(+lo: U32, +hi: U32, s: Test.Sum) -> Test.Sum:
  Sum{+n, h} = s
  Sum{(n + 2 : U32), H.Fnv.mix(h, B.Bytes.le16(lo, hi))}

# A chunk of the file, two bytes a sample. Every chunk holds an even
# number of bytes, so no sample straddles two.
def Test.step(bytes: List<&2, U32>, s: Test.Sum) -> Test.Sum:
  match bytes:
    case lo <> hi <> rest:
      Test.step(rest, Test.mix(lo, hi, s))
    case _:
      s

def Test.show(+name: String, s: Test.Sum) -> String:
  Sum{n, h} = s
  name ++ " " ++ U32.show(n) ++ " bytes chunk " ++ U32.show(h)

def Test.file(+dir: String, +name: String) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File, File.open(dir ++ "/" ++ name ++ ".raw", "r"))
    sum : Test.Sum <- B.Bytes.fold(~Test.Sum, ~Test.step, file, Sum{0, H.Fnv.basis()})
    IO.print(Test.show(name, sum))

def Test.files(+dir: String, names: List<&2, String>) -> IO(Unit):
  match names:
    case []:
      IO.pure(Unit, Unit{})
    case name <> rest:
      do IO<Unit>:
        Test.file(dir, name)
        Test.files(dir, rest)

def main() -> IO(Unit):
  do IO<Unit>:
    dir : String <- IO.try(String, IO.get_env("BENDOOM_SOUNDS"))
    Test.files(dir, ["DSNOWAY", "DSITEMUP"])

#|DSNOWAY 33992 bytes chunk 973226569
#|DSITEMUP 17384 bytes chunk 4006389721
