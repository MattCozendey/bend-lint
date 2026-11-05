// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindings, getRunOutcome } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "layout/format";

// Functions
// =========

const getReports = async (text: string): Promise<string[]> =>
  (await getFindings(RULE, { "main.bend": text }, "main.bend")).map(
    ({ at, message }) => at + " " + message,
  );

// The config error a run with `options` stops with.
const getConfigError = async (options: Record<string, unknown>): Promise<string> => {
  const ran = await getRunOutcome(
    RULE,
    {
      "main.bend": "import Base\n",
      "bend-lint.json": JSON.stringify({ rules: { "layout/format": options } }),
    },
    "main.bend",
  );
  expect(ran.code).toBe(2);
  return ran.err.trim();
};

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("a file that does not parse is not formatted", async () => {
    expect(await getReports("import Base\n\ndef main( -> U32:\n    1\n")).toEqual([]);
  });

  test("an option it does not declare, or a value it does not take, stops the run", async () => {
    expect(await getConfigError({ tabwidth: 4 })).toBe(
      "bend-lint config: layout/format: it has no option tabwidth",
    );
    expect(await getConfigError({ tabWidth: 0 })).toBe(
      "bend-lint config: layout/format: tabWidth does not take that value",
    );
    expect(await getConfigError({ wrapAtWidth: "always" })).toBe(
      "bend-lint config: layout/format: wrapAtWidth does not take that value",
    );
  });

  test("an empty file ends with a newline", async () => {
    expect(await getReports("")).toEqual(["1:1 Apply canonical formatting."]);
  });

  test("--fix makes no fix, and says why", async () => {
    const text =
      "import   Base\r\n\r\n\r\ntype N is Data:\r\n    Z{}  \r\n    S{p:N}\r\ndef id(x:N)->N:\r\n\tx  \r\ndef main()->N: id(S{Z{}})";
    const awaiting = await getRunOutcome(RULE, { "main.bend": text }, "main.bend", ["--fix"]);
    expect([
      awaiting.files["main.bend"],
      awaiting.out.trim().split("\n").at(-1),
      awaiting.err.trim(),
    ]).toEqual([
      text,
      "bend-lint: 1 finding(s)",
      "bend-lint: --fix makes no fix until Bend's checker in Bend can prove that a fix keeps the program; --fix-dangerously makes every fix",
    ]);
  });
});
