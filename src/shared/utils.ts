// Imports
// =======

import { createHash } from "node:crypto";
import * as nodeFs from "node:fs";
import * as nodePath from "node:path";
import * as url from "node:url";

import { error, ok } from "./result.ts";
import type { Result } from "./result.ts";

// Types
// =====

// How a command ended: its exit code, and what it printed.
export type Outcome = { code: number; out: string; err: string };

// Functions
// =========

// How `cmd` ends when it runs in `cwd`.
export const getCommandOutcome = async (cmd: string[], cwd: string): Promise<Outcome> => {
  const child = Bun.spawn(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  const [code, out, err] = await Promise.all([
    child.exited,
    new Response(child.stdout).text(),
    new Response(child.stderr).text(),
  ]);
  return { code, out, err };
};

export const getErrorMessageFromUnknown = (e: unknown): string =>
  e instanceof Error ? e.message : String(e);

export const getPathWithForwardSlashes = (p: string): string => p.split(nodePath.sep).join("/");

// f's value, or undefined if it throws.
export const tryGetOrUndefined = <T>(f: () => T): T | undefined => {
  try {
    return f();
  } catch {
    return undefined;
  }
};

// The text's sha256, in hex.
export const getSha256Hex = (text: string): string =>
  createHash("sha256").update(text).digest("hex");

// Writes `text` to `file` whole or not at all: to a file beside it, then
// renamed over it.
export const writeFileAtomically = (file: string, text: string): void => {
  const temp = `${file}.${process.pid}.${Date.now()}`;
  nodeFs.writeFileSync(temp, text);
  nodeFs.renameSync(temp, file);
};

// The folder at its real path, as a file: URL that ends in `/`, so
// `new URL("file", folder)` finds a file in it. An error if `dir` cannot be
// resolved.
export const tryGetUrlFromFolderPathOrUrl = (dir: string | URL): Result<URL, string> => {
  try {
    return ok(url.pathToFileURL(nodeFs.realpathSync(dir) + nodePath.sep));
  } catch (e) {
    return error(getErrorMessageFromUnknown(e));
  }
};
