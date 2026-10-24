// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

import { getCommandOutcome } from "../shared/utils.ts";
import {
  buildRule,
  BUILDS,
  getFindings,
  getFoundOf,
  getFreshFolder,
  getRunOutcome,
} from "./testing.ts";

// Constants
// =========

// The test rules this file runs: tests/<def> runs the def <def> of tests.bend.
const RULES = ["file", "written", "some", "every", "across", "rename"].map(
  (name) => "tests/" + name,
);
const [FILE, WRITTEN, SOME, EVERY, ACROSS, RENAME] = RULES;

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

const getReports = async (
  program: string,
  files: Record<string, string>,
  named: string,
): Promise<string[]> =>
  (await getFindings(program, files, named)).map(({ at, message }) => at + " " + message);

// Side effects
// ============

await Promise.all(RULES.map(buildRule));
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
    const got = await getReports(WRITTEN, { "main.bend": SUGARED }, "main.bend");
    expect(got).toEqual(expect.arrayContaining(written));
    expect(got.filter((x) => !allowed.includes(x))).toEqual([]);
  });

  test("a some-entry program rule keeps what any check finds", async () => {
    expect(await getReports(SOME, ENTRIES, "util.bend")).toEqual([
      "1:1 at 0",
      "1:3 at the count",
      "1:4 at the count",
    ]);
  });

  test("an every-entry program rule keeps what every check finds", async () => {
    expect(await getReports(EVERY, ENTRIES, "util.bend")).toEqual(["1:1 at 0"]);
  });

  test("an entry that reads the file and fails its check leaves the checking to Bend, and says so", async () => {
    const broken = ENTRIES["b.bend"].replace("(U.u() + C.c() : U32)", '"no"');
    const ran = await getRunOutcome(FILE, { ...ENTRIES, "b.bend": broken }, "util.bend");
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
    const ran = await getRunOutcome(
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
    const dir = getFreshFolder();
    await getCommandOutcome(["git", "init", "-q"], dir);
    const util = ENTRIES["util.bend"];
    const ran = await getRunOutcome(
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
    const ran = await getRunOutcome(
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
    const ran = await getRunOutcome(
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
    const ran = await getRunOutcome(
      ACROSS,
      { "main.bend": ENTRIES["a.bend"], "util.bend": util },
      "main.bend",
      ["util.bend", "--json"],
    );
    const getWithoutFolder = (key: string, value: unknown): unknown =>
      key === "path" && typeof value === "string" ? value.replace(/^.*\//, "") : value;
    const getPosition = (line: number, character: number) => ({ line, character });
    const getInsertEdit = (path: string) => ({
      path,
      range: { start: getPosition(0, 0), end: getPosition(0, 0) },
      text: "# fixed\n",
    });
    const getMarkFinding = (path: string, edits: string[]) => ({
      code: "tests/across",
      severity: "hint",
      message: "at 0",
      path,
      range: { start: getPosition(0, 0), end: getPosition(0, 1) },
      fixes: [
        { title: "Mark every file", applicability: "dangerous", edits: edits.map(getInsertEdit) },
      ],
    });
    expect([ran.code, JSON.parse(ran.out, getWithoutFolder), ran.err.trim()]).toEqual([
      0,
      {
        ok: true,
        findings: [getMarkFinding("main.bend", ["main.bend", "util.bend"])],
        suppressed: [getMarkFinding("util.bend", ["util.bend"])],
        skipped: [],
      },
      "bend-lint: 1 finding(s), 1 suppressed",
    ]);
  });

  test("--json gives each file that rules did not run on, and why", async () => {
    const broken = ENTRIES["b.bend"].replace("(U.u() + C.c() : U32)", '"no"');
    const ran = await getRunOutcome(
      FILE,
      { ...ENTRIES, "b.bend": broken, "bad.bend": "import Base\n\ndef bad(\n" },
      "util.bend",
      ["bad.bend", "--json"],
    );
    const getWithoutFolder = (key: string, value: unknown): unknown =>
      (key === "path" || key === "entry") && typeof value === "string"
        ? value.replace(/^.*\//, "")
        : value;
    expect([
      ran.code,
      (JSON.parse(ran.out, getWithoutFolder) as { skipped: unknown }).skipped,
    ]).toEqual([
      0,
      [
        {
          path: "util.bend",
          reason: "unentered",
          entry: "b.bend",
          rules: [],
          message: expect.stringMatching(
            /^bend-lint: Bend's check of the entry \S*b\.bend fails, so /,
          ),
        },
        {
          path: "bad.bend",
          reason: "unloaded",
          message: expect.stringMatching(
            /^bend-lint: Bend does not load \S*bad\.bend, so no rule ran/,
          ),
        },
      ],
    ]);
  });

  test("--json gives an error that ends the run as its one object, with the file it is about", async () => {
    const runner = await getRunOutcome(
      FILE,
      {
        "util.bend": ENTRIES["util.bend"],
        "bend-lint.json": JSON.stringify({ entries: ["nope.bend"] }),
      },
      "util.bend",
      ["--json"],
    );
    const server = await getRunOutcome(
      FILE,
      {
        "util.bend": ENTRIES["util.bend"],
        "bend-lint.json": JSON.stringify({ rules: { "no/such": "warning" } }),
      },
      "util.bend",
      ["--json"],
    );
    expect([runner.code, JSON.parse(runner.out), server.code, JSON.parse(server.out)]).toEqual([
      2,
      {
        ok: false,
        errors: [
          {
            path: expect.stringMatching(/bend-lint\.json$/),
            message: expect.stringMatching(
              /^bend-lint: \S*bend-lint\.json: the entry \S*nope\.bend is not a file$/,
            ),
          },
        ],
      },
      2,
      {
        ok: false,
        errors: [
          {
            path: expect.stringMatching(/bend-lint\.json$/),
            message: expect.stringMatching(/^bend-lint: there is no rule no\/such: /),
          },
        ],
      },
    ]);
  });

  test("--fix-dangerously renames a local name, but no global one: files the check did not read can use it", async () => {
    const ran = await getRunOutcome(
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
    const ran = await getRunOutcome(
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

  test("--overlays lints each overlay's text in place of its file, which need not be on disk", async () => {
    const dir = getFreshFolder();
    const ran = await getRunOutcome(
      WRITTEN,
      { "main.bend": "import Base\n\ndef one() -> U32:\n  1\n" },
      "main.bend",
      ["--overlays", path.join(dir, "new.bend")],
      dir,
      JSON.stringify({
        [path.join(dir, "main.bend")]: "import Base\n\ndef two() -> Nat:\n  2n\n",
        [path.join(dir, "new.bend")]: "import Base\n\ndef three() -> F32:\n  3.0\n",
      }),
    );
    expect(getFoundOf(ran).map(({ file, at, message }) => `${file}:${at} ${message}`)).toEqual([
      "main.bend:3:14 reference Nat",
      "new.bend:3:16 reference F32",
    ]);
  });

  test("--overlays gives an import's overlay to the check of each file that imports it", async () => {
    const dir = getFreshFolder();
    const ran = await getRunOutcome(
      WRITTEN,
      {
        "main.bend": "import Base\nimport ./util.bend as U\n\ndef m() -> U32:\n  U.v()\n",
        "util.bend": "import Base\n\ndef u() -> U32:\n  1\n",
      },
      "main.bend",
      ["--overlays"],
      dir,
      JSON.stringify({ [path.join(dir, "util.bend")]: "import Base\n\ndef v() -> U32:\n  2\n" }),
    );
    expect([ran.code, getFoundOf(ran).map(({ at, message }) => `${at} ${message}`)]).toEqual([
      0,
      ["4:12 reference U32", "5:3 reference U.v"],
    ]);
  });

  test("--overlays reads a JSON object of paths to texts, or the run ends", async () => {
    const ran = await getRunOutcome(
      FILE,
      { "main.bend": SUGARED },
      "main.bend",
      ["--overlays"],
      getFreshFolder(),
      "[]",
    );
    expect([ran.code, ran.err.trim()]).toEqual([
      2,
      "bend-lint: --overlays reads a JSON object of paths to texts on stdin",
    ]);
  });

  test("--fix-dangerously with --overlays ends the run: a fix writes the file on disk", async () => {
    const dir = getFreshFolder();
    const ran = await getRunOutcome(
      FILE,
      { "main.bend": SUGARED },
      "main.bend",
      ["--overlays", "--fix-dangerously"],
      dir,
      JSON.stringify({ [path.join(dir, "main.bend")]: SUGARED }),
    );
    expect([ran.code, ran.err.trim()]).toEqual([
      2,
      "bend-lint: --fix-dangerously does not go with --overlays: a fix writes the file on disk",
    ]);
  });

  test("--report writes how the run ran: its backend, its checks from the cache or not, and no source text", async () => {
    const dir = getFreshFolder();
    const first = await getRunOutcome(
      FILE,
      { "util.bend": ENTRIES["util.bend"] },
      "util.bend",
      ["--report", path.join(dir, "first.json")],
      dir,
    );
    const again = await getRunOutcome(
      FILE,
      {},
      "util.bend",
      ["--report", path.join(dir, "again.json")],
      dir,
    );
    const [one, two] = ["first.json", "again.json"].map((name) =>
      fs.readFileSync(path.join(dir, name), "utf8"),
    );
    const getFacts = (text: string): unknown[] => {
      const report = JSON.parse(text) as {
        backend: string;
        cache: { checks: unknown };
        exitCode: number;
      };
      return [report.backend, report.cache.checks, report.exitCode];
    };
    expect([
      first.code,
      again.code,
      getFacts(one),
      getFacts(two),
      one.includes("def u()") || two.includes("def u()"),
    ]).toEqual([
      0,
      0,
      [expect.stringMatching(/^(native|javascript)$/), { cached: 0, checked: 1 }, 0],
      [expect.stringMatching(/^(native|javascript)$/), { cached: 1, checked: 0 }, 0],
      false,
    ]);
  });
});
