// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindingTexts } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "performance/eager-branch";

// A loop over n that calls itself outside a tail position, on lines 3 to 8.
const DEEP =
  "def deep(n: Nat) -> U32:\n  match n:\n    case 0n:\n      0\n    case 1n+p:\n      (deep(p) + 1 : U32)\n";

// A loop whose call of itself is a tail call.
const SPIN =
  "def spin(n: Nat, acc: U32) -> U32:\n  match n:\n    case 0n:\n      acc\n    case 1n+p:\n      spin(p, (acc + 1 : U32))\n";

// What each finding says after its first sentence: why it matters and what to do.
const ADVICE =
  ". C lane (CPU and GPU): measured 5x slower than a match, for an unused call that calls itself outside a tail position. JS lane: the same. Confidence: high. Choose with a match: pass the condition to a helper whose match runs only the needed value; inside a loop, where that helper would call the loop back (Bend refuses mutual recursion), pass the condition to the next call, and match on it there.";

// Functions
// =========

// A file with `deep` and then `defs`, which start on line 10.
const getFile = (defs: string): string => "import Base\n\n" + DEEP + "\n" + defs;

// Where each finding is, and what it says. The file must pass Bend's check.
const getReports = (text: string): Promise<string[]> => getFindingTexts(RULE, text);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("a value of Bool.pick that calls a deep loop is reported, with what to do", async () => {
    expect(
      await getReports(getFile("def f(c: Bool) -> U32:\n  Bool.pick(U32, c, 7, deep(9n))\n")),
    ).toEqual([
      "11:24 performance/eager-branch: Bool.pick computes both of its values before it picks one, so this call of deep runs even when the condition picks the other value" +
        ADVICE +
        " If deep runs only a few steps here, expect this finding.",
    ]);
  });

  test("the right side of && that calls a deep loop is reported", async () => {
    expect(
      (await getReports(getFile("def f(c: Bool) -> Bool:\n  c && U32.is_eq(deep(9n), 9)\n"))).map(
        (f) => f.split(", so")[0],
      ),
    ).toEqual([
      "11:8 performance/eager-branch: && computes its right side even when its left side decides the result (False)",
    ]);
  });

  test("a loop's own call is reported as walking to its end", async () => {
    expect(
      (
        await getReports(
          "import Base\n\ndef has(xs: List<&2, U32>, +x: U32) -> Bool:\n  match xs:\n    case Nil{}:\n      False{}\n    case Con{h, t}:\n      U32.is_eq(h, x) || has(t, x)\n",
        )
      ).map((f) => f.split(". C lane")[0]),
    ).toEqual([
      "8:26 performance/eager-branch: || computes its right side even when its left side decides the result (True), so this call of has runs even then: it is the loop's own call, so the loop walks to its end instead of stopping where the condition decides",
    ]);
  });

  test("tail loops, calls that do not loop, calls in a lambda or a type, and a match pass", async () => {
    expect(
      await getReports(
        getFile(
          SPIN +
            "\ndef one() -> U32:\n  1\n\ndef e(c: Bool) -> U32:\n  Bool.pick(U32, c, 7, spin(9n, 0))\n\ndef f(c: Bool) -> U32:\n  Bool.pick(U32, c, 7, one())\n\ndef g(c: Bool) -> U32 -> U32:\n  Bool.pick(U32 -> U32, c, x => x, x => deep(9n))\n\ndef h(c: Bool) -> U32:\n  match c:\n    case True{}:\n      7\n    case False{}:\n      deep(9n)\n\ndef k(c: Bool) -> {Bool.pick(U32, c, 7, deep(9n)) == Bool.pick(U32, c, 7, deep(9n)) : U32}:\n  {==}\n",
        ),
      ),
    ).toEqual([]);
  });
});
