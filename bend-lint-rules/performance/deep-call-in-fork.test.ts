// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, BUILDS, lint } from "../../src/linter/testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when bend does not run.
const PROGRAM = BUILDS ? await build("performance/deep-call-in-fork") : "";

// 2^d, by a call of itself that is not a tail call. Lines 3 to 9.
const DEEP =
  "def pow2(d: Nat) -> U32:\n  match d:\n    case 0n:\n      1\n    case 1n+p:\n      +h = pow2(p)\n      U32.add(h, h)\n";

// 2^d times acc, by a tail call. Lines 3 to 8.
const FLAT =
  "def pow2(d: Nat, +acc: U32) -> U32:\n  match d:\n    case 0n:\n      acc\n    case 1n+p:\n      pow2(p, U32.add(acc, acc))\n";

// Functions
// =========

// A file with `pow2` and a fork over lo .. lo + 2^d - 1, whose leaf is `leaf` and whose step is `step`.
const file = (pow2: string, step: string, leaf = "lo"): string =>
  `import Base\n\n${pow2}\ndef f(d: Nat, +lo: U32) -> U32:\n  match d:\n    case 0n:\n      ${leaf}\n    case 1n++p:\n${step}\n`;

// Where each finding is, and what it says. The file must pass Bend's check.
const found = async (text: string): Promise<string[]> =>
  (await lint(PROGRAM, { "main.bend": text }, "main.bend")).map(
    ({ at, code, message }) => `${at} ${code}: ${message}`,
  );

const where = async (text: string): Promise<string[]> =>
  (await found(text)).map((f) => f.split(" ")[0]);

// Side effects
// ============

setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)("performance/deep-call-in-fork", () => {
  test("a call in a fork's value is reported, with what to do", async () => {
    expect(
      await found(
        file(DEEP, "      a b = f(p, lo) f(p, U32.add(lo, pow2(p)))\n      U32.add(a, b)"),
      ),
    ).toEqual([
      '16:39 performance/deep-call-in-fork: pow2 calls itself outside a tail position: Bend runs such a call with a frame per call ("bend guide shaders"). f calls pow2 in a fork: a value of its parallel let, or of a let just before it. In bend-lint\'s benchmark (Bend 2.0.36, 16 threads), one such call per fork cut the speedup from 10x to 1.9x, and a tail-recursive version kept the 10x. Make pow2 tail-recursive with an accumulator, compute its value with native operations (such as U32.shln), or compute it once and pass it down as a parameter. In the slash boss demo of Bend, doing so for such a call changed no timing: the list it walked was short. Time it before and after.',
    ]);
  });

  test("a call in a let just before the fork is reported", async () => {
    expect(
      await where(
        file(
          DEEP,
          "      +h = pow2(p)\n      a b = f(p, lo) f(p, U32.add(lo, h))\n      U32.add(a, b)",
        ),
      ),
    ).toEqual(["16:12"]);
  });

  test("a tail-recursive definition passes", async () => {
    expect(
      await found(
        file(FLAT, "      a b = f(p, lo) f(p, U32.add(lo, pow2(p, 1)))\n      U32.add(a, b)"),
      ),
    ).toEqual([]);
  });

  test("the call in a leaf passes", async () => {
    expect(
      await found(
        file(
          DEEP,
          "      a b = f(p, lo) f(p, U32.add(lo, U32.shln(1, p)))\n      U32.add(a, b)",
          "U32.add(lo, pow2(5n))",
        ),
      ),
    ).toEqual([]);
  });

  test("the call without a fork passes", async () => {
    expect(await found(file(DEEP, "      U32.add(f(p, lo), f(p, U32.add(lo, pow2(p))))"))).toEqual(
      [],
    );
  });

  test("a fork's calls of its own definition pass", async () => {
    expect(
      await found(
        `import Base\n\ndef f(d: Nat, +lo: U32) -> U32:\n  match d:\n    case 0n:\n      lo\n    case 1n++p:\n      a b = f(p, lo) f(p, U32.add(lo, U32.shln(1, p)))\n      U32.add(a, b)\n`,
      ),
    ).toEqual([]);
  });
});
