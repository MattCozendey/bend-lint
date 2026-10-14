// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindings } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "performance/gpu-fit";

// A tree, a record of numbers, a walk of the tree, and a fork over numbers; the definitions that
// follow start on line 26.
const START =
  "import Base\n\ntype T is Data:\n  Leaf{v: U32}\n  Node{l: T, r: T}\n\ntype P is Data:\n  P{x: F32, y: F32}\n\ndef walk(t: T) -> U32:\n  match t:\n    case Leaf{v}:\n      v\n    case Node{l, r}:\n      a b = walk(l) walk(r)\n      (a + b : U32)\n\ndef grow(d: Nat, +s: U32, p: P) -> U32:\n  match d:\n    case 0n:\n      s\n    case 1n++e:\n      a b = grow(e, (s * 2 : U32), P{1.0, 2.0}) grow(e, (s * 2 + 1 : U32), P{1.0, 2.0})\n      (a + b : U32)\n\n";

// Functions
// =========

// Where each finding is, and what it says. The file must pass Bend's check.
const getReports = async (defs: string): Promise<string[]> =>
  (await getFindings(RULE, { "main.bend": START + defs }, "main.bend")).map(
    ({ at, severity, code, message }) => `${at} ${severity} ${code}: ${message}`,
  );

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("a ! call of a definition that forks and receives data is maybe slower on a discrete GPU", async () => {
    expect(await getReports("def main(t: T) -> U32:\n  walk!(t)\n")).toEqual([
      "27:3 information performance/gpu-fit: walk! receives data (t: T), which a discrete GPU reads across PCIe, page by page. Discrete GPU (CUDA): slower than `--gpu off` for Bend's slash boss draw on an RTX 4050 laptop (1.4x), and for portal-bend on an RTX 4060 desktop. Unified memory (Apple M-series): the GPU wins that draw. Confidence: medium, as it depends on the machine. Time the program with and without `--gpu off`; where the GPU wins, expect this finding.",
    ]);
  });

  test("a ! call of a definition under which no parallel let runs is a warning", async () => {
    expect(
      await getReports(
        "def sum(xs: List<&2, U32>, acc: U32) -> U32:\n  match xs:\n    case Nil{}:\n      acc\n    case Con{x, rest}:\n      sum(rest, (acc + x : U32))\n\ndef main() -> U32:\n  sum!([1, 2, 3], 0)\n",
      ),
    ).toEqual([
      "34:3 warning performance/gpu-fit: sum! runs on one GPU lane, alone: no parallel let runs under sum. GPU: measured 80x slower than without the `!` (a list walk of BendSR, RTX 4050 laptop). CPU (`--gpu off`): 1.6x slower. Confidence: high. Remove the `!`, or fork inside sum with a parallel let.",
    ]);
  });

  test("a ! call of a definition that forks through a call is not alone", async () => {
    expect(
      (
        await getReports(
          "def wrap(t: T) -> U32:\n  walk(t)\n\ndef main(t: T) -> U32:\n  wrap!(t)\n",
        )
      ).map((f) => f.split(" receives")[0]),
    ).toEqual(["30:3 information performance/gpu-fit: wrap!"]);
  });

  test("a fork over numbers called without ! is a hint that a long call may be faster on the GPU", async () => {
    expect(
      (await getReports("def main() -> U32:\n  grow(10n, 1, P{0.0, 0.0})\n")).map(
        (f) => f.split(", so")[0],
      ),
    ).toEqual(["27:3 hint performance/gpu-fit: grow forks over numbers only"]);
  });

  test("a ! call of a definition that returns Unit is left to performance/drop-in-bang", async () => {
    expect(
      await getReports(
        "def free(t: T) -> Unit:\n  match t:\n    case Leaf{v}:\n      Unit{}\n    case Node{l, r}:\n      free(r)\n\ndef main(t: T) -> Unit:\n  free!(t)\n",
      ),
    ).toEqual([]);
  });

  test("a ! call over numbers, and a call of a fork from a fork, pass", async () => {
    expect(
      await getReports(
        "def main() -> U32:\n  grow!(10n, 1, P{0.0, 0.0})\n\ndef twice(d: Nat) -> U32:\n  match d:\n    case 0n:\n      grow(3n, 1, P{0.0, 0.0})\n    case 1n++e:\n      a b = twice(e) twice(e)\n      (a + b : U32)\n",
      ),
    ).toEqual([]);
  });
});
