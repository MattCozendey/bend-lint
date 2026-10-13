// What the rules' tests share: build the program of one rule, and lint files
// with it through the server, as a user's project does.

// Imports
// =======

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { isMachineNote, tryGetBend2SourceUrl } from "../shared/bend2.ts";
import { OK, unwrap } from "../shared/result.ts";
import { getCommandOutcome, writeFileAtomically } from "../shared/utils.ts";
import type { Outcome } from "../shared/utils.ts";
import { BUILD, getBuiltProgram, getRulesProgram } from "./seam.ts";

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
const ROOT = path.dirname(path.dirname(HERE));
const SERVER = path.join(HERE, "seam.ts");

// The project of the test rules: tests/<def> is the def <def> of tests.bend,
// through a rule file in its bend-lint-rules/.
const FIXTURES = path.join(BUILD, "fixtures");

const LINE = /^(.*):(\d+:\d+): (\w+) (\S+): (.*)$/;

// Whether bend-lint has its Bend to build with: the pinned one, which it
// downloads once.
export const BUILDS: boolean = OK in (await tryGetBend2SourceUrl());

// Functions
// =========

// The project whose bend-lint-rules/ holds the rule `id`: this repo, or
// FIXTURES for tests/<def>.
const getRuleProject = (id: string): string => (id.startsWith("tests/") ? FIXTURES : ROOT);

// Builds the program of the rule `id` alone, as the server does for a project
// that turns on only it, if bend-lint has its Bend (BUILDS). A test file builds
// its rules once, before its tests.
export const buildRule = async (id: string): Promise<void> => {
  if (!BUILDS) {
    return;
  }
  if (id.startsWith("tests/")) {
    writeFileAtomically(
      path.join(FIXTURES, "bend-lint-rules", ...id.split("/")) + ".bend",
      "import Base\nimport ../../../../lint.bend as Lint\nimport ../../../../tests.bend as Tests\n\n" +
        `def rule() -> Lint.Rule:\n  Tests.${id.slice("tests/".length)}()\n`,
    );
  }
  await getBuiltProgram(
    getRulesProgram(getRuleProject(id), { ids: [id], packages: new Map() }),
    unwrap(await tryGetBend2SourceUrl()),
  );
};

// A fresh folder for a case.
export const getFreshFolder = (): string =>
  fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), "bend-lint-case-")));

// How the rule `id` ends on `named` (none: on what bend-lint lints when it is
// given no file), with the command line's other `args` (flags, more files or
// globs), after it writes `files` (names to text) into `dir`, a fresh folder
// unless given. It runs in that folder, whose bend-lint.json turns `id` on,
// with what a bend-lint.json among `files` says, and whose bend-lint-rules
// links the folder that holds `id`. Its stderr leaves out what bend-lint says
// of how this machine runs it.
export const getRunOutcome = async (
  id: string,
  files: Record<string, string>,
  named: string | undefined,
  args: string[] = [],
  dir: string = getFreshFolder(),
): Promise<Ran> => {
  Object.entries(files).forEach(([name, text]) => writeFileAtomically(path.join(dir, name), text));
  const config = path.join(dir, "bend-lint.json");
  const given = files["bend-lint.json"];
  if (given !== undefined || !fs.existsSync(config)) {
    const read = (given === undefined ? {} : JSON.parse(given)) as { rules?: object };
    fs.writeFileSync(config, JSON.stringify({ ...read, rules: { [id]: {}, ...read.rules } }));
  }
  const rules = path.join(dir, "bend-lint-rules");
  if (!fs.existsSync(rules)) {
    fs.symlinkSync(path.join(getRuleProject(id), "bend-lint-rules"), rules, "junction");
  }
  const inputs = named === undefined ? [] : [path.join(dir, named)];
  const ran = await getCommandOutcome(["bun", SERVER, ...inputs, ...args], dir);
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

// What the rule `id` finds in `named`, after it writes `files` (names to
// text) into a fresh folder.
export const getFindings = async (
  id: string,
  files: Record<string, string>,
  named: string,
): Promise<Found[]> =>
  (await getRunOutcome(id, files, named)).out.split("\n").flatMap((line) => {
    const m = LINE.exec(line);
    return m === null
      ? []
      : [{ file: path.basename(m[1]), at: m[2], severity: m[3], code: m[4], message: m[5] }];
  });

// What the rule `id` finds in a main.bend of `text`: each finding as where it
// is, its rule and what it says.
export const getFindingTexts = async (id: string, text: string): Promise<string[]> =>
  (await getFindings(id, { "main.bend": text }, "main.bend")).map(
    ({ at, code, message }) => `${at} ${code}: ${message}`,
  );
