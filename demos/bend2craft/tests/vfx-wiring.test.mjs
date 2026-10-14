import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createWebglTerrainShaderSources } from "../web/webgl-shaders.js";
import { WEBGPU_TERRAIN_SHADER } from "../web/webgpu-terrain-renderer.js";

const gameSource = await readFile(new URL("../web/game.js", import.meta.url), "utf8");
const webgpuSource = await readFile(
  new URL("../web/webgpu-terrain-renderer.js", import.meta.url), "utf8",
);

// assert.match on a multi-kilobyte shader prints the whole shader into the
// failure output, which buries the actual problem. Report the pattern instead.
function has(source, pattern, message) {
  if (!pattern.test(source)) throw new Error(`${message} (missing ${pattern})`);
}

/**
 * A particle batch that the shader never reads, or a blend mode that quietly
 * reverts to opaque, produces no error anywhere: the program links, the draw
 * call runs, and the only symptom is that every effect in the game is missing.
 * Nothing else in the suite would notice, because a world with no fire, no
 * debris and no sparks still passes every simulation check.
 *
 * So this asserts the wiring itself. Both backends have to shade the pass, and
 * both have to blend it the way the emitter data promises - premultiplied, so
 * one batch can carry additive sparks and alpha-blended smoke at once.
 */
const advanced = createWebglTerrainShaderSources(96, {
  bumpMapping: true,
  waterDetail: true,
  grassWind: true,
  shadows: true,
});
const fallback = createWebglTerrainShaderSources(96, {
  bumpMapping: false,
  waterDetail: false,
  grassWind: false,
  shadows: false,
});

// The two backends select the pass differently - WebGL through a named uniform,
// WebGPU through the mode scalar in the frame uniform - so each is checked
// against the mechanism it actually uses.
for (const [label, source] of [
  ["advanced GLSL", advanced.fragmentSource],
  ["fallback GLSL", fallback.fragmentSource],
]) {
  has(source, /uVfxPass/, `the ${label} shader must declare a particle pass`);
  has(source, /vLight\.y/, `the ${label} shader must read the additive flag off the light attribute`);
  // Premultiplied output is what lets one batch hold both kinds of particle:
  // collapsing the destination weight to zero is what makes one of them add.
  has(source, /particleAlpha \* \(1\.0 - additive\)/,
    `the ${label} shader must zero the destination weight for an additive particle`);
  has(source, /1\.0 \+ additive \* \(core \* 1\.9 - 0\.25\)/,
    `the ${label} shader must brighten the core of an additive particle`);
  // GLSL ES 1.00 has no mix() overload whose selector is a scalar bool - the
  // bool overloads take a bvec. Passing one is a compile error that no amount of
  // string inspection elsewhere would catch, and the only symptom is that the
  // whole world fails to render.
  assert.doesNotMatch(source, /mix\([^;]*\badditive\s*\)/,
    `the ${label} shader must not pass a bool to mix(): GLSL ES 1.00 has no such overload`);
}
// WebGPU selects the pass from the mode scalar the frame uniform already carries.
has(WEBGPU_TERRAIN_SHADER, /let surfacePass = frame\.params\.z;/,
  "the WGSL shader must read the pass mode from the frame uniform");
has(WEBGPU_TERRAIN_SHADER, /if \(surfacePass > 3\.5\)/,
  "the WGSL shader must branch on the particle pass mode");
has(WEBGPU_TERRAIN_SHADER, /particleAlpha \* \(1\.0 - additive\)/,
  "the WGSL shader must zero the destination weight for an additive particle");
has(WEBGPU_TERRAIN_SHADER, /1\.0 \+ additive \* \(core \* 1\.9 - 0\.25\)/,
  "the WGSL shader must brighten the core of an additive particle");
// The particle is a camera-facing quad shaded from its vertex colour, not an
// atlas tile, so the pass has to build its own falloff from the local uv.
for (const [label, source] of [
  ["advanced GLSL", advanced.fragmentSource],
  ["fallback GLSL", fallback.fragmentSource],
  ["WGSL", WEBGPU_TERRAIN_SHADER],
]) {
  has(source, /falloff/, `the ${label} shader must shape the particle quad`);
}

// game.js: the uniform has to be located, switched on for the particle batch,
// and switched back off, or it leaks into the next draw. The declaration itself
// is already asserted above against the generated shader source.
const vfxLocation = gameSource.match(/(\w+)\s*=\s*gl\.getUniformLocation\(\s*\w+\s*,\s*"uVfxPass"\s*\)/);
assert.ok(vfxLocation, "game.js must locate uVfxPass");
has(gameSource, new RegExp(`uniform1f\\(\\s*${vfxLocation[1]}\\s*,\\s*1\\s*\\)`),
  "game.js must switch the particle pass on for the particle draw");
has(gameSource, new RegExp(`uniform1f\\(\\s*${vfxLocation[1]}\\s*,\\s*0\\s*\\)`),
  "game.js must switch the particle pass back off after the particle draw");

// Premultiplied alpha is the whole reason a flame and a puff of smoke can share
// one batch: with ONE / ONE_MINUS_SRC_ALPHA, an additive particle writes a zero
// destination weight and a covering one writes its own alpha.
has(gameSource, /blendFunc\(\s*gl\.ONE\s*,\s*gl\.ONE_MINUS_SRC_ALPHA\s*\)/,
  "the particle pass must blend premultiplied");
// Depth writes have to be off, or a particle would carve its own silhouette into
// the depth buffer and every particle behind it would be culled.
has(gameSource, /vfxVertexCount[\s\S]{0,900}?depthMask\(false\)/,
  "the particle pass must draw with depth writes disabled");

// The draw has to land inside the HDR scene, before the composite, or the
// effects skip the tonemap, the bloom and the FXAA the rest of the frame gets.
const vfxDraw = gameSource.indexOf("drawArrays(gl.TRIANGLES, 0, vfxVertexCount)");
assert.ok(vfxDraw > 0, "game.js must issue the particle draw");
assert.ok(vfxDraw < gameSource.indexOf("postPipeline.composite("),
  "the particle pass must be drawn before the post composite");
assert.ok(vfxDraw > gameSource.indexOf("beginScene()"),
  "the particle pass must be drawn into the scene, not onto the default framebuffer");

// The particle batch has to be uploaded from the same emitter data the pure
// module produces, or the effect vocabulary and the renderer drift apart.
has(gameSource, /from "\.\/vfx\.js"/, "game.js must import the particle module");
for (const emitter of [
  "emitFlame", "emitSmoke", "emitBlockDebris", "emitImpact", "emitDeathPuff", "emitSparkle",
]) {
  has(gameSource, new RegExp(`\\b${emitter}\\s*\\(`),
    `game.js must actually emit ${emitter}, or the effect is dead code`);
}

// Fire is the case the whole pass exists for, so it has to be driven by the
// domain's own flag rather than by a browser guess about the weather.
has(gameSource, /if \(!mob\.alive \|\| !mob\.burning\) continue;/,
  "game.js must present the Bend mob burning flag, not a browser guess");

// WebGPU has no post pipeline and its own pipeline table, so a new pass needs a
// fifth entry there or the effects simply do not exist on that backend.
has(webgpuSource, /const vfxPipeline = await createPipeline\(/,
  "the WebGPU renderer must own a particle pipeline");
has(webgpuSource, /"premultiplied",\s*false\)/,
  "the particle pipeline must blend premultiplied and leave depth writes off");
has(webgpuSource, /frameBuffers = Array\.from\(\{ length: 5 \}/,
  "the WebGPU frame uniform table needs a fifth entry, one per pass mode");
has(webgpuSource, /writeFrame\(frame, 4\)/,
  "the WebGPU frame must write the particle pass mode");
has(webgpuSource, /drawLayer\(pass, vfxPipeline, vfx\?\.buffer/,
  "the WebGPU render pass must draw the particle layer");
// The particle layer is uploaded on its own: uploadDynamic reallocates every
// layer it is handed, so a second call in the same frame would replace the
// entity buffers with empty ones and drop every mob.
has(gameSource, /gpuRenderer\.uploadVfx\(/,
  "game.js must upload the particle layer through its own WebGPU entry point");
assert.doesNotMatch(gameSource, /uploadDynamic\(\{[^}]*vfx/,
  "the particle layer must not go through uploadDynamic, which would drop the entity batch");

console.log("vfx wiring ok");
