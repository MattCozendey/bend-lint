// What the rules' tests share: build a program that holds one rule, and
// lint files with it through the server.

// Imports
// =======

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

// Types
// =====

// A finding as the CLI prints it: its file's name, where it starts
// (line:column), its severity, its rule and its message.
export type Found = { file: string; at: string; severity: string; code: string; message: string };

// How a run ended: its exit code, what it printed, and the files after it.
export type Ran = { code: number; out: string; err: string; files: Record<string, string> };

// Constants
// =========

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SERVER = path.join(HERE, "server.ts");

// Bend imports only relative paths of plain names, so the programs the
// tests build live in this folder.
const BUILD = path.join(HERE, "build");

const LINE = /^(.*):(\d+:\d+): (\w+) (\S+): (.*)$/;

// Functions
// =========

// The program that lints with the rule in `rule` (a path under this
// folder), built once; the path of its executable.
export const build = (rule: string): string => {
  const name = path.basename(rule, ".bend").replace(/[^\w]/g, "_");
  const source = path.join(BUILD, name + ".bend");
  const relative = path.relative(BUILD, path.join(HERE, rule)).replaceAll(path.sep, "/");
  fs.mkdirSync(BUILD, { recursive: true });
  fs.writeFileSync(
    source,
    `import Base\nimport ../cli.bend as Cli\nimport ${relative} as Rule\n\ndef main() -> IO(Unit):\n  Cli.run(~[Rule.rule()])\n`,
  );
  const out = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "bend-lint-test-")),
    name + (process.platform === "win32" ? ".exe" : ""),
  );
  const run = Bun.spawnSync(["bend", source, "-o", out], { cwd: BUILD });
  if (run.exitCode !== 0) {
    throw new Error(`could not build ${source}:\n${run.stdout.toString()}${run.stderr.toString()}`);
  }
  return out;
};

// How `program` ends on `named`, with the command line's other `args`
// (flags, more files or globs), after it writes `files` (names to text) into
// a fresh folder. It runs in that folder.
export const run = (
  program: string,
  files: Record<string, string>,
  named: string,
  args: string[] = [],
): Ran => {
  const dir = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), "bend-lint-case-")));
  Object.entries(files).forEach(([name, text]) => {
    fs.mkdirSync(path.dirname(path.join(dir, name)), { recursive: true });
    fs.writeFileSync(path.join(dir, name), text);
  });
  const ran = Bun.spawnSync(["bun", SERVER, program, path.join(dir, named), ...args], { cwd: dir });
  return {
    code: ran.exitCode,
    out: ran.stdout.toString(),
    err: ran.stderr.toString(),
    files: Object.fromEntries(
      Object.keys(files).map((name) => [name, fs.readFileSync(path.join(dir, name), "utf8")]),
    ),
  };
};

// What `program` finds in `named`, after it writes `files` (names to text)
// into a fresh folder.
export const lint = (program: string, files: Record<string, string>, named: string): Found[] =>
  run(program, files, named)
    .out.split("\n")
    .flatMap((line) => {
      const m = LINE.exec(line);
      return m === null
        ? []
        : [{ file: path.basename(m[1]), at: m[2], severity: m[3], code: m[4], message: m[5] }];
    });
