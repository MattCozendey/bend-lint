// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindingTexts } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "performance/append-in-loop";

// Functions
// =========

// A loop of `n` steps over an accumulator of type `type`, whose step, on line 8, is `step`.
const getLoop = (type: string, step: string): string =>
  `import Base\n\ndef f(n: Nat, acc: ${type}) -> ${type}:\n  match n:\n    case 0n:\n      acc\n    case 1n+p:\n${step}\n`;

// Where each finding is, and what it says. The file must pass Bend's check.
const getReports = (text: string): Promise<string[]> => getFindingTexts(RULE, text);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("List.append to the accumulator of a loop is reported, with how to build it", async () => {
    expect(
      await getReports(getLoop("List<&2, U32>", "      f(p, List.append(&2, U32, acc, [1]))")),
    ).toEqual([
      "8:12 performance/append-in-loop: List.append copies acc on each call of f, so a loop of n steps copies O(n²) items. Every lane. Confidence: high. Add each item at the head instead, with `item <> acc`, and reverse acc once when the loop ends: `List.reverse(&2, U32, acc)`; to add a list each step, collect the lists, with `piece <> pieces`, and join them once: `List.concat(&2, U32, List.reverse(&2, List<&2, U32>, pieces))`. If the loop runs only a few steps, expect this finding.",
    ]);
  });

  test("++ to the accumulator of a loop is reported, with how to join the pieces", async () => {
    expect(await getReports(getLoop("String", '      f(p, acc ++ "x")'))).toEqual([
      "8:12 performance/append-in-loop: ++ copies acc on each call of f, so a loop of n steps copies O(n²) characters. C lane (CPU and GPU): measured 12.6 s against 0.07 s for 20,000 lines. JS lane: strings join natively, no cost. Confidence: high. Collect the pieces in a list instead, with `piece <> pieces`, and join them once when the loop ends: `String.concat(List.reverse(&2, String, pieces))`. If the loop runs only a few steps, expect this finding.",
    ]);
  });

  test("adding at the accumulator's head passes", async () => {
    expect(await getReports(getLoop("List<&2, U32>", "      f(p, 1 <> acc)"))).toEqual([]);
  });

  test("appending the accumulator to something else passes", async () => {
    expect(
      await getReports(getLoop("List<&2, U32>", "      f(p, List.append(&2, U32, [1], acc))")),
    ).toEqual([]);
  });

  test("an append that the loop does not pass to itself passes", async () => {
    expect(
      await getReports(
        "import Base\n\ndef f(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:\n  match n:\n    case 0n:\n      List.append(&2, U32, acc, [1])\n    case 1n+p:\n      f(p, acc)\n",
      ),
    ).toEqual([]);
  });

  test("a loop that also keeps each value it builds passes: it needs the copies", async () => {
    expect(
      await getReports(
        'import Base\n\ndef f(n: Nat, +acc: String, out: List<&2, String>) -> List<&2, String>:\n  match n:\n    case 0n:\n      out\n    case 1n+p:\n      f(p, acc ++ "x", (acc ++ "x") <> out)\n',
      ),
    ).toEqual([]);
  });

  test("an append in a definition that does not call itself passes", async () => {
    expect(
      await getReports(
        "import Base\n\ndef f(acc: List<&2, U32>) -> List<&2, U32>:\n  List.append(&2, U32, acc, [1])\n",
      ),
    ).toEqual([]);
  });
});
