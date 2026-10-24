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

import { API, DEFAULTS, getClosure, IMPORT } from "../linter/seam.ts";
import { getBendCli, tryGetBend2SourceUrl } from "../shared/bend2.ts";
import { unwrap } from "../shared/result.ts";
import { getPathWithForwardSlashes, getSha256Hex, writeFileAtomically } from "../shared/utils.ts";

// Constants
// =========

const ROOT = path.resolve(import.meta.dir, "..", "..");
const SRC = path.join(ROOT, "src");
const RULES = path.join(ROOT, "bend-lint-rules");
const LICENSE = fs.readFileSync(path.join(ROOT, "LICENSE"), "utf8");

// The rule API's files.
const API_FILES = new Set(getClosure(path.join(SRC, "linter", "lint.bend")));

// The npm package holds these files of this repo, but those it leaves out: tests, these scripts,
// the test rules, and the rule API.
const SHIPPED = /^(src\/|README\.md$|LICENSE$)/;
const LEFT_OUT = /(\.test\.ts$|^src\/meta\/|^src\/linter\/(testing\.ts|tests\.bend)$)/;

// What the npm package's package.json leaves out of this repo's: what only this repo uses.
const DEV_ONLY = new Set(["private", "scripts", "devDependencies", "packageManager"]);

// Functions
// =========

// The path of `file` from the folder `dir`, with "/" between its parts.
const getPathFrom = (dir: string, file: string): string =>
  getPathWithForwardSlashes(path.relative(dir, file));

// The files git tracks in this repo.
const getTrackedFiles = (): string[] => {
  const listed = spawnSync("git", ["ls-files", "-z"], { cwd: ROOT, encoding: "utf8" });
  if (listed.status !== 0) throw new Error("git ls-files failed: " + listed.stderr);
  return listed.stdout
    .split("\0")
    .filter((p) => p !== "")
    .map((p) => path.join(ROOT, p));
};

// The package of the files of this repo `at` (files to their paths in it), and of `more` (paths to
// texts): paths to texts. A .bend file's imports of files the package holds follow them, and its
// imports of rule API files come from BendHub.
const getPackage = (
  at: Map<string, string>,
  more: Array<[string, string]> = [],
): Map<string, string> =>
  new Map([
    ...[...at].map(([file, to]): [string, string] => {
      const text = fs.readFileSync(file, "utf8");
      if (!file.endsWith(".bend")) return [to, text];
      return [
        to,
        text.replace(IMPORT, (line: string, relative: string) => {
          const target = path.resolve(path.dirname(file), relative);
          const held = at.get(target);
          if (held !== undefined) {
            const moved = path.posix.relative(path.posix.dirname(to), held);
            return line.replace(relative, moved.startsWith("../") ? moved : "./" + moved);
          }
          if (API_FILES.has(target))
            return line.replace(relative, API + "/" + getPathFrom(SRC, target));
          throw new Error(
            getPathFrom(ROOT, file) + " imports " + relative + ", which its package lacks",
          );
        }),
      ];
    }),
    ...more,
  ]);

// The rule API.
export const getApiPackage = (): Map<string, string> =>
  getPackage(
    new Map([...API_FILES].map((file): [string, string] => [file, getPathFrom(SRC, file)])),
    [["linter/LICENSE", LICENSE]],
  );

// bend-lint's own rules: the .bend files git tracks in bend-lint-rules/.
const getDefaultRules = (): string[] =>
  getTrackedFiles().filter((file) => file.startsWith(RULES + path.sep) && file.endsWith(".bend"));

// bend-lint's own rules.
export const getDefaultsPackage = (): Map<string, string> => {
  const rules = getDefaultRules();
  const seen = new Set(API_FILES);
  const at = new Map(
    rules
      .flatMap((rule) => getClosure(rule, seen))
      .map((file): [string, string] => [
        file,
        file.startsWith(RULES + path.sep)
          ? getPathFrom(RULES, file)
          : "lib/" + getPathFrom(SRC, file),
      ]),
  );
  const entry = rules
    .map((rule, n) => `import ./${getPathFrom(RULES, rule)} as Rule${n}\n`)
    .join("");
  return getPackage(at, [
    ["rules.bend", "import Base\n" + entry],
    ["LICENSE", LICENSE],
  ]);
};

// The npm package, with the ids of bend-lint's own rules in src/linter/defaults.json (see
// getBuiltRules in seam.ts). A project that trusts it runs its postinstall (see seam.ts).
export const getNpmPackage = (): Map<string, string> => {
  const config = JSON.parse(fs.readFileSync(path.join(ROOT, "package.json"), "utf8")) as object;
  const kept = Object.entries(config).filter(([key]) => !DEV_ONLY.has(key));
  const scripts = { postinstall: "bun ./src/linter/seam.ts postinstall" };
  return getPackage(
    new Map(
      getTrackedFiles()
        .filter((file) => !API_FILES.has(file))
        .map((file): [string, string] => [file, getPathFrom(ROOT, file)])
        .filter(([, p]) => SHIPPED.test(p) && !LEFT_OUT.test(p)),
    ),
    [
      ["package.json", JSON.stringify({ ...Object.fromEntries(kept), scripts }, null, 2) + "\n"],
      [
        "src/linter/defaults.json",
        JSON.stringify(
          getDefaultRules().map((rule) => getPathFrom(RULES, rule).replace(/\.bend$/, "")),
        ) + "\n",
      ],
    ],
  );
};

// The hash of the package of `files` (paths to texts), as `bend --publish` makes it.
export const getPackageHash = (files: Map<string, string>): string =>
  "0x" +
  getSha256Hex(
    [...files]
      .sort(([a], [b]) => (a < b ? -1 : 1))
      .map(([at, text]) => getSha256Hex(text.replace(/^﻿/, "")) + " " + at + "\n")
      .join(""),
  ).slice(0, 32);

// Writes `files` (paths to texts) into `dir`.
export const writeFiles = (dir: string, files: Map<string, string>): void =>
  files.forEach((text, at) => writeFileAtomically(path.join(dir, at), text));

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
    ["api", "linter/lint.bend", API, getApiPackage()],
    ["rules", "rules.bend", DEFAULTS, getDefaultsPackage()],
  ];
  hub.forEach(([name, , named, files]) => {
    writeFiles(path.join(dir, name), files);
    console.log(named + " is " + getPackageHash(files));
  });
  writeFiles(path.join(dir, "npm"), getNpmPackage());
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
