// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, BUILDS, lint } from "../../linter/testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when bend does not run.
const PROGRAM = BUILDS
  ? await build("bend-lint-default-rules/performance/append-in-loop.bend")
  : "";

// Functions
// =========

// A loop of `n` steps over an accumulator of type `type`, whose step, on line 8, is `step`.
const loop = (type: string, step: string): string =>
  `import Base\n\ndef f(n: Nat, acc: ${type}) -> ${type}:\n  match n:\n    case 0n:\n      acc\n    case 1n+p:\n${step}\n`;

// Where each finding is, and what it says. The file must pass Bend's check.
const found = async (text: string): Promise<string[]> =>
  (await lint(PROGRAM, { "main.bend": text }, "main.bend")).map(
    ({ at, code, message }) => `${at} ${code}: ${message}`,
  );

// Side effects
// ============

setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)("performance/append-in-loop", () => {
  test("List.append to the accumulator of a loop is reported, with how to build it", async () => {
    expect(
      await found(loop("List<&2, U32>", "      f(p, List.append(&2, U32, acc, [1]))")),
    ).toEqual([
      "8:12 performance/append-in-loop: List.append copies acc on each call of f, so a loop of n steps copies O(n²) items. Add each item at the head instead, with `item <> acc`, and reverse acc once when the loop ends: `List.reverse(&2, U32, acc)`.",
    ]);
  });

  test("++ to the accumulator of a loop is reported, with how to join the pieces", async () => {
    expect(await found(loop("String", '      f(p, acc ++ "x")'))).toEqual([
      "8:12 performance/append-in-loop: On the C lane, ++ copies acc on each call of f, so a loop of n steps copies O(n²) characters (the JS lane joins strings natively). Collect the pieces in a list instead, with `piece <> pieces`, and join them once when the loop ends: `String.concat(List.reverse(&2, String, pieces))`.",
    ]);
  });

  test("adding at the accumulator's head passes", async () => {
    expect(await found(loop("List<&2, U32>", "      f(p, 1 <> acc)"))).toEqual([]);
  });

  test("appending the accumulator to something else passes", async () => {
    expect(
      await found(loop("List<&2, U32>", "      f(p, List.append(&2, U32, [1], acc))")),
    ).toEqual([]);
  });

  test("an append that the loop does not pass to itself passes", async () => {
    expect(
      await found(
        "import Base\n\ndef f(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:\n  match n:\n    case 0n:\n      List.append(&2, U32, acc, [1])\n    case 1n+p:\n      f(p, acc)\n",
      ),
    ).toEqual([]);
  });

  test("a loop that also keeps each value it builds passes: it needs the copies", async () => {
    expect(
      await found(
        'import Base\n\ndef f(n: Nat, +acc: String, out: List<&2, String>) -> List<&2, String>:\n  match n:\n    case 0n:\n      out\n    case 1n+p:\n      f(p, acc ++ "x", (acc ++ "x") <> out)\n',
      ),
    ).toEqual([]);
  });

  test("an append in a definition that does not call itself passes", async () => {
    expect(
      await found(
        "import Base\n\ndef f(acc: List<&2, U32>) -> List<&2, U32>:\n  List.append(&2, U32, acc, [1])\n",
      ),
    ).toEqual([]);
  });
});
