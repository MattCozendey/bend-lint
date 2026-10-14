import { mkdir, rm } from "node:fs/promises";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(fileURLToPath(new URL("../", import.meta.url)));
const requested = process.argv[2] ?? "dist";
const output = path.resolve(root, requested);

if (output === root || !output.startsWith(`${root}${path.sep}`)) {
  throw new Error(`Refusing to clean output outside the repository: ${output}`);
}

await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
console.log(`Cleaned ${path.relative(root, output) || "."}`);
