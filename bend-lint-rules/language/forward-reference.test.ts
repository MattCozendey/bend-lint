// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindings, getFindingTexts } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "language/forward-reference";

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
  test("a use of a definition below is reported, with what to do", async () => {
    expect(
      await getReports(
        "import Base\n\ndef main() -> Nat:\n  later()\n\ndef later() -> Nat:\n  1n\n",
      ),
    ).toEqual([
      '4:3 later is defined below main, and Bend checks definitions in file order: live code can use only what is defined above it, so this use fails the check ("a filled definition"). Move later above main. If the two call each other, merge them into one definition with an argument that selects which to run: Bend does not allow mutual recursion. This is a false positive if the use is an argument for an erased parameter (`-x`): that is dead code.',
    ]);
  });

  test("uses of definitions above, and from @unsafe definitions, pass", async () => {
    expect(
      await getFindingTexts(
        RULE,
        "import Base\n\ndef earlier() -> Nat:\n  1n\n\ndef main() -> Nat:\n  earlier()\n\n@unsafe\ndef u() -> Nat:\n  later()\n\ndef v?() -> Nat:\n  later()\n\ndef later() -> Nat:\n  1n\n",
      ),
    ).toEqual([]);
  });
});
