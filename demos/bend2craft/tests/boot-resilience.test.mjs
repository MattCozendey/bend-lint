import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const game = await readFile(new URL("web/game.js", root), "utf8");
const main = await readFile(new URL("web/main.js", root), "utf8");
const chunkWorker = await readFile(new URL("web/chunk-worker-entry.js", root), "utf8");
const capabilities = await readFile(new URL("web/webgpu-capabilities.js", root), "utf8");

assert.match(chunkWorker, /pathGrid/, "the chunk worker must own asynchronous path-grid construction");
assert.match(chunkWorker, /Villagers\.path_grid/, "path-grid construction must remain Bend-owned");
assert.match(game, /villagerPathWorker/, "the game must schedule path-grid work off the main thread");
assert.match(game, /villagerPathGrid\s*=\s*null/, "path-grid state must start asynchronously");
assert.doesNotMatch(game, /let villagerPathGrid\s*=\s*Villagers\.path_grid/, "path-grid construction must not block boot");
assert.match(main, /loading\?\.removeAttribute\("hidden"\)/, "the loading shell must be visible before the game module evaluates");
assert.match(capabilities, /withTimeout/, "WebGPU probes must have a bounded failure path");
assert.match(game, /withTimeout/, "renderer initialization must have a bounded failure path");

console.log("boot resilience contract ok");
