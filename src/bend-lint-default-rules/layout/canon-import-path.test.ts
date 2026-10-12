// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, BUILDS, lint, run } from "../../linter/testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when bend does not run.
const PROGRAM = BUILDS ? await build("bend-lint-default-rules/layout/canon-import-path.bend") : "";

const LEAF = "import Base\n\ndef one() -> U32:\n  1\n";

// Functions
// =========

// What the rule finds in `named`, whose imports are `imports`, beside x.bend and sub/y.bend.
const found = async (named: string, imports: string): Promise<string[]> =>
  (
    await lint(
      PROGRAM,
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

setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)("layout/canon-import-path", () => {
  test("shortest paths that start with ./ or ../ pass, and so does Base", async () => {
    expect(await found("main.bend", "import ./x.bend as X\nimport ./sub/y.bend as Y\n")).toEqual(
      [],
    );
    expect(await found("sub/main.bend", "import ../x.bend as X\nimport ./y.bend as Y\n")).toEqual(
      [],
    );
  });

  test("a path without ./ is reported, at the path", async () => {
    expect(await found("main.bend", "import x.bend as X\nimport sub/y.bend as Y\n")).toEqual([
      '2:8 Write "./x.bend": the shortest path from this file, starting with ./ or ../.',
      '3:8 Write "./sub/y.bend": the shortest path from this file, starting with ./ or ../.',
    ]);
  });

  test("a longer path is reported with the shortest one", async () => {
    expect(
      await found("sub/main.bend", "import ./../x.bend as X\nimport ../sub/y.bend as Y\n"),
    ).toEqual([
      '2:8 Write "../x.bend": the shortest path from this file, starting with ./ or ../.',
      '3:8 Write "./y.bend": the shortest path from this file, starting with ./ or ../.',
    ]);
  });

  test("--fix-dangerously writes the shortest path", async () => {
    const ran = await run(
      PROGRAM,
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
