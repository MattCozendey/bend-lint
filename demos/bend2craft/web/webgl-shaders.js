import {
  SURFACE_MATERIAL_FIRE,
  SURFACE_MATERIAL_LAVA,
  SURFACE_MATERIAL_WATER,
} from "./surface-materials.js";
import {
  AERIAL_FOG_HEIGHT_FALLOFF,
  AERIAL_FOG_MIN_DENSITY,
  CLOUD_DIFFUSE_SCATTER,
  CLOUD_PHASE_SCATTER,
  FIRE_ALPHA,
  FIRE_PULSE_AMPLITUDE,
  FIRE_PULSE_SPEED,
  FIRE_PULSE_SPATIAL_FREQUENCY,
  LAVA_ALPHA,
  LAVA_PULSE_AMPLITUDE,
  LAVA_PULSE_SPEED,
  LAVA_PULSE_SPATIAL_FREQUENCY,
  MINING_FRACTURE_PROGRESS,
  MATERIAL_DETAIL_STRENGTH,
  TERRAIN_FOG_START,
  TERRAIN_VARIATION_SEED,
  TERRAIN_VARIATION_X,
  TERRAIN_VARIATION_Z,
  WATER_DEPTH_FLOOR_R,
  WATER_DEPTH_MAX,
} from "./terrain-presentation.js";
import { SHADOW_SAMPLING_GLSL } from "./webgl-shadow.js";

export function isSoftwareRenderer(rendererName) {
  return /swiftshader|llvmpipe|software|basic render/i.test(String(rendererName ?? ""));
}

/** Hard cap on shadow-filter taps, so the loop bound stays a GLSL constant. */
export const SHADOW_MAX_TAPS = 24;
/**
 * Hard cap on cloud-march samples, for the same reason.
 *
 * This is a compile-time bound and not a budget: the march costs what the tier
 * asks for and breaks out of the loop, so a larger constant costs nothing until
 * something asks for more. It is set at twice the densest tier so a player who
 * turns clouds up to 200% on the top tier gets twice the march rather than the
 * same march twice promised.
 */
export const CLOUD_MAX_STEPS = 48;

export const SKY_CLOUD_BOTTOM = 58;
export const SKY_CLOUD_TOP = 96;
/** Longest distance the cloud march will cover before fading out. */
export const MAX_CLOUD_SPAN = 620;

/**
 * Shared GLSL prelude: hashes, noise and tone/colour helpers used by both the
 * terrain and the sky. Kept as one string so the two programs cannot drift.
 */
const SHARED_GLSL = `
  float hash12(vec2 point) {
    vec3 p3 = fract(vec3(point.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
  }

  float valueNoise(vec2 point) {
    vec2 cell = floor(point);
    vec2 local = fract(point);
    local = local * local * (3.0 - 2.0 * local);
    float a = hash12(cell);
    float b = hash12(cell + vec2(1.0, 0.0));
    float c = hash12(cell + vec2(0.0, 1.0));
    float d = hash12(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
  }

  float fbm(vec2 point, int octaves) {
    float total = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int index = 0; index < 5; index++) {
      if (index >= octaves) break;
      total += valueNoise(point * frequency) * amplitude;
      frequency *= 2.03;
      amplitude *= 0.5;
    }
    return total;
  }

  // Henyey-Greenstein phase: strongly forward scattering, which is what makes
  // a cloud edge glow when the sun is behind it.
  float phaseHG(float cosine, float g) {
    float g2 = g * g;
    float denominator = 1.0 + g2 - 2.0 * g * cosine;
    return (1.0 - g2) / (4.0 * 3.14159265 * max(denominator * sqrt(max(denominator, 1e-4)), 1e-4));
  }

  float luminanceOf(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
  }
`;

export const WEBGL_SKY_VERTEX_SHADER = `
  precision highp float;
  attribute vec2 aPosition;
  varying vec2 vNdc;
  void main() {
    vNdc = aPosition;
    gl_Position = vec4(aPosition, 1.0, 1.0);
  }
`;

/**
 * Advanced sky: atmospheric gradient, stars, sun and moon discs, and a
 * raymarched cloud deck with light scattering.
 */
export function createWebglSkyFragmentShader({ volumetricClouds = true } = {}) {
  if (!volumetricClouds) return WEBGL_SKY_FALLBACK_FRAGMENT_SHADER;
  return `
  #ifdef GL_FRAGMENT_PRECISION_HIGH
  precision highp float;
  #else
  precision mediump float;
  #endif
  #define CLOUD_MAX_STEPS ${CLOUD_MAX_STEPS}
  #define MAX_CLOUD_SPAN ${MAX_CLOUD_SPAN.toFixed(1)}
  varying vec2 vNdc;
  uniform vec3 uCameraForward;
  uniform vec3 uCameraRight;
  uniform vec3 uCameraUp;
  uniform vec3 uCameraPosition;
  uniform vec3 uSkyColor;
  uniform vec3 uSkyHorizonColor;
  uniform vec3 uSunDirection;
  uniform vec3 uSunColor;
  uniform float uAspect;
  uniform float uTanHalfFov;
  uniform float uDaylight;
  uniform float uTime;
  uniform float uCloudSteps;
  uniform float uCloudLightSteps;
  uniform float uCloudCoverage;
  uniform float uWindSpeed;
  ${SHARED_GLSL}

  float cloudDensity(vec3 point) {
    vec2 wind = vec2(uTime * uWindSpeed * 0.55, uTime * uWindSpeed * 0.22);
    // Height fraction: 0 at the flat cloud base, 1 at the eroded top.
    float height = clamp((point.y - ${SKY_CLOUD_BOTTOM.toFixed(1)}) / ${(SKY_CLOUD_TOP - SKY_CLOUD_BOTTOM).toFixed(1)}, 0.0, 1.0);
    // Cumulus have a hard base and a rounded, eroding top. Both shoulders are
    // deliberately wide: a narrow profile turns into a thin shell, and a shell
    // sampled at a handful of depths produces hard contours.
    float profile = smoothstep(0.0, 0.34, height) * (1.0 - smoothstep(0.38, 1.0, height));

    // The noise lattice is 2D, so the field has to be sheared with height or the
    // density depends only on altitude and the deck collapses into horizontal
    // shells, which project to a visible ring when the camera looks along them.
    // A helical shear makes the field genuinely three-dimensional for the cost
    // of one sin and one cos.
    float twist = height * 2.3;
    vec2 shear = vec2(cos(twist), sin(twist)) * (height * 26.0);
    vec2 base = (point.xz + shear) * 0.0034 + wind * 0.004;

    float shape = fbm(base, 4);
    float detail = fbm(base * 2.4 + shear * 0.02, 3);
    float density = shape * 0.78 + detail * 0.22;
    float threshold = 1.0 - uCloudCoverage;
    // A wide ramp keeps the density gradient shallow, which is what stops the
    // isosurface from showing as a hard edge through a coarse march.
    density = smoothstep(threshold, threshold + 0.4, density);
    // Erosion eats into the edges of the shape, which is what gives the billows
    // their cauliflower silhouette instead of leaving a smooth blob.
    float billow = fbm(base * 4.7 + wind * 0.01, 3);
    density -= (0.3 - billow * 0.42) * smoothstep(0.12, 0.55, height) * 0.4;
    return max(density, 0.0) * profile;
  }

  void main() {
    vec3 skyRay = normalize(
      uCameraForward
      + uCameraRight * vNdc.x * uAspect * uTanHalfFov
      + uCameraUp * vNdc.y * uTanHalfFov
    );

    float vertical = clamp(skyRay.y, -1.0, 1.0);
    float sunHeight = uSunDirection.y;
    float dayFactor = smoothstep(-0.16, 0.24, sunHeight);

    // --- atmosphere -------------------------------------------------------
    // Rayleigh-like falloff plus a Mie lobe pointing at the sun, so the sky
    // reddens and brightens around sunrise instead of only changing hue.
    float zenith = clamp(vertical, 0.0, 1.0);
    vec3 skyColor = mix(uSkyHorizonColor, uSkyColor, pow(zenith, 0.62));
    float mieAmount = pow(max(dot(skyRay, uSunDirection), 0.0), 14.0);
    skyColor += uSunColor * mieAmount * (0.1 + 0.16 * dayFactor);
    // Horizon haze, thickest right at eye level.
    float horizon = 1.0 - clamp(abs(vertical), 0.0, 1.0);
    skyColor = mix(skyColor, uSkyHorizonColor, horizon * horizon * horizon * 0.42);

    // --- night ------------------------------------------------------------
    float night = 1.0 - smoothstep(0.18, 0.6, uDaylight);
    if (night > 0.01) {
      // A soft galactic band gives the sky a structure to read against,
      // instead of an even field of dots.
      float band = 1.0 - abs(dot(skyRay, normalize(vec3(0.42, 0.36, -0.83))));
      float milkyWay = pow(clamp(band, 0.0, 1.0), 26.0) * night;
      vec3 starCell = floor(skyRay * 340.0);
      vec2 starLocal = fract(skyRay * 340.0).xy - vec2(0.5);
      float starSize = 1.0 - smoothstep(0.02, 0.13, length(starLocal));
      float starBrightness = step(0.9968, hash12(starCell.xy + starCell.z * 17.0));
      float twinkle = 0.72 + 0.28 * sin(uTime * 2.4 + hash12(starCell.xy) * 62.8);
      skyColor += vec3(0.86, 0.9, 1.0) * starBrightness * starSize * night * twinkle * 0.9;
      skyColor += vec3(0.2, 0.24, 0.4) * milkyWay * 0.5;
    }

    // --- sun and moon -----------------------------------------------------
    float sunDot = max(dot(skyRay, uSunDirection), 0.0);
    float sunVisible = smoothstep(-0.12, 0.04, sunHeight);
    // Limb darkening: the disc is brighter at its centre than at its rim.
    float disc = smoothstep(0.99965, 0.99992, sunDot);
    float discEdge = smoothstep(0.9992, 0.9998, sunDot);
    float sunDisc = mix(discEdge, disc, 0.6);
    float sunGlow = pow(sunDot, 900.0) * 0.6 + pow(sunDot, 60.0) * 0.1 + pow(sunDot, 8.0) * 0.018;
    // The disc is kept just above 1.0 so it is the bloom stage, not the sky
    // pass, that makes it read as blindingly bright.
    skyColor += uSunColor * (sunDisc * 1.9 + sunGlow) * sunVisible;

    if (night > 0.01) {
      vec3 moonDirection = -uSunDirection;
      float moonDot = max(dot(skyRay, moonDirection), 0.0);
      float moonDisc = smoothstep(0.99955, 0.99985, moonDot) * night;
      float moonGlow = pow(moonDot, 900.0) * 0.9 + pow(moonDot, 30.0) * 0.06;
      // Project onto a tangent basis around the moon so the maria land on the
      // disc itself instead of drifting with the camera.
      vec3 moonRight = normalize(cross(moonDirection, vec3(0.0, 1.0, 0.0)) + vec3(1e-4, 0.0, 0.0));
      vec3 moonUp = normalize(cross(moonRight, moonDirection));
      vec2 moonLocal = vec2(dot(skyRay, moonRight), dot(skyRay, moonUp)) * 1200.0;
      float maria = 0.84 + 0.16 * valueNoise(moonLocal);
      skyColor += vec3(0.95, 0.96, 0.92) * moonDisc * 1.5 * maria * night;
      skyColor += vec3(0.62, 0.72, 0.95) * moonGlow * 0.35 * night;
    }

    // --- volumetric cloud deck -------------------------------------------
    if (vertical > 0.008 && uCloudSteps >= 1.0) {
      float bottom = ${SKY_CLOUD_BOTTOM.toFixed(1)};
      float top = ${SKY_CLOUD_TOP.toFixed(1)};
      float enter = (bottom - uCameraPosition.y) / vertical;
      float exitPoint = (top - uCameraPosition.y) / vertical;
      enter = max(enter, 0.0);
      if (exitPoint > enter) {
        int steps = int(uCloudSteps);
        int lightSteps = int(uCloudLightSteps);
        // Cap the marched distance. A shallow view angle through the deck spans
        // thousands of units, and a fixed step budget over that span makes the
        // accumulated optical depth jump in discrete shells, which shows up as
        // concentric rings around the sun. Clamping the span keeps the step size
        // bounded and costs nothing visually, because cloud that far away is
        // already washed into the horizon colour.
        float span = exitPoint - enter;
        float farFade = 1.0 - smoothstep(MAX_CLOUD_SPAN * 0.55, MAX_CLOUD_SPAN, span);
        span = min(span, MAX_CLOUD_SPAN);
        // Dither the ray start in world distance at every step count. A constant
        // offset turns the sparse march into visible contours; a per-pixel offset
        // trades them for fine noise, which the blur and the grade hide.
        float jitter = hash12(gl_FragCoord.xy * 1.7 + vec2(uTime * 0.7, uTime * 0.3));
        float transmittance = 1.0;
        vec3 scattered = vec3(0.0);
        // Forward scattering is what makes a cloud edge glow when the sun is
        // behind it. The phase function is already normalised, so it is scaled
        // rather than treated as a raw multiplier.
        float phase = phaseHG(dot(skyRay, uSunDirection), 0.7) * 0.85
          + phaseHG(dot(skyRay, uSunDirection), -0.2) * 0.3;
        float sunUp = smoothstep(-0.18, 0.12, sunHeight);
        float stepSize = span / float(steps);
        for (int index = 0; index < ${CLOUD_MAX_STEPS}; index++) {
          if (index >= steps) break;
          // Uniform spacing in world distance, dithered per pixel. Quadratic
          // spacing bunches samples at the near edge, which is where the shells
          // end up closest together and therefore most visible as rings; even
          // spacing plus a per-pixel offset turns them into fine noise instead.
          float t = enter + (float(index) + jitter) * stepSize;
          vec3 samplePoint = uCameraPosition + skyRay * t;
          float density = cloudDensity(samplePoint);
          if (density > 0.004) {
            // Light march: walk toward the sun and see how much cloud blocks it.
            float lightDepth = 0.0;
            for (int lightIndex = 0; lightIndex < 3; lightIndex++) {
              if (lightIndex >= lightSteps) break;
              vec3 lightPoint = samplePoint + uSunDirection * (18.0 + float(lightIndex) * 32.0);
              lightDepth += cloudDensity(lightPoint);
            }
            float lightTransmittance = exp(-lightDepth * 0.7);
            // Powder term: dense cloud interiors stay dark even when backlit.
            float powder = 1.0 - exp(-density * 2.6);
            float shade = mix(0.5, 1.0, lightTransmittance) * powder;
            // A cloud is a bright diffuse reflector, so most of its light comes
            // from the whole sunlit hemisphere rather than from the forward lobe
            // alone. With the phase term by itself the deck could never out-shine
            // the sky behind it and read as a flat grey stain across it, so the
            // sun term carries an isotropic part and the lobe adds the glow on top.
            vec3 sunLit = uSunColor * shade * (${CLOUD_DIFFUSE_SCATTER.toFixed(3)}
              + phase * ${CLOUD_PHASE_SCATTER.toFixed(3)}) * (0.35 + 0.65 * sunUp);
            // The underside of a cumulus is lit by bounce, not by the sun, so the
            // ambient term is generous; too little of it and the shaded half of
            // the deck collapses to the flat dark grey it used to be everywhere.
            vec3 ambient = mix(uSkyHorizonColor, uSkyColor, 0.5) * (0.55 + 0.4 * uDaylight);
            // Energy-conserving absorption. A linear density*stepSize term
            // over-counts on the first sample that lands inside a cloud, which is
            // exactly where the banding shows.
            float absorb = 1.0 - exp(-density * stepSize * 0.32);
            scattered += (sunLit + ambient) * absorb * transmittance;
            transmittance *= 1.0 - absorb;
            if (transmittance < 0.02) break;
          }
        }
        float cloudAlpha = clamp(1.0 - transmittance, 0.0, 1.0) * farFade;
        skyColor = mix(skyColor, scattered, cloudAlpha);
      }
    }

    // Ground haze below the horizon keeps the sky dome from showing a hard
    // seam where the horizon skirt mesh ends.
    float belowHorizon = 1.0 - smoothstep(-0.24, 0.0, vertical);
    skyColor = mix(skyColor, uSkyHorizonColor * 0.66, belowHorizon * 0.72);

    gl_FragColor = vec4(max(skyColor, vec3(0.0)), 1.0);
  }
`;
}

export const WEBGL_SKY_FALLBACK_FRAGMENT_SHADER = `
  #ifdef GL_FRAGMENT_PRECISION_HIGH
  precision highp float;
  #else
  precision mediump float;
  #endif
  varying vec2 vNdc;
  uniform vec3 uCameraForward;
  uniform vec3 uCameraRight;
  uniform vec3 uCameraUp;
  uniform vec3 uSkyColor;
  uniform vec3 uSkyHorizonColor;
  uniform float uAspect;
  uniform float uTanHalfFov;

  void main() {
    vec3 skyRay = normalize(
      uCameraForward
      + uCameraRight * vNdc.x * uAspect * uTanHalfFov
      + uCameraUp * vNdc.y * uTanHalfFov
    );
    float vertical = clamp(skyRay.y * 0.5 + 0.5, 0.0, 1.0);
    vec3 skyColor = mix(uSkyHorizonColor, uSkyColor, smoothstep(0.0, 0.86, vertical));
    float horizonBase = 1.0 - clamp(abs(skyRay.y), 0.0, 1.0);
    float horizonHaze = horizonBase * horizonBase * horizonBase;
    skyColor = mix(skyColor, uSkyHorizonColor, horizonHaze * 0.36);
    gl_FragColor = vec4(clamp(skyColor * 1.08, 0.0, 1.0), 1.0);
  }
`;

/**
 * Minimal terrain shader. It is the compile-failure fallback, not a quality
 * tier: it has no shadow map, no bump, no wind and no water shading, so it only
 * has to keep the world visible and correctly coloured.
 */
export const WEBGL_TERRAIN_FALLBACK_VERTEX_SHADER = `
  precision highp float;
  attribute vec3 aPosition;
  attribute vec3 aColor;
  attribute vec2 aLight;
  attribute vec2 aUV;
  attribute float aMaterial;
  attribute vec4 aTileRect;
  uniform mat4 uViewProjection;
  uniform vec3 uCamera;
  varying vec3 vColor;
  varying vec2 vLight;
  varying vec2 vUV;
  varying vec3 vWorldPosition;
  varying vec3 vViewDirection;
  varying float vMaterial;
  varying vec4 vTileRect;
  varying float vFog;
  void main() {
    vColor = aColor;
    vLight = aLight;
    vUV = aUV;
    vWorldPosition = aPosition;
    vViewDirection = aPosition - uCamera;
    vMaterial = aMaterial;
    vTileRect = aTileRect;
    vFog = clamp((distance(aPosition, uCamera) - ${TERRAIN_FOG_START.toFixed(1)}) / ${Number(60).toFixed(1)}, 0.0, 1.0);
    gl_Position = uViewProjection * vec4(aPosition, 1.0);
  }
`;

export const WEBGL_TERRAIN_FALLBACK_FRAGMENT_SHADER = `
  #ifdef GL_FRAGMENT_PRECISION_HIGH
  precision highp float;
  #else
  precision mediump float;
  #endif
  varying vec3 vColor;
  varying vec2 vLight;
  varying vec2 vUV;
  varying vec3 vWorldPosition;
  varying vec3 vViewDirection;
  varying float vMaterial;
  varying vec4 vTileRect;
  varying float vFog;
  uniform float uDaylight;
  uniform vec3 uSkyColor;
  uniform vec3 uSkyHorizonColor;
  uniform vec3 uSunColor;
  uniform sampler2D uAtlas;
  uniform float uSurfacePass;
  uniform float uShadowPass;
  uniform float uVfxPass;
  uniform float uMiningProgress;

  void main() {
    bool miningPass = vTileRect.x < -0.5;
    vec2 tileUv = mix(vTileRect.xy, vTileRect.zw, fract(vUV));
    vec4 textureColor = miningPass ? vec4(1.0) : texture2D(uAtlas, tileUv);
    vec3 albedo = vColor * textureColor.rgb;
    vec3 lit = albedo * mix(0.35, 1.0, uDaylight);
    lit += uSunColor * pow(max(dot(vec3(0.0, 1.0, 0.0), normalize(-vViewDirection)), 0.0), 24.0) * 0.12;
    float alpha = textureColor.a;
    vec3 color = lit;
    if (uVfxPass > 0.5) {
      vec2 particleUv = vUV * 2.0 - 1.0;
      float radius = length(particleUv);
      float falloff = 1.0 - smoothstep(0.18, 1.0, radius);
      float core = 1.0 - smoothstep(0.0, 0.5, radius);
      float additive = vLight.y > 0.5 ? 1.0 : 0.0;
      float particleAlpha = clamp(vLight.x, 0.0, 1.0) * falloff * (1.0 - vFog * 0.8);
      vec3 particleColor = vColor * (1.0 + additive * (core * 1.9 - 0.25));
      gl_FragColor = vec4(particleColor * particleAlpha, particleAlpha * (1.0 - additive));
      return;
    }
    if (uShadowPass > 0.5) {
      vec2 shadowUv = vUV * 2.0 - 1.0;
      float softness = 1.0 - smoothstep(0.38, 1.0, length(shadowUv));
      color = vec3(0.015, 0.02, 0.018);
      alpha = 0.28 * softness * (1.0 - vFog * 0.65);
    } else if (miningPass) {
      color = vec3(0.04, 0.045, 0.04);
      alpha = 0.2;
    }
    vec3 fogColor = mix(uSkyHorizonColor, uSkyColor, 0.58);
    gl_FragColor = vec4(mix(clamp(color, 0.0, 1.0), fogColor, vFog), alpha);
  }
`;

/**
 * The real terrain shader.
 *
 * Lighting is per pixel: a sun term from the actual sun direction multiplied by
 * the shadow map, a hemispheric sky ambient gated by the baked sky-light level
 * and by vertex occlusion, and a GGX specular. `aColor` is only a per-face
 * grade, so a face facing the sun is actually brighter than one facing away.
 */
export function createWebglTerrainShaderSources(fogDistance, {
  shadows = true,
  bumpMapping = true,
  waterDetail = true,
  grassWind = true,
  aerialPerspective = true,
} = {}) {
  const waterLow = SURFACE_MATERIAL_WATER.toFixed(1);
  const lavaLow = SURFACE_MATERIAL_LAVA.toFixed(1);
  const fireLow = SURFACE_MATERIAL_FIRE.toFixed(1);
  const fireHigh = (SURFACE_MATERIAL_FIRE + 1).toFixed(1);
  // Opaque terrain encodes `10 + block`, so grass is 13 and leaves 14 in the
  // band. Both are shaded per pixel (the backlit translucency below); only
  // leaves are displaced in the vertex stage, because only leaves are exempt
  // from greedy merging.
  const grassMaterial = (10 + 3).toFixed(1);
  const leafMaterial = (10 + 4).toFixed(1);
  // GLSL ES 1.00 has no array constructors and no non-constant loop bounds, so
  // the shadow filter size is injected as a preprocessor constant.
  const defines = `#define SHADOW_MAX_TAPS ${SHADOW_MAX_TAPS}`;

  const windGLSL = grassWind ? `
    // A smooth field of gusts, sampled per vertex from the world position.
    //
    // Only foliage rides this field. Terrain quads are greedy-merged, so a
    // merged top face is a single quad with four corners however large it is,
    // and a world-space field sampled at four corners can do nothing but tilt
    // that quad. A plain of those quads therefore read as a few big facets
    // rolling like ocean swell rather than as a field rippling, and the block
    // surface is the surface the player collides against, so moving it
    // desyncs what is drawn from what is stood on. Leaves are exempt from
    // merging, so a leaf cell is its own quad and the field is sampled densely
    // enough to stay coherent.
    float windField(vec2 point, float time) {
      return sin(point.x * 0.34 + time * 1.15) * 0.46
        + sin(point.y * 0.27 - time * 0.92) * 0.33
        + sin((point.x + point.y) * 0.13 + time * 0.61) * 0.28;
    }
  ` : "";

  const waterSwell = waterDetail
    ? `
    if (uSurfacePass > 0.5 && aMaterial >= ${waterLow} && aMaterial < ${lavaLow}) {
      // Gerstner-style swell: two crossing wave trains plus a slow swell. The
      // large-scale motion lives here; the fine chop is added as a normal in
      // the fragment shader, which is where it can be shaded per pixel.
      //
      // Amplitude is faded with distance. A water plane seen almost edge-on
      // covers a huge world area per pixel, so any surviving displacement turns
      // into a jagged silhouette and the specular aliases into hard horizontal
      // streaks right along the horizon.
      float viewDistance = distance(position, uCamera);
      float waveFade = 1.0 - smoothstep(28.0, 90.0, viewDistance);
      vec2 p = position.xz;
      float swell = sin(p.x * 0.09 + p.y * 0.07 + uTime * 0.62);
      float chopA = sin(p.x * 0.31 - p.y * 0.19 + uTime * 1.55);
      float chopB = sin(-p.x * 0.17 + p.y * 0.38 - uTime * 1.21);
      position.y += (swell * 0.055 + chopA * 0.028 + chopB * 0.021) * waveFade;
    }`
    : "";

  const surfaceAnimation = `${waterSwell}
    ${grassWind ? `
    // Every face of a leaf cell, not just the up-facing one. The field is a
    // function of world position and the leaf faces share each corner's world
    // position, so all six faces of a cell agree on that corner and the cell
    // moves as one rigid body. Gating on the face normal would leave the sides
    // behind and slide the top face off them, opening a slit around every leaf
    // block's top rim.
    if (uSurfacePass < 0.5 && abs(aMaterial - ${leafMaterial}) < 0.25) {
      float sway = windField(position.xz * 1.7 + 11.3, uTime * 1.25);
      position.y += sway * 0.085;
      position.xz += vec2(sway * 0.05, sway * -0.04);
    }` : ""}
  `;

  const vertexSource = `
    precision highp float;
    attribute vec3 aPosition;
    attribute vec3 aColor;
    attribute vec2 aLight;
    attribute vec3 aNormal;
    attribute vec2 aUV;
    attribute float aMaterial;
    attribute vec4 aTileRect;
    uniform mat4 uViewProjection;
    uniform vec3 uCamera;
    uniform float uTime;
    uniform float uSurfacePass;
    varying vec3 vColor;
    varying vec2 vLight;
    varying vec3 vNormal;
    varying vec2 vUV;
    varying vec3 vWorldPosition;
    varying vec3 vViewDirection;
    varying float vMaterial;
    varying vec4 vTileRect;
    varying float vFog;
    varying float vAerialFog;
    ${windGLSL}
    void main() {
      vec3 position = aPosition;
      ${surfaceAnimation}
      vColor = aColor;
      vLight = aLight;
      vNormal = aNormal;
      vUV = aUV;
      vWorldPosition = position;
      vViewDirection = position - uCamera;
      vMaterial = aMaterial;
      vTileRect = aTileRect;
      float viewDistance = distance(position, uCamera);
      vFog = clamp((viewDistance - ${TERRAIN_FOG_START.toFixed(1)}) / ${Number(fogDistance).toFixed(1)}, 0.0, 1.0);
      ${
        aerialPerspective
          ? `float heightAttenuation = exp(-max(position.y - uCamera.y, 0.0) * ${AERIAL_FOG_HEIGHT_FALLOFF.toFixed(3)});
      vAerialFog = clamp(vFog * (${AERIAL_FOG_MIN_DENSITY.toFixed(2)} + ${(1 - AERIAL_FOG_MIN_DENSITY).toFixed(2)} * heightAttenuation), 0.0, 1.0);`
          : "vAerialFog = vFog;"
      }
      gl_Position = uViewProjection * vec4(position, 1.0);
    }
  `;

  // The extension directive must be the first token in the shader, before any
  // precision statement, so it is prepended here rather than inlined below.
  const fragmentSource = `
    ${bumpMapping ? "#extension GL_OES_standard_derivatives : enable\n" : ""}#ifdef GL_FRAGMENT_PRECISION_HIGH
  precision highp float;
  #else
  precision mediump float;
  #endif
  ${defines}
  varying vec3 vColor;
  varying vec2 vLight;
  varying vec3 vNormal;
  varying vec2 vUV;
  varying vec3 vWorldPosition;
  varying vec3 vViewDirection;
  varying float vMaterial;
  varying vec4 vTileRect;
  varying float vFog;
  varying float vAerialFog;
  uniform float uDaylight;
  uniform vec3 uSkyColor;
  uniform vec3 uSkyHorizonColor;
  uniform vec3 uGroundBounce;
  uniform vec3 uSunDirection;
  uniform vec3 uSunColor;
  uniform float uSunIntensity;
  uniform float uAmbientStrength;
  uniform float uAmbientDesaturation;
  uniform sampler2D uAtlas;
  uniform sampler2D uCloudMap;
  uniform sampler2D uSceneDepth;
  uniform float uTime;
  uniform float uSurfacePass;
  uniform float uShadowPass;
  uniform float uVfxPass;
  uniform float uMiningProgress;
  uniform float uBumpStrength;
  uniform float uDetailStrength;
  uniform float uDetailScale;
  uniform float uWaterDetail;
  uniform float uNear;
  uniform float uFar;
  uniform vec3 uCameraPosition;
  ${SHADOW_SAMPLING_GLSL}
  ${SHARED_GLSL}

  float linearizeDepth(float depth) {
    float ndc = depth * 2.0 - 1.0;
    return (2.0 * uNear * uFar) / (uFar + uNear - ndc * (uFar - uNear));
  }

  ${
    bumpMapping
      ? `
  // Derivative bump (Mikkelsen): turn a height stored in the atlas into a
  // normal perturbation using screen-space derivatives of world position. It
  // gives real surface relief from a flat texture with no normal-map channel.
  vec3 perturbNormal(vec3 normal, vec3 viewDirection, float height) {
    vec3 positionDerivativeX = dFdx(vWorldPosition);
    vec3 positionDerivativeY = dFdy(vWorldPosition);
    float heightDerivativeX = dFdx(height);
    float heightDerivativeY = dFdy(height);
    vec3 cross1 = cross(positionDerivativeY, normal);
    vec3 cross2 = cross(normal, positionDerivativeX);
    float determinant = dot(positionDerivativeX, cross1);
    vec3 gradient = sign(determinant) * (heightDerivativeX * cross1 + heightDerivativeY * cross2);
    return normalize(abs(determinant) * normal - uBumpStrength * gradient);
  }`
      : ""
  }

  ${
    shadows
      ? ""
      : `
  float sunShadow(vec3 worldPosition, vec3 normal, vec3 lightDirection, float clearance) {
    return 1.0;
  }`
  }

  // GGX specular. Terrain is a dielectric, so F0 stays low; the lobe is what
  // gives stone and sand their grazing-angle sheen and makes wet-looking
  // surfaces read as polished.
  vec3 specularLobe(vec3 normal, vec3 viewDirection, vec3 lightDirection, float roughness) {
    vec3 halfway = normalize(lightDirection + viewDirection);
    float ndotl = max(dot(normal, lightDirection), 0.0);
    float ndoth = max(dot(normal, halfway), 0.0);
    float ndotv = max(dot(normal, viewDirection), 0.0001);
    float alpha = max(roughness * roughness, 0.004);
    float alpha2 = alpha * alpha;
    float denominator = ndoth * ndoth * (alpha2 - 1.0) + 1.0;
    float distribution = alpha2 / (3.14159265 * denominator * denominator);
    // Smith visibility, height-correlated approximation.
    float visibility = 0.5 / max(mix(2.0 * ndotl * ndotv, ndotl + ndotv, alpha), 0.0001);
    float fresnel = 0.04 + 0.96 * pow(1.0 - max(dot(halfway, viewDirection), 0.0), 5.0);
    return vec3(min(distribution * visibility * fresnel * ndotl, 12.0));
  }

  vec3 fresnelSchlick(float cosine, float f0) {
    return vec3(f0) + (vec3(1.0) - vec3(f0)) * pow(1.0 - clamp(cosine, 0.0, 1.0), 5.0);
  }

  void main() {
    bool miningPass = vTileRect.x < -0.5;
    vec2 tileUv = mix(vTileRect.xy, vTileRect.zw, fract(vUV));
    vec4 textureColor = miningPass ? vec4(1.0) : texture2D(uAtlas, tileUv);

    // Detail layer. One tile per block makes a wall of stone read as a grid of
    // identical stamps, so the same tile is resampled at a higher frequency and
    // used only to modulate brightness. It carries no hue, which hides the
    // repeat while leaving the block's identity intact.
    vec2 detailUv = mix(vTileRect.xy, vTileRect.zw, fract(vUV * uDetailScale));
    vec3 detailSample = miningPass ? vec3(1.0) : texture2D(uAtlas, detailUv).rgb;
    float detailModulation = 1.0 + uDetailStrength * (dot(detailSample, vec3(0.3333)) - 0.5);

    float materialVariation = fract(sin(dot(floor(vWorldPosition.xz), vec2(${TERRAIN_VARIATION_X}, ${TERRAIN_VARIATION_Z}))) * ${TERRAIN_VARIATION_SEED});
    vec3 normal = normalize(vNormal);
    vec3 viewDirection = normalize(-vViewDirection);
    float viewDistance = length(vViewDirection);

    // Micro-relief: a bounded multiplier from the material's own sample, so it
    // adds contrast without ever replacing the albedo.
    float detail = 1.0 + ${MATERIAL_DETAIL_STRENGTH} * (clamp(textureColor.r, 0.0, 1.0) * 2.0 - 1.0);
    vec3 albedo = vColor * textureColor.rgb * detail * detailModulation;
    // A little large-scale colour drift stops a big field of one block from
    // looking printed.
    albedo *= 0.94 + 0.12 * materialVariation;

    float occlusion = clamp(vLight.x, 0.0, 1.0);
    float skyLightLevel = clamp(vLight.y, 0.0, 1.0);
    float roughness = mix(0.62, 0.98, materialVariation);

    ${
      bumpMapping
        ? `if (!miningPass && uBumpStrength > 0.0) {
      normal = perturbNormal(normal, viewDirection, textureColor.r * 0.6 + textureColor.g * 0.4);
    }`
        : ""
    }

    float alpha = textureColor.a;
    vec3 emissive = vec3(0.0);

    if (uSurfacePass > 0.5 && vMaterial >= ${waterLow} && vMaterial < ${lavaLow}) {
      // ---------------- water ----------------
      float depthInColumn = clamp(vMaterial - ${waterLow}, 0.0, 1.0);
      vec2 flow = vWorldPosition.xz;
      // Three crossing gerstner-ish gradients give a normal with real detail at
      // every distance, instead of a sine that reads as a repeating pattern.
      float waveA = sin(flow.x * 0.72 + flow.y * 0.41 + uTime * 1.35);
      float waveB = sin(-flow.x * 0.38 + flow.y * 0.83 - uTime * 1.07);
      float waveC = sin(flow.x * 1.61 - flow.y * 1.12 + uTime * 2.11);
      float waveD = sin(flow.x * 3.1 + flow.y * 2.4 - uTime * 2.9);
      vec2 gradient = vec2(
        cos(flow.x * 0.72 + flow.y * 0.41 + uTime * 1.35) * 0.72 * 0.055
        + cos(-flow.x * 0.38 + flow.y * 0.83 - uTime * 1.07) * -0.38 * 0.045
        + cos(flow.x * 1.61 - flow.y * 1.12 + uTime * 2.11) * 1.61 * 0.018
        + cos(flow.x * 3.1 + flow.y * 2.4 - uTime * 2.9) * 3.1 * 0.006,
        cos(flow.x * 0.72 + flow.y * 0.41 + uTime * 1.35) * 0.41 * 0.055
        + cos(-flow.x * 0.38 + flow.y * 0.83 - uTime * 1.07) * 0.83 * 0.045
        + cos(flow.x * 1.61 - flow.y * 1.12 + uTime * 2.11) * -1.12 * 0.018
        + cos(flow.x * 3.1 + flow.y * 2.4 - uTime * 2.9) * 2.4 * 0.006
      );
      // Waves flatten out with distance, otherwise the high-frequency terms
      // alias into noise across the whole far field.
      float detailFade = uWaterDetail * (1.0 - smoothstep(18.0, 70.0, viewDistance));
      normal = normalize(vec3(-gradient.x * detailFade * 22.0, 1.0, -gradient.y * detailFade * 22.0));
      // Beyond the fade the normal is exactly straight up. Leaving any residual
      // tilt there is what produces the horizontal specular banding at the
      // horizon, because a near-edge-on surface turns a small normal change into
      // a large reflected-direction change.
      normal = normalize(mix(vec3(0.0, 1.0, 0.0), normal, clamp(detailFade * 1.6, 0.0, 1.0)));
      // Normal filtering, retested now that the cascade sampler is actually bound.
      // The wave field carries slopes steep enough to swing a fourth-power Fresnel
      // and an analytic sky reflection from one pixel to the next, which is what
      // leaves the surface stippled. Flattening by the normal's own screen
      // footprint is self-adjusting: the waves keep their shape wherever a pixel
      // can resolve them and only flatten where it cannot.
${
  bumpMapping
    ? `      float slopeFootprint = clamp(length(fwidth(normal)) * 7.0, 0.0, 1.0);
      normal = normalize(mix(normal, vec3(0.0, 1.0, 0.0), slopeFootprint * 0.92));`
    : "      float slopeFootprint = 0.0;"
}
      // Foam belongs on the crests and along the shoreline, not across the whole
      // surface. The open-water contribution is deliberately tiny: a threshold
      // that fires on a third of the surface turns the lake into white noise.
      float crest = waveA * 0.4 + waveB * 0.32 + waveC * 0.18 + waveD * 0.1;
      // The shoreline term has to key off a genuinely thin film. A flooded plain is
      // one cell deep everywhere, so a threshold that treats "shallower than a
      // third of a cell" as shore marks the entire lake as shore: the water comes
      // out a uniform blown-out sheet, and the crest term dithering on top of that
      // baseline is what stippled it.
      float shoreFoam = 1.0 - smoothstep(0.0, 0.1, depthInColumn);
      // Widened, because a hard threshold on a four-sine sum is binary per pixel
      // and reads as speckle rather than as a crest.
      float crestFoam = smoothstep(0.6, 1.0, crest) * 0.2;
      float shoreline = shoreFoam * (0.55 + 0.45 * sin(shoreFoam * 26.0 + uTime * 1.4) * 0.5);
      // Low-frequency breakup so the foam reads as lace, not per-texel speckle.
      float foamNoise = valueNoise(flow * 0.9 + vec2(uTime * 0.22, -uTime * 0.16));
      float foam = clamp((crestFoam + shoreline * 0.35) * (0.45 + 0.55 * foamNoise), 0.0, 1.0);
      foam *= 1.0 - smoothstep(34.0, 90.0, viewDistance);

      float ndotv = max(dot(normal, viewDirection), 0.0);
      float fresnel = pow(1.0 - ndotv, 4.2);
      // Reflection direction against the sky, plus the sun's own glare.
      vec3 reflected = reflect(-viewDirection, normal);
      float reflectedUp = clamp(reflected.y * 0.5 + 0.5, 0.0, 1.0);
      vec3 skyReflection = mix(uSkyHorizonColor, uSkyColor, pow(reflectedUp, 0.7)) * 1.35;
      skyReflection = mix(skyReflection, mix(uSkyHorizonColor, uSkyColor, 0.55) * 1.35, slopeFootprint * 0.7);
      // A real environment lookup is mip-filtered by the roughness of the
      // surface that reflects it. This one is analytic, so it has to be pulled
      // toward the average sky by hand, or the reflection keeps a hard horizon
      // line that the flattened normal still crosses pixel to pixel.

      // Beer-Lambert absorption: the deeper the column, the more the bottom
      // falls away and the less the bed shows through.
      float pathLength = depthInColumn * max(1.0, 1.0 / max(ndotv, 0.22));
      float absorption = 1.0 - exp(-pathLength * 1.35);
      vec3 shallowColor = vec3(0.10, 0.42, 0.46);
      vec3 deepColor = vec3(${WATER_DEPTH_FLOOR_R.toFixed(3)}, 0.055, 0.11);
      vec3 bodyColor = mix(shallowColor, deepColor, absorption);
      // The bed of a shallow body still tints the water, but only faintly. The
      // bed is seen through a metre of absorbing water, so most of its own
      // contrast is scattered away; keeping more than a trace of it turns the
      // tile's per-texel grain into visible stipple across the whole surface.
      vec3 bedTint = mix(albedo, vec3(0.0), 0.72);

      float sunVisible = smoothstep(-0.1, 0.08, uSunDirection.y);
      float shadow = sunShadow(vWorldPosition, normal, uSunDirection, 1.35);
      vec3 sunSpecular = specularLobe(normal, viewDirection, uSunDirection, mix(0.06, 0.4, slopeFootprint)) * uSunColor * 5.0 * sunVisible * shadow;
      // Caustics: the light pattern a rippled surface focuses on the floor.
${
  waterDetail
    ? `      vec2 causticUv = vWorldPosition.xz * 0.09 + vec2(uTime * 0.012, -uTime * 0.008);
      float causticPattern = texture2D(uCloudMap, causticUv).r * texture2D(uCloudMap, causticUv * 2.1 + 0.37).r;
      float caustic = smoothstep(0.16, 0.46, causticPattern) * (1.0 - absorption) * sunVisible * shadow;`
    : "      float caustic = 0.0;"
}

      vec3 waterColor = mix(bedTint * bodyColor, skyReflection, clamp(fresnel * 0.92 + 0.08, 0.0, 1.0));
      waterColor += uSunColor * sunVisible * shadow * 0.1 * (1.0 - absorption) * max(dot(normal, uSunDirection), 0.0);
      waterColor += vec3(0.22, 0.72, 0.66) * caustic * 0.55;
      waterColor += vec3(0.62, 0.86, 0.88) * foam * 0.28;
      // A sun-facing sheet of water glitters. The exponent is high so it stays a
      // tight sparkle instead of a sheet of white, and the distance fade keeps it
      // from aliasing into horizontal streaks along the horizon.
${
  waterDetail
    ? `      // The exponent is the whole story here. At 260 the lobe is far narrower than
      // a pixel at any distance, so instead of a sparkle it resolves into isolated
      // fireflies, and the normal's screen footprint is too small for the damping
      // below to engage. A lobe the renderer can actually resolve reads as glitter;
      // one it cannot has to be widened until it can.
      float sunGlitter = pow(max(dot(reflect(-uSunDirection, normal), viewDirection), 0.0), mix(70.0, 22.0, slopeFootprint));
      float glitterFade = (1.0 - smoothstep(30.0, 110.0, viewDistance)) * (1.0 - slopeFootprint * 0.85);
      waterColor += uSunColor * sunGlitter * 1.5 * sunVisible * shadow * glitterFade * (0.3 + 0.7 * fresnel);`
    : ""
}

      emissive += waterColor;
      alpha = clamp(0.58 + fresnel * 0.3 + foam * 0.2 + absorption * 0.16, 0.0, 1.0);
      // Water is nearly all specular and reflection, so it deliberately skips
      // the diffuse sun term further down; adding one would wash out the body.
      roughness = 0.05;
    } else if (uSurfacePass > 0.5 && vMaterial >= ${lavaLow} && vMaterial < ${fireLow}) {
      // ---------------- lava ----------------
      float pulse = 1.0 + ${LAVA_PULSE_AMPLITUDE} * sin(uTime * ${LAVA_PULSE_SPEED} + vWorldPosition.x * ${LAVA_PULSE_SPATIAL_FREQUENCY});
      vec2 crust = vWorldPosition.xz * 0.24;
      float cracks = smoothstep(0.42, 0.62, valueNoise(crust + vec2(uTime * 0.03, uTime * 0.017)));
      vec3 hot = mix(vec3(0.55, 0.12, 0.02), vec3(1.6, 0.62, 0.12), cracks);
      emissive = hot * pulse * 2.6;
      alpha = max(alpha, ${LAVA_ALPHA});
      roughness = 0.35;
    } else if (uSurfacePass > 0.5 && vMaterial >= ${fireLow} && vMaterial < ${fireHigh}) {
      float pulse = 1.0 + ${FIRE_PULSE_AMPLITUDE} * sin(uTime * ${FIRE_PULSE_SPEED.toFixed(1)} + vWorldPosition.y * ${FIRE_PULSE_SPATIAL_FREQUENCY.toFixed(1)});
      float flicker = 0.65 + 0.35 * valueNoise(vWorldPosition.xz * 3.1 + vec2(0.0, uTime * 2.4));
      emissive = vec3(1.5, 0.52, 0.14) * pulse * flicker * 2.2;
      alpha = max(alpha, ${FIRE_ALPHA});
    }

    vec3 color;
    if (uSurfacePass > 0.5 && vMaterial >= ${waterLow} && vMaterial < ${lavaLow}) {
      color = emissive;
    } else {
      // ---------------- direct sun ----------------
      float shadow = sunShadow(vWorldPosition, normal, uSunDirection, 0.0);
      float ndotl = max(dot(normal, uSunDirection), 0.0);
      // Soften the terminator: a hard N.L makes blocky terrain look chipped.
      float wrapped = max((ndotl + 0.18) / 1.18, 0.0);
      // A wide fade on the sun's height: a sun just under the horizon still
      // throws long warm light, and switching the direct term off at exactly
      // zero makes dusk collapse in a single frame.
      float sunVisible = smoothstep(-0.16, 0.14, uSunDirection.y);
      vec3 sunLight = uSunColor * uSunIntensity * sunVisible * shadow;
      vec3 diffuse = albedo * sunLight * mix(ndotl, wrapped, 0.35);

      // ---------------- ambient ----------------
      // Hemispheric: sky colour from above, bounced ground colour from below.
      // The sky term is pulled partway toward its own luminance because a fully
      // saturated sky ambient turns every shadowed grass blade cyan.
      float up = normal.y * 0.5 + 0.5;
      vec3 ambientColor = mix(uGroundBounce, uSkyColor, up) * uAmbientStrength;
      float ambientLuma = dot(ambientColor, vec3(0.2126, 0.7152, 0.0722));
      ambientColor = mix(ambientColor, vec3(ambientLuma), uAmbientDesaturation);
      // The baked sky-light level says how much of the sky this voxel can even
      // see, so a cave mouth is bright and a cave interior is not.
      ambientColor *= mix(0.24, 1.0, skyLightLevel);
      // Occlusion only gates the ambient term, which is what it physically
      // represents; the sun is already blocked by the shadow map.
      vec3 ambient = albedo * ambientColor * occlusion;
      // A floor of bounce light keeps deep shadow from crushing to pure black.
      ambient += albedo * uSkyHorizonColor * 0.05 * uDaylight * occlusion;

      vec3 specular = specularLobe(normal, viewDirection, uSunDirection, roughness)
        * uSunColor * uSunIntensity * sunVisible * shadow;
      // Foliage and grass get a little translucent glow when backlit, which is
      // what separates a tree from a dark blob against a bright sky.
      float transmission = 0.0;
      if (abs(vMaterial - ${leafMaterial}) < 0.25 || abs(vMaterial - ${grassMaterial}) < 0.25) {
        float backlit = max(dot(-viewDirection, uSunDirection), 0.0);
        transmission = pow(backlit, 3.0) * smoothstep(-0.1, 0.2, uSunDirection.y) * 0.5;
      }
      color = diffuse + ambient + specular + albedo * uSunColor * transmission * shadow;
      color += emissive;
    }

    // ---------------- atmosphere ----------------
    if (uVfxPass > 0.5) {
      // A particle is a camera-facing quad shaded from its own vertex colour,
      // not an atlas tile, so the whole sprite is procedural: a soft disc with a
      // hotter core that only an additive particle shows. The two kinds of
      // particle share one batch and one blend state because the output is
      // premultiplied - collapsing the destination weight to zero is what makes
      // an additive particle add.
      vec2 particleUv = vUV * 2.0 - 1.0;
      float radius = length(particleUv);
      float falloff = 1.0 - smoothstep(0.18, 1.0, radius);
      float core = 1.0 - smoothstep(0.0, 0.5, radius);
      float additive = vLight.y > 0.5 ? 1.0 : 0.0;
      float particleAlpha = clamp(vLight.x, 0.0, 1.0) * falloff * (1.0 - vFog * 0.8);
      vec3 particleColor = vColor * (1.0 + additive * (core * 1.9 - 0.25));
      gl_FragColor = vec4(particleColor * particleAlpha, particleAlpha * (1.0 - additive));
      return;
    }
    if (uShadowPass > 0.5) {
      vec2 shadowUv = fract(vUV) * 2.0 - 1.0;
      float softness = 1.0 - smoothstep(0.38, 1.0, length(shadowUv));
      gl_FragColor = vec4(vec3(0.012, 0.016, 0.014), 0.3 * softness * (1.0 - vFog * 0.65));
      return;
    }
    if (miningPass) {
      vec2 fractureUv = fract(vUV) * 4.0 + floor(uMiningProgress * 6.0);
      float fractureA = 1.0 - smoothstep(0.0, 0.045, abs(fractureUv.x + fractureUv.y) - 0.5);
      float fractureB = 1.0 - smoothstep(0.0, 0.045, abs(fractureUv.x - fractureUv.y) - 0.5);
      float fracture = max(fractureA, fractureB) * step(${MINING_FRACTURE_PROGRESS}, uMiningProgress);
      gl_FragColor = vec4(vec3(0.035, 0.04, 0.036), 0.16 + fracture * 0.74);
      return;
    }

    // Aerial perspective with sun-facing inscattering: distant terrain picks up
    // the sky it is seen against, and warms when you look toward the sun.
    float viewDotSun = max(dot(viewDirection, uSunDirection), 0.0);
    vec3 fogColor = mix(uSkyHorizonColor, uSkyColor, 0.5);
    fogColor += uSunColor * pow(viewDotSun, 6.0) * 0.28 * smoothstep(-0.1, 0.15, uSunDirection.y);
    color = mix(color, fogColor, vAerialFog);

    gl_FragColor = vec4(max(color, vec3(0.0)), alpha);
  }
`;
  return { vertexSource, fragmentSource };
}
