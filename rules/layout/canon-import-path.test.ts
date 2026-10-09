import { afterAll, describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { applyFixes, createLinter } from "../../src/lint.ts";
import type { LintResult } from "../../src/lint.ts";
import { unwrap } from "../../src/result.ts";

const linter = unwrap(await createLinter());
const rules = unwrap(
  await linter.loadRules([fileURLToPath(new URL("./canon-import-path.bend", import.meta.url))]),
);
const dir = fs
  .realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "bend-imports-")))
  .replaceAll("\\", "/");
afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));
const fixture = (name: string, text: string): string => {
  const file = path.posix.join(dir, name);
  fs.mkdirSync(path.posix.dirname(file), { recursive: true });
  fs.writeFileSync(file, text);
  return file;
};
const LEAF = "import Base\n\ndef leaf() -> U32:\n  1\n";
fixture("x.bend", LEAF);
fixture("sub/y.bend", LEAF);

const lint = async (name: string, imports: string): Promise<LintResult> =>
  unwrap(
    await linter.lint(
      fixture(name, "import Base\n" + imports + "\ndef main() -> U32:\n  1\n"),
      rules,
      { config: {} },
    ),
  );

// Each finding as the path it flags and the path its fix writes.
const flagged = async (name: string, imports: string): Promise<string[][]> => {
  const res = await lint(name, imports);
  expect(res.diags.filter((d) => d.code !== "layout/canon-import-path")).toEqual([]);
  return res.diags.map((d) => [
    d.span!.file.text.slice(d.span!.beg, d.span!.end),
    d.fixes[0].edits[0].text,
  ]);
};

describe("layout/canon-import-path", () => {
  test("shortest paths that start with ./ or ../ pass, and so does Base", async () => {
    expect(await flagged("main.bend", "import ./x.bend as X\nimport ./sub/y.bend as Y\n")).toEqual(
      [],
    );
    expect(await flagged("sub/main.bend", "import ../x.bend as X\nimport ./y.bend as Y\n")).toEqual(
      [],
    );
  });

  test("a path without ./ gets it", async () => {
    expect(await flagged("main.bend", "import x.bend as X\nimport sub/y.bend as Y\n")).toEqual([
      ["x.bend", "./x.bend"],
      ["sub/y.bend", "./sub/y.bend"],
    ]);
  });

  test("a longer path gets the shortest one", async () => {
    const name = path.posix.basename(dir);
    expect(await flagged("main.bend", `import ../${name}/x.bend as X\n`)).toEqual([
      [`../${name}/x.bend`, "./x.bend"],
    ]);
    expect(
      await flagged("sub/main.bend", "import ./../x.bend as X\nimport ../sub/y.bend as Y\n"),
    ).toEqual([
      ["./../x.bend", "../x.bend"],
      ["../sub/y.bend", "./y.bend"],
    ]);
  });

  test("an absolute path gets the relative one", async () => {
    const absolute = dir.replace(/^[A-Za-z]:/, "") + "/sub/y.bend";
    expect(await flagged("main.bend", `import ${absolute} as Y\n`)).toEqual([
      [absolute, "./sub/y.bend"],
    ]);
  });

  test("a path through a symlink gets the real one", async () => {
    fs.symlinkSync(path.posix.join(dir, "sub"), path.posix.join(dir, "link"), "junction");
    expect(await flagged("main.bend", "import ./link/y.bend as Y\n")).toEqual([
      ["./link/y.bend", "./sub/y.bend"],
    ]);
  });

  test("the fix changes only the path, and the fixed file passes", async () => {
    const res = await lint("main.bend", "import   x.bend   as X  # the leaf\n");
    const { text } = applyFixes(res.root!, res.diags);
    expect(text).toBe(
      "import Base\nimport   ./x.bend   as X  # the leaf\n\ndef main() -> U32:\n  1\n",
    );
    fs.writeFileSync(res.root!.path, text);
    expect(unwrap(await linter.lint(res.root!.path, rules, { config: {} })).diags).toEqual([]);
  });
});
