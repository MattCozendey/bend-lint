// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindingTexts } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "performance/deep-call-in-fork";

// 2^d, by a call of itself that is not a tail call. Lines 3 to 9.
const DEEP =
  "def pow2(d: Nat) -> U32:\n  match d:\n    case 0n:\n      1\n    case 1n+p:\n      +h = pow2(p)\n      U32.add(h, h)\n";

// 2^d times acc, by a tail call. Lines 3 to 8.
const FLAT =
  "def pow2(d: Nat, +acc: U32) -> U32:\n  match d:\n    case 0n:\n      acc\n    case 1n+p:\n      pow2(p, U32.add(acc, acc))\n";

// Functions
// =========

// A file with `pow2` and a fork over lo .. lo + 2^d - 1, whose leaf is `leaf` and whose step is
// `step`.
const getFile = (pow2: string, step: string, leaf = "lo"): string =>
  `import Base\n\n${pow2}\ndef f(d: Nat, +lo: U32) -> U32:\n  match d:\n    case 0n:\n      ${leaf}\n    case 1n++p:\n${step}\n`;

// Where each finding is, and what it says. The file must pass Bend's check.
const getReports = (text: string): Promise<string[]> => getFindingTexts(RULE, text);

const getPlaces = async (text: string): Promise<string[]> =>
  (await getReports(text)).map((f) => f.split(" ")[0]);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("a call in a fork's value is reported, with what to do", async () => {
    expect(
      await getReports(
        getFile(DEEP, "      a b = f(p, lo) f(p, U32.add(lo, pow2(p)))\n      U32.add(a, b)"),
      ),
    ).toEqual([
      '16:39 performance/deep-call-in-fork: pow2 calls itself outside a tail position, so Bend gives each of its calls a frame, and f calls it in a fork (a value of its parallel let, or of a let just before it). CPU: measured 4% to 8% faster for a raytracer once such a call was tail-recursive, and a 10x speedup cut to 1.9x with such a call at each fork. GPU: a non-tail recursion in a `!` made a draw 2.3x slower ("bend guide shaders"). Confidence: medium. Make pow2 tail-recursive with an accumulator, compute its value with native operations (such as U32.shln), or compute it once and pass it down as a parameter. If its input is short, expect this finding.',
    ]);
  });

  test("a call in a let just before the fork is reported", async () => {
    expect(
      await getPlaces(
        getFile(
          DEEP,
          "      +h = pow2(p)\n      a b = f(p, lo) f(p, U32.add(lo, h))\n      U32.add(a, b)",
        ),
      ),
    ).toEqual(["16:12"]);
  });

  test("a tail-recursive definition passes", async () => {
    expect(
      await getReports(
        getFile(FLAT, "      a b = f(p, lo) f(p, U32.add(lo, pow2(p, 1)))\n      U32.add(a, b)"),
      ),
    ).toEqual([]);
  });

  test("the call in a leaf passes", async () => {
    expect(
      await getReports(
        getFile(
          DEEP,
          "      a b = f(p, lo) f(p, U32.add(lo, U32.shln(1, p)))\n      U32.add(a, b)",
          "U32.add(lo, pow2(5n))",
        ),
      ),
    ).toEqual([]);
  });

  test("the call without a fork passes", async () => {
    expect(
      await getReports(getFile(DEEP, "      U32.add(f(p, lo), f(p, U32.add(lo, pow2(p))))")),
    ).toEqual([]);
  });

  test("a fork tree called in a fork passes: its calls of itself are forks, not frames", async () => {
    expect(
      await getReports(
        getFile(
          "def tree(+d: Nat) -> U32:\n  match d:\n    case 0n:\n      1\n    case 1n+p:\n      a b = tree(p) tree(p)\n      U32.add(a, b)\n",
          "      a b = f(p, lo) f(p, U32.add(lo, tree(p)))\n      U32.add(a, b)",
        ),
      ),
    ).toEqual([]);
  });

  test("a fork's calls of its own definition pass", async () => {
    expect(
      await getReports(
        `import Base\n\ndef f(d: Nat, +lo: U32) -> U32:\n  match d:\n    case 0n:\n      lo\n    case 1n++p:\n      a b = f(p, lo) f(p, U32.add(lo, U32.shln(1, p)))\n      U32.add(a, b)\n`,
      ),
    ).toEqual([]);
  });
});
