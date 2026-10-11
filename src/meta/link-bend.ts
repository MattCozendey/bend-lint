// Points .bend2 at the Bend bend-lint loads, so tsconfig's bend2/* finds
// its types.

// Imports
// =======

import * as fs from "node:fs";
import * as path from "node:path";
import * as url from "node:url";

import { GIVE, tryGetBend2SourceUrl } from "../shared/bend2.ts";
import { mapError, unwrap } from "../shared/result.ts";

// Constants
// =========

const LINK = path.resolve(import.meta.dir, "..", "..", ".bend2");

// Side effects
// ============

const dir = url.fileURLToPath(
  unwrap(mapError(await tryGetBend2SourceUrl(), (e) => e + "; " + GIVE)),
);
const now = fs.lstatSync(LINK, { throwIfNoEntry: false });
if (now !== undefined && !now.isSymbolicLink()) {
  throw new Error(LINK + " is not a link; move it away");
}
if (now !== undefined) fs.unlinkSync(LINK);
fs.symlinkSync(dir, LINK, "junction");
