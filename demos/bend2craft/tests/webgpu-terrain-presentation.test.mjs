import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  AERIAL_FOG_HEIGHT_FALLOFF,
  AERIAL_FOG_MIN_DENSITY,
  MATERIAL_DETAIL_NEUTRAL,
  MATERIAL_DETAIL_STAGE,
  MATERIAL_DETAIL_STRENGTH,
  MATERIAL_LIGHTING_STAGE,
  MATERIAL_ALBEDO_STAGE,
  MATERIAL_ROUGHNESS_MAX,
  MATERIAL_ROUGHNESS_MIN,
  MATERIAL_SPECULAR_POWER,
  MATERIAL_SPECULAR_STRENGTH,
  MATERIAL_STAGE_ORDER,
  WATER_DEPTH_FLOOR_R,
  WATER_DEPTH_MAX,
  WATER_DEPTH_TINT_STRENGTH,
  detailShade,
  materialRoughness,
  materialSpecular,
  waterDepthColor,
  waterDepthTint,
  FIRE_ALPHA,
  FIRE_PULSE_AMPLITUDE,
  FIRE_PULSE_SPEED,
  LAVA_ALPHA,
  LAVA_PULSE_AMPLITUDE,
  LAVA_PULSE_SPEED,
  MINING_FRACTURE_PROGRESS,
  MOON_FILL_STRENGTH,
  NIGHT_AMBIENT_G,
  NIGHT_AMBIENT_R,
  NIGHT_AMBIENT_STRENGTH,
  TERRAIN_FOG_START,
  TERRAIN_MATERIAL_VARIATION_MAX,
  TERRAIN_MATERIAL_VARIATION_MIN,
  WATER_CAUSTIC_STRENGTH,
  WATER_CAUSTIC_THRESHOLD_END,
  WATER_CAUSTIC_THRESHOLD_START,
  WATER_DARK_R,
  WATER_DARK_G,
  WATER_DARK_B,
  WATER_LIGHT_R,
  WATER_LIGHT_G,
  WATER_LIGHT_B,
  WATER_FRESNEL_POWER,
  WATER_SPECULAR_POWER,
  WATER_FOAM_THRESHOLD,
  WATER_NORMAL_STRENGTH,
  WATER_FOAM_STRENGTH,
  aerialPerspective,
  fireAlpha,
  firePulse,
  fractureVisibility,
  lavaAlpha,
  lavaPulse,
  materialVariationMultiplier,
  terrainFog,
  waterCaustic,
} from "../web/terrain-presentation.js";
import {
  CLOUD_TEXTURE_SIZE,
  createCloudTextureData,
} from "../web/cloud-texture.js";
import {
  WEBGL_SKY_FALLBACK_FRAGMENT_SHADER,
  WEBGL_SKY_VERTEX_SHADER,
  createWebglSkyFragmentShader,
  createWebglTerrainShaderSources,
  isSoftwareRenderer,
} from "../web/webgl-shaders.js";
import {
  FRAME_UNIFORM_BYTES,
  WEBGPU_SKY_SHADER,
  WEBGPU_TERRAIN_SHADER,
  WGSL_FRAME_UNIFORMS,
} from "../web/webgpu-terrain-renderer.js";
import { SURFACE_MATERIAL_OPAQUE_BASE } from "../web/surface-materials.js";
const rendererSource = await readFile(new URL("../web/webgpu-terrain-renderer.js", import.meta.url), "utf8");
const gameSource = await readFile(new URL("../web/game.js", import.meta.url), "utf8");

assert.equal(TERRAIN_FOG_START, 24);
assert.equal(TERRAIN_MATERIAL_VARIATION_MIN, 0.985);
assert.equal(TERRAIN_MATERIAL_VARIATION_MAX, 1.015);
assert.equal(MINING_FRACTURE_PROGRESS, 0.02);
assert.equal(MOON_FILL_STRENGTH, 0.72);
assert.equal(NIGHT_AMBIENT_R, 0.035);
assert.equal(NIGHT_AMBIENT_G, 0.055);
assert.equal(NIGHT_AMBIENT_STRENGTH, 0.7);
assert.equal(LAVA_PULSE_AMPLITUDE, 0.16);
assert.equal(LAVA_PULSE_SPEED, 2.4);
assert.equal(LAVA_ALPHA, 0.86);
assert.equal(FIRE_PULSE_AMPLITUDE, 0.25);
assert.equal(FIRE_PULSE_SPEED, 8);
assert.equal(FIRE_ALPHA, 0.9);
assert.equal(WATER_DARK_R, 0.025);
assert.equal(WATER_DARK_G, 0.22);
assert.equal(WATER_DARK_B, 0.34);
assert.equal(WATER_LIGHT_R, 0.12);
assert.equal(WATER_LIGHT_G, 0.62);
assert.equal(WATER_LIGHT_B, 0.72);
assert.equal(WATER_FRESNEL_POWER, 3);
assert.equal(WATER_SPECULAR_POWER, 48);
assert.equal(WATER_FOAM_THRESHOLD, 0.94);
assert.equal(WATER_NORMAL_STRENGTH, 6);
assert.equal(WATER_FOAM_STRENGTH, 0.035);
assert.equal(WATER_CAUSTIC_STRENGTH, 0.18);
assert.equal(WATER_CAUSTIC_THRESHOLD_START, 0.54);
assert.equal(WATER_CAUSTIC_THRESHOLD_END, 0.72);
assert.equal(AERIAL_FOG_MIN_DENSITY, 0.42);
assert.equal(AERIAL_FOG_HEIGHT_FALLOFF, 0.028);

// The material contract is split into albedo, lighting and material response so
// the two backends can be held to one contract instead of two implementations.
assert.equal(MATERIAL_ALBEDO_STAGE, 1);
assert.equal(MATERIAL_LIGHTING_STAGE, 2);
assert.equal(MATERIAL_DETAIL_STAGE, 3);
assert.deepEqual(MATERIAL_STAGE_ORDER, [1, 2, 3]);
assert.ok(Object.isFrozen(MATERIAL_STAGE_ORDER));
assert.ok(MATERIAL_DETAIL_STRENGTH > 0 && MATERIAL_DETAIL_STRENGTH < 0.2);
assert.ok(MATERIAL_ROUGHNESS_MIN > 0 && MATERIAL_ROUGHNESS_MIN < 1);
assert.ok(MATERIAL_ROUGHNESS_MAX > MATERIAL_ROUGHNESS_MIN);
assert.ok(MATERIAL_ROUGHNESS_MAX <= 1);
assert.equal(MATERIAL_SPECULAR_POWER, 24);
assert.equal(MATERIAL_SPECULAR_STRENGTH, 0.18);
assert.equal(WATER_DEPTH_MAX, 5);
assert.ok(WATER_DEPTH_TINT_STRENGTH > 0 && WATER_DEPTH_TINT_STRENGTH < 0.5);
assert.ok(WATER_DEPTH_FLOOR_R < 1);

// A rougher surface must respond less to the specular lobe, and detail must be
// a bounded multiplier on the albedo rather than a replacement for it.
assert.equal(detailShade(0.5, 0.0), MATERIAL_DETAIL_NEUTRAL, "a mid sample is the neutral detail");
assert.equal(detailShade(0.5, MATERIAL_ROUGHNESS_MAX), MATERIAL_DETAIL_NEUTRAL);
const smoothDetail = detailShade(1.0, MATERIAL_ROUGHNESS_MIN);
const roughDetail = detailShade(1.0, MATERIAL_ROUGHNESS_MAX);
assert.ok(roughDetail > smoothDetail, "a rougher surface must show more relief contrast");
assert.ok(detailShade(1.0, 0.5) - MATERIAL_DETAIL_NEUTRAL <= MATERIAL_DETAIL_STRENGTH);
assert.ok(detailShade(0.0, 0.5) - MATERIAL_DETAIL_NEUTRAL >= -MATERIAL_DETAIL_STRENGTH);
// The facing bias is a 0..1 term, so it clamps instead of going negative.
assert.equal(detailShade(0.75, 0.5, -1), detailShade(0.75, 0.5, 0), "a negative bias must clamp to zero");
assert.equal(detailShade(0.75, 0.5, 2), detailShade(0.75, 0.5, 1), "a bias past one must clamp");
assert.ok(detailShade(0.75, 0.5, 1) > detailShade(0.75, 0.5, 0), "a lit bias must lift the detail");

assert.equal(materialRoughness(0), MATERIAL_ROUGHNESS_MIN);
assert.ok(materialRoughness(1) > materialRoughness(0.5));
assert.ok(materialRoughness(1) <= MATERIAL_ROUGHNESS_MAX);
assert.equal(materialSpecular(0, MATERIAL_ROUGHNESS_MIN), 0, "a matte surface has no lobe");
assert.ok(materialSpecular(1, MATERIAL_ROUGHNESS_MIN) > 0);
assert.ok(materialSpecular(1, MATERIAL_ROUGHNESS_MAX) < materialSpecular(1, MATERIAL_ROUGHNESS_MIN));

// Water depth must darken and cool the surface without ever reaching the floor
// tint before the documented maximum depth.
assert.equal(waterDepthTint(0), 0);
assert.ok(waterDepthTint(0.5) > 0);
assert.equal(waterDepthTint(WATER_DEPTH_MAX), 1);
assert.ok(waterDepthTint(WATER_DEPTH_MAX * 2) === 1, "depth tint must saturate at the documented maximum");
assert.ok(waterDepthTint(1) < waterDepthTint(3), "deeper water must tint more");
const shallow = waterDepthColor(0.5);
const deep = waterDepthColor(4.0);
for (let channel = 0; channel < 3; channel += 1) {
  assert.ok(deep[channel] < shallow[channel], "deeper water must be darker");
  assert.ok(deep[channel] >= 0, "the depth floor must keep every channel non-negative");
}
assert.equal(waterDepthColor(0)[0], WATER_LIGHT_R, "no depth must leave the water albedo untouched");
assert.ok(waterDepthColor(0)[0] > WATER_DARK_R, "shallow water must stay lighter than deep water");
const deepestRed = waterDepthColor(WATER_DEPTH_MAX)[0];
assert.ok(
  Math.abs(
    deepestRed - (WATER_LIGHT_R + (WATER_DEPTH_FLOOR_R - WATER_LIGHT_R) * WATER_DEPTH_TINT_STRENGTH),
  ) < 1e-9,
  "the deepest water must be the strength-weighted blend toward the floor",
);
assert.ok(deepestRed > WATER_DEPTH_FLOOR_R, "the tint strength must keep deep water above its floor");
assert.ok(
  WATER_DEPTH_TINT_STRENGTH < 1,
  "a bounded tint is what stops a deep ocean from losing its silhouette",
);

const cellScale = materialVariationMultiplier(1.25, 2.75);
assert.equal(cellScale, materialVariationMultiplier(1.9, 2.1));
assert.ok(cellScale >= TERRAIN_MATERIAL_VARIATION_MIN);
assert.ok(cellScale <= TERRAIN_MATERIAL_VARIATION_MAX);
assert.notEqual(cellScale, materialVariationMultiplier(1.25, 3.75));

assert.equal(terrainFog(23, 120), 0);
assert.equal(terrainFog(24, 120), 0);
assert.equal(terrainFog(84, 120), 0.5);
assert.equal(terrainFog(145, 120), 1);
assert.equal(terrainFog(200, 120), 1);

assert.equal(aerialPerspective(20, 120, 12, 12), 0);
const valleyFog = aerialPerspective(80, 120, 12, 12);
const ridgeFog = aerialPerspective(80, 120, 12, 36);
assert.ok(valleyFog > 0.4);
assert.ok(ridgeFog < valleyFog);
assert.ok(ridgeFog >= 0);
assert.ok(valleyFog <= 1);

assert.equal(fractureVisibility(0, 1), 0);
assert.equal(fractureVisibility(0.019, 1), 0);
assert.equal(fractureVisibility(0.02, 1), 1);
assert.equal(fractureVisibility(0.5, 0.4), 0.4);
assert.equal(lavaAlpha(0.2), LAVA_ALPHA);
assert.equal(lavaAlpha(0.95), 0.95);
assert.equal(fireAlpha(0.2), FIRE_ALPHA);
assert.equal(fireAlpha(0.95), 0.95);

assert.ok(Math.abs(lavaPulse(Math.PI / (2 * LAVA_PULSE_SPEED), 0) - (1 + LAVA_PULSE_AMPLITUDE)) < 1e-12);
assert.ok(Math.abs(firePulse(Math.PI / (2 * FIRE_PULSE_SPEED), 0) - (1 + FIRE_PULSE_AMPLITUDE)) < 1e-12);
assert.ok(lavaPulse(1.25, 2.5) >= 1 - LAVA_PULSE_AMPLITUDE);
assert.ok(lavaPulse(1.25, 2.5) <= 1 + LAVA_PULSE_AMPLITUDE);
assert.ok(firePulse(1.25, 2.5) >= 1 - FIRE_PULSE_AMPLITUDE);
assert.ok(firePulse(1.25, 2.5) <= 1 + FIRE_PULSE_AMPLITUDE);

assert.equal(CLOUD_TEXTURE_SIZE, 64);
const cloudTexture = createCloudTextureData();
assert.equal(cloudTexture.length, CLOUD_TEXTURE_SIZE * CLOUD_TEXTURE_SIZE * 4);
assert.deepEqual(createCloudTextureData(), cloudTexture);
let cloudMinimum = 255;
let cloudMaximum = 0;
for (let index = 0; index < cloudTexture.length; index += 4) {
  assert.equal(cloudTexture[index], cloudTexture[index + 1]);
  assert.equal(cloudTexture[index], cloudTexture[index + 2]);
  assert.equal(cloudTexture[index + 3], 255);
  cloudMinimum = Math.min(cloudMinimum, cloudTexture[index]);
  cloudMaximum = Math.max(cloudMaximum, cloudTexture[index]);
}
assert.ok(cloudMinimum < 96);
assert.ok(cloudMaximum > 160);
const strongestCaustic = waterCaustic(cloudMaximum / 255, 1);
assert.ok(strongestCaustic >= WATER_CAUSTIC_STRENGTH * 0.95);
assert.equal(waterCaustic(0, 1), 0);
assert.equal(isSoftwareRenderer("ANGLE (Google, Vulkan SwiftShader Device)"), true);
assert.equal(isSoftwareRenderer("llvmpipe (LLVM 20.1.0, 256 bits)"), true);
assert.equal(isSoftwareRenderer("Microsoft Basic Render Driver"), true);
assert.equal(isSoftwareRenderer("NVIDIA GeForce RTX 4070"), false);

assert.equal(typeof WEBGPU_TERRAIN_SHADER, "string");

// The terrain and sky pipelines bind the same per-frame uniform, so they must
// agree on its layout. Derive the size from the struct instead of trusting the
// constant the buffer is allocated with: a field added to the struct without
// updating FRAME_UNIFORM_BYTES writes past the end of the binding, and the
// resulting garbage is invisible in every other assertion.
const frameStruct = WGSL_FRAME_UNIFORMS.match(/struct Frame \{([\s\S]*?)\n\}/)?.[1];
assert.ok(frameStruct, "the shared uniform preamble must declare struct Frame");
const frameFields = [...frameStruct.matchAll(/(\w+):\s*(mat4x4|vec[234])<f32>/g)].map(([, name, type]) => ({ name, type }));
assert.ok(frameFields.length > 0, "struct Frame must declare fields");
const WGSL_TYPE_BYTES = { mat4x4: 64, vec4: 16, vec3: 12, vec2: 8 };
const frameBytes = frameFields.reduce((sum, { type }) => sum + WGSL_TYPE_BYTES[type], 0);
assert.equal(
  frameBytes,
  FRAME_UNIFORM_BYTES,
  `FRAME_UNIFORM_BYTES (${FRAME_UNIFORM_BYTES}) must match struct Frame (${frameBytes}): ${frameFields.map((f) => f.name).join(", ")}`,
);
assert.equal(FRAME_UNIFORM_BYTES % 16, 0, "a uniform buffer binding must be 16-byte aligned");
assert.equal(FRAME_UNIFORM_BYTES / 4, new Float32Array(FRAME_UNIFORM_BYTES / 4).length);

// Both pipelines must carry the identical declaration, exactly once each.
for (const [label, shader] of [["terrain", WEBGPU_TERRAIN_SHADER], ["sky", WEBGPU_SKY_SHADER]]) {
  assert.equal((shader.match(/struct Frame \{/g) ?? []).length, 1, `${label} must declare struct Frame once`);
  assert.ok(shader.startsWith(WGSL_FRAME_UNIFORMS), `${label} must start with the shared uniform preamble`);
  assert.equal(
    (shader.match(/var<uniform> frame: Frame;/g) ?? []).length,
    1,
    `${label} must bind the frame uniform once`,
  );
}
assert.match(gameSource, /createPermutedProgram/);
assert.match(gameSource, /fallbackTerrainSources/);
assert.match(gameSource, /configureWebglQuality\(\)/);
assert.match(rendererSource, /createRenderPipelineAsync/);
assert.match(rendererSource, /validateDevicePresentation/);
assert.match(rendererSource, /RENDER_ATTACHMENT/);
// Culling must happen while the pass is being encoded, and the metrics must be
// the ones the frame readback and the smoke report.
assert.match(rendererSource, /selectVisibleChunks\(terrain\.values\(\), planes\)/);
const renderBody = rendererSource.slice(rendererSource.indexOf("function render(frame)"));
assert.ok(
  renderBody.indexOf("const planes = extractClipPlanes(frame.viewProjection);")
    < renderBody.indexOf("device.createCommandEncoder()"),
  "clip planes must be extracted before the command encoder is created",
);
for (const field of ["visibleChunks", "culledChunks", "drawCalls", "submittedVertexBytes"]) {
  assert.ok(rendererSource.includes(field), `renderer stats must expose ${field}`);
}
assert.ok(
  renderBody.indexOf("for (const chunk of visible) drawLayer(pass, opaquePipeline")
    < renderBody.indexOf("pass.setPipeline(skyPipeline)"),
  "culled chunks must not reach the opaque pass",
);
// A block edit must reach the per-chunk edit path, and the WebGPU mesh cache
// must not compose a whole-world vertex array for it.
assert.match(rendererSource, /function updateChunks\(chunks\)/);
assert.match(rendererSource, /classifyChunkUpdate/);
// Both backends are per chunk now: WebGL keeps one interleaved buffer per chunk
// too (web/webgl-chunk-buffers.js), so the cache never composes a world array.
assert.match(gameSource, /perChunkOnly: true/);
assert.match(gameSource, /glChunkBuffers\.update\(chunks\)/);
assert.match(gameSource, /gpuRenderer\.updateChunks\(chunks\)/);
assert.doesNotMatch(gameSource, /gpuRenderer\.uploadTerrain\(chunks\)/);
assert.ok(
  rendererSource.indexOf("const shadowPipeline = await createPipeline")
    < rendererSource.indexOf("const canvasContext = context ?? canvas.getContext"),
  "WebGPU pipelines must validate before the game canvas context is claimed",
);
const vertexStart = WEBGPU_TERRAIN_SHADER.indexOf("fn vs_main");
const fragmentStart = WEBGPU_TERRAIN_SHADER.indexOf("@fragment");
assert.ok(vertexStart >= 0);
assert.ok(fragmentStart > vertexStart);
const vertexSource = WEBGPU_TERRAIN_SHADER.slice(vertexStart, fragmentStart);
const fragmentSource = WEBGPU_TERRAIN_SHADER.slice(fragmentStart);

// The varying locations shift because the vertex stage now carries the normal
// and the occlusion/block-light pair; fog and material sit after them.
assert.match(WEBGPU_TERRAIN_SHADER, /@location\(6\) fog: f32/);
assert.match(WEBGPU_TERRAIN_SHADER, /@location\(7\) material: f32/);
assert.match(WEBGPU_TERRAIN_SHADER, /@location\(1\) light: vec2<f32>/);
assert.match(WEBGPU_TERRAIN_SHADER, /@location\(2\) normal: vec3<f32>/);
assert.match(WEBGPU_TERRAIN_SHADER, /output\.material = input\.material/);
assert.match(WEBGPU_TERRAIN_SHADER, /output\.normal = input\.normal/);
assert.match(WEBGPU_TERRAIN_SHADER, /output\.light = input\.light/);
assert.doesNotMatch(WEBGPU_TERRAIN_SHADER, /\bpass\b/);
// The WebGPU stage must light from the interpolated normal, like the WebGL one.
assert.match(fragmentSource, /normalize\(input\.normal\)/);
// WGSL has no implicit truncation and `dot` needs two vectors of the same width,
// so the sun direction has to be narrowed to its xyz here. Written without the
// `.xyz` this reads as an assertion about a shader that cannot compile, which is
// how a real shader bug sat in this file being asserted as correct.
assert.match(fragmentSource, /dot\(normal, frame\.sunDirection\.xyz\)/);
assert.doesNotMatch(fragmentSource, /dot\(normal, frame\.sunDirection\)/);
assert.match(fragmentSource, /mix\(0\.24, 1\.0, skyLightLevel\) \* occlusion/);
assert.match(vertexSource, /output\.fog\s*=\s*clamp\(\(distance\(position, frame\.camera\.xyz\) - 24/);
assert.doesNotMatch(fragmentSource, /distance\(input\.worldPosition/);
assert.match(fragmentSource, /input\.aerialFog/);
assert.match(fragmentSource, /mix\(clamp\(color, vec3<f32>\(0\.0\), vec3<f32>\(1\.0\)\), fogColor, input\.aerialFog\)/);
assert.match(vertexSource, /output\.aerialFog/);
assert.match(fragmentSource, /floor\(input\.worldPosition\.xz\)/);
assert.match(fragmentSource, /0\.985, 1\.015/);
assert.match(fragmentSource, /step\(0\.02, frame\.params\.w\)/);
assert.match(fragmentSource, /1\.0 \+ 0\.16 \* sin\(frame\.params\.y \* 2\.4 \+ input\.worldPosition\.x \* 0\.5\)/);
assert.match(fragmentSource, /max\(alpha, 0\.86\)/);
assert.match(fragmentSource, /1\.0 \+ 0\.25 \* sin\(frame\.params\.y \* 8 \+ input\.worldPosition\.y \* 4\)/);
assert.match(fragmentSource, /max\(alpha, 0\.9\)/);
assert.match(fragmentSource, /0\.28 \* \(1\.0 - smoothstep\(0\.38, 1\.0, length\(shadowUv\)\)\) \* \(1\.0 - input\.fog \* 0\.65\)/);
const sampleIndex = fragmentSource.indexOf("textureSample");
const firstBranchIndex = fragmentSource.indexOf("if (");
assert.ok(sampleIndex >= 0 && sampleIndex < firstBranchIndex, "texture sampling must be in uniform control flow");
assert.match(fragmentSource, /rippleC/);
assert.match(fragmentSource, /waterNormal/);
assert.match(fragmentSource, /fresnel/);
assert.match(fragmentSource, /specular/);
assert.match(fragmentSource, /foam/);
assert.doesNotMatch(fragmentSource, /depthTint/);
assert.match(fragmentSource, /waterTone/);
assert.equal((WEBGPU_TERRAIN_SHADER.match(/@group\(0\)/g) ?? []).length, 5);
assert.doesNotMatch(WEBGPU_TERRAIN_SHADER, /@group\([1-9]/);
assert.match(fragmentSource, /aerialFog/);
assert.match(fragmentSource, /frame\.skyHorizon\.rgb/);
assert.match(fragmentSource, /frame\.sunDirection\.xyz/);
assert.match(fragmentSource, /sunVisibility/);
assert.match(fragmentSource, /ambientLuma/);
// The old baked night-fill helpers are gone: a single hemispheric ambient now
// covers daylight and night, so a dead reference would mean the night term
// silently stopped applying.
assert.doesNotMatch(fragmentSource, /moonFill|nightAmbient|coolLight|warmLight/);
assert.match(fragmentSource, /caustic/);
assert.match(fragmentSource, /textureSampleLevel\(cloudTexture, cloudSampler/);
assert.match(fragmentSource, /smoothstep\(0\.54, 0\.72, causticPattern\)/);
assert.doesNotMatch(fragmentSource, /filmicToneMap/);

// A block-scoped `var color` or `var alpha` inside the material branch shadows
// the function-scope pair, so the final return keeps shipping the unshaded seed
// value. That made the whole three-stage material contract, the water shading and
// the atlas alpha dead code on the WebGPU path, and it rendered as a flat
// near-white frame while every other assertion in this file still passed. The
// branches must assign, never re-declare.
for (const name of ["color", "alpha"]) {
  const declarations = fragmentSource.match(new RegExp(`var ${name}\\s*=`, "g")) ?? [];
  assert.equal(
    declarations.length,
    1,
    `the WGSL fragment must declare \`var ${name}\` exactly once, found ${declarations.length}`,
  );
  assert.equal(
    (fragmentSource.match(new RegExp(`^\\s*var ${name}\\b`, "gm")) ?? []).length,
    1,
    `the single \`var ${name}\` must sit at fragment scope, not inside a branch`,
  );
}
assert.doesNotMatch(
  fragmentSource,
  /var color = litColor/,
  "the shaded result must assign the fragment-scope color, not shadow it",
);
assert.doesNotMatch(
  fragmentSource,
  /var alpha = textureColor\.a/,
  "the atlas alpha must assign the fragment-scope alpha, not shadow it",
);
// The material branch is the only producer of the shaded color, so the value the
// function returns has to come from it.
const shadedAssignment = fragmentSource.indexOf("color = litColor");
const finalReturn = fragmentSource.lastIndexOf("mix(clamp(color, vec3<f32>(0.0)");
assert.ok(shadedAssignment >= 0, "the material branch must assign the shaded color");
assert.ok(shadedAssignment < finalReturn, "the shaded color must be assigned before it is returned");
const alphaAssignment = fragmentSource.indexOf("alpha = textureColor.a");
const finalAlpha = fragmentSource.lastIndexOf("alpha * (1.0 - input.aerialFog)");
assert.ok(alphaAssignment >= 0 && alphaAssignment < finalAlpha);

// Phase 6: the WebGPU path must be able to hand a real frame back, and must
// say so explicitly when it cannot. A readback path that only proves the
// pipeline compiles is not a visible-validation gate.
assert.match(rendererSource, /async function readFramePixels\(/, "the WebGPU path must expose a real frame readback");
assert.match(rendererSource, /copyTextureToBuffer/, "the readback must copy the presented texture");
assert.match(rendererSource, /mapAsync/, "the readback must map the copied buffer");
assert.match(rendererSource, /bytesPerRow/, "the readback must respect the 256-byte row alignment");
assert.match(rendererSource, /COPY_SRC/, "the swap chain must be configured for copying");
assert.match(rendererSource, /MAP_READ/, "the readback buffer must be mappable");
// The copy is encoded from the same command buffer as the render pass, so it
// reads the texture that pass wrote rather than a presented-and-recycled one.
const renderBodyForCapture = rendererSource.slice(rendererSource.indexOf("function render(frame)"));
assert.ok(
  renderBodyForCapture.indexOf("pass.end()")
    < renderBodyForCapture.indexOf("encoder.copyTextureToBuffer"),
  "the readback copy must be encoded after the render pass in the same encoder",
);
assert.ok(
  renderBodyForCapture.indexOf("encoder.copyTextureToBuffer")
    < renderBodyForCapture.indexOf("device.queue.submit"),
  "the readback copy must be part of the submitted command buffer",
);
assert.match(
  renderBodyForCapture,
  /const presented = canvasContext\.getCurrentTexture\(\)/,
  "the readback must target the texture the render pass drew into",
);
assert.match(gameSource, /readFramePixelsAsync/, "the bridge must expose the async readback");
assert.match(gameSource, /getFrameReadbackSupport/, "the bridge must report readback support");
assert.doesNotMatch(
  gameSource,
  /WebGPU frame readback is not enabled in this diagnostic path/,
  "the old readback stub must be gone",
);
const webglSources = createWebglTerrainShaderSources(96, {
  bumpMapping: true,
  waterDetail: true,
  grassWind: true,
});
const fallbackWebglSources = createWebglTerrainShaderSources(96, {
  bumpMapping: false,
  waterDetail: false,
  grassWind: false,
});
const WEBGL_SKY_FRAGMENT_SHADER = createWebglSkyFragmentShader({ volumetricClouds: true });
// WebGL and WGSL must agree on the material band bounds, the water depth tint
// and the per-pixel lighting model, so a pixel grades the same on both backends.
const webglFragment = webglSources.fragmentSource;
const wgslFragment = fragmentSource;
for (const [name, source] of [["webgl", webglFragment], ["wgsl", wgslFragment]]) {
  // Anchor on the declaration, not on the bare word "albedo", which also
  // appears in the comments that explain the stages. WGSL types it with `let`,
  // GLSL with `vec3`, so match the assignment itself.
  const albedo = source.search(/(?:vec3|vec3<f32>|let)\s+albedo\s*=/);
  // WebGL accumulates into a pre-declared `color`, WGSL into a `litColor`
  // local; both must come after the albedo they shade.
  const lighting = source.search(/litColor\s*=|=\s*diffuse\s*\+\s*ambient/);
  assert.ok(albedo >= 0, `${name} must build an albedo stage`);
  assert.ok(lighting > albedo, `${name} must apply lighting after albedo`);
  // The two backends spell these differently; what matters is that each one has
  // a roughness, a micro-detail term and a water depth term.
  assert.match(source, /surfaceRoughness|float roughness/, `${name} must derive a roughness`);
  assert.match(source, /detailAmplitude|float detail =/, `${name} must derive detail shading`);
  assert.match(source, /waterDepth|depthInColumn/, `${name} must tint water by depth`);
  // The sun term must be driven by the interpolated face normal, not by a baked
  // vertex colour, and the ambient must be gated by occlusion.
  // The backends spell the uniform uSunDirection and sunDirection respectively.
  assert.match(source, /[Ss]unDirection/, `${name} must light from a sun direction`);
  assert.match(source, /occlusion/, `${name} must gate ambient by occlusion`);
  assert.match(
    source,
    /clamp\((?:vMaterial|input\.material) - 1\.0, 0\.0, 1\.0\)|depthInColumn = clamp\(vMaterial - 1\.0, 0\.0, 1\.0\)/,
    `${name} must decode the water depth from the material band`,
  );
  assert.match(source, /deepColor|deepWater/, `${name} must tint toward a bounded deep-water colour`);
  // The material bands must not overlap, or a lava or fire quad would be graded
  // as water. The exact bounds are asserted below.
  assert.doesNotMatch(
    source,
    /(?:vMaterial|input\.material) [<>=]+ 1\.5/,
    `${name} must not use the old half-open water band`,
  );
}
assert.doesNotMatch(fragmentSource, /depthTint/);
assert.match(webglSources.vertexSource, /vViewDirection/);
assert.match(webglSources.vertexSource, /vAerialFog/);
assert.match(webglSources.vertexSource, /aNormal/, "the vertex stage must carry the face normal");
assert.match(webglSources.vertexSource, /aLight/, "the vertex stage must carry occlusion and block light");
assert.match(webglSources.fragmentSource, /vAerialFog/);
assert.match(webglSources.fragmentSource, /uSkyHorizonColor/);
assert.match(webglSources.fragmentSource, /uSunDirection/);
assert.match(webglSources.fragmentSource, /uGroundBounce/, "ambient needs a ground bounce colour");
assert.match(webglSources.fragmentSource, /specularLobe/, "a real specular lobe replaces the world-up fake");
assert.match(webglSources.fragmentSource, /caustic/);
assert.match(webglSources.fragmentSource, /uniform sampler2D uCloudMap/);
assert.match(webglSources.fragmentSource, /texture2D\(uCloudMap, causticUv\)/);
// Sun shadows: the terrain shader must sample the cascade, and the cascade must
// be fed the light matrix the shadow pass renders with.
assert.match(webglSources.fragmentSource, /uniform sampler2D uShadowMap/);
assert.match(webglSources.fragmentSource, /sunShadow\(/);
assert.match(webglSources.fragmentSource, /uShadowStrength/);
assert.match(gameSource, /uLightViewProjection/, "the frame must upload the light matrix");
assert.match(gameSource, /renderShadowPass/, "the frame must render the shadow cascade");

// The fallback drops the expensive water terms but keeps the same lighting
// contract, so land materials grade identically on both quality tiers.
assert.doesNotMatch(fallbackWebglSources.fragmentSource, /causticUv/);
assert.doesNotMatch(fallbackWebglSources.vertexSource, /position\.y \+=/);
assert.match(fallbackWebglSources.fragmentSource, /uSunDirection/);

// The wind may only move what is not a solid surface. Terrain quads are
// greedy-merged, so a merged grass top is one quad with four corners however
// large it is, and a world-space field sampled at four corners can only tilt
// that quad. A plain therefore read as a handful of big facets rolling like
// ocean swell, and the block surface is the surface the player collides
// against, so moving it desyncs what is drawn from what is stood on. Only the
// water surface and the per-cell leaf quads may be displaced.
const GRASS_BAND = (SURFACE_MATERIAL_OPAQUE_BASE + 3).toFixed(1);
assert.doesNotMatch(
  webglSources.vertexSource,
  new RegExp(`aMaterial - ${GRASS_BAND.replace(".", "\\.")}`),
  "the terrain vertex stage must not displace the grass band",
);
// Gating the wind on the face normal slides a cell's top face off its own
// sides, because the sides stay put while the top moves, so a leaf block opens
// a slit around its whole top rim.
assert.doesNotMatch(
  webglSources.vertexSource,
  /aNormal\.y/,
  "the wind must not be gated on the face normal, or a leaf cell tears along its top rim",
);
// The same rule on the WGSL side, so swapping the backend cannot reintroduce
// terrain that rolls.
assert.doesNotMatch(
  vertexSource,
  new RegExp(`input\\.material - ${GRASS_BAND.replace(".", "\\.")}`),
  "the WGSL terrain vertex stage must not displace the grass band either",
);
assert.match(WEBGL_SKY_VERTEX_SHADER, /gl_Position = vec4\(aPosition, 1\.0, 1\.0\)/);
assert.match(WEBGL_SKY_FRAGMENT_SHADER, /skyRay/);
// The cloud deck is fully procedural now, so the sky must not reach for the
// shared 2D cloud map that only the water caustics still use.
assert.doesNotMatch(WEBGL_SKY_FRAGMENT_SHADER, /uCloudMap/);
assert.doesNotMatch(WEBGL_SKY_FRAGMENT_SHADER, /uAtlas/);
// The advanced sky raymarches a cloud deck and scatters light inside it.
assert.match(WEBGL_SKY_FRAGMENT_SHADER, /cloudDensity\(/);
assert.match(WEBGL_SKY_FRAGMENT_SHADER, /uCloudSteps/);
assert.match(WEBGL_SKY_FRAGMENT_SHADER, /phaseHG\(/);
assert.match(WEBGL_SKY_FRAGMENT_SHADER, /transmittance/);
assert.match(WEBGL_SKY_FRAGMENT_SHADER, /#define CLOUD_MAX_STEPS/);
assert.match(WEBGL_SKY_FRAGMENT_SHADER, /#define MAX_CLOUD_SPAN/);
assert.match(WEBGL_SKY_FRAGMENT_SHADER, /sunDisc/);
assert.match(WEBGL_SKY_FRAGMENT_SHADER, /starBrightness/);
assert.match(WEBGL_SKY_FRAGMENT_SHADER, /milkyWay/);
assert.match(WEBGL_SKY_FALLBACK_FRAGMENT_SHADER, /skyRay/);
assert.match(WEBGL_SKY_FALLBACK_FRAGMENT_SHADER, /horizonHaze/);
assert.doesNotMatch(
  WEBGL_SKY_FALLBACK_FRAGMENT_SHADER,
  /cloudDensity|starField|sunDisc|transmittance/,
);

assert.match(WEBGPU_SKY_SHADER, /textureSample\(cloudTexture, cloudSampler/);
assert.match(WEBGPU_SKY_SHADER, /sunDisk/);
assert.match(WEBGPU_SKY_SHADER, /starField/);
assert.match(WEBGPU_SKY_SHADER, /horizonHaze/);
assert.match(WEBGPU_SKY_SHADER, /frame\.sunDirection\.xyz/);

// The WebGPU path builds its own atlas texture, so the Foreign Tile Contamination
// gate has to run on the WebGPU device. It used to be certified only in the WebGL
// boot path, which left the WebGPU atlas reporting "not probed" and shipping
// without the mip chain the WebGL backend already had.
assert.match(
  rendererSource,
  /await certifyAtlasMipmapsOnGpu\(device, atlasCanvas\)/,
  "the WebGPU path must certify the atlas on its own device",
);
assert.match(rendererSource, /getAtlasMipmapVerdict/, "the WebGPU verdict must be reportable");
assert.match(gameSource, /gpuRenderer\.getAtlasMipmapVerdict\(\)/, "the game must read the verdict");
assert.match(
  rendererSource,
  /const atlasMipmapVerdict = await certifyAtlasMipmapsOnGpu[\s\S]*?createAtlasTexture\(device, atlasCanvas, atlasMipmapVerdict\.safe\)/,
  "the gate must decide before the shipping atlas is built",
);
// The gate is only real if it can await its readback and compare against an
// isolation reference; a synchronous stub would have to report "unsafe" forever.
assert.match(rendererSource, /async function certifyAtlasMipmapsOnGpu/);
assert.match(rendererSource, /spreadProbeTiles\(ATLAS_TEXTURES\.length, ATLAS_COLUMNS\)/,
  "both backends must probe the same tile spread");
assert.match(rendererSource, /buildIsolationReference/);
assert.match(rendererSource, /foreignTileContamination\(/);
assert.match(rendererSource, /maxChannelDelta\(/);
// The readback still has to be awaited, but through the bounded helper: a
// mapAsync on a device that has stopped making progress never settles, and an
// unbounded await there is a permanent freeze rather than a slow read.
assert.match(rendererSource, /await mapBufferWithin\(buffer, mapMode\(\)\)/,
  "the gate must await its own readback through the bounded helper");
assert.match(rendererSource, /GPU_READBACK_TIMEOUT_MS/,
  "a stalled readback must be bounded by a timeout");
assert.doesNotMatch(
  rendererSource,
  /the WebGPU mip chain needs an async readback to certify/,
  "the gate must no longer give up instead of awaiting",
);
// Contamination alone is not enough: a gate that builds the observed atlas and
// its isolation reference with the same generator certifies a broken chain as
// clean, which is what shipped a washed-out WebGPU scene. The chain has to be
// checked against a reference computed a different way.
assert.match(rendererSource, /certifyMipChainGenerator/);
assert.match(rendererSource, /atlasBoxDownsample\(size, source, level\)/);
assert.match(rendererSource, /the WebGPU mip chain does not match a box-filter reference/);
assert.match(
  rendererSource,
  /if \(!chain\.matches\)[\s\S]*?return verdict;/,
  "a chain that misses the reference must not be used",
);
assert.match(
  rendererSource,
  /createMipScratchTexture/,
  "a texture cannot be sampled and rendered into, so the chain needs a scratch texture",
);
assert.match(rendererSource, /copyTextureToTexture/);
assert.match(
  rendererSource,
  /minFilter: "linear"/,
  "an uncertified atlas must still get linear minification within the base level",
);
assert.match(rendererSource, /mipmapFilter: atlasMipmapVerdict\.safe \? "linear" : "nearest"/);
// The readback has to report the frame the caller asked for, in the caller's
// orientation and channel order, or a scene probe scores the wrong pixels.
assert.match(rendererSource, /readbackRowTop\(canvas\.height, bottom, pixelHeight\)/);
assert.match(rendererSource, /readbackTargetRow\(pixelHeight, row\)/);
assert.match(rendererSource, /if \(format\.startsWith\("bgra"\)\) swapRedBlue\(pixels\)/);
assert.match(
  rendererSource,
  /copyTextureToBuffer\([\s\S]*?origin: \{ x: capture\.left, y: capture\.top, z: 0 \}/,
  "the copy must start at the requested region, not at the texture origin",
);

console.log("webgpu terrain presentation ok");
