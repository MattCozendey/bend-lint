import { afterAll, describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { applyFixes, createLinter } from "../../src/lint.ts";
import { unwrap } from "../../src/result.ts";

const linter = unwrap(await createLinter());
const rules = unwrap(
  await linter.loadRules([fileURLToPath(new URL("./imports.bend", import.meta.url))]),
);
const dir = fs.realpathSync
  .native(fs.mkdtempSync(path.join(os.tmpdir(), "bend-layout-")))
  .replaceAll("\\", "/");
afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));
const fixture = (name: string, text: string): string => {
  const file = path.posix.join(dir, name);
  fs.mkdirSync(path.posix.dirname(file), { recursive: true });
  fs.writeFileSync(file, text);
  return file;
};
const LEAF = "import Base\n\ndef one() -> U32:\n  1\n";
fixture("a.bend", LEAF);
fixture("b.bend", LEAF);
fixture("sub/c.bend", LEAF);

const MAIN = "\ndef main() -> U32:\n  1\n";

// The file its fix gives, after one finding with a fix; the same text when
// it finds nothing.
const fixed = async (text: string, name = "main.bend"): Promise<string> => {
  const res = unwrap(await linter.lint(fixture(name, text), rules, { config: {} }));
  expect(res.diags.filter((d) => d.code !== "layout/imports").map(linter.render)).toEqual([]);
  expect(res.diags.every((d) => d.fixes.length === 1)).toBe(true);
  return applyFixes(res.root!, res.diags).text;
};

// The fixed text passes Bend's check, and the rule finds nothing more.
const settled = async (text: string, name = "main.bend"): Promise<void> => {
  const res = unwrap(await linter.lint(fixture(name, text), rules, { config: {} }));
  expect(res.diags.map(linter.render)).toEqual([]);
};

describe("layout/imports", () => {
  test("Base first, then sorted by path, passes", async () => {
    await settled(
      "import Base\nimport ../a.bend as A\nimport ./c.bend as C\n" + MAIN,
      "sub/main.bend",
    );
  });

  test("Base moves first, and the others sort by path, ../ before ./", async () => {
    const out = await fixed(
      "import ./c.bend as C\nimport ../b.bend as B\nimport Base\nimport ../a.bend as A\n" + MAIN,
      "sub/main.bend",
    );
    expect(out).toBe(
      "import Base\nimport ../a.bend as A\nimport ../b.bend as B\nimport ./c.bend as C\n" + MAIN,
    );
    await settled(out, "sub/main.bend");
  });

  test("a comment line moves with the import below it; blank lines go; a header stays", async () => {
    const out = await fixed(
      "# header\nimport ./b.bend as B  # bee\n\n# about a\nimport ./a.bend as A\nimport Base\n" +
        MAIN,
    );
    expect(out).toBe(
      "# header\nimport Base\n# about a\nimport ./a.bend as A\nimport ./b.bend as B  # bee\n" +
        MAIN,
    );
    await settled(out);
  });

  test("a second import of a file goes, and its uses take the first alias", async () => {
    const out = await fixed(
      "import Base\nimport ./a.bend as A\nimport ./a.bend as Again\n\ndef main() -> U32:\n  Again.one()\n",
    );
    expect(out).toBe("import Base\nimport ./a.bend as A\n\ndef main() -> U32:\n  A.one()\n");
    await settled(out);
  });

  test("a file imported through two different paths counts once", async () => {
    const out = await fixed(
      "import Base\nimport ./a.bend as A\nimport a.bend as Again\n\ndef main() -> U32:\n  Again.one()\n",
    );
    expect(out).toBe("import Base\nimport ./a.bend as A\n\ndef main() -> U32:\n  A.one()\n");
  });

  test("a second import Base goes", async () => {
    const out = await fixed("import Base\nimport ./a.bend as A\nimport Base\n" + MAIN);
    expect(out).toBe("import Base\nimport ./a.bend as A\n" + MAIN);
    await settled(out);
  });

  test("a file without imports passes", async () => {
    await settled("type N is Data:\n  Z{}\n");
  });
});
