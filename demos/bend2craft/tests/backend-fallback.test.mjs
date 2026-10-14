import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  BACKEND_NOTICE_KEY,
  describeBackendNotice,
  reportBackendFailureAndReturnToMenu,
  takeBackendNotice,
} from "../web/backend-notice.js";

function memoryStore(initial = {}) {
  const data = new Map(Object.entries(initial));
  return {
    map: data,
    getItem: (key) => (data.has(key) ? data.get(key) : null),
    setItem: (key, value) => { data.set(key, String(value)); },
    removeItem: (key) => { data.delete(key); },
  };
}

function fakeLocation(href = "http://127.0.0.1:3000/?play=1&renderer=webgpu") {
  const target = new URL(href);
  return {
    href: target.toString(),
    origin: target.origin,
    assign(next) { this.assigned = next; },
  };
}

// The whole point of the module: a failed backend must leave an address the menu
// can boot. A navigate that keeps ?play=1 is the same dead page again.
// A realistic setup: the options the player has already configured live in
// localStorage, and the one-shot notice has its own sessionStorage.
const optionsStore = memoryStore({
  "bend2craft-options": JSON.stringify({
    renderer: "webgpu",
    graphicsQuality: "ultra",
    volumeMaster: 0.35,
    controls: { attack: "KeyF" },
  }),
});
const noticeStore = memoryStore();
const location = fakeLocation();
const reason = reportBackendFailureAndReturnToMenu({
  renderer: "webgpu",
  reason: "device lost: destroyed",
  noticeStore,
  optionsStore,
  location,
});
assert.equal(reason, "device lost: destroyed");
assert.ok(location.assigned, "a backend failure must navigate somewhere");
const arrived = new URL(location.assigned);
assert.equal(arrived.searchParams.get("play"), null, "the menu must not boot the world again");
assert.equal(arrived.searchParams.get("renderer"), null, "the failed backend must not be re-selected by the URL");
assert.equal(arrived.searchParams.get("renderer-fallback"), "1");
assert.ok(arrived.pathname.length > 0);

// The pin has to be released, or the next launch walks into the same wall before
// the player can reach the setting that would fix it. This is the release that
// matters: the options document lives in localStorage, so writing the preference
// anywhere else leaves the pin in place and the player bounces between the world
// and the menu forever.
assert.equal(noticeStore.getItem("bend2craft-options"), null,
  "the options document must not be written into the notice store");
assert.notEqual(noticeStore.getItem(BACKEND_NOTICE_KEY), null,
  "the notice belongs in the notice store");
const released = JSON.parse(optionsStore.getItem("bend2craft-options"));
assert.equal(released.renderer, "auto");
// Read-modify-write, not overwrite: the volumes, the tier and the key bindings the
// player configured are not the backend's business to reset.
assert.equal(released.graphicsQuality, "ultra", "releasing the backend must not reset the graphics tier");
assert.equal(released.volumeMaster, 0.35, "releasing the backend must not reset the volumes");
assert.equal(released.controls?.attack, "KeyF", "releasing the backend must not reset the key bindings");
assert.equal(JSON.parse(noticeStore.getItem(BACKEND_NOTICE_KEY)).renderer, "webgpu");

// The notice survives the navigation and is readable by the menu.
const notice = takeBackendNotice(noticeStore);
assert.deepEqual(notice, { renderer: "webgpu", reason: "device lost: destroyed" });
assert.equal(takeBackendNotice(noticeStore), null, "the notice is one-shot");
assert.match(describeBackendNotice(notice), /WebGPU could not start/);
assert.match(describeBackendNotice(notice), /device lost: destroyed/, "the reason must reach the player");
assert.equal(describeBackendNotice(null), "");

// A corrupt options document is replaced rather than half-parsed.
const corruptOptions = memoryStore({ "bend2craft-options": "{not json" });
const corruptLocation = fakeLocation();
reportBackendFailureAndReturnToMenu({
  renderer: "webgpu",
  reason: "no adapter",
  noticeStore: memoryStore(),
  optionsStore: corruptOptions,
  location: corruptLocation,
});
assert.equal(JSON.parse(corruptOptions.getItem("bend2craft-options")).renderer, "auto",
  "a corrupt options document must still end up with the backend released");

// A storage that refuses writes must not strand the player on the dead page.
const hostile = {
  getItem() { throw new Error("blocked"); },
  setItem() { throw new Error("blocked"); },
  removeItem() { throw new Error("blocked"); },
};
const stillNavigates = fakeLocation();
reportBackendFailureAndReturnToMenu({
  renderer: "webgpu",
  reason: "no adapter",
  noticeStore: hostile,
  optionsStore: hostile,
  location: stillNavigates,
});
assert.ok(stillNavigates.assigned, "a blocked storage must not stop the navigation");
assert.equal(takeBackendNotice(hostile), null, "a blocked storage yields no notice rather than throwing");

// A junk or empty reason still produces a usable sentence.
for (const bad of [undefined, null, "", "   "]) {
  const line = describeBackendNotice({ renderer: "webgpu", reason: bad });
  assert.match(line, /WebGPU could not start/, `a missing reason must still explain (${JSON.stringify(bad)})`);
  assert.doesNotMatch(line, /undefined|null/, "the sentence must not leak a placeholder");
}

// The renderer source has to actually wire the two failure paths, because a lost
// device is invisible at runtime: no throw, no error, just a still image.
const renderer = await readFile(new URL("../web/webgpu-terrain-renderer.js", import.meta.url), "utf8");
assert.match(renderer, /device\.lost\?\.then/, "a lost device must be observed");
assert.match(renderer, /"uncapturederror"/, "an uncaptured GPU error must be observed");
assert.match(renderer, /getDeviceFailure:/, "the failure must be readable after the fact");
assert.match(renderer, /onDeviceFailure:/, "the failure must be reportable immediately");
assert.match(renderer, /GPU_READBACK_TIMEOUT_MS/,
  "a buffer readback that never settles must be bounded, or it wedges the pipeline forever");
assert.equal((renderer.match(/mapAsync\(/g) ?? []).length, 1,
  "every mapAsync must go through the bounded helper");

// And the game has to act on it rather than freeze.
const game = await readFile(new URL("../web/game.js", import.meta.url), "utf8");
assert.match(game, /gpuRenderer\.onDeviceFailure\(/, "the game must react to a lost device");
assert.match(game, /reportBackendFailureAndReturnToMenu\(\{ renderer: "webgpu", reason: failure\.reason \}\)/,
  "a lost device must hand the player back to the menu");
assert.doesNotMatch(
  game,
  /if \(requestedRenderer !== "auto"\) throw error;/,
  "an explicit WebGPU request must still fall back, not throw the player onto a dead page",
);

// The menu must gate the option on a real probe, or it offers a choice that hangs.
const menu = await readFile(new URL("../web/menu.js", import.meta.url), "utf8");
assert.match(menu, /probeWebGpu\(/, "the menu must probe before offering the option");
assert.match(menu, /option\.disabled = !probe\.supported/, "an unavailable backend must be disabled");
assert.match(menu, /takeBackendNotice\(/, "the menu must read the pending notice");
assert.match(menu, /describeBackendNotice\(/, "the menu must explain the notice in words");
assert.match(menu, /renderer: "auto"/, "an unusable stored pin must be released by the menu too");

// The flag that tells the pin check a backend actually failed has to be readable
// by both the notice reader and the check. Declaring it inside the menu closure
// while the reader sits at module scope makes the assignment throw, the flag stay
// false, and the pin survive - which is a silent return to the same bug.
assert.equal((menu.match(/let failedBackendNotice/g) ?? []).length, 1,
  "the failure flag must be declared exactly once");
assert.ok(menu.includes("failedBackendNotice = notice !== null"),
  "the notice reader must set the flag from the notice it read");
assert.ok(menu.includes("!failedBackendNotice"),
  "the pin check must consult the flag, or a failed backend is pinned again");
// Module-scope declarations in this file are unindented; an indented one is inside
// the menu closure, where the module-level notice reader cannot reach it, and the
// assignment then throws and the flag stays false - which silently restores the
// bounce loop this flag exists to prevent.
const declarationLine = menu.split("\n").find((line) => line.includes("let failedBackendNotice"));
assert.ok(declarationLine !== undefined, "the failure flag must be declared");
assert.ok(!declarationLine.startsWith(" ") && !declarationLine.startsWith("\t"),
  `the failure flag must be at module scope, found: ${JSON.stringify(declarationLine)}`);

console.log("backend fallback ok");
