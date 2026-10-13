// Imports
// =======

import { expect, setDefaultTimeout, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

import { API, DEFAULTS } from "../linter/seam.ts";
import { BUILDS, fresh } from "../linter/testing.ts";
import { getCommandOutcome } from "../shared/utils.ts";
import { apiOf, defaultsOf, hashOf, npmOf, writeFiles } from "./ship.ts";

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
  const hash = hashOf(files);
  writeFiles(path.join(lib, hash), files);
  writeFiles(path.join(lib, "names"), new Map([[named, hash + "\n"]]));
};

// Side effects
// ============

setDefaultTimeout(600_000);

(BUILDS ? test : test.skip)(
  "a project that installs the npm package lints: init's formatter, and a rule of a package on BendHub",
  async () => {
    const dir = fresh();
    const lib = path.join(dir, "lib");
    const npm = path.join(dir, "npm");
    const project = path.join(dir, "project");
    const env = { BEND_LIB: lib };
    host(lib, API, apiOf());
    host(lib, DEFAULTS, defaultsOf());
    host(lib, "demo-rules@1.0.0.0", new Map([["no-one.bend", DEMO]]));
    writeFiles(npm, npmOf());
    const packed = await getCommandOutcome(["bun", "pm", "pack"], npm);
    const tgz = path.join(npm, fs.readdirSync(npm).find((name) => name.endsWith(".tgz")) ?? "");
    writeFiles(project, new Map([["package.json", '{ "name": "demo", "private": true }\n']]));
    const added = await getCommandOutcome(["bun", "add", "-D", "--trust", tgz], project, env);
    const inited = ["bend-lint.json", "bend-lint-rules/format.bend"].map((name) =>
      fs.existsSync(path.join(project, name)),
    );
    writeFiles(
      project,
      new Map([
        [
          "bend-lint.json",
          JSON.stringify({
            packages: { "demo-rules": "1.0.0.0" },
            rules: { format: "warning", "demo-rules/no-one": "warning" },
          }),
        ],
        ["main.bend", "import Base\n\n\n\ndef one() -> U32:\n  1\n"],
      ]),
    );
    const ran = await getCommandOutcome(["bunx", "bend-lint", "main.bend"], project, env);
    expect([
      packed.code,
      added.code,
      inited,
      ran.code,
      ran.out
        .trim()
        .split("\n")
        .map((line) => line.replace(/^.*\/(?=[\w.]+:\d)/, "")),
    ]).toEqual([
      0,
      0,
      [true, true],
      0,
      [
        "main.bend:1:1: warning demo-rules/no-one: demo",
        "main.bend:3:1: warning format: Apply canonical formatting.",
        "bend-lint: 2 finding(s)",
      ],
    ]);
  },
);
