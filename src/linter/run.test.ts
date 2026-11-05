// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

import { getCommandOutcome } from "../shared/utils.ts";
import { buildRule, BUILDS, getFreshFolder, getRunOutcome } from "./testing.ts";

// Constants
// =========

// The test rules this file runs: tests/<def> runs the def <def> of tests.bend.
const RULES = ["file", "across", "rename"].map((name) => "tests/" + name);
const [FILE, ACROSS, RENAME] = RULES;

// A file that imports util.bend.
const FILES = {
  "util.bend": "import Base\n\ndef u() -> U32:\n  1\n",
  "a.bend": "import Base\nimport ./util.bend as U\n\ndef a() -> U32:\n  U.u()\n",
};

// Side effects
// ============

await Promise.all(RULES.map(buildRule));
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)("run", () => {
  test("with no file, it lints the .bend files git lists, but none in node_modules or a hidden folder", async () => {
    const dir = getFreshFolder();
    await getCommandOutcome(["git", "init", "-q"], dir);
    const util = FILES["util.bend"];
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
      { "main.bend": FILES["a.bend"], "util.bend": FILES["util.bend"] },
      "main.bend",
      ["--fix-dangerously"],
    );
    expect([ran.files, ran.out.trim().split("\n").at(-1)]).toEqual([
      { "main.bend": "# fixed\n" + FILES["a.bend"], "util.bend": "# fixed\n" + FILES["util.bend"] },
      "bend-lint: 1 finding(s), 1 fixed",
    ]);
  });

  test("--report writes how the run ran: its backend, its checks from the cache or not, and no source text", async () => {
    const dir = getFreshFolder();
    const first = await getRunOutcome(
      FILE,
      { "util.bend": FILES["util.bend"] },
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
