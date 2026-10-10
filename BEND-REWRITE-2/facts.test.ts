// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, lint } from "./testing.ts";
import type { Found } from "./testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when Bend is not given.
const TYPES = process.env.BEND_DIR === undefined ? "" : build("tests/types.bend");
const BUDGET = process.env.BEND_DIR === undefined ? "" : build("tests/budget.bend");

const UTIL = "import Base\n\ntype T is Data:\n  A{}\n  B{}\n";

// Functions
// =========

const found = (program: string, main: string): Array<Pick<Found, "at" | "message">> =>
  lint(program, { "main.bend": main, "util.bend": UTIL }, "main.bend").map(({ at, message }) => ({
    at,
    message,
  }));

// Side effects
// ============

setDefaultTimeout(120_000);

(process.env.BEND_DIR === undefined ? describe.skip : describe)("facts", () => {
  test("a variable use has the type it was checked as; same types are the same", () => {
    expect(
      found(TYPES, "import Base\n\ndef add(a: U32, b: U32) -> U32:\n  (a + b : U32)\n"),
    ).toEqual([
      { at: "4:4", message: "type: U32" },
      { at: "4:8", message: "type: U32" },
      { at: "4:4", message: "the first two are the same type" },
    ]);
  });

  test("different types are different", () => {
    expect(
      found(
        TYPES,
        "import Base\n\ndef size(s: String, n: U32) -> U32:\n  (U32.from_nat(String.length(s)) + n : U32)\n",
      ),
    ).toEqual([
      { at: "4:31", message: "type: String" },
      { at: "4:37", message: "type: U32" },
      { at: "4:31", message: "the first two are different types" },
    ]);
  });

  test("a type is shown as the file spells it", () => {
    expect(
      found(
        TYPES,
        "import Base\nimport ./util.bend as U\n\ndef push(t: U.T, xs: List<&2, U.T>) -> List<&2, U.T>:\n  t <> xs\n",
      ),
    ).toEqual([
      { at: "5:3", message: "type: U.T" },
      { at: "5:8", message: "type: List<&2, U.T>" },
      { at: "5:3", message: "the first two are different types" },
    ]);
  });

  test("a file with no variable uses asks nothing", () => {
    expect(found(TYPES, "import Base\n\ndef one() -> U32:\n  1\n")).toEqual([]);
  });

  test("a rule that asks past the round budget fails, and says so", () => {
    expect(found(BUDGET, "import Base\n\ndef id(x: U32) -> U32:\n  x\n")).toEqual([
      {
        at: "1:1",
        message: "The rule tests/budget asked the checker more rounds than its budget.",
      },
    ]);
  });
});
