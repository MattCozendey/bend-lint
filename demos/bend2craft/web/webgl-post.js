// HDR post-processing chain for the WebGL 1 backend.
//
// The scene is drawn into an offscreen float target instead of the default
// framebuffer, which is what makes every effect below possible: bloom needs
// values above 1.0, god rays need the depth buffer as a texture, and the ACES
// tonemap needs to run after the whole frame is known rather than per surface.
//
// Chain: scene -> bright prefilter -> 6-step downsample -> 6-step upsample
//        -> god-ray occlusion + radial blur -> composite (bloom, god rays,
//        exposure, ACES, grade, vignette, aberration, grain, sharpen, FXAA).
//
// Every stage is optional and probed. Without `WEBGL_color_buffer_float` the
// target is RGBA8 and the tonemapped result is simply cruder; without
// `WEBGL_depth_texture` the god-ray stage is skipped entirely.

import {
  RENDER_TARGET_FILTER,
  bindRenderTarget,
  createRenderTarget,
  detectColorCapabilities,
  detectDepthSampling,
} from "./gl-render-target.js";

export const BLOOM_MIP_COUNT = 6;
export const GODRAY_SCALE = 0.5;

/** Fullscreen triangle: one primitive, no diagonal seam, no wasted fragments. */
const FULLSCREEN_VERTEX_SHADER = `
  precision highp float;
  attribute vec2 aPosition;
  varying vec2 vUv;
  void main() {
    vUv = aPosition * 0.5 + 0.5;
    gl_Position = vec4(aPosition, 0.0, 1.0);
  }
`;

const BRIGHT_PREFILTER_FRAGMENT_SHADER = `
  #ifdef GL_FRAGMENT_PRECISION_HIGH
  precision highp float;
  #else
  precision mediump float;
  #endif
  varying vec2 vUv;
  uniform sampler2D uSource;
  uniform vec2 uTexel;
  uniform float uThreshold;
  uniform float uSoftKnee;
  uniform float uClamp;

  vec3 fetch(vec2 uv) {
    return min(texture2D(uSource, uv).rgb, vec3(uClamp));
  }

  // Karis-style weighted average of a 13-tap box: weighting each group by 1/(1+luma)
  // stops a single fireflies pixel from dominating the whole mip.
  vec3 prefilter(vec2 uv) {
    vec3 a = fetch(uv + uTexel * vec2(-2.0,  2.0));
    vec3 b = fetch(uv + uTexel * vec2( 0.0,  2.0));
    vec3 c = fetch(uv + uTexel * vec2( 2.0,  2.0));
    vec3 d = fetch(uv + uTexel * vec2(-2.0,  0.0));
    vec3 e = fetch(uv);
    vec3 f = fetch(uv + uTexel * vec2( 2.0,  0.0));
    vec3 g = fetch(uv + uTexel * vec2(-2.0, -2.0));
    vec3 h = fetch(uv + uTexel * vec2( 0.0, -2.0));
    vec3 i = fetch(uv + uTexel * vec2( 2.0, -2.0));
    vec3 j = fetch(uv + uTexel * vec2(-1.0,  1.0));
    vec3 k = fetch(uv + uTexel * vec2( 1.0,  1.0));
    vec3 l = fetch(uv + uTexel * vec2(-1.0, -1.0));
    vec3 m = fetch(uv + uTexel * vec2( 1.0, -1.0));
    vec3 result = e * 0.125;
    result += (a + c + g + i) * 0.03125;
    result += (b + d + f + h) * 0.0625;
    result += (j + k + l + m) * 0.125;
    return result;
  }

  void main() {
    vec3 color = prefilter(vUv);
    float brightness = max(max(color.r, color.g), color.b);
    // Soft knee so the bloom ramps in over a band instead of switching on at a
    // hard luminance edge, which is what makes highlights pop without flicker.
    float knee = uThreshold * uSoftKnee;
    float soft = clamp(brightness - uThreshold + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 0.0001);
    float contribution = max(soft, brightness - uThreshold) / max(brightness, 0.0001);
    gl_FragColor = vec4(color * contribution, 1.0);
  }
`;

const DOWNSAMPLE_FRAGMENT_SHADER = `
  #ifdef GL_FRAGMENT_PRECISION_HIGH
  precision highp float;
  #else
  precision mediump float;
  #endif
  varying vec2 vUv;
  uniform sampler2D uSource;
  uniform vec2 uTexel;

  void main() {
    vec3 a = texture2D(uSource, vUv + uTexel * vec2(-2.0,  2.0)).rgb;
    vec3 b = texture2D(uSource, vUv + uTexel * vec2( 0.0,  2.0)).rgb;
    vec3 c = texture2D(uSource, vUv + uTexel * vec2( 2.0,  2.0)).rgb;
    vec3 d = texture2D(uSource, vUv + uTexel * vec2(-2.0,  0.0)).rgb;
    vec3 e = texture2D(uSource, vUv).rgb;
    vec3 f = texture2D(uSource, vUv + uTexel * vec2( 2.0,  0.0)).rgb;
    vec3 g = texture2D(uSource, vUv + uTexel * vec2(-2.0, -2.0)).rgb;
    vec3 h = texture2D(uSource, vUv + uTexel * vec2( 0.0, -2.0)).rgb;
    vec3 i = texture2D(uSource, vUv + uTexel * vec2( 2.0, -2.0)).rgb;
    vec3 j = texture2D(uSource, vUv + uTexel * vec2(-1.0,  1.0)).rgb;
    vec3 k = texture2D(uSource, vUv + uTexel * vec2( 1.0,  1.0)).rgb;
    vec3 l = texture2D(uSource, vUv + uTexel * vec2(-1.0, -1.0)).rgb;
    vec3 m = texture2D(uSource, vUv + uTexel * vec2( 1.0, -1.0)).rgb;
    vec3 result = e * 0.125;
    result += (a + c + g + i) * 0.03125;
    result += (b + d + f + h) * 0.0625;
    result += (j + k + l + m) * 0.125;
    gl_FragColor = vec4(result, 1.0);
  }
`;

const UPSAMPLE_FRAGMENT_SHADER = `
  #ifdef GL_FRAGMENT_PRECISION_HIGH
  precision highp float;
  #else
  precision mediump float;
  #endif
  varying vec2 vUv;
  uniform sampler2D uSource;
  uniform vec2 uTexel;
  uniform float uRadius;

  void main() {
    vec2 offset = uTexel * uRadius;
    vec3 result = texture2D(uSource, vUv + vec2(-offset.x,  offset.y)).rgb * 1.0;
    result += texture2D(uSource, vUv + vec2( 0.0,       offset.y)).rgb * 2.0;
    result += texture2D(uSource, vUv + vec2( offset.x,  offset.y)).rgb * 1.0;
    result += texture2D(uSource, vUv + vec2(-offset.x,  0.0)).rgb * 2.0;
    result += texture2D(uSource, vUv).rgb * 4.0;
    result += texture2D(uSource, vUv + vec2( offset.x,  0.0)).rgb * 2.0;
    result += texture2D(uSource, vUv + vec2(-offset.x, -offset.y)).rgb * 1.0;
    result += texture2D(uSource, vUv + vec2( 0.0,      -offset.y)).rgb * 2.0;
    result += texture2D(uSource, vUv + vec2( offset.x, -offset.y)).rgb * 1.0;
    gl_FragColor = vec4(result * (1.0 / 16.0), 1.0);
  }
`;

const GODRAY_MASK_FRAGMENT_SHADER = `
  #ifdef GL_FRAGMENT_PRECISION_HIGH
  precision highp float;
  #else
  precision mediump float;
  #endif
  varying vec2 vUv;
  uniform sampler2D uDepth;
  uniform float uNear;
  uniform float uFar;
  uniform float uSunVisible;
  uniform vec2 uSunUv;

  void main() {
    float depth = texture2D(uDepth, vUv).r;
    // The sky pass leaves depth at the far plane, so a depth of 1.0 is exactly
    // "no geometry here" and is the only thing allowed to emit a light shaft.
    float sky = step(0.9999, depth);
    // Fade the shaft out near the frame edge so the radial march cannot smear
    // a bright sun disc into the corners of the image.
    vec2 fromCenter = (vUv - uSunUv) * vec2(1.0, 0.62);
    float reach = 1.0 - smoothstep(0.25, 1.0, length(fromCenter));
    float source = sky * uSunVisible * reach;
    gl_FragColor = vec4(vec3(source), 1.0);
  }
`;

const GODRAY_BLUR_FRAGMENT_SHADER = `
  #ifdef GL_FRAGMENT_PRECISION_HIGH
  precision highp float;
  #else
  precision mediump float;
  #endif
  varying vec2 vUv;
  uniform sampler2D uSource;
  uniform vec2 uSunUv;
  uniform float uDensity;
  uniform float uDecay;
  uniform float uWeight;

  void main() {
    vec2 delta = (vUv - uSunUv) * uDensity / 24.0;
    vec2 uv = vUv;
    float illumination = 1.0;
    float accumulated = 0.0;
    // March from the pixel back toward the sun; each step contributes what the
    // mask holds there, attenuated by distance so the shaft has a soft head.
    for (int step = 0; step < 24; step++) {
      uv -= delta;
      vec2 clamped = clamp(uv, vec2(0.0), vec2(1.0));
      accumulated += texture2D(uSource, clamped).r * illumination * uWeight;
      illumination *= uDecay;
    }
    gl_FragColor = vec4(vec3(accumulated / 24.0), 1.0);
  }
`;

const COMPOSITE_FRAGMENT_SHADER = `
  #ifdef GL_FRAGMENT_PRECISION_HIGH
  precision highp float;
  #else
  precision mediump float;
  #endif
  varying vec2 vUv;
  uniform sampler2D uScene;
  uniform sampler2D uBloom;
  uniform sampler2D uGodray;
  uniform sampler2D uDepth;
  uniform vec2 uTexel;
  uniform float uExposure;
  uniform float uBloomStrength;
  uniform float uGodrayStrength;
  uniform vec3 uGodrayColor;
  uniform float uVignette;
  uniform float uAberration;
  uniform float uGrain;
  uniform float uSharpen;
  uniform float uTime;
  uniform float uSaturation;
  uniform float uContrast;
  uniform vec3 uLift;
  uniform vec3 uGain;
  uniform float uUnderwater;
  uniform vec3 uUnderwaterColor;
  uniform float uNear;
  uniform float uFar;
  uniform float uFxaa;
  uniform float uCaustics;

  // ACES filmic tonemap, Stephen Hill's fit of the full RRT+ODT. The simple
  // Narkowicz curve is noticeably weaker on saturated colour, which matters
  // here because grass and lava dominate the frame. The two 3x3 transforms are
  // written as explicit dot products: GLSL ES 1.00 drivers reject a const mat3
  // built from a constructor, and this form compiles everywhere.
  vec3 acesInputTransform(vec3 value) {
    return vec3(
      dot(vec3(0.59719, 0.35458, 0.04823), value),
      dot(vec3(0.07600, 0.90834, 0.01566), value),
      dot(vec3(0.02840, 0.13383, 0.83777), value)
    );
  }
  vec3 acesOutputTransform(vec3 value) {
    return vec3(
      dot(vec3( 1.60475, -0.53108, -0.07367), value),
      dot(vec3(-0.10208,  1.10813, -0.00605), value),
      dot(vec3(-0.00327, -0.07276,  1.07602), value)
    );
  }
  vec3 rrtOdtFit(vec3 value) {
    vec3 a = value * (value + 0.0245786) - 0.000090537;
    vec3 b = value * (0.983729 * value + 0.4329510) + 0.238081;
    return a / b;
  }
  vec3 acesFitted(vec3 color) {
    color = acesInputTransform(color);
    color = rrtOdtFit(color);
    return clamp(acesOutputTransform(color), 0.0, 1.0);
  }

  float luminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
  }

  float hash12(vec2 point) {
    vec3 p3 = fract(vec3(point.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
  }

  // FXAA over the tonemapped image. The scene target has no MSAA, so without
  // this every terrain edge and tree silhouette crawls.
  vec3 fxaa(vec2 uv) {
    vec3 center = texture2D(uScene, uv).rgb;
    vec3 nw = texture2D(uScene, uv + vec2(-1.0, -1.0) * uTexel).rgb;
    vec3 ne = texture2D(uScene, uv + vec2( 1.0, -1.0) * uTexel).rgb;
    vec3 sw = texture2D(uScene, uv + vec2(-1.0,  1.0) * uTexel).rgb;
    vec3 se = texture2D(uScene, uv + vec2( 1.0,  1.0) * uTexel).rgb;
    vec4 luma = vec4(luminance(nw), luminance(ne), luminance(sw), luminance(se));
    float lumaMin = min(luma.x, min(min(luma.y, luma.z), luma.w));
    float lumaMax = max(luma.x, max(max(luma.y, luma.z), luma.w));
    vec2 dir = vec2(
      -((luma.x + luma.y) - (luma.z + luma.w)),
      ((luma.x + luma.z) - (luma.y + luma.w))
    );
    float dirReduce = max((luma.x + luma.y + luma.z + luma.w) * 0.03125, 0.0078125);
    float reciprocal = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = clamp(dir * reciprocal, vec2(-8.0), vec2(8.0)) * uTexel;
    vec3 a = 0.5 * (
      texture2D(uScene, uv + dir * (1.0 / 3.0 - 0.5)).rgb +
      texture2D(uScene, uv + dir * (2.0 / 3.0 - 0.5)).rgb);
    vec3 b = a * 0.5 + 0.25 * (
      texture2D(uScene, uv - dir * 0.5).rgb +
      texture2D(uScene, uv + dir * 0.5).rgb);
    float lumaB = luminance(b);
    return (lumaB < lumaMin || lumaB > lumaMax) ? a : b;
  }

  void main() {
    vec2 uv = vUv;
    vec2 fromCenter = uv - 0.5;
    float radiusSquared = dot(fromCenter, fromCenter);

    // Lateral chromatic aberration: the channels are sampled at slightly
    // different radial offsets, which is what a real lens does toward the edge.
    vec3 scene;
    if (uAberration > 0.0) {
      float amount = uAberration * radiusSquared;
      scene.r = texture2D(uScene, uv - fromCenter * amount).r;
      scene.g = texture2D(uScene, uv).g;
      scene.b = texture2D(uScene, uv + fromCenter * amount).b;
    } else {
      scene = texture2D(uScene, uv).rgb;
    }

    // Underwater: absorb red first, then green, with a slow caustic ripple that
    // is strongest near the top of the frame.
    if (uUnderwater > 0.0) {
      float depth = clamp(texture2D(uDepth, uv).r, 0.0, 1.0);
      float ripple = sin(uv.x * 42.0 + uTime * 1.7) * sin(uv.y * 31.0 - uTime * 1.1);
      float caustic = smoothstep(0.55, 1.0, ripple) * uCaustics;
      scene = mix(scene * uUnderwaterColor, scene * uUnderwaterColor * 0.5, depth * 0.5);
      scene += vec3(0.05, 0.11, 0.12) * caustic * (1.0 - depth);
    }

    vec3 color = scene;
    color += texture2D(uBloom, uv).rgb * uBloomStrength;
    color += texture2D(uGodray, uv).rgb * uGodrayStrength * uGodrayColor;
    color *= uExposure;

    // Unsharp mask against a cross blur of the scene: brings back the local
    // contrast the tonemap compressed, at a fraction of a full-res pass.
    if (uSharpen > 0.0) {
      vec3 blur = (
        texture2D(uScene, uv + vec2(uTexel.x, 0.0)).rgb +
        texture2D(uScene, uv - vec2(uTexel.x, 0.0)).rgb +
        texture2D(uScene, uv + vec2(0.0, uTexel.y)).rgb +
        texture2D(uScene, uv - vec2(0.0, uTexel.y)).rgb) * 0.25;
      color += (scene - blur) * uSharpen;
    }

    color = acesFitted(max(color, vec3(0.0)));

    // Grade: lift/gain around a saturation and contrast pivot. Applied after the
    // tonemap so it shapes the display-referred image, not the scene radiance.
    color = color * uGain + uLift;
    float luma = luminance(color);
    color = mix(vec3(luma), color, uSaturation);
    color = clamp((color - 0.5) * uContrast + 0.5, 0.0, 1.0);

    float vignette = 1.0 - uVignette * smoothstep(0.18, 0.78, radiusSquared);
    color *= vignette;

    if (uGrain > 0.0) {
      float noise = hash12(gl_FragCoord.xy + vec2(uTime * 37.0, uTime * 71.0)) - 0.5;
      // Weight grain toward the shadows, where real sensor noise lives and
      // where a flat mid-grey band would otherwise be most visible.
      color += noise * uGrain * (1.0 - smoothstep(0.0, 0.7, luminance(color)));
    }

    if (uFxaa > 0.0) color = mix(color, fxaa(uv), uFxaa);

    gl_FragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
  }
`;

function compile(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    const info = gl.getShaderInfoLog(shader);
    gl.deleteShader(shader);
    throw new Error(`Post shader compilation failed: ${info}`);
  }
  return shader;
}

function createProgram(gl, vertexSource, fragmentSource) {
  const vertex = compile(gl, gl.VERTEX_SHADER, vertexSource);
  const fragment = compile(gl, gl.FRAGMENT_SHADER, fragmentSource);
  const program = gl.createProgram();
  gl.attachShader(program, vertex);
  gl.attachShader(program, fragment);
  gl.linkProgram(program);
  gl.deleteShader(vertex);
  gl.deleteShader(fragment);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    const info = gl.getProgramInfoLog(program);
    gl.deleteProgram(program);
    throw new Error(`Post program link failed: ${info}`);
  }
  return program;
}

function uniformMap(gl, program, names) {
  const uniforms = {};
  for (const name of names) uniforms[name] = gl.getUniformLocation(program, name);
  return uniforms;
}

function createFullscreenQuad(gl) {
  const buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(
    gl.ARRAY_BUFFER,
    new Float32Array([-1, -1, 3, -1, -1, 3]),
    gl.STATIC_DRAW,
  );
  return {
    buffer,
    positionLocation: 0,
    draw() {
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
      gl.enableVertexAttribArray(0);
      gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      gl.disableVertexAttribArray(0);
    },
    dispose() {
      gl.deleteBuffer(buffer);
    },
  };
}

/**
 * Build the whole chain. `quality` scales the resolution of the two heaviest
 * stages so a weak GPU keeps its frame rate; `enabled` is false when the context
 * cannot give the pipeline an offscreen colour target at all, in which case the
 * caller draws straight to the canvas exactly as it did before.
 */
export function createPostPipeline(gl, {
  quality = 1,
  anisotropy = null,
  anisotropyExtension = null,
} = {}) {
  const capabilities = detectColorCapabilities(gl);
  const depthSampling = detectDepthSampling(gl);
  const quad = createFullscreenQuad(gl);
  const mipCount = Math.max(2, BLOOM_MIP_COUNT);
  const bloomScale = quality >= 1 ? 1 : 2;
  const godrayEnabled = depthSampling.supported;

  let scene = null;
  let outputWidth = 1;
  let outputHeight = 1;
  let bloomMips = [];
  let godrayMask = null;
  let godrayBlur = null;

  const programs = {};
  try {
    programs.prefilter = createProgram(gl, FULLSCREEN_VERTEX_SHADER, BRIGHT_PREFILTER_FRAGMENT_SHADER);
    programs.downsample = createProgram(gl, FULLSCREEN_VERTEX_SHADER, DOWNSAMPLE_FRAGMENT_SHADER);
    programs.upsample = createProgram(gl, FULLSCREEN_VERTEX_SHADER, UPSAMPLE_FRAGMENT_SHADER);
    programs.composite = createProgram(gl, FULLSCREEN_VERTEX_SHADER, COMPOSITE_FRAGMENT_SHADER);
    if (godrayEnabled) {
      programs.godrayMask = createProgram(gl, FULLSCREEN_VERTEX_SHADER, GODRAY_MASK_FRAGMENT_SHADER);
      programs.godrayBlur = createProgram(gl, FULLSCREEN_VERTEX_SHADER, GODRAY_BLUR_FRAGMENT_SHADER);
    }
  } catch (error) {
    for (const program of Object.values(programs)) gl.deleteProgram(program);
    quad.dispose();
    throw error;
  }

  const uniforms = {
    prefilter: uniformMap(gl, programs.prefilter, ["uSource", "uTexel", "uThreshold", "uSoftKnee", "uClamp"]),
    downsample: uniformMap(gl, programs.downsample, ["uSource", "uTexel"]),
    upsample: uniformMap(gl, programs.upsample, ["uSource", "uTexel", "uRadius"]),
    godrayMask: godrayEnabled
      ? uniformMap(gl, programs.godrayMask, ["uDepth", "uNear", "uFar", "uSunVisible", "uSunUv"])
      : null,
    godrayBlur: godrayEnabled
      ? uniformMap(gl, programs.godrayBlur, ["uSource", "uSunUv", "uDensity", "uDecay", "uWeight"])
      : null,
    composite: uniformMap(gl, programs.composite, [
      "uScene", "uBloom", "uGodray", "uDepth", "uTexel", "uExposure", "uBloomStrength",
      "uGodrayStrength", "uGodrayColor", "uVignette", "uAberration", "uGrain", "uSharpen",
      "uTime", "uSaturation", "uContrast", "uLift", "uGain", "uUnderwater",
      "uUnderwaterColor", "uNear", "uFar", "uFxaa", "uCaustics",
    ]),
  };

  function allocate(width, height) {
    for (const mip of bloomMips) mip.dispose();
    for (const target of [godrayMask, godrayBlur]) target?.dispose();
    scene?.dispose();
    bloomMips = [];
    godrayMask = null;
    godrayBlur = null;
    scene = createRenderTarget(gl, {
      width,
      height,
      capabilities,
      depth: depthSampling.supported ? "texture" : "renderbuffer",
      filter: RENDER_TARGET_FILTER.LINEAR,
    });
    let mipWidth = Math.max(1, Math.floor((width * bloomScale) / 2));
    let mipHeight = Math.max(1, Math.floor((height * bloomScale) / 2));
    for (let level = 0; level < mipCount; level += 1) {
      bloomMips.push(createRenderTarget(gl, {
        width: mipWidth,
        height: mipHeight,
        capabilities,
        depth: "none",
        filter: RENDER_TARGET_FILTER.LINEAR,
      }));
      mipWidth = Math.max(1, Math.floor(mipWidth / 2));
      mipHeight = Math.max(1, Math.floor(mipHeight / 2));
    }
    if (godrayEnabled) {
      const gw = Math.max(1, Math.floor(width * GODRAY_SCALE));
      const gh = Math.max(1, Math.floor(height * GODRAY_SCALE));
      godrayMask = createRenderTarget(gl, {
        width: gw,
        height: gh,
        capabilities,
        depth: "none",
        filter: RENDER_TARGET_FILTER.LINEAR,
      });
      godrayBlur = createRenderTarget(gl, {
        width: gw,
        height: gh,
        capabilities,
        depth: "none",
        filter: RENDER_TARGET_FILTER.LINEAR,
      });
    }
  }

  function blit(source, target, program, programUniforms, setup) {
    bindRenderTarget(gl, target);
    gl.useProgram(program);
    gl.disable(gl.DEPTH_TEST);
    gl.depthMask(false);
    gl.disable(gl.BLEND);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, source);
    setup(programUniforms);
    quad.draw();
  }

  return {
    capabilities,
    depthSampling,
    quality,
    mipCount,
    godrayEnabled,
    /** True when the caller should render the scene into `scene` rather than the canvas. */
    enabled: true,
    get scene() {
      return scene;
    },
    get width() {
      return scene?.width ?? 0;
    },
    get height() {
      return scene?.height ?? 0;
    },
    /**
     * Size the chain. `scale` below 1 renders the scene into a smaller target and
     * lets the composite upscale to the canvas: the one lever that scales the
     * whole frame rather than one effect, and therefore the first thing to reach
     * for when the frame budget is blown.
     */
    resize(width, height, scale = 1) {
      const w = Math.max(1, Math.floor(width * Math.max(0.25, Math.min(1, scale))));
      const h = Math.max(1, Math.floor(height * Math.max(0.25, Math.min(1, scale))));
      outputWidth = Math.max(1, Math.floor(width));
      outputHeight = Math.max(1, Math.floor(height));
      if (scene !== null && scene.width === w && scene.height === h) return false;
      allocate(w, h);
      return true;
    },
    beginScene() {
      bindRenderTarget(gl, scene);
      gl.enable(gl.DEPTH_TEST);
      gl.depthMask(true);
      gl.depthFunc(gl.LESS);
      gl.disable(gl.BLEND);
      gl.disable(gl.CULL_FACE);
    },
    /**
     * Run bloom, god rays and the composite onto the default framebuffer.
     * `params` carries the per-frame look; every field has a defined default so
     * a caller can pass a partial object.
     */
    composite(params = {}) {
      const {
        bloomThreshold = 1.05,
        bloomSoftKnee = 0.6,
        bloomClamp = 12,
        bloomStrength = 0.055,
        bloomRadius = 1.0,
        godrayStrength = 0.0,
        godrayColor = [1, 0.86, 0.62],
        godrayDensity = 0.72,
        godrayDecay = 0.94,
        godrayWeight = 1.0,
        sunUv = [0.5, 0.5],
        sunVisible = 0,
        exposure = 1,
        vignette = 0.34,
        aberration = 0.0016,
        grain = 0.022,
        sharpen = 0.18,
        saturation = 1.06,
        contrast = 1.04,
        lift = [0, 0, 0],
        gain = [1, 1, 1],
        fxaa = 0.85,
        underwater = 0,
        underwaterColor = [0.24, 0.52, 0.62],
        caustics = 0.6,
        time = 0,
        near = 0.05,
        far = 1000,
      } = params;

      // --- bloom: prefilter into mip 0, then walk down and back up ---
      // Skipped entirely at zero strength. The chain is six downsamples, six
      // upsamples and an additive blend over the whole frame, so a player who
      // turns bloom off should stop paying for it rather than multiply the result
      // by zero. The composite below is given an inert sampler and a zero
      // strength in that case, the same way the god-ray stage is.
      const bloomActive = bloomStrength > 0;
      if (bloomActive) {
        blit(scene.texture, bloomMips[0], programs.prefilter, uniforms.prefilter, (u) => {
          gl.uniform1i(u.uSource, 0);
          gl.uniform2f(u.uTexel, 1 / scene.width, 1 / scene.height);
          gl.uniform1f(u.uThreshold, bloomThreshold);
          gl.uniform1f(u.uSoftKnee, Math.max(bloomSoftKnee, 0.0001));
          gl.uniform1f(u.uClamp, bloomClamp);
        });
        for (let level = 1; level < bloomMips.length; level += 1) {
          const source = bloomMips[level - 1];
          blit(source.texture, bloomMips[level], programs.downsample, uniforms.downsample, (u) => {
            gl.uniform1i(u.uSource, 0);
            gl.uniform2f(u.uTexel, 1 / source.width, 1 / source.height);
          });
        }
        gl.enable(gl.BLEND);
        gl.blendFunc(gl.ONE, gl.ONE);
        for (let level = bloomMips.length - 1; level > 0; level -= 1) {
          const source = bloomMips[level];
          bindRenderTarget(gl, bloomMips[level - 1]);
          gl.useProgram(programs.upsample);
          gl.activeTexture(gl.TEXTURE0);
          gl.bindTexture(gl.TEXTURE_2D, source.texture);
          gl.uniform1i(uniforms.upsample.uSource, 0);
          gl.uniform2f(uniforms.upsample.uTexel, 1 / source.width, 1 / source.height);
          gl.uniform1f(uniforms.upsample.uRadius, bloomRadius);
          quad.draw();
        }
        gl.disable(gl.BLEND);
      }

      // --- god rays: occlusion mask from depth, then a radial march ---
      const godrayActive = godrayEnabled && godrayStrength > 0 && sunVisible > 0.001;
      if (godrayActive) {
        bindRenderTarget(gl, godrayMask);
        gl.useProgram(programs.godrayMask);
        gl.disable(gl.DEPTH_TEST);
        gl.depthMask(false);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, scene.depthTexture);
        gl.uniform1i(uniforms.godrayMask.uDepth, 0);
        gl.uniform1f(uniforms.godrayMask.uNear, near);
        gl.uniform1f(uniforms.godrayMask.uFar, far);
        gl.uniform1f(uniforms.godrayMask.uSunVisible, Math.min(1, sunVisible));
        gl.uniform2f(uniforms.godrayMask.uSunUv, sunUv[0], sunUv[1]);
        quad.draw();

        blit(godrayMask.texture, godrayBlur, programs.godrayBlur, uniforms.godrayBlur, (u) => {
          gl.uniform1i(u.uSource, 0);
          gl.uniform2f(u.uSunUv, sunUv[0], sunUv[1]);
          gl.uniform1f(u.uDensity, godrayDensity);
          gl.uniform1f(u.uDecay, godrayDecay);
          gl.uniform1f(u.uWeight, godrayWeight);
        });
      }

      // --- composite onto the default framebuffer ---
      // When the god-ray stage did not run, its sampler is pointed at something
      // inert and its strength forced to zero; multiplying a real image by a
      // zero strength is cheaper than branching again here. The same goes for a
      // bloom that was skipped.
      const bloomTexture = bloomActive ? bloomMips[0].texture : scene.texture;
      const effectiveBloomStrength = bloomActive ? bloomStrength : 0;
      const effectiveGodrayStrength = godrayActive ? godrayStrength : 0;
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      // Blit across the whole canvas, not the scaled scene target: the
      // fullscreen triangle upsamples the scene into the output resolution.
      gl.viewport(0, 0, outputWidth, outputHeight);
      gl.useProgram(programs.composite);
      gl.disable(gl.DEPTH_TEST);
      gl.depthMask(false);
      gl.disable(gl.BLEND);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, scene.texture);
      gl.uniform1i(uniforms.composite.uScene, 0);
      gl.activeTexture(gl.TEXTURE1);
      gl.bindTexture(gl.TEXTURE_2D, bloomTexture);
      gl.uniform1i(uniforms.composite.uBloom, 1);
      gl.activeTexture(gl.TEXTURE2);
      gl.bindTexture(gl.TEXTURE_2D, godrayActive ? godrayBlur.texture : scene.texture);
      gl.uniform1i(uniforms.composite.uGodray, 2);
      gl.activeTexture(gl.TEXTURE3);
      gl.bindTexture(gl.TEXTURE_2D, scene.depthTexture ?? scene.texture);
      gl.uniform1i(uniforms.composite.uDepth, 3);
      gl.uniform2f(uniforms.composite.uTexel, 1 / scene.width, 1 / scene.height);
      gl.uniform1f(uniforms.composite.uExposure, exposure);
      gl.uniform1f(uniforms.composite.uBloomStrength, effectiveBloomStrength);
      gl.uniform1f(uniforms.composite.uGodrayStrength, effectiveGodrayStrength);
      gl.uniform3f(uniforms.composite.uGodrayColor, godrayColor[0], godrayColor[1], godrayColor[2]);
      gl.uniform1f(uniforms.composite.uVignette, vignette);
      gl.uniform1f(uniforms.composite.uAberration, aberration);
      gl.uniform1f(uniforms.composite.uGrain, grain);
      gl.uniform1f(uniforms.composite.uSharpen, sharpen);
      gl.uniform1f(uniforms.composite.uTime, time);
      gl.uniform1f(uniforms.composite.uSaturation, saturation);
      gl.uniform1f(uniforms.composite.uContrast, contrast);
      gl.uniform3f(uniforms.composite.uLift, lift[0], lift[1], lift[2]);
      gl.uniform3f(uniforms.composite.uGain, gain[0], gain[1], gain[2]);
      gl.uniform1f(uniforms.composite.uUnderwater, underwater);
      gl.uniform3f(
        uniforms.composite.uUnderwaterColor,
        underwaterColor[0], underwaterColor[1], underwaterColor[2],
      );
      gl.uniform1f(uniforms.composite.uNear, near);
      gl.uniform1f(uniforms.composite.uFar, far);
      gl.uniform1f(uniforms.composite.uFxaa, fxaa);
      gl.uniform1f(uniforms.composite.uCaustics, caustics);
      quad.draw();
      gl.depthMask(true);
    },
    dispose() {
      scene?.dispose();
      for (const mip of bloomMips) mip.dispose();
      godrayMask?.dispose();
      godrayBlur?.dispose();
      for (const program of Object.values(programs)) gl.deleteProgram(program);
      quad.dispose();
    },
  };
}
