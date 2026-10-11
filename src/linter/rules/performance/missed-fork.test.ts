// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, BUILDS, lint } from "../../testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when bend does not run.
const PROGRAM = BUILDS ? await build("rules/performance/missed-fork.bend") : "";

// What each finding says after what it found, about the cost of a fork.
const CAVEAT =
  ' Do it only if each call does much work: each fork costs about 100 operations of task machinery ("bend guide shaders"), so forking small calls makes the program slower. The JS lane runs on one thread, so it does not gain. Measured in the hand-tuned slash boss demo of Bend, forks of this kind made it slower: in a merge of quadtree cells, a frame took 16% longer; in a cloth step, that step took 30% longer. Time the program before and after a fork, and keep it only if it is faster.';

// Functions
// =========

// A definition of depth `d` whose step is `step`, written under `case 1n++p:`.
const def = (name: string, step: string, returns = "U32", leaf = "1"): string =>
  `def ${name}(d: Nat) -> ${returns}:\n  match d:\n    case 0n:\n      ${leaf}\n    case 1n++p:\n${step}\n`;

// A file whose first definition starts on line 7, so its step is on line 12.
const file = (...defs: string[]): string =>
  "import Base\n\ntype T is Data:\n  Leaf{}\n  Node{l: T, r: T}\n\n" + defs.join("\n");

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

(BUILDS ? describe : describe.skip)("performance/missed-fork", () => {
  test("two calls in one call's arguments are reported, with the parallel let to write", async () => {
    expect(await found(file(def("f", "      U32.add(f(p), f(p))")))).toEqual([
      "12:7 performance/missed-fork: f calls itself 2 times in this expression (`f(p)`, `f(p)`), and these calls run one after the other. Bend runs calls in parallel only as the values of a parallel let. To run them in parallel, bind them first with one parallel let of fresh names, such as `a b = f(p) f(p)`, and use those names here." +
        CAVEAT,
    ]);
  });

  test("two calls in a constructor are reported", async () => {
    expect(await where(file(def("f", "      Node{f(p), f(p)}", "T", "Leaf{}")))).toEqual(["12:7"]);
  });

  test("two calls under an operator are reported", async () => {
    expect(await where(file(def("f", "      (f(p) + f(p) : U32)")))).toEqual(["12:8"]);
  });

  test("calls nested in other calls of one expression are reported", async () => {
    expect(await where(file(def("f", "      U32.add(U32.mul(2, f(p)), f(p))")))).toEqual(["12:7"]);
  });

  test("calls in a let's value are reported at the value", async () => {
    expect(await where(file(def("f", "      x = U32.add(f(p), f(p))\n      x")))).toEqual([
      "12:11",
    ]);
  });

  test("lets that follow each other are reported, with the parallel let to write", async () => {
    expect(
      await found(file(def("f", "      +l = f(p)\n      r = f(p)\n      (l + r + l : U32)"))),
    ).toEqual([
      "12:7 performance/missed-fork: f calls itself in 2 lets that follow each other (`+l = f(p)`, `r = f(p)`), and these calls run one after the other. Bend runs calls in parallel only as the values of a parallel let. To run them in parallel, merge the lets into one: `+l r = f(p) f(p)`." +
        CAVEAT,
    ]);
  });

  test("three lets that follow each other are one finding", async () => {
    expect(
      await where(
        file(def("f", "      x = f(p)\n      y = f(p)\n      z = f(p)\n      (x + y + z : U32)")),
      ),
    ).toEqual(["12:7"]);
  });

  test("a typed let counts", async () => {
    expect(
      await where(file(def("f", "      l = f(p)\n      r: U32 = f(p)\n      (l + r : U32)"))),
    ).toEqual(["12:7"]);
  });

  test("a let whose call uses the one before passes", async () => {
    expect(
      await found(
        file(
          "def f(d: Nat, x: U32) -> U32:\n  match d:\n    case 0n:\n      x\n    case 1n++p:\n      +l = f(p, x)\n      r = f(p, l)\n      (l + r : U32)\n",
        ),
      ),
    ).toEqual([]);
  });

  test("a parallel let passes", async () => {
    expect(await found(file(def("f", "      a b = f(p) f(p)\n      U32.add(a, b)")))).toEqual([]);
  });

  test("one call per expression passes", async () => {
    expect(await found(file(def("f", "      U32.add(f(p), 1)")))).toEqual([]);
  });

  test("calls to other definitions pass", async () => {
    expect(
      await found(file(def("g", "      g(p)"), def("f", "      U32.add(g(p), g(p))"))),
    ).toEqual([]);
  });

  test("a definition that returns IO passes", async () => {
    expect(
      await found(
        file(def("f", "      IO.bind(Unit, Unit, f(p), u => f(p))", "IO(Unit)", 'IO.print("x")')),
      ),
    ).toEqual([]);
  });
});
