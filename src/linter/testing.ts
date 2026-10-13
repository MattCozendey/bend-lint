// What the rules' tests share: build a program that holds one rule, and
// lint files with it through the server.

// Imports
// =======

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { isMachineNote, tryGetBend2SourceUrl } from "../shared/bend2.ts";
import { OK, unwrap } from "../shared/result.ts";
import {
  getCommandOutcome,
  getPathWithForwardSlashes,
  writeFileAtomically,
} from "../shared/utils.ts";
import type { Outcome } from "../shared/utils.ts";
import { built } from "./seam.ts";

// Types
// =====

// A finding as the CLI prints it: its file's name, where it starts
// (line:column), its severity, its rule and its message.
export type Found = { file: string; at: string; severity: string; code: string; message: string };

// How a run ended, with the files after it, and the folder it ran in.
export type Ran = Outcome & { files: Record<string, string>; dir: string };

// Constants
// =========

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SRC = path.dirname(HERE);
const SERVER = path.join(HERE, "seam.ts");

// Bend imports only relative paths of plain names, so the programs the
// tests build live in this folder.
const BUILD = path.join(HERE, "build");

const LINE = /^(.*):(\d+:\d+): (\w+) (\S+): (.*)$/;

// Whether bend-lint has its Bend to build with: the pinned one, which it
// downloads once.
export const BUILDS: boolean = OK in (await tryGetBend2SourceUrl());

// Functions
// =========

// The program that lints with the rule the def `def` of `file` (a path under
// src/) gives; the path of its executable, which the server builds and keeps.
export const build = async (file: string, def = "rule"): Promise<string> => {
  const name = (file.replace(/\.bend$/, "") + "_" + def).replace(/\W/g, "_");
  const source = path.join(BUILD, name + ".bend");
  const relative = getPathWithForwardSlashes(path.relative(BUILD, path.join(SRC, file)));
  const text = `import Base\nimport ../cli.bend as Cli\nimport ${relative} as Rule\n\ndef main() -> IO(Unit):\n  Cli.run(~[Rule.${def}()])\n`;
  fs.mkdirSync(BUILD, { recursive: true });
  writeFileAtomically(source, text);
  return built(source, unwrap(await tryGetBend2SourceUrl()));
};

// How `program` ends on `named`, with the command line's other `args`
// (flags, more files or globs), after it writes `files` (names to text) into
// `dir`, a fresh folder unless given. It runs in that folder. Its stderr leaves
// out what bend-lint says of how this machine runs it.
export const run = async (
  program: string,
  files: Record<string, string>,
  named: string,
  args: string[] = [],
  dir: string = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), "bend-lint-case-"))),
): Promise<Ran> => {
  Object.entries(files).forEach(([name, text]) => {
    fs.mkdirSync(path.dirname(path.join(dir, name)), { recursive: true });
    fs.writeFileSync(path.join(dir, name), text);
  });
  const ran = await getCommandOutcome(
    ["bun", SERVER, "--program", program, path.join(dir, named), ...args],
    dir,
  );
  return {
    ...ran,
    err: ran.err
      .split("\n")
      .filter((line) => !isMachineNote(line.trimEnd()))
      .join("\n"),
    files: Object.fromEntries(
      Object.keys(files).map((name) => [name, fs.readFileSync(path.join(dir, name), "utf8")]),
    ),
    dir,
  };
};

// What `program` finds in `named`, after it writes `files` (names to text)
// into a fresh folder.
export const lint = async (
  program: string,
  files: Record<string, string>,
  named: string,
): Promise<Found[]> =>
  (await run(program, files, named)).out.split("\n").flatMap((line) => {
    const m = LINE.exec(line);
    return m === null
      ? []
      : [{ file: path.basename(m[1]), at: m[2], severity: m[3], code: m[4], message: m[5] }];
  });
