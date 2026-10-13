// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, BUILDS, lint } from "../../src/linter/testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when bend does not run.
const PROGRAM = BUILDS ? await build("performance/gpu-fit") : "";

// A tree, a record of numbers, a walk of the tree, and a fork over numbers; the definitions that
// follow start on line 26.
const START =
  "import Base\n\ntype T is Data:\n  Leaf{v: U32}\n  Node{l: T, r: T}\n\ntype P is Data:\n  P{x: F32, y: F32}\n\ndef walk(t: T) -> U32:\n  match t:\n    case Leaf{v}:\n      v\n    case Node{l, r}:\n      a b = walk(l) walk(r)\n      (a + b : U32)\n\ndef grow(d: Nat, +s: U32, p: P) -> U32:\n  match d:\n    case 0n:\n      s\n    case 1n++e:\n      a b = grow(e, (s * 2 : U32), P{1.0, 2.0}) grow(e, (s * 2 + 1 : U32), P{1.0, 2.0})\n      (a + b : U32)\n\n";

// Functions
// =========

// Where each finding is, and what it says. The file must pass Bend's check.
const found = async (defs: string): Promise<string[]> =>
  (await lint(PROGRAM, { "main.bend": START + defs }, "main.bend")).map(
    ({ at, severity, code, message }) => `${at} ${severity} ${code}: ${message}`,
  );

// Side effects
// ============

setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)("performance/gpu-fit", () => {
  test("a ! call that receives data is reported as maybe slower on the GPU", async () => {
    expect(await found("def main(t: T) -> U32:\n  walk!(t)\n")).toEqual([
      "27:3 information performance/gpu-fit: walk! runs on the GPU, if there is one, and receives data (t: T), not only numbers. A GPU is fast on uniform numeric work but slow at walking data, and a discrete GPU (CUDA) also pays for each page of that data it reads from the CPU's memory. Measured against `--gpu off` on an RTX 4050 laptop GPU: the draw of Bend's slash boss demo took 30% longer on the GPU, its parallel sort 4.6x longer, a tree walk 2.7x longer. Time the program with and without `--gpu off` (or this call without its `!`), and keep the faster. On unified memory (Apple M-series), the GPU can still win.",
    ]);
  });

  test("a fork over numbers called without ! is a hint that it may be faster on the GPU", async () => {
    expect(
      (await found("def main() -> U32:\n  grow(10n, 1, P{0.0, 0.0})\n")).map(
        (f) => f.split(", so")[0],
      ),
    ).toEqual(["27:3 hint performance/gpu-fit: grow forks over numbers only"]);
  });

  test("a ! call over numbers, and a call of a fork from a fork, pass", async () => {
    expect(
      await found(
        "def main() -> U32:\n  grow!(10n, 1, P{0.0, 0.0})\n\ndef twice(d: Nat) -> U32:\n  match d:\n    case 0n:\n      grow(3n, 1, P{0.0, 0.0})\n    case 1n++e:\n      a b = twice(e) twice(e)\n      (a + b : U32)\n",
      ),
    ).toEqual([]);
  });
});
