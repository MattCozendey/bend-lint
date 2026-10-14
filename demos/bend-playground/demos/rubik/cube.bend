# A 3x3 cube as 54 distinct stickers. URFDLB face order, row-major faces.
# Coordinates 0,1,2 avoid signed arithmetic. Every move is an exact permutation.
import Base

type Point is Data:
  Point{x: U32, y: U32, z: U32}

type Site is Data:
  Site{position: Point, normal: Point}

def face_site(face: U32, +row: U32, +col: U32) -> Site:
  match face:
    case 0:
      Site{Point{col, 2, row}, Point{1, 2, 1}}
    case 1:
      Site{Point{2, (2 - row : U32), (2 - col : U32)}, Point{2, 1, 1}}
    case 2:
      Site{Point{col, (2 - row : U32), 2}, Point{1, 1, 2}}
    case 3:
      Site{Point{col, 0, (2 - row : U32)}, Point{1, 0, 1}}
    case 4:
      Site{Point{0, (2 - row : U32), col}, Point{0, 1, 1}}
    case _:
      Site{Point{(2 - col : U32), (2 - row : U32), 0}, Point{1, 1, 0}}

def site(+index: U32) -> Site:
  face_site((index / 9 : U32), (index % 9 / 3 : U32), (index % 3 : U32))

def face_of(n: Point) -> U32:
  Point{+x, +y, z} = n
  Bool.pick(U32, U32.is_eq(y, 2), 0, Bool.pick(U32, U32.is_eq(x, 2), 1, Bool.pick(U32, U32.is_eq(z, 2), 2, Bool.pick(U32, U32.is_eq(y, 0), 3, Bool.pick(U32, U32.is_eq(x, 0), 4, 5)))))

def face_index(+face: U32, p: Point) -> U32:
  match face:
    case 0:
      Point{x, y, z} = p
      (3 * z + x : U32)
    case 1:
      Point{x, y, z} = p
      (9 + 3 * (2 - y) + 2 - z : U32)
    case 2:
      Point{x, y, z} = p
      (18 + 3 * (2 - y) + x : U32)
    case 3:
      Point{x, y, z} = p
      (27 + 3 * (2 - z) + x : U32)
    case 4:
      Point{x, y, z} = p
      (36 + 3 * (2 - y) + z : U32)
    case _:
      Point{x, y, z} = p
      (45 + 3 * (2 - y) + 2 - x : U32)

def index(s: Site) -> U32:
  Site{p, n} = s
  face_index(face_of(n), p)

# Clockwise when viewed from outside the selected face.
def rotate(face: U32, p: Point) -> Point:
  match face:
    case 0:
      Point{x, y, z} = p
      Point{(2 - z : U32), y, x}
    case 1:
      Point{x, y, z} = p
      Point{x, z, (2 - y : U32)}
    case 2:
      Point{x, y, z} = p
      Point{y, (2 - x : U32), z}
    case 3:
      Point{x, y, z} = p
      Point{z, y, (2 - x : U32)}
    case 4:
      Point{x, y, z} = p
      Point{x, (2 - z : U32), y}
    case _:
      Point{x, y, z} = p
      Point{(2 - y : U32), x, z}

def in_layer(face: U32, p: Point) -> Bool:
  match face:
    case 0:
      Point{x, y, z} = p
      U32.is_eq(y, 2)
    case 1:
      Point{x, y, z} = p
      U32.is_eq(x, 2)
    case 2:
      Point{x, y, z} = p
      U32.is_eq(z, 2)
    case 3:
      Point{x, y, z} = p
      U32.is_eq(y, 0)
    case 4:
      Point{x, y, z} = p
      U32.is_eq(x, 0)
    case _:
      Point{x, y, z} = p
      U32.is_eq(z, 0)

def rotated(+face: U32, s: Site) -> Site:
  Site{p, n} = s
  Site{rotate(face, p), rotate(face, n)}

def rotations(turns: Nat, +face: U32, s: Site) -> Site:
  match turns:
    case 0n:
      s
    case 1n+p:
      rotations(p, face, rotated(face, s))

def turn_if(active: Bool, turns: Nat, face: U32, s: Site) -> Site:
  match active:
    case False{}:
      s
    case True{}:
      rotations(turns, face, s)

def moved_site(s: Site, +move: U32) -> Site:
  Site{+p, n} = s
  +face = (move / 3 : U32)
  turn_if(in_layer(face, p), U32.to_nat((move % 3 + 1 : U32)), face, Site{p, n})

# Moves 0..17 encode U,U2,U',R,R2,R',F,...,B'.
def destination(i: U32, move: U32) -> U32:
  index(moved_site(site(i), move))

def inverse(+move: U32) -> U32:
  (move / 3 * 3 + 2 - move % 3 : U32)

def indices(fuel: Nat, +offset: U32) -> List<&2, U32>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+p:
      offset <> indices(p, (offset + 1 : U32))

def solved() -> List<&2, U32>:
  indices(54n, 0)

def first(xs: List<&2, U32>) -> U32:
  match xs:
    case Nil{}:
      0
    case h <> t:
      h

def get(i: Nat, xs: List<&2, U32>) -> U32:
  match i:
    case 0n:
      first(xs)
    case 1n+p:
      match xs:
        case Nil{}:
          0
        case h <> t:
          get(p, t)

def apply_slots(fuel: Nat, +offset: U32, +cube: List<&2, U32>, +backward: U32) -> List<&2, U32>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+p:
      value = get(U32.to_nat(destination(offset, backward)), cube)
      value <> apply_slots(p, (offset + 1 : U32), cube, backward)

def apply(cube: List<&2, U32>, move: U32) -> List<&2, U32>:
  apply_slots(54n, 0, cube, inverse(move))

def sequence(moves: List<&2, U32>, cube: List<&2, U32>) -> List<&2, U32>:
  match moves:
    case Nil{}:
      cube
    case h <> t:
      sequence(t, apply(cube, h))

def matches(cube: List<&2, U32>, +i: U32) -> Bool:
  match cube:
    case Nil{}:
      True{}
    case h <> t:
      U32.is_eq((h / 9 : U32), (i / 9 : U32)) && matches(t, (i + 1 : U32))

def is_solved(cube: List<&2, U32>) -> Bool:
  matches(cube, 0)

def undo_moves(moves: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match moves:
    case Nil{}:
      acc
    case h <> t:
      undo_moves(t, inverse(h) <> acc)

# Reproducible legal scrambles. Consecutive moves use different faces.
def scramble(fuel: Nat, seed: U32, +previous: U32) -> List<&2, U32>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+p:
      +next = (seed * 1664525 + 1013904223 : U32)
      +candidate = ((next >> 8n) % 6 : U32)
      +face = Bool.pick(U32, U32.is_eq(candidate, previous), ((candidate + 1) % 6 : U32), candidate)
      move = (face * 3 + (next >> 16n) % 3 : U32)
      move <> scramble(p, next, face)
