// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindings, getFindingTexts } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "performance/template_value_field";

// A record of functions, a reader of its value field, and a leaf; the definitions that follow start
// on line 14.
const START =
  "import Base\n\ntype R is Type:\n  R{f: U32 -> U32, n: U32}\n\ndef R.n(r: R) -> U32:\n  match r:\n    case R{f, n}:\n      n\n\ndef leaf() -> R:\n  R{x => x, 1}\n\n";

const BOTH = "def both(~a: R, ~b: R) -> R:\n  R{x => x, (R.n(a) + R.n(b) : U32)}\n";

// Functions
// =========

// Where each finding is, and the template it names. The file must pass Bend's check.
const getPlaces = async (defs: string): Promise<string[]> =>
  (await getFindingTexts(RULE, START + defs)).map((f) => f.split(" is a template")[0]);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("a value field that reads a record of functions passed as a template is reported, with what to do", async () => {
    expect((await getFindingTexts(RULE, START + BOTH))[0]).toEqual(
      "15:18 performance/template_value_field: a is a template, so reading it here builds its whole record, closures too, to read a part of it; and a record of functions passed as a template is built again at each use, so both repeats this wherever its record is used, twice as often at each level of nesting. All lanes. Measured on a combinator nested 6 deep: 1.7 s against 1.0 s after the fix on the C lane, 49 s against 14 s on the JS lane; on a nested model, 6% of the time. Confidence: medium, as the fix moves the work to each read of the field. Make the field a function of Unit (`n: Unit -> U32`, built as `u => ..`), so that a is read only when the field is called. If the field is read about as often as the record is built, expect this finding.",
    );
  });

  test("a function or number template, a record of values, a read in a lambda field, and a record built under a lambda, pass", async () => {
    expect(
      await getPlaces(
        "type Box is Data:\n  Box{n: U32}\n\n" +
          "def lift(~g: U32 -> U32) -> R:\n  R{x => g(x), g(3)}\n\n" +
          "def width(~w: U32) -> R:\n  R{x => x, (w * 2 : U32)}\n\n" +
          "def count(~a: R) -> Box:\n  Box{R.n(a)}\n\n" +
          "def wrap(~a: R) -> R:\n  R{x => (x + R.n(a) : U32), 1}\n\n" +
          "def later(~a: R) -> U32 -> R:\n  y => R{x => x, R.n(a)}\n",
      ),
    ).toEqual([]);
  });

  test("a record of functions declared in another file is judged", async () => {
    expect(
      (
        await getFindings(
          RULE,
          {
            "kinds.bend": "type R is Type:\n  R{f: U32 -> U32, n: U32}\n",
            "main.bend":
              "import Base\nimport ./kinds.bend as K\n\ndef R.n(r: K.R) -> U32:\n  match r:\n    case K.R{f, n}:\n      n\n\ndef both(~a: K.R, ~b: K.R) -> K.R:\n  K.R{x => x, (R.n(a) + R.n(b) : U32)}\n",
          },
          "main.bend",
        )
      ).map(({ at, message }) => `${at} ${message.split(" is a template")[0]}`),
    ).toEqual(["10:20 a", "10:29 b"]);
  });
});
