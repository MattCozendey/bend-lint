// Moves package.json's bendRelease to Bend's newest release, only if the
// tests, typecheck and lint pass with it. It runs on Linux or macOS: on
// Windows, bend-lint uses bendWindows instead.

// Imports
// =======

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

import pkg from "../../package.json" with { type: "json" };

// Constants
// =========

const ROOT = path.resolve(import.meta.dir, "..", "..");
const PACKAGE = path.join(ROOT, "package.json");

// Functions
// =========

// Runs `cmd`, shown on this terminal; whether it passed.
const passes = (cmd: string[]): boolean =>
  spawnSync(cmd[0], cmd.slice(1), { cwd: ROOT, stdio: "inherit" }).status === 0;

// Side effects
// ============

if (process.platform === "win32") {
  throw new Error("run sync-bend on Linux or macOS: on Windows, bend-lint uses bendWindows");
}
const [owner, repo, tag] = pkg.bendRelease.split("/");
const listed = spawnSync(
  "git",
  ["ls-remote", "--tags", "--refs", `https://github.com/${owner}/${repo}`, "refs/tags/v*"],
  { encoding: "utf8" },
);
if (listed.status !== 0) throw new Error("cannot list Bend's releases: " + listed.stderr);
const newest = [...listed.stdout.matchAll(/refs\/tags\/v(\d+)\.(\d+)\.(\d+)$/gm)]
  .map((m) => [Number(m[1]), Number(m[2]), Number(m[3])])
  .sort((a, b) => b[0] - a[0] || b[1] - a[1] || b[2] - a[2])
  .map((v) => "v" + v.join("."))[0];
if (newest === undefined) throw new Error("Bend has no release tags");
if (newest === tag) {
  console.log("bendRelease is already " + pkg.bendRelease);
} else {
  const text = fs.readFileSync(PACKAGE, "utf8");
  const moved = `${owner}/${repo}/${newest}`;
  fs.writeFileSync(
    PACKAGE,
    text.replace(`"bendRelease": "${pkg.bendRelease}"`, `"bendRelease": "${moved}"`),
  );
  const passed = [
    ["bun", "test", "--parallel"],
    ["bun", "run", "typecheck"],
    ["bun", "run", "lint"],
  ].every(passes);
  if (!passed) {
    fs.writeFileSync(PACKAGE, text);
    throw new Error(`the checks fail with ${moved}; bendRelease stays ${pkg.bendRelease}`);
  }
  console.log("bendRelease moved from " + pkg.bendRelease + " to " + moved);
}
