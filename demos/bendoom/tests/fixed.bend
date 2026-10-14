# Doom's fixed point on chosen values, each a 32-bit word, 65536 to the
# unit, negatives in two's complement. A map coordinate converts by sign
# extension then shift: 0xFFFF is -1.0 and 0x7FFF is 32767.0. The signed
# order puts -1 below 0 and 0 below 1, and not 0 below -1. Multiply
# answers FixedMul for 3 * 0.5, -0.5 * -0.5 and 3 * -0.5; where the
# product overflows it keeps the low word of the exact product shifted
# right by sixteen: 0x7FFFFFFF squared is 0x3FFFFFFF00000001, whose bits
# 16 to 47 are 0xFFFF0000. Multiplying by one keeps -1 either way round,
# and 0.78125 * 0.90625 is 46400 either way round. Divide answers
# FixedDiv for 1 / 3 and -1 / 3, and saturates to MAXINT and MININT by
# sign where the quotient would not fit: 3 / 0 and -3 / 0.
import Base
import ../src/fixed.bend as F

def words(xs: List<&2, U32>) -> String:
  List.show(~&2, ~U32, ~U32.show, xs)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("of_map " ++ words([F.Fixed.of_map(65535), F.Fixed.of_map(32767)]))
    IO.print("lt " ++ List.show(~&2, ~Bool, ~Bool.show, [F.Fixed.lt(4294967295, 0), F.Fixed.lt(0, 1),
      F.Fixed.lt(0, 4294967295)]))
    IO.print("mul signs " ++ words([F.Fixed.mul(196608, 32768), F.Fixed.mul(4294934528, 4294934528),
      F.Fixed.mul(196608, 4294934528)]))
    IO.print("mul overflow " ++ U32.show(F.Fixed.mul(2147483647, 2147483647)))
    IO.print("mul one " ++ words([F.Fixed.mul(4294901760, 65536), F.Fixed.mul(65536, 4294901760),
      F.Fixed.mul(51200, 59392), F.Fixed.mul(59392, 51200)]))
    IO.print("div " ++ words([F.Fixed.div(65536, 196608), F.Fixed.div(4294901760, 196608), F.Fixed.div(196608, 0),
      F.Fixed.div(4294770688, 0)]))

#|of_map [4294901760, 2147418112]
#|lt [True, True, False]
#|mul signs [98304, 16384, 4294868992]
#|mul overflow 4294901760
#|mul one [4294901760, 4294901760, 46400, 46400]
#|div [21845, 4294945451, 2147483647, 2147483648]
