import Base
import ../world/world_state.bend as WorldState
import ../world/multiplayer.bend as Multiplayer

# Save migration, phase 1: a world seed and its block edit log.
#
# `read_v1` reads a legacy multiplayer snapshot -- snapshot version 1, the shape
# server/room/snapshot.js version 1 wrote to worlds/multiplayer.json -- into a
# WorldState edit log. `encode` and `decode` read and write the native `B2CW:1`
# snapshot, which carries the same seed and edit log.
#
# Everything here is pure and total. Nothing opens, renames or truncates a save,
# so a refused document can never cost a user data: the caller keeps the file
# and decides what to do. `Rejected{}` means the document is malformed or out of
# contract; `UnsupportedVersion{version}` means it is readable but comes from a
# version this migration does not read.
#
# Nothing is dropped silently. A document carrying anything phase 1 does not
# migrate -- the chests, furnaces, clock or simulation of snapshot versions 2
# and 3, or any member outside the four below -- is refused whole. README.md in
# this directory lists what is still unmigrated and how to reach it.
#
# Edit validity is not restated here: Multiplayer.valid_edit owns the world band
# and the block ids, so a migrated log cannot drift from that contract.

# Limits -----------------------------------------------------------------------

# The most block edits one snapshot may carry; a snapshot above it is refused
# whole. The cap bounds work and memory, not the format: raising it only widens
# the two input caps below, and a save above the cap keeps its file untouched, so
# a larger world needs nothing but this one number changed.
#
# It is deliberately small. Base's own `String.length`, `List.all`, `List.sort`
# and `String.split` are not tail recursive, and the TypeScript lane that
# scripts/test-suite.sh uses overflows its stack a little past 40,000 of them, so
# a cap whose test document fits under that keeps this regression runnable there
# as well as as a native binary. A world with more distinct edited cells than
# this has to raise the number first; the native target has no such limit.
def max_edits() -> Nat:
  1024n

# A U32 in decimal is at most ten digits, so a longer run of digits is already
# too large to be read.
def max_u32_digits() -> Nat:
  10n

# The widest one edit may be in the canonical form `JSON.stringify` wrote and
# `encode` writes: two brackets, three commas and, from Multiplayer.valid_edit,
# an x and a z below World.negative_origin (94371840, eight digits), a y below
# World.max_y (64, two digits) and a block id at most 27 (two digits).
def max_edit_text() -> Nat:
  25n

# The widest legacy document: a short object header plus every edit. Both caps
# assume the canonical form, so a document reformatted with interior whitespace
# can exceed them and is then refused whole.
def max_json_input() -> Nat:
  Nat.add(128n, Nat.mul(max_edits(), max_edit_text()))

# The widest native document: the "B2CW:1" marker line, a seed line (a Bend
# `Nat` is at most 48 bits, so fifteen decimal digits), an edit-count line and
# one line per edit, which is the same record plus its newline.
def max_native_input() -> Nat:
  Nat.add(35n, Nat.mul(max_edits(), Nat.add(max_edit_text(), 1n)))

# Types ------------------------------------------------------------------------

type Import is Data:
  Imported{seq: U32, seed: Nat, edits: List<&2, WorldState.Edit>}
  UnsupportedVersion{version: U32}
  Rejected{}

type Snapshot is Data:
  Snapshot{seed: Nat, edits: List<&2, WorldState.Edit>}

# One number and the text after it.
type Number is Data:
  Number{value: U32, next: String}

# One `[x, y, z, block]` record: the four numbers, whether a `,` follows it (so
# another record belongs to the same array) and the text after that comma or
# bracket. A legacy edit array and a native edit line carry the same record, so
# both read through this.
type Quad is Data:
  Quad{x: U32, y: U32, z: U32, block: U32, comma: Bool, next: String}

# One quoted string with no escape in it, and the text after it.
type Text is Data:
  Text{value: String, next: String}

# One member's value: the members read so far and the text after the value.
type Value is Data:
  Value{fields: Fields, next: String}

# One member of a legacy snapshot, plus the `,` or `}` that follows it.
type Member is Data:
  Member{ok: Bool, comma: Bool, fields: Fields, next: String}

# The four members of a legacy snapshot. `seen` is a bit mask over them, so a
# repeated member is refused instead of quietly replacing the first.
type Fields is Data:
  Fields{version: U32, seq: U32, seed: Nat, edits: List<&2, WorldState.Edit>, seen: Nat, ok: Bool}

# A JSON edits array: the log read so far, how many entries it holds, and the
# text after the array.
type Edits is Data:
  Edits{value: Maybe<&2, List<&2, WorldState.Edit>>, count: Nat, at: String}

# One native edit line: the record it holds, the line after it and the lines
# left. `Last` is the final edit line, `Empty` and `Malformed` are the two ways
# a line fails to be one well-formed `[x, y, z, block]` record.
type Line is Data:
  Read{edit: WorldState.Edit, next: String, rest: List<&2, String>}
  Last{edit: WorldState.Edit}
  Malformed{}
  Empty{}

# Shared checks ----------------------------------------------------------------

def coordinate_le(a: WorldState.Edit, b: WorldState.Edit) -> Bool:
  WorldState.Edit{+x_a, +y_a, +z_a, block_a} = a
  WorldState.Edit{+x_b, +y_b, +z_b, block_b} = b
  Bool.or(Nat.is_lt(x_a, x_b),
    Bool.and(Nat.is_eq(x_a, x_b),
      Bool.or(Nat.is_lt(y_a, y_b),
        Bool.and(Nat.is_eq(y_a, y_b), Nat.is_le(z_a, z_b)))))

def same_cell(a: WorldState.Edit, b: WorldState.Edit) -> Bool:
  WorldState.Edit{x, y, z, block} = a
  WorldState.edit_matches(b, x, y, z)

# One entry per cell: sorting by cell and comparing neighbours finds every
# repeated cell without comparing every pair.
def no_repeats.go(edits: List<&2, WorldState.Edit>, +ok: Bool) -> Bool:
  match edits:
    case Nil{}:
      ok
    case Con{head, Con{next, rest}}:
      no_repeats.go(rest, Bool.and(ok, Bool.not(same_cell(head, next))))
    case Con{head, Nil{}}:
      ok

def no_repeats(edits: List<&2, WorldState.Edit>) -> Bool:
  no_repeats.go(List.sort(~WorldState.Edit, ~coordinate_le, edits), True{})

def every_edit_legal(edits: List<&2, WorldState.Edit>) -> Bool:
  List.all(~&2, ~WorldState.Edit, ~Multiplayer.valid_edit, edits)

# A log may be read only when every edit is a legal world edit and no cell is
# named twice. A WorldState log holds one entry per cell, so a repeated cell is
# a damaged document, not a value to fold.
def checked(+edits: List<&2, WorldState.Edit>) -> Bool:
  Bool.and(every_edit_legal(edits), no_repeats(edits))

# Reading text -----------------------------------------------------------------

# JSON whitespace: space, newline, carriage return and tab, exactly what
# JSON.parse accepts. One case per blank character, so each step is a match --
# `Bool.pick` would evaluate the whole remaining text on every character.
def spaces(rest: String) -> String:
  match rest:
    case SNil{}:
      rest
    case SCon{+head, +tail}:
      match head:
        case ' ':
          spaces(tail)
        case '\n':
          spaces(tail)
        case '\t':
          spaces(tail)
        case '\r':
          spaces(tail)
        case _:
          rest

# A number is a run of decimal digits read as a U32 and spelled back exactly as
# it was. That refuses a leading zero and anything past 2^32 - 1. A sign, a
# fraction or an exponent never reach the digits, so `-1`, `1.5` and `1e3` are
# all refused as non-numbers, and a run longer than any U32 is refused at once.
def number.canonical(text: String, rest: String, parsed: Maybe<&2, U32>) -> Maybe<&2, Number>:
  match parsed:
    case None{}:
      None{}
    case Some{+value}:
      Bool.pick(Maybe<&2, Number>, String.eq(U32.show(value), text),
        Some{Number{value, rest}}, None{})

# The number of digits at the head of `rest`, never more than one past the widest
# U32. Measuring the run before reading it keeps a damaged document with a long
# run of digits from costing a pass per digit.
def digits(left: Nat, +rest: String, +count: Nat) -> Nat:
  match left rest:
    case 0n _:
      count
    case 1n+more SNil{}:
      count
    case 1n+more SCon{+head, +tail}:
      Bool.pick(Nat, Bool.and(Char.is_digit(head), Nat.is_lt(count, max_u32_digits())),
        digits(more, tail, (1n + count : Nat)), count)

def number.read(length: Nat, +text: String, +rest: String) -> Maybe<&2, Number>:
  Bool.pick(Maybe<&2, Number>, Nat.is_le(length, max_u32_digits()),
    number.canonical(text, rest, U32.read(text)), None{})

def number.take(+rest: String, +length: Nat) -> Maybe<&2, Number>:
  number.read(length, String.take(rest, length), String.drop(rest, length))

def number(+rest: String) -> Maybe<&2, Number>:
  number.take(rest, digits((1n + max_u32_digits() : Nat), rest, 0n))

# A quoted string with no escape in it. The only string a version 1 snapshot
# carries is the seed, a decimal number, so an escape or a raw control character
# can only mean damage. As with `spaces`, the step matches its flags rather than
# testing them, so a long run costs one pass.
# A quoted string with no escape in it. The only string a version 1 snapshot
# carries is the seed, a decimal number, so an escape or a raw control character
# can only mean damage. A version 1 snapshot has at most four strings, so the
# eager branch below is a few characters long.
def raw_control(+ch: Char) -> Bool:
  Bool.or(U32.is_lt(Char.to_u32(ch), 32), Char.is_eq(ch, '\\'))

def text.go(+rest: String, +acc: String) -> Maybe<&2, Text>:
  match rest:
    case SNil{}:
      None{}
    case SCon{+head, +tail}:
      match head:
        case '"':
          Some{Text{String.reverse(acc), tail}}
        case _:
          Bool.pick(Maybe<&2, Text>, raw_control(head), None{},
            text.go(tail, SCon{head, acc}))

def text_value(rest: String) -> Maybe<&2, Text>:
  match rest:
    case SNil{}:
      None{}
    case SCon{+head, +tail}:
      match head:
        case '"':
          text.go(tail, SNil{})
        case _:
          None{}

# One `[x, y, z, block]` record. `at_end` reads a native edit line, where the
# line ends after the record, instead of a JSON array, where a comma or the
# array's bracket follows it.
def quad.sep(sep: Char, head: Char, tail: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, Char.is_eq(head, sep), Some{tail}, None{})

def quad.separated(rest: String, sep: Char) -> Maybe<&2, String>:
  match rest:
    case SNil{}:
      None{}
    case SCon{head, tail}:
      quad.sep(sep, head, tail)

# The text after the separator that must come before the next number.
def quad.after(rest: String, sep: Char) -> Maybe<&2, String>:
  quad.separated(spaces(rest), sep)

def quad.stop(comma: Bool, brace: Bool, +x: U32, +y: U32, +z: U32, +block: U32, +next: String) ->
  Maybe<&2, Quad>:
  Bool.pick(Maybe<&2, Quad>, comma, Some{Quad{x, y, z, block, True{}, next}},
    Bool.pick(Maybe<&2, Quad>, brace, Some{Quad{x, y, z, block, False{}, next}}, None{}))

def quad.last(at_end: Bool, x: U32, y: U32, z: U32, block: U32) -> Maybe<&2, Quad>:
  match at_end:
    case True{}:
      Some{Quad{x, y, z, block, False{}, SNil{}}}
    case False{}:
      None{}

def quad.delimiter(rest: String, x: U32, y: U32, z: U32, block: U32, at_end: Bool) ->
  Maybe<&2, Quad>:
  match rest:
    case SNil{}:
      quad.last(at_end, x, y, z, block)
    case SCon{+head, +tail}:
      quad.stop(Char.is_eq(head, ','), Char.is_eq(head, ']'), x, y, z, block, tail)

# `rest` is the text after the block.
def quad.end(rest: String, x: U32, y: U32, z: U32, block: U32, at_end: Bool) -> Maybe<&2, Quad>:
  match rest:
    case SNil{}:
      None{}
    case SCon{+head, +tail}:
      match head:
        case ']':
          quad.delimiter(spaces(tail), x, y, z, block, at_end)
        case _:
          None{}

def quad.id(found: Maybe<&2, Number>, x: U32, y: U32, z: U32, at_end: Bool) -> Maybe<&2, Quad>:
  match found:
    case None{}:
      None{}
    case Some{Number{value, next}}:
      quad.end(spaces(next), x, y, z, value, at_end)

# `found` is the text after the separator before the block.
def quad.after_z(found: Maybe<&2, String>, x: U32, y: U32, z: U32, at_end: Bool) -> Maybe<&2, Quad>:
  match found:
    case None{}:
      None{}
    case Some{tail}:
      quad.id(number(spaces(tail)), x, y, z, at_end)

def quad.close(found: Maybe<&2, Number>, +sep: Char, x: U32, y: U32, at_end: Bool) -> Maybe<&2, Quad>:
  match found:
    case None{}:
      None{}
    case Some{Number{value, next}}:
      quad.after_z(quad.after(spaces(next), sep), x, y, value, at_end)

# `found` is the text after the separator before z.
def quad.block(found: Maybe<&2, String>, sep: Char, x: U32, y: U32, at_end: Bool) -> Maybe<&2, Quad>:
  match found:
    case None{}:
      None{}
    case Some{tail}:
      quad.close(number(spaces(tail)), sep, x, y, at_end)

def quad.z(found: Maybe<&2, Number>, +sep: Char, x: U32, at_end: Bool) -> Maybe<&2, Quad>:
  match found:
    case None{}:
      None{}
    case Some{Number{value, next}}:
      quad.block(quad.after(spaces(next), sep), sep, x, value, at_end)

def quad.y(found: Maybe<&2, String>, sep: Char, x: U32, at_end: Bool) -> Maybe<&2, Quad>:
  match found:
    case None{}:
      None{}
    case Some{tail}:
      quad.z(number(spaces(tail)), sep, x, at_end)

def quad.first(found: Maybe<&2, Number>, +sep: Char, at_end: Bool) -> Maybe<&2, Quad>:
  match found:
    case None{}:
      None{}
    case Some{Number{value, next}}:
      quad.y(quad.after(spaces(next), sep), sep, value, at_end)

def quad(rest: String, sep: Char, at_end: Bool) -> Maybe<&2, Quad>:
  quad.first(number(rest), sep, at_end)

def edit_tuple(rest: String, at_end: Bool) -> Maybe<&2, Quad>:
  match rest:
    case SNil{}:
      None{}
    case SCon{+head, +tail}:
      match head:
        case '[':
          quad(spaces(tail), ',', at_end)
        case _:
          None{}

# Legacy JSON snapshot version 1 -----------------------------------------------
#
# `read_v1` reads the document `JSON.stringify` writes for
# {version, seed, seq, edits}: one object whose four members may appear in any
# order, separated by JSON whitespace, with no member repeated and no member
# outside those four. Every other shape is refused.

def empty_fields() -> Fields:
  Fields{0, 0, 0n, Nil{}, 0n, True{}}

def mark(fields: Fields, ok: Bool) -> Fields:
  Fields{version, seq, seed, edits, seen, previous} = fields
  Fields{version, seq, seed, edits, seen, ok}

def refused(fields: Fields) -> Fields:
  mark(fields, False{})

def bit_set(seen: Nat, bit: Nat) -> Bool:
  Nat.is_eq(Nat.mod(Nat.div(seen, bit), 2n), 1n)

def put_version(fields: Fields, value: U32) -> Fields:
  Fields{+version, +seq, +seed, +edits, +seen, +ok} = fields
  Fields{value, seq, seed, edits, Nat.add(seen, 1n), Bool.and(ok, Bool.not(bit_set(seen, 1n)))}

def put_seq(fields: Fields, value: U32) -> Fields:
  Fields{+version, +seq, +seed, +edits, +seen, +ok} = fields
  Fields{version, value, seed, edits, Nat.add(seen, 2n), Bool.and(ok, Bool.not(bit_set(seen, 2n)))}

def put_seed(fields: Fields, value: Nat) -> Fields:
  Fields{+version, +seq, +seed, +edits, +seen, +ok} = fields
  Fields{version, seq, value, edits, Nat.add(seen, 4n), Bool.and(ok, Bool.not(bit_set(seen, 4n)))}

def put_edits(fields: Fields, value: List<&2, WorldState.Edit>) -> Fields:
  Fields{+version, +seq, +seed, +edits, +seen, +ok} = fields
  Fields{version, seq, seed, value, Nat.add(seen, 8n), Bool.and(ok, Bool.not(bit_set(seen, 8n)))}

# A seed is `BigInt.prototype.toString` of the world seed: canonical decimal,
# non-negative. Nat.read refuses a sign, a fraction, a non-digit and anything
# past 2^48 - 1, which is also the largest seed a Bend `Nat` world can hold.
def seed_canonical(text: String, parsed: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match parsed:
    case None{}:
      None{}
    case Some{+value}:
      Bool.pick(Maybe<&2, Nat>, String.eq(Nat.show(value), text), Some{value}, None{})

def seed_text(+text: String) -> Maybe<&2, Nat>:
  seed_canonical(text, Nat.read(text))

def set_version.put(found: Maybe<&2, Number>, fields: Fields) -> Maybe<&2, Value>:
  match found:
    case None{}:
      None{}
    case Some{Number{value, next}}:
      Some{Value{put_version(fields, value), next}}

def set_version(rest: String, fields: Fields) -> Maybe<&2, Value>:
  set_version.put(number(rest), fields)

def set_seq.put(found: Maybe<&2, Number>, fields: Fields) -> Maybe<&2, Value>:
  match found:
    case None{}:
      None{}
    case Some{Number{value, next}}:
      Some{Value{put_seq(fields, value), next}}

def set_seq(rest: String, fields: Fields) -> Maybe<&2, Value>:
  set_seq.put(number(rest), fields)

def set_seed.text(found: Maybe<&2, Nat>, fields: Fields, next: String) -> Maybe<&2, Value>:
  match found:
    case None{}:
      None{}
    case Some{value}:
      Some{Value{put_seed(fields, value), next}}

def set_seed.put(found: Maybe<&2, Text>, fields: Fields) -> Maybe<&2, Value>:
  match found:
    case None{}:
      None{}
    case Some{Text{value, next}}:
      set_seed.text(seed_text(value), fields, next)

def set_seed(rest: String, fields: Fields) -> Maybe<&2, Value>:
  set_seed.put(text_value(rest), fields)

# The edits array: a bracket, then `[x, y, z, block]` records separated by
# commas. `left` is the edit budget, so a document above the cap is refused
# while it is read rather than after it.
def edit_array.closed(acc: List<&2, WorldState.Edit>, count: Nat, at: String) -> Edits:
  Edits{Some{List.reverse.go(&2, WorldState.Edit, acc, Nil{})}, count, at}

def edit_array.failed(count: Nat, at: String) -> Edits:
  Edits{None{}, count, at}

def edit_array.item(left: Nat, found: Maybe<&2, Quad>, rest: String, acc: List<&2, WorldState.Edit>, count: Nat) -> Edits:
  match left found:
    case 0n _:
      edit_array.failed(count, rest)
    case 1n+more None{}:
      edit_array.failed(count, rest)
    case 1n+more Some{Quad{x, y, z, block, +comma, +next}}:
      match comma:
        case True{}:
          edit_array.item(more, edit_tuple(spaces(next), False{}), spaces(next),
            Con{WorldState.Edit{U32.to_nat(x), U32.to_nat(y), U32.to_nat(z), block}, acc},
            (1n + count : Nat))
        case False{}:
          edit_array.closed(Con{WorldState.Edit{U32.to_nat(x), U32.to_nat(y), U32.to_nat(z), block}, acc},
            (1n + count : Nat), next)

def edit_array.open(head: Char, tail: String, +rest: String, left: Nat) -> Edits:
  match head:
    case ']':
      edit_array.closed(Nil{}, 0n, tail)
    case _:
      edit_array.item(left, edit_tuple(rest, False{}), rest, Nil{}, 0n)

def edit_array.begin(+rest: String) -> Edits:
  match rest:
    case SNil{}:
      edit_array.failed(0n, rest)
    case SCon{+head, +tail}:
      edit_array.open(head, tail, rest, max_edits())

def edit_array(rest: String) -> Edits:
  edit_array.begin(rest)

def set_edits.stored(found: Maybe<&2, List<&2, WorldState.Edit>>, fields: Fields, at: String) ->
  Maybe<&2, Value>:
  match found:
    case None{}:
      None{}
    case Some{value}:
      Some{Value{put_edits(fields, value), at}}

def set_edits.array(edits: Edits, fields: Fields) -> Maybe<&2, Value>:
  Edits{value, count, +at} = edits
  set_edits.stored(value, fields, at)

def set_edits.bracket(bracket: Bool, tail: String, fields: Fields) -> Maybe<&2, Value>:
  match bracket:
    case True{}:
      set_edits.array(edit_array(spaces(tail)), fields)
    case False{}:
      None{}

def set_edits.rest(head: Char, tail: String, fields: Fields) -> Maybe<&2, Value>:
  set_edits.bracket(Char.is_eq(head, '['), tail, fields)

def set_edits(rest: String, fields: Fields) -> Maybe<&2, Value>:
  match rest:
    case SNil{}:
      None{}
    case SCon{+head, +tail}:
      set_edits.rest(head, tail, fields)

# A member this migration does not read has no case here, so the document is
# refused instead of read without it.
def set_member(key: String, rest: String, fields: Fields) -> Maybe<&2, Value>:
  match key:
    case "version":
      set_version(rest, fields)
    case "seq":
      set_seq(rest, fields)
    case "seed":
      set_seed(rest, fields)
    case "edits":
      set_edits(rest, fields)
    case _:
      None{}

def member.mark(comma: Bool, brace: Bool, +fields: Fields, +next: String) -> Maybe<&2, Member>:
  Bool.pick(Maybe<&2, Member>, comma, Some{Member{True{}, True{}, fields, next}},
    Bool.pick(Maybe<&2, Member>, brace, Some{Member{True{}, False{}, fields, next}}, None{}))

def member.delimiter(rest: String, fields: Fields) -> Maybe<&2, Member>:
  match rest:
    case SNil{}:
      None{}
    case SCon{+head, +tail}:
      member.mark(Char.is_eq(head, ','), Char.is_eq(head, '}'), fields, tail)

def member.close(found: Maybe<&2, Value>) -> Maybe<&2, Member>:
  match found:
    case None{}:
      None{}
    case Some{Value{fields, +next}}:
      member.delimiter(spaces(next), fields)

def member.set(key: String, rest: String, fields: Fields) -> Maybe<&2, Member>:
  member.close(set_member(key, rest, fields))

def member.value(key: String, rest: String, fields: Fields) -> Maybe<&2, Member>:
  match rest:
    case SNil{}:
      None{}
    case SCon{+head, +tail}:
      match head:
        case ':':
          member.set(key, spaces(tail), fields)
        case _:
          None{}

def member.key(found: Maybe<&2, Text>, fields: Fields) -> Maybe<&2, Member>:
  match found:
    case None{}:
      None{}
    case Some{Text{value, next}}:
      member.value(value, spaces(next), fields)

def member(rest: String, fields: Fields) -> Maybe<&2, Member>:
  member.key(text_value(rest), fields)

# Nothing may follow the closing brace, so a document that continues past its
# object -- or a truncated one that lost the brace -- is refused.
def closed.over(rest: String, fields: Fields) -> Fields:
  match rest:
    case SNil{}:
      fields
    case SCon{head, tail}:
      refused(fields)

def closed(rest: String, fields: Fields) -> Fields:
  closed.over(spaces(rest), fields)

# A version 1 snapshot has four members, and this walk refuses the fifth
# through the repeated-member and unknown-member rules, so the budget never
# decides an outcome: it only makes each step of the walk decrease.
def max_members() -> Nat:
  8n

# An empty object `{}` reads as no member at all, which is refused here rather
# than by the completeness check; either way the document is `Rejected{}`.
def members.go(left: Nat, +rest: String, found: Maybe<&2, Member>, +fields: Fields) -> Fields:
  match left found:
    case 0n _:
      refused(fields)
    case 1n+more None{}:
      members.go(more, spaces(rest), member(spaces(rest), fields), fields)
    case 1n+more Some{Member{+ok, +comma, +state, +after}}:
      match ok:
        case False{}:
          refused(state)
        case True{}:
          match comma:
            case True{}:
              members.go(more, after, None{}, state)
            case False{}:
              closed(after, state)

def object.brace(brace: Bool, tail: String) -> Fields:
  match brace:
    case True{}:
      members.go(max_members(), spaces(tail), None{}, empty_fields())
    case False{}:
      refused(empty_fields())

def object.open(head: Char, tail: String) -> Fields:
  object.brace(Char.is_eq(head, '{'), tail)

def object(rest: String) -> Fields:
  match rest:
    case SNil{}:
      refused(empty_fields())
    case SCon{head, tail}:
      object.open(head, tail)

def finish_v1(fields: Fields) -> Import:
  Fields{+version, +seq, +seed, +edits, +seen, +ok} = fields
  Bool.pick(Import, Bool.and(ok, Nat.is_eq(seen, 15n)),
    Bool.pick(Import, checked(edits), Imported{seq, seed, edits}, Rejected{}), Rejected{})

# A document whose version was read and is not 1 is reported as unsupported, so
# a version 2 or 3 save says what it is instead of reading as damaged. Every
# snapshot this repository wrote puts `version` first, so it is read before the
# members phase 1 does not migrate end the walk.
def finish(fields: Fields) -> Import:
  Fields{+version, +seq, +seed, +edits, +seen, +ok} = fields
  +read = bit_set(seen, 1n)
  +legacy = Bool.and(read, U32.is_eq(version, 1))
  Bool.pick(Import, legacy, finish_v1(fields),
    Bool.pick(Import, read, UnsupportedVersion{version}, Rejected{}))

def read_v1.within(within_limit: Bool, input: String) -> Import:
  match within_limit:
    case True{}:
      finish(object(spaces(input)))
    case False{}:
      Rejected{}

def read_v1(+input: String) -> Import:
  read_v1.within(Nat.is_le(String.length(input), max_json_input()), input)

# Native snapshot B2CW:1 -------------------------------------------------------
#
# Line-oriented: the "B2CW:1" marker, the seed, the number of edits and that many
# `[x, y, z, block]` records, one per line. This is the native runtime's own
# format and is unrelated to the B2CS:1 probe codec in native/save-probe.

def magic() -> String:
  "B2CW:1"

def seed_line(seed: Nat) -> String:
  Nat.show(seed) ++ "\n"

def count_line(edits: List<&2, WorldState.Edit>) -> String:
  Nat.show(List.length(&2, WorldState.Edit, edits)) ++ "\n"

def edit_line(edit: WorldState.Edit) -> String:
  WorldState.Edit{x, y, z, block} = edit
  "[" ++ Nat.show(x) ++ "," ++ Nat.show(y) ++ "," ++ Nat.show(z) ++ "," ++ U32.show(block) ++ "]\n"

# `String.append(a, b)` copies only `a` and links to `b`, so a long snapshot is
# built by prepending reversed pieces and reversing the whole string once.
def pushed(piece: String, +acc: String) -> String:
  String.append(String.reverse(piece), acc)

def encode_lines(edits: List<&2, WorldState.Edit>, +acc: String) -> String:
  match edits:
    case Nil{}:
      acc
    case Con{head, tail}:
      encode_lines(tail, pushed(edit_line(head), acc))

def encode(snapshot: Snapshot) -> String:
  Snapshot{+seed, +edits} = snapshot
  +head = pushed(count_line(edits), pushed(seed_line(seed), pushed(magic() ++ "\n", SNil{})))
  String.reverse(encode_lines(edits, head))

# A native edit line and the lines left after it. A line that is not one
# well-formed `[x, y, z, block]` record is `Malformed`: the format puts one
# record on a line, so a comma after the bracket belongs to no line at all.
def lines.read.more(edit: WorldState.Edit, tail: List<&2, String>) -> Line:
  match tail:
    case Nil{}:
      Last{edit}
    case Con{next, +after}:
      Read{edit, next, after}

def lines.read.at(over: Bool, x: U32, y: U32, z: U32, block: U32, tail: List<&2, String>) -> Line:
  Bool.pick(Line, over,
    lines.read.more(WorldState.Edit{U32.to_nat(x), U32.to_nat(y), U32.to_nat(z), block}, tail),
    Malformed{})

def lines.read(found: Maybe<&2, Quad>, tail: List<&2, String>) -> Line:
  match found:
    case None{}:
      Malformed{}
    case Some{Quad{x, y, z, block, +comma, next}}:
      lines.read.at(Bool.and(String.is_empty(next), Bool.not(comma)), x, y, z, block, tail)

def lines.of(rest: List<&2, String>) -> Line:
  match rest:
    case Nil{}:
      Empty{}
    case Con{head, tail}:
      lines.read(edit_tuple(head, True{}), tail)

def pending.done(seed: Nat, log: List<&2, WorldState.Edit>) -> Maybe<&2, Snapshot>:
  +read = List.reverse.go(&2, WorldState.Edit, log, Nil{})
  Bool.pick(Maybe<&2, Snapshot>, checked(read), Some{Snapshot{seed, read}}, None{})

# Every native line ends with a newline, so the text after the last edit is one
# empty line; a file written without the final newline has none.
def pending.trimmed.last(head: String, tail: List<&2, String>, +rest: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(head), tail, rest)

def pending.trimmed.drop(head: String, tail: List<&2, String>, rest: List<&2, String>) -> List<&2, String>:
  pending.trimmed.last(head, tail, rest)

def pending.trimmed(rest: List<&2, String>) -> List<&2, String>:
  match rest:
    case Con{+head, +tail}:
      pending.trimmed.drop(head, tail, rest)
    case Nil{}:
      rest

# Every native line ends with a newline, so the text after the last edit is one
# empty line; a file written without a final newline has none. Dropping it leaves
# exactly the declared number of edit lines.
def pending.trim(rest: List<&2, String>) -> List<&2, String>:
  List.reverse.go(&2, String, pending.trimmed(List.reverse(&2, String, rest)), Nil{})

# `left` is the declared number of lines and shrinks every step, so the walk
# cannot outlast the file even though the line count is already checked.
def pending.walk(left: Nat, line: Line, seed: Nat, log: List<&2, WorldState.Edit>) -> Maybe<&2, Snapshot>:
  match left line:
    case 0n _:
      None{}
    case 1n+more Empty{}:
      None{}
    case 1n+more Malformed{}:
      None{}
    case 1n+more Last{edit}:
      pending.done(seed, Con{edit, log})
    case 1n+more Read{edit, next, rest}:
      pending.walk(more, lines.read(edit_tuple(next, True{}), rest), seed, Con{edit, log})

def pending.start.empty(empty: Bool, rest: List<&2, String>, seed: Nat, declared: Nat) -> Maybe<&2, Snapshot>:
  match empty:
    case True{}:
      pending.done(seed, Nil{})
    case False{}:
      pending.walk(declared, lines.of(rest), seed, Nil{})

def pending.start(+rest: List<&2, String>, seed: Nat, declared: Nat) -> Maybe<&2, Snapshot>:
  pending.start.empty(List.is_empty(&2, String, rest), rest, seed, declared)

def pending.counted(fits: Bool, rest: List<&2, String>, seed: Nat, declared: Nat) -> Maybe<&2, Snapshot>:
  match fits:
    case True{}:
      pending.start(rest, seed, declared)
    case False{}:
      None{}

# The file must hold exactly the number of edit lines it declares.
def pending.reading(+rest: List<&2, String>, seed: Nat, +declared: Nat) -> Maybe<&2, Snapshot>:
  pending.counted(Nat.is_eq(List.length(&2, String, pending.trim(rest)), declared),
    pending.trim(rest), seed, declared)

def decode.fits(fits: Bool, declared: Nat, seed: Nat, rest: List<&2, String>) -> Maybe<&2, Snapshot>:
  match fits:
    case True{}:
      pending.reading(rest, seed, declared)
    case False{}:
      None{}

def decode.declared(seed: Nat, +declared: Nat, rest: List<&2, String>) -> Maybe<&2, Snapshot>:
  decode.fits(Nat.is_le(declared, max_edits()), declared, seed, rest)

def decode.counted(seed: Nat, count: Maybe<&2, U32>, rest: List<&2, String>) -> Maybe<&2, Snapshot>:
  match count:
    case None{}:
      None{}
    case Some{value}:
      decode.declared(seed, U32.to_nat(value), rest)

def decode.seed(found: Maybe<&2, Nat>, count: Maybe<&2, U32>, rest: List<&2, String>) ->
  Maybe<&2, Snapshot>:
  match found:
    case None{}:
      None{}
    case Some{seed}:
      decode.counted(seed, count, rest)

def decode.whole(next: String, value: U32) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, String.is_empty(next), Some{value}, None{})

def decode.counted_line(found: Maybe<&2, Number>) -> Maybe<&2, U32>:
  match found:
    case None{}:
      None{}
    case Some{Number{value, next}}:
      decode.whole(next, value)

def decode.count(count_line: String) -> Maybe<&2, U32>:
  decode.counted_line(number(count_line))

def decode.members(seed_line: String, count_line: String, rest: List<&2, String>) -> Maybe<&2, Snapshot>:
  decode.seed(seed_text(seed_line), decode.count(count_line), rest)

def decode.header(header: String, seed_line: String, count_line: String, rest: List<&2, String>) ->
  Maybe<&2, Snapshot>:
  Bool.pick(Maybe<&2, Snapshot>, String.eq(header, magic()),
    decode.members(seed_line, count_line, rest), None{})

def decode.lines(lines: List<&2, String>) -> Maybe<&2, Snapshot>:
  match lines:
    case Con{header, Con{seed_line, Con{count_line, rest}}}:
      decode.header(header, seed_line, count_line, rest)
    case _:
      None{}

def decode.within(within_limit: Bool, text: String) -> Maybe<&2, Snapshot>:
  match within_limit:
    case True{}:
      decode.lines(String.split(text, '\n'))
    case False{}:
      None{}

# The same checks as a legacy document: canonical numbers, the edit cap, legal
# world edits and one entry per cell.
def decode(+text: String) -> Maybe<&2, Snapshot>:
  decode.within(Nat.is_le(String.length(text), max_native_input()), text)
