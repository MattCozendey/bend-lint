# P_NoiseAlert's sector flood. Only the player makes this alert, so a
# sector's persistent sound target is whether it has heard that player.
# Each flood records one plus the fewest sound-blocking lines crossed;
# zero means unreached. Relaxing the open lines reaches the same sectors
# as P_RecursiveSound, without a call stack proportional to the map.
import Base
import ./level.bend as L
import ./fixed.bend as F
import ./vec.bend as V

type Noise.Flood is Data:
  Flood{marks: V.Vec, changed: Bool}

def Noise.write(better: Bool, to: U32, count: U32, f: Noise.Flood) -> Noise.Flood:
  match better:
    case False{}:
      f
    case True{}:
      Flood{marks, changed} = f
      Flood{V.Vec.set(marks, to, count), True{}}

def Noise.edge(from: U32, +to: U32, block: U32, f: Noise.Flood) -> Noise.Flood:
  Flood{+marks, changed} = f
  +start = V.Vec.get(marks, from)
  +count = (start + block : U32)
  +old = V.Vec.get(marks, to)
  Noise.write(Bool.and(U32.is_gt(start, 0), Bool.and(U32.is_le(count, 2),
    Bool.or(U32.is_zero(old), U32.is_lt(count, old)))), to, count, Flood{marks, changed})

def Noise.open(open: Bool, +front: U32, +back: U32, +block: U32, f: Noise.Flood) -> Noise.Flood:
  match open:
    case False{}:
      f
    case True{}:
      Noise.edge(front, back, block, Noise.edge(back, front, block, f))

def Noise.line(+level: L.Level, line: L.Level.Line, f: Noise.Flood) -> Noise.Flood:
  L.Line{x1, y1, x2, y2, +flags, +front, +back} = line
  Noise.open(Bool.and(Bool.not(U32.is_zero((flags .&. 4 : U32))),
    Bool.and(Bool.not(U32.is_eq(back, L.Level.none())),
      F.Fixed.lt(F.Fixed.max(L.Level.floor(level, front), L.Level.floor(level, back)),
        F.Fixed.min(L.Level.ceil(level, front), L.Level.ceil(level, back))))), front, back,
    Bool.to_u32(Bool.not(U32.is_zero((flags .&. 64 : U32)))), f)

def Noise.lines(n: Nat, +level: L.Level, +i: U32, f: Noise.Flood) -> Noise.Flood:
  match n:
    case 0n:
      f
    case 1n+k:
      Noise.lines(k, level, (i + 1 : U32), Noise.line(level, L.Level.line(level, i), f))

def Noise.flood(n: Nat, +level: L.Level, f: Noise.Flood) -> V.Vec:
  match n f:
    case 1n+k Flood{marks, True{}}:
      Noise.flood(k, level, Noise.lines(U32.to_nat(L.Level.nlines(level)), level, 0, Flood{marks, False{}}))
    case _ Flood{marks, changed}:
      marks

def Noise.hear(reached: Bool, sector: U32, heard: V.Vec) -> V.Vec:
  match reached:
    case False{}:
      heard
    case True{}:
      V.Vec.set(heard, sector, 1)

def Noise.targets(n: Nat, +i: U32, +marks: V.Vec, heard: V.Vec) -> V.Vec:
  match n:
    case 0n:
      heard
    case 1n+k:
      Noise.targets(k, (i + 1 : U32), marks,
        Noise.hear(Bool.not(U32.is_zero(V.Vec.get(marks, i))), i, heard))

def Noise.alert(+level: L.Level, sector: U32) -> L.Level:
  L.Level{geo, sectors, specials, heard} = level
  +count = L.Level.nsectors(level)
  L.Level{geo, sectors, specials, Noise.targets(U32.to_nat(count), 0,
    Noise.flood(U32.to_nat((count * 2 + 1 : U32)), level,
      Flood{V.Vec.set(V.Vec.of_list([], count), sector, 1), True{}}), heard)}
