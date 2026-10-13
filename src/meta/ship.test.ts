// Imports
// =======

import { expect, setDefaultTimeout, test } from "bun:test";
import * as path from "node:path";

import { API } from "../linter/seam.ts";
import { BUILDS, fresh } from "../linter/testing.ts";
import { getCommandOutcome } from "../shared/utils.ts";
import { apiOf, hashOf, writeFiles, writeNpm } from "./ship.ts";

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
  "a project lints with the shipped package: init's formatter, and a rule of a package on BendHub",
  async () => {
    const dir = fresh();
    const lib = path.join(dir, "lib");
    const project = path.join(dir, "project");
    const api = apiOf();
    host(lib, API, api);
    host(lib, "demo-rules@1.0.0.0", new Map([["no-one.bend", DEMO]]));
    writeNpm(path.join(project, "node_modules", "bend-lint"), api);
    const server = path.join(project, "node_modules", "bend-lint", "src", "linter", "seam.ts");
    const init = await getCommandOutcome(["bun", server, "init"], project, { BEND_LIB: lib });
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
    const ran = await getCommandOutcome(["bun", server, "main.bend"], project, { BEND_LIB: lib });
    expect([
      init.code,
      ran.code,
      ran.out
        .trim()
        .split("\n")
        .map((line) => line.replace(/^.*\/(?=[\w.]+:\d)/, "")),
    ]).toEqual([
      0,
      0,
      [
        "main.bend:1:1: warning demo-rules/no-one: demo",
        "main.bend:3:1: warning format: Apply canonical formatting.",
        "bend-lint: 2 finding(s)",
      ],
    ]);
  },
);
