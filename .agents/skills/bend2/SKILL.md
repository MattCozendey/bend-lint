---
name: bend2
description:
  "Rules to write and check Bend2 code. Use before you write, review or check Bend code, a law, a
  proof or a test."
---

# Bend2

## Setup

1. Run `bend guide` once per session, before you write Bend code. Use the `bend` on PATH, also if it
   is a fork or a different version.
2. Before parallel or performance work, run `bend guide shaders`. Before a custom effect, run
   `bend guide effects`.
3. After a change, run `bend <file> --check-only` on each changed file and on each proof file that
   depends on it. Report the result.

Do not run `--verdict` unless the user asks.

## Code

- Before you write a def, search for it: `bend base <Name>`.
- Write small capabilities yourself. Import large ones from BendHub. Do not copy hub code. If the
  hub does not have it, tell the user.
- Use `@unsafe` only when the user asks. Above each use, write a comment that says why it is safe.
- Use foreign code only when the user approves.
- A helper with one caller is OK (for example, to match on a computed value, or to split a pair). A
  def that only passes its arguments on is not.
- A def calls only defs above it: put operations before laws.
- Above each law, write a comment that says what it asks.

## Names

Use the repo's conventions. Where they say nothing, name defs as Base does:

- `Type.verb`: the type or concept, then the action (`Wire.ask`, `Reader.add`). A def about none of
  its file's types is the verb alone; the import alias gives the prefix (`Lists.append`).
- Bool: `is_x`, `has_x`, or a verb in the third person (`fits`). Compare: `is_lt`, `is_le`, `is_eq`.
- Opposites, always in pairs: `to_x`/`from_x` convert; `show` gives a String, `read` parses it back
  to a Maybe; `get`/`set` (and `add`) act on a collection.
- `T.of` makes a T from its parts.
- Add the unit where it is not clear (`timeout_ms`, `size_bytes`). Use full words, except
  established abbreviations.
- Law: its property (`get_after_set`, `set_preserves_size`).
- Helper of `f`: `f.go` (loop), `f.step` (one step), `f.done` (end result), `f.if` (Bool branch),
  `f.of` (`f` from parts that it computed), or another short verb.
- A def that continues after an effect, or after a match on a result: the event, in the past tense.
  It takes the result: `Config.opened(folder, opened)`.

## Checks

Make the bug impossible to write: give it a type that cannot hold a bad value. Use a law only when a
type cannot rule the bug out. Use a test only when a law cannot state the behavior.

| Kind        | It checks                                               | Example                                  |
| ----------- | ------------------------------------------------------- | ---------------------------------------- |
| Law         | Our code against our definitions, for all inputs.       | `Map.get_after_set`                      |
| Test a      | IO, foreign code, or process output.                    | A stdin reader.                          |
| Test b      | Our code or definitions against a source we do not own. | A parser against the standard's vectors. |
| Test c      | A claim a law can state, until its proof is affordable. | A fast def against another program.      |
| Measurement | Speed. No pass or fail.                                 | Operations per second.                   |

Each test states its kind. A kind c test also names the law that will replace it. A law replaces
kind c only. Kind b stays: a law cannot compare our definitions with the world.

### Laws that matter

A law costs a proof. State it only if it stops a bug that someone could write. Do not state a law
that:

- holds by definition (it restates a body, or evaluation proves it);
- checks a constant (length, order or uniqueness of a hardcoded list);
- is vacuous ("every" over a list that can be empty, or a premise that never holds);
- fixes an implementation detail that no caller uses;
- repeats a law, or follows from proven laws in one step.

Good laws relate operations: round trip (`read_after_show`), access after update (`get_after_set`),
frame (`set_keeps_other_keys`), kept measure (`set_preserves_size`), fast def equals clear def.

### Proofs

- Trust the checker. Bend is sound: a proof that checks is correct. Do not look for counterexamples.
- A law's statement obeys the code rules. Its proof body does not, unless it is too expensive to
  check.
- Ask the user before you review a proof body, or code that a proven law covers.
- Priority: good laws and an ergonomic API.
- If a proven law covers a def, use that def. Do not write or use an unproven def that does the
  same.
