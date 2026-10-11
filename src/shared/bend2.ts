// Finding bend2, for both versions: the folder the user names, else a
// downloaded release. The docs give the order.

// Imports
// =======

import { spawnSync } from "node:child_process";
import * as nodeFs from "node:fs";
import * as os from "node:os";
import * as nodePath from "node:path";

import pkg from "../../package.json" with { type: "json" };
import { getErrorMessageFromUnknown } from "./result.ts";

// Types
// =====

export type Get = (url: string) => Promise<Response>;

// How findBend2 reaches the network, runs `bend`, and where it caches;
// tests give their own. run gives a command's stdout, or undefined if it
// fails.
export type FindOptions = {
  get?: Get;
  run?: (cmd: string[]) => string | undefined;
  cache?: string;
};

// Constants
// =========

const RAW = "https://raw.githubusercontent.com/bendlang/bend/";
const RELEASE = /^v\d+\.\d+\.\d+$/;
const EFF = /^effs\/[\w.-]+$/;

// What a download holds besides base.bend and the effs/ files Base imports.
const FILES = ["bend.ts", "comp.ts", "main.ts", "safe.ts"];

// The newest bend release this repo's checks passed with; scripts/sync-bend.ts
// moves it.
export const PIN: string = pkg.bendRelease;

// bend-lint's cache: downloaded bends, one folder per release, and what each
// version keeps.
export const CACHE: string = nodePath.join(
  process.env.XDG_CACHE_HOME ??
    (process.platform === "win32"
      ? (process.env.LOCALAPPDATA ?? nodePath.join(os.homedir(), "AppData", "Local"))
      : nodePath.join(os.homedir(), ".cache")),
  "bend-lint",
);

// Functions
// =========

// A response's text, or a rejection naming its status.
const text = (res: Response, what: string): Promise<string> =>
  res.ok ? res.text() : Promise.reject(new Error(`GitHub answered ${res.status}${what}`));

// fetch, given up after 30 seconds.
const download = (url: string): Promise<Response> =>
  fetch(url, { signal: AbortSignal.timeout(30_000) });

// A command's stdout, or undefined if it does not run or fails.
const spawn = (cmd: string[]): string | undefined => {
  const r = spawnSync(cmd[0], cmd.slice(1), {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  });
  return r.error === undefined && r.status === 0 ? r.stdout : undefined;
};

// The bend2 folder in `chosen`, a checkout or its bend2 folder: the first
// that holds bend.ts. A throw ends with `give`, which tells how to name one.
const bend2In = (chosen: string, give: string): string => {
  const dir = nodePath.resolve(chosen);
  const found = [nodePath.join(dir, "bend2"), dir].find((d) =>
    nodeFs.existsSync(nodePath.join(d, "bend.ts")),
  );
  if (found === undefined) {
    throw new Error(`no bend2 at ${dir} (it needs bend.ts); ${give}`);
  }
  return found;
};

// The installed bend's release ("v2.0.36"), or undefined if `bend version`
// does not run.
export const installedTag = (
  run: (cmd: string[]) => string | undefined = spawn,
): string | undefined => {
  const version = run(["bend", "version"])?.match(/^bend (\d+\.\d+\.\d+)\b/)?.[1];
  return version === undefined ? undefined : "v" + version;
};

// bend2 at a release, kept in <cache>/<tag>/bend2.
// A download goes to a temporary folder first, so the cache never holds a
// partial one.
export const fetchBend = async (
  tag: string,
  cache: string = CACHE,
  get: Get = download,
): Promise<string> => {
  if (!RELEASE.test(tag)) {
    throw new Error("not a bend release: " + tag);
  }
  const dir = nodePath.join(cache, tag, "bend2");
  const whole = (): boolean =>
    [...FILES, "base.bend"].every((f) => nodeFs.existsSync(nodePath.join(dir, f)));
  if (whole()) {
    return dir;
  }
  const fetched = (file: string): Promise<[string, string]> =>
    get(`${RAW}${tag}/bend2/${file}`)
      .then((res) => text(res, ` for bend2/${file}`))
      .then((body) => [file, body]);
  const base = await fetched("base.bend");
  const effs = [
    ...new Set([...base[1].matchAll(/^\s*import "\.\/(effs\/[^"]+)"/gm)].map((m) => m[1])),
  ];
  const odd = effs.find((f) => !EFF.test(f));
  if (odd !== undefined) {
    throw new Error("base.bend imports " + odd + ", which is not a plain file in effs/");
  }
  const files = [base, ...(await Promise.all([...FILES, ...effs].map(fetched)))];
  nodeFs.mkdirSync(nodePath.join(cache, tag), { recursive: true });
  const part = nodeFs.mkdtempSync(nodePath.join(cache, tag, ".part-"));
  files.forEach(([file, body]) => {
    nodeFs.mkdirSync(nodePath.dirname(nodePath.join(part, file)), { recursive: true });
    nodeFs.writeFileSync(nodePath.join(part, file), body);
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
  return dir;
};

// The real path of the bend2 folder to load: `chosen`, else a download. A
// throw ends with `give`, which tells how to name one.
export const findBend2 = async (
  chosen: string | undefined,
  give: string,
  { get = download, run = spawn, cache = CACHE }: FindOptions = {},
): Promise<string> => {
  if (chosen !== undefined) {
    return nodeFs.realpathSync(bend2In(chosen, give));
  }
  const tag = installedTag(run) ?? PIN;
  const fresh = !nodeFs.existsSync(nodePath.join(cache, tag, "bend2"));
  const got = await fetchBend(tag, cache, get).catch((e: unknown) => {
    throw new Error(`could not download bend ${tag} (${getErrorMessageFromUnknown(e)}); ${give}`);
  });
  if (fresh) {
    console.error("bend-lint: downloaded bend " + tag + " to " + got);
  }
  return nodeFs.realpathSync(got);
};
