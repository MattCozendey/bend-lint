// Imports
// =======

import { expect, setDefaultTimeout, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

import { API, DEFAULTS } from "../linter/seam.ts";
import { BUILDS, getFreshFolder } from "../linter/testing.ts";
import { getCommandOutcome } from "../shared/utils.ts";
import {
  getApiPackage,
  getDefaultsPackage,
  getNpmPackage,
  getPackageHash,
  writeFiles,
} from "./ship.ts";

// Constants
// =========

// The rule of a package on BendHub: a hint on each file.
const DEMO = [
  "import Base",
  `import ${API}/linter/lint.bend as Lint`,
  "",
  "def rule() -> Lint.Rule:",
  "  Lint.Rule{",
  "    Lint.Needs{False{}, False{}},",
  "    [],",
  "    Lint.OnFile{",
  '      here => Lint.done([Lint.Finding{Lint.Hint{}, Lint.Span{Lint.Here.path(here), 0, 0}, "demo", []}])',
  "    }",
  "  }",
  "",
].join("\n");

// Functions
// =========

// Puts the package of `files` (paths to texts) in `lib`, a BEND_LIB, as BendHub's `named`.
const host = (lib: string, named: string, files: Map<string, string>): void => {
  const hash = getPackageHash(files);
  writeFiles(path.join(lib, hash), files);
  writeFiles(path.join(lib, "names"), new Map([[named, hash + "\n"]]));
};

// Side effects
// ============

setDefaultTimeout(600_000);

(BUILDS ? test : test.skip)(
  "a project that installs the npm package lints: init's formatter, and a rule of a package on BendHub; configs of bend-lint's own rules share one build",
  async () => {
    const dir = getFreshFolder();
    const lib = path.join(dir, "lib");
    const npm = path.join(dir, "npm");
    const project = path.join(dir, "project");
    const env = { BEND_LIB: lib };
    host(lib, API, getApiPackage());
    host(lib, DEFAULTS, getDefaultsPackage());
    host(lib, "demo-rules@1.0.0.0", new Map([["no-one.bend", DEMO]]));
    writeFiles(npm, getNpmPackage());
    const packed = await getCommandOutcome(["bun", "pm", "pack"], npm);
    const tgz = path.join(npm, fs.readdirSync(npm).find((name) => name.endsWith(".tgz")) ?? "");
    writeFiles(project, new Map([["package.json", '{ "name": "demo", "private": true }\n']]));
    const added = await getCommandOutcome(["bun", "add", "-D", "--trust", tgz], project, env);
    const inited = fs.readFileSync(path.join(project, "bend-lint.json"), "utf8");
    const own = DEFAULTS.split("@")[0];
    const version = DEFAULTS.split("@")[1];
    // Runs `args` in the project with a bend-lint.json of `rules` and `packages`.
    const getRun = async (args: string[], rules: object, packages: object = {}) => {
      writeFiles(
        project,
        new Map([
          ["bend-lint.json", JSON.stringify({ packages: { [own]: version, ...packages }, rules })],
          ["main.bend", "import Base\n\n\n\ndef One() -> U32:\n  1\n"],
        ]),
      );
      return getCommandOutcome(["bunx", "bend-lint", ...args], project, env);
    };
    const getLines = (text: string): string[] =>
      text
        .trim()
        .split("\n")
        .map((line) => line.replace(/^.*\/(?=[\w.]+:\d)/, ""));
    const getPrepared = (text: string): string | undefined =>
      /^bend-lint: prepared (.*)$/m.exec(text)?.[1];
    const format = { [own + "/layout/format"]: "warning" };
    const formatted = await getRun(["prepare"], format);
    const cased = await getRun(["prepare"], { ...format, [own + "/layout/case"]: "warning" });
    const alone = await getRun(["main.bend"], format);
    const linked = await getRun(["main.bend", "--json"], format);
    const mixed = await getRun(
      ["main.bend"],
      { ...format, "demo-rules/no-one": "warning" },
      { "demo-rules": "1.0.0.0" },
    );
    expect([
      packed.code,
      added.code,
      JSON.parse(inited),
      fs.existsSync(path.join(project, "bend-lint-rules")),
      getPrepared(formatted.err) !== undefined &&
        getPrepared(formatted.err) === getPrepared(cased.err),
      getLines(alone.out),
      (JSON.parse(linked.out) as { findings: Array<{ docs?: string }> }).findings.map(
        (f) => f.docs,
      ),
      mixed.code,
      getLines(mixed.out),
    ]).toEqual([
      0,
      0,
      { packages: { [own]: version }, rules: format },
      false,
      true,
      [
        `main.bend:3:1: warning ${own}/layout/format: Apply canonical formatting.`,
        "bend-lint: 1 finding(s)",
      ],
      [`https://github.com/MattCozendey/bend-lint/blob/main/${own}/layout/format.bend`],
      0,
      [
        "main.bend:1:1: warning demo-rules/no-one: demo",
        `main.bend:3:1: warning ${own}/layout/format: Apply canonical formatting.`,
        "bend-lint: 2 finding(s)",
      ],
    ]);
  },
);
