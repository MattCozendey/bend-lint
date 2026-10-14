// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindings, getRunOutcome } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "layout/directive_order";

// Functions
// =========

// A directive that names `rule`, which the program need not know: the order is by what is written.
const getDisableDirective = (rule: string): string =>
  `# bend-lint: disable-next ${rule} -- a reason not-expected-because: it varies`;

// What the rule finds in a file of `lines`.
const getReports = async (lines: string[]): Promise<string[]> =>
  (await getFindings(RULE, { "main.bend": lines.join("\n") + "\n" }, "main.bend"))
    .filter(({ code }) => code === RULE)
    .map(({ at, severity, message }) => `${at} ${severity} ${message}`);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("a stack out of order is reported where it starts; one in order, or no stack, is not", async () => {
    expect(
      await getReports([
        "import Base",
        getDisableDirective("c/d"),
        getDisableDirective("a/b"),
        "",
        getDisableDirective("a/b"),
        getDisableDirective("c/d"),
        "",
        getDisableDirective("c/d"),
        "",
        getDisableDirective("a/b"),
        "def one() -> U32:",
        "  1 " + getDisableDirective("a/b").replace("disable-next", "disable-line"),
      ]),
    ).toEqual([
      "2:1 warning Directives that stack must be in order: by rule, then severity, then keyword.",
    ]);
  });

  test("--fix-dangerously writes the stack in order, over the same comments", async () => {
    const getFile = (first: string, second: string): string =>
      ["import Base", first, second, "def one() -> U32:", "  1", ""].join("\n");
    const ran = await getRunOutcome(
      RULE,
      { "main.bend": getFile(getDisableDirective("c/d"), getDisableDirective("a/b")) },
      "main.bend",
      ["--fix-dangerously"],
    );
    expect(ran.files["main.bend"]).toEqual(
      getFile(getDisableDirective("a/b"), getDisableDirective("c/d")),
    );
  });
});
