// Writes what bend-lint ships into an empty folder, each part as it goes out:
// - api/: the rule API, as the BendHub package API in seam.ts: src/linter/lint.bend and the files
//   it imports, at their paths from src/.
// - rules/: bend-lint's own rules, as the BendHub package DEFAULTS in seam.ts: each at its path
//   from bend-lint-rules/, the other files of this repo they import under lib/, at their paths from
//   src/, and rules.bend, which imports every rule.
// - npm/: the npm package: the files of this repo that a project runs, at their paths.
// Their Bend files import the rule API from BendHub, and each BendHub package has the license
// beside its entry. It prints the hashes of the BendHub packages. With --publish, it then
// publishes them, which is public and permanent, as `bend login` lets it.
//
// usage: bun run ship <empty folder> [--publish]

// Imports
// =======

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

import { API, closure, DEFAULTS, IMPORT } from "../linter/seam.ts";
import { getBendCli, tryGetBend2SourceUrl } from "../shared/bend2.ts";
import { unwrap } from "../shared/result.ts";
import { getPathWithForwardSlashes, getSha256Hex } from "../shared/utils.ts";

// Constants
// =========

const ROOT = path.resolve(import.meta.dir, "..", "..");
const SRC = path.join(ROOT, "src");
const RULES = path.join(ROOT, "bend-lint-rules");
const LICENSE = fs.readFileSync(path.join(ROOT, "LICENSE"), "utf8");

// The rule API's files.
const API_FILES = new Set(closure(path.join(SRC, "linter", "lint.bend")));

// The npm package holds these files of this repo, but those it leaves out: tests, these scripts,
// the test rules, and the rule API.
const SHIPPED = /^(src\/|package\.json$|README\.md$|LICENSE$)/;
const LEFT_OUT = /(\.test\.ts$|^src\/meta\/|^src\/linter\/(testing\.ts|tests\.bend)$)/;

// Functions
// =========

// The path of `file` from the folder `dir`, with "/" between its parts.
const from = (dir: string, file: string): string =>
  getPathWithForwardSlashes(path.relative(dir, file));

// The files git tracks in this repo.
const tracked = (): string[] => {
  const listed = spawnSync("git", ["ls-files", "-z"], { cwd: ROOT, encoding: "utf8" });
  if (listed.status !== 0) throw new Error("git ls-files failed: " + listed.stderr);
  return listed.stdout
    .split("\0")
    .filter((p) => p !== "")
    .map((p) => path.join(ROOT, p));
};

// `text`, of the .bend file `file` of the package `at` (files of this repo to their paths in it),
// with each import of a file the package holds following that file, and each of a rule API file
// from BendHub.
const relocated = (file: string, text: string, at: Map<string, string>): string =>
  text.replace(IMPORT, (line: string, relative: string) => {
    const target = path.resolve(path.dirname(file), relative);
    const held = at.get(target);
    if (held !== undefined) {
      const to = path.posix.relative(path.posix.dirname(at.get(file) ?? ""), held);
      return line.replace(relative, to.startsWith("../") ? to : "./" + to);
    }
    if (API_FILES.has(target)) return line.replace(relative, API + "/" + from(SRC, target));
    throw new Error(from(ROOT, file) + " imports " + relative + ", which its package lacks");
  });

// The package of the files of this repo `at` (files to their paths in it), and of `more` (paths to
// texts): paths to texts.
const packed = (at: Map<string, string>, more: Array<[string, string]> = []): Map<string, string> =>
  new Map([
    ...[...at].map(([file, to]): [string, string] => {
      const text = fs.readFileSync(file, "utf8");
      return [to, file.endsWith(".bend") ? relocated(file, text, at) : text];
    }),
    ...more,
  ]);

// The rule API.
export const apiOf = (): Map<string, string> =>
  packed(new Map([...API_FILES].map((file): [string, string] => [file, from(SRC, file)])), [
    ["linter/LICENSE", LICENSE],
  ]);

// bend-lint's own rules.
export const defaultsOf = (): Map<string, string> => {
  const rules = tracked().filter(
    (file) => file.startsWith(RULES + path.sep) && file.endsWith(".bend"),
  );
  const seen = new Set(API_FILES);
  const at = new Map(
    rules
      .flatMap((rule) => closure(rule, seen))
      .map((file): [string, string] => [
        file,
        file.startsWith(RULES + path.sep) ? from(RULES, file) : "lib/" + from(SRC, file),
      ]),
  );
  const entry = rules.map((rule, n) => `import ./${from(RULES, rule)} as Rule${n}\n`).join("");
  return packed(at, [
    ["rules.bend", "import Base\n" + entry],
    ["LICENSE", LICENSE],
  ]);
};

// The npm package.
export const npmOf = (): Map<string, string> =>
  packed(
    new Map(
      tracked()
        .filter((file) => !API_FILES.has(file))
        .map((file): [string, string] => [file, from(ROOT, file)])
        .filter(([, p]) => SHIPPED.test(p) && !LEFT_OUT.test(p)),
    ),
  );

// The hash of the package of `files` (paths to texts), as `bend --publish` makes it.
export const hashOf = (files: Map<string, string>): string =>
  "0x" +
  getSha256Hex(
    [...files]
      .sort(([a], [b]) => (a < b ? -1 : 1))
      .map(([at, text]) => getSha256Hex(text.replace(/^﻿/, "")) + " " + at + "\n")
      .join(""),
  ).slice(0, 32);

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
  // Each BendHub package: its folder, its entry there, and its name. The rules import the API.
  const hub: Array<[string, string, string, Map<string, string>]> = [
    ["api", "linter/lint.bend", API, apiOf()],
    ["rules", "rules.bend", DEFAULTS, defaultsOf()],
  ];
  hub.forEach(([name, , named, files]) => {
    writeFiles(path.join(dir, name), files);
    console.log(named + " is " + hashOf(files));
  });
  writeFiles(path.join(dir, "npm"), npmOf());
  if (flag === "--publish") {
    const bend = getBendCli(unwrap(await tryGetBend2SourceUrl()));
    const failed = hub.find(
      ([name, entry, named]) =>
        spawnSync(
          bend.cmd[0] ?? "",
          [...bend.cmd.slice(1), path.join(dir, name, entry), "--publish", named],
          { stdio: "inherit", env: { ...process.env, ...bend.env } },
        ).status !== 0,
    );
    process.exit(failed === undefined ? 0 : 1);
  }
}
