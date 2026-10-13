// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, BUILDS, lint } from "../../src/linter/testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when bend does not run.
const PROGRAM = BUILDS ? await build("performance/eager-branch") : "";

// A loop over n, on lines 3 to 8.
const SPIN =
  "def spin(n: Nat, acc: U32) -> U32:\n  match n:\n    case 0n:\n      acc\n    case 1n+p:\n      spin(p, (acc + 1 : U32))\n";

// What each finding says after its first sentence: why it matters and what to do.
const ADVICE =
  ". Measured on the C lane, a Bool.pick whose unused value ran a 300M-step loop took 0.63 s, against 0.26 s for a match. Choose with a match instead: pass the condition to a helper whose match runs only the needed value. Inside a loop, where such a helper would call the loop back (Bend refuses mutual recursion), pass the condition to the next call as a parameter, and match on it there.";

// Functions
// =========

// A file with `spin` and then `defs`, which start on line 10.
const file = (defs: string): string => "import Base\n\n" + SPIN + "\n" + defs;

// Where each finding is, and what it says. The file must pass Bend's check.
const found = async (text: string): Promise<string[]> =>
  (await lint(PROGRAM, { "main.bend": text }, "main.bend")).map(
    ({ at, code, message }) => `${at} ${code}: ${message}`,
  );

// Side effects
// ============

setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)("performance/eager-branch", () => {
  test("a value of Bool.pick that calls a loop is reported, with what to do", async () => {
    expect(
      await found(file("def f(c: Bool) -> U32:\n  Bool.pick(U32, c, 7, spin(9n, 0))\n")),
    ).toEqual([
      "11:24 performance/eager-branch: Bool.pick computes both of its values before it picks one, so this call of spin runs even when the condition picks the other value" +
        ADVICE +
        " If spin loops only a few steps here, ignore this.",
    ]);
  });

  test("the right side of && that calls a loop is reported", async () => {
    expect(
      (await found(file("def f(c: Bool) -> Bool:\n  c && U32.is_eq(spin(9n, 0), 9)\n"))).map(
        (f) => f.split(", so")[0],
      ),
    ).toEqual([
      "11:8 performance/eager-branch: && computes its right side even when its left side decides the result (False)",
    ]);
  });

  test("a loop's own call is reported as walking to its end", async () => {
    expect(
      (
        await found(
          "import Base\n\ndef has(xs: List<&2, U32>, +x: U32) -> Bool:\n  match xs:\n    case Nil{}:\n      False{}\n    case Con{h, t}:\n      U32.is_eq(h, x) || has(t, x)\n",
        )
      ).map((f) => f.split(". Measured")[0]),
    ).toEqual([
      "8:26 performance/eager-branch: || computes its right side even when its left side decides the result (True), so this call of has runs even then: it is the loop's own call, so the loop walks to its end instead of stopping where the condition decides",
    ]);
  });

  test("calls that do not loop, calls in a lambda, and a match pass", async () => {
    expect(
      await found(
        file(
          "def one() -> U32:\n  1\n\ndef f(c: Bool) -> U32:\n  Bool.pick(U32, c, 7, one())\n\ndef g(c: Bool) -> U32 -> U32:\n  Bool.pick(U32 -> U32, c, x => x, x => spin(9n, x))\n\ndef h(c: Bool) -> U32:\n  match c:\n    case True{}:\n      7\n    case False{}:\n      spin(9n, 0)\n",
        ),
      ),
    ).toEqual([]);
  });
});
