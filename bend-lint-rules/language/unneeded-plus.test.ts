// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindingTexts } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "language/unneeded-plus";

// Functions
// =========

// Where each finding is, and what it says. The file must pass Bend's check.
const getReports = (text: string): Promise<string[]> => getFindingTexts(RULE, text);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("a + parameter used once is reported, with what to write", async () => {
    expect(
      await getReports("import Base\n\ndef f(+x: Nat, y: Nat) -> Nat:\n  Nat.add(x, y)\n"),
    ).toEqual([
      "3:8 language/unneeded-plus: +x is used at most once on each path, so it needs no `+`. Write x without it. Speed does not change: Bend counts references from the uses, not from the `+`.",
    ]);
  });

  test("a + field and a + let used once are reported", async () => {
    expect(
      (
        await getReports(
          "import Base\n\ndef f(xs: List<&2, Nat>) -> Nat:\n  match xs:\n    case Nil{}:\n      0n\n    case Con{+h, t}:\n      +y = h\n      y\n",
        )
      ).map((f) => f.split(" is used")[0]),
    ).toEqual(["7:14 language/unneeded-plus: +h", "8:7 language/unneeded-plus: +y"]);
  });

  test("+ binders used twice, and matched ones, pass", async () => {
    expect(
      await getReports(
        "import Base\n\ndef f(+x: Nat) -> Nat:\n  Nat.add(x, x)\n\ndef g(+n: Nat) -> Nat:\n  match n:\n    case 0n:\n      0n\n    case 1n+p:\n      Nat.add(p, p)\n",
      ),
    ).toEqual([]);
  });
});
