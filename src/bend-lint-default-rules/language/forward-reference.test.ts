// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, BUILDS, lint } from "../../linter/testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when bend does not run.
const PROGRAM = BUILDS
  ? await build("bend-lint-default-rules/language/forward-reference.bend")
  : "";

const CODE = "language/forward-reference";

// Functions
// =========

// Where each finding of the rule is, and what it says. Bend's check fails on these files too.
const found = async (text: string): Promise<string[]> =>
  (await lint(PROGRAM, { "main.bend": text }, "main.bend"))
    .filter(({ code }) => code === CODE)
    .map(({ at, message }) => `${at} ${message}`);

// Every finding.
const all = async (text: string): Promise<string[]> =>
  (await lint(PROGRAM, { "main.bend": text }, "main.bend")).map(({ at, code }) => `${at} ${code}`);

// Side effects
// ============

setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(CODE, () => {
  test("a use of a definition below is reported, with what to do", async () => {
    expect(
      await found("import Base\n\ndef main() -> Nat:\n  later()\n\ndef later() -> Nat:\n  1n\n"),
    ).toEqual([
      '4:3 later is defined below main, and Bend checks definitions in file order: live code can use only what is defined above it, so this use fails the check ("a filled definition"). Move later above main. If the two call each other, merge them into one definition with an argument that selects which to run: Bend does not allow mutual recursion. This is a false positive if the use is an argument for an erased parameter (`-x`): that is dead code.',
    ]);
  });

  test("uses of definitions above, and from @unsafe definitions, pass", async () => {
    expect(
      await all(
        "import Base\n\ndef earlier() -> Nat:\n  1n\n\ndef main() -> Nat:\n  earlier()\n\n@unsafe\ndef u() -> Nat:\n  later()\n\ndef v?() -> Nat:\n  later()\n\ndef later() -> Nat:\n  1n\n",
      ),
    ).toEqual([]);
  });
});
