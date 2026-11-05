// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindingTexts } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "performance/list_index_loop";

// A file's start: Base, and `or_zero`, which reads a Maybe. The defs that follow start on line 10.
const START =
  "import Base\n\ndef or_zero(m: Maybe<&2, U32>) -> U32:\n  match m:\n    case None{}:\n      0\n    case Some{x}:\n      x\n\n";

// Functions
// =========

// A loop of `n` steps over `xs`, whose step is `step`.
const getLoop = (step: string): string =>
  `${START}def f(n: Nat, +xs: List<&2, U32>, +i: Nat, acc: U32) -> U32:\n  match n:\n    case 0n:\n      acc\n    case 1n+p:\n${step}\n`;

// Where each finding is, and what it says. The file must pass Bend's check.
const getReports = (text: string): Promise<string[]> => getFindingTexts(RULE, text);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("List.get on a list the loop passes unchanged is reported, with how to walk it", async () => {
    expect(
      await getReports(
        getLoop("      f(p, xs, Nat.add(i, 1n), U32.add(acc, or_zero(List.get(&2, U32, xs, i))))"),
      ),
    ).toEqual([
      "15:53 performance/list_index_loop: List.get walks xs from its head, and f passes xs unchanged to each call of itself, so a loop that visits each of its n items takes O(n²) time. All lanes. Confidence: high, as each step walks the list again. Walk xs instead: match it, use its head, and pass its tail to the next call. If the list stays short, expect this finding.",
    ]);
  });

  test("List.length in such a loop asks to compute it once", async () => {
    expect(
      await getReports(
        getLoop("      f(p, xs, i, U32.add(acc, U32.from_nat(List.length(&2, U32, xs))))"),
      ),
    ).toEqual([
      "15:45 performance/list_index_loop: List.length walks xs from its head, and f passes xs unchanged to each call of itself, so a loop that visits each of its n items takes O(n²) time. All lanes. Confidence: high, as each step walks the list again. Compute the length once before the loop, and pass it as a parameter. If the list stays short, expect this finding.",
    ]);
  });
});
