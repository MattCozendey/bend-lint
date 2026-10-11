// Finding bend2, for both versions: the folder the user names, else a
// downloaded release. The docs give the order.

// Imports
// =======

import { spawnSync } from "node:child_process";
import * as nodeFs from "node:fs";
import * as os from "node:os";
import * as nodePath from "node:path";

import pkg from "../../package.json" with { type: "json" };
import { error } from "./result.ts";
import type { Result } from "./result.ts";
import { getErrorMessageFromUnknown, tryGetUrlFromFolder } from "./utils.ts";

// Constants
// =========

// What a download holds besides base.bend and the effs/ files Base imports.
const FILES = ["bend.ts", "comp.ts", "main.ts", "safe.ts"];

// How to name a bend2 folder, for a caller that takes only BEND_DIR.
export const GIVE = "set BEND_DIR to a bend checkout";

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

export const getInstalledBendTagOrUndefined = (
  readBendVersion = (): string | undefined => {
    const r = spawnSync("bend", ["version"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    return r.status === 0 ? r.stdout : undefined;
  },
): string | undefined => {
  const version = readBendVersion()?.match(/^bend (\d+\.\d+\.\d+)\b/)?.[1];
  return version === undefined ? undefined : "v" + version;
};

// bend2 at a release, kept in <downloadDir>/<tag>/bend2.
// A download goes to a temporary folder first, so `downloadDir` never holds a
// partial one.
export const fetchBend = async (tag: string, downloadDir: string = CACHE): Promise<string> => {
  if (!/^v\d+\.\d+\.\d+$/.test(tag)) {
    throw new Error("not a bend release: " + tag);
  }
  const dir = nodePath.join(downloadDir, tag, "bend2");
  const whole = (): boolean =>
    [...FILES, "base.bend"].every((f) => nodeFs.existsSync(nodePath.join(dir, f)));
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
  nodeFs.mkdirSync(nodePath.join(downloadDir, tag), { recursive: true });
  const part = nodeFs.mkdtempSync(nodePath.join(downloadDir, tag, ".part-"));
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
  console.error("bend-lint: downloaded bend " + tag + " to " + dir);
  return dir;
};

// The bend2 folder to load: in `bendDir`, a checkout or its bend2 folder, else
// a download. An error does not tell how to name one; the caller does.
export const tryGetBend2SourceUrl = async ({
  bendDir = process.env.BEND_DIR,
  readBendVersion,
  downloadDir,
}: {
  bendDir?: string;
  readBendVersion?: () => string | undefined;
  downloadDir?: string;
} = {}): Promise<Result<URL, string>> => {
  if (bendDir === undefined) {
    const tag = getInstalledBendTagOrUndefined(readBendVersion) ?? PIN;
    return fetchBend(tag, downloadDir).then(tryGetUrlFromFolder, (e: unknown) =>
      error(`could not download bend ${tag} (${getErrorMessageFromUnknown(e)})`),
    );
  }
  const dir = nodePath.resolve(bendDir);
  const found = [nodePath.join(dir, "bend2"), dir].find((d) =>
    nodeFs.existsSync(nodePath.join(d, "bend.ts")),
  );
  return found === undefined
    ? error(`no bend2 at ${dir} (it needs bend.ts)`)
    : tryGetUrlFromFolder(found);
};
