import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { SHADOW_SAMPLING_GLSL, createVogelDiskTexture } from "../web/webgl-shadow.js";

const gameSource = await readFile(new URL("../web/game.js", import.meta.url), "utf8");
const { createWebglTerrainShaderSources, createWebglSkyFragmentShader } = await import("../web/webgl-shaders.js");

/**
 * A sampler uniform that is never assigned a texture unit keeps its default of 0,
 * so the shader silently reads whatever texture happens to be on unit 0. Nothing
 * errors, the program links, and the only symptom is a shading term that samples
 * the wrong image: in this project that turned the whole sun-shadow lookup into a
 * read of the block atlas, which is invisible to every other check because the
 * result is still plausible-looking pixels.
 *
 * So this asserts the invariant directly: every sampler the shader declares must
 * be both located and assigned, and the assigned unit must be the one the
 * per-frame binding code uses.
 */
const advanced = createWebglTerrainShaderSources(96, {
  bumpMapping: true,
  waterDetail: true,
  grassWind: true,
  shadows: true,
});
const sources = [
  ["terrain fragment", advanced.fragmentSource],
  ["terrain vertex", advanced.vertexSource],
  ["sky fragment", createWebglSkyFragmentShader({ volumetricClouds: true })],
  ["shadow sampling", SHADOW_SAMPLING_GLSL],
];

const declared = new Map();
for (const [label, source] of sources) {
  for (const match of source.matchAll(/uniform\s+sampler2D\s+(\w+)\s*;/g)) {
    declared.set(match[1], label);
  }
}
assert.ok(declared.size >= 4, `expected several samplers, found ${[...declared].join(", ")}`);

for (const name of declared.keys()) {
  const located = new RegExp(`getUniformLocation\\(\\s*\\w+\\s*,\\s*"${name}"\\s*\\)`).test(gameSource);
  assert.ok(located, `${name} is declared by ${declared.get(name)} but game.js never locates it`);
  // The location must be handed to a uniform1i somewhere. Matching on the
  // variable name is not possible from the string alone, so assert the weaker but
  // still meaningful property: the location variable is used in a uniform1i.
  const locationVariable = gameSource
    .match(new RegExp(`(\\w+)\\s*=\\s*gl\\.getUniformLocation\\(\\s*\\w+\\s*,\\s*"${name}"\\s*\\)`))?.[1];
  assert.ok(locationVariable, `could not resolve the location variable for ${name}`);
  const assigned = new RegExp(`uniform1i\\(\\s*${locationVariable}\\s*,`).test(gameSource);
  assert.ok(assigned, `${name} (${locationVariable}) is located but never assigned a texture unit`);
}

// The unit a sampler is assigned must match the unit its texture is bound to.
// The two are separate pieces of GL state, and writing the numbers in two places
// is how they drift apart.
const unitTable = gameSource.match(/const TERRAIN_TEXTURE_UNIT = Object\.freeze\(\{([\s\S]*?)\}\);/);
assert.ok(unitTable, "the terrain texture units must be declared in one named table");
const units = Object.fromEntries(
  [...unitTable[1].matchAll(/(\w+):\s*(\d+)/g)].map(([, key, value]) => [key, Number(value)]),
);
for (const [key, value] of Object.entries(units)) {
  assert.ok(Number.isInteger(value) && value >= 0 && value <= 15, `unit ${key} is not a valid texture unit`);
}
assert.equal(new Set(Object.values(units)).size, Object.keys(units).length, "texture units must be distinct");

// Every named unit must actually be used for a binding, and the sampler for it
// must be assigned that same number.
for (const [key, value] of Object.entries(units)) {
  const bound = new RegExp(`activeTexture\\(gl\\.TEXTURE0 \\+ TERRAIN_TEXTURE_UNIT\\.${key}\\)`).test(gameSource);
  assert.ok(bound, `TERRAIN_TEXTURE_UNIT.${key} is declared but never used for a binding`);
  const assigned = new RegExp(`uniform1i\\(\\s*\\w+\\s*,\\s*TERRAIN_TEXTURE_UNIT\\.${key}\\s*\\)`).test(gameSource);
  assert.ok(assigned, `TERRAIN_TEXTURE_UNIT.${key} is bound but no sampler is assigned to it`);
}

// The Vogel disk is a data texture the shader reads by index; if it were left
// unbound the tap offsets would be whatever unit 0 holds, which is the same
// class of failure this file exists to catch.
const glStub = {
  createTexture: () => ({}),
  bindTexture() {},
  texImage2D() {},
  texParameteri() {},
  REPEAT: 0x2901,
  NEAREST: 0x2600,
  CLAMP_TO_EDGE: 0x812f,
  RGBA: 0x1908,
  UNSIGNED_BYTE: 0x1401,
  TEXTURE_2D: 0x0de1,
  TEXTURE_MIN_FILTER: 0x2801,
  TEXTURE_MAG_FILTER: 0x2800,
  TEXTURE_WRAP_S: 0x2802,
  TEXTURE_WRAP_T: 0x2803,
};
assert.ok(createVogelDiskTexture(glStub, 8), "the Vogel disk texture must be creatable");

console.log("sun shadow wiring ok");
