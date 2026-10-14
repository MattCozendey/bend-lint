import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const html = await readFile(new URL("../web/index.html", import.meta.url), "utf8");
const css = await readFile(new URL("../web/styles.css", import.meta.url), "utf8");

function channel(value) {
  const normalized = value / 255;
  return normalized <= 0.03928 ? normalized / 12.92 : ((normalized + 0.055) / 1.055) ** 2.4;
}

function luminance(hex) {
  const value = hex.replace("#", "");
  const [r, g, b] = [0, 2, 4].map((offset) => parseInt(value.slice(offset, offset + 2), 16));
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}

function contrastRatio(first, second) {
  const light = Math.max(luminance(first), luminance(second));
  const dark = Math.min(luminance(first), luminance(second));
  return (light + 0.05) / (dark + 0.05);
}

function openingTag(source, id) {
  const match = source.match(new RegExp(`<[^>]*\\bid="${id}"[^>]*>`));
  assert.ok(match, `missing #${id}`);
  return match[0];
}

const title = openingTag(html, "screen-title");
assert.doesNotMatch(title, /\bmenu-panel\b/, "the title must not be a centered card");
assert.match(openingTag(html, "world-preview"), /aria-hidden="true"/, "the menu needs a world-first backdrop");
assert.match(html, /data-action="continue-world"/, "returning players need one-step world entry");

const menu = openingTag(html, "menu");
for (const attribute of [/role="dialog"/, /aria-modal="true"/, /aria-label="[^"]+"/]) {
  assert.match(menu, attribute);
}

const loading = openingTag(html, "screen-loading");
for (const attribute of [/role="status"/, /aria-live="polite"/, /aria-busy="true"/]) {
  assert.match(loading, attribute);
}

assert.match(html, /id="loading-progress"[^>]*aria-label="World loading progress"/, "loading needs a tangible progress surface");
assert.match(html, /id="xp-hud"[\s\S]*?id="xp-track"[^>]*role="progressbar"/, "survival feedback needs a visible experience track");
assert.match(openingTag(html, "survival-announcer"), /role="status"[^>]*aria-live="polite"/, "meaningful survival changes need a low-frequency live status");
assert.match(openingTag(html, "game"), /tabindex="0"/, "the canvas needs a focusable browser-game surface");
const menuProgress = openingTag(html, "menu-loading-progress");
assert.doesNotMatch(menuProgress, /aria-valuenow/, "the redirect transition should not claim world-generation percentages");
assert.match(menuProgress, /aria-busy="true"/, "the redirect transition needs an explicit busy state");
assert.match(css, /#menu-loading-progress span\s*\{[^}]*animation:\s*menu-loading-sweep/s, "the redirect transition must be visually indeterminate");
assert.match(html, /id="inventory-panel"[^>]*role="dialog"[^>]*aria-modal="true"/, "inventory needs modal semantics");
assert.doesNotMatch(css, /#held-item-view\s*\{[^}]*display:\s*none\s*!important/s, "the held-item fallback must not be permanently hidden");
assert.doesNotMatch(css, /#menu\b[^{}]*\{[^}]*(?:align-items|justify-content)\s*:\s*center/s, "launch content must not be center-aligned");
assert.match(css, /@media\s*\(prefers-reduced-motion:\s*reduce\)/, "motion needs a reduced-mode contract");
assert.match(css, /\.mc-button\.primary\s*\{[^}]*color:\s*#101310/s, "primary controls need dark high-contrast labels");
assert.match(css, /#xp-level\s*\{[^}]*color:\s*#101310/s, "the experience badge needs dark high-contrast labels");
assert.ok(contrastRatio("#101310", "#6c9b43") >= 4.5);
assert.ok(contrastRatio("#101310", "#5d8a35") >= 4.5);
assert.ok(contrastRatio("#101310", "#82b950") >= 4.5);
assert.ok(contrastRatio("#101310", "#6b9940") >= 4.5);
assert.ok(contrastRatio("#101310", "#4f9a3d") >= 4.5);
assert.ok(contrastRatio("#101310", "#438d35") >= 4.5);
assert.doesNotMatch(css, /@media\s*\(max-width:\s*680px\)[\s\S]*?#air\s*\{[^}]*display:\s*none/s, "narrow layouts must keep underwater air feedback");
const pauseOverlay = css.match(/#pause,\s*#death\s*\{[^}]*background:\s*rgb\(8 12 9 \/ ([0-9.]+)\)/s);
assert.ok(pauseOverlay !== null);
assert.ok(Number(pauseOverlay[1]) <= 0.45, "pause/death overlays must not obscure world textures");

console.log("ui shell ok");
