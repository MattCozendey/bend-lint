// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindingTexts } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "performance/drop-in-bang";

// A definition that frees a list, on lines 3 to 8.
const FREE =
  "def free(xs: List<&2, U32>) -> Unit:\n  match xs:\n    case Nil{}:\n      Unit{}\n    case Con{x, rest}:\n      free(rest)\n";

// Functions
// =========

// Where each finding is, and what it says. The file must pass Bend's check.
const getReports = (text: string): Promise<string[]> => getFindingTexts(RULE, text);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("Image.drop with ! is reported, with what to do", async () => {
    expect(
      await getReports("import Base\n\ndef main(img: Image) -> Unit:\n  Image.drop!(img)\n"),
    ).toEqual([
      '4:3 performance/drop-in-bang: Image.drop! only frees what it receives, as it returns Unit, and a GPU frees slower than its CPU. Discrete GPU (CUDA): measured 15x slower than without the `!` (dropping a 1M-leaf image, RTX 4050 laptop). Unified memory (Apple M-series): freeing a scene in a bang made a frame 12.9 ms against 8.0 ms ("bend guide shaders"). CPU (`--gpu off`): 10% slower. Confidence: high. Remove the `!`; to drop the last frame, let the next frame\'s fork tree drop it, a quadrant per tile ("bend guide shaders").',
    ]);
  });

  test("a ! call of a definition of the program that returns Unit is reported", async () => {
    expect(
      (
        await getReports(
          "import Base\n\n" + FREE + "\ndef main(xs: List<&2, U32>) -> Unit:\n  free!(xs)\n",
        )
      ).map((f) => f.split(" only")[0]),
    ).toEqual(["11:3 performance/drop-in-bang: free!"]);
  });

  test("a drop without !, and a ! call that returns a value, pass", async () => {
    expect(
      await getReports(
        "import Base\n\n" +
          FREE +
          "\ndef main(img: Image, xs: List<&2, U32>) -> Unit:\n  Image.drop(img)\n\ndef id(n: U32) -> U32:\n  n\n\ndef g(n: U32) -> U32:\n  id!(n)\n",
      ),
    ).toEqual([]);
  });
});
