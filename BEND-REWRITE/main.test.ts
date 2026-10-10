// Imports
// =======

import { afterAll, describe, expect, setDefaultTimeout, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { lintIn } from "./testing.ts";
import type { Found } from "./testing.ts";

// Constants
// =========

const dir = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), "bend-rewrite-main-")));

const LINT = path.posix.relative(
  dir.replaceAll("\\", "/"),
  fileURLToPath(new URL("./main.bend", import.meta.url)).replaceAll("\\", "/"),
);

const UNUSED = fileURLToPath(new URL("./rules/no-unused/imports.bend", import.meta.url));

// A rule of `scope`, needing declarations, whose run reports `body`, a list
// of findings that can use `path` (its file) and `n` (how many files it saw).
const rule = (id: string, scope: string, body: string): string =>
  [
    "import Base",
    `import ${LINT} as Lint`,
    "",
    "def at(path: String, message: String) -> Lint.Finding:",
    "  Lint.Finding{Lint.Hint{}, message, Lint.BendSourceSpan{path, 0, 0}, []}",
    "",
    "def each(sources: List<&2, Lint.SourceDeclarations>, +message: String) -> List<&2, Lint.Finding>:",
    "  match sources:",
    "    case Nil{}:",
    "      []",
    "    case Con{Lint.SourceDeclarations{path, declarations}, t}:",
    "      at(path, message) <> each(t, message)",
    "",
    "def others(sources: List<&2, Lint.BendSource>, +root: String) -> List<&2, Lint.Finding>:",
    "  match sources:",
    "    case Nil{}:",
    "      []",
    "    case Con{Lint.BendSource{+path, text, lines}, t}:",
    '      Lint.get_kept(Lint.Finding, Bool.not(String.eq(path, root)), at(path, "here"), others(t, root))',
    "",
    "def run(input: Lint.RuleInput) -> List<&2, Lint.Finding>:",
    "  match input:",
    "    case Lint.RuleInput{Lint.BendSource{+path, text, lines}, sources, options, prior, +declarations}:",
    "      +n = Nat.show(List.length(&2, Lint.SourceDeclarations, declarations))",
    `      ${body}`,
    "",
    "def rules() -> List<&1, Lint.Rule>:",
    `  [Lint.Rule{"${id}", Lint.${scope}{}, [], [], [Lint.DeclarationsNeed{}], run}]`,
    "",
  ].join("\n");

const RULES = {
  // Reports, at the start of its file, how many files it saw.
  "seen.bend": rule("test/seen", "FileScope", "[at(path, n)]"),
  // Reports in each file it saw, with how many it saw.
  "everywhere.bend": rule("test/everywhere", "ProgramSomeScope", "each(declarations, n)"),
  // A file rule that reports in every other file the check read.
  "elsewhere.bend": rule("test/elsewhere", "FileScope", "others(sources, path)"),
};

// main.bend imports util.bend, which imports other.bend and does not use it.
const PROGRAM = {
  "main.bend": "import Base\nimport ./util.bend as U\n\ndef main() -> U32:\n  U.k()\n",
  "util.bend": "import Base\nimport ./other.bend as O\n\ndef k() -> U32:\n  1\n",
  "other.bend": "import Base\n\ndef z() -> U32:\n  0\n",
};

// Functions
// =========

// What the rewrite reports for main.bend with the rule files `rules`.
const found = (rules: string[], ...flags: string[]): Array<Omit<Found, "text">> =>
  lintIn(dir, { ...RULES, ...PROGRAM }, "main.bend", [
    ...rules.flatMap((r) => ["--rules", path.isAbsolute(r) ? r : path.join(dir, r)]),
    ...flags,
  ]).map(({ code, file, message, fixes }) => ({ code, file, message, fixes }));

// Side effects
// ============

setDefaultTimeout(300_000);

afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));

describe("rule scope", () => {
  test("a file rule runs on the named file, and sees only it", () => {
    expect(found(["seen.bend"])).toEqual([
      { code: "test/seen", file: "main.bend", message: "1", fixes: [] },
    ]);
  });

  test("with --imports, a file rule runs on each file of the program, and sees only it", () => {
    expect(found(["seen.bend"], "--imports")).toEqual([
      { code: "test/seen", file: "main.bend", message: "1", fixes: [] },
      { code: "test/seen", file: "util.bend", message: "1", fixes: [] },
      { code: "test/seen", file: "other.bend", message: "1", fixes: [] },
    ]);
  });

  test("a program rule sees every file, and shows only what it finds in the named one", () => {
    expect(found(["everywhere.bend"])).toEqual([
      { code: "test/everywhere", file: "main.bend", message: "3", fixes: [] },
    ]);
  });

  test("with --imports, a program rule's findings show in every file", () => {
    expect(found(["everywhere.bend"], "--imports")).toEqual([
      { code: "test/everywhere", file: "main.bend", message: "3", fixes: [] },
      { code: "test/everywhere", file: "util.bend", message: "3", fixes: [] },
      { code: "test/everywhere", file: "other.bend", message: "3", fixes: [] },
    ]);
  });

  test("a file rule that reports in another file crashes, and its findings are dropped", () => {
    const out = found(["elsewhere.bend"]);
    expect(out.map((f) => [f.code, f.file])).toEqual([["bend-lint/rule-crash", "main.bend"]]);
    expect(out[0].message).toStartWith("test/elsewhere: it reported in ");
  });

  test("--no-imports undoes --imports", () => {
    expect(found(["seen.bend"], "--imports", "--no-imports").map((f) => f.file)).toEqual([
      "main.bend",
    ]);
  });
});

describe("Safe fixes", () => {
  test("with --imports, a Safe fix in an imported file is checked and offered", () => {
    expect(found([UNUSED], "--imports")).toEqual([
      {
        code: "no-unused/imports",
        file: "util.bend",
        message: "Remove the import O: nothing uses it.",
        fixes: ["Remove the import [safe]"],
      },
    ]);
  });
});
