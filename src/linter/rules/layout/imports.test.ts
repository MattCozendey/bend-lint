// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, BUILDS, lint, run } from "../../testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when bend does not run.
const PROGRAM = BUILDS ? build("rules/layout/imports.bend") : "";

const LEAF = "import Base\n\ndef one() -> U32:\n  1\n";

const MAIN = "\ndef main() -> U32:\n  1\n";

const MESSAGE = "Order the imports: import Base first, then by path and alias, each file once.";

// Functions
// =========

// What the rule finds in `named`, beside a.bend, b.bend and sub/c.bend.
const found = (text: string, named = "main.bend"): string[] =>
  lint(PROGRAM, { [named]: text, "a.bend": LEAF, "b.bend": LEAF, "sub/c.bend": LEAF }, named).map(
    ({ at, message }) => at + " " + message,
  );

// Side effects
// ============

setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)("layout/imports", () => {
  test("Base first, then sorted by path, passes", () => {
    expect(
      found("import Base\nimport ../a.bend as A\nimport ./c.bend as C\n" + MAIN, "sub/main.bend"),
    ).toEqual([]);
  });

  test("Base after another import, or paths out of order, are reported at the block", () => {
    expect(
      found(
        "import ./c.bend as C\nimport ../b.bend as B\nimport Base\nimport ../a.bend as A\n" + MAIN,
        "sub/main.bend",
      ),
    ).toEqual(["1:1 " + MESSAGE]);
  });

  test("a comment line stays with the import below it; a header is not in the block", () => {
    expect(
      found(
        "# header\nimport Base\n# about a\nimport ./a.bend as A\nimport ./b.bend as B  # bee\n" +
          MAIN,
      ),
    ).toEqual([]);
  });

  test("a blank line in the block is reported", () => {
    expect(found("import Base\n\nimport ./a.bend as A\n" + MAIN)).toEqual(["1:1 " + MESSAGE]);
  });

  test("a second import of a file is reported, also through another path", () => {
    expect(found("import Base\nimport ./a.bend as A\nimport ./a.bend as Again\n" + MAIN)).toEqual([
      "1:1 " + MESSAGE,
    ]);
    expect(found("import Base\nimport ./a.bend as A\nimport a.bend as Again\n" + MAIN)).toEqual([
      "1:1 " + MESSAGE,
    ]);
    expect(found("import Base\nimport ./a.bend as A\nimport Base\n" + MAIN)).toEqual([
      "1:1 " + MESSAGE,
    ]);
  });

  test("a file without imports passes", () => {
    expect(found("type N is Data:\n  Z{}\n")).toEqual([]);
  });

  test("--fix-dangerously writes the block in order, each file once", () => {
    const files = { "a.bend": LEAF, "b.bend": LEAF, "sub/c.bend": LEAF };
    const ordered = run(
      PROGRAM,
      {
        ...files,
        "sub/main.bend":
          "import ./c.bend as C\nimport ../b.bend as B\nimport Base\nimport ../a.bend as A\n" +
          MAIN,
      },
      "sub/main.bend",
      ["--fix-dangerously"],
    );
    expect(ordered.files["sub/main.bend"]).toBe(
      "import Base\nimport ../a.bend as A\nimport ../b.bend as B\nimport ./c.bend as C\n" + MAIN,
    );
  });

  test("--fix-dangerously points the uses of a dropped import at the kept one", () => {
    const uses =
      "\ndef Again.same(x):\n  {==}\n\ndef main() -> U32:\n  (Again.one() + A.one() : U32)\n";
    const ran = run(
      PROGRAM,
      {
        "a.bend": LEAF + "\nlaw same:\n  for x: Nat\n  {x == x : Nat}\n",
        "main.bend":
          "import Base\nimport ./a.bend as A\nimport ./a.bend as Again\nimport Base\n" + uses,
      },
      "main.bend",
      ["--fix-dangerously"],
    );
    expect(ran.files["main.bend"]).toBe(
      "import Base\nimport ./a.bend as A\n" +
        "\ndef A.same(x):\n  {==}\n\ndef main() -> U32:\n  (A.one() + A.one() : U32)\n",
    );
  });
});
