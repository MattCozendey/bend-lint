// Imports
// =======

import { createHash } from "node:crypto";
import * as nodeFs from "node:fs";
import * as nodePath from "node:path";
import * as url from "node:url";

// Functions
// =========

export const getErrorMessageFromUnknown = (e: unknown): string =>
  e instanceof Error ? e.message : String(e);

// The text's sha256, in hex.
export const digest = (text: string): string => createHash("sha256").update(text).digest("hex");

// The folder at its real path, as a file: URL that ends in `/`, so
// `new URL("file", folder)` finds a file in it.
export const getUrlFromFolder = (dir: string): URL =>
  url.pathToFileURL(nodeFs.realpathSync(dir) + nodePath.sep);
