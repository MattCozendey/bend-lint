// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindingTexts } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "performance/unused-result";

// A list builder, and a function that hands a list and a number to a continuation; the definitions
// that follow start on line 13.
const START =
  "import Base\n\ndef build(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:\n  match n:\n    case 0n:\n      acc\n    case 1n+m:\n      build(m, 1 <> acc)\n\ndef then(-R: Type, xs: List<&2, U32>, k: List<&2, U32> -> U32 -> R) -> R:\n  k(xs, 7)\n\n";

// A loop over n, written under `case 1n+m:` as `step` (on line 18).
const getLoop = (name: string, step: string, returns = "U32"): string =>
  `def ${name}(n: Nat, +acc: U32) -> ${returns}:\n  match n:\n    case 0n:\n      acc\n    case 1n+m:\n${step}\n`;

// Functions
// =========

// Where each finding is, and its first words. The file must pass Bend's check.
const getPlaces = async (defs: string): Promise<string[]> =>
  (await getFindingTexts(RULE, START + defs)).map((f) => f.split(", but")[0]);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("a list that a loop's continuation never uses is reported, with what to do", async () => {
    expect(
      await getFindingTexts(
        RULE,
        START + getLoop("f", "      then(U32, build(3n, []), xs => k => f(m, (acc + k : U32)))"),
      ),
    ).toEqual([
      "18:32 performance/unused-result: xs is never used, but Bend computes every value it binds: xs is built, then walked to be freed, on every step of f. All lanes. Measured on the CPU, in llama.bend: not building the activations that its generation loop never used made each token 19% to 25% faster. Confidence: medium, as the cost grows with the value. Have the code that makes xs skip it, such as a variant that does not build it. If it is small, expect this finding.",
    ]);
  });

  test("a let that a loop never uses is reported", async () => {
    expect(await getPlaces(getLoop("g", "      xs = build(3n, [])\n      g(m, acc)"))).toEqual([
      "18:7 performance/unused-result: xs is never used",
    ]);
  });

  test("an unused number, a value outside a loop, and an IO step's result, pass", async () => {
    expect(
      await getPlaces(
        getLoop(
          "h",
          "      then(U32, build(3n, []), xs => k => h(m, (acc + U32.from_nat(List.length(&2, U32, xs)) : U32)))",
        ) +
          "\ndef once() -> U32:\n  then(U32, build(3n, []), xs => k => k)\n\n" +
          'def io(n: Nat) -> IO(Unit):\n  match n:\n    case 0n:\n      IO.print("done")\n    case 1n+m:\n      do IO<Unit>:\n        args : List<String> <- IO.args()\n        io(m)\n',
      ),
    ).toEqual([]);
  });
});
