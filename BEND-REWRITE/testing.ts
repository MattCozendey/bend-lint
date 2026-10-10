// What the rewrite's tests share: lint files with the host, and read what it
// reports.

// Imports
// =======

import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

// Types
// =====

// A finding as the host reports it: its code, severity, the name of its file,
// the text of its span, the text of its line from where it starts, its
// message, and its fixes as `title [applicability]`.
export type Found = {
  code: string;
  severity: string;
  file: string;
  text: string;
  line: string;
  message: string;
  fixes: string[];
};

// What a run of the host gives: its findings, those directives suppressed,
// its exit code, and its stderr.
export type Run = { found: Found[]; suppressed: Found[]; code: number; stderr: string };

// A position and a finding as --json prints them.
type Point = { line: number; character: number };
type Reported = {
  code: string;
  severity: string;
  message: string;
  path: string;
  range?: { start: Point; end: Point };
  fixes: Array<{ title: string; applicability: string }>;
};

// Constants
// =========

const HOST = fileURLToPath(new URL("./host.ts", import.meta.url));

// Functions
// =========

// The offset (UTF-16 units) of a point in `text`.
const offset = (text: string, p: Point): number =>
  text
    .split("\n")
    .slice(0, p.line)
    .reduce((n, l) => n + l.length + 1, 0) + p.character;

const found = (r: Reported, texts: Map<string, string>): Found => {
  const file = path.basename(r.path);
  const text = texts.get(file) ?? "";
  const beg = r.range === undefined ? 0 : offset(text, r.range.start);
  const end = r.range === undefined ? 0 : offset(text, r.range.end);
  return {
    code: r.code,
    severity: r.severity,
    file,
    text: text.slice(beg, end),
    line: text.slice(beg).split("\n")[0],
    message: r.message,
    fixes: r.fixes.map((f) => `${f.title} [${f.applicability}]`),
  };
};

// Writes `files` (names, maybe with folders, to text) into `dir`, and runs
// the host on `named` there with `args`.
const host = (dir: string, files: Record<string, string>, named: string, args: string[]) => {
  Object.entries(files).forEach(([name, text]) => {
    fs.mkdirSync(path.dirname(path.join(dir, name)), { recursive: true });
    fs.writeFileSync(path.join(dir, name), text);
  });
  return Bun.spawnSync(["bun", HOST, path.join(dir, named), ...args]);
};

// What the host prints as text, as `host` runs it.
export const lintText = (
  dir: string,
  files: Record<string, string>,
  named: string,
  args: string[],
): { stdout: string; stderr: string } => {
  const run = host(dir, files, named, args);
  return { stdout: run.stdout.toString(), stderr: run.stderr.toString() };
};

// What the host reports with --json, as `host` runs it.
export const lintRun = (
  dir: string,
  files: Record<string, string>,
  named: string,
  args: string[],
): Run => {
  const run = host(dir, files, named, [...args, "--json"]);
  const texts = new Map(Object.entries(files).map(([name, text]) => [path.basename(name), text]));
  const out = run.stdout.toString().trim();
  const json = (out.startsWith("{") ? JSON.parse(out) : { findings: [], suppressed: [] }) as {
    findings: Reported[];
    suppressed: Reported[];
  };
  return {
    found: json.findings.map((r) => found(r, texts)),
    suppressed: json.suppressed.map((r) => found(r, texts)),
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
