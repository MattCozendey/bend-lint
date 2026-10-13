// The Bend bend-lint checks and builds with, bend2: a pinned commit on GitHub,
// downloaded once, whatever bend is installed. Bend's releases do not run on
// Windows, so there it is a commit of a fork that does, and bend-lint says so
// on each run.

// Imports
// =======

import { execFile, spawnSync } from "node:child_process";
import * as nodeFs from "node:fs";
import * as os from "node:os";
import * as nodePath from "node:path";
import * as url from "node:url";

import pkg from "../../package.json" with { type: "json" };
import { error } from "./result.ts";
import type { Result } from "./result.ts";
import {
  getErrorMessageFromUnknown,
  tryGetJsonOrUndefined,
  tryGetOrUndefined,
  tryGetUrlFromFolderPathOrUrl,
  tryWriteJsonAtomically,
  writeFileAtomically,
} from "./utils.ts";

// Constants
// =========

// The Bend bend-lint uses, as `<owner>/<repo>/<ref>` on GitHub: Bend's newest
// release this repo's checks passed with (src/meta/sync-bend.ts moves it), or,
// on Windows, a commit of a fork that runs there.
export const PINNED_BEND: string = process.platform === "win32" ? pkg.bendWindows : pkg.bendRelease;

// What bend-lint says on each run on Windows, where it uses the fork.
export const PINNED_BEND_NOTE: string | undefined =
  process.platform === "win32"
    ? "bend-lint: on Windows, bend-lint uses a fork of Bend, as Bend's releases do not run there: https://github.com/" +
      pkg.bendWindows.replace(/^([^/]+\/[^/]+)\//, "$1/tree/")
    : undefined;

// bend-lint's cache: the downloaded Bend, and what the server keeps.
export const getBendLintCacheDir = (): URL =>
  url.pathToFileURL(
    nodePath.join(
      process.env.XDG_CACHE_HOME ??
        (process.platform === "win32"
          ? (process.env.LOCALAPPDATA ?? nodePath.join(os.homedir(), "AppData", "Local"))
          : nodePath.join(os.homedir(), ".cache")),
      "bend-lint",
    ) + nodePath.sep,
  );

// What bend-lint says on each run whose rules it built as JavaScript, as it
// found no clang (see findClangOrUndefined).
export const JAVASCRIPT_NOTE =
  "bend-lint: found no clang 14 or newer, so the rules run as JavaScript, about 3 to 8 times slower; install clang to speed them up";

// How the line starts that says the installed bend is another version.
const VERSION_NOTE = "bend-lint: your bend is ";

// Functions
// =========

// Whether a line is one bend-lint prints about how this machine runs it: on
// Windows, that it uses the fork; that the installed bend is another version;
// or that the rules run as JavaScript.
export const isMachineNote = (line: string): boolean =>
  line === PINNED_BEND_NOTE || line === JAVASCRIPT_NOTE || line.startsWith(VERSION_NOTE);

// The clang Bend builds native programs with, if there is one, as Bend's
// cc_find picks it (main.ts): the first of $CC, clang, each clang-NN on PATH
// (the newest first), and on Windows where LLVM's installer puts it, that is
// clang 14 or newer.
export const findClangOrUndefined = (): string | undefined => {
  const listed = (dir: string): string[] => tryGetOrUndefined(() => nodeFs.readdirSync(dir)) ?? [];
  const numbered = [
    ...new Set(
      (process.env.PATH ?? "")
        .split(nodePath.delimiter)
        .flatMap(listed)
        .filter((f) => /^clang-\d+$/.test(f)),
    ),
  ].sort((a, b) => Number(b.slice(6)) - Number(a.slice(6)));
  return [
    ...(process.env.CC === undefined ? [] : [process.env.CC]),
    "clang",
    ...numbered,
    ...(process.platform === "win32"
      ? [nodePath.join(process.env.ProgramFiles ?? "C:\\Program Files", "LLVM", "bin", "clang.exe")]
      : []),
  ].find((cc) => {
    const version = /^(?:Apple )?(?:\w+ )?clang version (\d+)/m.exec(
      spawnSync(cc, ["--version"], { encoding: "utf8" }).stdout ?? "",
    )?.[1];
    return version !== undefined && Number(version) >= 14;
  });
};

// The line bend-lint prints when the `bend` on PATH is another version than
// the Bend in the bend2 folder `dir`, which bend-lint checks and builds with;
// undefined if it is the same, or if none is installed or `bend version` names
// no version. `bend version` takes a third of a second, so its answer is kept
// by the path, size and time of the `bend` that gave it. It runs by name:
// Windows runs a bend.cmd only that way.
export const getBendVersionNoteOrUndefined = async (dir: URL): Promise<string | undefined> => {
  const bend = Bun.which("bend");
  const stat = bend === null ? undefined : nodeFs.statSync(bend, { throwIfNoEntry: false });
  if (bend === null || stat === undefined) {
    return undefined;
  }
  const key = [bend, stat.size, stat.mtimeMs].join(" ");
  const file = url.fileURLToPath(new URL("installed-bend.json", getBendLintCacheDir()));
  const kept = tryGetJsonOrUndefined(file) as { key?: string; version?: string } | undefined;
  const version =
    kept?.key === key
      ? kept.version
      : await new Promise<string | undefined>((resolve) => {
          const said = (e: Error | null, stdout: string): void =>
            resolve(/^bend (\d+\.\d+\.\d+)(?:\r?\n|$)/.exec(e === null ? stdout : "")?.[1]);
          try {
            execFile("bend", ["version"], { encoding: "utf8", timeout: 10_000 }, said);
          } catch (e) {
            said(e as Error, "");
          }
        });
  if (kept?.key !== key) {
    tryWriteJsonAtomically(file, { key, version });
  }
  const pinned = /^const VERSION = "([^"]+)";$/m.exec(
    nodeFs.readFileSync(new URL("main.ts", dir), "utf8"),
  )?.[1];
  return version === undefined || pinned === undefined || version === pinned
    ? undefined
    : `${VERSION_NOTE}${version}, and bend-lint checks with Bend ${pinned}; the two can disagree on a few files`;
};

// How to run the Bend in the bend2 folder `dir`: its CLI (main.ts) on this Bun,
// in an environment that keeps it from asking bend-lang.com, once a day, for a
// newer release (see main.ts).
export const getBendCli = (dir: URL): { cmd: string[]; env: Record<string, string> } => ({
  cmd: [process.execPath, url.fileURLToPath(new URL("main.ts", dir))],
  env: { BEND_NO_TELEMETRY: "1" },
});

// bend2 at `pin` (`<owner>/<repo>/<ref>` on GitHub), kept in <cache>/<pin>/bend2.
// Each file goes in whole (see writeFileAtomically), base.bend last, and none is
// ever replaced: runs at once may each download, while others read the files.
const fetchBend = async (pin: string): Promise<URL> => {
  if (!/^[\w.-]+\/[\w.-]+\/[\w.-]+$/.test(pin)) {
    throw new Error("not a GitHub <owner>/<repo>/<ref>: " + pin);
  }
  const dir = new URL(pin + "/bend2/", getBendLintCacheDir());
  // What a download holds besides base.bend and the effs/ files Base imports.
  const FILES = ["bend.ts", "comp.ts", "main.ts", "safe.ts"];
  const missing = (file: string): boolean => !nodeFs.existsSync(new URL(file, dir));
  if (![...FILES, "base.bend"].some(missing)) {
    return dir;
  }
  const fetched = async (file: string): Promise<[string, string]> => {
    const res = await fetch(`https://raw.githubusercontent.com/${pin}/bend2/${file}`, {
      signal: AbortSignal.timeout(30_000),
    });
    if (!res.ok) {
      throw new Error(`GitHub answered ${res.status} for bend2/${file}`);
    }
    return [file, await res.text()];
  };
  const base = await fetched("base.bend");
  const effs = new Set([...base[1].matchAll(/^\s*import "\.\/(effs\/[^"]+)"/gm)].map((m) => m[1]));
  const odd = [...effs].find((f) => !/^effs\/[\w.-]+$/.test(f));
  if (odd !== undefined) {
    throw new Error("base.bend imports " + odd + ", which is not a plain file in effs/");
  }
  [...(await Promise.all([...effs, ...FILES].map(fetched))), base].forEach(([file, body]) => {
    if (missing(file)) {
      writeFileAtomically(url.fileURLToPath(new URL(file, dir)), body);
    }
  });
  console.error("bend-lint: downloaded bend " + pin + " to " + url.fileURLToPath(dir));
  return dir;
};

// The bend2 folder to load: the pinned Bend's, downloaded if it is not yet.
export const tryGetBend2SourceUrl = async (): Promise<Result<URL, string>> =>
  fetchBend(PINNED_BEND).then(tryGetUrlFromFolderPathOrUrl, (e: unknown) =>
    error(`could not download bend ${PINNED_BEND} (${getErrorMessageFromUnknown(e)})`),
  );
