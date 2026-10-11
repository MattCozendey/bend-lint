// fs and path that give real paths with `/`, for both versions' patched
// bend.ts: Bend resolves imports with path.posix, so on Windows it needs
// them.

// Imports
// =======

import * as nodeFs from "node:fs";
import * as nodePath from "node:path";

// Constants
// =========

const DRIVE = /^[A-Za-z]:(?=\/)/;

// Functions
// =========

export const slash = (p: string): string => p.split(nodePath.sep).join("/");

// path.posix.resolve from `cwd`, where a drive letter is a root.
export const resolve = (cwd: string, ...ps: string[]): string => {
  const all = [cwd, ...ps].map(slash);
  const drive =
    all
      .filter((p) => DRIVE.test(p))
      .at(-1)
      ?.slice(0, 2) ?? "";
  return drive + nodePath.posix.resolve(...all.map((p) => p.replace(DRIVE, "")));
};

export const relative = (from: string, to: string): string =>
  nodePath.posix.relative(slash(from).replace(DRIVE, ""), slash(to).replace(DRIVE, ""));

export const fs = {
  ...nodeFs,
  realpathSync: (p: nodeFs.PathLike): string => slash(nodeFs.realpathSync(p)),
};

export const path = {
  ...nodePath,
  join: (...ps: string[]): string => slash(nodePath.join(...ps)),
  resolve: (...ps: string[]): string => slash(nodePath.resolve(...ps)),
  posix: {
    ...nodePath.posix,
    resolve: (...ps: string[]): string => resolve(process.cwd(), ...ps),
    relative,
  },
};
