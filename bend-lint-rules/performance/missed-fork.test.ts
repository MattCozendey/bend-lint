// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindingTexts } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "performance/missed-fork";

// What each finding says after what it found, about the cost of a fork.
const CAVEAT =
  " C lane (CPU, and GPU under a `!`): measured 2.5x faster for a few calls over a 1M-leaf tree, but 3.9x slower for 100,000 calls over 1k-leaf trees, and 230x slower for a small tree walked once per data point. JS lane: one thread, no gain. Confidence: low, as it depends on how much work each call does. If this definition runs once per item of a loop, or below a fork that already fills the cores, expect this finding.";

// Functions
// =========

// A definition of depth `d` whose step is `step`, written under `case 1n++p:`.
const getDef = (name: string, step: string, returns = "U32", leaf = "1"): string =>
  `def ${name}(d: Nat) -> ${returns}:\n  match d:\n    case 0n:\n      ${leaf}\n    case 1n++p:\n${step}\n`;

// A file whose first definition starts on line 7, so its step is on line 12.
const getFile = (...defs: string[]): string =>
  "import Base\n\ntype T is Data:\n  Leaf{}\n  Node{l: T, r: T}\n\n" + defs.join("\n");

// Where each finding is, and what it says. The file must pass Bend's check.
const getReports = (text: string): Promise<string[]> => getFindingTexts(RULE, text);

const getPlaces = async (text: string): Promise<string[]> =>
  (await getReports(text)).map((f) => f.split(" ")[0]);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("two calls in one call's arguments are reported, with the parallel let to write", async () => {
    expect(await getReports(getFile(getDef("f", "      U32.add(f(p), f(p))")))).toEqual([
      "12:7 performance/missed-fork: f calls itself 2 times in this expression (`f(p)`, `f(p)`), and these calls run one after the other. Bend runs calls in parallel only as the values of a parallel let. To run them in parallel, bind them first with one parallel let of fresh names, such as `a b = f(p) f(p)`, and use those names here." +
        CAVEAT,
    ]);
  });

  test("two calls in a constructor are reported", async () => {
    expect(await getPlaces(getFile(getDef("f", "      Node{f(p), f(p)}", "T", "Leaf{}")))).toEqual([
      "12:7",
    ]);
  });

  test("two calls under an operator are reported", async () => {
    expect(await getPlaces(getFile(getDef("f", "      (f(p) + f(p) : U32)")))).toEqual(["12:8"]);
  });

  test("calls nested in other calls of one expression are reported", async () => {
    expect(await getPlaces(getFile(getDef("f", "      U32.add(U32.mul(2, f(p)), f(p))")))).toEqual([
      "12:7",
    ]);
  });

  test("calls in a let's value are reported at the value", async () => {
    expect(await getPlaces(getFile(getDef("f", "      x = U32.add(f(p), f(p))\n      x")))).toEqual(
      ["12:11"],
    );
  });

  test("lets that follow each other are reported, with the parallel let to write", async () => {
    expect(
      await getReports(
        getFile(getDef("f", "      +l = f(p)\n      r = f(p)\n      (l + r + l : U32)")),
      ),
    ).toEqual([
      "12:7 performance/missed-fork: f calls itself in 2 lets that follow each other (`+l = f(p)`, `r = f(p)`), and these calls run one after the other. Bend runs calls in parallel only as the values of a parallel let. To run them in parallel, merge the lets into one: `+l r = f(p) f(p)`." +
        CAVEAT,
    ]);
  });

  test("three lets that follow each other are one finding", async () => {
    expect(
      await getPlaces(
        getFile(
          getDef("f", "      x = f(p)\n      y = f(p)\n      z = f(p)\n      (x + y + z : U32)"),
        ),
      ),
    ).toEqual(["12:7"]);
  });

  test("a typed let counts", async () => {
    expect(
      await getPlaces(
        getFile(getDef("f", "      l = f(p)\n      r: U32 = f(p)\n      (l + r : U32)")),
      ),
    ).toEqual(["12:7"]);
  });

  test("a let whose call uses the one before passes", async () => {
    expect(
      await getReports(
        getFile(
          "def f(d: Nat, x: U32) -> U32:\n  match d:\n    case 0n:\n      x\n    case 1n++p:\n      +l = f(p, x)\n      r = f(p, l)\n      (l + r : U32)\n",
        ),
      ),
    ).toEqual([]);
  });

  test("a parallel let passes", async () => {
    expect(
      await getReports(getFile(getDef("f", "      a b = f(p) f(p)\n      U32.add(a, b)"))),
    ).toEqual([]);
  });

  test("one call per expression passes", async () => {
    expect(await getReports(getFile(getDef("f", "      U32.add(f(p), 1)")))).toEqual([]);
  });

  test("calls in different values of Bool.pick, or on two sides of &&, are alternatives and pass", async () => {
    expect(
      await getReports(
        getFile(
          getDef("f", "      Bool.pick(U32, True{}, f(p), U32.add(f(p), 1))"),
          getDef("g", "      g(p) && g(p)", "Bool", "True{}"),
        ),
      ),
    ).toEqual([]);
  });

  test("two calls in one value of Bool.pick are reported", async () => {
    expect(
      await getPlaces(getFile(getDef("f", "      Bool.pick(U32, True{}, U32.add(f(p), f(p)), 1)"))),
    ).toEqual(["12:30"]);
  });

  test("calls to other definitions pass", async () => {
    expect(
      await getReports(
        getFile(getDef("g", "      g(p)"), getDef("f", "      U32.add(g(p), g(p))")),
      ),
    ).toEqual([]);
  });

  test("a definition that returns IO passes", async () => {
    expect(
      await getReports(
        getFile(
          getDef("f", "      IO.bind(Unit, Unit, f(p), u => f(p))", "IO(Unit)", 'IO.print("x")'),
        ),
      ),
    ).toEqual([]);
  });
});
