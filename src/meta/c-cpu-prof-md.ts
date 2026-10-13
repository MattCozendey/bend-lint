// Profiles a rules program's C lane, like bun's --cpu-prof-md: builds it with
// clang's coverage, runs it through the server, and writes
// C-CPU.<date>.<time>.<pid>.md, plus the .c its locations point into, to the
// current folder. Exits with the run's status.
//
// usage: bun run c-cpu-prof-md <rules program.bend> <server args...>
//
// Coverage counts calls, not time. On the host each def segment is a function
// WL_FID_<DEF>, its continuations WL_FID_<DEF>_K<n>, so a def's count is its
// segments' sum. A run of several files lints each in a worker process; the
// counts are those of every process.

// Imports
// =======

import { spawnSync } from "node:child_process";
import type { SpawnSyncOptions } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

import { getBendCli, tryGetBend2SourceUrl } from "../shared/bend2.ts";
import { unwrap } from "../shared/result.ts";

// Types
// =====

type Row = { name: string; count: number; line: number; segments: number };

// llvm-cov export's JSON, as far as this script reads it.
type CoverageExport = {
  data: [{ functions: { name: string; count: number; regions: number[][] }[] }];
};

// Constants
// =========

const SERVER = path.resolve(import.meta.dir, "..", "linter", "seam.ts");
const RUNTIME_ROWS = 30;
const NUMBER_COLUMNS = new Set([
  "Calls%",
  "Calls",
  "Segments",
  "Def calls",
  "Defs run",
  "Runtime calls",
]);

// Functions
// =========

// Runs `cmd`; throws with its stderr if it fails.
const run = (cmd: string, args: string[], options: SpawnSyncOptions = {}): void => {
  const out = spawnSync(cmd, args, { encoding: "utf8", ...options });
  if (out.error !== undefined || out.status !== 0) {
    throw new Error(`${path.basename(cmd)} failed: ${out.error?.message ?? String(out.stderr)}`);
  }
};

// The first clang that answers, in bend's order: $CC, clang on PATH, then,
// on Windows, where LLVM's installer puts it.
const findClang = (): string => {
  const found = [
    process.env.CC,
    "clang",
    process.platform === "win32"
      ? path.join(process.env.ProgramFiles ?? "C:\\Program Files", "LLVM", "bin", "clang.exe")
      : undefined,
  ].find((cc) => cc !== undefined && spawnSync(cc, ["--version"]).status === 0);
  if (found === undefined) throw new Error("no clang: set CC, or put clang on PATH");
  return found;
};

const findTool = (clang: string, tool: string): string =>
  spawnSync(clang, ["--print-prog-name=" + tool], { encoding: "utf8" }).stdout.trim();

const getRowsFromFunctions = (
  functions: CoverageExport["data"][0]["functions"],
  toName: (f: string) => string,
): Row[] =>
  [...new Set(functions.map((f) => toName(f.name)))]
    .map((name) => {
      const group = functions.filter((f) => toName(f.name) === name);
      return {
        name,
        count: group.reduce((sum, f) => sum + f.count, 0),
        line: Math.min(...group.map((f) => f.regions[0][0])),
        segments: group.length,
      };
    })
    .filter((r) => r.count > 0)
    .sort((a, b) => b.count - a.count);

const getCount = (rows: Row[]): number => rows.reduce((sum, r) => sum + r.count, 0);

const getPercent = (part: number, whole: number): string => ((100 * part) / whole).toFixed(1) + "%";

const getMarkdownTable = (header: string[], rows: string[][]): string[] => [
  "| " + header.join(" | ") + " |",
  "|" + header.map((h) => (NUMBER_COLUMNS.has(h) ? "-----:" : "-----")).join("|") + "|",
  ...rows.map((r) => "| " + r.join(" | ") + " |"),
];

const getMarkdown = (command: string, c: string, defs: Row[], runtime: Row[]): string => {
  const defCalls = getCount(defs);
  const runtimeCalls = getCount(runtime);
  return [
    "# C CPU Profile",
    "",
    ...getMarkdownTable(
      ["Command", "Def calls", "Defs run", "Runtime calls"],
      [
        [
          "`" + command + "`",
          defCalls.toLocaleString("en-US"),
          String(defs.length),
          runtimeCalls.toLocaleString("en-US"),
        ],
      ],
    ),
    "",
    "Calls, not time: clang's coverage counts each entry to a function.",
    "",
    "## Hot Defs (Calls)",
    "",
    ...getMarkdownTable(
      ["Calls%", "Calls", "Segments", "Def", "Location"],
      defs.map((r) => [
        getPercent(r.count, defCalls),
        r.count.toLocaleString("en-US"),
        String(r.segments),
        "`" + r.name + "`",
        "`" + c + ":" + r.line + "`",
      ]),
    ),
    "",
    `## Hot Runtime Functions (Calls, top ${RUNTIME_ROWS})`,
    "",
    ...getMarkdownTable(
      ["Calls%", "Calls", "Function", "Location"],
      runtime
        .slice(0, RUNTIME_ROWS)
        .map((r) => [
          getPercent(r.count, runtimeCalls),
          r.count.toLocaleString("en-US"),
          "`" + r.name + "`",
          "`" + c + ":" + r.line + "`",
        ]),
    ),
    "",
  ].join("\n");
};

// Side effects
// ============

const [program, ...args] = process.argv.slice(2);
if (program === undefined) {
  console.error("usage: bun run c-cpu-prof-md <rules program.bend> <server args...>");
  process.exit(2);
}
const clang = findClang();
const stamp = new Date().toISOString().replace(/[-:]/g, "").replace("T", ".").slice(0, 15);
const name = `C-CPU.${stamp}.${process.pid}`;
const work = fs.mkdtempSync(path.join(os.tmpdir(), "bend-lint-c-cpu-prof-"));
try {
  const c = path.join(work, "program.c");
  const exe = path.join(work, process.platform === "win32" ? "program.exe" : "program");
  const bend = getBendCli(unwrap(await tryGetBend2SourceUrl()));
  run(bend.cmd[0], [...bend.cmd.slice(1), program, "-o", c], {
    env: { ...process.env, ...bend.env },
  });
  run(clang, [
    "-std=c11",
    "-O3",
    "-g",
    "-fprofile-instr-generate",
    "-fcoverage-mapping",
    c,
    ...(process.platform === "win32" ? [] : ["-lpthread", "-lm"]),
    "-o",
    exe,
  ]);
  const ran = spawnSync(process.execPath, [SERVER, "--program", exe, ...args], {
    env: { ...process.env, LLVM_PROFILE_FILE: path.join(work, "program.%p.profraw") },
    stdio: "inherit",
  });
  const raws = fs
    .readdirSync(work)
    .filter((f) => f.endsWith(".profraw"))
    .map((f) => path.join(work, f));
  if (raws.length === 0) throw new Error("the run wrote no profile");
  const data = path.join(work, "program.profdata");
  run(findTool(clang, "llvm-profdata"), ["merge", "-sparse", ...raws, "-o", data]);
  const json = path.join(work, "coverage.json");
  const jsonFd = fs.openSync(json, "w");
  try {
    run(
      findTool(clang, "llvm-cov"),
      ["export", "-format=text", "-skip-expansions", "-instr-profile", data, exe],
      { stdio: ["ignore", jsonFd, "pipe"] },
    );
  } finally {
    fs.closeSync(jsonFd);
  }
  const coverage = JSON.parse(fs.readFileSync(json, "utf8")) as CoverageExport;
  const functions = coverage.data[0].functions.map((f) => ({
    ...f,
    name: f.name.replace(/^.*:/, ""),
  }));
  const isDef = (f: { name: string }): boolean => f.name.startsWith("WL_FID_");
  fs.copyFileSync(c, name + ".c");
  fs.writeFileSync(
    name + ".md",
    getMarkdown(
      ["bun run c-cpu-prof-md", program, ...args].join(" "),
      name + ".c",
      getRowsFromFunctions(functions.filter(isDef), (f) =>
        f.replace(/^WL_FID_/, "").replace(/_K\d+$/, ""),
      ),
      getRowsFromFunctions(
        functions.filter((f) => !isDef(f)),
        (f) => f,
      ),
    ),
  );
  console.error("bend-lint: wrote " + path.resolve(name + ".md"));
  process.exitCode = ran.status ?? 1;
} finally {
  fs.rmSync(work, { recursive: true, force: true });
}
