import Base

def village_origin_x(+seed: Nat) -> Nat:
  Nat.add(16n, Nat.mod(seed, 16n))

def village_origin_z(+seed: Nat) -> Nat:
  Nat.add(16n, Nat.mod(Nat.mul(Nat.mod(seed, 16n), 3n), 16n))

def village_height_valid(+height: Nat) -> Bool:
  Nat.is_gt(height, 7n) && Nat.is_lt(height, 14n)

def in_square(+x: Nat, +z: Nat, +origin_x: Nat, +origin_z: Nat, +half: Nat) -> Bool:
  Bool.and(
    Bool.and(Nat.is_ge(x, Nat.sub(origin_x, half)), Nat.is_le(x, Nat.add(origin_x, half))),
    Bool.and(Nat.is_ge(z, Nat.sub(origin_z, half)), Nat.is_le(z, Nat.add(origin_z, half)))
  )

def on_edge(+x: Nat, +z: Nat, +origin_x: Nat, +origin_z: Nat, +half: Nat) -> Bool:
  Bool.or(
    Bool.or(Nat.is_eq(x, Nat.sub(origin_x, half)), Nat.is_eq(x, Nat.add(origin_x, half))),
    Bool.or(Nat.is_eq(z, Nat.sub(origin_z, half)), Nat.is_eq(z, Nat.add(origin_z, half)))
  )

def house_door(+x: Nat, +y: Nat, +z: Nat, +origin_x: Nat, +origin_z: Nat, +base: Nat, +half: Nat) -> Bool:
  Bool.and(
    Bool.and(Nat.is_eq(x, origin_x), Nat.is_eq(z, Nat.sub(origin_z, half))),
    Bool.or(Nat.is_eq(y, Nat.add(base, 1n)), Nat.is_eq(y, Nat.add(base, 2n)))
  )

def house_window(+x: Nat, +y: Nat, +z: Nat, +origin_x: Nat, +origin_z: Nat, +base: Nat, +half: Nat) -> Bool:
  +window_height = Nat.is_eq(y, Nat.add(base, 2n))
  +side_window = Bool.or(
    Bool.and(Nat.is_eq(x, Nat.sub(origin_x, 2n)), Nat.is_eq(z, Nat.sub(origin_z, half))),
    Bool.and(Nat.is_eq(x, Nat.add(origin_x, 2n)), Nat.is_eq(z, Nat.sub(origin_z, half)))
  )
  +back_window = Bool.and(Nat.is_eq(x, origin_x), Nat.is_eq(z, Nat.add(origin_z, half)))
  Bool.and(window_height, Bool.or(side_window, back_window))

def house_block(
  +x: Nat, +y: Nat, +z: Nat, +origin_x: Nat, +origin_z: Nat,
  +base: Nat, +half: Nat, main: Bool
) -> U32:
  +inside = in_square(x, z, origin_x, origin_z, half)
  +floor = Nat.is_eq(y, base)
  +roof = Nat.is_eq(y, Nat.add(base, 4n))
  +wall_level = Bool.or(
    Bool.or(Nat.is_eq(y, Nat.add(base, 1n)), Nat.is_eq(y, Nat.add(base, 2n))),
    Nat.is_eq(y, Nat.add(base, 3n))
  )
  +edge = on_edge(x, z, origin_x, origin_z, half)
  +door = house_door(x, y, z, origin_x, origin_z, base, half)
  +window = house_window(x, y, z, origin_x, origin_z, base, half)
  +furnace = Bool.and(
    main,
    Bool.and(
      Bool.and(Nat.is_eq(x, origin_x), Nat.is_eq(z, origin_z)),
      Nat.is_eq(y, Nat.add(base, 1n))
    )
  )
  +bed = Bool.and(
    Bool.and(Nat.is_eq(x, Nat.add(origin_x, 2n)), Nat.is_eq(z, Nat.add(origin_z, 2n))),
    Nat.is_eq(y, Nat.add(base, 1n))
  )
  Bool.pick(U32, Bool.and(inside, roof), 5,
    Bool.pick(U32, Bool.and(inside, floor), 1,
      Bool.pick(U32, door, 14,
        Bool.pick(U32, bed, 13,
        Bool.pick(U32, furnace, 11,
        Bool.pick(U32, Bool.and(Bool.and(inside, Bool.and(wall_level, edge)), Bool.not(Bool.or(door, window))), 5, 0))))
        ))

def path_block(+x: Nat, +y: Nat, +z: Nat, +origin_x: Nat, +origin_z: Nat, +base: Nat) -> U32:
  +on_path = Bool.and(
    Bool.and(Nat.is_eq(x, origin_x), Nat.is_ge(z, Nat.sub(origin_z, 8n))),
    Nat.is_lt(z, Nat.sub(origin_z, 3n))
  )
  Bool.pick(U32, Bool.and(on_path, Nat.is_eq(y, base)), 1, 0)

def block.village(+x: Nat, +y: Nat, +z: Nat, +origin_x: Nat, +origin_z: Nat, +height: Nat) -> U32:
  +main = house_block(x, y, z, origin_x, origin_z, height, 4n, True{})
  +east = house_block(x, y, z, Nat.add(origin_x, 10n), origin_z, height, 3n, False{})
  +south = house_block(x, y, z, origin_x, Nat.add(origin_z, 10n), height, 3n, False{})
  +path = path_block(x, y, z, origin_x, origin_z, height)
  +structure = Bool.pick(U32, U32.is_ne(main, 0), main,
    Bool.pick(U32, U32.is_ne(east, 0), east,
      Bool.pick(U32, U32.is_ne(south, 0), south, path)))
  structure

def block(+seed: Nat, +x: Nat, +y: Nat, +z: Nat, +height: Nat) -> U32:
  +origin_x = village_origin_x(seed)
  +origin_z = village_origin_z(seed)
  +valid = village_height_valid(height)
  +near = Bool.and(
    Bool.and(Nat.is_ge(x, Nat.sub(origin_x, 8n)), Nat.is_lt(x, Nat.add(origin_x, 14n))),
    Bool.and(Nat.is_ge(z, Nat.sub(origin_z, 8n)), Nat.is_lt(z, Nat.add(origin_z, 14n)))
  )
  Bool.pick(U32, Bool.and(valid, near), block.village(x, y, z, origin_x, origin_z, height), 0)
