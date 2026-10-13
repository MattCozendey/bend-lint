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

// How `cmd` ends, run in `cwd`, with `env` added to this process's environment.
export const getCommandOutcome = async (
  cmd: string[],
  cwd: string,
  env: Record<string, string> = {},
): Promise<Outcome> => {
  const child = Bun.spawn(cmd, {
    cwd,
    env: { ...process.env, ...env },
    stdout: "pipe",
    stderr: "pipe",
  });
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
export const tryGet = <T>(f: () => T): T | undefined => {
  try {
    return f();
  } catch {
    return undefined;
  }
};

export const getSha256Hex = (text: string): string =>
  createHash("sha256").update(text).digest("hex");

// Writes `text` to `file` whole or not at all: to a file beside it, in the
// file's folder, made if need be, then renamed over it.
export const writeFileAtomically = (file: string, text: string): void => {
  nodeFs.mkdirSync(nodePath.dirname(file), { recursive: true });
  const temp = `${file}.${process.pid}.${Date.now()}`;
  nodeFs.writeFileSync(temp, text);
  nodeFs.renameSync(temp, file);
};

// The JSON value in `file`, or undefined if it cannot be read.
export const tryGetJson = (file: string): unknown =>
  tryGet(() => JSON.parse(nodeFs.readFileSync(file, "utf8")) as unknown);

// Writes `value` to `file` as JSON, whole or not at all; a write that fails is skipped.
export const tryWriteJsonAtomically = (file: string, value: unknown): void => {
  tryGet(() => writeFileAtomically(file, JSON.stringify(value)));
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
