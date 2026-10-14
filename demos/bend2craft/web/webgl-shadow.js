// Single-cascade sun shadow map for the WebGL 1 backend.
//
// The map is a sampleable depth texture rendered from an orthographic light
// frustum that is re-fitted around the camera every frame and snapped to the
// shadow texel grid, which is what keeps the shadow edges from crawling when
// the player moves. WebGL 1 has no `sampler2DShadow`, so the terrain shader
// compares manually and filters with a rotated Poisson disk.
//
// One cascade is deliberate: the map is fitted to the radius the player can see
// detail in, and the terrain shader fades the shadow into ambient at the edge
// of that radius instead of paying for a second pass over all the geometry.

import { createRenderTarget, RENDER_TARGET_FILTER } from "./gl-render-target.js";
import { cross, lookAt, multiply4, normalize, ortho } from "./gl-matrix.js";

export const SHADOW_MAP_SIZE = 2048;
export const SHADOW_LOW_MAP_SIZE = 1024;
/**
 * Half-extent of the cascade, in world units, measured in the light's own
 * space. The covered world region is therefore a square rotated with the sun,
 * so the region guaranteed for *every* sun direction is the inscribed circle of
 * radius SHADOW_RADIUS / sqrt(2) ~ 0.707 * SHADOW_RADIUS. Sizing a level against
 * the circumscribed value instead overstates the coverage.
 */
export const SHADOW_RADIUS = 52;
/** Distance from the cascade centre along the light axis, front and back. */
export const SHADOW_DEPTH_RANGE = 180;
/** Beyond this fraction of the radius the shadow is gone, so the edge never pops. */
export const SHADOW_FADE_START = 0.72;
export const SHADOW_FADE_END = 0.98;
/** Radius, in world units, covered for every sun direction. */
export const SHADOW_GUARANTEED_RADIUS = SHADOW_RADIUS / Math.SQRT2;
/** Fraction of the direct sun that still reaches a fully shadowed surface. */
export const SHADOW_FLOOR = 0.16;

export const SHADOW_DEPTH_VERTEX_SHADER = `
  precision highp float;
  attribute vec3 aPosition;
  uniform mat4 uLightViewProjection;
  uniform float uTime;
  uniform float uWaterLow;
  uniform float uWaterHigh;
  void main() {
    vec3 position = aPosition;
    if (position.y > 0.0) {
      // Match the water surface displacement so its shadow does not detach from
      // the surface it belongs to.
      float wave = sin(uTime * 1.6 + position.x * 0.38 + position.z * 0.27);
      position.y += 0.028 * wave;
    }
    gl_Position = uLightViewProjection * vec4(position, 1.0);
  }
`;

export const SHADOW_DEPTH_FRAGMENT_SHADER = `
  precision highp float;
  void main() {
    gl_FragColor = vec4(1.0);
  }
`;

function compile(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    const info = gl.getShaderInfoLog(shader);
    gl.deleteShader(shader);
    throw new Error(`Shadow shader compilation failed: ${info}`);
  }
  return shader;
}

export function createShadowDepthProgram(gl) {
  const vertex = compile(gl, gl.VERTEX_SHADER, SHADOW_DEPTH_VERTEX_SHADER);
  const fragment = compile(gl, gl.FRAGMENT_SHADER, SHADOW_DEPTH_FRAGMENT_SHADER);
  const program = gl.createProgram();
  gl.attachShader(program, vertex);
  gl.attachShader(program, fragment);
  gl.linkProgram(program);
  gl.deleteShader(vertex);
  gl.deleteShader(fragment);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    const info = gl.getProgramInfoLog(program);
    gl.deleteProgram(program);
    throw new Error(`Shadow program link failed: ${info}`);
  }
  return {
    program,
    lightViewProjection: gl.getUniformLocation(program, "uLightViewProjection"),
    time: gl.getUniformLocation(program, "uTime"),
    dispose() {
      gl.deleteProgram(program);
    },
  };
}

/**
 * Fit an orthographic light matrix around `center` looking down `sunDirection`.
 *
 * The centre is snapped to whole shadow texels in light space, so as the player
 * walks the projection moves in texel-sized steps instead of continuously and
 * the shadow edges stay put.
 */
export function fitSunShadowMatrix(sunDirection, center, {
  radius = SHADOW_RADIUS,
  depthRange = SHADOW_DEPTH_RANGE,
  mapSize = SHADOW_MAP_SIZE,
} = {}) {
  const light = normalize(sunDirection);
  // A light direction parallel to world up would make the cross product
  // degenerate, so bias the eye axis by a fraction of a degree.
  const eyeAxis = normalize([light[0], Math.min(0.9999, Math.max(-0.9999, light[1])), light[2]]);
  const distance = depthRange;
  const texelWorldSize = (radius * 2) / mapSize;

  // The light's own basis, used to quantise the centre before the view is built.
  // Quantising afterwards cannot work: the view is constructed looking at the
  // centre, so the centre is always at the light-space origin and the residual
  // is always zero. Snapping has to move the point the camera is fitted around.
  const basisRight = normalize(cross([0, 1, 0], eyeAxis));
  const basisUp = cross(eyeAxis, basisRight);
  const alongRight = center[0] * basisRight[0] + center[1] * basisRight[1] + center[2] * basisRight[2];
  const alongUp = center[0] * basisUp[0] + center[1] * basisUp[1] + center[2] * basisUp[2];
  const alongLight = center[0] * eyeAxis[0] + center[1] * eyeAxis[1] + center[2] * eyeAxis[2];
  const snappedRight = Math.round(alongRight / texelWorldSize) * texelWorldSize;
  const snappedUp = Math.round(alongUp / texelWorldSize) * texelWorldSize;
  const snappedCenter = [
    basisRight[0] * snappedRight + basisUp[0] * snappedUp + eyeAxis[0] * alongLight,
    basisRight[1] * snappedRight + basisUp[1] * snappedUp + eyeAxis[1] * alongLight,
    basisRight[2] * snappedRight + basisUp[2] * snappedUp + eyeAxis[2] * alongLight,
  ];

  const eye = [
    snappedCenter[0] + eyeAxis[0] * distance,
    snappedCenter[1] + eyeAxis[1] * distance,
    snappedCenter[2] + eyeAxis[2] * distance,
  ];
  const view = lookAt(eye, snappedCenter, [0, 1, 0]);
  const projection = ortho(-radius, radius, -radius, radius, 0.05, depthRange * 2);
  return multiply4(projection, view);
}

/**
 * Owns the shadow map render target and the depth-only program. `supported` is
 * false when the context cannot sample depth, in which case the terrain shader
 * simply keeps its unshadowed ambient term.
 */
export function createSunShadowPass(gl, { mapSize = SHADOW_MAP_SIZE, depthSampling } = {}) {
  const supported = Boolean(depthSampling?.supported);
  let target = null;
  let program = null;
  let currentSize = mapSize;

  function allocate(size) {
    return createRenderTarget(gl, {
      width: size,
      height: size,
      capabilities: {
        internalFormat: gl.RGBA,
        type: gl.UNSIGNED_BYTE,
      },
      // A sampleable depth attachment: the cascade is compared by reading the very
      // depth the depth test wrote, so 16-bit fixed point over the ortho range is
      // the precision that decides whether a flat surface self-shadows.
      depth: "texture",
      filter: RENDER_TARGET_FILTER.NEAREST,
    });
  }

  if (supported) {
    program = createShadowDepthProgram(gl);
    try {
      target = allocate(currentSize);
    } catch {
      // A depth-texture attachment can fail on drivers that advertise the
      // extension without supporting an orthographic depth-only FBO.
      program.dispose();
      return {
        supported: false,
        mapSize: currentSize,
        texelWorldSize: 1,
        radius: SHADOW_RADIUS,
        resize() { return false; },
        begin() { return null; },
        end() {},
        dispose() {},
      };
    }
  }
  return {
    supported,
    get mapSize() {
      return currentSize;
    },
    radius: SHADOW_RADIUS,
    get texelWorldSize() {
      return (SHADOW_RADIUS * 2) / currentSize;
    },
    /**
     * Change the cascade resolution. The shadow map is depth-only and covers a
     * fixed world area, so its texel count can exceed the whole frame's on a
     * weak rasteriser; the quality tier owns this and the caller re-applies it
     * whenever the tier changes. Reallocating is the only cost, so it is done
     * only on an actual change.
     */
    resize(size) {
      const next = Math.max(64, Math.floor(size));
      if (!supported || target === null || next === currentSize) return false;
      const previous = target;
      target = allocate(next);
      currentSize = next;
      previous.dispose();
      return true;
    },
    get texture() {
      return target?.depthTexture ?? null;
    },
    begin() {
      gl.bindFramebuffer(gl.FRAMEBUFFER, target.framebuffer);
      gl.viewport(0, 0, mapSize, mapSize);
      // Front-face culling in the depth pass pushes the comparison surface to
      // the back of the caster, which removes most acne on thin geometry.
      gl.enable(gl.CULL_FACE);
      gl.cullFace(gl.FRONT);
      gl.enable(gl.DEPTH_TEST);
      gl.depthMask(true);
      gl.depthFunc(gl.LEQUAL);
      gl.clear(gl.DEPTH_BUFFER_BIT);
      gl.useProgram(program.program);
      return program;
    },
    end() {
      gl.disable(gl.CULL_FACE);
      gl.cullFace(gl.BACK);
      gl.depthFunc(gl.LESS);
    },
    dispose() {
      program?.dispose();
      target?.dispose();
    },
  };
}

/**
 * GLSL shared by every lit surface: shadow lookup, a normal-offset bias and a
 * rotated Vogel filter.
 */
/**
 * Vogel (sunflower) disk offsets, packed one per texel.
 *
 * A Vogel disk is a low-discrepancy spiral: no random numbers, and the samples
 * stay evenly spread for any tap count. It lives in a texture rather than a
 * GLSL array because GLSL ES 1.00 has no array constructors, and because a
 * texture lets the tap count stay a uniform.
 */
export function createVogelDiskTexture(gl, size = 64) {
  const pixels = new Uint8Array(size * size * 4);
  const goldenAngle = Math.PI * (3 - Math.sqrt(5));
  for (let index = 0; index < size * size; index += 1) {
    const radius = Math.sqrt((index + 0.5) / (size * size));
    const angle = index * goldenAngle;
    const offset = index * 4;
    pixels[offset] = Math.round((Math.cos(angle) * radius * 0.5 + 0.5) * 255);
    pixels[offset + 1] = Math.round((Math.sin(angle) * radius * 0.5 + 0.5) * 255);
    pixels[offset + 2] = Math.round(radius * 255);
    pixels[offset + 3] = 255;
  }
  const texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, size, size, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
  gl.bindTexture(gl.TEXTURE_2D, null);
  return texture;
}

/**
 * GLSL shared by every lit surface: shadow lookup, a normal-offset bias and a
 * per-pixel rotated Vogel filter. `uShadowMap` holds normalised device depth.
 */
export const SHADOW_SAMPLING_GLSL = `
  uniform sampler2D uShadowMap;
  uniform sampler2D uShadowDisk;
  uniform mat4 uLightViewProjection;
  uniform float uShadowTexelSize;
  uniform float uShadowRadius;
  uniform vec2 uShadowFade;
  uniform float uShadowStrength;
  uniform float uShadowTaps;
  uniform float uShadowFloor;

  float interleavedGradientNoise(vec2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
  }

  float sunShadow(vec3 worldPosition, vec3 normal, vec3 lightDirection, float clearance) {
    if (uShadowStrength <= 0.0) return 1.0;
    // Normal offset: push the lookup along the surface normal by roughly one
    // shadow texel, scaled by how obliquely the light hits. This removes acne
    // on slopes without the peter-panning a constant depth bias would cause.
    float slope = clamp(1.0 - dot(normal, lightDirection), 0.0, 1.0);
    vec3 offsetPosition = worldPosition
      + normal * (1.2 + slope * 2.6) * uShadowTexelSize * uShadowRadius
      + lightDirection * clearance;
    vec3 projected = (uLightViewProjection * vec4(offsetPosition, 1.0)).xyz * 0.5 + 0.5;
    if (projected.z > 1.0 || projected.x < 0.0 || projected.x > 1.0
      || projected.y < 0.0 || projected.y > 1.0) {
      return 1.0;
    }
    // Fade the cascade out at its edge instead of letting the border clip hard.
    vec2 fromCenter = abs(projected.xy - 0.5) * 2.0;
    float edge = max(fromCenter.x, fromCenter.y);
    float cascade = 1.0 - smoothstep(uShadowFade.x, uShadowFade.y, edge);
    if (cascade <= 0.0) return 1.0;

    float receiver = projected.z;
    float bias = 0.0012 + slope * 0.0038;
    // Each pixel walks a different, evenly spread set of disk offsets, so the
    // residual error reads as fine noise instead of banded rings.
    float rotation = interleavedGradientNoise(gl_FragCoord.xy) * 6.2831853;
    float cosine = cos(rotation);
    float sine = sin(rotation);
    float radius = uShadowTexelSize * 1.7;
    int taps = int(uShadowTaps);
    float lit = 0.0;
    for (int index = 0; index < SHADOW_MAX_TAPS; index++) {
      if (index >= taps) break;
      vec3 disk = texture2D(uShadowDisk, vec2((float(index) + 0.5) / uShadowTaps, 0.5)).rgb;
      vec2 tap = vec2(disk.x * cosine - disk.y * sine, disk.x * sine + disk.y * cosine) * radius;
      float depth = texture2D(uShadowMap, projected.xy + tap).r;
      lit += (receiver - bias > depth) ? 0.0 : 1.0;
    }
    lit /= float(taps);
    // A shadowed surface still receives light scattered around the corner and
    // down through the sky. Without this floor the cascade reads as a hole cut
    // in the world, which is the most common way shadow maps look wrong.
    lit = mix(uShadowFloor, 1.0, lit);
    return mix(1.0, lit, cascade * uShadowStrength);
  }
`;
