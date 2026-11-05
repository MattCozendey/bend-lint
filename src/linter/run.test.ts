// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

import { buildRule, BUILDS, getFreshFolder, getRunOutcome } from "./testing.ts";

// Constants
// =========

// The test rule this file runs: tests/file runs the def file of tests.bend.
const FILE = "tests/file";

// A file of one def.
const UTIL = "import Base\n\ndef u() -> U32:\n  1\n";

// Side effects
// ============

await buildRule(FILE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)("run", () => {
  test("--report writes how the run ran: its backend, its checks from the cache or not, and no source text", async () => {
    const dir = getFreshFolder();
    const first = await getRunOutcome(
      FILE,
      { "util.bend": UTIL },
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
