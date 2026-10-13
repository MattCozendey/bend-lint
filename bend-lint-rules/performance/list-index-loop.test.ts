// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, BUILDS, lint } from "../../src/linter/testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when bend does not run.
const PROGRAM = BUILDS ? await build("performance/list-index-loop") : "";

// A file's start: Base, and `or_zero`, which reads a Maybe. The defs that follow start on line 10.
const START =
  "import Base\n\ndef or_zero(m: Maybe<&2, U32>) -> U32:\n  match m:\n    case None{}:\n      0\n    case Some{x}:\n      x\n\n";

// A helper that gives its list to List.get.
const AT = "def at(xs: List<&2, U32>, i: Nat) -> U32:\n  or_zero(List.get(&2, U32, xs, i))\n\n";

// Functions
// =========

// A loop of `n` steps over `xs`, whose step, after `defs`, is `step`.
const loop = (step: string, defs = ""): string =>
  `${START}${defs}def f(n: Nat, +xs: List<&2, U32>, +i: Nat, acc: U32) -> U32:\n  match n:\n    case 0n:\n      acc\n    case 1n+p:\n${step}\n`;

// Where each finding is, and what it says. The file must pass Bend's check.
const found = async (text: string): Promise<string[]> =>
  (await lint(PROGRAM, { "main.bend": text }, "main.bend")).map(
    ({ at, code, message }) => `${at} ${code}: ${message}`,
  );

// Side effects
// ============

setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)("performance/list-index-loop", () => {
  test("List.get on a list the loop passes unchanged is reported, with how to walk it", async () => {
    expect(
      await found(
        loop("      f(p, xs, Nat.add(i, 1n), U32.add(acc, or_zero(List.get(&2, U32, xs, i))))"),
      ),
    ).toEqual([
      "15:53 performance/list-index-loop: List.get walks xs from its head, and f passes xs unchanged to each call of itself, so a loop that visits each of its n items takes O(n²) time. Walk xs instead: match it, use its head, and pass its tail to the next call.",
    ]);
  });

  test("List.length in such a loop asks to compute it once", async () => {
    expect(
      await found(loop("      f(p, xs, i, U32.add(acc, U32.from_nat(List.length(&2, U32, xs))))")),
    ).toEqual([
      "15:45 performance/list-index-loop: List.length walks xs from its head, and f passes xs unchanged to each call of itself, so a loop that visits each of its n items takes O(n²) time. Compute the length once before the loop, and pass it as a parameter.",
    ]);
  });

  test("a helper that gives the list to List.get is reported where the loop calls it", async () => {
    expect(
      await found(loop("      f(p, xs, Nat.add(i, 1n), U32.add(acc, at(xs, i)))", AT)),
    ).toEqual([
      "18:45 performance/list-index-loop: at walks xs from its head (through List.get), and f passes xs unchanged to each call of itself, so a loop that visits each of its n items takes O(n²) time. Walk xs instead: match it, use its head, and pass its tail to the next call.",
    ]);
  });

  test("a read in a branch that does not loop passes", async () => {
    expect(
      await found(
        `${START}def f(n: Nat, +xs: List<&2, U32>, acc: U32) -> U32:\n  match n:\n    case 0n:\n      U32.add(acc, U32.from_nat(List.length(&2, U32, xs)))\n    case 1n+p:\n      f(p, xs, U32.add(acc, 1))\n`,
      ),
    ).toEqual([]);
  });

  test("a helper called outside a loop passes", async () => {
    expect(await found(`${START}${AT}def f(xs: List<&2, U32>) -> U32:\n  at(xs, 3n)\n`)).toEqual(
      [],
    );
  });

  test("a loop that passes the list's rest passes", async () => {
    expect(
      await found(
        loop(
          "      f(p, List.drop(&2, U32, xs, 1n), i, U32.add(acc, or_zero(List.get(&2, U32, xs, 0n))))",
        ),
      ),
    ).toEqual([]);
  });

  test("a loop that walks the list passes", async () => {
    expect(
      await found(
        `${START}def f(xs: List<&2, U32>, acc: U32) -> U32:\n  match xs:\n    case Nil{}:\n      acc\n    case h <> t:\n      f(t, U32.add(acc, h))\n`,
      ),
    ).toEqual([]);
  });

  test("a list that is not a parameter passes", async () => {
    expect(
      await found(
        `${START}def f(n: Nat, acc: U32) -> U32:\n  match n:\n    case 0n:\n      acc\n    case 1n++p:\n      f(p, U32.add(acc, or_zero(List.get(&2, U32, [1, 2, 3], p))))\n`,
      ),
    ).toEqual([]);
  });
});
