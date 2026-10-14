# Bytes.read over files the test writes as ASCII text, and Bytes.hex.
# Each line is a file's slots, its first five, and the sum of them all.
# The expected values are worked out by hand: the slots are the
# smallest power of two that holds the file, one for an empty file; 'a'
# is 97, so "abc" sums to 97 + 98 + 99, 4096 of 'a' to 97 * 4096, which
# fill their array, and a 'b' after them doubles it. Hex takes each
# cell's low byte, so 427, 0x1ab, reads ab.
# Then words: the bytes 78 56 34 12 assemble little-endian as
# 0x12345678; a WAD's kind is 1 for "IWAD" and 2 for "PWAD", each read
# as a little-endian word, and 0 for anything else; and a tree built
# from 5 6 7 reads them back by position.
import Base
import ../src/bytes.bend as B
import ../src/wad.bend as W
import ../src/vec.bend as V

def ints(xs: List<&2, U32>) -> String:
  match xs:
    case []:
      ""
    case x <> rest:
      " " ++ U32.show(x) ++ ints(rest)

def add(sum: U32, b: U32) -> U32:
  (sum + b : U32)

def summed(p: Array<U32> & List<&2, U32>) -> String:
  (a, +slots) = p
  ints(List.take(&2, U32, slots, 5n)) ++ " | sum " ++ U32.show(List.foldl(~&2, ~U32, ~U32, ~add, slots, 0))

def sized(p: Array<U32> & U32) -> String:
  (a, +size) = p
  U32.show(size) ++ " slots |" ++ summed(B.Bytes.list(a, 0, size))

def wrote(p: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (file, done) = p
  File.close(file)

def show(tag: String, text: String) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File, File.open("bytes.scratch", "w"))
    IO.bind(File & Result<&1, &1, U32 & String, Unit>, Unit, File.write(file, text), wrote)
    bytes : Array<U32> <- IO.try(Array<U32>, B.Bytes.read("bytes.scratch"))
    IO.print(tag ++ ": " ++ sized(Array.size(U32, bytes)))

def main() -> IO(Unit):
  do IO<Unit>:
    show("empty", "")
    show("a", "a")
    show("ab", "ab")
    show("abc", "abc")
    show("abcde", "abcde")
    show("4096 a", String.repeat("a", U32.to_nat(4096)))
    show("4096 a, b", String.repeat("a", U32.to_nat(4096)) ++ "b")
    missing : Result<&1, &1, U32 & String, Array<U32>> <- B.Bytes.read("bytes.missing")
    IO.print("missing: opened " ++ Bool.show(Result.is_done(&1, &1, U32 & String, Array<U32>, missing)))
    IO.print("hex " ++ B.Bytes.hex([0, 9, 10, 15, 16, 128, 255, 427]))
    IO.print("le32" ++ ints([B.Bytes.le32(120, 86, 52, 18)]))
    IO.print("kinds" ++ ints([W.Wad.kind(1145132873), W.Wad.kind(1145132880), W.Wad.kind(0)]))
    IO.print("vec" ++ ints([V.Vec.get(V.Vec.of_list([5, 6, 7], 3), 0), V.Vec.get(V.Vec.of_list([5, 6, 7], 3), 1),
      V.Vec.get(V.Vec.of_list([5, 6, 7], 3), 2)]))

#|empty: 1 slots | 0 | sum 0
#|a: 1 slots | 97 | sum 97
#|ab: 2 slots | 97 98 | sum 195
#|abc: 4 slots | 97 98 99 0 | sum 294
#|abcde: 8 slots | 97 98 99 100 101 | sum 495
#|4096 a: 4096 slots | 97 97 97 97 97 | sum 397312
#|4096 a, b: 8192 slots | 97 97 97 97 97 | sum 397410
#|missing: opened False
#|hex 00090a0f1080ffab
#|le32 305419896
#|kinds 1 2 0
#|vec 5 6 7
