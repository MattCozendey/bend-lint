// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindingTexts } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "performance/repeated-call";

// A loop that returns a number, and one that returns data; the definitions that follow start on
// line 17.
const START =
  "import Base\n\ndef count(xs: List<&2, U32>, +n: Nat) -> Nat:\n  match xs:\n    case Nil{}:\n      n\n    case Con{x, t}:\n      count(t, 1n+n)\n\ndef copy(xs: List<&2, U32>) -> List<&2, U32>:\n  match xs:\n    case Nil{}:\n      Nil{}\n    case Con{x, t}:\n      x <> copy(t)\n\n";

// Functions
// =========

// Where each finding is, and its first words. The file must pass Bend's check.
const getPlaces = async (defs: string): Promise<string[]> =>
  (await getFindingTexts(RULE, START + defs)).map((f) => f.split(" is called")[0]);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("a call made again with the same arguments is reported, with what to do", async () => {
    expect(
      await getFindingTexts(
        RULE,
        START + "def f(+xs: List<&2, U32>) -> Nat:\n  Nat.add(count(xs, 0n), count(xs, 0n))\n",
      ),
    ).toEqual([
      "18:26 performance/repeated-call: count is called again here, with the same arguments, on this path of f: Bend computes it twice, as clang does not merge calls of a definition that loops. Every lane: pow2(30) written `Nat.add(pow2(q), pow2(q))` took 3.4 s; computed once (`+h = pow2(q)`), 0.1 s. Confidence: high that it repeats; the gain is what the call costs. Bind its value once, with `+` if it is used twice, and use that name.",
    ]);
  });

  test("a call repeated in a later let of the same branch is reported", async () => {
    expect(
      await getPlaces(
        "def f(+xs: List<&2, U32>) -> Nat:\n  +a = count(xs, 0n)\n  +b = count(xs, 0n)\n  Nat.add(a, b)\n",
      ),
    ).toEqual(["19:8 performance/repeated-call: count"]);
  });

  test("other arguments, other branches, a parallel let, data, and choices pass", async () => {
    expect(
      await getPlaces(
        "def f(+xs: List<&2, U32>) -> Nat:\n  Nat.add(count(xs, 0n), count(xs, 1n))\n\n" +
          "def g(+xs: List<&2, U32>, b: Bool) -> Nat:\n  match b:\n    case True{}:\n      count(xs, 0n)\n    case False{}:\n      count(xs, 0n)\n\n" +
          "def h(+xs: List<&2, U32>) -> Nat:\n  a b = count(xs, 0n) count(xs, 0n)\n  Nat.add(a, b)\n\n" +
          "def k(+xs: List<&2, U32>) -> List<&2, U32>:\n  List.append(&2, U32, copy(xs), copy(xs))\n\n" +
          "def m(+xs: List<&2, U32>, b: Bool) -> Nat:\n  Bool.pick(Nat, b, count(xs, 0n), count(xs, 0n))\n",
      ),
    ).toEqual([]);
  });
});
