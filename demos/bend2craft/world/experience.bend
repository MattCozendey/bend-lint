import Base

# Experience points for mob kills. Monsters (kind 2) award 5 points and
# passive mobs (kind 1) award 2. Level thresholds grow linearly:
# threshold(level) = 7 + level * 2.

type XP is Data:
  XP{level: U32, points: U32}

def empty() -> XP:
  XP{0, 0}

def threshold(+level: U32) -> U32:
  U32.add(7, U32.mul(level, 2))

def xp_for_kind(+kind: U32) -> U32:
  Bool.pick(U32, U32.is_eq(kind, 2), 5, 2)

def xp_level(state: XP) -> U32:
  XP{+level, points} = state
  level

def xp_points(state: XP) -> U32:
  XP{level, +points} = state
  points

def normalize(+remaining: Nat, +level: U32, +points: U32) -> XP:
  match remaining:
    case 0n:
      XP{level, points}
    case 1n+p:
      +need = threshold(level)
      +leveled = U32.is_ge(points, need)
      +next_level = Bool.pick(U32, leveled, U32.add(level, 1), level)
      +next_points = Bool.pick(U32, leveled, U32.sub(points, need), points)
      normalize(p, next_level, next_points)

def add(+state: XP, +gain: U32) -> XP:
  XP{+level, +points} = state
  normalize(8n, level, U32.add(points, gain))

def award(+state: XP, +kind: U32) -> XP:
  add(state, xp_for_kind(kind))
