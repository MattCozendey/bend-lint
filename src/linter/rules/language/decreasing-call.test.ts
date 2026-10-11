// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, BUILDS, lint } from "../../testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when bend does not run.
const PROGRAM = BUILDS ? await build("rules/language/decreasing-call.bend") : "";

const CODE = "language/decreasing-call";

// Functions
// =========

// Where each finding of the rule is, and what it says. Bend's check fails on these files too.
const found = async (text: string): Promise<string[]> =>
  (await lint(PROGRAM, { "main.bend": text }, "main.bend"))
    .filter(({ code }) => code === CODE)
    .map(({ at, message }) => `${at} ${message}`);

// Every finding, of the rule and of Bend's check.
const all = async (text: string): Promise<string[]> =>
  (await lint(PROGRAM, { "main.bend": text }, "main.bend")).map(({ at, code }) => `${at} ${code}`);

// Side effects
// ============

setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(CODE, () => {
  test("an argument that is another parameter is reported, with which one", async () => {
    expect(
      await found(
        "import Base\n\ndef f(n: Nat, m: Nat) -> Nat:\n  match n:\n    case 0n:\n      m\n    case 1n+p:\n      f(m, p)\n",
      ),
    ).toEqual([
      '8:7 f calls itself here, but argument 1 (`m`) is neither the parameter n unchanged nor a part of it that a match took apart, and the arguments before it are unchanged. Bend reads the arguments left to right, so it cannot prove the loop ends, and the check fails ("a decreasing self-call"). Put the parameter that shrinks first, pass the ones before it unchanged, and pass a part of it that a match took apart (`p` of `case 1n+p:`).',
    ]);
  });

  test("an argument that is a call is reported", async () => {
    expect(
      (
        await found(
          "import Base\n\ndef f(n: Nat) -> Nat:\n  match n:\n    case 0n:\n      0n\n    case 1n+p:\n      f(Nat.add(p, 1n))\n",
        )
      ).map((f) => f.split(" (`")[0]),
    ).toEqual(["8:7 f calls itself here, but argument 1"]);
  });

  test("a call with every argument unchanged is reported", async () => {
    expect(await found("import Base\n\ndef f(n: Nat) -> Nat:\n  f(n)\n")).toEqual([
      '4:3 f calls itself here with every argument unchanged, so the loop would never end, and the check fails ("a decreasing self-call"). Pass a part of the parameter that shrinks, one that a match took apart (`p` of `case 1n+p:`).',
    ]);
  });

  test("decreasing calls, @unsafe definitions and calls in types pass", async () => {
    expect(
      await all(
        "import Base\n\ndef f(+m: Nat, n: Nat) -> Nat:\n  match n:\n    case 0n:\n      m\n    case 1n+p:\n      f(m, p)\n\n@unsafe\ndef g(n: Nat) -> Nat:\n  g(n)\n\ndef h?(n: Nat) -> Nat:\n  h(n)\n\ndef Ord(xs: List<&2, Nat>) -> Type:\n  match xs:\n    case Nil{}:\n      Unit\n    case x <> t:\n      (Nat & Ord(t))\n",
      ),
    ).toEqual([]);
  });
});
