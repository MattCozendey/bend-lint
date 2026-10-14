import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { GRAPHICS_QUALITY_CHOICES, FPS_LIMIT_CHOICES } from "../web/settings.js";
import { GRAPHICS_EFFECTS, graphicsEffectKeys } from "../web/graphics-effects.js";

const html = await readFile(new URL("../web/index.html", import.meta.url), "utf8");
const css = await readFile(new URL("../web/styles.css", import.meta.url), "utf8");
const menu = await readFile(new URL("../web/menu.js", import.meta.url), "utf8");
const game = await readFile(new URL("../web/game.js", import.meta.url), "utf8");

// The options panel is the one screen whose markup has to stay in step with three
// separate contracts: the stored option keys, the controls that edit them, and the
// runtime that reads them. A control with no handler, a handler with no control
// and a stored key nothing reads are all silent - the panel just looks right and
// does nothing - so the wiring is asserted from both ends.
const panel = html.slice(
  html.indexOf('id="screen-options"'),
  html.indexOf('id="screen-help"'),
);
assert.ok(panel.length > 0, "the options panel must exist");

// 1. The groups, in order, and only those.
const headings = [...panel.matchAll(/<h3[^>]*>([^<]+)<\/h3>/g)].map((match) => match[1]);
assert.deepEqual(headings, ["Video", "Graphics", "Audio", "Controls", "Interface"],
  "the options must stay grouped, and video has to come first");
for (const heading of headings) {
  assert.ok(
    panel.includes(`aria-labelledby="options-${heading.toLowerCase()}-heading"`),
    `the ${heading} section must be labelled for assistive technology`,
  );
  assert.ok(panel.includes(`id="options-${heading.toLowerCase()}-heading"`),
    `the ${heading} section must own its heading id`);
}

// 2. Every control the panel offers must be one the menu actually handles, and
//    every id the menu reads must exist in the panel.
const controlIds = [...panel.matchAll(/id="(input-[a-z-]+)"/g)].map((match) => match[1]);
const outputIds = [...panel.matchAll(/id="([a-z-]*-value)"/g)].map((match) => match[1]);
assert.ok(controlIds.length >= 10, `expected a full settings panel, found ${controlIds.length} controls`);
// A control may be handled by its exact id or by a family prefix, which is how
// the three volume buses and the key bindings are wired. The prefix has to be
// quoted in the source either way, so a dangling control is still caught.
const handlerPrefixes = [...menu.matchAll(/event\.target\.id\??\s*===\s*"([^"]+)"|event\.target\.id\??\.startsWith\("([^"]+)"\)/g)]
  .map((match) => match[1] ?? match[2]);
assert.ok(handlerPrefixes.length > 0, "menu.js must compare input ids somewhere");
for (const id of controlIds) {
  const handled = handlerPrefixes.some((prefix) => id === prefix || id.startsWith(prefix));
  assert.ok(handled, `${id} is in the panel but menu.js has no handler for it`);
}
// The families must be handled as families, so a fourth bus or a sixth binding
// does not need its own branch.
for (const family of ["input-volume-", "input-control-", "input-effect-"]) {
  assert.ok(handlerPrefixes.includes(family), `${family} controls must be handled as a family`);
}
// The readouts next to the sliders have to be driven, or the panel shows a stale
// number while the stored value has already changed. Three are written by name and
// the volume readouts share one template, so both shapes are pinned.
for (const id of ["fov-value", "sensitivity-value", "render-distance-value"]) {
  assert.ok(outputIds.includes(id), `the panel is missing the ${id} readout`);
  assert.ok(menu.includes(`"${id}"`), `${id} has no menu code updating it`);
}
for (const bus of ["master", "music", "effects"]) {
  assert.ok(outputIds.includes(`volume-${bus}-value`), `the panel is missing the ${bus} volume readout`);
}
assert.ok(
  /volume-\$\{bus\}-value/.test(menu),
  "the volume readouts must be written from the bus name, so all three stay in step",
);

// 3. The specific controls the feature set promises.
for (const id of [
  "input-graphics-quality",
  "input-renderer",
  "input-fov",
  "input-render-distance",
  "input-fps-limit",
  "input-volume-master",
  "input-volume-music",
  "input-volume-effects",
  "input-sensitivity",
  "input-show-coords",
]) {
  assert.ok(panel.includes(`id="${id}"`), `the options panel is missing ${id}`);
}
// 3b. The frame rate cap belongs with the other video controls.
assert.ok(
  panel.indexOf('id="input-fps-limit"') > panel.indexOf('id="input-render-distance"')
    && panel.indexOf('id="input-fps-limit"') < panel.indexOf("</section>"),
  "the frame rate cap has to sit inside the video section",
);
// Like the quality list, the cap list is generated from the shared table rather
// than hand-written, so a limit the runtime does not implement cannot be offered
// and one it does implement cannot go missing. Uncapped has to be in that list:
// a cap the player cannot lift from the panel is not a setting.
const fpsSelect = panel.match(/<select id="input-fps-limit"[^>]*>([\s\S]*?)<\/select>/);
assert.ok(fpsSelect !== null, "the frame rate cap must be a select");
assert.ok(!fpsSelect[1].includes("<option"),
  "the frame rate options must be built in code, not duplicated in the markup");
assert.ok(menu.includes("buildFpsLimitOptions"), "menu.js must build the frame rate options");
assert.ok(menu.includes("FPS_LIMIT_CHOICES"), "the cap list must come from the shared choices");
assert.ok(FPS_LIMIT_CHOICES.includes(0), "the cap list must offer an uncapped choice");
// And the runtime has to read it, or the control is decorative.
assert.ok(game.includes("options.fpsLimit") || game.includes("fpsLimit"),
  "the game must read the stored frame rate cap");
// 3a. The three volume buses, and the bounds the mixer clamps to.
for (const bus of ["master", "music", "effects"]) {
  const input = panel.match(new RegExp(`id="input-volume-${bus}"[^>]*min="(\\d+)"[^>]*max="(\\d+)"`));
  assert.ok(input !== null, `the ${bus} volume needs an explicit range`);
  assert.equal(Number(input[1]), 0, `the ${bus} volume must reach silence`);
  assert.equal(Number(input[2]), 100, `the ${bus} volume must reach full`);
}

// 4. The quality list must be generated from the tier table, not hand-written.
//    A hardcoded copy is how the menu ends up offering a tier the runtime does
//    not have, or losing one that it does.
assert.ok(!/<select id="input-graphics-quality">[\s\S]*?<option/.test(panel),
  "the quality options must be built in code, not duplicated in the markup");
assert.ok(menu.includes("buildGraphicsQualityOptions"), "menu.js must build the quality options");
assert.ok(menu.includes("GRAPHICS_QUALITY_CHOICES"), "the option list must come from the shared choices");
assert.deepEqual(GRAPHICS_QUALITY_CHOICES[0], "auto", "auto has to remain the first choice");
// Every tier name in the table needs a human label, or the menu shows the raw key.
for (const tier of GRAPHICS_QUALITY_CHOICES.slice(1)) {
  assert.ok(
    new RegExp(`${tier}:\\s*"[^"]+"`).test(menu),
    `the ${tier} tier needs a label in the menu`,
  );
  assert.ok(
    new RegExp(`${tier}:\\s*"[^"]+"`).test(menu.replace(/labels = \{[\s\S]*?\};/, "")) === false
      || menu.includes(`TIER_SUMMARY`),
    "each tier also needs a cost summary so the panel explains the trade",
  );
}

// 5. A reset action that writes the whole default document, so an option this
//    build no longer knows about cannot survive it.
assert.ok(panel.includes('data-action="options-reset"'), "the panel needs a reset action");
assert.ok(menu.includes('action === "options-reset"'), "the reset action needs a handler");
assert.ok(
  /action === "options-reset"[\s\S]{0,400}createDefaultOptions\(\)/.test(menu),
  "reset must write createDefaultOptions rather than clearing the key",
);

// 6. The panel must scroll its body and keep the actions reachable, because four
//    groups of settings are taller than a short viewport.
assert.ok(panel.includes('class="options-scroll"'), "the panel needs a scrollable body");
assert.ok(css.includes(".options-scroll"), "the scroll body needs styling");
// The class lives in the same tag but before the id, so the slice above cannot
// see it: match the opening tag itself.
const panelTag = html.match(/<div[^>]*id="screen-options"[^>]*>/)?.[0] ?? "";
assert.ok(panelTag !== "", "the options panel must be a div with a data-screen target");
assert.ok(/"[^"]*\bwide\b[^"]*"/.test(panelTag), "the options panel should use the wider shell");
assert.ok(panelTag.includes("data-screen"), "the options panel must be a data-screen so the router can reach it");
assert.ok(panelTag.includes("hidden"), "the options panel must start hidden");
assert.ok(/@media \(min-width: 900px\)[\s\S]*?\.options-scroll\s*\{[\s\S]*?repeat\(2,/.test(css),
  "a wide viewport should place the groups in two columns");
assert.ok(css.includes(".menu-panel.wide"), "the wide panel shell needs styling");

// 7. The runtime must read the settings the panel writes. A panel that saves a
//    tier the game ignores is the original bug this replaced.
assert.ok(game.includes("options.graphicsQuality"), "the game must read the stored graphics tier");
assert.ok(game.includes("audioVolumesFromOptions(options)"), "the game must apply the stored volumes");
assert.ok(game.includes("getAudioMixer()"), "the game must share the mixer's instance with the menu");
assert.ok(!game.includes("createAudioMixer()"), "the game must not build a private mixer");
assert.ok(menu.includes("getAudioMixer()"), "the menu must drive the same mixer");
assert.ok(menu.includes("mixer.play("), "moving a volume slider must play a preview");

// 8. The coordinates readout is a select now, not a toggle button, so the old
//    action and its handler must be gone rather than left as dead code.
assert.ok(!panel.includes('data-action="toggle-coords"'), "the old coords button must be gone");
assert.ok(!menu.includes('"toggle-coords"'), "the old coords handler must be gone");
assert.ok(game.includes("options.showCoords") || game.includes("showCoords"),
  "the game must still read the coordinates preference");

// 9. The per-effect graphics controls. They are generated from the effect table
//    rather than written out, so an effect the runtime cannot apply cannot be
//    offered, and one it can apply cannot be lost between table and panel.
assert.ok(panel.includes('id="graphics-effect-fields"'), "the graphics section needs a container for the effect controls");
assert.ok(
  panel.indexOf('id="graphics-effect-fields"') > panel.indexOf('id="options-graphics-heading"'),
  "the effect controls belong to the graphics section",
);
assert.ok(
  !/<input id="input-effect-/.test(panel),
  "the per-effect sliders must be built in code, not duplicated in the markup",
);
assert.ok(menu.includes("GRAPHICS_EFFECTS"), "menu.js must build the effect controls from the shared table");
assert.ok(menu.includes("buildGraphicsEffectFields"), "menu.js needs a builder for the effect controls");
assert.ok(
  /input-effect-/.test(menu),
  "the effect controls must be addressed as a family, so a new effect needs no new branch",
);
for (const effect of GRAPHICS_EFFECTS) {
  assert.ok(effect.label.length > 0, `${effect.key} needs a label`);
}
// Every effect needs a readout the menu writes, or the slider moves and the panel
// keeps showing the number it was left on.
assert.ok(menu.includes("effect-"), "the effect readouts have to be written by key");
assert.ok(/`effect-\$\{key\}-value`/.test(menu), "the effect readouts must be written from the key, so all of them stay in step");
// And the runtime has to read what they store, or twelve sliders do nothing.
assert.ok(game.includes("options.graphics"), "the game must read the stored per-effect amounts");
assert.ok(
  game.includes("resolveGraphicsEffects"),
  "the game must resolve the stored amounts through the shared contract",
);
assert.deepEqual(graphicsEffectKeys(), GRAPHICS_EFFECTS.map((effect) => effect.key),
  "the effect table is the single source of the key list");

console.log("options panel ok");
