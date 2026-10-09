// Moves package.json's bendRelease to Bend's newest release, only if the
// tests, typecheck and lint pass on a fresh clone of it.

// Imports
// =======

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

import { PIN } from "../src/seam.ts";

// Constants
// =========

const ROOT = path.resolve(import.meta.dir, "..");
const PACKAGE = path.join(ROOT, "package.json");
const REPO = "https://github.com/bendlang/bend";

// Functions
// =========

// Runs `cmd`, shown on this terminal; throws if it fails.
const run = (cmd: string[], env: Record<string, string> = {}): void => {
  const out = spawnSync(cmd[0], cmd.slice(1), {
    cwd: ROOT,
    stdio: "inherit",
    env: { ...process.env, ...env },
  });
  if (out.status !== 0) throw new Error(cmd.join(" ") + " failed");
};

// Side effects
// ============

const listed = spawnSync("git", ["ls-remote", "--tags", "--refs", REPO, "refs/tags/v*"], {
  encoding: "utf8",
});
if (listed.status !== 0) throw new Error("cannot list Bend's releases: " + listed.stderr);
const newest = [...listed.stdout.matchAll(/refs\/tags\/v(\d+)\.(\d+)\.(\d+)$/gm)]
  .map((m) => [Number(m[1]), Number(m[2]), Number(m[3])])
  .sort((a, b) => b[0] - a[0] || b[1] - a[1] || b[2] - a[2])
  .map((v) => "v" + v.join("."))[0];
if (newest === undefined) throw new Error("Bend has no release tags");
if (newest === PIN) {
  console.log("bendRelease is already " + PIN);
} else {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "bend-lint-sync-"));
  try {
    run(["git", "clone", "--quiet", "--depth", "1", "--branch", newest, REPO, dir]);
    run(["bun", "test"], { BEND_DIR: dir });
    run(["bun", "run", "typecheck"], { BEND_DIR: dir });
    run(["bun", "run", "lint"], { BEND_DIR: dir });
    const text = fs.readFileSync(PACKAGE, "utf8");
    fs.writeFileSync(
      PACKAGE,
      text.replace(`"bendRelease": "${PIN}"`, `"bendRelease": "${newest}"`),
    );
    console.log("bendRelease moved from " + PIN + " to " + newest);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}
