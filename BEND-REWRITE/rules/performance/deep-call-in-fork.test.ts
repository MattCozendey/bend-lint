// Imports
// =======

import { afterAll, describe, expect, setDefaultTimeout, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { lintIn } from "../../testing.ts";
import type { Found } from "../../testing.ts";

// Constants
// =========

const RULE = fileURLToPath(new URL("./deep-call-in-fork.bend", import.meta.url));
const CODE = "performance/deep-call-in-fork";

const dir = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), "bend-rewrite-deep-")));

// 2^d, recursing without a tail call.
const deep =
  "def pow2(d: Nat) -> U32:\n  match d:\n    case 0n:\n      1\n    case 1n+p:\n      +h = pow2(p)\n      U32.add(h, h)\n";

// 2^d times acc, with a tail call.
const flat =
  "def pow2(d: Nat, +acc: U32) -> U32:\n  match d:\n    case 0n:\n      acc\n    case 1n+p:\n      pow2(p, U32.add(acc, acc))\n";

// Functions
// =========

// A fork over lo .. lo + 2^d - 1, whose leaf is `leaf` and whose step is `step`.
const fork = (step: string, leaf = "lo"): string =>
  `def f(d: Nat, +lo: U32) -> U32:\n  match d:\n    case 0n:\n      ${leaf}\n    case 1n++p:\n${step}\n`;

const file = (...defs: string[]): string => "import Base\n\n" + defs.join("\n");

// The findings of the rule on `text`, which must pass Bend's check; none has a fix.
const reported = (text: string): Found[] => {
  const out = lintIn(dir, { "main.bend": text }, "main.bend", ["--rules", RULE]);
  expect(out.filter((f) => f.code !== CODE)).toEqual([]);
  expect(out.every((f) => f.fixes.length === 0)).toBe(true);
  return out;
};

// Where each finding starts.
const found = (text: string): string[] => reported(text).map((f) => f.text);

// Side effects
// ============

setDefaultTimeout(300_000);

afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));

describe("performance/deep-call-in-fork", () => {
  test("a call in a fork's value is reported", () => {
    const out = reported(
      file(deep, fork("      a b = f(p, lo) f(p, U32.add(lo, pow2(p)))\n      U32.add(a, b)")),
    );
    expect(out.map((f) => f.message)).toEqual([
      "pow2 recurses without a tail call, and f calls it at each fork. In our tests, such a call cut the 16-thread speedup from 10x to 1.9x; a tail call kept it. Make pow2 tail-recursive with an accumulator, compute its value with native operations, or pass it down as a parameter.",
    ]);
    expect(out.map((f) => f.text)).toEqual(["pow2(p)))"]);
  });

  test("a call in a let just before the fork is reported", () => {
    expect(
      found(
        file(
          deep,
          fork(
            "      +h = pow2(p)\n      a b = f(p, lo) f(p, U32.add(lo, h))\n      U32.add(a, b)",
          ),
        ),
      ),
    ).toEqual(["pow2(p)"]);
  });

  test("a def with a tail call passes", () => {
    expect(
      found(
        file(flat, fork("      a b = f(p, lo) f(p, U32.add(lo, pow2(p, 1)))\n      U32.add(a, b)")),
      ),
    ).toEqual([]);
  });

  test("the call in a leaf passes", () => {
    expect(
      found(
        file(
          deep,
          fork(
            "      a b = f(p, lo) f(p, U32.add(lo, U32.shln(1, p)))\n      U32.add(a, b)",
            "U32.add(lo, pow2(5n))",
          ),
        ),
      ),
    ).toEqual([]);
  });

  test("the call without a fork passes", () => {
    expect(found(file(deep, fork("      U32.add(f(p, lo), f(p, U32.add(lo, pow2(p))))")))).toEqual(
      [],
    );
  });

  test("a fork's calls of its own def pass", () => {
    expect(
      found(
        file(fork("      a b = f(p, lo) f(p, U32.add(lo, U32.shln(1, p)))\n      U32.add(a, b)")),
      ),
    ).toEqual([]);
  });
});
