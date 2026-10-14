# A measurement, not a test: 100 s of the OPL chip's output, 4,410,000
# frames, one note held. Every operator runs every sample whether it
# sounds or not, so this is the chip's cost at any point of a song.
# Build natively and time it against 100 s:
#
#   bend bench/chip.bend -o chip
#   time ./chip --threads 1
import Base
import ../src/fnv.bend as H
import ../src/opl.bend as O

# Channel 0's carrier at full level and fastest attack, keyed at f-num
# 0x244, block 4.
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(H.Fnv.words(O.Opl.Frames.out(O.Opl.frames(U32.to_nat(4410000), O.Opl.roms(),
      O.Opl.Frames.queue([O.Write{67, 0}, O.Write{99, 240}, O.Write{160, 68}, O.Write{176, 50}],
        O.Frames{O.Opl.reset(), []}))))))
