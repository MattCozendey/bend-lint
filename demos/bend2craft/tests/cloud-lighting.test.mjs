import assert from "node:assert/strict";
import { createWebglSkyFragmentShader } from "../web/webgl-shaders.js";
import { CLOUD_DIFFUSE_SCATTER, CLOUD_PHASE_SCATTER } from "../web/terrain-presentation.js";

const WEBGL_SKY_FRAGMENT_SHADER = createWebglSkyFragmentShader();

// The cloud deck's brightness is the one term in the sky shader that a picture
// showed to be wrong rather than merely adjustable: lit only by the forward
// scattering lobe, a cloud can never be brighter than the sky behind it, so the
// deck read as a flat grey stain across a blue sky instead of as a lit volume.
//
// A cloud is a bright diffuse reflector - most of its light arrives from the
// whole sunlit hemisphere, and the phase function only describes the extra glow
// around the sun. So the sun term is split into an isotropic part and the phase
// part, and both are constants here rather than literals in the shader, because a
// number written into GLSL is a number nobody can find again.

// The deck has to be able to out-shine the sky, which is the whole point: with
// only the phase term its lit colour was a fraction of the sky's own.
//
// The value is calibrated from pictures rather than derived, so these bounds are
// the measured ones: at 0.55 the deck still measured darker than the sky behind
// it (132 against 149), at 1.8 it reads as a lit cumulus (160 against 149) and at
// 3.0 it was bright enough to start losing its shading (181). The window below is
// that measured span, so a later edit cannot quietly put the deck back to being a
// stain or blow it out.
assert.ok(CLOUD_DIFFUSE_SCATTER >= 1.2, "below about 1.2 the deck still reads as a stain against the sky");
assert.ok(CLOUD_DIFFUSE_SCATTER <= 2.5, "above about 2.5 the deck washes out and loses its shading");
assert.ok(CLOUD_PHASE_SCATTER > 0, "the forward lobe still has to add the glow around the sun");
assert.ok(
  CLOUD_DIFFUSE_SCATTER + CLOUD_PHASE_SCATTER < 4,
  "the two parts together must stay inside a tonemappable range",
);

// And the shader has to use these numbers rather than its own, or tuning the
// constant stops meaning anything.
assert.ok(
  WEBGL_SKY_FRAGMENT_SHADER.includes(CLOUD_DIFFUSE_SCATTER.toFixed(3)),
  "the sky shader must carry the diffuse constant, so tuning it changes the sky",
);
assert.ok(
  WEBGL_SKY_FRAGMENT_SHADER.includes(CLOUD_PHASE_SCATTER.toFixed(3)),
  "the sky shader must carry the phase constant, so tuning it changes the sky",
);
// Both halves have to be in the same sun term: a deck lit by one and not the
// other is the stain this replaced.
const sunTerm = /vec3 sunLit = ([^;]+);/.exec(WEBGL_SKY_FRAGMENT_SHADER);
assert.ok(sunTerm !== null, "the cloud sun term has to be findable in the shader");
assert.match(sunTerm[1], /CLOUD_DIFFUSE|0\.\d+/, "the sun term must name the diffuse constant");
assert.match(sunTerm[1], /phase/, "the sun term must still keep the forward-scattering lobe");

console.log("cloud lighting ok");