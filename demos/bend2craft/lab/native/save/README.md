# Native save migration, phase 1

`save.bend` reads an existing save into the native runtime's world
data and writes the native snapshot that data comes back as. It is pure and
total: it never opens, renames or truncates a file, so **a refused document
cannot cost a user data** — the caller keeps the file and decides what to do.

```
read_v1(legacy text) -> Import          Imported | UnsupportedVersion | Rejected
encode(Snapshot)    -> native text      seed + N edits
decode(native text) -> Maybe<Snapshot>
```

Both formats go through `checked`, so a snapshot is only ever produced from a
log in which every edit is a legal world edit and no cell is named twice.

## Legacy input: snapshot version 1

The exact document `server/room/snapshot.js` version 1 wrote to
`worlds/multiplayer.json`: `JSON.stringify` of `{version, seed, seq, edits}`
plus the newline `server/node-host.mjs` appends.

```
{"version":1,"seed":"1337","seq":2,"edits":[[1,8,1,0],[2,8,1,26]]}
```

Read as a strict subset of JSON, not as a general JSON tokenizer: one object
whose members are `version`, `seed`, `seq` and `edits`, in any order, separated
by JSON whitespace (space, tab, LF, CR). The subset is the whole of what a
version 1 snapshot can be; a general tokenizer would add string escapes,
fractions, exponents and arbitrary nesting that a version 1 snapshot can never
contain.

* `version` — the integer `1`.
* `seq` — a non-negative integer, kept in `Imported{seq}` for the room that
  will own it. Phase 1 does not build a `Multiplayer.Room`.
* `seed` — a quoted canonical decimal (`BigInt.toString`): no sign, no
  fraction, no leading zero, at most 15 digits and at most 281474976710655,
  which is also the largest seed a Bend `Nat` world can hold.
* `edits` — `[x, y, z, block]` in stored (Bend) coordinates: `[` four
  non-negative integers separated by commas `]`.

## Native output: `B2CW:1`

Line-oriented, one record per line, LF endings:

```
B2CW:1
1337
3
[1,8,1,0]
[2,8,1,26]
[94371839,3,94371839,12]
```

The header, the seed, the number of edits, then exactly that many records. The
file may end with or without the final newline. `B2CW:1` is the native
runtime's own format and is unrelated to the `B2CS:1` probe codec in
`native/save-probe`, which holds a single edit and cannot read either format.

`B2CW:1` carries the seed and the edit log, which is what phase 1 migrates.
It does not carry the room sequence, chests, furnaces, the world clock or the
block simulation; see below.

## What is refused, and why

Nothing is applied partially. Each of these returns `Rejected{}` (or
`decode` returns `None`) for the whole document:

| Refused | Why |
| --- | --- |
| a version other than 1 | reported as `UnsupportedVersion{version}`, so a version 2 or 3 save says what it is |
| a missing, non-integer or unreadable `version` | malformed |
| a seed that is not canonical decimal, is negative, has a leading zero or exceeds 2^48 - 1 | malformed, or a seed no Bend `Nat` world can hold |
| a number that is not a non-negative integer: `1.5`, `1e3`, `+1`, `-1`, `01`, a value past 2^32 - 1 | malformed |
| a missing or extra member, a repeated member, a member outside the four | malformed, or data this migration does not read |
| a truncated document, or anything after the closing brace | malformed |
| an edit outside the world band, or a block id above 27 | `Multiplayer.valid_edit` refuses it |
| two edits of one cell | a `WorldState` log holds one entry per cell, so a repeat is damage |
| more edits than `max_edits()` | work and memory guard |
| an input longer than `max_json_input()` / `max_native_input()` | work and memory guard, checked before any parsing |

## Limits

`max_edits()` is 1024 edits; `max_json_input()` and `max_native_input()` follow
from it. The cap is a guard, not a format limit, and it is deliberately small:
Base's `String.length`, `List.all`, `List.sort` and `String.split` are not tail
recursive, and the TypeScript lane `scripts/test-suite.sh` uses overflows its
stack a little past 40,000 of them, so a cap whose test document fits under
that keeps this regression runnable in both lanes. A world with more distinct
edited cells than the cap has to raise `max_edits()` first; the native target has
no such limit. Raising it only widens the two input caps.

The input caps assume the canonical form `JSON.stringify` and `encode` produce.
A document reformatted with interior whitespace can exceed them and is then
refused whole.

## Checks

```bash
# native binary (the migration's own target)
.tools/bend-local/bin/bend lab/native/save/save_test.bend -o /tmp/save-migration
/tmp/save-migration

# the TypeScript lane, the way scripts/test-suite.sh runs the native probes
bash scripts/check-bend.sh lab/native/save/save_test.bend
```

Both print `native save migration ok`; a failure prints the first failing case
and exits 1.

## Not migrated yet

Phase 1 moves the seed and the block edit log, and refuses everything else
rather than dropping it. Still to migrate, with the next step for each:

| Data | Where it lives today | Next step |
| --- | --- | --- |
| the room sequence number | `Imported{seq}` (read, not stored) | add `seq` to the native snapshot once a native `Multiplayer.Room` exists |
| chests (snapshot version 2) | `snapshot.chests` | a `[x,y,z]` + slots record per line, read through `Chests.World` |
| furnaces (version 2) | `snapshot.furnaces` | a `[x,y,z]` + state record per line, read through `Furnaces.World` |
| the world clock (version 2) | `snapshot.time` | one decimal line after the seed; a `Furnaces` tick needs it |
| the block simulation (version 3) | `snapshot.simulation`, an encoded string | decode `world/simulation.bend`'s own format in Bend, then add it to the native snapshot |
| the browser save | `web/persistent-save.js`, a two-slot revision journal with `__bend2craft_bigint` tags | a second importer for that shape, reusing the same `checked` gate; the tag encoding has to be read first |
| player profiles, inventories and positions | browser local storage | not world data; separate work, and `web/inventory.js` still owns the transitions |

Versions 2 and 3 are recognized far enough to be reported as
`UnsupportedVersion{n}`: every snapshot this repository ever wrote puts
`version` first, so it is read before the members phase 1 does not migrate end
the walk.
