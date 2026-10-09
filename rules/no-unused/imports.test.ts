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
  await linter.loadRules([fileURLToPath(new URL("./imports.bend", import.meta.url))]),
);
const dir = fs.realpathSync
  .native(fs.mkdtempSync(path.join(os.tmpdir(), "bend-unused-")))
  .replaceAll("\\", "/");
afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));
const fixture = (name: string, text: string): string => {
  const file = path.posix.join(dir, name);
  fs.writeFileSync(file, text);
  return file;
};
fixture("leaf.bend", "import Base\n\ndef one() -> U32:\n  1\n");
fixture("other.bend", "import Base\n\ndef two() -> U32:\n  2\n");
fixture("law.bend", "import Base\n\nlaw L:\n  for x: U32\n  U32\n");
fixture("fill.bend", "import Base\nimport ./law.bend as B\n\ndef B.L(x):\n  x\n");
fixture("relay.bend", "import Base\nimport ./fill.bend as F\n\ndef two() -> U32:\n  2\n");

const lint = async (text: string): Promise<LintResult> =>
  unwrap(await linter.lint(fixture("main.bend", text), rules, { config: {} }));

// Each finding's text, and the file its fixes give.
const fixed = async (text: string): Promise<{ flagged: string[]; text: string }> => {
  const res = await lint(text);
  expect(res.diags.filter((d) => d.code !== "no-unused/imports").map(linter.render)).toEqual([]);
  return {
    flagged: res.diags.map((d) => d.span!.file.text.slice(d.span!.beg, d.span!.end)),
    text: applyFixes(res.root!, res.diags).text,
  };
};

// The fixed file passes Bend's check, and the rule finds nothing more.
const settled = async (text: string): Promise<void> => {
  expect((await lint(text)).diags.map(linter.render)).toEqual([]);
};

describe("no-unused/imports", () => {
  test("imports whose alias is used pass, Base included", async () => {
    await settled("import Base\nimport ./leaf.bend as L\n\ndef main() -> U32:\n  L.one()\n");
  });

  test("an unused import is removed with its whole line", async () => {
    const out = await fixed(
      "import Base\nimport ./other.bend as O  # the other\nimport ./leaf.bend as L\n\ndef main() -> U32:\n  L.one()\n",
    );
    expect(out.flagged).toEqual(["O"]);
    expect(out.text).toBe(
      "import Base\nimport ./leaf.bend as L\n\ndef main() -> U32:\n  L.one()\n",
    );
  });

  test("an unused import Base is removed", async () => {
    const out = await fixed("import Base\n\ntype N is Data:\n  Z{}\n\ndef main() -> N:\n  Z{}\n");
    expect(out.flagged).toEqual(["Base"]);
    expect(out.text).toBe("\ntype N is Data:\n  Z{}\n\ndef main() -> N:\n  Z{}\n");
    await settled(out.text);
  });

  test("an import that only loads a fill of a law is used", async () => {
    await settled(
      "import Base\nimport ./law.bend as B\nimport ./fill.bend as F\n\ndef main() -> U32:\n  B.L(1)\n",
    );
  });

  test("an import that loads a fill through another import is used", async () => {
    await settled(
      "import Base\nimport ./law.bend as B\nimport ./relay.bend as R\n\ndef main() -> U32:\n  B.L(1)\n",
    );
  });

  test("the fixed file passes Bend's check", async () => {
    const out = await fixed(
      "import Base\nimport ./other.bend as O\nimport ./leaf.bend as L\n\ndef main() -> U32:\n  L.one()\n",
    );
    expect(out.flagged).toEqual(["O"]);
    await settled(out.text);
  });
});
