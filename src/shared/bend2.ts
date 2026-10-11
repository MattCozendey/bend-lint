// Finding bend2: the folder the user names, else a
// downloaded release. The docs give the order.

// Imports
// =======

import { execFile } from "node:child_process";
import * as nodeFs from "node:fs";
import * as os from "node:os";
import * as nodePath from "node:path";
import * as url from "node:url";

import pkg from "../../package.json" with { type: "json" };
import { ERROR, error, mapError, ok } from "./result.ts";
import type { Result } from "./result.ts";
import { getErrorMessageFromUnknown, tryGetUrlFromFolderPathOrUrl } from "./utils.ts";

// Constants
// =========

// The newest bend release this repo's checks passed with; src/meta/sync-bend.ts
// moves it.
export const PINNED_BEND_RELEASE_TAG: string = pkg.bendRelease;

// Functions
// =========

// bend-lint's cache: downloaded bends, one folder per release, and what the
// server keeps.
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

// The installed bend's release ("v2.0.36"), or undefined if bend is not
// installed. An error if `bend version` fails, runs too long, or names no
// release.
export const tryGetInstalledBendTagFromCliOrUndefined = async (): Promise<
  Result<string | undefined, string>
> => {
  const VERSION_CHECK_TIMEOUT_IN_MS = 10_000;
  const read = await new Promise<Result<string | undefined, string>>((resolve) => {
    execFile(
      "bend",
      ["version"],
      { encoding: "utf8", timeout: VERSION_CHECK_TIMEOUT_IN_MS },
      (e, stdout) => {
        resolve(
          e === null
            ? ok(stdout)
            : e.code === "ENOENT"
              ? ok(undefined)
              : error(
                  e.killed
                    ? `bend version ran over ${VERSION_CHECK_TIMEOUT_IN_MS / 1000} s`
                    : `bend version failed (${e.message})`,
                ),
        );
      },
    );
  });
  if (ERROR in read || read.OK === undefined) {
    return read;
  }
  const version = /^bend (\d+\.\d+\.\d+)(?:\r?\n|$)/.exec(read.OK)?.[1];
  return version === undefined
    ? error(`bend version printed ${JSON.stringify(read.OK.split("\n")[0])}, not a release`)
    : ok("v" + version);
};

// bend2 at a release, kept in <cache>/<tag>/bend2.
// A download goes to a temporary folder first, so the cache never holds a
// partial one.
const fetchBend = async (tag: string): Promise<URL> => {
  if (!/^v\d+\.\d+\.\d+$/.test(tag)) {
    throw new Error("not a bend release: " + tag);
  }
  const release = new URL(tag + "/", getBendLintCacheDir());
  const dir = new URL("bend2/", release);
  // What a download holds besides base.bend and the effs/ files Base imports.
  const FILES = ["bend.ts", "comp.ts", "main.ts", "safe.ts"];
  const whole = (): boolean =>
    [...FILES, "base.bend"].every((f) => nodeFs.existsSync(new URL(f, dir)));
  if (whole()) {
    return dir;
  }
  const fetched = async (file: string): Promise<[string, string]> => {
    const res = await fetch(
      `https://raw.githubusercontent.com/bendlang/bend/${tag}/bend2/${file}`,
      { signal: AbortSignal.timeout(30_000) },
    );
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
  const files = [base, ...(await Promise.all([...FILES, ...effs].map(fetched)))];
  nodeFs.mkdirSync(release, { recursive: true });
  const part = url.pathToFileURL(
    nodeFs.mkdtempSync(url.fileURLToPath(new URL(".part-", release))) + nodePath.sep,
  );
  files.forEach(([file, body]) => {
    const to = new URL(file, part);
    nodeFs.mkdirSync(new URL(".", to), { recursive: true });
    nodeFs.writeFileSync(to, body);
  });
  try {
    nodeFs.rmSync(dir, { recursive: true, force: true });
    nodeFs.renameSync(part, dir);
  } catch (e) {
    nodeFs.rmSync(part, { recursive: true, force: true });
    if (!whole()) {
      throw e;
    }
  }
  console.error("bend-lint: downloaded bend " + tag + " to " + url.fileURLToPath(dir));
  return dir;
};

// The bend2 folder to load: in `bendDir`, a checkout or its bend2 folder, else
// a download.
const tryFindBend2SourceUrl = async (bendDir: string | undefined): Promise<Result<URL, string>> => {
  if (bendDir === undefined) {
    const installed = await tryGetInstalledBendTagFromCliOrUndefined();
    if (ERROR in installed) {
      return error(`could not read the installed bend's release (${installed[ERROR]})`);
    }
    const tag = installed.OK ?? PINNED_BEND_RELEASE_TAG;
    return fetchBend(tag).then(tryGetUrlFromFolderPathOrUrl, (e: unknown) =>
      error(`could not download bend ${tag} (${getErrorMessageFromUnknown(e)})`),
    );
  }
  const dir = nodePath.resolve(bendDir);
  const found = [nodePath.join(dir, "bend2"), dir].find((d) =>
    nodeFs.existsSync(nodePath.join(d, "bend.ts")),
  );
  return found === undefined
    ? error(`no bend2 at ${dir} (it needs bend.ts)`)
    : tryGetUrlFromFolderPathOrUrl(found);
};

// The bend2 folder to load. An error tells how to name one.
export const tryGetBend2SourceUrl = async ({
  bendDir = process.env.BEND_DIR,
}: { bendDir?: string } = {}): Promise<Result<URL, string>> =>
  mapError(await tryFindBend2SourceUrl(bendDir), (e) => e + "; set BEND_DIR to a bend checkout");
