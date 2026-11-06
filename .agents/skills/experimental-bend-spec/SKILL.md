---
name: experimental-bend-spec
description:
  "Experimental. Split a Bend module into a self-contained spec (spec.bend), its proof (impl.bend)
  and the tests it earned (tests.bend). Use with bend2 before you write, review or check a module's
  laws or tests, or code that calls the module."
---

# Bend spec (experimental)

Source: https://github.com/LeeeeT/winning-is-possible

## Why

A law that imports the code is weak. An agent can change the code, and the law checks but means
less. A caller bug has one of two causes:

1. The spec is not complete.
2. The caller relies on a property that the spec does not state.

## Layout

- `shared.bend` (optional, see feature layout): A self-contained module (its laws, proofs and tests
  live in it). It imports only Base and the `shared` of each layer on the path from it up to `src/`.
- `spec.bend`: the full public interface, and the claims about it. It imports only Base, the
  `shared` of each layer on the path from it up to `src/`, and the `spec.bend` of each feature whose
  names it uses (never an `impl.bend`). The user owns it.
- `impl.bend`: imports `./spec.bend as Spec`. It has the code, fills each interface law, and proves
  each claim. You can rewrite it.
- `tests.bend` (optional): the tests that the module earned (see Tests).
- A caller imports `spec.bend` for the names, and `impl.bend` for the code. It uses only the names
  of `spec.bend`.
- Bend checks the proofs of a file that has or imports foreign or unsafe code, but that file never
  prints ALL PROOFS CHECK. Read its errors: a def that relies on foreign code is not a broken proof.

## spec.bend

- Declare each type and operation that a caller uses as a law without a body:

  ```python
  # a board
  law Game:
    Data

  # the board after the moves, in order, from g
  law replay:
    for g: Game
    for moves: List<Move>
    Game
  ```

- A law mentions only Base, what `spec.bend` imports, and names of `spec.bend`. If a claim mentions
  `f`, `spec.bend` declares `f` and specifies it (by claims, or by a reference def in `spec.bend`).
- Keep a type opaque (`Data`) unless callers match on it: then its constructors are part of the
  interface. Give each field that a caller reads as a law (`law player_x: for g: Game  Nat`). Give
  each value that a caller makes as a law (`law up: Move`).
- State each property that a caller relies on. Common misses:
  - one step at a time equals all steps at once;
  - the start value;
  - how text is counted (code points, not UTF-16 units);
  - what happens when an expected part is missing.
- Do not fix a detail that no caller relies on.

## impl.bend

- Fill each law with a def of the same name: `def Spec.replay(g, moves): ...`.
- The bend2 rules apply.

## Tests

A test is a yellow flag. It must earn its place. Make the module correct by construction:

1. A type that cannot hold a wrong value.
2. Else, a claim in `spec.bend` that `impl.bend` proves. Prove it by structure (induction, symmetry,
   a lemma), not by a case for each value, so that the proof stays small. A case split is fine only
   when the cases are few (two Bools).
3. Only if neither can state the behavior, a test (its kinds: the bend2 skill, Checks).

A test starts with a comment that says why steps 1 and 2 cannot state the behavior. It ends with the
`#|` lines that its run must print.

## Caller

- If a caller relies on a fact that no law states, add the law or remove the reliance.
- Still trusted, not proven: the caller code itself, speed, and the Bend compiler and runtime.

## Folder structure and shared modules

- Features are onion-like. For each layer(probably in `src` or `features`), there may be a
  `shared.bend` file XOR a `shared` folder if the utility earns it(file grows too large or has
  effects, for example). A `shared` folder, being a feature, may too contain `shared.bend` XOR a
  nested `shared` folder if needed.
- A `shared` module never imports a cousin. When a module that is not a descendant of a helper's
  layer needs the helper, move the helper to the `shared` of the nearest common ancestor layer, not
  higher.
- A module that needs another feature, not one of its helpers, imports that feature's `spec.bend`
  and `impl.bend` (see Layout), never its `shared`. Do not move a feature into a `shared` module to
  get around the rule above.
