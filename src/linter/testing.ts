// What the rules' tests share: build a program that holds one rule, and
// lint files with it through the server.

// Imports
// =======

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { tryGetBend2SourceUrl, tryGetInstalledBendTagFromCliOrUndefined } from "../shared/bend2.ts";
import { getPathWithForwardSlashes } from "../shared/paths.ts";
import { ERROR, OK } from "../shared/result.ts";
import { getSha256Hex } from "../shared/utils.ts";

// Types
// =====

// A finding as the CLI prints it: its file's name, where it starts
// (line:column), its severity, its rule and its message.
export type Found = { file: string; at: string; severity: string; code: string; message: string };

// How a run ended: its exit code, what it printed, the files after it, and
// the folder it ran in.
export type Ran = {
  code: number;
  out: string;
  err: string;
  files: Record<string, string>;
  dir: string;
};

// Constants
// =========

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SERVER = path.join(HERE, "server.ts");

// Bend imports only relative paths of plain names, so the programs the
// tests build live in this folder, beside the executables they keep.
const BUILD = path.join(HERE, "build");

const LINE = /^(.*):(\d+:\d+): (\w+) (\S+): (.*)$/;

const IMPORT = /^\s*import\s+(\.\.?\/\S+)/gm;

// Whether the bend that build runs is installed. The server finds its
// release too, if BEND_DIR is not set.
export const BUILDS: boolean = await tryGetInstalledBendTagFromCliOrUndefined().then(
  (installed) => OK in installed && installed.OK !== undefined,
);

// Functions
// =========

// The .bend file at `file` and every .bend file it imports, at any depth,
// each once.
const getBendFileClosure = (file: string, seen: ReadonlySet<string> = new Set()): string[] =>
  seen.has(file)
    ? []
    : [...fs.readFileSync(file, "utf8").matchAll(IMPORT)].reduce<string[]>(
        (files, m) => [
          ...files,
          ...getBendFileClosure(
            path.resolve(path.dirname(file), m[1]),
            new Set([...seen, ...files]),
          ),
        ],
        [file],
      );

// The paths and texts of the files under `dir` whose extension is in `exts`.
const getFilesText = (dir: string, exts: string[]): string =>
  fs
    .readdirSync(dir, { recursive: true, encoding: "utf8" })
    .filter((f) => exts.includes(path.extname(f)))
    .sort()
    .map((f) => f + "\0" + fs.readFileSync(path.join(dir, f), "latin1"))
    .join("\0");

// What a build depends on besides the linter's files: the `bend` on PATH, and
// the bend2 sources, which hold Base and the compiler when that `bend` runs a
// checkout.
const getBuilderText = async (): Promise<string> => {
  const bend2 = await tryGetBend2SourceUrl();
  if (ERROR in bend2) {
    throw new Error(bend2[ERROR]);
  }
  const bend = Bun.which("bend");
  return [
    bend === null ? "" : fs.readFileSync(bend, "latin1"),
    getFilesText(fileURLToPath(bend2.OK), [".ts", ".bend"]),
  ].join("\0");
};

// The program that lints with the rule in `rule` (a path under this
// folder); the path of its executable. A build is kept, and used again until
// the rule, a file it imports or the bend that builds it changes. It goes to
// a folder of its own first, so a kept executable is never partial.
export const build = async (rule: string): Promise<string> => {
  const name = rule.replace(/\.bend$/, "").replace(/\W/g, "_");
  const source = path.join(BUILD, name + ".bend");
  const relative = getPathWithForwardSlashes(path.relative(BUILD, path.join(HERE, rule)));
  const text = `import Base\nimport ../cli.bend as Cli\nimport ${relative} as Rule\n\ndef main() -> IO(Unit):\n  Cli.run(~[Rule.rule()])\n`;
  const key = getSha256Hex(
    [
      text,
      await getBuilderText(),
      ...getBendFileClosure(path.join(HERE, rule)).flatMap((f) => [
        path.relative(HERE, f),
        fs.readFileSync(f, "utf8"),
      ]),
    ].join("\0"),
  ).slice(0, 16);
  const exe = path.join(BUILD, `${name}.${key}${process.platform === "win32" ? ".exe" : ""}`);
  if (fs.existsSync(exe)) {
    return exe;
  }
  fs.mkdirSync(BUILD, { recursive: true });
  fs.writeFileSync(source, text);
  const part = fs.mkdtempSync(path.join(BUILD, ".part-"));
  const out = path.join(part, path.basename(exe));
  const run = Bun.spawn(["bend", source, "-o", out], {
    cwd: BUILD,
    stdout: "pipe",
    stderr: "pipe",
  });
  const [code, stdout, stderr] = await Promise.all([
    run.exited,
    new Response(run.stdout).text(),
    new Response(run.stderr).text(),
  ]);
  if (code !== 0) {
    fs.rmSync(part, { recursive: true, force: true });
    throw new Error(`could not build ${source}:\n${stdout}${stderr}`);
  }
  fs.readdirSync(BUILD)
    .filter((f) => f.startsWith(name + ".") && f !== name + ".bend")
    .forEach((f) => fs.rmSync(path.join(BUILD, f), { force: true }));
  fs.renameSync(out, exe);
  fs.rmSync(part, { recursive: true, force: true });
  return exe;
};

// How `program` ends on `named`, with the command line's other `args`
// (flags, more files or globs), after it writes `files` (names to text) into
// `dir`, a fresh folder unless given. It runs in that folder.
export const run = (
  program: string,
  files: Record<string, string>,
  named: string,
  args: string[] = [],
  dir: string = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), "bend-lint-case-"))),
): Ran => {
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
    dir,
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
