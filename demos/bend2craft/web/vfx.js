// World-space particle effects.
//
// Pure data and arithmetic: no DOM, no GL, no timers, no frame callback. The
// game owns the buffers and the draw call; this module owns which particles
// exist, how they move and what colour they are. That split is what lets the
// whole effect vocabulary be tested without a browser.
//
// Presentation only. Whether a mob is on fire is decided by the Bend entity
// tick (`Entities.sunlight_damage` sets `Mob.burning`); nothing here decides
// that fire should happen, it only draws what it is told.

/**
 * A hard ceiling on live particles. Every emitter is rate-limited by its own
 * lifetime, so this only has to cover the worst case the game can produce: a
 * screen full of burning mobs plus a burst from every effect in flight.
 */
export const VFX_CAPACITY = 384;

const FLAME_COLOR_LOW = [1.0, 0.28, 0.05];
const FLAME_COLOR_HIGH = [1.0, 0.78, 0.24];
const SMOKE_COLOR = [0.16, 0.15, 0.14];

function clamp01(value) {
  if (!Number.isFinite(value)) return 0;
  return value < 0 ? 0 : value > 1 ? 1 : value;
}

/**
 * Turn a CSS hex colour into the 0..1 triple the vertex buffer carries.
 *
 * Block and item tints already exist as hex strings in the inventory contract,
 * and an effect that cannot be tinted with the colour of the thing it came from
 * is a second palette to keep in sync. An unparseable colour resolves to white
 * so a typo shows up as a bright particle rather than an invisible one.
 */
export function hexToRgb(hex) {
  if (typeof hex !== "string") return [1, 1, 1];
  const digits = hex.trim().replace(/^#/, "");
  // #rgb and #rgba expand to their doubled-digit form. #rrggbb and #rrggbbaa
  // drop the alpha channel, which a vertex colour has nowhere to put.
  const body = digits.length === 3 || digits.length === 4
    ? digits.slice(0, 3).split("").map((digit) => digit + digit).join("")
    : digits.length === 6 || digits.length === 8 ? digits.slice(0, 6) : null;
  if (body === null || !/^[0-9a-f]{6}$/i.test(body)) return [1, 1, 1];
  return [0, 2, 4].map((offset) => parseInt(body.slice(offset, offset + 2), 16) / 255);
}

/**
 * The longest integration step the solver will take. Semi-implicit Euler is
 * only first-order accurate, so a single long step drops a particle visibly
 * further than the same fall taken in short ones. Substepping at a fixed rate
 * makes a 30fps machine and a 144fps machine see the same effect, which is the
 * whole reason the simulation lives here instead of in the frame callback.
 */
const MAX_STEP_SECONDS = 1 / 60;

/**
 * The most substeps one `update` may take. A tab that was backgrounded reports
 * a huge `dt` on its first frame back; spending a second integrating an effect
 * nobody is looking at would stall the frame that has to catch up.
 */
const MAX_SUBSTEPS = 16;

export function createVfx({ capacity = VFX_CAPACITY, random = Math.random } = {}) {
  const limit = Math.max(1, Math.floor(capacity));
  // Live particles, oldest first. A spawn into a full pool recycles the oldest
  // slot: the newest event is the one the player is looking at, so dropping it
  // in favour of a long-lived ember left over from a previous minute is the
  // wrong trade.
  const particles = [];

  function spawn(spec = {}) {
    const life = Number(spec.life) || 0;
    const particle = {
      x: Number(spec.x) || 0,
      y: Number(spec.y) || 0,
      z: Number(spec.z) || 0,
      vx: Number(spec.vx) || 0,
      vy: Number(spec.vy) || 0,
      vz: Number(spec.vz) || 0,
      life,
      // The span is the life this particle was born with, kept so the fade can
      // be read off the remaining life. It is deliberately not a spec field: a
      // caller that set it independently could start a particle already faded.
      span: life,
      size: Number(spec.size) || 0,
      growth: Number(spec.growth) || 0,
      r: clamp01(spec.r),
      g: clamp01(spec.g),
      b: clamp01(spec.b),
      alpha: clamp01(spec.alpha),
      additive: spec.additive === true,
      drag: Number(spec.drag) || 0,
      gravity: Number(spec.gravity) || 0,
    };
    if (particle.life <= 0) return null;
    if (particles.length >= limit) particles.shift();
    particles.push(particle);
    return particle;
  }

  /**
   * Advance every particle and retire the expired ones.
   *
   * Returns the number of particles retired, which is what the frame uses to
   * decide whether anything needs re-uploading.
   */
  function update(dt) {
    const total = Number(dt);
    if (!(total > 0)) return 0;
    const steps = Math.min(Math.max(Math.ceil(total / MAX_STEP_SECONDS), 1), MAX_SUBSTEPS);
    const step = total / steps;
    let retired = 0;
    for (let pass = 0; pass < steps; pass += 1) {
      for (let index = particles.length - 1; index >= 0; index -= 1) {
        const particle = particles[index];
        particle.life -= step;
        if (particle.life <= 0) {
          particles.splice(index, 1);
          retired += 1;
          continue;
        }
        // An exponential decay rather than a per-frame multiplier, so the
        // velocity a particle ends up with does not depend on the step size.
        const decay = Math.exp(-particle.drag * step);
        particle.vx *= decay;
        particle.vz *= decay;
        particle.vy = particle.vy * decay - particle.gravity * step;
        particle.x += particle.vx * step;
        particle.y += particle.vy * step;
        particle.z += particle.vz * step;
        if (particle.growth !== 0) {
          particle.size += particle.growth * step;
          if (particle.size < 0) particle.size = 0;
        }
      }
    }
    return retired;
  }

  function clear() {
    particles.length = 0;
  }

  return Object.freeze({
    spawn,
    update,
    clear,
    random: () => random(),
    get particles() {
      return particles;
    },
    get count() {
      return particles.length;
    },
  });
}

/** A point inside a horizontal disc of `radius`, drawn from the emitter's own random source. */
function scatterXZ(vfx, x, y, z, radius) {
  const angle = vfx.random() * Math.PI * 2;
  const distance = Math.sqrt(vfx.random()) * radius;
  return {
    x: x + Math.cos(angle) * distance,
    y: y + vfx.random() * 0.1,
    z: z + Math.sin(angle) * distance,
  };
}

/**
 * Fire on a burning body. Additive and short-lived, so overlapping puffs build
 * a bright core instead of a flat orange card, and the colour is sampled across
 * the ember ramp so the plume has internal variation.
 *
 * `spread` is the radius of the disc the particles land in, and `height` is how
 * far up the body that disc is stacked. Both matter more than they look: a
 * particle spawned inside a mob is behind the mob's own front faces, so the depth
 * test discards it against the body it is meant to be licking, and a ring at one
 * height reads as a hoop around the waist rather than as a body alight. Callers
 * pass the body's own measurements (see `MOB_BODY`).
 */
export function emitFlame(vfx, x, y, z, count = 1, spread = 0.22, height = 0) {
  for (let index = 0; index < count; index += 1) {
    const heat = vfx.random();
    const point = scatterXZ(vfx, x, y, z, spread);
    const span = 0.3 + vfx.random() * 0.28;
    vfx.spawn({
      ...point,
      // Weighted toward the bottom of the body, the way a flame actually burns:
      // it is fed at the base and thins out before it reaches the head. A square
      // biases the spread low without needing a second draw.
      y: point.y + height * (0.1 + 0.9 * vfx.random() ** 2),
      vx: (vfx.random() - 0.5) * 0.3,
      vy: 1.2 + vfx.random() * 1.1,
      vz: (vfx.random() - 0.5) * 0.3,
      life: span,
      size: 0.26 + vfx.random() * 0.18,
      growth: -0.22,
      r: FLAME_COLOR_LOW[0],
      g: FLAME_COLOR_LOW[1] + (FLAME_COLOR_HIGH[1] - FLAME_COLOR_LOW[1]) * heat,
      b: FLAME_COLOR_LOW[2] + (FLAME_COLOR_HIGH[2] - FLAME_COLOR_LOW[2]) * heat,
      alpha: 0.92,
      additive: true,
      drag: 1.2,
      // Buoyancy is measured against drag, so this is a terminal velocity of
      // 2.6/1.2 blocks per second: the launch speed decays into a steady climb
      // rather than coasting to a stop.
      gravity: -2.6,
    });
  }
}

/**
 * Smoke off the same fire. Blended rather than additive, slower, wider and
 * longer-lived than the flame that fed it, so the two read as one column.
 */
export function emitSmoke(vfx, x, y, z, count = 1, spread = 0.24) {
  for (let index = 0; index < count; index += 1) {
    const shade = 0.75 + vfx.random() * 0.5;
    const point = scatterXZ(vfx, x, y, z, spread);
    const span = 0.9 + vfx.random() * 0.6;
    vfx.spawn({
      ...point,
      vx: (vfx.random() - 0.5) * 0.3 + 0.12,
      vy: 0.55 + vfx.random() * 0.35,
      vz: (vfx.random() - 0.5) * 0.3,
      life: span,
      size: 0.2 + vfx.random() * 0.12,
      growth: 0.34,
      r: SMOKE_COLOR[0] * shade,
      g: SMOKE_COLOR[1] * shade,
      b: SMOKE_COLOR[2] * shade,
      alpha: 0.4,
      additive: false,
      drag: 0.9,
      gravity: -0.35,
    });
  }
}

/**
 * Block debris. Thrown outward from the cell it came from and pulled down, so
 * a mined block throws its own colour at the player instead of a screen-space
 * burst that could be anywhere on the display.
 */
export function emitBlockDebris(vfx, x, y, z, rgb, count = 10, spread = 0.5) {
  const [r, g, b] = rgb;
  for (let index = 0; index < count; index += 1) {
    const angle = vfx.random() * Math.PI * 2;
    const speed = 0.9 + vfx.random() * 1.9;
    const lift = 0.9 + vfx.random() * 1.5;
    const shade = 0.72 + vfx.random() * 0.44;
    const span = 0.5 + vfx.random() * 0.45;
    vfx.spawn({
      x: x + (vfx.random() - 0.5) * spread,
      y: y + (vfx.random() - 0.5) * spread,
      z: z + (vfx.random() - 0.5) * spread,
      vx: Math.cos(angle) * speed,
      vy: lift,
      vz: Math.sin(angle) * speed,
      life: span,
      size: 0.07 + vfx.random() * 0.09,
      growth: -0.02,
      r: r * shade,
      g: g * shade,
      b: b * shade,
      alpha: 1,
      additive: false,
      drag: 1.9,
      gravity: 13,
    });
  }
}

/**
 * A hit landing. Small, fast, additive and gone almost at once, which is what
 * separates a spark from the debris of a broken block.
 */
export function emitImpact(vfx, x, y, z, rgb, count = 6) {
  const [r, g, b] = rgb;
  for (let index = 0; index < count; index += 1) {
    const angle = vfx.random() * Math.PI * 2;
    const lift = (vfx.random() - 0.2) * 1.6;
    const speed = 1.6 + vfx.random() * 2.6;
    const span = 0.14 + vfx.random() * 0.16;
    vfx.spawn({
      x,
      y,
      z,
      vx: Math.cos(angle) * speed,
      vy: lift,
      vz: Math.sin(angle) * speed,
      life: span,
      size: 0.05 + vfx.random() * 0.05,
      growth: -0.1,
      r,
      g,
      b,
      alpha: 0.95,
      additive: true,
      drag: 3.4,
      gravity: 7,
    });
  }
}

/**
 * A body coming apart: a wider, slower, longer-lived puff than a hit spark.
 *
 * The lifetime is the point. A puff that is gone in half a second lands between
 * two frames of attention and reads as the mob blinking out rather than as
 * something happening to it, which is the one impression a death cannot afford.
 */
export function emitDeathPuff(vfx, x, y, z, rgb, count = 14) {
  const [r, g, b] = rgb;
  for (let index = 0; index < count; index += 1) {
    const angle = vfx.random() * Math.PI * 2;
    const speed = 0.7 + vfx.random() * 1.5;
    const shade = 0.7 + vfx.random() * 0.5;
    const span = 0.95 + vfx.random() * 0.7;
    vfx.spawn({
      x: x + (vfx.random() - 0.5) * 0.4,
      y: y + vfx.random() * 0.9,
      z: z + (vfx.random() - 0.5) * 0.4,
      vx: Math.cos(angle) * speed,
      vy: 0.7 + vfx.random() * 1.0,
      vz: Math.sin(angle) * speed,
      life: span,
      size: 0.16 + vfx.random() * 0.18,
      growth: 0.16,
      r: r * shade,
      g: g * shade,
      b: b * shade,
      alpha: 0.85,
      additive: false,
      drag: 2.2,
      gravity: 4.5,
    });
  }
}

/** A pickup drifting up out of the world: a small additive twinkle. */
export function emitSparkle(vfx, x, y, z, rgb, count = 5) {
  const [r, g, b] = rgb;
  for (let index = 0; index < count; index += 1) {
    const point = scatterXZ(vfx, x, y, z, 0.18);
    const span = 0.3 + vfx.random() * 0.25;
    vfx.spawn({
      ...point,
      vx: (vfx.random() - 0.5) * 0.5,
      vy: 1.1 + vfx.random() * 0.8,
      vz: (vfx.random() - 0.5) * 0.5,
      life: span,
      size: 0.06 + vfx.random() * 0.05,
      growth: -0.05,
      r,
      g,
      b,
      alpha: 0.9,
      additive: true,
      drag: 1.6,
      gravity: -0.4,
    });
  }
}

// Two triangles, wound so the face is visible from the camera side. The corners
// are ordered once here rather than per emitter, which is what lets the batch
// stay a flat array push instead of a per-particle allocation.
const QUAD_CORNERS = [
  [-1, -1],
  [1, -1],
  [1, 1],
  [-1, -1],
  [1, 1],
  [-1, 1],
];

/**
 * Emit one camera-facing quad per particle into the terrain program's own
 * vertex layout, so a particle rides the buffers and the shader that everything
 * else already uses instead of needing a second pipeline.
 *
 * `right` and `up` are the camera basis, which the frame already has. Baking the
 * billboard on the CPU is what keeps a particle off the model-matrix path the
 * renderer does not have.
 *
 * The light attribute is unused for a particle, so it carries the two values
 * the shader cannot otherwise know: the faded alpha, and whether this particle
 * is additive.
 */
export function appendVfxQuads(batches, particles, right, up) {
  const { positions, colors, lights, normals, uvs, tiles } = batches;
  for (const particle of particles) {
    const half = particle.size * 0.5;
    const fade = particle.life / particle.span;
    const alpha = particle.alpha * fade;
    const additive = particle.additive ? 1 : 0;
    const [r, g, b] = [particle.r, particle.g, particle.b];
    for (const [u, v] of QUAD_CORNERS) {
      positions.push(
        particle.x + right[0] * u * half + up[0] * v * half,
        particle.y + right[1] * u * half + up[1] * v * half,
        particle.z + right[2] * u * half + up[2] * v * half,
      );
      colors.push(r, g, b);
      lights.push(alpha, additive);
      normals.push(0, 1, 0);
      uvs.push((u + 1) * 0.5, (v + 1) * 0.5);
      tiles.push(0, 0, 1, 1);
    }
  }
  return particles.length * 6;
}
