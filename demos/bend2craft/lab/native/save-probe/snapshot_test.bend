import Base
import ./snapshot.bend as Snapshot

def same_edits(a: Snapshot.Edit, b: Snapshot.Edit) -> Bool:
  match a b:
    case Snapshot.Edit{x_a, y_a, z_a, block_a} Snapshot.Edit{x_b, y_b, z_b, block_b}:
      Bool.and(U32.is_eq(x_a, x_b),
        Bool.and(U32.is_eq(y_a, y_b),
          Bool.and(U32.is_eq(z_a, z_b), U32.is_eq(block_a, block_b))))

def same(a: Snapshot.Snapshot, b: Snapshot.Snapshot) -> Bool:
  match a b:
    case Snapshot.Snapshot{seed_a, edit_a} Snapshot.Snapshot{seed_b, edit_b}:
      Bool.and(U32.is_eq(seed_a, seed_b),
        same_edits(edit_a, edit_b))

def matches(maybe_snapshot: Maybe<&2, Snapshot.Snapshot>, expected: Snapshot.Snapshot) -> Bool:
  match maybe_snapshot:
    case None{}:
      False{}
    case Some{snapshot}:
      same(snapshot, expected)

def roundtrips(+snapshot: Snapshot.Snapshot) -> Bool:
  matches(Snapshot.decode(Snapshot.encode(snapshot)), snapshot)

def rejects(maybe_snapshot: Maybe<&2, Snapshot.Snapshot>) -> Bool:
  match maybe_snapshot:
    case None{}:
      True{}
    case Some{snapshot}:
      False{}

def passes() -> Bool:
  +expected: Snapshot.Snapshot = Snapshot.Snapshot{1337, Snapshot.Edit{40, 8, 40, 14}}
  +encoded: String = Snapshot.encode(expected)
  +maximum: Snapshot.Snapshot = Snapshot.Snapshot{
    4294967295, Snapshot.Edit{4294967295, 4294967295, 4294967295, 4294967295}}
  String.eq(encoded, "B2CS:1:1337:40:8:40:14")
    && roundtrips(expected)
    && String.eq(Snapshot.encode(maximum),
      "B2CS:1:4294967295:4294967295:4294967295:4294967295:4294967295")
    && roundtrips(maximum)
    && rejects(Snapshot.decode("B2CS:2:1337:40:8:40:14"))
    && rejects(Snapshot.decode("B2CS:1:1337:40::40:14"))
    && rejects(Snapshot.decode("B2CS:1:01337:40:8:40:14"))
    && rejects(Snapshot.decode("B2CS:1:1337:40:8:40:4294967296"))
    && rejects(Snapshot.decode("B2CS:1:1337:40:8:40:14:extra"))
    && rejects(Snapshot.decode(String.repeat("x", 62n)))

def main.result(valid: Bool) -> IO(Unit):
  match valid:
    case False{}:
      IO.die(Unit, 1, "native save probe failed")
    case True{}:
      IO.print("native save probe ok")

def main() -> IO(Unit):
  main.result(passes())

#|native save probe ok
