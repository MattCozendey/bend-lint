// What the rewrite's tests share: lint files with the host, and read what it
// reports.

// Imports
// =======

import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

// Types
// =====

// A finding as the host prints it: its code, the name of its file, its text
// from where it starts to the end of that line, its message, and its fixes.
export type Found = { code: string; file: string; text: string; message: string; fixes: string[] };

// Constants
// =========

const HOST = fileURLToPath(new URL("./host.ts", import.meta.url));
const LINE = /^(.+):(\d+): ([\w/-]+): (.*)$/;
const FIX = /^ {2}fix: (.*)$/;

// Functions
// =========

// Writes `files` (names to text) into `dir`, lints `named` there with `args`,
// and gives what the host reports, in order.
export const lintIn = (
  dir: string,
  files: Record<string, string>,
  named: string,
  args: string[],
): Found[] => {
  Object.entries(files).forEach(([name, text]) => fs.writeFileSync(path.join(dir, name), text));
  const out = Bun.spawnSync(["bun", HOST, path.join(dir, named), ...args]).stdout.toString();
  return out.split(/\r?\n/).reduce<Found[]>((found, line) => {
    const fix = FIX.exec(line);
    const last = found[found.length - 1];
    if (fix !== null && last !== undefined) {
      return [...found.slice(0, -1), { ...last, fixes: [...last.fixes, fix[1]] }];
    }
    const m = LINE.exec(line);
    if (m === null) {
      return found;
    }
    const file = path.basename(m[1]);
    const points = (files[file] ?? "").match(/./gsu) ?? [];
    return [
      ...found,
      {
        code: m[3],
        file,
        text: points.slice(Number(m[2])).join("").split("\n")[0],
        message: m[4],
        fixes: [],
      },
    ];
  }, []);
};
