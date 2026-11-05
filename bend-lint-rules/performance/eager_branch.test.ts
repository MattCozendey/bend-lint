// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindingTexts } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "performance/eager_branch";

// Functions
// =========

// Where each finding is, and what it says. The file must pass Bend's check.
const getReports = (text: string): Promise<string[]> => getFindingTexts(RULE, text);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("a loop's own call is reported as walking to its end", async () => {
    expect(
      (
        await getReports(
          "import Base\n\ndef has(xs: List<&2, U32>, +x: U32) -> Bool:\n  match xs:\n    case Nil{}:\n      False{}\n    case Con{h, t}:\n      U32.is_eq(h, x) || has(t, x)\n",
        )
      ).map((f) => f.split(". CPU and GPU")[0]),
    ).toEqual([
      "8:26 performance/eager_branch: || computes its right side even when its left side decides the result (True), so this call of has runs even then: it is the loop's own call, so the loop walks to its end instead of stopping where the condition decides",
    ]);
  });
});
