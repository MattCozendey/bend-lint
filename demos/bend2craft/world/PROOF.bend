# PROOF.bend: every law of LAWS.bend, closed. `npm run proof` prints ALL PROOFS CHECK
# when they hold and SOME PROOFS FAIL with the first that does not.
#
# A law on values is closed by `{==}`: both sides compute to the same term. A law
# with a `for` is proved here by cases and induction. Three moves do most of it:
#
# - a computed condition cannot be matched, so the lemma takes it as a parameter
#   (`valid: Bool`) and is called with the condition; when the case needs to know
#   which condition it was, the lemma also takes `{condition == valid}`;
# - `%e : P` rewrites the goal with `e : {a == b}`: `P` is the goal with `_` where
#   `b` stands, and the goal becomes `P` with `a` there;
# - an impossible case holds a proof of `{True{} == False{}}`, which `is_true`
#   turns into `Empty`.

import Base
import ./LAWS.bend as Laws
import ./world.bend as World
import ./world_state.bend as WorldState
import ./inventory.bend as Inventory
import ./equipment.bend as Equipment
import ./furnace.bend as Furnace
import ./chest.bend as Chest
import ./farmland.bend as Farmland
import ./crops.bend as Crops

# --- booleans ----------------------------------------------------------------------

def is_true(b: Bool) -> Type:
  match b:
    case True{}:
      Unit
    case False{}:
      Empty

def true_is_not_false(e: {True{} == False{} : Bool}) -> Empty:
  %e : is_true(_)
  Unit{}

def false_is_not_true(e: {False{} == True{} : Bool}) -> Empty:
  %Equal.sym(Bool, False{}, True{}, e) : is_true(_)
  Unit{}

def and_false(a: Bool) -> {Bool.and(a, False{}) == False{} : Bool}:
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

def or_false_right(b: Bool) -> {Bool.or(False{}, b) == b : Bool}:
  match b:
    case False{}:
      {==}
    case True{}:
      {==}

def false_is_and(a: Bool) -> {False{} == Bool.and(a, False{}) : Bool}:
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

def and_left(a: Bool, b: Bool, h: {Bool.and(a, b) == True{} : Bool}) -> {a == True{} : Bool}:
  match a:
    case False{}:
      Empty.absurd({False{} == True{} : Bool}, false_is_not_true(h))
    case True{}:
      {==}

def and_right(a: Bool, b: Bool, h: {Bool.and(a, b) == True{} : Bool}) -> {b == True{} : Bool}:
  match a:
    case False{}:
      Empty.absurd({b == True{} : Bool}, false_is_not_true(h))
    case True{}:
      h

# --- naturals ----------------------------------------------------------------------

def nat_eq_refl(a: Nat) -> {Nat.is_eq(a, a) == True{} : Bool}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      nat_eq_refl(p)

def nat_ne_refl(a: Nat) -> {Nat.is_ne(a, a) == False{} : Bool}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      nat_ne_refl(p)

def nat_eq_true(a: Nat, b: Nat, h: {Nat.is_eq(a, b) == True{} : Bool}) -> {a == b : Nat}:
  match a b:
    case 0n 0n:
      {==}
    case 0n 1n+q:
      Empty.absurd({0n == 1n+q : Nat}, false_is_not_true(h))
    case 1n+p 0n:
      Empty.absurd({1n+p == 0n : Nat}, false_is_not_true(h))
    case 1n+p 1n+q:
      %nat_eq_true(p, q, h) : {1n+p == 1n+_ : Nat}
      {==}

def lt_zero(k: Nat) -> {Nat.is_lt(k, 0n) == False{} : Bool}:
  match k:
    case 0n:
      {==}
    case 1n+p:
      {==}

def lt_succ(h: Nat) -> {Nat.is_lt(h, 1n+h) == True{} : Bool}:
  match h:
    case 0n:
      {==}
    case 1n+p:
      lt_succ(p)

def not_lt_add(h: Nat, k: Nat) -> {Nat.is_lt(Nat.add(h, k), h) == False{} : Bool}:
  match h:
    case 0n:
      lt_zero(k)
    case 1n+p:
      not_lt_add(p, k)

def add_zero(a: Nat) -> {Nat.add(a, 0n) == a : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_zero(p) : {1n+Nat.add(p, 0n) == 1n+_ : Nat}
      {==}

def add_one(a: Nat) -> {Nat.add(a, 1n) == 1n+a : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_one(p) : {1n+Nat.add(p, 1n) == 1n+_ : Nat}
      {==}

def sub_zero(a: Nat) -> {Nat.sub(a, 0n) == a : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      {==}

def add_shift(k: Nat, +i: Nat) -> {Nat.add(Nat.add(k, 1n), i) == Nat.add(k, 1n+i) : Nat}:
  match k:
    case 0n:
      {==}
    case 1n+q:
      %add_shift(q, i) : {1n+Nat.add(Nat.add(q, 1n), i) == 1n+_ : Nat}
      {==}

# three coordinates are the cell they are
def same_cell(+x: Nat, +y: Nat, +z: Nat) -> {Bool.and(Bool.and(Nat.is_eq(x, x), Nat.is_eq(y, y)), Nat.is_eq(z, z)) == True{} : Bool}:
  %Equal.sym(Bool, Nat.is_eq(x, x), True{}, nat_eq_refl(x)) : {Bool.and(Bool.and(_, Nat.is_eq(y, y)), Nat.is_eq(z, z)) == True{} : Bool}
  %Equal.sym(Bool, Nat.is_eq(y, y), True{}, nat_eq_refl(y)) : {Bool.and(_, Nat.is_eq(z, z)) == True{} : Bool}
  nat_eq_refl(z)

# --- the generated world -------------------------------------------------------------

def Laws.air_above_surface():
  {==}

def Laws.surface_is_grass():
  {==}

def Laws.known_tree_wood():
  {==}

def Laws.known_tree_leaf():
  {==}

def Laws.beach_is_sand():
  {==}

def Laws.sea_surface_is_water():
  {==}

def Laws.cave_is_air():
  {==}

def Laws.caves_run():
  {==}

def Laws.ground_beside_a_cave_is_solid():
  {==}

def Laws.known_coal_ore():
  {==}

def Laws.known_iron_ore():
  {==}

def Laws.known_diamond_ore():
  {==}

def Laws.known_village_furnace():
  {==}

def Laws.a_chunk_holds_its_cells():
  {==}

def Laws.the_origin_shift_is_a_whole_number_of_terrain_periods():
  {==}

# what `World.terrain_block_height` answers for a cell inside the column
def inside_column(+h: Nat, +y: Nat) -> U32:
  Bool.pick(U32, World.same(y, Nat.sub(h, 1n)), Bool.pick(U32, Nat.is_le(h, World.sea_level()), 6, 3),
    Bool.pick(U32, World.same(y, Nat.sub(h, 2n)), Bool.pick(U32, Nat.is_le(h, World.sea_level()), 6, 2),
      Bool.pick(U32, Nat.is_lt(y, Nat.sub(h, 3n)), 1, 2)))

def Laws.above_a_column_is_air(h, k):
  %Equal.sym(Bool, Nat.is_lt(Nat.add(h, k), h), False{}, not_lt_add(h, k)) : {Bool.pick(U32, _, inside_column(h, Nat.add(h, k)), 0) == 0 : U32}
  {==}

def surface(+h: Nat) -> U32:
  Bool.pick(U32, Nat.is_le(1n+h, World.sea_level()), 6, 3)

def under_surface(+h: Nat) -> U32:
  Bool.pick(U32, World.same(h, Nat.sub(1n+h, 2n)), Bool.pick(U32, Nat.is_le(1n+h, World.sea_level()), 6, 2),
    Bool.pick(U32, Nat.is_lt(h, Nat.sub(1n+h, 3n)), 1, 2))

def Laws.the_surface_is_sand_by_the_sea_and_grass_above(h):
  %Equal.sym(Bool, Nat.is_lt(h, 1n+h), True{}, lt_succ(h)) : {Bool.pick(U32, _, Bool.pick(U32, Nat.is_eq(h, Nat.sub(h, 0n)), surface(h), under_surface(h)), 0) == surface(h) : U32}
  %Equal.sym(Nat, Nat.sub(h, 0n), h, sub_zero(h)) : {Bool.pick(U32, Nat.is_eq(h, _), surface(h), under_surface(h)) == surface(h) : U32}
  %Equal.sym(Bool, Nat.is_eq(h, h), True{}, nat_eq_refl(h)) : {Bool.pick(U32, _, surface(h), under_surface(h)) == surface(h) : U32}
  {==}

def Laws.no_generated_water_above_the_sea(h, k):
  %Equal.sym(Bool, Nat.is_lt(k, 0n), False{}, lt_zero(k)) : {Bool.and(Nat.is_le(h, Nat.add(1n+World.sea_level(), k)), _) == False{} : Bool}
  and_false(Nat.is_le(h, Nat.add(1n+World.sea_level(), k)))

# --- the edit log, said forward ------------------------------------------------------
# `WorldState.set` finds the cell's entry with a running index and rebuilds the log
# through an accumulator. `find`, `put` and `placed` say the same thing without
# either, and the first lemmas show that they are the same thing.

def shift(p: WorldState.Position) -> WorldState.Position:
  match p:
    case WorldState.At{i}:
      WorldState.At{1n+i}
    case WorldState.Missing{}:
      WorldState.Missing{}

def find.at(m: Bool, rest: WorldState.Position) -> WorldState.Position:
  match m:
    case True{}:
      WorldState.At{0n}
    case False{}:
      shift(rest)

# where the cell's entry is, counted from the head
def find(edits: List<&2, WorldState.Edit>, +x: Nat, +y: Nat, +z: Nat) -> WorldState.Position:
  match edits:
    case Nil{}:
      WorldState.Missing{}
    case Con{+head, tail}:
      find.at(WorldState.edit_matches(head, x, y, z), find(tail, x, y, z))

def offset(+k: Nat, p: WorldState.Position) -> WorldState.Position:
  match p:
    case WorldState.At{i}:
      WorldState.At{Nat.add(k, i)}
    case WorldState.Missing{}:
      WorldState.Missing{}

def put(edits: List<&2, WorldState.Edit>, index: Nat, edit: WorldState.Edit) -> List<&2, WorldState.Edit>:
  match edits:
    case Nil{}:
      Nil{}
    case Con{head, tail}:
      match index:
        case 0n:
          Con{edit, tail}
        case 1n+p:
          Con{head, put(tail, p, edit)}

def placed(p: WorldState.Position, +edits: List<&2, WorldState.Edit>, +edit: WorldState.Edit) -> List<&2, WorldState.Edit>:
  match p:
    case WorldState.At{i}:
      put(edits, i, edit)
    case WorldState.Missing{}:
      Con{edit, edits}

def E(+x: Nat, +y: Nat, +z: Nat, +block: U32) -> WorldState.Edit:
  WorldState.make_edit(x, y, z, block)

# the index a stopped walk answers: one before the next
def back_one(+k: Nat) -> {Nat.sub(Nat.add(k, 1n), 1n) == Nat.add(k, 0n) : Nat}:
  %Equal.sym(Nat, Nat.add(k, 0n), k, add_zero(k)) : {Nat.sub(Nat.add(k, 1n), 1n) == _ : Nat}
  %Equal.sym(Nat, Nat.add(k, 1n), 1n+k, add_one(k)) : {Nat.sub(_, 1n) == k : Nat}
  sub_zero(k)

def offset_shift(+k: Nat, p: WorldState.Position) -> {offset(Nat.add(k, 1n), p) == offset(k, shift(p)) : WorldState.Position}:
  match p:
    case WorldState.At{+i}:
      %add_shift(k, i) : {WorldState.At{Nat.add(Nat.add(k, 1n), i)} == WorldState.At{_} : WorldState.Position}
      {==}
    case WorldState.Missing{}:
      {==}

def walk_stopped(t: List<&2, WorldState.Edit>, +x: Nat, +y: Nat, +z: Nat, +k: Nat) -> {WorldState.position.go(t, True{}, x, y, z, Nat.add(k, 1n)) == WorldState.At{Nat.add(k, 0n)} : WorldState.Position}:
  match t:
    case Nil{}:
      %back_one(k) : {WorldState.At{Nat.sub(Nat.add(k, 1n), 1n)} == WorldState.At{_} : WorldState.Position}
      {==}
    case Con{head, tail}:
      %back_one(k) : {WorldState.At{Nat.sub(Nat.add(k, 1n), 1n)} == WorldState.At{_} : WorldState.Position}
      {==}

def walk_step(+t: List<&2, WorldState.Edit>, +x: Nat, +y: Nat, +z: Nat, +k: Nat, m: Bool,
  ih: {WorldState.position.go(t, False{}, x, y, z, Nat.add(k, 1n)) == offset(Nat.add(k, 1n), find(t, x, y, z)) : WorldState.Position}) ->
  {WorldState.position.go(t, m, x, y, z, Nat.add(k, 1n)) == offset(k, find.at(m, find(t, x, y, z))) : WorldState.Position}:
  match m:
    case True{}:
      walk_stopped(t, x, y, z, k)
    case False{}:
      Equal.trans(WorldState.Position, WorldState.position.go(t, False{}, x, y, z, Nat.add(k, 1n)), offset(Nat.add(k, 1n), find(t, x, y, z)), offset(k, shift(find(t, x, y, z))), ih, offset_shift(k, find(t, x, y, z)))

# the indexed walk is the forward search
def walk_is_find(edits: List<&2, WorldState.Edit>, +x: Nat, +y: Nat, +z: Nat, +k: Nat) -> {WorldState.position.go(edits, False{}, x, y, z, k) == offset(k, find(edits, x, y, z)) : WorldState.Position}:
  match edits:
    case Nil{}:
      {==}
    case Con{+head, +tail}:
      walk_step(tail, x, y, z, k, WorldState.edit_matches(head, x, y, z), walk_is_find(tail, x, y, z, Nat.add(k, 1n)))

# the rebuild through the accumulator is the forward replace
def rebuild_is_put(edits: List<&2, WorldState.Edit>, index: Nat, +acc: List<&2, WorldState.Edit>, +edit: WorldState.Edit) -> {WorldState.replace_at(edits, index, acc, edit) == WorldState.rev_append(acc, put(edits, index, edit)) : List<&2, WorldState.Edit>}:
  match edits:
    case Nil{}:
      match index:
        case 0n:
          {==}
        case 1n+p:
          {==}
    case Con{+head, tail}:
      match index:
        case 0n:
          {==}
        case 1n+p:
          rebuild_is_put(tail, p, Con{head, acc}, edit)

def set_at_is_placed(p: WorldState.Position, +edits: List<&2, WorldState.Edit>, +edit: WorldState.Edit) -> {WorldState.set.at(offset(0n, p), edits, edit) == placed(p, edits, edit) : List<&2, WorldState.Edit>}:
  match p:
    case WorldState.At{+i}:
      rebuild_is_put(edits, i, Nil{}, edit)
    case WorldState.Missing{}:
      {==}

def set_is_placed(+edits: List<&2, WorldState.Edit>, +x: Nat, +y: Nat, +z: Nat, +block: U32) -> {WorldState.set(edits, x, y, z, block) == placed(find(edits, x, y, z), edits, E(x, y, z, block)) : List<&2, WorldState.Edit>}:
  %Equal.sym(WorldState.Position, WorldState.position.go(edits, False{}, x, y, z, 0n), offset(0n, find(edits, x, y, z)), walk_is_find(edits, x, y, z, 0n)) : {WorldState.set.at(_, edits, E(x, y, z, block)) == placed(find(edits, x, y, z), edits, E(x, y, z, block)) : List<&2, WorldState.Edit>}
  set_at_is_placed(find(edits, x, y, z), edits, E(x, y, z, block))

# --- the edit log: a placed edit reads back -------------------------------------------

def read_stopped(edits: List<&2, WorldState.Edit>, +value: U32, +seed: Nat, +x: Nat, +y: Nat, +z: Nat) -> {WorldState.block.go(edits, True{}, value, seed, x, y, z) == value : U32}:
  match edits:
    case Nil{}:
      {==}
    case Con{head, tail}:
      {==}

# the new entry at the head of any log answers its own block
def read_new(+rest: List<&2, WorldState.Edit>, +value: U32, +seed: Nat, +x: Nat, +y: Nat, +z: Nat, +block: U32) -> {WorldState.block.go(Con{E(x, y, z, block), rest}, False{}, value, seed, x, y, z) == block : U32}:
  %Equal.sym(Bool, WorldState.edit_matches(E(x, y, z, block), x, y, z), True{}, same_cell(x, y, z)) : {WorldState.block.go(rest, _, block, seed, x, y, z) == block : U32}
  read_stopped(rest, block, seed, x, y, z)

def read_past(+head: WorldState.Edit, +tail: List<&2, WorldState.Edit>, +value: U32, +seed: Nat, +x: Nat, +y: Nat, +z: Nat, +block: U32, p: WorldState.Position,
  hm: {WorldState.edit_matches(head, x, y, z) == False{} : Bool},
  ih: {WorldState.block.go(placed(p, tail, E(x, y, z, block)), False{}, WorldState.edit_value(head), seed, x, y, z) == block : U32}) ->
  {WorldState.block.go(placed(shift(p), Con{head, tail}, E(x, y, z, block)), False{}, value, seed, x, y, z) == block : U32}:
  match p:
    case WorldState.At{+j}:
      %Equal.sym(Bool, WorldState.edit_matches(head, x, y, z), False{}, hm) : {WorldState.block.go(put(tail, j, E(x, y, z, block)), _, WorldState.edit_value(head), seed, x, y, z) == block : U32}
      ih
    case WorldState.Missing{}:
      read_new(Con{head, tail}, value, seed, x, y, z, block)

def read_entry(+head: WorldState.Edit, +tail: List<&2, WorldState.Edit>, +value: U32, +seed: Nat, +x: Nat, +y: Nat, +z: Nat, +block: U32, m: Bool,
  hm: {WorldState.edit_matches(head, x, y, z) == m : Bool},
  ih: {WorldState.block.go(placed(find(tail, x, y, z), tail, E(x, y, z, block)), False{}, WorldState.edit_value(head), seed, x, y, z) == block : U32}) ->
  {WorldState.block.go(placed(find.at(m, find(tail, x, y, z)), Con{head, tail}, E(x, y, z, block)), False{}, value, seed, x, y, z) == block : U32}:
  match m:
    case True{}:
      read_new(tail, value, seed, x, y, z, block)
    case False{}:
      read_past(head, tail, value, seed, x, y, z, block, find(tail, x, y, z), hm, ih)

def read_placed(edits: List<&2, WorldState.Edit>, +value: U32, +seed: Nat, +x: Nat, +y: Nat, +z: Nat, +block: U32) -> {WorldState.block.go(placed(find(edits, x, y, z), edits, E(x, y, z, block)), False{}, value, seed, x, y, z) == block : U32}:
  match edits:
    case Nil{}:
      read_new(Nil{}, value, seed, x, y, z, block)
    case Con{+head, +tail}:
      read_entry(head, tail, value, seed, x, y, z, block, WorldState.edit_matches(head, x, y, z), {==}, read_placed(tail, WorldState.edit_value(head), seed, x, y, z, block))

def Laws.an_empty_log_is_the_generated_world(seed, x, y, z):
  {==}

def Laws.an_edit_reads_back(edits, seed, x, y, z, block):
  %Equal.sym(List<&2, WorldState.Edit>, WorldState.set(edits, x, y, z, block), placed(find(edits, x, y, z), edits, E(x, y, z, block)), set_is_placed(edits, x, y, z, block)) : {WorldState.block.go(_, False{}, 0, seed, x, y, z) == block : U32}
  read_placed(edits, 0, seed, x, y, z, block)

# --- the edit log: an edit leaves every other cell alone -------------------------------

# an entry of the edited cell is not an entry of another cell
def other_entry(head: WorldState.Edit, +x: Nat, +y: Nat, +z: Nat, +block: U32, +ox: Nat, +oy: Nat, +oz: Nat,
  +hm: {WorldState.edit_matches(head, x, y, z) == True{} : Bool},
  apart: {WorldState.edit_matches(E(x, y, z, block), ox, oy, oz) == False{} : Bool}) ->
  {WorldState.edit_matches(head, ox, oy, oz) == False{} : Bool}:
  match head:
    case WorldState.Edit{+hx, +hy, +hz, hb}:
      %Equal.sym(Nat, hx, x, nat_eq_true(hx, x, and_left(Nat.is_eq(hx, x), Nat.is_eq(hy, y), and_left(Bool.and(Nat.is_eq(hx, x), Nat.is_eq(hy, y)), Nat.is_eq(hz, z), hm)))) : {Bool.and(Bool.and(Nat.is_eq(_, ox), Nat.is_eq(hy, oy)), Nat.is_eq(hz, oz)) == False{} : Bool}
      %Equal.sym(Nat, hy, y, nat_eq_true(hy, y, and_right(Nat.is_eq(hx, x), Nat.is_eq(hy, y), and_left(Bool.and(Nat.is_eq(hx, x), Nat.is_eq(hy, y)), Nat.is_eq(hz, z), hm)))) : {Bool.and(Bool.and(Nat.is_eq(x, ox), Nat.is_eq(_, oy)), Nat.is_eq(hz, oz)) == False{} : Bool}
      %Equal.sym(Nat, hz, z, nat_eq_true(hz, z, and_right(Bool.and(Nat.is_eq(hx, x), Nat.is_eq(hy, y)), Nat.is_eq(hz, z), hm))) : {Bool.and(Bool.and(Nat.is_eq(x, ox), Nat.is_eq(y, oy)), Nat.is_eq(_, oz)) == False{} : Bool}
      apart

# a walk that has not stopped does not read the value it carries
def read_carries_nothing(edits: List<&2, WorldState.Edit>, +a: U32, +b: U32, +seed: Nat, +x: Nat, +y: Nat, +z: Nat) -> {WorldState.block.go(edits, False{}, a, seed, x, y, z) == WorldState.block.go(edits, False{}, b, seed, x, y, z) : U32}:
  match edits:
    case Nil{}:
      {==}
    case Con{head, tail}:
      {==}

# the new entry at the head of a log is walked past by another cell
def other_new(+rest: List<&2, WorldState.Edit>, +value: U32, +seed: Nat, +x: Nat, +y: Nat, +z: Nat, +block: U32, +ox: Nat, +oy: Nat, +oz: Nat,
  apart: {WorldState.edit_matches(E(x, y, z, block), ox, oy, oz) == False{} : Bool}) ->
  {WorldState.block.go(Con{E(x, y, z, block), rest}, False{}, value, seed, ox, oy, oz) == WorldState.block.go(rest, False{}, value, seed, ox, oy, oz) : U32}:
  %Equal.sym(Bool, WorldState.edit_matches(E(x, y, z, block), ox, oy, oz), False{}, apart) : {WorldState.block.go(rest, _, block, seed, ox, oy, oz) == WorldState.block.go(rest, False{}, value, seed, ox, oy, oz) : U32}
  read_carries_nothing(rest, block, value, seed, ox, oy, oz)

# past an entry of some other cell: the rest of the walk is the same walk either way
def other_past(+head: WorldState.Edit, +tail: List<&2, WorldState.Edit>, +seed: Nat, +x: Nat, +y: Nat, +z: Nat, +block: U32, +ox: Nat, +oy: Nat, +oz: Nat, +j: Nat, stop: Bool,
  ih: {WorldState.block.go(put(tail, j, E(x, y, z, block)), False{}, WorldState.edit_value(head), seed, ox, oy, oz) == WorldState.block.go(tail, False{}, WorldState.edit_value(head), seed, ox, oy, oz) : U32}) ->
  {WorldState.block.go(put(tail, j, E(x, y, z, block)), stop, WorldState.edit_value(head), seed, ox, oy, oz) == WorldState.block.go(tail, stop, WorldState.edit_value(head), seed, ox, oy, oz) : U32}:
  match stop:
    case True{}:
      %Equal.sym(U32, WorldState.block.go(tail, True{}, WorldState.edit_value(head), seed, ox, oy, oz), WorldState.edit_value(head), read_stopped(tail, WorldState.edit_value(head), seed, ox, oy, oz)) : {WorldState.block.go(put(tail, j, E(x, y, z, block)), True{}, WorldState.edit_value(head), seed, ox, oy, oz) == _ : U32}
      read_stopped(put(tail, j, E(x, y, z, block)), WorldState.edit_value(head), seed, ox, oy, oz)
    case False{}:
      ih

def other_shifted(+head: WorldState.Edit, +tail: List<&2, WorldState.Edit>, +value: U32, +seed: Nat, +x: Nat, +y: Nat, +z: Nat, +block: U32, +ox: Nat, +oy: Nat, +oz: Nat, p: WorldState.Position,
  apart: {WorldState.edit_matches(E(x, y, z, block), ox, oy, oz) == False{} : Bool},
  ih: {WorldState.block.go(placed(p, tail, E(x, y, z, block)), False{}, WorldState.edit_value(head), seed, ox, oy, oz) == WorldState.block.go(tail, False{}, WorldState.edit_value(head), seed, ox, oy, oz) : U32}) ->
  {WorldState.block.go(placed(shift(p), Con{head, tail}, E(x, y, z, block)), False{}, value, seed, ox, oy, oz) == WorldState.block.go(Con{head, tail}, False{}, value, seed, ox, oy, oz) : U32}:
  match p:
    case WorldState.At{+j}:
      other_past(head, tail, seed, x, y, z, block, ox, oy, oz, j, WorldState.edit_matches(head, ox, oy, oz), ih)
    case WorldState.Missing{}:
      other_new(Con{head, tail}, value, seed, x, y, z, block, ox, oy, oz, apart)

# at the entry of the edited cell itself: it is replaced, and the other cell walks past both
def other_replaced(+head: WorldState.Edit, +tail: List<&2, WorldState.Edit>, +value: U32, +seed: Nat, +x: Nat, +y: Nat, +z: Nat, +block: U32, +ox: Nat, +oy: Nat, +oz: Nat,
  +hm: {WorldState.edit_matches(head, x, y, z) == True{} : Bool},
  +apart: {WorldState.edit_matches(E(x, y, z, block), ox, oy, oz) == False{} : Bool}) ->
  {WorldState.block.go(Con{E(x, y, z, block), tail}, False{}, value, seed, ox, oy, oz) == WorldState.block.go(Con{head, tail}, False{}, value, seed, ox, oy, oz) : U32}:
  %Equal.sym(Bool, WorldState.edit_matches(head, ox, oy, oz), False{}, other_entry(head, x, y, z, block, ox, oy, oz, hm, apart)) : {WorldState.block.go(Con{E(x, y, z, block), tail}, False{}, value, seed, ox, oy, oz) == WorldState.block.go(tail, _, WorldState.edit_value(head), seed, ox, oy, oz) : U32}
  %read_carries_nothing(tail, value, WorldState.edit_value(head), seed, ox, oy, oz) : {WorldState.block.go(Con{E(x, y, z, block), tail}, False{}, value, seed, ox, oy, oz) == _ : U32}
  other_new(tail, value, seed, x, y, z, block, ox, oy, oz, apart)

def other_entry_case(+head: WorldState.Edit, +tail: List<&2, WorldState.Edit>, +value: U32, +seed: Nat, +x: Nat, +y: Nat, +z: Nat, +block: U32, +ox: Nat, +oy: Nat, +oz: Nat, m: Bool,
  +hm: {WorldState.edit_matches(head, x, y, z) == m : Bool},
  +apart: {WorldState.edit_matches(E(x, y, z, block), ox, oy, oz) == False{} : Bool},
  ih: {WorldState.block.go(placed(find(tail, x, y, z), tail, E(x, y, z, block)), False{}, WorldState.edit_value(head), seed, ox, oy, oz) == WorldState.block.go(tail, False{}, WorldState.edit_value(head), seed, ox, oy, oz) : U32}) ->
  {WorldState.block.go(placed(find.at(m, find(tail, x, y, z)), Con{head, tail}, E(x, y, z, block)), False{}, value, seed, ox, oy, oz) == WorldState.block.go(Con{head, tail}, False{}, value, seed, ox, oy, oz) : U32}:
  match m:
    case True{}:
      other_replaced(head, tail, value, seed, x, y, z, block, ox, oy, oz, hm, apart)
    case False{}:
      other_shifted(head, tail, value, seed, x, y, z, block, ox, oy, oz, find(tail, x, y, z), apart, ih)

def other_placed(edits: List<&2, WorldState.Edit>, +value: U32, +seed: Nat, +x: Nat, +y: Nat, +z: Nat, +block: U32, +ox: Nat, +oy: Nat, +oz: Nat,
  +apart: {WorldState.edit_matches(E(x, y, z, block), ox, oy, oz) == False{} : Bool}) ->
  {WorldState.block.go(placed(find(edits, x, y, z), edits, E(x, y, z, block)), False{}, value, seed, ox, oy, oz) == WorldState.block.go(edits, False{}, value, seed, ox, oy, oz) : U32}:
  match edits:
    case Nil{}:
      other_new(Nil{}, value, seed, x, y, z, block, ox, oy, oz, apart)
    case Con{+head, +tail}:
      other_entry_case(head, tail, value, seed, x, y, z, block, ox, oy, oz, WorldState.edit_matches(head, x, y, z), {==}, apart,
        other_placed(tail, WorldState.edit_value(head), seed, x, y, z, block, ox, oy, oz, apart))

def Laws.an_edit_keeps_every_other_cell(edits, seed, x, y, z, block, ox, oy, oz, apart):
  %Equal.sym(List<&2, WorldState.Edit>, WorldState.set(edits, x, y, z, block), placed(find(edits, x, y, z), edits, E(x, y, z, block)), set_is_placed(edits, x, y, z, block)) : {WorldState.block.go(_, False{}, 0, seed, ox, oy, oz) == WorldState.block.go(edits, False{}, 0, seed, ox, oy, oz) : U32}
  other_placed(edits, 0, seed, x, y, z, block, ox, oy, oz, apart)

def Laws.the_last_edit_of_a_batch_wins():
  {==}

# --- the inventory: refusals ---------------------------------------------------------

def Laws.mining_the_bottom_layer_is_refused(bag, tool, block):
  {==}

# `can_place` once one of its three conditions fails, under any test of the slot
def refuse_occupied(a: Bool, p: Bool, i: Bool, n: Bool) -> {False{} == Bool.and(a, Bool.and(Bool.and(Bool.and(p, False{}), i), n)) : Bool}:
  match a p:
    case False{} _:
      {==}
    case True{} False{}:
      {==}
    case True{} True{}:
      {==}

def refuse_outside(a: Bool, p: Bool, t: Bool, n: Bool) -> {False{} == Bool.and(a, Bool.and(Bool.and(Bool.and(p, t), False{}), n)) : Bool}:
  match a p t:
    case False{} _ _:
      {==}
    case True{} False{} _:
      {==}
    case True{} True{} False{}:
      {==}
    case True{} True{} True{}:
      {==}

def refuse_overlap(a: Bool, p: Bool, t: Bool, i: Bool) -> {False{} == Bool.and(a, Bool.and(Bool.and(Bool.and(p, t), i), False{})) : Bool}:
  match a p t i:
    case False{} _ _ _:
      {==}
    case True{} False{} _ _:
      {==}
    case True{} True{} False{} _:
      {==}
    case True{} True{} True{} False{}:
      {==}
    case True{} True{} True{} True{}:
      {==}

def place_occupied(+bag: List<&2, Inventory.Slot>, +index: Nat, +item: U32, +inside: Bool, +over: Bool, l: Inventory.Lookup) -> {Inventory.place.lookup(bag, index, item, False{}, inside, over, l) == Inventory.result(bag, False{}) : Inventory.InventoryResult}:
  match l:
    case Inventory.Missing{}:
      {==}
    case Inventory.Found{+slot}:
      %refuse_occupied(U32.is_eq(Inventory.slot_item(slot), item), Inventory.is_placeable(item), inside, Bool.not(over)) : {Inventory.place.valid(bag, index, _) == Inventory.result(bag, False{}) : Inventory.InventoryResult}
      {==}

def Laws.placing_into_an_occupied_cell_is_refused(bag, index, item, inside, over):
  place_occupied(bag, index, item, inside, over, Inventory.lookup(bag, index))

def place_outside(+bag: List<&2, Inventory.Slot>, +index: Nat, +item: U32, +empty: Bool, +over: Bool, l: Inventory.Lookup) -> {Inventory.place.lookup(bag, index, item, empty, False{}, over, l) == Inventory.result(bag, False{}) : Inventory.InventoryResult}:
  match l:
    case Inventory.Missing{}:
      {==}
    case Inventory.Found{+slot}:
      %refuse_outside(U32.is_eq(Inventory.slot_item(slot), item), Inventory.is_placeable(item), empty, Bool.not(over)) : {Inventory.place.valid(bag, index, _) == Inventory.result(bag, False{}) : Inventory.InventoryResult}
      {==}

def Laws.placing_outside_the_world_is_refused(bag, index, item, empty, over):
  place_outside(bag, index, item, empty, over, Inventory.lookup(bag, index))

def place_overlap(+bag: List<&2, Inventory.Slot>, +index: Nat, +item: U32, +empty: Bool, +inside: Bool, l: Inventory.Lookup) -> {Inventory.place.lookup(bag, index, item, empty, inside, True{}, l) == Inventory.result(bag, False{}) : Inventory.InventoryResult}:
  match l:
    case Inventory.Missing{}:
      {==}
    case Inventory.Found{+slot}:
      %refuse_overlap(U32.is_eq(Inventory.slot_item(slot), item), Inventory.is_placeable(item), empty, inside) : {Inventory.place.valid(bag, index, _) == Inventory.result(bag, False{}) : Inventory.InventoryResult}
      {==}

def Laws.placing_into_the_player_is_refused(bag, index, item, empty, inside):
  place_overlap(bag, index, item, empty, inside, Inventory.lookup(bag, index))

def Laws.consuming_nothing_is_refused(bag, index):
  %false_is_and(Nat.is_lt(index, Inventory.slot_count())) : {Inventory.consume.if(bag, index, U32.from_nat(0n), _) == Inventory.result(bag, False{}) : Inventory.InventoryResult}
  {==}

def Laws.moving_a_slot_onto_itself_is_refused(bag, index, amount):
  %Equal.sym(Bool, Nat.is_ne(index, index), False{}, nat_ne_refl(index)) : {Inventory.move.if(bag, index, index, U32.from_nat(amount), Bool.and(Bool.and(Nat.is_lt(index, Inventory.slot_count()), Nat.is_lt(index, Inventory.slot_count())), _)) == Inventory.result(bag, False{}) : Inventory.InventoryResult}
  %false_is_and(Bool.and(Nat.is_lt(index, Inventory.slot_count()), Nat.is_lt(index, Inventory.slot_count()))) : {Inventory.move.if(bag, index, index, U32.from_nat(amount), _) == Inventory.result(bag, False{}) : Inventory.InventoryResult}
  {==}

def Laws.crafting_past_the_recipes_is_refused(bag, k):
  match k:
    case 0n:
      {==}
    case 1n+p:
      {==}

# --- the inventory: a refused interaction keeps the bag --------------------------------

def mine_used(+edit: WorldState.Edit, +original: List<&2, Inventory.Slot>, collected_ok: Bool, used: Inventory.InventoryResult,
  h: {Laws.interaction_ok(Inventory.mine_interaction_at_finish_used(edit, original, collected_ok, used)) == False{} : Bool}) ->
  {Laws.interaction_slots(Inventory.mine_interaction_at_finish_used(edit, original, collected_ok, used)) == original : List<&2, Inventory.Slot>}:
  match collected_ok:
    case False{}:
      match used:
        case Inventory.InventoryResult{used_slots, used_ok}:
          {==}
    case True{}:
      match used:
        case Inventory.InventoryResult{used_slots, used_ok}:
          match used_ok:
            case False{}:
              {==}
            case True{}:
              Empty.absurd({used_slots == original : List<&2, Inventory.Slot>}, true_is_not_false(h))

def mine_mode(+edit: WorldState.Edit, +original: List<&2, Inventory.Slot>, +index: Nat, +bag: List<&2, Inventory.Slot>, tool_empty: Bool, collected_ok: Bool,
  h: {Laws.interaction_ok(Inventory.mine_interaction_at_finish_mode(edit, original, index, bag, collected_ok, tool_empty)) == False{} : Bool}) ->
  {Laws.interaction_slots(Inventory.mine_interaction_at_finish_mode(edit, original, index, bag, collected_ok, tool_empty)) == original : List<&2, Inventory.Slot>}:
  match tool_empty:
    case True{}:
      match collected_ok:
        case False{}:
          {==}
        case True{}:
          Empty.absurd({bag == original : List<&2, Inventory.Slot>}, true_is_not_false(h))
    case False{}:
      mine_used(edit, original, collected_ok, Inventory.use_tool_at(bag, index), h)

def mine_collected(+edit: WorldState.Edit, +original: List<&2, Inventory.Slot>, +index: Nat, +tool: U32, state: Inventory.InventoryResult,
  h: {Laws.interaction_ok(Inventory.mine_interaction_at_finish_collected(edit, original, index, tool, state)) == False{} : Bool}) ->
  {Laws.interaction_slots(Inventory.mine_interaction_at_finish_collected(edit, original, index, tool, state)) == original : List<&2, Inventory.Slot>}:
  match state:
    case Inventory.InventoryResult{+bag, collected_ok}:
      mine_mode(edit, original, index, bag, U32.is_eq(Inventory.tool_max_durability(tool), 0), collected_ok, h)

def Laws.a_refused_mining_keeps_the_bag(bag, index, tool, block, x, y, z, h):
  mine_collected(WorldState.make_edit(x, y, z, 0), bag, index, tool, Inventory.mine_collect_at(bag, tool, block, x, y, z), h)

def place_finish(+edit: WorldState.Edit, +original: List<&2, Inventory.Slot>, state: Inventory.InventoryResult,
  h: {Laws.interaction_ok(Inventory.interaction.finish(edit, original, state)) == False{} : Bool}) ->
  {Laws.interaction_slots(Inventory.interaction.finish(edit, original, state)) == original : List<&2, Inventory.Slot>}:
  match state:
    case Inventory.InventoryResult{bag, ok}:
      match ok:
        case False{}:
          {==}
        case True{}:
          Empty.absurd({bag == original : List<&2, Inventory.Slot>}, true_is_not_false(h))

def Laws.a_refused_placing_keeps_the_bag(bag, index, item, block, x, y, z, empty, inside, over, h):
  place_finish(WorldState.make_edit(x, y, z, block), bag, Inventory.place(bag, index, item, empty, inside, over), h)

# --- the inventory: a bag never grows or shrinks -----------------------------------------

# what `add_existing`, `add_empty` and `remove_items` take from the amount at one slot
def existing_added(+head: Inventory.Slot, +item: U32, +amount: U32) -> U32:
  Bool.pick(U32, Bool.and(Bool.and(U32.is_eq(Inventory.slot_item(head), item), U32.is_lt(Inventory.slot_count_value(head), Inventory.max_stack())), U32.is_ne(amount, 0)),
    U32.min(amount, U32.sub(Inventory.max_stack(), Inventory.slot_count_value(head))), 0)

def empty_added(+head: Inventory.Slot, +amount: U32) -> U32:
  Bool.pick(U32, Bool.and(Bool.and(U32.is_eq(Inventory.slot_item(head), 0), U32.is_eq(Inventory.slot_count_value(head), 0)), U32.is_ne(amount, 0)),
    U32.min(amount, Inventory.max_stack()), 0)

def removed(+head: Inventory.Slot, +item: U32, +amount: U32) -> U32:
  Bool.pick(U32, U32.is_eq(Inventory.slot_item(head), item), U32.min(amount, Inventory.slot_count_value(head)), 0)

def add_existing_keeps(bag: List<&2, Inventory.Slot>, +item: U32, +amount: U32) -> {Laws.slots(Inventory.add_slots(Inventory.add_existing(bag, item, amount))) == Laws.slots(bag) : Nat}:
  match bag:
    case Nil{}:
      {==}
    case Con{+head, +tail}:
      %add_existing_keeps(tail, item, U32.sub(amount, existing_added(head, item, amount))) : {1n+Laws.slots(Inventory.add_slots(Inventory.add_existing(tail, item, U32.sub(amount, existing_added(head, item, amount))))) == 1n+_ : Nat}
      {==}

def add_empty_keeps(bag: List<&2, Inventory.Slot>, +item: U32, +amount: U32) -> {Laws.slots(Inventory.add_slots(Inventory.add_empty(bag, item, amount))) == Laws.slots(bag) : Nat}:
  match bag:
    case Nil{}:
      {==}
    case Con{+head, +tail}:
      %add_empty_keeps(tail, item, U32.sub(amount, empty_added(head, amount))) : {1n+Laws.slots(Inventory.add_slots(Inventory.add_empty(tail, item, U32.sub(amount, empty_added(head, amount))))) == 1n+_ : Nat}
      {==}

def Laws.adding_items_keeps_the_slots(bag, item, amount):
  %add_existing_keeps(bag, item, amount) : {Laws.slots(Inventory.add_slots(Inventory.add_items(bag, item, amount))) == _ : Nat}
  add_empty_keeps(Inventory.add_slots(Inventory.add_existing(bag, item, amount)), item, Inventory.add_remaining(Inventory.add_existing(bag, item, amount)))

def Laws.removing_items_keeps_the_slots(bag, item, amount):
  match bag:
    case Nil{}:
      {==}
    case Con{+head, +tail}:
      %Laws.removing_items_keeps_the_slots(tail, item, U32.sub(amount, removed(head, item, amount))) : {1n+Laws.slots(Inventory.remove_slots(Inventory.remove_items(tail, item, U32.sub(amount, removed(head, item, amount))))) == 1n+_ : Nat}
      {==}

def collect_finalize_keeps(+original: List<&2, Inventory.Slot>, +added: Inventory.AddResult, valid: Bool,
  hl: {Laws.slots(Inventory.add_slots(added)) == Laws.slots(original) : Nat}) ->
  {Laws.slots(Inventory.inventory_slots(Inventory.collect.finalize(original, added, valid))) == Laws.slots(original) : Nat}:
  match valid:
    case True{}:
      hl
    case False{}:
      {==}

def collect_if_keeps(+bag: List<&2, Inventory.Slot>, +item: U32, +amount: U32, valid: Bool) -> {Laws.slots(Inventory.inventory_slots(Inventory.collect.if(bag, item, amount, valid))) == Laws.slots(bag) : Nat}:
  match valid:
    case False{}:
      {==}
    case True{}:
      collect_finalize_keeps(bag, Inventory.add_items(bag, item, amount), U32.is_eq(Inventory.add_remaining(Inventory.add_items(bag, item, amount)), 0), Laws.adding_items_keeps_the_slots(bag, item, amount))

def mine_collect_keeps(+original: List<&2, Inventory.Slot>, mining: Inventory.MiningResult) -> {Laws.slots(Inventory.inventory_slots(Inventory.mine_collect.if(original, mining))) == Laws.slots(original) : Nat}:
  match mining:
    case Inventory.MiningResult{+item, +amount, valid}:
      match valid:
        case False{}:
          {==}
        case True{}:
          collect_if_keeps(original, item, U32.from_nat(U32.to_nat(amount)), Bool.and(Inventory.pickup_item(item), Nat.is_gt(U32.to_nat(amount), 0n)))

def tool_finalize_keeps(head: Inventory.Slot, +tail: List<&2, Inventory.Slot>, used: Inventory.ToolResult) -> {Laws.slots(Inventory.inventory_slots(Inventory.use_tool_at.finalize(Con{head, tail}, tail, head, used))) == 1n+Laws.slots(tail) : Nat}:
  match head:
    case Inventory.Slot{item, count, old}:
      match used:
        case Inventory.ToolResult{durability, broken, valid}:
          match valid:
            case False{}:
              {==}
            case True{}:
              {==}

def use_tool_keeps(bag: List<&2, Inventory.Slot>, +index: Nat) -> {Laws.slots(Inventory.inventory_slots(Inventory.use_tool_at(bag, index))) == Laws.slots(bag) : Nat}:
  match bag:
    case Nil{}:
      {==}
    case Con{+head, +tail}:
      match index:
        case 0n:
          tool_finalize_keeps(head, tail, Inventory.use_tool(Inventory.slot_item(head), Inventory.slot_durability(head)))
        case 1n+p:
          %use_tool_keeps(tail, p) : {1n+Laws.slots(Inventory.inventory_slots(Inventory.use_tool_at(tail, p))) == 1n+_ : Nat}
          {==}

def mine_used_keeps(+edit: WorldState.Edit, +original: List<&2, Inventory.Slot>, collected_ok: Bool, used: Inventory.InventoryResult,
  hu: {Laws.slots(Inventory.inventory_slots(used)) == Laws.slots(original) : Nat}) ->
  {Laws.slots(Laws.interaction_slots(Inventory.mine_interaction_at_finish_used(edit, original, collected_ok, used))) == Laws.slots(original) : Nat}:
  match collected_ok:
    case False{}:
      match used:
        case Inventory.InventoryResult{used_slots, used_ok}:
          {==}
    case True{}:
      match used:
        case Inventory.InventoryResult{used_slots, used_ok}:
          match used_ok:
            case False{}:
              {==}
            case True{}:
              hu

def mine_mode_keeps(+edit: WorldState.Edit, +original: List<&2, Inventory.Slot>, +index: Nat, +bag: List<&2, Inventory.Slot>, tool_empty: Bool, collected_ok: Bool,
  hs: {Laws.slots(bag) == Laws.slots(original) : Nat}) ->
  {Laws.slots(Laws.interaction_slots(Inventory.mine_interaction_at_finish_mode(edit, original, index, bag, collected_ok, tool_empty))) == Laws.slots(original) : Nat}:
  match tool_empty:
    case True{}:
      match collected_ok:
        case False{}:
          {==}
        case True{}:
          hs
    case False{}:
      mine_used_keeps(edit, original, collected_ok, Inventory.use_tool_at(bag, index),
        Equal.trans(Nat, Laws.slots(Inventory.inventory_slots(Inventory.use_tool_at(bag, index))), Laws.slots(bag), Laws.slots(original), use_tool_keeps(bag, index), hs))

def mine_collected_keeps(+edit: WorldState.Edit, +original: List<&2, Inventory.Slot>, +index: Nat, +tool: U32, state: Inventory.InventoryResult,
  hs: {Laws.slots(Inventory.inventory_slots(state)) == Laws.slots(original) : Nat}) ->
  {Laws.slots(Laws.interaction_slots(Inventory.mine_interaction_at_finish_collected(edit, original, index, tool, state))) == Laws.slots(original) : Nat}:
  match state:
    case Inventory.InventoryResult{+bag, collected_ok}:
      mine_mode_keeps(edit, original, index, bag, U32.is_eq(Inventory.tool_max_durability(tool), 0), collected_ok, hs)

def Laws.mining_keeps_the_slots(bag, index, tool, block, x, y, z):
  mine_collected_keeps(WorldState.make_edit(x, y, z, 0), bag, index, tool, Inventory.mine_collect_at(bag, tool, block, x, y, z),
    mine_collect_keeps(bag, Inventory.mine_drop_at(tool, block, x, y, z)))

def consume_head_keeps(+head: Inventory.Slot, +tail: List<&2, Inventory.Slot>, +amount: U32, valid: Bool) -> {Laws.slots(Inventory.inventory_slots(Inventory.consume.head(Con{head, tail}, tail, head, amount, valid))) == 1n+Laws.slots(tail) : Nat}:
  match valid:
    case False{}:
      {==}
    case True{}:
      {==}

def consume_at_keeps(bag: List<&2, Inventory.Slot>, +index: Nat, +amount: U32) -> {Laws.slots(Inventory.inventory_slots(Inventory.consume.at(bag, index, amount))) == Laws.slots(bag) : Nat}:
  match bag:
    case Nil{}:
      {==}
    case Con{+head, +tail}:
      match index:
        case 0n:
          consume_head_keeps(head, tail, amount, Bool.and(U32.is_ne(Inventory.slot_item(head), 0), U32.is_le(amount, Inventory.slot_count_value(head))))
        case 1n+p:
          %consume_at_keeps(tail, p, amount) : {1n+Laws.slots(Inventory.inventory_slots(Inventory.consume.at(tail, p, amount))) == 1n+_ : Nat}
          {==}

def consume_if_keeps(+bag: List<&2, Inventory.Slot>, +index: Nat, +amount: U32, valid: Bool) -> {Laws.slots(Inventory.inventory_slots(Inventory.consume.if(bag, index, amount, valid))) == Laws.slots(bag) : Nat}:
  match valid:
    case False{}:
      {==}
    case True{}:
      consume_at_keeps(bag, index, amount)

def place_valid_keeps(+bag: List<&2, Inventory.Slot>, +index: Nat, valid: Bool) -> {Laws.slots(Inventory.inventory_slots(Inventory.place.valid(bag, index, valid))) == Laws.slots(bag) : Nat}:
  match valid:
    case False{}:
      {==}
    case True{}:
      consume_if_keeps(bag, index, U32.from_nat(1n), Bool.and(Nat.is_lt(index, Inventory.slot_count()), Nat.is_gt(1n, 0n)))

def place_lookup_keeps(+bag: List<&2, Inventory.Slot>, +index: Nat, +item: U32, +empty: Bool, +inside: Bool, +over: Bool, l: Inventory.Lookup) -> {Laws.slots(Inventory.inventory_slots(Inventory.place.lookup(bag, index, item, empty, inside, over, l))) == Laws.slots(bag) : Nat}:
  match l:
    case Inventory.Missing{}:
      {==}
    case Inventory.Found{+slot}:
      place_valid_keeps(bag, index, Bool.and(U32.is_eq(Inventory.slot_item(slot), item), Inventory.can_place(item, empty, inside, over)))

def place_finish_keeps(+edit: WorldState.Edit, +original: List<&2, Inventory.Slot>, state: Inventory.InventoryResult,
  hs: {Laws.slots(Inventory.inventory_slots(state)) == Laws.slots(original) : Nat}) ->
  {Laws.slots(Laws.interaction_slots(Inventory.interaction.finish(edit, original, state))) == Laws.slots(original) : Nat}:
  match state:
    case Inventory.InventoryResult{bag, ok}:
      match ok:
        case False{}:
          {==}
        case True{}:
          hs

def Laws.placing_keeps_the_slots(bag, index, item, block, x, y, z, empty, inside, over):
  place_finish_keeps(WorldState.make_edit(x, y, z, block), bag, Inventory.place(bag, index, item, empty, inside, over),
    place_lookup_keeps(bag, index, item, empty, inside, over, Inventory.lookup(bag, index)))

def Laws.an_empty_bag_has_the_slots_asked_for(n):
  match n:
    case 0n:
      {==}
    case 1n+p:
      %Laws.an_empty_bag_has_the_slots_asked_for(p) : {1n+Laws.slots(Inventory.empty_slots(p)) == 1n+_ : Nat}
      {==}

# --- the inventory: the tables ---------------------------------------------------------

def Laws.the_starting_bag_has_thirty_six_slots():
  {==}

def Laws.the_starting_bag_holds_stone_dirt_grass_leaves_and_wood():
  {==}

def Laws.a_bare_hand_breaks_dirt_and_not_stone():
  {==}

def Laws.a_wooden_pickaxe_breaks_stone_and_not_iron():
  {==}

def Laws.a_stone_pickaxe_breaks_iron_and_not_diamond():
  {==}

def Laws.an_iron_pickaxe_breaks_diamond_and_not_obsidian():
  {==}

def Laws.a_diamond_pickaxe_breaks_obsidian():
  {==}

def Laws.air_and_fluids_are_not_mined():
  {==}

def Laws.what_a_block_drops():
  {==}

def Laws.what_a_redstone_block_drops():
  {==}

def Laws.what_an_open_door_drops():
  {==}

def Laws.what_a_block_drops_places_it_again():
  {==}

def Laws.the_bottom_row_is_bedrock():
  {==}

def Laws.every_placeable_item_places_a_block():
  {==}

def Laws.tools_and_food_place_nothing():
  {==}

def Laws.some_leaves_drop_an_apple():
  {==}

def Laws.a_stack_holds_sixty_four():
  {==}

def Laws.a_tool_wears_by_one_and_breaks_at_zero():
  {==}

def Laws.each_tool_starts_with_its_durability():
  {==}

def Laws.two_logs_make_a_wooden_pickaxe():
  {==}

def Laws.crafting_without_the_ingredients_is_refused():
  {==}

# --- armour --------------------------------------------------------------------------

def Laws.an_unknown_armour_slot_changes_nothing(outfit, item, k):
  match outfit:
    case Equipment.Equipment{offhand, helmet, chest, legs, boots}:
      {==}

def Laws.armour_taken_off_is_the_armour_put_on(outfit, item):
  match outfit:
    case Equipment.Equipment{offhand, helmet, chest, legs, boots}:
      {==}

def Laws.each_armour_piece_has_its_slot():
  {==}

def Laws.a_full_set_defends_seven():
  {==}

def Laws.a_block_is_not_armour():
  {==}

# --- the furnace ---------------------------------------------------------------------

def load_refused(+original: Furnace.Furnace, +updated: Furnace.Furnace, valid: Bool,
  h: {Laws.furnace_ok(Furnace.load_input.finalize(original, updated, valid)) == False{} : Bool}) ->
  {Laws.furnace_of(Furnace.load_input.finalize(original, updated, valid)) == original : Furnace.Furnace}:
  match valid:
    case True{}:
      Empty.absurd({updated == original : Furnace.Furnace}, true_is_not_false(h))
    case False{}:
      {==}

def Laws.a_refused_load_keeps_the_furnace(furnace, item, amount, h):
  match furnace:
    case Furnace.Furnace{+input, +input_count, +fuel, +fuel_count, +output, +output_count, +progress, +burn}:
      load_refused(Furnace.Furnace{input, input_count, fuel, fuel_count, output, output_count, progress, burn},
        Furnace.Furnace{Bool.pick(U32, U32.is_eq(input, 0), item, input), U32.add(input_count, U32.from_nat(amount)), fuel, fuel_count, output, output_count, progress, burn},
        Bool.and(Bool.and(Furnace.smeltable(item), Nat.is_gt(amount, 0n)), Bool.and(Bool.or(U32.is_eq(input, 0), U32.is_eq(input, item)), U32.is_le(U32.from_nat(amount), U32.sub(Furnace.max_stack(), input_count)))),
        h)

def fuel_refused(+original: Furnace.Furnace, +updated: Furnace.Furnace, valid: Bool,
  h: {Laws.furnace_ok(Furnace.load_fuel.finalize(original, updated, valid)) == False{} : Bool}) ->
  {Laws.furnace_of(Furnace.load_fuel.finalize(original, updated, valid)) == original : Furnace.Furnace}:
  match valid:
    case True{}:
      Empty.absurd({updated == original : Furnace.Furnace}, true_is_not_false(h))
    case False{}:
      {==}

def Laws.a_refused_fuel_keeps_the_furnace(furnace, item, amount, h):
  match furnace:
    case Furnace.Furnace{+input, +input_count, +fuel, +fuel_count, +output, +output_count, +progress, +burn}:
      fuel_refused(Furnace.Furnace{input, input_count, fuel, fuel_count, output, output_count, progress, burn},
        Furnace.Furnace{input, input_count, Bool.pick(U32, U32.is_eq(fuel, 0), item, fuel), U32.add(fuel_count, U32.from_nat(amount)), output, output_count, progress, burn},
        Bool.and(Bool.and(U32.is_eq(item, 14), Nat.is_gt(amount, 0n)), Bool.and(Bool.or(U32.is_eq(fuel, 0), U32.is_eq(fuel, item)), U32.is_le(U32.from_nat(amount), U32.sub(Furnace.max_stack(), fuel_count)))),
        h)

def take_refused(+original: Furnace.Furnace, +updated: Furnace.Furnace, +item: U32, +amount: U32, valid: Bool,
  h: {Laws.transfer_ok(Furnace.take_output.finalize(original, updated, item, amount, valid)) == False{} : Bool}) ->
  {Laws.transfer_furnace(Furnace.take_output.finalize(original, updated, item, amount, valid)) == original : Furnace.Furnace}:
  match valid:
    case True{}:
      Empty.absurd({updated == original : Furnace.Furnace}, true_is_not_false(h))
    case False{}:
      {==}

def Laws.a_refused_take_keeps_the_furnace(furnace, h):
  match furnace:
    case Furnace.Furnace{+input, +input_count, +fuel, +fuel_count, +output, +output_count, +progress, +burn}:
      take_refused(Furnace.Furnace{input, input_count, fuel, fuel_count, output, output_count, progress, burn},
        Furnace.clear_output(input, input_count, fuel, fuel_count, progress, burn), output, output_count,
        Bool.and(U32.is_ne(output, 0), U32.is_gt(output_count, 0)), h)

def Laws.what_each_ore_smelts_into():
  {==}

def Laws.a_furnace_without_fuel_does_not_burn():
  {==}

def Laws.a_lit_furnace_burns_one_coal_for_eight_ticks():
  {==}

# --- the chest -----------------------------------------------------------------------

def chest_slots(xs: List<&2, Chest.Slot>) -> Nat:
  List.length(&2, Chest.Slot, xs)

def chest_head_if_keeps(+tail: List<&2, Chest.Slot>, +original: Chest.Slot, +replacement: Chest.Slot, +item: U32, +amount: U32, +durability: U32, valid: Bool) ->
  {chest_slots(Chest.withdraw_slots(Chest.withdraw.head.if(tail, original, replacement, item, amount, durability, valid))) == 1n+chest_slots(tail) : Nat}:
  match valid:
    case True{}:
      {==}
    case False{}:
      {==}

def chest_left(+amount: U32, +count: U32) -> U32:
  U32.sub(count, U32.min(amount, count))

def chest_head_keeps(+tail: List<&2, Chest.Slot>, +amount: U32, slot: Chest.Slot) -> {chest_slots(Chest.withdraw_slots(Chest.withdraw.head(tail, amount, slot))) == 1n+chest_slots(tail) : Nat}:
  match slot:
    case Chest.Slot{+item, +count, +durability}:
      chest_head_if_keeps(tail, Chest.make_slot(item, count, durability),
        Chest.make_slot(Bool.pick(U32, U32.is_eq(chest_left(amount, count), 0), 0, item), chest_left(amount, count), Bool.pick(U32, U32.is_eq(chest_left(amount, count), 0), 0, durability)),
        item, U32.min(amount, count), durability, Bool.and(U32.is_ne(item, 0), U32.is_ne(U32.min(amount, count), 0)))

def chest_prepend_keeps(+head: Chest.Slot, state: Chest.WithdrawResult) -> {chest_slots(Chest.withdraw_slots(Chest.prepend_withdraw(head, state))) == 1n+chest_slots(Chest.withdraw_slots(state)) : Nat}:
  match state:
    case Chest.WithdrawResult{slots, item, amount, durability, ok}:
      {==}

def Laws.a_withdrawal_keeps_the_chest_slots(chest, index, amount):
  match chest:
    case Nil{}:
      {==}
    case Con{+head, +tail}:
      match index:
        case 0n:
          chest_head_keeps(tail, amount, head)
        case 1n+p:
          %Laws.a_withdrawal_keeps_the_chest_slots(tail, p, amount) : {chest_slots(Chest.withdraw_slots(Chest.prepend_withdraw(head, Chest.withdraw.at(tail, p, amount)))) == 1n+_ : Nat}
          chest_prepend_keeps(head, Chest.withdraw.at(tail, p, amount))

def Laws.a_refused_dig_gets_nowhere(block, x, y, z, item, time):
  {==}

def Laws.the_blocks_that_hold_something_are_named():
  {==}

def Laws.an_item_places_the_block_named_for_it():
  {==}

def Laws.a_chest_has_nine_slots():
  {==}

def Laws.a_tool_keeps_its_wear_in_a_chest():
  {==}

# --- farmland and crops ----------------------------------------------------------------

def plot_added(+stored: List<&2, Farmland.Plot>, +x: Nat, +y: Nat, +z: Nat, held: Bool,
  hc: {Farmland.contains(stored, x, y, z) == held : Bool}) ->
  {Farmland.contains(Laws.farm_plots(Bool.pick(Farmland.FarmResult, held, Farmland.FarmResult{Farmland.State{stored}, True{}},
    Farmland.FarmResult{Farmland.State{Con{Farmland.Plot{x, y, z, 0}, stored}}, True{}})), x, y, z) == True{} : Bool}:
  match held:
    case True{}:
      hc
    case False{}:
      %Equal.sym(Bool, Bool.and(Bool.and(Nat.is_eq(x, x), Nat.is_eq(y, y)), Nat.is_eq(z, z)), True{}, same_cell(x, y, z)) : {Bool.or(_, Farmland.contains(stored, x, y, z)) == True{} : Bool}
      {==}

def Laws.an_added_plot_is_in_the_farm(farm, x, y, z):
  match farm:
    case Farmland.State{+stored}:
      plot_added(stored, x, y, z, Farmland.contains(stored, x, y, z), {==})

def Laws.a_tick_keeps_every_plot(plots, waters):
  match plots:
    case Nil{}:
      {==}
    case Con{+head, +tail}:
      %Laws.a_tick_keeps_every_plot(tail, waters) : {1n+List.length(&2, Farmland.Plot, Farmland.tick_entries(tail, waters)) == 1n+_ : Nat}
      {==}

def crop_tick_keeps(head: Crops.Crop, +tail: List<&2, Crops.Crop>, +steps: Nat,
  ih: {List.length(&2, Crops.Crop, Crops.tick_entries(tail, steps)) == List.length(&2, Crops.Crop, tail) : Nat}) ->
  {List.length(&2, Crops.Crop, Crops.tick_entries(Con{head, tail}, steps)) == 1n+List.length(&2, Crops.Crop, tail) : Nat}:
  match head:
    case Crops.Crop{x, y, z, stage, age}:
      %ih : {1n+List.length(&2, Crops.Crop, Crops.tick_entries(tail, steps)) == 1n+_ : Nat}
      {==}

def Laws.a_tick_keeps_every_crop(crops, steps):
  match crops:
    case Nil{}:
      {==}
    case Con{+head, +tail}:
      crop_tick_keeps(head, tail, steps, Laws.a_tick_keeps_every_crop(tail, steps))

def Laws.water_within_four_cells_wets_a_plot():
  {==}

def Laws.seeds_grow_on_farmland_only():
  {==}

def Laws.wheat_grows_a_stage_every_four_ticks_and_stops_ripe():
  {==}

def Laws.ripe_wheat_gives_a_seed_and_a_wheat():
  {==}

# --- experience, light, bodies, fluids, redstone, mobs ----------------------------------

def Laws.a_level_costs_seven_and_two_more_each_time():
  {==}

def Laws.seven_points_are_the_first_level():
  {==}

def Laws.a_monster_is_worth_five_and_an_animal_two():
  {==}

def Laws.light_reaches_fifteen():
  {==}

def Laws.a_cave_is_never_darker_than_three_or_brighter_than_twelve():
  {==}

def Laws.torches_and_lava_give_light():
  {==}

def Laws.what_light_passes_a_body_passes():
  {==}

def Laws.the_ground_is_solid_and_the_air_is_not():
  {==}

def Laws.a_settled_pool_keeps_its_cells():
  {==}

def Laws.an_unfed_flow_dries_up():
  {==}

def Laws.the_tool_kinds_are_what_they_are():
  {==}

def Laws.the_tool_tiers_run_wooden_to_diamond():
  {==}

def Laws.a_tool_wears_by_its_tier():
  {==}

def Laws.the_tools_place_nothing():
  {==}

def Laws.the_tools_break_what_they_are_for():
  {==}

def Laws.each_block_wants_its_tool():
  {==}

def Laws.the_diamond_band_is_the_first_quarter_of_a_twelve_cell_column():
  {==}

def Laws.the_diamond_band_is_a_quarter_of_the_column():
  {==}

def Laws.the_diamond_band_stops_at_the_quarter():
  {==}

def Laws.only_diamond_has_a_band_of_its_own():
  {==}

def Laws.a_vein_is_the_size_its_ore_gives_it():
  {==}

def Laws.the_veins_are_placed_in_the_order_of_rarity():
  {==}

def Laws.the_fluids_are_water_and_lava():
  {==}

def Laws.water_and_lava_meet_as_stone():
  {==}

def Laws.only_wood_and_leaves_burn():
  {==}

def Laws.the_redstone_blocks_are_twenty_eight_to_forty():
  {==}

def Laws.power_never_decays_below_zero():
  {==}

def Laws.a_signal_equals_itself(a):
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

def Laws.every_mob_is_an_animal_or_a_hostile():
  {==}

def Laws.only_the_roster_are_mobs():
  {==}

def Laws.zombies_and_brutes_are_the_hostiles():
  {==}

def Laws.what_each_mob_leaves():
  {==}

def Laws.wander_dir_pins_heading():
  {==}
