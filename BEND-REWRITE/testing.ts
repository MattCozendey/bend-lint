// What the rewrite's tests share: lint files with the host, and read what it
// reports.

// Imports
// =======

import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

// Types
// =====

// A finding as the host prints it: its code, the name of its file, its text
// from where it starts to the end of that line, its message, and its fixes.
export type Found = { code: string; file: string; text: string; message: string; fixes: string[] };

// What a run of the host gives: its findings, those directives suppressed
// (shown with --show-suppressed), its exit code, and its stderr.
export type Run = { found: Found[]; suppressed: Found[]; code: number; stderr: string };

// Constants
// =========

const HOST = fileURLToPath(new URL("./host.ts", import.meta.url));
const LINE = /^(.+):(\d+): ([\w/-]+): (.*)$/;
const FIX = /^ {2}fix: (.*)$/;
const SUPPRESSED = "bend-lint: suppressed";

// Functions
// =========

// The findings `lines` print, each with the text of its file at its start.
const read = (lines: string[], texts: Map<string, string>): Found[] =>
  lines.reduce<Found[]>((done, line) => {
    const fix = FIX.exec(line);
    const last = done[done.length - 1];
    if (fix !== null && last !== undefined) {
      return [...done.slice(0, -1), { ...last, fixes: [...last.fixes, fix[1]] }];
    }
    const m = LINE.exec(line);
    if (m === null) {
      return done;
    }
    const file = path.basename(m[1]);
    const points = (texts.get(file) ?? "").match(/./gsu) ?? [];
    return [
      ...done,
      {
        code: m[3],
        file,
        text: points.slice(Number(m[2])).join("").split("\n")[0],
        message: m[4],
        fixes: [],
      },
    ];
  }, []);

// Writes `files` (names, maybe with folders, to text) into `dir`, lints
// `named` there with `args`, and gives what the host reports.
export const lintRun = (
  dir: string,
  files: Record<string, string>,
  named: string,
  args: string[],
): Run => {
  Object.entries(files).forEach(([name, text]) => {
    fs.mkdirSync(path.dirname(path.join(dir, name)), { recursive: true });
    fs.writeFileSync(path.join(dir, name), text);
  });
  const run = Bun.spawnSync(["bun", HOST, path.join(dir, named), ...args]);
  const texts = new Map(Object.entries(files).map(([name, text]) => [path.basename(name), text]));
  const lines = run.stdout.toString().split(/\r?\n/);
  const cut = lines.indexOf(SUPPRESSED);
  return {
    found: read(cut < 0 ? lines : lines.slice(0, cut), texts),
    suppressed: cut < 0 ? [] : read(lines.slice(cut + 1), texts),
    code: run.exitCode,
    stderr: run.stderr.toString(),
  };
};

// What the host reports, as lintRun lints it.
export const lintIn = (
  dir: string,
  files: Record<string, string>,
  named: string,
  args: string[],
): Found[] => lintRun(dir, files, named, args).found;
