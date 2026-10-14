// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindingTexts } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "performance/loop_invariant_call";

// A definition that loops over a list, and one that does not; the definitions that follow start on
// line 13.
const START =
  "import Base\n\ndef count(xs: List<&2, U32>, +n: Nat) -> Nat:\n  match xs:\n    case Nil{}:\n      n\n    case Con{x, t}:\n      count(t, 1n+n)\n\ndef twice(+n: Nat) -> Nat:\n  Nat.add(n, n)\n\n";

// A loop over k with a fixed list xs, whose base case is `base` and whose step is `step` (line 18).
const getLoop = (name: string, step: string, base = "acc"): string =>
  `def ${name}(k: Nat, +xs: List<&2, U32>, +acc: Nat) -> Nat:\n  match k:\n    case 0n:\n      ${base}\n    case 1n+p:\n${step}\n`;

// Functions
// =========

// Where each finding is, and its first words. The file must pass Bend's check.
const getPlaces = async (defs: string): Promise<string[]> =>
  (await getFindingTexts(RULE, START + defs)).map((f) => f.split(" gets")[0]);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("a call of a loop with the same arguments on every step is reported, with what to do", async () => {
    expect(
      await getFindingTexts(
        RULE,
        START + getLoop("f", "      f(p, xs, Nat.add(acc, count(xs, 0n)))"),
      ),
    ).toEqual([
      "18:29 performance/loop_invariant_call: count gets the same arguments on every step of f, so it computes the same value each time: clang hoists plain arithmetic out of a loop, but not a call of a definition that loops. All lanes. Confidence: medium, as the gain is what the call costs. Compute it once before the loop, and pass it as a parameter. If the call is cheap, or the loop repeats it on purpose (a benchmark), expect this finding.",
    ]);
  });

  test("an argument that changes, a call in the base case, a callee that does not loop, and a proof, pass", async () => {
    expect(
      await getPlaces(
        getLoop("f", "      f(p, xs, count(xs, acc))") +
          "\n" +
          getLoop("g", "      g(p, xs, twice(acc))", "count(xs, 0n)") +
          "\n" +
          getLoop("h", "      h(p, xs, Nat.add(acc, twice(3n)))") +
          "\ndef proof(k: Nat, +xs: List<&2, U32>) -> {count(xs, 0n) == count(xs, 0n) : Nat}:\n  match k:\n    case 0n:\n      {==}\n    case 1n+p:\n      _ = count(xs, 0n)\n      proof(p, xs)\n",
      ),
    ).toEqual([]);
  });
});
