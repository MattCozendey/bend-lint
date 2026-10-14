// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindingTexts } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "performance/dead_accumulator";

// A loop over a list with a second list `done`, whose base case is `base` and whose step is `step`; its
// parameters are on line 3.
const getLoop = (name: string, done: string, base: string, step: string): string =>
  `import Base\n\ndef ${name}(todo: List<&2, U32>, ${done}: List<&2, U32>) -> ${base.startsWith("done") ? "List<&2, U32>" : "Nat"}:\n  match todo:\n    case Nil{}:\n      ${base}\n    case Con{h, t}:\n      ${step}\n`;

// Functions
// =========

// Where each finding is, and its first words. The file must pass Bend's check.
const getPlaces = async (text: string): Promise<string[]> =>
  (await getFindingTexts(RULE, text)).map((f) => f.split(" passes it")[0]);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("a parameter that only grows and is never read is reported, with what to do", async () => {
    expect(await getFindingTexts(RULE, getLoop("f", "done", "0n", "f(t, h <> done)"))).toEqual([
      "3:28 performance/dead_accumulator: done only grows: f passes it to itself with something added, and nothing reads it, so Bend builds it on every step and frees it at the end. All lanes. Measured on the CPU, in bend-ml's BPE encode, where such a list, built per word, was half of the time: 26.1 s to tokenize 19 KB of text, against 11.5 s after the fix. Confidence: medium, as the gain is what building it costs. Erase it, with `-done`: the checker keeps it for proofs, and the compiler deletes it; or remove it. If it gets only a few small items, expect this finding.",
    ]);
  });

  test("a parameter that is returned, read, passed unchanged, or erased passes", async () => {
    expect(
      await getPlaces(
        getLoop("g", "done", "done", "g(t, h <> done)") +
          "\ndef m(todo: List<&2, U32>, +done: List<&2, U32>) -> Nat:\n  match todo:\n    case Nil{}:\n      0n\n    case Con{h, t}:\n      Nat.add(List.length(&2, U32, done), m(t, h <> done))\n" +
          "\ndef p(todo: List<&2, U32>, done: List<&2, U32>) -> Nat:\n  match todo:\n    case Nil{}:\n      0n\n    case Con{h, t}:\n      p(t, done)\n" +
          "\ndef e(todo: List<&2, U32>, -done: List<&2, U32>) -> Nat:\n  match todo:\n    case Nil{}:\n      0n\n    case Con{h, t}:\n      e(t, h <> done)\n",
      ),
    ).toEqual([]);
  });
});
