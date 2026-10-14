// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindingTexts } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "performance/bang-after-fork";

// A fork over numbers, a loop that does not fork, and a definition under which no parallel let runs; the
// definitions that follow start on line 21.
const START =
  "import Base\n\ndef host(+d: Nat, +i: U32) -> U32:\n  match d:\n    case 0n:\n      i\n    case 1n+e:\n      a b = host(e, (i * 2 : U32)) host(e, (i * 2 + 1 : U32))\n      (a + b : U32)\n\ndef spin(n: Nat, +x: U32) -> U32:\n  match n:\n    case 0n:\n      x\n    case 1n+m:\n      spin(m, (x + 1 : U32))\n\ndef walk(n: Nat, x: U32) -> U32:\n  spin(n, x)\n\n";

// Functions
// =========

// Where each finding is, and its first words. The file must pass Bend's check.
const getPlaces = async (defs: string): Promise<string[]> =>
  (await getFindingTexts(RULE, START + defs)).map((f) => f.split(" runs after")[0]);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("a ! call after a parallel let is reported, with what to do", async () => {
    expect(
      await getFindingTexts(
        RULE,
        START + "def f() -> U32:\n  a b = spin(3n, 1) spin(3n, 2)\n  host!(4n, (a + b : U32))\n",
      ),
    ).toEqual([
      "23:3 performance/bang-after-fork: host! runs after a fork of the same evaluation, so Bend runs it on the CPU pool, not on the GPU. GPU: measured 7x slower than with an IO step between them (3.9 s against 0.55 s, RTX 4050 laptop). CPU (`--gpu off`): no change. Confidence: high. Put an IO step, such as `t : Nat <- IO.now()`, between the forks and this call, as Bend's slash boss demo does.",
    ]);
  });

  test("a ! call after a let whose value forks, or with an argument that forks, is reported", async () => {
    expect(
      await getPlaces(
        "def f() -> U32:\n  +s = host(4n, 1)\n  host!(4n, s)\n\ndef g() -> U32:\n  host!(4n, host(4n, 1))\n\ndef k() -> IO(Unit):\n  do IO<Unit>:\n    s : U32 = host(4n, 1)\n    IO.print(U32.show(host!(4n, s)))\n",
      ),
    ).toEqual([
      "23:3 performance/bang-after-fork: host!",
      "26:3 performance/bang-after-fork: host!",
      "31:23 performance/bang-after-fork: host!",
    ]);
  });

  test("a ! call after another ! call, or with one as its argument, passes", async () => {
    expect(
      await getPlaces(
        "def f() -> U32:\n  +s = host!(4n, 1)\n  host!(4n, s)\n\ndef g() -> U32:\n  host!(4n, host!(4n, 1))\n",
      ),
    ).toEqual([]);
  });

  test("an IO step between, a let that does not fork, and a ! call that gpu-fit reports, pass", async () => {
    expect(
      await getPlaces(
        "def f() -> U32:\n  +s = spin(9n, 1)\n  host!(4n, s)\n\ndef g() -> IO(Unit):\n  do IO<Unit>:\n    s : U32 = host(4n, 1)\n    t : Nat <- IO.now()\n    IO.print(U32.show(host!(4n, s)))\n\ndef h() -> U32:\n  +s = host(4n, 1)\n  walk!(3n, s)\n",
      ),
    ).toEqual([]);
  });
});
