// Imports
// =======

import { createHash } from "node:crypto";
import * as nodeFs from "node:fs";
import * as nodePath from "node:path";
import * as url from "node:url";

import { error, ok } from "./result.ts";
import type { Result } from "./result.ts";

// Functions
// =========

export const getErrorMessageFromUnknown = (e: unknown): string =>
  e instanceof Error ? e.message : String(e);

// The text's sha256, in hex.
export const digest = (text: string): string => createHash("sha256").update(text).digest("hex");

// The folder at its real path, as a file: URL that ends in `/`, so
// `new URL("file", folder)` finds a file in it. An error if `dir` is not a
// folder, or cannot be resolved.
export const tryGetUrlFromFolderPathOrUrl = (dir: string | URL): Result<URL, string> => {
  try {
    const real = nodeFs.realpathSync(dir);
    return nodeFs.statSync(real).isDirectory()
      ? ok(url.pathToFileURL(real + nodePath.sep))
      : error(`${real} is not a folder`);
  } catch (e) {
    return error(getErrorMessageFromUnknown(e));
  }
};
