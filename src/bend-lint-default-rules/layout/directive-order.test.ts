// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, BUILDS, lint, run } from "../../linter/testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when bend does not run.
const PROGRAM = BUILDS ? await build("bend-lint-default-rules/layout/directive-order.bend") : "";

const RULE = "layout/directive-order";

// A directive that names `rule`, which the program need not know: the order is by what is written.
const disable = (rule: string): string =>
  `# bend-lint: disable-next ${rule} -- a reason not-expected-because: it varies`;

// Functions
// =========

// What the rule finds in a file of `lines`.
const found = async (lines: string[]): Promise<string[]> =>
  (await lint(PROGRAM, { "main.bend": lines.join("\n") + "\n" }, "main.bend"))
    .filter(({ code }) => code === RULE)
    .map(({ at, severity, message }) => `${at} ${severity} ${message}`);

// Side effects
// ============

setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("a stack out of order is reported where it starts; one in order, or no stack, is not", async () => {
    expect(
      await found([
        "import Base",
        disable("c/d"),
        disable("a/b"),
        "",
        disable("a/b"),
        disable("c/d"),
        "",
        disable("c/d"),
        "",
        disable("a/b"),
        "def one() -> U32:",
        "  1 " + disable("a/b").replace("disable-next", "disable-line"),
      ]),
    ).toEqual([
      "2:1 warning Directives that stack must be in order: by rule, then severity, then keyword.",
    ]);
  });

  test("--fix writes the stack in order, over the same comments", async () => {
    const file = (first: string, second: string): string =>
      ["import Base", first, second, "def one() -> U32:", "  1", ""].join("\n");
    const ran = await run(
      PROGRAM,
      { "main.bend": file(disable("c/d"), disable("a/b")) },
      "main.bend",
      ["--fix"],
    );
    expect(ran.files["main.bend"]).toEqual(file(disable("a/b"), disable("c/d")));
  });
});
