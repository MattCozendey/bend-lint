// Where a given Bend is: the lookup that both versions make for a folder
// the user names.

// Imports
// =======

import * as nodeFs from "node:fs";
import * as nodePath from "node:path";

// Functions
// =========

// The bend2 folder in `chosen`, a checkout or its bend2 folder: the first
// that holds bend.ts. A throw ends with `give`, which tells how to name one.
export const bend2In = (chosen: string, give: string): string => {
  const dir = nodePath.resolve(chosen);
  const found = [nodePath.join(dir, "bend2"), dir].find((d) =>
    nodeFs.existsSync(nodePath.join(d, "bend.ts")),
  );
  if (found === undefined) {
    throw new Error(`no bend2 at ${dir} (it needs bend.ts); ${give}`);
  }
  return found;
};
