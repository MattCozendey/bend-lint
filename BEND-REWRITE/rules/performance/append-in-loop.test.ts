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

const RULE = fileURLToPath(new URL("./append-in-loop.bend", import.meta.url));
const CODE = "performance/append-in-loop";

const dir = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), "bend-rewrite-append-")));

// Functions
// =========

// A loop of `n` steps over the accumulator `acc` of type `type`, whose step is `step`.
const loop = (type: string, step: string): string =>
  `import Base\n\ndef f(n: Nat, acc: ${type}) -> ${type}:\n  match n:\n    case 0n:\n      acc\n    case 1n+p:\n${step}\n`;

// The findings of the rule on `text`, which must pass Bend's check; none has a fix.
const reported = (text: string): Array<Pick<Found, "text" | "message">> => {
  const out = lintIn(dir, { "main.bend": text }, "main.bend", ["--rules", RULE]);
  expect(out.filter((f) => f.code !== CODE)).toEqual([]);
  expect(out.every((f) => f.fixes.length === 0)).toBe(true);
  return out.map(({ text: at, message }) => ({ text: at, message }));
};

// Side effects
// ============

setDefaultTimeout(300_000);

afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));

describe("performance/append-in-loop", () => {
  test("List.append to the accumulator of a loop is reported", () => {
    expect(reported(loop("List<&2, U32>", "      f(p, List.append(&2, U32, acc, [1]))"))).toEqual([
      {
        text: "List.append(&2, U32, acc, [1])",
        message:
          "List.append copies acc on each call of f, so building it is O(n²). Build it at its head with `x <> acc`, and reverse it once when the loop ends: `List.reverse(&2, U32, acc)`.",
      },
    ]);
  });

  test("++ to the accumulator of a loop is reported", () => {
    expect(reported(loop("String", '      f(p, acc ++ "x")'))).toEqual([
      {
        text: 'acc ++ "x"',
        message:
          "++ copies acc on each call of f, so building it is O(n²). Collect the pieces in a list with `piece <> acc`, and join them once when the loop ends: `String.concat(List.reverse(&2, String, acc))`.",
      },
    ]);
  });

  test("a cons at the accumulator's head passes", () => {
    expect(reported(loop("List<&2, U32>", "      f(p, 1 <> acc)"))).toEqual([]);
  });

  test("an append before the accumulator passes", () => {
    expect(reported(loop("List<&2, U32>", "      f(p, List.append(&2, U32, [1], acc))"))).toEqual(
      [],
    );
  });

  test("an append that is not passed to the loop passes", () => {
    expect(
      reported(
        "import Base\n\ndef f(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:\n  match n:\n    case 0n:\n      List.append(&2, U32, acc, [1])\n    case 1n+p:\n      f(p, acc)\n",
      ),
    ).toEqual([]);
  });

  test("an append in a def that does not call itself passes", () => {
    expect(
      reported(
        "import Base\n\ndef f(acc: List<&2, U32>) -> List<&2, U32>:\n  List.append(&2, U32, acc, [1])\n",
      ),
    ).toEqual([]);
  });
});
