import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const launcher = await readFile(new URL("Jogar-Bend2Craft.bat", root), "utf8");
const packageJson = JSON.parse(await readFile(new URL("package.json", root), "utf8"));
const server = await readFile(new URL("scripts/play-server.mjs", root), "utf8");

const buildAt = launcher.indexOf("npm run build");
const serveAt = launcher.indexOf("play-server.mjs");
assert.ok(buildAt >= 0, "the launcher must build the current bundle");
assert.ok(serveAt > buildAt, "the launcher must build before serving");
assert.match(launcher, /wsl\.exe/, "the launcher must use the WSL toolchain for the build");
assert.match(launcher, /play-server\.mjs --open/, "the server must open the browser after listening");
assert.doesNotMatch(launcher, /timeout\s+\/t\s+2/, "the launcher must not use a fixed browser-open delay");
assert.match(packageJson.scripts.build, /clean-output\.mjs/, "builds must remove stale output");
assert.match(server, /renderer=webgl/, "the launcher must open the verified WebGL path by default");
assert.match(server, /no-store/, "the local server must disable stale browser caching");
assert.match(server, /server\.on\("error"/, "the local server must report bind failures clearly");
assert.match(server, /rundll32\.exe/, "Windows browser opening must not spawn a command shell");
assert.doesNotMatch(server, /cmd\.exe/, "the server must not create a command-shell window");
assert.match(server, /windowsHide/, "automatic browser opening must stay hidden on Windows");

console.log("startup contract ok");
