// Writes what bend-lint ships into an empty folder. api/ is the rule API as BendHub has it (API
// in seam.ts): src/linter/lint.bend and the files it imports, at their paths from src/, with the
// license beside lint.bend. npm/ is the npm package: the files of this repo that a project runs,
// whose Bend files import the rule API from BendHub. It prints api/'s hash. With --publish, it
// then publishes api/ to BendHub, which is public and permanent, as `bend login` lets it.
//
// usage: bun run ship <empty folder> [--publish]

// Imports
// =======

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

import { API, closure, IMPORT } from "../linter/seam.ts";
import { getBendCli, tryGetBend2SourceUrl } from "../shared/bend2.ts";
import { unwrap } from "../shared/result.ts";
import { getPathWithForwardSlashes, getSha256Hex } from "../shared/utils.ts";

// Constants
// =========

const ROOT = path.resolve(import.meta.dir, "..", "..");
const SRC = path.join(ROOT, "src");

// A project runs these files of this repo, but those it leaves out: tests, these scripts, the
// test rules, and the rule API, which comes from BendHub.
const SHIPPED = /^(src\/|bend-lint-rules\/|package\.json$|README\.md$|LICENSE$)/;
const LEFT_OUT = /(\.test\.ts$|^src\/meta\/|^src\/linter\/(testing\.ts|tests\.bend)$)/;

// Functions
// =========

// The rule API's files: their paths from src/ to their texts.
export const apiOf = (): Map<string, string> =>
  new Map([
    ...closure(path.join(SRC, "linter", "lint.bend")).map((file): [string, string] => [
      getPathWithForwardSlashes(path.relative(SRC, file)),
      fs.readFileSync(file, "utf8"),
    ]),
    ["linter/LICENSE", fs.readFileSync(path.join(ROOT, "LICENSE"), "utf8")],
  ]);

// The hash of the package of `files` (paths to texts), as `bend --publish` makes it.
export const hashOf = (files: Map<string, string>): string =>
  "0x" +
  getSha256Hex(
    [...files]
      .sort(([a], [b]) => (a < b ? -1 : 1))
      .map(([at, text]) => getSha256Hex(text.replace(/^﻿/, "")) + " " + at + "\n")
      .join(""),
  ).slice(0, 32);

// `text`, of the .bend file at `file`, with each import of a rule API file from BendHub instead.
const shipped = (file: string, text: string, api: Map<string, string>): string =>
  text.replace(IMPORT, (line: string, relative: string) => {
    const at = getPathWithForwardSlashes(
      path.relative(SRC, path.resolve(path.dirname(file), relative)),
    );
    return api.has(at) ? line.replace(relative, API + "/" + at) : line;
  });

// Writes the npm package into `dir`: the shipped files of this repo, as git lists them.
export const writeNpm = (dir: string, api: Map<string, string>): void => {
  const listed = spawnSync("git", ["ls-files", "-z"], { cwd: ROOT, encoding: "utf8" });
  if (listed.status !== 0) throw new Error("git ls-files failed: " + listed.stderr);
  listed.stdout
    .split("\0")
    .filter((p) => SHIPPED.test(p) && !LEFT_OUT.test(p) && !api.has(p.replace(/^src\//, "")))
    .forEach((p) => {
      const from = path.join(ROOT, p);
      const to = path.join(dir, p);
      fs.mkdirSync(path.dirname(to), { recursive: true });
      if (p.endsWith(".bend")) {
        fs.writeFileSync(to, shipped(from, fs.readFileSync(from, "utf8"), api));
      } else {
        fs.copyFileSync(from, to);
      }
    });
};

// Writes `files` (paths to texts) into `dir`.
export const writeFiles = (dir: string, files: Map<string, string>): void =>
  files.forEach((text, at) => {
    const to = path.join(dir, at);
    fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.writeFileSync(to, text);
  });

// Side effects
// ============

if (import.meta.main) {
  const [dir, flag] = process.argv.slice(2);
  if (dir === undefined || (flag !== undefined && flag !== "--publish")) {
    console.error("usage: bun run ship <empty folder> [--publish]");
    process.exit(2);
  }
  if (fs.existsSync(dir) && fs.readdirSync(dir).length > 0) {
    console.error("ship writes into an empty folder, and " + dir + " is not");
    process.exit(2);
  }
  const api = apiOf();
  writeFiles(path.join(dir, "api"), api);
  writeNpm(path.join(dir, "npm"), api);
  console.log(API + " is " + hashOf(api));
  if (flag === "--publish") {
    const bend = getBendCli(unwrap(await tryGetBend2SourceUrl()));
    const entry = path.join(dir, "api", "linter", "lint.bend");
    const published = spawnSync(
      bend.cmd[0] ?? "",
      [...bend.cmd.slice(1), entry, "--publish", API],
      { stdio: "inherit", env: { ...process.env, ...bend.env } },
    );
    process.exit(published.status ?? 1);
  }
}
