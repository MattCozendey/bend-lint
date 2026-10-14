import Base
import ../world/world_state.bend as WorldState
import ./save.bend as Migration

# Regression for the phase 1 save migration: a legacy multiplayer snapshot
# version 1 (a seed and a block edit log) read into a WorldState edit log, and
# the native B2CW:1 snapshot that carries the same data.
#
# Every case is a pure function of the text it names, so the same input twice
# gives the same answer, and the importer only reads its input: a refused
# document leaves the file on disk untouched.

type Check is Data:
  Check{name: String, ok: Bool}

# The document server/room/snapshot.js version 1 wrote to worlds/multiplayer.json:
# JSON.stringify of {version, seed, seq, edits} plus the newline node-host.mjs
# appends. The last edit names the cell a world coordinate of -1 stores, so the
# fixture covers a positive and a negative stored coordinate.
def v1_fixture() -> String:
  "{\"version\":1,\"seed\":\"1337\",\"seq\":2,\"edits\":[[1,8,1,0],[2,8,1,26],[94371839,3,94371839,12]]}\n"

def v1_fixture_literal() -> String:
  "{\"version\":1,\"seed\":\"1337\",\"seq\":2,\"edits\":[[1,8,1,0],[2,8,1,26],[94371839,3,94371839,12]]}\n"

def fixture_edits() -> List<&2, WorldState.Edit>:
  [WorldState.Edit{1n, 8n, 1n, 0}, WorldState.Edit{2n, 8n, 1n, 26}, WorldState.Edit{94371839n, 3n, 94371839n, 12}]

# A document with the members reordered and spaced, still version 1.
def v1_spaced() -> String:
  "{ \"edits\" : [ [1, 8, 1, 26] ] ,\n  \"seed\" : \"7\" , \"seq\" : 5 , \"version\" : 1 }\n"

def v1_empty() -> String:
  "{\"version\":1,\"seed\":\"1337\",\"seq\":0,\"edits\":[]}\n"

# Documents under test ------------------------------------------------------------

def one_edit_document(x: Nat, y: Nat, z: Nat, block: U32) -> String:
  "{\"version\":1,\"seed\":\"1337\",\"seq\":1,\"edits\":[[" ++ Nat.show(x) ++ "," ++ Nat.show(y)
    ++ "," ++ Nat.show(z) ++ "," ++ U32.show(block) ++ "]]}"

def edits_document(edits: String) -> String:
  "{\"version\":1,\"seed\":\"1337\",\"seq\":1,\"edits\":[" ++ edits ++ "]}"

def units.go(left: Nat, +i: Nat, acc: List<&2, String>) -> List<&2, String>:
  match left:
    case 0n:
      List.reverse.go(&2, String, acc, Nil{})
    case 1n+more:
      units.go(more, (1n + i : Nat), Con{"[" ++ Nat.show(i) ++ ",8,1,0]", acc})

# count distinct cells, so a refusal can only come from the edit cap.
def distinct_units(count: Nat) -> List<&2, String>:
  units.go(count, 0n, Nil{})

# Builds the document in reverse, one short piece at a time, so a cap-sized
# document costs a pass rather than a pass per piece.
def units.join(xs: List<&2, String>, +acc: String) -> String:
  match xs:
    case Nil{}:
      String.reverse(acc)
    case Con{head, Nil{}}:
      String.reverse(Migration.pushed(head, acc))
    case Con{head, tail}:
      units.join(tail, Migration.pushed(head ++ ",", acc))

def edits_document_of(count: Nat) -> String:
  edits_document(units.join(distinct_units(count), SNil{}))

def version_document(version: Nat, tail: String) -> String:
  "{\"version\":" ++ Nat.show(version) ++ "," ++ tail ++ "}"

# Assertions ---------------------------------------------------------------------

def same_bool(b: Bool) -> Bool:
  b

def all_of(flags: List<&2, Bool>) -> Bool:
  List.all(~&2, ~Bool, ~same_bool, flags)

def refused(result: Migration.Import) -> Bool:
  match result:
    case Migration.Rejected{}:
      True{}
    case Migration.Imported{seq, seed, edits}:
      False{}
    case Migration.UnsupportedVersion{version}:
      False{}

def read_refuses(text: String) -> Bool:
  refused(Migration.read_v1(text))

def unsupported_at(result: Migration.Import, version: U32) -> Bool:
  match result:
    case Migration.UnsupportedVersion{found}:
      U32.is_eq(found, version)
    case Migration.Imported{seq, seed, edits}:
      False{}
    case Migration.Rejected{}:
      False{}

def seed_of(result: Migration.Import) -> Nat:
  match result:
    case Migration.Imported{+seq, seed, edits}:
      seed
    case Migration.UnsupportedVersion{+version}:
      0n
    case Migration.Rejected{}:
      0n

def seq_of(result: Migration.Import) -> U32:
  match result:
    case Migration.Imported{seq, +seed, +edits}:
      seq
    case Migration.UnsupportedVersion{version}:
      0
    case Migration.Rejected{}:
      0

def edits_of(result: Migration.Import) -> List<&2, WorldState.Edit>:
  match result:
    case Migration.Imported{seq, seed, +edits}:
      edits
    case Migration.UnsupportedVersion{version}:
      Nil{}
    case Migration.Rejected{}:
      Nil{}

def x_of(edit: WorldState.Edit) -> Nat:
  WorldState.Edit{x, y, z, block} = edit
  x

def y_of(edit: WorldState.Edit) -> Nat:
  WorldState.Edit{x, y, z, block} = edit
  y

def z_of(edit: WorldState.Edit) -> Nat:
  WorldState.Edit{x, y, z, block} = edit
  z

def block_of(edit: WorldState.Edit) -> U32:
  WorldState.Edit{x, y, z, block} = edit
  block

def same_edits(+a: WorldState.Edit, +b: WorldState.Edit) -> Bool:
  WorldState.edit_matches(a, x_of(b), y_of(b), z_of(b)) && U32.is_eq(block_of(a), block_of(b))

def same_log(a: List<&2, WorldState.Edit>, b: List<&2, WorldState.Edit>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Con{first_a, tail_a} Con{first_b, tail_b}:
      Bool.and(same_edits(first_a, first_b), same_log(tail_a, tail_b))
    case _ _:
      False{}

def read_ok(+result: Migration.Import, seed: Nat, edits: List<&2, WorldState.Edit>) -> Bool:
  Bool.and(Nat.is_eq(seed_of(result), seed), same_log(edits_of(result), edits))

def migrated(text: String, seed: Nat, edits: List<&2, WorldState.Edit>) -> Bool:
  read_ok(Migration.read_v1(text), seed, edits)

def decode_ok(found: Maybe<&2, Migration.Snapshot>, seed: Nat, edits: List<&2, WorldState.Edit>) -> Bool:
  match found:
    case None{}:
      False{}
    case Some{Migration.Snapshot{+got_seed, +got_edits}}:
      Bool.and(Nat.is_eq(got_seed, seed), same_log(got_edits, edits))

def round_trips(snapshot: Migration.Snapshot, seed: Nat, edits: List<&2, WorldState.Edit>) -> Bool:
  decode_ok(Migration.decode(Migration.encode(snapshot)), seed, edits)

def snapshot_of(+result: Migration.Import) -> Migration.Snapshot:
  Migration.Snapshot{seed_of(result), edits_of(result)}

def encoded(text: String, snapshot: Migration.Snapshot) -> Bool:
  String.eq(Migration.encode(snapshot), text)

def decodes(found: Maybe<&2, Migration.Snapshot>) -> Bool:
  match found:
    case None{}:
      False{}
    case Some{Migration.Snapshot{+seed, +edits}}:
      True{}

def rejects_native(text: String) -> Bool:
  Bool.not(decodes(Migration.decode(text)))

# Legacy import ------------------------------------------------------------------

def legacy_fixture() -> Bool:
  migrated(v1_fixture(), 1337n, fixture_edits())

def legacy_fixture_sequence() -> Bool:
  U32.is_eq(seq_of(Migration.read_v1(v1_fixture())), 2)

def legacy_empty_log() -> Bool:
  migrated(v1_empty(), 1337n, Nil{})

def legacy_spaced_and_reordered() -> Bool:
  migrated(v1_spaced(), 7n, [WorldState.Edit{1n, 8n, 1n, 26}])

def unsupported_versions() -> Bool:
  all_of([
    unsupported_at(Migration.read_v1(version_document(2n, "\"seed\":\"1337\",\"seq\":1,\"edits\":[]")), 2),
    unsupported_at(Migration.read_v1(version_document(0n, "\"seed\":\"1337\",\"seq\":1,\"edits\":[]")), 0),
    unsupported_at(Migration.read_v1(
      version_document(3n, "\"seed\":\"1337\",\"seq\":1,\"edits\":[[1,8,1,0]],\"chests\":[{\"pos\":[1,8,1],"
        ++ "\"slots\":[[5,3,0]]}],\"furnaces\":[{\"pos\":[2,8,1],\"state\":null}],\"time\":12,"
        ++ "\"simulation\":\"B2SIM:1\"")), 3)
  ])

def versions_without_a_usable_one() -> Bool:
  all_of([
    read_refuses("{\"seed\":\"1337\",\"seq\":1,\"edits\":[]}"),
    read_refuses("{\"version\":,\"seed\":\"1337\",\"seq\":1,\"edits\":[]}"),
    read_refuses("{\"version\":\"1\",\"seed\":\"1337\",\"seq\":1,\"edits\":[]}"),
    read_refuses("{\"version\":1.0,\"seed\":\"1337\",\"seq\":1,\"edits\":[]}"),
    read_refuses("{\"version\":1e0,\"seed\":\"1337\",\"seq\":1,\"edits\":[]}")
  ])

def seeds_that_are_refused() -> Bool:
  all_of([
    read_refuses("{\"version\":1,\"seed\":\"abc\",\"seq\":1,\"edits\":[]}"),
    read_refuses("{\"version\":1,\"seed\":\"\",\"seq\":1,\"edits\":[]}"),
    read_refuses("{\"version\":1,\"seed\":\"1.5\",\"seq\":1,\"edits\":[]}"),
    read_refuses("{\"version\":1,\"seed\":\"0x10\",\"seq\":1,\"edits\":[]}"),
    read_refuses("{\"version\":1,\"seed\":\"1337 \",\"seq\":1,\"edits\":[]}"),
    read_refuses("{\"version\":1,\"seed\":\"01337\",\"seq\":1,\"edits\":[]}"),
    read_refuses("{\"version\":1,\"seed\":\"+7\",\"seq\":1,\"edits\":[]}"),
    read_refuses("{\"version\":1,\"seed\":\"-1\",\"seq\":1,\"edits\":[]}"),
    read_refuses("{\"version\":1,\"seed\":\"281474976710656\",\"seq\":1,\"edits\":[]}"),
    read_refuses("{\"version\":1,\"seed\":\"99999999999999999999\",\"seq\":1,\"edits\":[]}")
  ])

def malformed_numbers_are_refused() -> Bool:
  all_of([
    read_refuses(edits_document("[1.5,2,3,4]")),
    read_refuses(edits_document("[1e3,2,3,4]")),
    read_refuses(edits_document("[+1,2,3,4]")),
    read_refuses(edits_document("[-1,2,3,4]")),
    read_refuses(edits_document("[01,2,3,4]")),
    read_refuses(edits_document("[4294967296,2,3,4]")),
    read_refuses(edits_document("[1,2,3]")),
    read_refuses(edits_document("[1,2,3,4,5]")),
    read_refuses(edits_document("[1,2,3,]")),
    read_refuses(edits_document("[1 2 3 4]")),
    read_refuses(edits_document("[1,2,3,4] trailing")),
    read_refuses(edits_document("[,1,2,3,4]"))
  ])

def truncated_documents_are_refused() -> Bool:
  all_of([
    read_refuses("{\"version\":1,\"seed\":\"1337\""),
    read_refuses("{\"version\":1,\"seed\":\"1337\",\"seq\":1"),
    read_refuses("{\"version\":1,\"seed\":\"1337\",\"seq\":1,\"edits\":[[1,8,1"),
    read_refuses("{\"version\":1,\"seed\":\"1337\",\"seq\":1,\"edits\":[[1,8,1,"),
    read_refuses("{\"version\":1,\"seed\":\"1337\",\"seq\":1,\"edits\":[[1,8,1,0]"),
    read_refuses("{\"version\":1,\"seed\":\"1337\",\"seq\":1,\"edits\":[[1,8,1,0]]"),
    read_refuses("{\"version\":1,\"seed\":\"1337\",\"seq\":1,\"edits\":[[1,8,1,0]]},"),
    read_refuses("{\"version\":1,\"seed\":\"1337\",\"seq\":1,\"edits\":[[1,8,1,0]]}x")
  ])

def over_long_input_is_refused() -> Bool:
  all_of([
    read_refuses(v1_fixture() ++ String.repeat(" ", (1n + Migration.max_json_input() : Nat))),
    read_refuses(String.repeat("x", (1n + Migration.max_json_input() : Nat)))
  ])

def duplicate_cells_are_refused() -> Bool:
  all_of([
    read_refuses(edits_document("[1,8,1,0],[1,8,1,26]")),
    read_refuses(edits_document(
      "[1,8,1,0],[2,8,1,26],[3,8,1,0],[4,8,1,26],[5,8,1,0],[6,8,1,26],[7,8,1,0],[1,8,1,26]"))
  ])

def out_of_world_cells_are_refused() -> Bool:
  all_of([
    read_refuses(one_edit_document(94371840n, 8n, 1n, 0)),
    read_refuses(one_edit_document(4294967295n, 8n, 1n, 0)),
    read_refuses(one_edit_document(1n, 64n, 1n, 0)),
    read_refuses(one_edit_document(1n, 8n, 94371840n, 0)),
    read_refuses(one_edit_document(1n, 8n, 1n, 28)),
    read_refuses(one_edit_document(1n, 8n, 1n, 4294967295))
  ])

def unknown_and_repeated_members_are_refused() -> Bool:
  all_of([
    read_refuses("{\"version\":1,\"version\":1,\"seed\":\"1337\",\"seq\":1,\"edits\":[]}"),
    read_refuses("{\"version\":1,\"seed\":\"1337\",\"seed\":\"7\",\"seq\":1,\"edits\":[]}"),
    read_refuses("{\"version\":1,\"seed\":\"1337\",\"seq\":1,\"edits\":[],\"edits\":[]}"),
    read_refuses("{\"version\":1,\"seed\":\"1337\",\"seq\":1,\"edits\":[],\"chests\":[]}"),
    read_refuses("{\"version\":1,\"seed\":\"1337\",\"seq\":1,\"edits\":[],\"time\":5}"),
    read_refuses("[]"),
    read_refuses("1337"),
    read_refuses("\"version\"")
  ])

def edit_count_at_the_cap_is_accepted() -> Bool:
  Bool.not(read_refuses(edits_document_of(Migration.max_edits())))

def edit_count_above_the_cap_is_refused() -> Bool:
  read_refuses(edits_document_of((1n + Migration.max_edits() : Nat)))

# Native snapshot ----------------------------------------------------------------

def native_text() -> Bool:
  all_of([
    encoded("B2CW:1\n1337\n3\n[1,8,1,0]\n[2,8,1,26]\n[94371839,3,94371839,12]\n",
      Migration.Snapshot{1337n, fixture_edits()}),
    encoded("B2CW:1\n0\n0\n", Migration.Snapshot{0n, Nil{}}),
    decode_ok(Migration.decode("B2CW:1\n1337\n1\n[1,8,1,26]"), 1337n,
      [WorldState.Edit{1n, 8n, 1n, 26}])
  ])

def native_round_trip() -> Bool:
  round_trips(Migration.Snapshot{1337n, fixture_edits()}, 1337n, fixture_edits())

def migration_round_trip() -> Bool:
  round_trips(snapshot_of(Migration.read_v1(v1_fixture())), 1337n, fixture_edits())

def native_rejects() -> Bool:
  all_of([
    rejects_native(""),
    rejects_native("B2CW:1"),
    rejects_native("B2CW:1\n1337"),
    rejects_native("B2CW:1\n1337\n"),
    rejects_native("B2CW:2\n1337\n0\n"),
    rejects_native("B2CS:1\n1337\n0\n"),
    rejects_native("B2CW:1\n01337\n0\n"),
    rejects_native("B2CW:1\n-1\n0\n"),
    rejects_native("B2CW:1\n281474976710656\n0\n"),
    rejects_native("B2CW:1\n1337\n01\n"),
    rejects_native("B2CW:1\n1337\n-1\n"),
    rejects_native("B2CW:1\n1337\n1\n"),
    rejects_native("B2CW:1\n1337\n0\n[1,8,1,26]\n"),
    rejects_native("B2CW:1\n1337\n999999999\n"),
    rejects_native("B2CW:1\n1337\n1\n[1,8,1,26]\n[2,8,1,26]\n"),
    rejects_native("B2CW:1\n1337\n2\n[1,8,1,0]\n[1,8,1,26]\n"),
    rejects_native("B2CW:1\r\n1337\r\n0\r\n"),
    rejects_native("B2CW:1\n1337\n1\n[1,8,1]\n"),
    rejects_native("B2CW:1\n1337\n1\n[1,8,1,26,5]\n"),
    rejects_native("B2CW:1\n1337\n1\n1,8,1,26\n"),
    rejects_native("B2CW:1\n1337\n1\n [1,8,1,26]\n"),
    rejects_native("B2CW:1\n1337\n1\n[1,8,1,26],[2,8,1,26]\n"),
    rejects_native("B2CW:1\n1337\n1\n[94371840,8,1,0]\n"),
    rejects_native("B2CW:1\n1337\n1\n[1,64,1,0]\n"),
    rejects_native("B2CW:1\n1337\n1\n[1,8,1,28]\n"),
    rejects_native("B2CW:1\n1337\n0\n" ++ String.repeat(" ", (1n + Migration.max_native_input() : Nat)))
  ])

def distinct_edits.walk(left: Nat, +i: Nat, acc: List<&2, WorldState.Edit>) -> List<&2, WorldState.Edit>:
  match left:
    case 0n:
      acc
    case 1n+more:
      distinct_edits.walk(more, (1n + i : Nat), Con{WorldState.Edit{i, 8n, 1n, 0}, acc})

def distinct_edits(count: Nat) -> List<&2, WorldState.Edit>:
  distinct_edits.walk(count, 0n, Nil{})

def native_cap_text() -> String:
  Migration.encode(Migration.Snapshot{1337n, distinct_edits(Migration.max_edits())})

def native_cap_round_trip() -> Bool:
  decode_ok(Migration.decode(native_cap_text()), 1337n, distinct_edits(Migration.max_edits()))

def native_accepts_at_the_cap() -> Bool:
  native_cap_round_trip()

# Determinism and immutability ---------------------------------------------------

def importer_is_deterministic() -> Bool:
  String.eq(Migration.encode(snapshot_of(Migration.read_v1(v1_fixture()))),
    Migration.encode(snapshot_of(Migration.read_v1(v1_fixture()))))

def importer_leaves_its_input_alone() -> Bool:
  all_of([
    String.eq(v1_fixture(), v1_fixture_literal()),
    legacy_fixture(),
    legacy_fixture()
  ])

def fixture_length() -> Bool:
  Nat.is_eq(String.length(v1_fixture()), 92n)

def native_text_of_fixture() -> String:
  "B2CW:1\n1337\n3\n[1,8,1,0]\n[2,8,1,26]\n[94371839,3,94371839,12]\n"

def native_decode_is_deterministic() -> Bool:
  all_of([
    decodes(Migration.decode(native_text_of_fixture())),
    decodes(Migration.decode(native_text_of_fixture()))
  ])

# The run -----------------------------------------------------------------------

def checks() -> List<&2, Check>:
  [
    Check{"legacy v1 fixture decodes to its seed and edits", legacy_fixture()},
    Check{"legacy v1 fixture keeps its sequence number", legacy_fixture_sequence()},
    Check{"legacy v1 fixture with an empty edit log decodes", legacy_empty_log()},
    Check{"legacy v1 members may be reordered and spaced", legacy_spaced_and_reordered()},
    Check{"native snapshot text is the documented form", native_text()},
    Check{"legacy -> native -> legacy keeps the seed and the edits",
      all_of([native_round_trip(), migration_round_trip()])},
    Check{"snapshot versions other than 1 are reported as unsupported", unsupported_versions()},
    Check{"a missing or non-integer version is refused", versions_without_a_usable_one()},
    Check{"a seed that is not canonical decimal is refused", seeds_that_are_refused()},
    Check{"malformed numbers are refused", malformed_numbers_are_refused()},
    Check{"a truncated document is refused", truncated_documents_are_refused()},
    Check{"input longer than the documented cap is refused", over_long_input_is_refused()},
    Check{"two edits of one cell are refused", duplicate_cells_are_refused()},
    Check{"an out-of-world cell or unknown block is refused", out_of_world_cells_are_refused()},
    Check{"a repeated or unknown member is refused", unknown_and_repeated_members_are_refused()},
    Check{"an edit count at the cap is accepted", edit_count_at_the_cap_is_accepted()},
    Check{"an edit count above the cap is refused", edit_count_above_the_cap_is_refused()},
    Check{"a native snapshot at the cap round trips", native_accepts_at_the_cap()},
    Check{"the native snapshot refuses a bad header, count or line", native_rejects()},
    Check{"the same document twice reads as the same snapshot", importer_is_deterministic()},
    Check{"reading a document leaves it unchanged",
      all_of([importer_leaves_its_input_alone(), fixture_length()])},
    Check{"the native snapshot decodes the same way twice", native_decode_is_deterministic()}
  ]

def first_failure(all: List<&2, Check>, answer: Maybe<&2, String>) -> Maybe<&2, String>:
  match all answer:
    case Nil{} answer:
      answer
    case Con{Check{+name, ok}, tail} None{}:
      Bool.pick(Maybe<&2, String>, ok, first_failure(tail, None{}), Some{name})
    case Con{Check{name, ok}, tail} Some{+message}:
      first_failure(tail, Some{name})

def run(answer: Maybe<&2, String>) -> IO(Unit):
  match answer:
    case None{}:
      IO.print("native save migration ok")
    case Some{name}:
      IO.die(Unit, 1, "native save migration failed: " ++ name)

def main() -> IO(Unit):
  do IO<Unit>:
    answer : Maybe<&2, String> = first_failure(checks(), None{})
    run(answer)

#|native save migration ok
