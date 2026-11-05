// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindingTexts } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "performance/missed_fork";

// What each finding says after what it found: what a fork costs, on each lane.
const COSTS =
  "Bend runs calls in parallel only as the values of a parallel let. CPU, and GPU under a `!`: measured 2.5x faster for a few calls over a 1M-leaf tree, but 3.9x slower for 100,000 calls over 1k-leaf trees, and 230x slower for a small tree walked once per data point. JS: one thread, so no gain. Confidence: low, as it depends on how much work each call does.";

// What each finding says last: when to expect it.
const EXPECTED =
  " If this definition runs once per item of a loop, or below a fork that already fills the cores, expect this finding.";

// Functions
// =========

// A definition of depth `d`, with a number `i`, whose step is `step`, written under `case 1n++p:`.
const getDef = (name: string, step: string): string =>
  `def ${name}(d: Nat, +i: U32) -> U32:\n  match d:\n    case 0n:\n      1\n    case 1n++p:\n${step}\n`;

// A file whose first definition starts on line 7, so its step is on line 12.
const getFile = (...defs: string[]): string =>
  "import Base\n\ntype T is Data:\n  Leaf{}\n  Node{l: T, r: T}\n\n" + defs.join("\n");

// Where each finding is, and what it says. The file must pass Bend's check.
const getReports = (text: string): Promise<string[]> => getFindingTexts(RULE, text);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("two calls in one call's arguments are reported, with the parallel let to write", async () => {
    expect(
      await getReports(getFile(getDef("f", "      U32.add(f(p, i), f(p, U32.inc(i)))"))),
    ).toEqual([
      "12:7 performance/missed_fork: f calls itself 2 times in this expression (`f(p, i)`, `f(p, U32.inc(i))`), and these calls run one after the other. " +
        COSTS +
        " To run them in parallel, bind them first with one parallel let of fresh names, such as `a b = f(p, i) f(p, U32.inc(i))`, and use those names here." +
        EXPECTED,
    ]);
  });

  test("lets that follow each other are reported, with the parallel let to write", async () => {
    expect(
      await getReports(
        getFile(
          getDef("f", "      +l = f(p, i)\n      r = f(p, U32.inc(i))\n      (l + r + l : U32)"),
        ),
      ),
    ).toEqual([
      "12:7 performance/missed_fork: f calls itself in 2 lets that follow each other (`+l = f(p, i)`, `r = f(p, U32.inc(i))`), and these calls run one after the other. " +
        COSTS +
        " To run them in parallel, merge the lets into one: `+l r = f(p, i) f(p, U32.inc(i))`." +
        EXPECTED,
    ]);
  });
});
