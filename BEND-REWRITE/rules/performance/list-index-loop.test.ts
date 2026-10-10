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

const RULE = fileURLToPath(new URL("./list-index-loop.bend", import.meta.url));
const CODE = "performance/list-index-loop";

const dir = fs.realpathSync.native(
  fs.mkdtempSync(path.join(os.tmpdir(), "bend-rewrite-list-loop-")),
);

// Functions
// =========

const file = (...defs: string[]): string =>
  "import Base\n\ndef or_zero(m: Maybe<&2, U32>) -> U32:\n  match m:\n    case None{}:\n      0\n    case Some{x}:\n      x\n\n" +
  defs.join("\n");

// A loop of `n` steps over `xs`, whose step is `step`.
const loop = (step: string): string =>
  `def f(n: Nat, +xs: List<&2, U32>, +i: Nat, acc: U32) -> U32:\n  match n:\n    case 0n:\n      acc\n    case 1n+p:\n${step}\n`;

const found = (text: string): Found[] =>
  lintIn(dir, { "main.bend": text }, "main.bend", ["--rules", RULE]);

// The findings of the rule on `text`, which must pass Bend's check.
const reported = (text: string): Array<Pick<Found, "text" | "message">> => {
  const out = found(text);
  expect(out.filter((f) => f.code !== CODE)).toEqual([]);
  return out.map(({ text: at, message }) => ({ text: at, message }));
};

// Side effects
// ============

setDefaultTimeout(300_000);

afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));

describe("performance/list-index-loop", () => {
  test("List.get on a list the loop passes unchanged is reported", () => {
    expect(
      reported(
        file(
          loop("      f(p, xs, Nat.add(i, 1n), U32.add(acc, or_zero(List.get(&2, U32, xs, i))))"),
        ),
      ),
    ).toEqual([
      {
        text: "List.get(&2, U32, xs, i))))",
        message:
          "List.get walks xs from its head, and f passes xs unchanged to each call of itself: the loop is O(n²). Walk it instead: match it, use its head, and pass its tail to the next call.",
      },
    ]);
  });

  test("List.length in such a loop asks to compute it once", () => {
    expect(
      reported(
        file(loop("      f(p, xs, i, U32.add(acc, U32.from_nat(List.length(&2, U32, xs))))")),
      ).map((f) => f.message),
    ).toEqual([
      "List.length walks xs from its head, and f passes xs unchanged to each call of itself: the loop is O(n²). Compute it once before the loop, and pass it as a parameter.",
    ]);
  });

  test("a helper that gives the list to List.get is reported where the loop calls it", () => {
    expect(
      reported(
        file(
          "def at(xs: List<&2, U32>, i: Nat) -> U32:\n  or_zero(List.get(&2, U32, xs, i))\n",
          loop("      f(p, xs, Nat.add(i, 1n), U32.add(acc, at(xs, i)))"),
        ),
      ),
    ).toEqual([
      {
        text: "at(xs, i)))",
        message:
          "at walks xs from its head (through List.get), and f passes xs unchanged to each call of itself: the loop is O(n²). Walk it instead: match it, use its head, and pass its tail to the next call.",
      },
    ]);
  });

  test("a helper called outside a loop passes", () => {
    expect(
      reported(
        file(
          "def at(xs: List<&2, U32>, i: Nat) -> U32:\n  or_zero(List.get(&2, U32, xs, i))\n",
          "def f(xs: List<&2, U32>) -> U32:\n  at(xs, 3n)\n",
        ),
      ),
    ).toEqual([]);
  });

  test("a loop that passes the list's rest passes", () => {
    expect(
      reported(
        file(
          loop(
            "      f(p, List.drop(&2, U32, xs, 1n), i, U32.add(acc, or_zero(List.get(&2, U32, xs, 0n))))",
          ),
        ),
      ),
    ).toEqual([]);
  });

  test("a loop that walks the list passes", () => {
    expect(
      reported(
        file(
          "def f(xs: List<&2, U32>, acc: U32) -> U32:\n  match xs:\n    case Nil{}:\n      acc\n    case h <> t:\n      f(t, U32.add(acc, h))\n",
        ),
      ),
    ).toEqual([]);
  });

  test("List.get outside a loop passes", () => {
    expect(
      reported(file("def f(xs: List<&2, U32>) -> U32:\n  or_zero(List.get(&2, U32, xs, 3n))\n")),
    ).toEqual([]);
  });

  test("a list that is not a parameter passes", () => {
    expect(
      reported(
        file(
          "def f(n: Nat, acc: U32) -> U32:\n  match n:\n    case 0n:\n      acc\n    case 1n++p:\n      f(p, U32.add(acc, or_zero(List.get(&2, U32, [1, 2, 3], p))))\n",
        ),
      ),
    ).toEqual([]);
  });

  test("a file that fails Bend's check gets no finding of the rule", () => {
    const out = found(file(loop("      f(p, xs, i, List.get(&2, U32, xs, i))")));
    expect(out.map((f) => f.code)).toEqual(["bend/check"]);
  });
});
