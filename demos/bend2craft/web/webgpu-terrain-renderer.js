import { CLOUD_TEXTURE_SIZE, createCloudTextureData } from "./cloud-texture.js";
import {
  TERRAIN_VERTEX_LAYOUT,
  TERRAIN_VERTEX_STRIDE_BYTES,
  classifyChunkUpdate,
  packTerrainLayer,
  packedLayerBounds,
} from "./webgpu-chunk-buffers.js";
import {
  ATLAS_MIPMAP_SAFE_LEVELS,
  ATLAS_TILE_GUTTER,
  ATLAS_TILE_SIZE,
  ATLAS_TILE_STRIDE,
  ATLAS_TEXTURES,
  ATLAS_WIDTH,
  ATLAS_COLUMNS,
  atlasBoxDownsample,
  atlasCellOrigin,
  atlasMipLevelGeometry,
  foreignTileContamination,
  maxChannelDelta,
} from "./texture-atlas.js";
import { spreadProbeTiles } from "./atlas-probe.js";
import { withTimeout } from "./webgpu-capabilities.js";
import {
  COPY_SRC,
  FRAME_READBACK_BYTES_PER_PIXEL,
  MAP_READ,
  bytesPerRow,
  describeFrameReadbackSupport,
  readbackRowTop,
  readbackTargetRow,
  swapRedBlue,
} from "./webgpu-frame-readback.js";
import {
  createSubmitMetrics,
  emptyBounds,
  extractClipPlanes,
  mergeBounds,
  selectVisibleChunks,
} from "./chunk-frustum.js";
import {
  SURFACE_MATERIAL_FIRE,
  SURFACE_MATERIAL_LAVA,
  SURFACE_MATERIAL_WATER,
} from "./surface-materials.js";
import {
  AERIAL_FOG_HEIGHT_FALLOFF,
  AERIAL_FOG_MIN_DENSITY,
  AMBIENT_DESATURATION,
  AMBIENT_STRENGTH,
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
  MATERIAL_ROUGHNESS_MAX,
  MATERIAL_ROUGHNESS_MIN,
  MATERIAL_SPECULAR_POWER,
  MATERIAL_SPECULAR_STRENGTH,
  SUN_INTENSITY,
  TERRAIN_FOG_START,
  TERRAIN_MATERIAL_VARIATION_MAX,
  TERRAIN_MATERIAL_VARIATION_MIN,
  TERRAIN_VARIATION_SEED,
  TERRAIN_VARIATION_X,
  TERRAIN_VARIATION_Z,
  WATER_CAUSTIC_STRENGTH,
  WATER_CAUSTIC_THRESHOLD_END,
  WATER_CAUSTIC_THRESHOLD_START,
  WATER_DARK_R,
  WATER_DARK_G,
  WATER_DARK_B,
  WATER_DEPTH_FLOOR_R,
  WATER_DEPTH_TINT_STRENGTH,  WATER_LIGHT_R,
  WATER_LIGHT_G,
  WATER_LIGHT_B,
  WATER_FOAM_THRESHOLD,
  WATER_FRESNEL_POWER,
  WATER_NORMAL_STRENGTH,
  WATER_FOAM_STRENGTH,
  WATER_SPECULAR_POWER,
} from "./terrain-presentation.js";

// `mapAsync` is the one WebGPU call that can stay pending indefinitely when the
// device stops making progress, and a pending promise is not an error: to the
// caller it is indistinguishable from a slow read. Racing it against a timeout
// turns a permanent stall into a reported failure, which is the difference
// between a frozen window and a message the player can act on.
const GPU_READBACK_TIMEOUT_MS = 4000;

async function mapBufferWithin(buffer, mode) {
  await withTimeout(
    buffer.mapAsync(mode),
    GPU_READBACK_TIMEOUT_MS,
    "WebGPU buffer readback timed out; the device stopped completing work.",
  );
}

const BUFFER_USAGE = {
  COPY_DST: 0x0008,
  VERTEX: 0x0020,
  UNIFORM: 0x0040,
};
const TEXTURE_USAGE = {
  COPY_DST: 0x0002,
  TEXTURE_BINDING: 0x0004,
  RENDER_ATTACHMENT: 0x0010,
};
const SHADER_STAGE = { VERTEX: 0x1, FRAGMENT: 0x2 };
// The per-frame uniform, declared once and prepended to both pipelines. Terrain
// and sky bind the same buffer at the same binding, so a field added to one copy
// and not the other would leave the sky pass reading a different layout than the
// terrain pass, with no error on either side. FRAME_UNIFORM_BYTES is asserted
// against this struct in tests/webgpu-terrain-presentation.test.mjs.
export const WGSL_FRAME_UNIFORMS = `
struct Frame {
  viewProjection: mat4x4<f32>,
  camera: vec4<f32>,
  skyColor: vec4<f32>,
  params: vec4<f32>,
  fog: vec4<f32>,
  skyHorizon: vec4<f32>,
  cameraRight: vec4<f32>,
  cameraUp: vec4<f32>,
  cameraForward: vec4<f32>,
  sunDirection: vec4<f32>,
  sunColor: vec4<f32>,
};

@group(0) @binding(0) var<uniform> frame: Frame;
`;
// One mat4x4 (64 bytes) plus ten vec4<f32> (16 bytes each).
export const FRAME_UNIFORM_BYTES = 224;
// An rgba8 round trip through a box filter rounds by at most one step, so a
// correct chain lands inside this; anything larger is a real generator bug.
const MIP_CHAIN_TOLERANCE = 2;

export const WEBGPU_TERRAIN_SHADER = `${WGSL_FRAME_UNIFORMS}
@group(0) @binding(1) var atlasSampler: sampler;
@group(0) @binding(2) var atlasTexture: texture_2d<f32>;
@group(0) @binding(3) var cloudSampler: sampler;
@group(0) @binding(4) var cloudTexture: texture_2d<f32>;

// Mirrors the WebGL attribute set: colour is a per-face grade only, and the
// lighting inputs (occlusion, block light, normal) arrive separately so the
// fragment stage owns the lighting on both backends.
struct VertexInput {
  @location(0) position: vec3<f32>,
  @location(1) color: vec3<f32>,
  @location(2) light: vec2<f32>,
  @location(3) normal: vec3<f32>,
  @location(4) uv: vec2<f32>,
  @location(5) material: f32,
  @location(6) tileRect: vec4<f32>,
};

struct VertexOutput {
  @builtin(position) position: vec4<f32>,
  @location(0) color: vec3<f32>,
  @location(1) light: vec2<f32>,
  @location(2) normal: vec3<f32>,
  @location(3) uv: vec2<f32>,
  @location(4) worldPosition: vec3<f32>,
  @location(5) tileRect: vec4<f32>,
  @location(6) fog: f32,
  @location(7) material: f32,
  @location(8) viewDirection: vec3<f32>,
  @location(9) aerialFog: f32,
};

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
  var position = input.position;
  let surfacePass = frame.params.z;
  if (surfacePass > 0.5 && surfacePass < 1.5 && input.material >= ${SURFACE_MATERIAL_WATER} && input.material < ${SURFACE_MATERIAL_LAVA}) {
    position.y += 0.028 * sin(frame.params.y * 1.6 + position.x * 0.38 + position.z * 0.27)
      + 0.012 * sin(frame.params.y * 2.7 - position.z * 0.19 + position.x * 0.11);
  }
  if (surfacePass < 0.5 && input.material >= ${SURFACE_MATERIAL_FIRE} && input.material < ${SURFACE_MATERIAL_FIRE + 1}) {
    position.x += 0.025 * sin(frame.params.y * 1.2 + position.x * 0.4 + position.z * 0.27);
    position.z += 0.018 * cos(frame.params.y * 1.05 + position.z * 0.32 + position.x * 0.18);
  }
  var output: VertexOutput;
  output.position = frame.viewProjection * vec4<f32>(position, 1.0);
  output.color = input.color;
  output.light = input.light;
  output.normal = input.normal;
  output.uv = input.uv;
  output.worldPosition = position;
  output.tileRect = input.tileRect;
  output.fog = clamp((distance(position, frame.camera.xyz) - ${TERRAIN_FOG_START}) / frame.fog.x, 0.0, 1.0);
  output.material = input.material;
  output.viewDirection = position - frame.camera.xyz;
  let heightAttenuation = exp(-max(position.y - frame.camera.y, 0.0) * ${AERIAL_FOG_HEIGHT_FALLOFF.toFixed(3)});
  output.aerialFog = clamp(output.fog * (${AERIAL_FOG_MIN_DENSITY.toFixed(2)} + ${(1 - AERIAL_FOG_MIN_DENSITY).toFixed(2)} * heightAttenuation), 0.0, 1.0);
  return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
  let surfacePass = frame.params.z;
  let miningPass = input.tileRect.x < -0.5;
  let localUv = fract(input.uv);
  let atlasUv = mix(input.tileRect.xy, input.tileRect.zw, localUv);
  let textureColor = textureSample(atlasTexture, atlasSampler, atlasUv);
  var color = input.color * frame.params.x;
  var alpha = 1.0;
  if (surfacePass > 3.5) {
    // Particle mode 4. Mirrors the WebGL branch exactly: a procedural soft disc
    // with a hotter core, shaded from the vertex colour, premultiplied so
    // additive sparks and covering smoke share one batch and one blend state.
    let particleUv = input.uv * 2.0 - vec2<f32>(1.0, 1.0);
    let radius = length(particleUv);
    let falloff = 1.0 - smoothstep(0.18, 1.0, radius);
    let core = 1.0 - smoothstep(0.0, 0.5, radius);
    let additive = select(0.0, 1.0, input.light.y > 0.5);
    let particleAlpha = clamp(input.light.x, 0.0, 1.0) * falloff * (1.0 - input.fog * 0.8);
    let particleColor = input.color * (1.0 + additive * (core * 1.9 - 0.25));
    return vec4<f32>(particleColor * particleAlpha, particleAlpha * (1.0 - additive));
  }
  if (miningPass) {
    let fractureUv = input.uv * 4.0 + floor(frame.params.w * 6.0);
    let fractureA = 1.0 - smoothstep(0.0, 0.045, abs(fractureUv.x + fractureUv.y) - 0.5);
    let fractureB = 1.0 - smoothstep(0.0, 0.045, abs(fractureUv.x - fractureUv.y) - 0.5);
    let fracture = max(fractureA, fractureB) * step(${MINING_FRACTURE_PROGRESS}, frame.params.w);
    color = vec3<f32>(0.04, 0.045, 0.04);
    alpha = 0.14 + fracture * 0.72;
  } else if (surfacePass > 1.5 && surfacePass < 2.5) {
    color = vec3<f32>(0.015, 0.02, 0.018);
    let shadowUv = input.uv * 2.0 - 1.0;
    alpha = 0.28 * (1.0 - smoothstep(0.38, 1.0, length(shadowUv))) * (1.0 - input.fog * 0.65);
  } else {
    let materialVariation = fract(sin(dot(floor(input.worldPosition.xz), vec2<f32>(${TERRAIN_VARIATION_X}, ${TERRAIN_VARIATION_Z}))) * ${TERRAIN_VARIATION_SEED});
    // Stage 1 - albedo: the material sample plus its authored variation, with
    // no lighting folded in yet.
    let surfaceRoughness = ${MATERIAL_ROUGHNESS_MIN} + (${MATERIAL_ROUGHNESS_MAX} - ${MATERIAL_ROUGHNESS_MIN}) * materialVariation;
    let detailAmplitude = ${MATERIAL_DETAIL_STRENGTH} * (0.5 + 0.5 * surfaceRoughness);
    let detail = 1.0 + detailAmplitude * (clamp(textureColor.r, 0.0, 1.0) * 2.0 - 1.0);
    let albedo = input.color * textureColor.rgb * mix(${TERRAIN_MATERIAL_VARIATION_MIN}, ${TERRAIN_MATERIAL_VARIATION_MAX}, materialVariation) * detail;
    // Stage 2 - lighting: a real directional sun plus a hemispheric sky
    // ambient, so a face pointing at the sun is brighter than one pointing
    // away. Occlusion gates the ambient only, which is what it represents.
    let normal = normalize(input.normal);
    let occlusion = clamp(input.light.x, 0.0, 1.0);
    let skyLightLevel = clamp(input.light.y, 0.0, 1.0);
    let sunVisibility = smoothstep(-0.16, 0.14, frame.sunDirection.y);
    let ndotl = max(dot(normal, frame.sunDirection.xyz), 0.0);
    let wrapped = max((ndotl + 0.18) / 1.18, 0.0);
    let sunTerm = frame.sunColor.rgb * ${SUN_INTENSITY} * sunVisibility * mix(ndotl, wrapped, 0.35);
    // Hemispheric ambient: sky above, bounced ground below, pulled part way to
    // neutral so a shadowed surface does not turn cyan.
    let up = normal.y * 0.5 + 0.5;
    var ambient = mix(frame.skyHorizon.rgb, frame.skyColor.rgb, up) * ${AMBIENT_STRENGTH};
    let ambientLuma = dot(ambient, vec3<f32>(0.2126, 0.7152, 0.0722));
    ambient = mix(ambient, vec3<f32>(ambientLuma), ${AMBIENT_DESATURATION});
    ambient *= mix(0.24, 1.0, skyLightLevel) * occlusion;
    let litColor = albedo * (sunTerm + ambient);
    // Stage 3 - material lobe: a roughness-controlled specular highlight.
    let materialView = normalize(-input.viewDirection);
    let materialFacing = max(dot(vec3<f32>(0.0, 1.0, 0.0), materialView), 0.0);
    let materialSpecular = ${MATERIAL_SPECULAR_STRENGTH.toFixed(3)} * pow(materialFacing, ${MATERIAL_SPECULAR_POWER.toFixed(1)}) * (1.0 - surfaceRoughness);
    // These assign the fragment-scope color and alpha. Re-declaring them here
    // would shadow the outer pair, and the final return would then ship the
    // unshaded seed value instead of the material result.
    color = litColor + frame.sunColor.rgb * materialSpecular * sunVisibility;
    alpha = textureColor.a;
    if (surfacePass > 0.5 && surfacePass < 1.5 && input.material >= ${SURFACE_MATERIAL_WATER} && input.material < ${SURFACE_MATERIAL_LAVA}) {
      let phaseA = frame.params.y * 1.8 + input.worldPosition.x * 0.42 + input.worldPosition.z * 0.28;
      let phaseB = frame.params.y * 2.7 - input.worldPosition.z * 0.19 + input.worldPosition.x * 0.11;
      let phaseC = frame.params.y * 1.15 + input.worldPosition.x * 0.31 - input.worldPosition.z * 0.23;
      let rippleA = 0.5 + 0.5 * sin(phaseA);
      let rippleB = 0.5 + 0.5 * sin(phaseB);
      let rippleC = 0.5 + 0.5 * sin(phaseC);
      let shimmer = rippleA * 0.5 + rippleB * 0.3 + rippleC * 0.2;
      let waterSlope = vec2<f32>(
        cos(phaseA) * 0.42 * 0.028 + cos(phaseB) * 0.11 * 0.012 + cos(phaseC) * 0.07,
        cos(phaseA) * 0.28 * 0.028 - cos(phaseB) * 0.19 * 0.012 - cos(phaseC) * 0.05
      );
      let waterNormal = normalize(vec3<f32>(-waterSlope.x * ${WATER_NORMAL_STRENGTH.toFixed(1)}, 1.0, -waterSlope.y * ${WATER_NORMAL_STRENGTH.toFixed(1)}));
      let viewDirection = normalize(-input.viewDirection);
      let facing = max(dot(waterNormal, viewDirection), 0.0);
      let fresnel = pow(1.0 - facing, ${WATER_FRESNEL_POWER.toFixed(1)});
      let sunVisibility = smoothstep(-0.08, 0.08, frame.sunDirection.y);
      let specular = pow(max(dot(reflect(-frame.sunDirection.xyz, waterNormal), viewDirection), 0.0), ${WATER_SPECULAR_POWER.toFixed(1)});
      let waveHeight = (shimmer - 0.5) * 0.5;
      let foam = smoothstep(${WATER_FOAM_THRESHOLD.toFixed(2)}, 0.98, shimmer) * (0.25 + fresnel * 0.75);
      let causticUv = input.worldPosition.xz * 0.055 + vec2<f32>(frame.params.y * 0.006, -frame.params.y * 0.004);
      let causticPattern = textureSampleLevel(cloudTexture, cloudSampler, causticUv, 0.0).r;
      let caustic = smoothstep(${WATER_CAUSTIC_THRESHOLD_START.toFixed(2)}, ${WATER_CAUSTIC_THRESHOLD_END.toFixed(2)}, causticPattern)
        * ${WATER_CAUSTIC_STRENGTH.toFixed(2)}
        * (0.35 + facing * 0.65);
      let darkWater = vec3<f32>(${WATER_DARK_R}, ${WATER_DARK_G}, ${WATER_DARK_B});
      let lightWater = vec3<f32>(${WATER_LIGHT_R}, ${WATER_LIGHT_G}, ${WATER_LIGHT_B});
      // The material band carries the sampled column depth, so a deep ocean
      // darkens toward a bounded floor without a second vertex attribute.
      let waterDepth = clamp(input.material - ${SURFACE_MATERIAL_WATER.toFixed(1)}, 0.0, 1.0);
      let deepWater = vec3<f32>(${WATER_DEPTH_FLOOR_R.toFixed(3)}, ${(WATER_DARK_G * 0.5).toFixed(3)}, ${(WATER_DARK_B * 0.6).toFixed(3)});
      let depthAlbedo = mix(textureColor.rgb * lightWater, deepWater, waterDepth * ${WATER_DEPTH_TINT_STRENGTH.toFixed(2)});
      let shallowWater = mix(darkWater, depthAlbedo, 0.24);
      let waterTone = clamp(0.18 + facing * 0.48 + waveHeight * 0.38, 0.0, 1.0);
      var waterColor = mix(darkWater, shallowWater, waterTone);
      waterColor = mix(waterColor, frame.skyHorizon.rgb, 0.08 + fresnel * 0.34);
      waterColor += frame.sunColor.rgb * specular * 0.96 * sunVisibility;
      waterColor += vec3<f32>(0.16, 0.72, 0.64) * caustic;
      let foamFade = 1.0 - smoothstep(28.0, 72.0, length(input.viewDirection));
      waterColor += vec3<f32>(0.32, 0.78, 0.78) * foam * foamFade * ${WATER_FOAM_STRENGTH.toFixed(2)};
      color = waterColor * mix(vec3<f32>(0.72, 0.84, 1.0), vec3<f32>(1.0), frame.params.x);
      alpha = 0.7 + fresnel * 0.12 + foam * 0.1;
    } else if (surfacePass > 0.5 && surfacePass < 1.5 && input.material >= ${SURFACE_MATERIAL_LAVA} && input.material < ${SURFACE_MATERIAL_FIRE}) {
      color *= 1.0 + ${LAVA_PULSE_AMPLITUDE} * sin(frame.params.y * ${LAVA_PULSE_SPEED} + input.worldPosition.x * ${LAVA_PULSE_SPATIAL_FREQUENCY});
      alpha = max(alpha, ${LAVA_ALPHA});
    } else if (surfacePass > 0.5 && surfacePass < 1.5 && input.material >= ${SURFACE_MATERIAL_FIRE} && input.material < ${SURFACE_MATERIAL_FIRE + 1}) {
      color *= 1.0 + ${FIRE_PULSE_AMPLITUDE} * sin(frame.params.y * ${FIRE_PULSE_SPEED} + input.worldPosition.y * ${FIRE_PULSE_SPATIAL_FREQUENCY});
      alpha = max(alpha, ${FIRE_ALPHA});
    }
  }
  let fogColor = mix(frame.skyHorizon.rgb, frame.skyColor.rgb, 0.58);
  return vec4<f32>(mix(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), fogColor, input.aerialFog), alpha * (1.0 - input.aerialFog));
}
`;

export const WEBGPU_SKY_SHADER = `${WGSL_FRAME_UNIFORMS}
@group(0) @binding(3) var cloudSampler: sampler;
@group(0) @binding(4) var cloudTexture: texture_2d<f32>;

fn hash31(point: vec3<f32>) -> f32 {
  return fract(sin(dot(point, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453123);
}

fn filmicToneMap(color: vec3<f32>) -> vec3<f32> {
  return clamp(max(color, vec3<f32>(0.0)) * 1.08, vec3<f32>(0.0), vec3<f32>(1.0));
}

struct SkyVertexOutput {
  @builtin(position) position: vec4<f32>,
  @location(0) ndc: vec2<f32>,
};

@vertex
fn sky_vs(@builtin(vertex_index) vertexIndex: u32) -> SkyVertexOutput {
  var positions = array<vec2<f32>, 3>(
    vec2<f32>(-1.0, -1.0),
    vec2<f32>(3.0, -1.0),
    vec2<f32>(-1.0, 3.0),
  );
  var output: SkyVertexOutput;
  output.position = vec4<f32>(positions[vertexIndex], 1.0, 1.0);
  output.ndc = positions[vertexIndex];
  return output;
}

@fragment
fn sky_fs(input: SkyVertexOutput) -> @location(0) vec4<f32> {
  let skyRay = normalize(
    frame.cameraForward.xyz
    + frame.cameraRight.xyz * input.ndc.x * frame.fog.y * frame.fog.z
    + frame.cameraUp.xyz * input.ndc.y * frame.fog.z
  );
  let vertical = clamp(skyRay.y * 0.5 + 0.5, 0.0, 1.0);
  var skyColor = mix(frame.skyHorizon.rgb, frame.skyColor.rgb, smoothstep(0.0, 0.86, vertical));
  let horizonBase = 1.0 - clamp(abs(skyRay.y), 0.0, 1.0);
  let horizonHaze = horizonBase * horizonBase * horizonBase;
  skyColor = mix(skyColor, frame.skyHorizon.rgb, horizonHaze * 0.36);

  let night = 1.0 - smoothstep(0.18, 0.62, frame.params.x);
  var starField = 0.0;
  if (night > 0.01) {
    let starCell = floor(skyRay * 460.0);
    let starLocal = fract(skyRay * 460.0).xy - vec2<f32>(0.5);
    let starPoint = 1.0 - smoothstep(0.025, 0.14, length(starLocal));
    starField = step(0.9962, hash31(starCell)) * starPoint * night;
  }

  let cloudPlane = skyRay.xz * 0.72 + vec2<f32>(skyRay.y * 0.11, -skyRay.y * 0.08);
  let wind = vec2<f32>(frame.params.y * 0.004, frame.params.y * 0.0016);
  let broadCloud = textureSample(cloudTexture, cloudSampler, cloudPlane * 1.35 + wind).r;
  let cloudDetail = textureSample(cloudTexture, cloudSampler, cloudPlane * 2.4 - wind * 1.7 + vec2<f32>(0.17, 0.31)).r;
  var cloudNoise = smoothstep(0.54, 0.72, broadCloud * 0.78 + cloudDetail * 0.22);
  cloudNoise = cloudNoise * smoothstep(0.0, 0.1, skyRay.y);

  let sunDot = max(dot(skyRay, frame.sunDirection.xyz), 0.0);
  let sunVisibility = smoothstep(-0.08, 0.06, frame.sunDirection.y);
  let sunDisk = smoothstep(0.99925, 0.99982, sunDot) * sunVisibility;
  let sunHalo = pow(sunDot, 24.0) * 0.16;
  skyColor += frame.sunColor.rgb * (sunDisk * 1.55 + sunHalo) * sunVisibility;

  if (night > 0.01) {
    let moonDot = max(dot(skyRay, -frame.sunDirection.xyz), 0.0);
    let moonDisk = smoothstep(0.9986, 0.99945, moonDot) * night;
    let moonHalo = pow(moonDot, 48.0) * 0.12 * night;
    skyColor += vec3<f32>(0.72, 0.82, 1.0) * (moonDisk * 0.9 + moonHalo);
  }

  if (cloudNoise > 0.001) {
    let twilight = 1.0 - smoothstep(0.08, 0.48, abs(frame.sunDirection.y));
    let cloudShadow = mix(vec3<f32>(0.055, 0.075, 0.13), vec3<f32>(0.44, 0.53, 0.6), frame.params.x);
    var cloudLight = mix(vec3<f32>(0.12, 0.15, 0.24), vec3<f32>(1.0, 0.95, 0.84), frame.params.x);
    cloudLight = mix(cloudLight, vec3<f32>(1.0, 0.5, 0.27), twilight * 0.34);
    let cloudLightMix = smoothstep(0.48, 0.74, broadCloud);
    let cloudColor = mix(cloudShadow, cloudLight, cloudLightMix);
    skyColor = mix(skyColor, cloudColor, cloudNoise * 0.62);
  }
  skyColor += vec3<f32>(starField * (1.0 - cloudNoise));

  let belowHorizon = 1.0 - smoothstep(-0.2, 0.0, skyRay.y);
  skyColor = mix(skyColor, frame.skyHorizon.rgb * 0.72, belowHorizon * 0.48);
  return vec4<f32>(filmicToneMap(skyColor), 1.0);
}
`;

function align(value, alignment) {
  return Math.ceil(value / alignment) * alignment;
}

function bufferUsage(name) {
  return globalThis.GPUBufferUsage?.[name] ?? BUFFER_USAGE[name];
}

function textureUsage(name) {
  return globalThis.GPUTextureUsage?.[name] ?? TEXTURE_USAGE[name];
}

function shaderStage(name) {
  return globalThis.GPUShaderStage?.[name] ?? SHADER_STAGE[name];
}

function mapMode() {
  return globalThis.GPUMapMode?.READ ?? MAP_READ;
}

function createVertexBuffer(device, packed) {
  if (packed.vertexCount === 0) return null;
  const buffer = device.createBuffer({
    size: align(packed.data.byteLength, 4),
    usage: bufferUsage("VERTEX") | bufferUsage("COPY_DST"),
  });
  device.queue.writeBuffer(buffer, 0, packed.data);
  return buffer;
}

function createPackedDynamicLayer(layer) {
  if (layer === null || layer === undefined) return packTerrainLayer(null);
  const materials = layer.materials ?? new Float32Array(layer.positions.length / 3);
  const tiles = layer.tiles ?? new Float32Array((layer.positions.length / 3) * 4);
  return packTerrainLayer({ ...layer, materials, tiles });
}

function createDefaultAtlas(device) {
  const texture = device.createTexture({
    size: [1, 1, 1],
    format: "rgba8unorm",
    usage: textureUsage("TEXTURE_BINDING") | textureUsage("COPY_DST") | textureUsage("RENDER_ATTACHMENT"),
  });
  device.queue.writeTexture(
    { texture },
    Uint8Array.of(255, 255, 255, 255),
    { bytesPerRow: 4 },
    { width: 1, height: 1, depthOrArrayLayers: 1 },
  );
  return texture;
}

// Foreign Tile Contamination gate for the WebGPU path. The atlas is built on a
// throwaway texture, its mip chain is generated, and each tile's cell is read
// back through a copy so it can be compared against an isolation reference that
// holds only that one tile. This mirrors the WebGL certification, and the verdict
// decides whether the shipping atlas gets a mip chain at all.
async function certifyAtlasMipmapsOnGpu(device, canvas) {
  const levels = ATLAS_MIPMAP_SAFE_LEVELS;
  const verdict = { safe: false, reason: null, levels: [...levels], contaminated: [], worstDelta: 0 };
  if (canvas === null || canvas === undefined) {
    verdict.reason = "no atlas canvas was supplied";
    return verdict;
  }
  if (canvas.width !== canvas.height
    || (canvas.width & (canvas.width - 1)) !== 0) {
    verdict.reason = `the atlas must be square and a power of two, got ${canvas.width}x${canvas.height}`;
    return verdict;
  }
  const context = canvas.getContext("2d", { willReadFrequently: true });
  if (context === null) {
    verdict.reason = "the atlas canvas cannot be read back for certification";
    return verdict;
  }
  // Certify the exact bytes the shipping atlas uploads, so the gate cannot pass
  // on a texture the renderer never samples.
  const source = new Uint8ClampedArray(
    context.getImageData(0, 0, canvas.width, canvas.height).data,
  );
  const mipLevelCount = Math.floor(Math.log2(canvas.width)) + 1;
  // Contamination is a property of the padded layout, so both backends probe the
  // same spread of tiles and the two verdicts stay comparable.
  const probeTiles = spreadProbeTiles(ATLAS_TEXTURES.length, ATLAS_COLUMNS);
  const observed = createMipmappedAtlasTexture(device, canvas.width, mipLevelCount, source);
  if (observed === null) {
    verdict.reason = "the WebGPU device cannot build an atlas texture for certification";
    return verdict;
  }
  try {
    const chain = await certifyMipChainGenerator(device, observed, canvas.width, source);
    if (!chain.matches) {
      // The chain is wrong, so contamination is beside the point: keep the atlas
      // un-mipmapped rather than sample a broken level.
      verdict.mipChain = chain;
      verdict.reason = `the WebGPU mip chain does not match a box-filter reference (max delta ${chain.maxDelta} > ${chain.tolerance})`;
      return verdict;
    }
    const probed = await probeAtlasMipmapGpu(
      device, observed, canvas.width, mipLevelCount, source, levels, verdict, probeTiles,
    );
    return { ...probed, mipChain: chain };
  } catch (error) {
    verdict.reason = `the WebGPU atlas certification failed: ${String(error).slice(0, 160)}`;
    return verdict;
  } finally {
    observed.destroy();
  }
}

function createMipmappedAtlasTexture(device, size, mipLevelCount, pixels) {
  if (typeof device.createRenderPipeline !== "function") return null;
  const texture = device.createTexture({
    size: [size, size, 1],
    format: "rgba8unorm",
    mipLevelCount,
    usage: textureUsage("TEXTURE_BINDING") | textureUsage("COPY_DST")
      | textureUsage("RENDER_ATTACHMENT") | textureUsage("COPY_SRC"),
  });
  device.queue.writeTexture(
    { texture },
    pixels,
    { bytesPerRow: size * 4, rowsPerImage: size },
    { width: size, height: size, depthOrArrayLayers: 1 },
  );
  generateAtlasMipmaps(device, texture, mipLevelCount);
  return texture;
}

// The isolation reference is a full-size atlas that holds one tile and zeroes
// everything else, mipmapped the same way. If the observed cell differs from it,
// another tile's material reached into this one.
function buildIsolationReference(device, size, mipLevelCount, source, cell) {
  const isolated = new Uint8Array(size * size * 4);
  const origin = atlasCellOrigin(cell.tile);
  const stride = ATLAS_TILE_STRIDE * 4;
  for (let row = 0; row < ATLAS_TILE_STRIDE; row += 1) {
    const from = ((origin.y + row) * ATLAS_WIDTH + origin.x) * 4;
    isolated.set(source.subarray(from, from + stride), (origin.y + row) * size * 4 + origin.x * 4);
  }
  return createMipmappedAtlasTexture(device, size, mipLevelCount, isolated);
}

async function probeAtlasMipmapGpu(
  device, texture, size, mipLevelCount, source, levels, verdict, probeTiles,
) {
  const contaminated = [];
  let worstDelta = 0;
  for (const tile of probeTiles) {
    const cell = { tile };
    const reference = buildIsolationReference(device, size, mipLevelCount, source, cell);
    if (reference === null) {
      verdict.reason = "the WebGPU device cannot build an isolation reference";
      return verdict;
    }
    try {
      for (const level of levels) {
        const geometry = atlasMipLevelGeometry(ATLAS_TILE_GUTTER, ATLAS_TILE_SIZE, level);
        if (geometry.size < 1) continue;
        const cellPixels = readAtlasCell(device, texture, cell, geometry, level);
        const expectedPixels = readAtlasCell(device, reference, cell, geometry, level);
        const delta = maxChannelDelta(cellPixels, expectedPixels);
        if (delta > worstDelta) worstDelta = delta;
        if (foreignTileContamination(
          { size: geometry.size, pixels: cellPixels },
          { size: geometry.size, pixels: expectedPixels },
        )) {
          contaminated.push({ tile: cell.tile, level, maxDelta: delta });
        }
      }
    } finally {
      reference.destroy();
    }
  }
  return { ...verdict, safe: contaminated.length === 0, reason: null, contaminated, worstDelta };
}

async function readAtlasCell(device, texture, cell, geometry, level) {
  const origin = atlasCellOrigin(cell.tile);
  const factor = 2 ** level;
  // `geometry.size` is already the whole padded cell at this level, so the cell
  // starts at the scaled cell origin with no extra gutter inset.
  const x = Math.floor(origin.x / factor);
  const y = Math.floor(origin.y / factor);
  const region = await readTextureRegion(device, texture, level, x, y, geometry.size, geometry.size);
  return region.pixels;
}
/** Copy a rectangular region of one mip level and return it tightly packed. */
async function readTextureRegion(device, texture, level, x, y, width, height) {
  const stride = bytesPerRow(width);
  const buffer = device.createBuffer({
    size: stride * height,
    usage: bufferUsage("MAP_READ") | bufferUsage("COPY_DST"),
  });
  try {
    const encoder = device.createCommandEncoder();
    encoder.copyTextureToBuffer(
      { texture, mipLevel: level, origin: { x, y, z: 0 } },
      { buffer, bytesPerRow: stride, rowsPerImage: height },
      { width, height, depthOrArrayLayers: 1 },
    );
    device.queue.submit([encoder.finish()]);
    await mapBufferWithin(buffer, mapMode());
    const mapped = new Uint8Array(buffer.getMappedRange());
    const rowBytes = width * 4;
    const pixels = new Uint8Array(rowBytes * height);
    for (let row = 0; row < height; row += 1) {
      pixels.set(mapped.subarray(row * stride, row * stride + rowBytes), row * rowBytes);
    }
    buffer.unmap();
    return { width, height, pixels };
  } finally {
    buffer.destroy();
  }
}

// The contamination probe builds both the observed atlas and its isolation
// reference with the same generator, so a generator bug cancels out and the
// chain is certified as clean while the scene renders wrong. This compares the
// chain against a CPU box filter computed a different way, which can fail.
async function certifyMipChainGenerator(device, texture, size, source) {
  const level = 1;
  const half = Math.max(1, size >> 1);
  const observed = await readTextureRegion(device, texture, level, 0, 0, half, half);
  const expected = atlasBoxDownsample(size, source, level);
  const delta = maxChannelDelta(observed.pixels, expected.pixels);
  return {
    level,
    matches: delta <= MIP_CHAIN_TOLERANCE,
    maxDelta: delta,
    tolerance: MIP_CHAIN_TOLERANCE,
  };
}

// The atlas is a padded, power-of-two image, so it can take a mip chain like the
// WebGL path. The chain is only generated once the atlas has been certified free
// of foreign tile contamination and its levels match a box-filter reference.
function createAtlasTexture(device, canvas, mipmapSafe) {
  if (canvas === null || canvas === undefined) return createDefaultAtlas(device);
  const mipLevelCount = mipmapSafe
    ? Math.floor(Math.log2(Math.max(canvas.width, canvas.height))) + 1
    : 1;
  const texture = device.createTexture({
    size: [canvas.width, canvas.height, 1],
    format: "rgba8unorm",
    mipLevelCount,
    // COPY_SRC/COPY_DST are what let the generated chain be copied into the
    // levels, since a texture cannot be sampled and rendered into at once.
    usage: textureUsage("TEXTURE_BINDING") | textureUsage("COPY_DST")
      | textureUsage("COPY_SRC") | textureUsage("RENDER_ATTACHMENT"),
  });
  device.queue.copyExternalImageToTexture(
    { source: canvas },
    { texture },
    { width: canvas.width, height: canvas.height, depthOrArrayLayers: 1 },
  );
  if (mipmapSafe && mipLevelCount > 1) generateAtlasMipmaps(device, texture, mipLevelCount);
  return texture;
}

// `copyExternalImageToTexture` can only write mip level 0, so the chain is
// built by rendering each level from the one before it. This is the same box
// filter the WebGL path's `generateMipmap` applies.
function generateAtlasMipmaps(device, texture, mipLevelCount) {
  const size = mipLevelCount
    ?? (Math.floor(Math.log2(Math.max(texture.width, texture.height))) + 1);
  if (size < 1 || typeof device.createRenderPipeline !== "function") return;
  const format = "rgba8unorm";
  const pipeline = device.createRenderPipeline({
    layout: "auto",
    vertex: {
      module: device.createShaderModule({ code: ATLAS_MIPMAP_WGSL }),
      entryPoint: "vs_main",
    },
    fragment: {
      module: device.createShaderModule({ code: ATLAS_MIPMAP_WGSL }),
      entryPoint: "fs_main",
      targets: [{ format }],
    },
    primitive: { topology: "triangle-list" },
  });
  const sampler = device.createSampler({
    magFilter: "linear",
    minFilter: "linear",
    addressModeU: "clamp-to-edge",
    addressModeV: "clamp-to-edge",
  });
  // Level 0 already holds the atlas, so the chain is built by sampling it into a
  // scratch texture per level and copying the result back.
  let previous = createMipScratchTexture(device, texture.width);
  {
    const encoder = device.createCommandEncoder();
    encoder.copyTextureToTexture(
      { texture },
      { texture: previous },
      { width: previous.width, height: previous.height, depthOrArrayLayers: 1 },
    );
    device.queue.submit([encoder.finish()]);
  }
  for (let level = 1; level < size; level += 1) {
    const target = createMipScratchTexture(device, Math.max(1, texture.width >> level));
    const bindGroup = device.createBindGroup({
      layout: pipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: sampler },
        { binding: 1, resource: previous.createView() },
      ],
    });
    const encoder = device.createCommandEncoder();
    const pass = encoder.beginRenderPass({
      colorAttachments: [{
        view: target.createView(),
        loadOp: "clear",
        storeOp: "store",
        clearValue: { r: 0, g: 0, b: 0, a: 0 },
      }],
    });
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, bindGroup);
    pass.draw(3, 1, 0, 0);
    pass.end();
    // The downsample has to land in the chain, but a texture cannot be sampled
    // and rendered into at the same time, so each level is built in its own
    // texture and copied in afterwards.
    encoder.copyTextureToTexture(
      { texture: target },
      { texture, mipLevel: level },
      { width: target.width, height: target.height, depthOrArrayLayers: 1 },
    );
    device.queue.submit([encoder.finish()]);
    previous?.destroy?.();
    previous = target;
  }
  previous?.destroy?.();
}

function createMipScratchTexture(device, size) {
  return device.createTexture({
    size: [Math.max(1, size), Math.max(1, size), 1],
    format: "rgba8unorm",
    usage: textureUsage("TEXTURE_BINDING") | textureUsage("RENDER_ATTACHMENT")
      | textureUsage("COPY_SRC") | textureUsage("COPY_DST"),
  });
}

const ATLAS_MIPMAP_WGSL = `
@group(0) @binding(0) var sourceSampler: sampler;
@group(0) @binding(1) var sourceTexture: texture_2d<f32>;

struct VertexOutput {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) vertexIndex: u32) -> VertexOutput {
  var positions = array<vec2<f32>, 3>(
    vec2<f32>(-1.0, -1.0),
    vec2<f32>(3.0, -1.0),
    vec2<f32>(-1.0, 3.0),
  );
  var output: VertexOutput;
  output.position = vec4<f32>(positions[vertexIndex], 0.0, 1.0);
  output.uv = positions[vertexIndex] * 0.5 + 0.5;
  return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
  return textureSample(sourceTexture, sourceSampler, input.uv);
}
`;

function createCloudTexture(device) {
  const texture = device.createTexture({
    size: [CLOUD_TEXTURE_SIZE, CLOUD_TEXTURE_SIZE, 1],
    format: "rgba8unorm",
    usage: textureUsage("TEXTURE_BINDING") | textureUsage("COPY_DST"),
  });
  device.queue.writeTexture(
    { texture },
    createCloudTextureData(),
    { bytesPerRow: CLOUD_TEXTURE_SIZE * 4, rowsPerImage: CLOUD_TEXTURE_SIZE },
    { width: CLOUD_TEXTURE_SIZE, height: CLOUD_TEXTURE_SIZE, depthOrArrayLayers: 1 },
  );
  return texture;
}

async function validateDevicePresentation(device, format) {
  if (typeof globalThis.createImageBitmap !== "function" || typeof document === "undefined") return true;
  const probeCanvas = document.createElement("canvas");
  probeCanvas.width = 1;
  probeCanvas.height = 1;
  const probeContext = probeCanvas.getContext("webgpu");
  if (probeContext === null) return false;
  probeContext.configure({ device, format, alphaMode: "opaque" });
  return validateCanvasPresentation(probeCanvas, probeContext, device);
}

async function validateCanvasPresentation(canvas, canvasContext, device) {
  if (typeof globalThis.createImageBitmap !== "function" || typeof document === "undefined") return true;
  const encoder = device.createCommandEncoder();
  const pass = encoder.beginRenderPass({
    colorAttachments: [{
      view: canvasContext.getCurrentTexture().createView(),
      clearValue: { r: 1, g: 0, b: 0, a: 1 },
      loadOp: "clear",
      storeOp: "store",
    }],
  });
  pass.end();
  device.queue.submit([encoder.finish()]);
  await new Promise((resolve) => requestAnimationFrame(resolve));
  try {
    const bitmap = await createImageBitmap(canvas);
    const probe = document.createElement("canvas");
    probe.width = 1;
    probe.height = 1;
    const context = probe.getContext("2d", { willReadFrequently: true });
    context.drawImage(bitmap, 0, 0, 1, 1);
    bitmap.close();
    const pixel = context.getImageData(0, 0, 1, 1).data;
    return pixel[0] > 180 && pixel[1] < 100 && pixel[2] < 100 && pixel[3] > 180;
  } catch {
    return false;
  }
}

/**
 * Blend modes the terrain pipelines ask for. "opaque" is no blend at all;
 * "alpha" is the ordinary covering blend; "premultiplied" is the one the
 * particle pass needs, so a single batch can carry an additive spark
 * (destination weight zero) and a puff of covering smoke (destination weight
 * one minus its own alpha) at once.
 */
const BLEND_STATES = Object.freeze({
  alpha: {
    color: { srcFactor: "src-alpha", dstFactor: "one-minus-src-alpha", operation: "add" },
    alpha: { srcFactor: "one", dstFactor: "one-minus-src-alpha", operation: "add" },
  },
  premultiplied: {
    color: { srcFactor: "one", dstFactor: "one-minus-src-alpha", operation: "add" },
    alpha: { srcFactor: "one", dstFactor: "one-minus-src-alpha", operation: "add" },
  },
});

function resolveBlend(mode) {
  if (mode === "opaque") return undefined;
  const state = BLEND_STATES[mode];
  if (state === undefined) throw new Error(`unknown blend mode: ${mode}`);
  return state;
}

async function createPipeline(device, layout, module, format, depthFormat, blend, depthWriteEnabled) {
  const descriptor = {
    layout,
    vertex: {
      module,
      entryPoint: "vs_main",
      buffers: [TERRAIN_VERTEX_LAYOUT],
    },
    fragment: {
      module,
      entryPoint: "fs_main",
      targets: [{
        format,
        blend: resolveBlend(blend),
      }],
    },
    // Keep parity with the WebGL fallback until every greedy/dynamic face
    // has a certified winding contract; back-face culling can remove terrain.
    primitive: { topology: "triangle-list", cullMode: "none" },
    depthStencil: {
      format: depthFormat,
      depthWriteEnabled,
      depthCompare: "less",
    },
  };
  return typeof device.createRenderPipelineAsync === "function"
    ? device.createRenderPipelineAsync(descriptor)
    : device.createRenderPipeline(descriptor);
}

async function createSkyPipeline(device, layout, module, format, depthFormat) {
  const descriptor = {
    layout,
    vertex: { module, entryPoint: "sky_vs" },
    fragment: {
      module,
      entryPoint: "sky_fs",
      targets: [{ format }],
    },
    primitive: { topology: "triangle-list" },
    depthStencil: {
      format: depthFormat,
      depthWriteEnabled: false,
      depthCompare: "less-equal",
    },
  };
  return typeof device.createRenderPipelineAsync === "function"
    ? device.createRenderPipelineAsync(descriptor)
    : device.createRenderPipeline(descriptor);
}

export async function createWebGpuTerrainRenderer({
  canvas,
  atlasCanvas = null,
  navigatorLike = globalThis.navigator,
  context = null,
} = {}) {
  if (canvas === null || canvas === undefined) throw new TypeError("WebGPU renderer requires a canvas");
  const gpu = navigatorLike?.gpu;
  if (gpu === undefined || typeof gpu.requestAdapter !== "function") {
    throw new Error("WebGPU is not available in this browser.");
  }
  const adapter = await gpu.requestAdapter();
  if (adapter === null) throw new Error("No WebGPU adapter was returned.");
  const device = await adapter.requestDevice();
  // A lost device is the one WebGPU failure that looks like nothing at all: every
  // later submit is silently dropped and every mapAsync promise stays pending
  // forever, so the frame loop keeps requesting animation frames and the image
  // simply stops changing. Without these two handlers the browser cannot tell the
  // difference between a slow frame and a dead device, and the player is left
  // looking at a frozen picture with no way out.
  let destroyed = false;
  let deviceFailure = null;
  const noteDeviceFailure = (reason) => {
    if (deviceFailure !== null) return;
    deviceFailure = { reason: String(reason ?? "device lost") };
    for (const listener of failureListeners) {
      try {
        listener(deviceFailure);
      } catch {
        // A listener that throws must not take the renderer down with it.
      }
    }
  };
  const failureListeners = new Set();
  device.lost?.then((info) => {
    // A destroy we asked for is not a failure.
    if (destroyed) return;
    noteDeviceFailure(info?.reason ? `device lost: ${info.reason}` : "device lost");
  });
  device.addEventListener?.("uncapturederror", (event) => {
    if (destroyed) return;
    noteDeviceFailure(event?.error?.message ?? "uncaptured GPU error");
  });
  const format = gpu.getPreferredCanvasFormat?.() ?? "bgra8unorm";
  const depthFormat = "depth24plus";
  let depthTexture = null;
  let depthSize = "";
  if (!await validateDevicePresentation(device, format)) {
    throw new Error("WebGPU presentation is unavailable; refusing a blank canvas.");
  }
  const shaderModule = device.createShaderModule({ code: WEBGPU_TERRAIN_SHADER });
  const skyShaderModule = device.createShaderModule({ code: WEBGPU_SKY_SHADER });
  const bindGroupLayout = device.createBindGroupLayout({ entries: [
    { binding: 0, visibility: shaderStage("VERTEX") | shaderStage("FRAGMENT"), buffer: { type: "uniform" } },
    { binding: 1, visibility: shaderStage("FRAGMENT"), sampler: { type: "filtering" } },
    { binding: 2, visibility: shaderStage("FRAGMENT"), texture: { sampleType: "float" } },
    { binding: 3, visibility: shaderStage("FRAGMENT"), sampler: { type: "filtering" } },
    { binding: 4, visibility: shaderStage("FRAGMENT"), texture: { sampleType: "float" } },
  ] });
  const pipelineLayout = device.createPipelineLayout({ bindGroupLayouts: [bindGroupLayout] });
  const skyPipeline = await createSkyPipeline(device, pipelineLayout, skyShaderModule, format, depthFormat);
  const opaquePipeline = await createPipeline(device, pipelineLayout, shaderModule, format, depthFormat, "opaque", true);
  const alphaPipeline = await createPipeline(device, pipelineLayout, shaderModule, format, depthFormat, "alpha", false);
  const dynamicPipeline = await createPipeline(device, pipelineLayout, shaderModule, format, depthFormat, "alpha", true);
  const shadowPipeline = await createPipeline(device, pipelineLayout, shaderModule, format, depthFormat, "alpha", false);
  // Mode 4. Depth writes stay off so a particle cannot carve its own silhouette
  // out of the depth buffer and cull every particle behind it.
  const vfxPipeline = await createPipeline(device, pipelineLayout, shaderModule, format, depthFormat, "premultiplied", false);
  const frameBuffers = Array.from({ length: 5 }, () => device.createBuffer({
    size: FRAME_UNIFORM_BYTES,
    usage: bufferUsage("UNIFORM") | bufferUsage("COPY_DST"),
  }));
  device.pushErrorScope?.("validation");
  // The gate has to decide before the shipping atlas is built, so an uncertified
  // atlas can never reach the screen with a mip chain.
  const atlasMipmapVerdict = await certifyAtlasMipmapsOnGpu(device, atlasCanvas);
  const atlasTexture = createAtlasTexture(device, atlasCanvas, atlasMipmapVerdict.safe);
  const cloudTexture = createCloudTexture(device);
  const textureError = await device.popErrorScope?.();
  if (textureError) {
    atlasTexture.destroy();
    cloudTexture.destroy();
    throw new Error(`WebGPU texture upload failed: ${textureError.message}`);
  }
  const atlasSampler = device.createSampler({
    magFilter: "linear",
    // Minification filters within the base level whether or not a chain exists.
    // Only the mip filter has to follow the chain, so an uncertified atlas still
    // gets linear minification instead of dropping to nearest.
    minFilter: "linear",
    mipmapFilter: atlasMipmapVerdict.safe ? "linear" : "nearest",
    addressModeU: "clamp-to-edge",
    addressModeV: "clamp-to-edge",
  });
  const cloudSampler = device.createSampler({
    magFilter: "linear",
    minFilter: "linear",
    addressModeU: "repeat",
    addressModeV: "repeat",
  });
  const bindGroups = frameBuffers.map((frameBuffer) => device.createBindGroup({
    layout: bindGroupLayout,
    entries: [
      { binding: 0, resource: { buffer: frameBuffer } },
      { binding: 1, resource: atlasSampler },
      { binding: 2, resource: atlasTexture.createView() },
      { binding: 3, resource: cloudSampler },
      { binding: 4, resource: cloudTexture.createView() },
    ],
  }));
  const canvasContext = context ?? canvas.getContext("webgpu");
  if (canvasContext === null) throw new Error("WebGPU canvas context is unavailable.");
  // The swap chain must be configured for copying before a real frame can be
  // read back, otherwise the gate would only ever prove the pipeline compiles.
  canvasContext.configure({
    device,
    format,
    alphaMode: "opaque",
    usage: textureUsage("RENDER_ATTACHMENT") | textureUsage("COPY_SRC"),
  });
  // A device can still refuse the usage request, so the verdict comes from the
  // real context rather than from an assumption.
  const readbackSupport = describeFrameReadbackSupport({
    hasCopySource: typeof canvasContext.getCurrentTexture === "function"
      && (globalThis.GPUTextureUsage === undefined
        || (globalThis.GPUTextureUsage.COPY_SRC ?? COPY_SRC) !== 0),
    hasMapRead: typeof device.createBuffer === "function"
      && (globalThis.GPUBufferUsage === undefined
        || (globalThis.GPUBufferUsage.MAP_READ ?? MAP_READ) !== 0),
  });
  const terrain = new Map();
  let dynamic = null;
  let shadow = null;
  let vfx = null;
  let uploadedOpaqueVertices = 0;
  let uploadedWaterVertices = 0;
  let terrainBufferUploads = 0;
  let terrainBufferReuses = 0;
  let editUploads = 0;
  let resyncUploads = 0;
  let lastSubmit = createSubmitMetrics();
  // A frame readback request waiting for the next render() to encode its copy.
  let pendingCapture = null;

  function storeChunk(key, opaqueSource, waterSource) {
    const previous = terrain.get(key);
    if (previous !== undefined
      && previous.opaqueSource === opaqueSource
      && previous.waterSource === waterSource) {
      terrainBufferReuses += 1;
      uploadedOpaqueVertices += previous.opaqueVertices;
      uploadedWaterVertices += previous.waterVertices;
      return false;
    }
    const opaque = packTerrainLayer(opaqueSource);
    const water = packTerrainLayer(waterSource);
    terrain.set(key, {
      opaque: replaceBuffer(previous?.opaque, opaque),
      water: replaceBuffer(previous?.water, water),
      opaqueSource,
      waterSource,
      opaqueVertices: opaque.vertexCount,
      waterVertices: water.vertexCount,
      strideBytes: TERRAIN_VERTEX_STRIDE_BYTES,
      bounds: mergeBounds(
        packedLayerBounds(opaque, emptyBounds),
        packedLayerBounds(water, emptyBounds),
      ),
    });
    terrainBufferUploads += 1;
    uploadedOpaqueVertices += opaque.vertexCount;
    uploadedWaterVertices += water.vertexCount;
    return true;
  }

  // Streaming resync: the resident set may have changed, so retire the buffers
  // of chunks that left the active window before applying the rest.
  function uploadTerrain(chunks) {
    const incoming = new Set(chunks.map((chunk) => String(chunk.key)));
    for (const [key, buffers] of terrain) {
      if (!incoming.has(key)) {
        buffers.opaque?.destroy();
        buffers.water?.destroy();
        terrain.delete(key);
      }
    }
    uploadedOpaqueVertices = 0;
    uploadedWaterVertices = 0;
    for (const chunk of chunks) {
      if (storeChunk(String(chunk.key), chunk.vertexData?.opaque ?? null, chunk.vertexData?.water ?? null)) {
        resyncUploads += 1;
      }
    }
  }

  // Edit path: the resident set is unchanged, so only the chunks whose vertex
  // data actually changed are re-uploaded. No buffer is retired and no chunk is
  // touched twice.
  function updateChunks(chunks) {
    const mode = classifyChunkUpdate([...terrain.keys()], chunks.map((chunk) => String(chunk.key)));
    if (mode === "resync") {
      uploadTerrain(chunks);
      return mode;
    }
    uploadedOpaqueVertices = 0;
    uploadedWaterVertices = 0;
    for (const chunk of chunks) {
      if (storeChunk(String(chunk.key), chunk.vertexData?.opaque ?? null, chunk.vertexData?.water ?? null)) {
        editUploads += 1;
      }
    }
    return mode;
  }

  function ensureDepthTexture() {
    const key = `${canvas.width}x${canvas.height}`;
    if (key === depthSize && depthTexture !== null) return;
    depthTexture?.destroy();
    depthTexture = device.createTexture({
      size: [Math.max(1, canvas.width), Math.max(1, canvas.height), 1],
      format: depthFormat,
      usage: textureUsage("RENDER_ATTACHMENT"),
    });
    depthSize = key;
  }

  function replaceBuffer(previous, packed) {
    previous?.destroy();
    return createVertexBuffer(device, packed);
  }

  function uploadDynamic({ dynamic: dynamicLayer = null, shadow: shadowLayer = null } = {}) {
    const packedDynamic = createPackedDynamicLayer(dynamicLayer);
    const packedShadow = createPackedDynamicLayer(shadowLayer);
    dynamic?.buffer?.destroy();
    shadow?.buffer?.destroy();
    dynamic = { buffer: createVertexBuffer(device, packedDynamic), vertexCount: packedDynamic.vertexCount };
    shadow = { buffer: createVertexBuffer(device, packedShadow), vertexCount: packedShadow.vertexCount };
  }

  /**
   * The particle layer is uploaded on its own, not through `uploadDynamic`.
   * That one reallocates every layer it is handed, so calling it a second time
   * in the same frame - once for the entities, once for the particles - would
   * replace the entity buffers with empty ones and silently drop every mob.
   */
  function uploadVfx(layer) {
    const packed = createPackedDynamicLayer(layer);
    vfx?.buffer?.destroy();
    vfx = { buffer: createVertexBuffer(device, packed), vertexCount: packed.vertexCount };
  }

  function writeFrame(frame, mode) {
    const values = new Float32Array(FRAME_UNIFORM_BYTES / 4);
    values.set(frame.viewProjection, 0);
    values.set([frame.camera[0], frame.camera[1], frame.camera[2], 1], 16);
    values.set([frame.skyColor[0], frame.skyColor[1], frame.skyColor[2], 1], 20);
    values.set([frame.daylight ?? 1, frame.time ?? 0, mode, frame.miningProgress ?? 0], 24);
    values.set([
      frame.fogDistance ?? 120,
      frame.aspect ?? 1,
      frame.tanHalfFov ?? 1,
      0,
    ], 28);
    const horizon = frame.skyHorizon ?? frame.skyColor;
    const cameraRight = frame.cameraRight ?? [1, 0, 0];
    const cameraUp = frame.cameraUp ?? [0, 1, 0];
    const cameraForward = frame.cameraForward ?? [0, 0, -1];
    const sunDirection = frame.sunDirection ?? [0, 1, 0];
    const sunColor = frame.sunColor ?? [1, 0.94, 0.76];
    values.set([horizon[0], horizon[1], horizon[2], 1], 32);
    values.set([cameraRight[0], cameraRight[1], cameraRight[2], 0], 36);
    values.set([cameraUp[0], cameraUp[1], cameraUp[2], 0], 40);
    values.set([cameraForward[0], cameraForward[1], cameraForward[2], 0], 44);
    values.set([sunDirection[0], sunDirection[1], sunDirection[2], 0], 48);
    values.set([sunColor[0], sunColor[1], sunColor[2], 1], 52);
    device.queue.writeBuffer(frameBuffers[mode], 0, values);
  }

  function drawLayer(pass, pipeline, buffer, vertexCount, mode) {
    if (buffer === null || vertexCount === 0) return;
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, bindGroups[mode]);
    pass.setVertexBuffer(0, buffer);
    pass.draw(vertexCount, 1, 0, 0);
  }

  /**
   * Read a real region of the presented frame back to JavaScript.
   *
   * The copy must be encoded in the *same* command buffer as the render pass:
   * a canvas texture's contents are only valid until the frame is presented, so
   * copying it in a later submission reads back an empty texture. This arms a
   * capture request, waits for the next frame to encode it, then maps the copy.
   */
  async function readFramePixels(x, y, width, height) {
    if (!readbackSupport.supported) {
      throw new Error(`WebGPU frame readback is unavailable: ${readbackSupport.reason}`);
    }
    const left = Math.trunc(Number(x));
    const bottom = Math.trunc(Number(y));
    const pixelWidth = Math.trunc(Number(width));
    const pixelHeight = Math.trunc(Number(height));
    if (left < 0 || bottom < 0 || pixelWidth < 1 || pixelHeight < 1
      || left + pixelWidth > canvas.width || bottom + pixelHeight > canvas.height) {
      throw new RangeError("frame pixel region is outside the canvas");
    }
    // Callers address the frame the way WebGL `readPixels` does, with the origin
    // at the bottom left, so the copy has to start at the mirrored row.
    const top = readbackRowTop(canvas.height, bottom, pixelHeight);
    const stride = bytesPerRow(pixelWidth);
    const buffer = device.createBuffer({
      size: stride * pixelHeight,
      usage: bufferUsage("MAP_READ") | bufferUsage("COPY_DST"),
    });
    const request = {
      left,
      bottom,
      top,
      width: pixelWidth,
      height: pixelHeight,
      stride,
      buffer,
      resolve: null,
      reject: null,
    };
    const done = new Promise((resolve, reject) => {
      request.resolve = resolve;
      request.reject = reject;
    });
    const previous = pendingCapture;
    pendingCapture = request;
    if (previous !== null) {
      // A superseded request would otherwise wait forever for a frame.
      pendingCapture = request;
      previous.reject(new Error("WebGPU frame readback was superseded by a newer request"));
    }
    try {
      // The game loop drives render(), which is what encodes the copy.
      for (let attempt = 0; attempt < 240 && !request.captured; attempt += 1) {
        await new Promise((resolve) => setTimeout(resolve, 16));
      }
      if (!request.captured) {
        throw new Error("WebGPU frame readback timed out waiting for a rendered frame");
      }
      await mapBufferWithin(buffer, mapMode());
      const mapped = new Uint8Array(buffer.getMappedRange());
      const rowBytes = pixelWidth * FRAME_READBACK_BYTES_PER_PIXEL;
      const pixels = new Uint8Array(rowBytes * pixelHeight);
      for (let row = 0; row < pixelHeight; row += 1) {
        const source = row * stride;
        const target = readbackTargetRow(pixelHeight, row) * rowBytes;
        pixels.set(mapped.subarray(source, source + rowBytes), target);
      }
      if (format.startsWith("bgra")) swapRedBlue(pixels);
      return { left, bottom, width: pixelWidth, height: pixelHeight, pixels };
    } finally {
      if (pendingCapture === request) pendingCapture = null;
      buffer.unmap?.();
      buffer.destroy();
    }
  }

  function render(frame) {
    ensureDepthTexture();
    writeFrame(frame, 0);
    writeFrame(frame, 1);
    writeFrame(frame, 2);
    writeFrame(frame, 3);
    writeFrame(frame, 4);
    // Cull per chunk before the pass is encoded. A chunk that only touches the
    // frustum edge is kept, so culling can never pop terrain that is on screen.
    const planes = extractClipPlanes(frame.viewProjection);
    const { visible, metrics } = selectVisibleChunks(terrain.values(), planes);
    lastSubmit = metrics;
    metrics.drawCalls += 1; // the sky triangle
    if ((shadow?.vertexCount ?? 0) > 0) metrics.drawCalls += 1;
    if ((dynamic?.vertexCount ?? 0) > 0) metrics.drawCalls += 1;
    if ((vfx?.vertexCount ?? 0) > 0) metrics.drawCalls += 1;
    const encoder = device.createCommandEncoder();
    const presented = canvasContext.getCurrentTexture();
    const pass = encoder.beginRenderPass({
      colorAttachments: [{
        view: presented.createView(),
        clearValue: {
          r: frame.skyColor[0],
          g: frame.skyColor[1],
          b: frame.skyColor[2],
          a: 1,
        },
        loadOp: "clear",
        storeOp: "store",
      }],
      depthStencilAttachment: {
        view: depthTexture.createView(),
        depthClearValue: 1,
        depthLoadOp: "clear",
        depthStoreOp: "store",
      },
    });
    for (const chunk of visible) drawLayer(pass, opaquePipeline, chunk.opaque, chunk.opaqueVertices, 0);
    pass.setPipeline(skyPipeline);
    pass.setBindGroup(0, bindGroups[0]);
    pass.draw(3, 1, 0, 0);
    for (const chunk of visible) drawLayer(pass, alphaPipeline, chunk.water, chunk.waterVertices, 1);
    drawLayer(pass, shadowPipeline, shadow?.buffer ?? null, shadow?.vertexCount ?? 0, 2);
    drawLayer(pass, dynamicPipeline, dynamic?.buffer ?? null, dynamic?.vertexCount ?? 0, 3);
    drawLayer(pass, vfxPipeline, vfx?.buffer ?? null, vfx?.vertexCount ?? 0, 4);
    pass.end();
    // The readback copy has to be part of this submission. A canvas texture is
    // only valid until the frame is presented, so copying it afterwards would
    // read back an empty texture instead of the frame just drawn.
    const capture = pendingCapture;
    if (capture !== null) {
      encoder.copyTextureToBuffer(
        { texture: presented, origin: { x: capture.left, y: capture.top, z: 0 } },
        {
          buffer: capture.buffer,
          bytesPerRow: capture.stride,
          rowsPerImage: capture.height,
        },
        { width: capture.width, height: capture.height, depthOrArrayLayers: 1 },
      );
      capture.captured = true;
    }
    device.queue.submit([encoder.finish()]);
  }

  function destroy() {
    destroyed = true;
    failureListeners.clear();
    for (const buffers of terrain.values()) {
      buffers.opaque?.destroy();
      buffers.water?.destroy();
    }
    dynamic?.buffer?.destroy();
    shadow?.buffer?.destroy();
    depthTexture?.destroy();
    atlasTexture.destroy();
    cloudTexture.destroy();
    for (const frameBuffer of frameBuffers) frameBuffer.destroy();
    device.destroy?.();
  }

  return {
    kind: "webgpu",
    adapterName: adapter.name ?? null,
    uploadTerrain,
    updateChunks,
    uploadDynamic,
    uploadVfx,
    render,
    readFramePixels,
    getReadbackSupport: () => ({ ...readbackSupport }),
    /**
     * The first device failure seen, or null. A caller checks this each frame and
     * switches to the WebGL path, which is the only recovery from a lost device:
     * nothing the renderer does afterwards can make it draw again.
     */
    getDeviceFailure: () => (deviceFailure === null ? null : { ...deviceFailure }),
    /** Notified once, on the first failure, so a caller can react immediately. */
    onDeviceFailure: (listener) => {
      if (typeof listener !== "function") return () => {};
      if (deviceFailure !== null) {
        try { listener({ ...deviceFailure }); } catch { /* a bad listener is not a render failure */ }
        return () => {};
      }
      failureListeners.add(listener);
      return () => failureListeners.delete(listener);
    },
    getAtlasMipmapVerdict: () => ({ ...atlasMipmapVerdict }),
    destroy,
    getStats: () => ({
      backend: "webgpu",
      chunks: terrain.size,
      opaqueVertices: uploadedOpaqueVertices,
      waterVertices: uploadedWaterVertices,
      terrainBufferUploads,
      terrainBufferReuses,
      editUploads,
      resyncUploads,
      dynamicVertices: dynamic?.vertexCount ?? 0,
      shadowVertices: shadow?.vertexCount ?? 0,
      vertexStrideBytes: TERRAIN_VERTEX_STRIDE_BYTES,
      residentChunks: lastSubmit.totalChunks,
      visibleChunks: lastSubmit.visibleChunks,
      culledChunks: lastSubmit.culledChunks,
      drawCalls: lastSubmit.drawCalls,
      submittedVertices: lastSubmit.submittedVertices,
      submittedVertexBytes: lastSubmit.submittedVertexBytes,
    }),
  };
}
