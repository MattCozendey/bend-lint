// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindings, getFindingTexts } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "language/reused-binder";

// Functions
// =========

// Where each finding of the rule is, and what it says. Bend's check fails on these files too.
const getReports = async (text: string): Promise<string[]> =>
  (await getFindings(RULE, { "main.bend": text }, "main.bend"))
    .filter(({ code }) => code === RULE)
    .map(({ at, message }) => `${at} ${message}`);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("a parameter used twice on one path is reported at its second use", async () => {
    expect(
      await getReports(
        "import Base\n\ndef f(c: Bool, x: Nat) -> Nat:\n  Bool.pick(Nat, c, x, x)\n",
      ),
    ).toEqual([
      '4:24 x is used again here, on the same path as an earlier use, but it is declared without `+`, so it can be used once on each path, and the check fails ("consumed more than once"). If its type is Data, write `+x` where it is declared (it then carries a reference count at run time); else use it once: a function, an array or an IO handle can never be copied. This is a false positive if one of the uses is an argument for an erased parameter (`-x`, as a proof\'s motive often is): that is dead code.',
    ]);
  });

  test("a let's name used twice is reported", async () => {
    expect(
      (await getReports("import Base\n\ndef f(x: Nat) -> Nat:\n  y = x\n  Nat.add(y, y)\n")).map(
        (f) => f.split(" is used")[0],
      ),
    ).toEqual(["5:14 y"]);
  });

  test("+ binders, uses in different cases, matched binders and uses in types pass", async () => {
    expect(
      await getFindingTexts(
        RULE,
        "import Base\n\ndef f(c: Bool, +x: Nat) -> Nat:\n  Bool.pick(Nat, c, x, x)\n\ndef g(c: Bool, x: Nat, y: Nat) -> Nat:\n  match c:\n    case True{}:\n      Nat.add(x, y)\n    case False{}:\n      x\n\ndef k(x: Nat) -> Nat:\n  match x:\n    case 0n:\n      Nat.add(x, x)\n    case 1n+p:\n      p\n\ndef t(x: Nat) -> Nat:\n  ({x : Nat} : Nat)\n",
      ),
    ).toEqual([]);
  });
});
