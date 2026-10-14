// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindings, getRunOutcome } from "../../src/linter/testing.ts";
import type { Found } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "no_unused/imports";

const UTIL = "import Base\n\ndef two() -> U32:\n  2\n\nlaw two_is_two:\n  {two() == 2 : U32}\n";

// Functions
// =========

const getReports = (main: string): Promise<Found[]> =>
  getFindings(RULE, { "main.bend": main, "util.bend": UTIL }, "main.bend");

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("an alias that names nothing is reported, at the alias", async () => {
    expect(
      await getReports(
        "import Base\nimport ./util.bend as U\nimport ./util.bend as V\n\ndef three() -> U32:\n  (U.two() + 1 : U32)\n",
      ),
    ).toEqual([
      {
        file: "main.bend",
        at: "3:23",
        severity: "warning",
        code: "no_unused/imports",
        message: "Remove the import V: nothing uses it.",
      },
    ]);
  });

  test("an alias a name is written through is used", async () => {
    expect(
      await getReports(
        "import Base\nimport ./util.bend as U\n\ndef three() -> U32:\n  (U.two() + 1 : U32)\n",
      ),
    ).toEqual([]);
  });

  test("a fill of an imported law uses its alias; Base, used by no name, is reported", async () => {
    expect(
      await getReports("import Base\nimport ./util.bend as U\n\ndef U.two_is_two():\n  {==}\n"),
    ).toEqual([
      {
        file: "main.bend",
        at: "1:8",
        severity: "warning",
        code: "no_unused/imports",
        message: "Remove the import Base: nothing uses it.",
      },
    ]);
  });

  test("--fix-dangerously deletes the import's line", async () => {
    const ran = await getRunOutcome(
      RULE,
      {
        "main.bend":
          "import Base\nimport ./util.bend as U\nimport ./util.bend as V\n\ndef three() -> U32:\n  (U.two() + 1 : U32)\n",
        "util.bend": UTIL,
      },
      "main.bend",
      ["--fix-dangerously"],
    );
    expect(ran.files["main.bend"]).toBe(
      "import Base\nimport ./util.bend as U\n\ndef three() -> U32:\n  (U.two() + 1 : U32)\n",
    );
  });
});
