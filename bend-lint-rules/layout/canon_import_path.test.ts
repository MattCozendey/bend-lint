// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getFindings, getRunOutcome } from "../../src/linter/testing.ts";

// Constants
// =========

const RULE = "layout/canon_import_path";

const LEAF = "import Base\n\ndef one() -> U32:\n  1\n";

// Functions
// =========

// What the rule finds in `named`, whose imports are `imports`, beside x.bend and sub/y.bend.
const getReports = async (named: string, imports: string): Promise<string[]> =>
  (
    await getFindings(
      RULE,
      {
        [named]: "import Base\n" + imports + "\ndef main() -> U32:\n  1\n",
        "x.bend": LEAF,
        "sub/y.bend": LEAF,
      },
      named,
    )
  ).map(({ at, message }) => at + " " + message);

// Side effects
// ============

await buildRule(RULE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)(RULE, () => {
  test("shortest paths that start with ./ or ../ pass, and so does Base", async () => {
    expect(
      await getReports("main.bend", "import ./x.bend as X\nimport ./sub/y.bend as Y\n"),
    ).toEqual([]);
    expect(
      await getReports("sub/main.bend", "import ../x.bend as X\nimport ./y.bend as Y\n"),
    ).toEqual([]);
  });

  test("a path without ./ is reported, at the path", async () => {
    expect(await getReports("main.bend", "import x.bend as X\nimport sub/y.bend as Y\n")).toEqual([
      '2:8 Write "./x.bend": the shortest path from this file, starting with ./ or ../.',
      '3:8 Write "./sub/y.bend": the shortest path from this file, starting with ./ or ../.',
    ]);
  });

  test("a longer path is reported with the shortest one", async () => {
    expect(
      await getReports("sub/main.bend", "import ./../x.bend as X\nimport ../sub/y.bend as Y\n"),
    ).toEqual([
      '2:8 Write "../x.bend": the shortest path from this file, starting with ./ or ../.',
      '3:8 Write "./y.bend": the shortest path from this file, starting with ./ or ../.',
    ]);
  });

  test("--fix-dangerously writes the shortest path", async () => {
    const ran = await getRunOutcome(
      RULE,
      {
        "main.bend": "import Base\nimport x.bend as X\n\ndef main() -> U32:\n  X.one()\n",
        "x.bend": LEAF,
      },
      "main.bend",
      ["--fix-dangerously"],
    );
    expect(ran.files["main.bend"]).toBe(
      "import Base\nimport ./x.bend as X\n\ndef main() -> U32:\n  X.one()\n",
    );
  });
});
