// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, BUILDS, lint } from "../../testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when bend does not run.
const PROGRAM = BUILDS ? await build("rules/performance/unneeded-plus.bend") : "";

// Functions
// =========

// Where each finding is, and what it says. The file must pass Bend's check.
const found = async (text: string): Promise<string[]> =>
  (await lint(PROGRAM, { "main.bend": text }, "main.bend")).map(
    ({ at, code, message }) => `${at} ${code}: ${message}`,
  );

// Side effects
// ============

setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)("performance/unneeded-plus", () => {
  test("a + parameter used once is reported, with what to write", async () => {
    expect(await found("import Base\n\ndef f(+x: Nat, y: Nat) -> Nat:\n  Nat.add(x, y)\n")).toEqual(
      [
        '3:8 performance/unneeded-plus: +x is used at most once on each path, so it needs no `+`. A `+` value carries a reference count at run time, and "bend guide shaders" measured a needless `+` slowing a program from 2.83 s to 3.30 s. Write x without the `+`. In the slash boss demo of Bend, removing 503 such + changed no timing: it matters most for a value that many lanes share.',
      ],
    );
  });

  test("a + field and a + let used once are reported", async () => {
    expect(
      (
        await found(
          "import Base\n\ndef f(xs: List<&2, Nat>) -> Nat:\n  match xs:\n    case Nil{}:\n      0n\n    case Con{+h, t}:\n      +y = h\n      y\n",
        )
      ).map((f) => f.split(" is used")[0]),
    ).toEqual(["7:14 performance/unneeded-plus: +h", "8:7 performance/unneeded-plus: +y"]);
  });

  test("+ binders used twice, and matched ones, pass", async () => {
    expect(
      await found(
        "import Base\n\ndef f(+x: Nat) -> Nat:\n  Nat.add(x, x)\n\ndef g(+n: Nat) -> Nat:\n  match n:\n    case 0n:\n      0n\n    case 1n+p:\n      Nat.add(p, p)\n",
      ),
    ).toEqual([]);
  });
});
