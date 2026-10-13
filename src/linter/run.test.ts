// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { getCommandOutcome } from "../shared/utils.ts";
import { build, BUILDS, fresh, lint, run } from "./testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when bend does not run.
const [FILE, WRITTEN, SOME, EVERY, ACROSS, RENAME] = BUILDS
  ? await Promise.all(
      ["file", "written", "some", "every", "across", "rename"].map((name) =>
        build("tests/" + name),
      ),
    )
  : ["", "", "", "", "", ""];

// A file with sugar the parser expands: a do-block, `A & B`, an operator.
const SUGARED =
  "import Base\n\ndef say(m: IO(Unit)) -> IO(U32):\n  do IO<U32>:\n    m\n    n : U32 <- IO.pure(U32, 3)\n    return n\n\ndef both(-A: Type, -B: Type) -> Type:\n  A & B\n\ndef twice(+k: U32) -> U32:\n  (k * k : U32)\n";

// Two entries that import util.bend, one of them through a third file.
const ENTRIES = {
  "util.bend": "import Base\n\ndef u() -> U32:\n  1\n",
  "a.bend": "import Base\nimport ./util.bend as U\n\ndef a() -> U32:\n  U.u()\n",
  "b.bend":
    "import Base\nimport ./util.bend as U\nimport ./c.bend as C\n\ndef b() -> U32:\n  (U.u() + C.c() : U32)\n",
  "c.bend": "import Base\n\ndef c() -> U32:\n  2\n",
  "bend-lint.json": JSON.stringify({ entries: ["a.bend", "b.bend"] }),
};

// Functions
// =========

const found = async (
  program: string,
  files: Record<string, string>,
  named: string,
): Promise<string[]> =>
  (await lint(program, files, named)).map(({ at, message }) => at + " " + message);

// Side effects
// ============

setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)("run", () => {
  test("a node has a range only where the file writes it", async () => {
    const written = [
      "3:12 call",
      "3:12 reference IO",
      "3:15 reference Unit",
      "3:25 call",
      "3:25 reference IO",
      "3:28 reference U32",
      "4:9 reference U32",
      "6:5 lambda n",
      "6:9 reference U32",
      "6:16 call",
      "6:16 reference IO.pure",
      "6:24 reference U32",
      "7:5 call",
      "10:3 call",
      "12:15 reference U32",
      "12:23 reference U32",
      "13:4 call",
      "13:6 reference *",
    ];
    // The do-block's `IO` is written too, but its parser keeps no term of it.
    const allowed = [...written, "4:6 reference IO"];
    const got = await found(WRITTEN, { "main.bend": SUGARED }, "main.bend");
    expect(got).toEqual(expect.arrayContaining(written));
    expect(got.filter((x) => !allowed.includes(x))).toEqual([]);
  });

  test("a some-entry program rule keeps what any check finds", async () => {
    expect(await found(SOME, ENTRIES, "util.bend")).toEqual([
      "1:1 at 0",
      "1:3 at the count",
      "1:4 at the count",
    ]);
  });

  test("an every-entry program rule keeps what every check finds", async () => {
    expect(await found(EVERY, ENTRIES, "util.bend")).toEqual(["1:1 at 0"]);
  });

  test("an entry that reads the file and fails its check leaves the checking to Bend, and says so", async () => {
    const broken = ENTRIES["b.bend"].replace("(U.u() + C.c() : U32)", '"no"');
    const ran = await run(FILE, { ...ENTRIES, "b.bend": broken }, "util.bend");
    expect([ran.code, ran.out.trim().split("\n"), ran.err.trim().split("\n")]).toEqual([
      0,
      [
        expect.stringMatching(/util\.bend:1:1: hint tests\/file: linted$/),
        "bend-lint: 1 finding(s)",
      ],
      [
        expect.stringMatching(
          /^bend-lint: Bend's check of the entry \S*b\.bend fails, so \S*util\.bend was linted without it; `bend <file> --check-only` says why$/,
        ),
      ],
    ]);
  });

  test("each file the paths and globs name is linted once, in turn, with one summary", async () => {
    const ran = await run(
      FILE,
      { "a.bend": ENTRIES["a.bend"], "util.bend": ENTRIES["util.bend"] },
      "util.bend",
      ["*.bend"],
    );
    expect([
      ran.code,
      ran.out
        .trim()
        .split("\n")
        .map((line) => line.replace(/^.*\/(?=[\w.]+:\d)/, "")),
    ]).toEqual([
      0,
      [
        "util.bend:1:1: hint tests/file: linted",
        "a.bend:1:1: hint tests/file: linted",
        "bend-lint: 2 finding(s)",
      ],
    ]);
  });

  test("with no file, it lints the .bend files git lists, but none in node_modules or a hidden folder", async () => {
    const dir = fresh();
    await getCommandOutcome(["git", "init", "-q"], dir);
    const util = ENTRIES["util.bend"];
    const ran = await run(
      FILE,
      {
        ".gitignore": "ignored/\n# run links it here\nbend-lint-rules\n",
        "a.bend": util,
        "sub/b.bend": util,
        "ignored/c.bend": util,
        "node_modules/d.bend": util,
        ".hidden/e.bend": util,
      },
      undefined,
      [],
      dir,
    );
    expect([
      ran.code,
      ran.out
        .trim()
        .split("\n")
        .map((line) => line.replace(/^.*\/(?=[\w.]+:\d)/, "")),
    ]).toEqual([
      0,
      [
        "a.bend:1:1: hint tests/file: linted",
        "b.bend:1:1: hint tests/file: linted",
        "bend-lint: 2 finding(s)",
      ],
    ]);
  });

  test("an entry that is not a file ends the run, and says which", async () => {
    const ran = await run(
      FILE,
      {
        "util.bend": ENTRIES["util.bend"],
        "bend-lint.json": JSON.stringify({ entries: ["nope.bend"] }),
      },
      "util.bend",
    );
    expect([ran.code, ran.out, ran.err.trim()]).toEqual([
      2,
      "",
      expect.stringMatching(
        /^bend-lint: .*\/bend-lint\.json: the entry .*\/nope\.bend is not a file$/,
      ),
    ]);
  });

  test("a file Bend does not load is not linted, it says so, and the others are linted", async () => {
    const ran = await run(
      FILE,
      { "bad.bend": "import Base\n\ndef bad(\n", "util.bend": ENTRIES["util.bend"] },
      "bad.bend",
      ["util.bend"],
    );
    expect([
      ran.code,
      ran.err.includes("Bend does not load"),
      ran.out.includes("util.bend:1:1: hint tests/file: linted"),
    ]).toEqual([0, true, true]);
  });

  test("--json prints one object: the findings with their fixes' edits, and those suppressed", async () => {
    const util =
      "# bend-lint: disable-file tests/across -- kept not-expected-because: it is not always found\n" +
      ENTRIES["util.bend"];
    const ran = await run(
      ACROSS,
      { "main.bend": ENTRIES["a.bend"], "util.bend": util },
      "main.bend",
      ["util.bend", "--json"],
    );
    const named = (key: string, value: unknown): unknown =>
      key === "path" && typeof value === "string" ? value.replace(/^.*\//, "") : value;
    const at = (line: number, character: number) => ({ line, character });
    const insert = (path: string) => ({
      path,
      range: { start: at(0, 0), end: at(0, 0) },
      text: "# fixed\n",
    });
    const mark = (path: string, edits: string[]) => ({
      code: "tests/across",
      severity: "hint",
      message: "at 0",
      path,
      range: { start: at(0, 0), end: at(0, 1) },
      fixes: [{ title: "Mark every file", applicability: "dangerous", edits: edits.map(insert) }],
    });
    expect([ran.code, JSON.parse(ran.out, named), ran.err.trim()]).toEqual([
      0,
      {
        ok: true,
        findings: [mark("main.bend", ["main.bend", "util.bend"])],
        suppressed: [mark("util.bend", ["util.bend"])],
      },
      "bend-lint: 1 finding(s), 1 suppressed",
    ]);
  });

  test("--fix-dangerously renames a local name, but no global one: files the check did not read can use it", async () => {
    const ran = await run(
      RENAME,
      { "main.bend": "import Base\n\ndef foo(foo: U32) -> U32:\n  foo\n" },
      "main.bend",
      ["--fix-dangerously"],
    );
    expect([ran.files["main.bend"], ran.out.trim().split("\n").at(-1)]).toEqual([
      "import Base\n\ndef foo(bar: U32) -> U32:\n  bar\n",
      "bend-lint: 2 finding(s), 1 fixed",
    ]);
  });

  test("--fix-dangerously makes a fix whole, in each file it edits", async () => {
    const ran = await run(
      ACROSS,
      { "main.bend": ENTRIES["a.bend"], "util.bend": ENTRIES["util.bend"] },
      "main.bend",
      ["--fix-dangerously"],
    );
    expect([ran.files, ran.out.trim().split("\n").at(-1)]).toEqual([
      {
        "main.bend": "# fixed\n" + ENTRIES["a.bend"],
        "util.bend": "# fixed\n" + ENTRIES["util.bend"],
      },
      "bend-lint: 1 finding(s), 1 fixed",
    ]);
  });
});
