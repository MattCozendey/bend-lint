# Chords i -> (multiplier * i) mod n, with continuous fractional multipliers.
import Base

type Chord is Data:
  Chord{x: F32, y: F32, u: F32, v: F32}

def chord(index: U32, +n: U32, multiplier: F32) -> Chord:
  +i = U32.to_f32(index)
  +size = U32.to_f32(n)
  +product = (i * multiplier : F32)
  +target = (product - F32.floor((product / size : F32)) * size : F32)
  +a = (6.283185307 * i / size : F32)
  +b = (6.283185307 * target / size : F32)
  Chord{F32.cos(a),F32.sin(a),F32.cos(b),F32.sin(b)}
