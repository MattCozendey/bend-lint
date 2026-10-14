// High-definition procedural material synthesis for the block atlas.
//
// Every atlas tile is painted by a dedicated material painter instead of an
// authored 16x16 macro pattern with noise laid over it. The old approach was a
// fixed pixel grid magnified onto a 64-texel tile, so every surface read as a
// few blurred colour cells. A painter here builds the material the way it is
// actually structured: cobblestone is a Worley partition into rounded stones
// with mortar between them, bark is a field of vertical fissures, grass is a
// few thousand individual blades, leaves are overlapping lens-shaped leaves,
// ores are faceted crystals embedded in the same stone the stone block uses.
//
// Each painter writes a colour field and a height field. The height drives a
// baked top-left emboss and a cavity term, and it also agrees with the
// luminance the terrain shader derives its derivative bump from, so the baked
// relief and the lit relief point the same way.
//
// This is presentation only: the atlas is not a world rule, and nothing here
// reads or decides game state. Everything is a pure function of the painter
// name, the tile size, the seed and the palette, so the same block always gets
// the same texture and the atlas texel probe stays deterministic.

const TAU = Math.PI * 2;

// ---------------------------------------------------------------------------
// Hashing and tileable noise
// ---------------------------------------------------------------------------

/** 32-bit integer hash of a lattice point, stable across platforms. */
export function hashInt(x, y, seed) {
  let value = Math.imul(x | 0, 0x27d4eb2d) ^ Math.imul(y | 0, 0x165667b1) ^ Math.imul(seed | 0, 0x9e3779b1);
  value = Math.imul(value ^ (value >>> 15), 0x85ebca6b);
  value = Math.imul(value ^ (value >>> 13), 0xc2b2ae35);
  return (value ^ (value >>> 16)) >>> 0;
}

/** Hash of a lattice point in 0..1. */
export function hash01(x, y, seed) {
  return hashInt(x, y, seed) / 4294967295;
}

/** Deterministic stream of 0..1 values for scattering features. */
export function createRandom(seed) {
  let state = hashInt(seed, 0x5bd1e995, 0x1b873593) || 1;
  return () => {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return (state >>> 0) / 4294967296;
  };
}

function wrapIndex(value, period) {
  return ((value % period) + period) % period;
}

const GRADIENT_COUNT = 32;
const GRADIENT_X = new Float32Array(GRADIENT_COUNT);
const GRADIENT_Y = new Float32Array(GRADIENT_COUNT);
for (let index = 0; index < GRADIENT_COUNT; index += 1) {
  GRADIENT_X[index] = Math.cos((index / GRADIENT_COUNT) * TAU);
  GRADIENT_Y[index] = Math.sin((index / GRADIENT_COUNT) * TAU);
}

// Gradient noise is the hot path of every painter, so lattice hashing goes
// through a per-seed permutation table instead of the integer hash. Lattice
// coordinates are always wrapped into their period first, and every period a
// painter uses stays below 256, so the table lookup is exact.
const PERMUTATIONS = new Map();

function permutationFor(seed) {
  let table = PERMUTATIONS.get(seed);
  if (table !== undefined) return table;
  table = new Uint8Array(512);
  for (let index = 0; index < 256; index += 1) table[index] = index;
  for (let index = 255; index > 0; index -= 1) {
    const other = hashInt(index, 0x3c6ef372, seed) % (index + 1);
    const swap = table[index];
    table[index] = table[other];
    table[other] = swap;
  }
  for (let index = 0; index < 256; index += 1) table[index + 256] = table[index];
  PERMUTATIONS.set(seed, table);
  return table;
}

function noiseWithTable(x, y, periodX, periodY, table) {
  const cellX = Math.floor(x);
  const cellY = Math.floor(y);
  const localX = x - cellX;
  const localY = y - cellY;
  let x0 = cellX % periodX;
  if (x0 < 0) x0 += periodX;
  let y0 = cellY % periodY;
  if (y0 < 0) y0 += periodY;
  const x1 = x0 + 1 === periodX ? 0 : x0 + 1;
  const y1 = y0 + 1 === periodY ? 0 : y0 + 1;
  const row0 = table[x0 & 255];
  const row1 = table[x1 & 255];
  const ga = table[row0 + (y0 & 255)] & (GRADIENT_COUNT - 1);
  const gb = table[row1 + (y0 & 255)] & (GRADIENT_COUNT - 1);
  const gc = table[row0 + (y1 & 255)] & (GRADIENT_COUNT - 1);
  const gd = table[row1 + (y1 & 255)] & (GRADIENT_COUNT - 1);
  const a = GRADIENT_X[ga] * localX + GRADIENT_Y[ga] * localY;
  const b = GRADIENT_X[gb] * (localX - 1) + GRADIENT_Y[gb] * localY;
  const c = GRADIENT_X[gc] * localX + GRADIENT_Y[gc] * (localY - 1);
  const d = GRADIENT_X[gd] * (localX - 1) + GRADIENT_Y[gd] * (localY - 1);
  const u = localX * localX * localX * (localX * (localX * 6 - 15) + 10);
  const v = localY * localY * localY * (localY * (localY * 6 - 15) + 10);
  const top = a + (b - a) * u;
  const bottom = c + (d - c) * u;
  const value = (top + (bottom - top) * v) * 1.41421356;
  return value < -1 ? -1 : value > 1 ? 1 : value;
}

/**
 * Tileable gradient noise in roughly -1..1. The lattice wraps at `periodX` and
 * `periodY`, so sampling a tile at an integer frequency with the same period
 * produces a texture with no seam. Unequal periods give stretched noise, which
 * is what fibres and fissures are made of.
 */
export function gradientNoise(x, y, periodX, periodY, seed) {
  return noiseWithTable(x, y, periodX, periodY, permutationFor(seed | 0));
}

// fbm is called once per texel per layer, so the per-octave tables are looked
// up once per seed rather than once per sample.
const OCTAVE_TABLES = new Map();

function octaveTables(seed, octaves) {
  let tables = OCTAVE_TABLES.get(seed);
  if (tables === undefined) {
    tables = [];
    OCTAVE_TABLES.set(seed, tables);
  }
  while (tables.length < octaves) tables.push(permutationFor((seed + tables.length * 1013) | 0));
  return tables;
}

/**
 * Tileable fractal noise over a unit tile. `u`/`v` are tile coordinates in
 * 0..1 and `frequencyX`/`frequencyY` integers, so every octave wraps exactly.
 */
export function fbm(u, v, frequencyX, frequencyY, octaves, seed, gain = 0.5) {
  const tables = octaveTables(seed, octaves);
  let total = 0;
  let amplitude = 1;
  let norm = 0;
  let fx = frequencyX;
  let fy = frequencyY;
  for (let octave = 0; octave < octaves; octave += 1) {
    total += noiseWithTable(u * fx, v * fy, fx, fy, tables[octave]) * amplitude;
    norm += amplitude;
    amplitude *= gain;
    fx *= 2;
    fy *= 2;
  }
  return total / norm;
}

/**
 * Tileable Worley noise. Writes the distance to the nearest and second-nearest
 * feature point, the nearest point's cell id and its offset into `out`, so the
 * caller can shade a cell (a stone, a clod, a crystal) as one object.
 */
export function worley(u, v, frequency, seed, out, jitter = 1) {
  const x = u * frequency;
  const y = v * frequency;
  const cellX = Math.floor(x);
  const cellY = Math.floor(y);
  // Squared distances inside the search; one square root each at the end.
  let f1 = 4096;
  let f2 = 4096;
  let nearestCell = 0;
  let nearestX = 0;
  let nearestY = 0;
  let nearestWrappedX = 0;
  let nearestWrappedY = 0;
  for (let offsetY = -1; offsetY <= 1; offsetY += 1) {
    for (let offsetX = -1; offsetX <= 1; offsetX += 1) {
      const sampleX = cellX + offsetX;
      const sampleY = cellY + offsetY;
      const wrappedX = wrapIndex(sampleX, frequency);
      const wrappedY = wrapIndex(sampleY, frequency);
      const hash = hashInt(wrappedX, wrappedY, seed);
      const pointX = sampleX + 0.5 + (((hash & 0xffff) / 65535) - 0.5) * jitter;
      const pointY = sampleY + 0.5 + (((hash >>> 16) / 65535) - 0.5) * jitter;
      const dx = pointX - x;
      const dy = pointY - y;
      const distance = dx * dx + dy * dy;
      if (distance < f1) {
        f2 = f1;
        f1 = distance;
        nearestCell = 1;
        nearestWrappedX = wrappedX;
        nearestWrappedY = wrappedY;
        nearestX = dx;
        nearestY = dy;
      } else if (distance < f2) {
        f2 = distance;
      }
    }
  }
  out.f1 = Math.sqrt(f1);
  out.f2 = Math.sqrt(f2);
  out.id = nearestCell === 1 ? hashInt(nearestWrappedX, nearestWrappedY, seed + 77) : 0;
  out.dx = nearestX;
  out.dy = nearestY;
  return out;
}

export function smoothstep(edge0, edge1, value) {
  const t = Math.max(0, Math.min(1, (value - edge0) / (edge1 - edge0)));
  return t * t * (3 - 2 * t);
}

function clamp01(value) {
  return value < 0 ? 0 : value > 1 ? 1 : value;
}

// ---------------------------------------------------------------------------
// Colour helpers
// ---------------------------------------------------------------------------

const HEX_CACHE = new Map();

/** `#rrggbb` to linear-free 0..1 sRGB channels. */
export function hexToRgb(hex) {
  const cached = HEX_CACHE.get(hex);
  if (cached !== undefined) return cached;
  const match = /^#([0-9a-f]{6})$/i.exec(String(hex));
  if (match === null) throw new Error(`Invalid palette colour ${hex}.`);
  const value = Number.parseInt(match[1], 16);
  const rgb = Object.freeze([((value >> 16) & 0xff) / 255, ((value >> 8) & 0xff) / 255, (value & 0xff) / 255]);
  HEX_CACHE.set(hex, rgb);
  return rgb;
}

/** A colour ramp from evenly spaced palette entries. */
function ramp(colors) {
  const stops = colors.map(hexToRgb);
  const last = stops.length - 1;
  return (t, out) => {
    const position = clamp01(t) * last;
    const index = Math.min(last - 1, Math.floor(position));
    const local = position - index;
    const a = stops[index];
    const b = stops[index + 1];
    out[0] = a[0] + (b[0] - a[0]) * local;
    out[1] = a[1] + (b[1] - a[1]) * local;
    out[2] = a[2] + (b[2] - a[2]) * local;
    return out;
  };
}

// ---------------------------------------------------------------------------
// Tile surface
// ---------------------------------------------------------------------------

/**
 * A tile being painted: an RGB field and a height field, both size x size.
 * `wrapX`/`wrapY` say whether the material tiles along that axis, which decides
 * whether strokes and the emboss wrap around the edge or clamp at it.
 */
export class MaterialSurface {
  constructor(size) {
    this.size = size;
    this.color = new Float32Array(size * size * 3);
    this.height = new Float32Array(size * size);
    this.wrapX = true;
    this.wrapY = true;
  }

  index(x, y) {
    const size = this.size;
    const px = this.wrapX ? wrapIndex(x, size) : Math.max(0, Math.min(size - 1, x));
    const py = this.wrapY ? wrapIndex(y, size) : Math.max(0, Math.min(size - 1, y));
    return py * size + px;
  }

  inside(x, y) {
    return (this.wrapX || (x >= 0 && x < this.size)) && (this.wrapY || (y >= 0 && y < this.size));
  }

  /** Visit every texel with its tile coordinates. */
  each(visit) {
    const size = this.size;
    for (let y = 0; y < size; y += 1) {
      const v = (y + 0.5) / size;
      for (let x = 0; x < size; x += 1) {
        visit(x, y, (x + 0.5) / size, v, y * size + x);
      }
    }
  }

  set(index, rgb, height) {
    const offset = index * 3;
    this.color[offset] = rgb[0];
    this.color[offset + 1] = rgb[1];
    this.color[offset + 2] = rgb[2];
    if (height !== undefined) this.height[index] = height;
  }

  blend(index, rgb, amount, height) {
    if (amount <= 0) return;
    const offset = index * 3;
    const keep = 1 - amount;
    this.color[offset] = this.color[offset] * keep + rgb[0] * amount;
    this.color[offset + 1] = this.color[offset + 1] * keep + rgb[1] * amount;
    this.color[offset + 2] = this.color[offset + 2] * keep + rgb[2] * amount;
    if (height !== undefined) this.height[index] = this.height[index] * keep + height * amount;
  }

  scale(index, factor) {
    const offset = index * 3;
    this.color[offset] *= factor;
    this.color[offset + 1] *= factor;
    this.color[offset + 2] *= factor;
  }

  /**
   * Anti-aliased tapered stroke. Coverage falls off over one texel at the edge,
   * so a blade or fibre is soft at its border rather than a hard pixel step.
   */
  stroke(x0, y0, x1, y1, width0, width1, colorAt, heightAt, opacity = 1) {
    const minX = Math.floor(Math.min(x0, x1) - Math.max(width0, width1) - 1);
    const maxX = Math.ceil(Math.max(x0, x1) + Math.max(width0, width1) + 1);
    const minY = Math.floor(Math.min(y0, y1) - Math.max(width0, width1) - 1);
    const maxY = Math.ceil(Math.max(y0, y1) + Math.max(width0, width1) + 1);
    const dx = x1 - x0;
    const dy = y1 - y0;
    const lengthSquared = Math.max(1e-6, dx * dx + dy * dy);
    const rgb = [0, 0, 0];
    for (let y = minY; y <= maxY; y += 1) {
      for (let x = minX; x <= maxX; x += 1) {
        if (!this.inside(x, y)) continue;
        const px = x + 0.5 - x0;
        const py = y + 0.5 - y0;
        const t = Math.max(0, Math.min(1, (px * dx + py * dy) / lengthSquared));
        const ex = px - dx * t;
        const ey = py - dy * t;
        const distance = Math.sqrt(ex * ex + ey * ey);
        const halfWidth = (width0 + (width1 - width0) * t) * 0.5;
        const coverage = clamp01(halfWidth + 0.5 - distance) * opacity;
        if (coverage <= 0) continue;
        const index = this.index(x, y);
        colorAt(t, (distance / Math.max(0.5, halfWidth)), rgb);
        this.blend(index, rgb, coverage, heightAt(t, distance / Math.max(0.5, halfWidth)));
      }
    }
  }

  /**
   * Baked relief from the height field: a top-left light, so a raised texel
   * catches light on its upper-left flank and throws shade on its lower-right.
   * The difference is taken over two texels so it describes the material's
   * shape, not per-texel noise, and is scaled by the tile size so the result
   * does not depend on the resolution the tile is painted at.
   */
  emboss(strength, cavity = 0) {
    const size = this.size;
    const scale = size / 32;
    const source = this.height;
    const factors = new Float32Array(size * size);
    for (let y = 0; y < size; y += 1) {
      for (let x = 0; x < size; x += 1) {
        // The normal of a height field tilts against its gradient, so a flank
        // that rises towards the lower right faces the upper-left light.
        const upperLeft = source[this.index(x - 1, y - 1)];
        const lowerRight = source[this.index(x + 1, y + 1)];
        const slope = (lowerRight - upperLeft) * scale;
        const index = y * size + x;
        const ambient = 1 - cavity * (1 - source[index]);
        factors[index] = Math.max(0.35, Math.min(1.6, (1 + strength * slope) * ambient));
      }
    }
    for (let index = 0; index < size * size; index += 1) this.scale(index, factors[index]);
  }

  /** Box blur of the height field, used to round off stroke-built relief. */
  smoothHeight(radius = 1) {
    const size = this.size;
    const source = this.height.slice();
    for (let y = 0; y < size; y += 1) {
      for (let x = 0; x < size; x += 1) {
        let total = 0;
        let count = 0;
        for (let oy = -radius; oy <= radius; oy += 1) {
          for (let ox = -radius; ox <= radius; ox += 1) {
            total += source[this.index(x + ox, y + oy)];
            count += 1;
          }
        }
        this.height[y * size + x] = total / count;
      }
    }
  }

  /** Final RGBA bytes with a uniform alpha. */
  toRgba(alpha = 1) {
    const size = this.size;
    const out = new Uint8ClampedArray(size * size * 4);
    const alphaByte = Math.round(clamp01(alpha) * 255);
    for (let index = 0; index < size * size; index += 1) {
      out[index * 4] = Math.round(clamp01(this.color[index * 3]) * 255);
      out[index * 4 + 1] = Math.round(clamp01(this.color[index * 3 + 1]) * 255);
      out[index * 4 + 2] = Math.round(clamp01(this.color[index * 3 + 2]) * 255);
      out[index * 4 + 3] = alphaByte;
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// Shared material layers
// ---------------------------------------------------------------------------

// Base layers that several tiles embed (the stone every ore sits in, the soil
// under a grass side) are painted once per size, seed and palette and copied.
const LAYER_CACHE = new Map();

function paintCachedLayer(surface, painter, palette, seed) {
  const key = `${painter.name}:${surface.size}:${seed}:${JSON.stringify(palette)}`;
  let layer = LAYER_CACHE.get(key);
  if (layer === undefined) {
    const source = new MaterialSurface(surface.size);
    source.wrapX = surface.wrapX;
    source.wrapY = surface.wrapY;
    painter(source, palette, seed);
    layer = { color: source.color, height: source.height };
    LAYER_CACHE.set(key, layer);
  }
  surface.color.set(layer.color);
  surface.height.set(layer.height);
}

const WORLEY = { f1: 0, f2: 0, id: 0, dx: 0, dy: 0 };

/** Natural stone: warped soft blotches, partial hairline cracks, mineral grain. */
function paintStoneLayer(surface, palette, seed) {
  const shade = ramp([palette.dark, palette.base, palette.light]);
  const crack = hexToRgb(palette.crack);
  const rgb = [0, 0, 0];
  surface.each((x, y, u, v, index) => {
    const warpU = fbm(u, v, 3, 3, 3, seed + 1) * 0.1;
    const warpV = fbm(u, v, 3, 3, 3, seed + 2) * 0.1;
    const body = fbm(u + warpU, v + warpV, 4, 4, 5, seed);
    const blotch = fbm(u, v, 2, 2, 3, seed + 5);
    const grain = fbm(u, v, 16, 16, 2, seed + 13);
    // Hairline fractures only along a minority of cell borders, and only where
    // a slow mask allows it: a crack on every border reads as dried mud.
    worley(u + warpU, v + warpV, 2, seed + 9, WORLEY, 0.9);
    const edge = WORLEY.f2 - WORLEY.f1;
    const crackReach = smoothstep(0.18, 0.4, fbm(u, v, 3, 3, 2, seed + 21));
    const crackDepth = (1 - smoothstep(0.0, 0.022, edge)) * crackReach;
    const vein = smoothstep(0.55, 0.9, 1 - Math.abs(fbm(u + warpV, v + warpU, 3, 3, 3, seed + 31)));
    const tone = 0.52 + body * 0.3 + blotch * 0.24 + grain * 0.07 - vein * 0.08;
    const height = clamp01(0.5 + body * 0.2 + blotch * 0.08 + grain * 0.08 - crackDepth * 0.12);
    shade(clamp01(tone), rgb);
    surface.set(index, rgb, height);
    if (crackDepth > 0) surface.blend(index, crack, crackDepth * 0.6);
    // A slow warm/cool drift keeps a stone face from reading as flat grey paint.
    const drift = fbm(u, v, 2, 2, 2, seed + 41) * 0.035;
    surface.color[index * 3] *= 1 + drift;
    surface.color[index * 3 + 2] *= 1 - drift;
    worley(u, v, 12, seed + 17, WORLEY, 1);
    const speck = hash01(WORLEY.id, 3, seed);
    if (WORLEY.f1 < 0.2 && speck < 0.2) {
      const amount = (1 - WORLEY.f1 / 0.2) * 0.35;
      surface.blend(index, hexToRgb(speck < 0.1 ? palette.light : palette.dark), amount);
    }
  });
}

/** Soil: clumps, embedded pebbles and small pores. */
function paintDirtLayer(surface, palette, seed) {
  const shade = ramp([palette.dark, palette.base, palette.light]);
  const pebble = ramp([palette.pebbleDark, palette.pebble, palette.pebbleLight]);
  const rgb = [0, 0, 0];
  surface.each((x, y, u, v, index) => {
    const warpU = fbm(u, v, 4, 4, 2, seed + 1) * 0.06;
    const warpV = fbm(u, v, 4, 4, 2, seed + 2) * 0.06;
    const body = fbm(u + warpU, v + warpV, 5, 5, 5, seed);
    const clump = 1 - Math.abs(fbm(u + warpU, v + warpV, 8, 8, 3, seed + 3));
    const crumbs = fbm(u, v, 20, 20, 1, seed + 4);
    const height = clamp01(0.45 + body * 0.26 + (clump - 0.6) * 0.3 + crumbs * 0.1);
    shade(clamp01(0.48 + body * 0.32 + (clump - 0.6) * 0.22 + crumbs * 0.12), rgb);
    surface.set(index, rgb, height);

    worley(u, v, 5, seed + 7, WORLEY, 0.8);
    const pebbleChance = hash01(WORLEY.id, 1, seed);
    const radius = 0.13 + hash01(WORLEY.id, 2, seed) * 0.12;
    // A pebble is not a disc: its outline wanders with the angle around it.
    const outline = 1 + 0.22 * gradientNoise(
      Math.cos(Math.atan2(WORLEY.dy, WORLEY.dx)) * 1.3 + (WORLEY.id % 97),
      Math.sin(Math.atan2(WORLEY.dy, WORLEY.dx)) * 1.3,
      256, 256, seed + 8,
    );
    const pebbleDistance = WORLEY.f1 / outline;
    if (pebbleChance < 0.34 && pebbleDistance < radius + 0.08) {
      if (pebbleDistance < radius) {
        const dome = Math.sqrt(clamp01(1 - (pebbleDistance / radius) ** 2));
        // Lit from the upper left. `dx`/`dy` point from the texel to the pebble
        // centre, so a texel up and to the left of it has a positive sum.
        const facing = (WORLEY.dx + WORLEY.dy) / (radius * 1.4142);
        const light = clamp01(0.3 + facing * 0.28 + dome * 0.12 + (hash01(WORLEY.id, 5, seed) - 0.5) * 0.3
          + fbm(u, v, 24, 24, 1, seed + 6) * 0.12);
        pebble(light, rgb);
        const coverage = clamp01((radius - pebbleDistance) * 60);
        surface.blend(index, rgb, coverage, 0.62 + dome * 0.35);
      } else if (WORLEY.dx + WORLEY.dy < 0) {
        // Contact shadow on the lower-right side only.
        const fade = 1 - (pebbleDistance - radius) / 0.08;
        surface.scale(index, 1 - fade * 0.3);
      }
    }

    worley(u, v, 16, seed + 11, WORLEY, 1);
    if (WORLEY.f1 < 0.22 && hash01(WORLEY.id, 7, seed) < 0.3) {
      surface.scale(index, 0.74 + WORLEY.f1 * 1.2);
      surface.height[index] *= 0.75;
    }
  });
}

/** Wood grain along the vertical (`vertical`) or horizontal axis of a board. */
function woodGrain(u, v, seed, vertical) {
  const along = vertical ? v : u;
  const across = vertical ? u : v;
  const wobble = fbm(vertical ? across : along, vertical ? along : across, 2, 2, 2, seed + 3) * 0.05;
  const fibre = fbm(
    vertical ? across + wobble : along,
    vertical ? along : across + wobble,
    vertical ? 24 : 2,
    vertical ? 2 : 24,
    2,
    seed,
  );
  const figure = Math.sin((across * 10 + fbm(u, v, 3, 3, 2, seed + 9) * 1.8) * TAU) * 0.5;
  return fibre * 0.65 + figure * 0.35;
}

/**
 * Planks. `boards` boards along the axis perpendicular to the grain, with a dark
 * seam between them and a per-board tone, so a plank face reads as separate
 * boards instead of one sheet.
 */
function paintPlanksLayer(surface, palette, seed, { boards = 4, vertical = false, stagger = true } = {}) {
  const shade = ramp([palette.dark, palette.base, palette.light]);
  const seam = hexToRgb(palette.seam);
  const rgb = [0, 0, 0];
  surface.each((x, y, u, v, index) => {
    const across = vertical ? u : v;
    const along = vertical ? v : u;
    const board = Math.floor(across * boards);
    const local = across * boards - board;
    const tone = (hash01(board, 9, seed) - 0.5) * 0.22;
    const grain = woodGrain(u, v + board * 0.37, seed + board * 31, vertical);
    let height = clamp01(0.55 + grain * 0.22 + tone);
    const seamDistance = Math.min(local, 1 - local) * surface.size / boards;
    const seamDepth = 1 - smoothstep(0.6, 1.8, seamDistance);
    // A butt joint across the board, staggered between boards, stops a plank
    // wall from reading as continuous stripes.
    const jointAt = stagger ? hash01(board, 4, seed) : 2;
    const jointDistance = Math.abs(along - jointAt) * surface.size;
    const jointDepth = jointAt < 1 ? 1 - smoothstep(0.5, 1.6, jointDistance) : 0;
    const depth = Math.max(seamDepth, jointDepth);
    height = clamp01(height * (1 - depth * 0.7));
    shade(height, rgb);
    surface.set(index, rgb, height);
    if (depth > 0) surface.blend(index, seam, depth * 0.85);
    // Upper edge of each board catches light; lower edge sits in shade.
    const edgeLight = 1 - smoothstep(1.2, 3.2, local * surface.size / boards);
    const edgeShade = 1 - smoothstep(1.2, 3.2, (1 - local) * surface.size / boards);
    surface.scale(index, 1 + edgeLight * 0.1 - edgeShade * 0.12);
  });
}

/** Woven cloth: over-under threads with fibre noise and soft folds. */
function paintFabricLayer(surface, palette, seed, threads) {
  const shade = ramp([palette.dark, palette.base, palette.light]);
  const rgb = [0, 0, 0];
  surface.each((x, y, u, v, index) => {
    const tu = u * threads;
    const tv = v * threads;
    const cellU = Math.floor(tu);
    const cellV = Math.floor(tv);
    const over = (cellU + cellV) % 2 === 0;
    const profile = Math.sin((over ? tv - cellV : tu - cellU) * Math.PI);
    const fibre = fbm(u, v, threads, threads, 1, seed + 4) * 0.12;
    const fold = fbm(u, v, 2, 3, 3, seed);
    const wear = fbm(u, v, 6, 6, 3, seed + 8);
    const height = clamp01(0.4 + profile * 0.2 + fibre + fold * 0.18);
    shade(clamp01(0.45 + fold * 0.32 + wear * 0.14 + (profile - 0.5) * 0.12 + fibre * 0.4), rgb);
    surface.set(index, rgb, height);
  });
}

/** Skin: soft mottling, faint pores and larger blotches. */
function paintSkinLayer(surface, palette, seed) {
  const shade = ramp([palette.dark, palette.base, palette.light]);
  const rgb = [0, 0, 0];
  surface.each((x, y, u, v, index) => {
    const mottle = fbm(u, v, 3, 3, 4, seed);
    const fine = fbm(u, v, 20, 20, 1, seed + 3);
    worley(u, v, 14, seed + 5, WORLEY, 1);
    const pore = WORLEY.f1 < 0.12 && hash01(WORLEY.id, 1, seed) < 0.4 ? (1 - WORLEY.f1 / 0.12) * 0.12 : 0;
    const height = clamp01(0.5 + mottle * 0.25 + fine * 0.1 - pore);
    shade(clamp01(0.5 + mottle * 0.35 + fine * 0.08 - pore), rgb);
    surface.set(index, rgb, height);
  });
}

/** Smooth-stone bricks, used by furnaces. */
function paintStoneBricksLayer(surface, palette, seed, rows = 4) {
  const shade = ramp([palette.dark, palette.base, palette.light]);
  const mortar = hexToRgb(palette.mortar);
  const rgb = [0, 0, 0];
  const size = surface.size;
  surface.each((x, y, u, v, index) => {
    const row = Math.floor(v * rows);
    const offset = row % 2 === 0 ? 0 : 0.5;
    const brickU = u * 2 + offset;
    const column = Math.floor(brickU);
    const localU = brickU - column;
    const localV = v * rows - row;
    const tone = (hash01(column, row, seed) - 0.5) * 0.18;
    const body = fbm(u, v, 6, 6, 4, seed + column * 7 + row);
    const edgeDistance = Math.min(localU * size / 2, (1 - localU) * size / 2, localV * size / rows, (1 - localV) * size / rows);
    const gap = 1 - smoothstep(0.8, 2.2, edgeDistance);
    const bevel = smoothstep(2, 5, edgeDistance);
    const height = clamp01((0.5 + body * 0.2 + tone) * (0.55 + bevel * 0.45) * (1 - gap * 0.8));
    shade(clamp01(0.5 + body * 0.28 + tone), rgb);
    surface.set(index, rgb, height);
    if (gap > 0) surface.blend(index, mortar, gap * 0.9);
  });
}

function rect(surface, x0, y0, x1, y1, paint) {
  const size = surface.size;
  const minX = Math.max(0, Math.floor(x0 * size));
  const maxX = Math.min(size, Math.ceil(x1 * size));
  const minY = Math.max(0, Math.floor(y0 * size));
  const maxY = Math.min(size, Math.ceil(y1 * size));
  for (let y = minY; y < maxY; y += 1) {
    for (let x = minX; x < maxX; x += 1) {
      const u = (x + 0.5) / size;
      const v = (y + 0.5) / size;
      paint(x, y, (u - x0) / (x1 - x0), (v - y0) / (y1 - y0), y * size + x, u, v);
    }
  }
}

/** Raised or sunken bevel frame of `width` (tile units) inside a rectangle. */
function bevelFrame(surface, x0, y0, x1, y1, width, strength) {
  rect(surface, x0, y0, x1, y1, (x, y, lu, lv, index, u, v) => {
    const left = u - x0;
    const right = x1 - u;
    const top = v - y0;
    const bottom = y1 - v;
    const nearest = Math.min(left, right, top, bottom);
    if (nearest > width) return;
    const lit = nearest === left || nearest === top;
    surface.scale(index, 1 + (lit ? strength : -strength) * (1 - nearest / width));
  });
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

const STONE_EMBOSS = 0.45;
const STONE_CAVITY = 0.1;

function paintStone(surface, palette, seed) {
  paintCachedLayer(surface, paintStoneLayer, palette, seed);
  surface.emboss(STONE_EMBOSS, STONE_CAVITY);
}

function paintCobblestone(surface, palette, seed) {
  const shade = ramp([palette.dark, palette.base, palette.light]);
  const mortar = hexToRgb(palette.mortar);
  const warm = hexToRgb(palette.warm);
  const rgb = [0, 0, 0];
  surface.each((x, y, u, v, index) => {
    const warpU = fbm(u, v, 4, 4, 2, seed + 1) * 0.045;
    const warpV = fbm(u, v, 4, 4, 2, seed + 2) * 0.045;
    worley(u + warpU, v + warpV, 4, seed, WORLEY, 0.85);
    const edge = WORLEY.f2 - WORLEY.f1;
    const stoneId = WORLEY.id;
    const dome = smoothstep(0.02, 0.34, edge);
    const tone = (hash01(stoneId, 1, seed) - 0.5) * 0.34;
    const grain = fbm(u, v, 16, 16, 3, seed + (stoneId & 1023));
    const chips = fbm(u, v, 24, 24, 1, seed + 9);
    const mortarAmount = 1 - smoothstep(0.02, 0.07, edge);
    const height = clamp01(0.18 + dome * 0.62 + grain * 0.1 + chips * 0.04 - mortarAmount * 0.2);
    shade(clamp01(0.48 + tone + grain * 0.22 + dome * 0.12), rgb);
    surface.set(index, rgb, height);
    if (hash01(stoneId, 2, seed) < 0.3) surface.blend(index, warm, 0.18);
    if (mortarAmount > 0) {
      const gravel = 0.8 + fbm(u, v, 20, 20, 1, seed + 5) * 0.3;
      surface.blend(index, [mortar[0] * gravel, mortar[1] * gravel, mortar[2] * gravel], mortarAmount);
    }
  });
  surface.emboss(1.05, 0.35);
}

function paintDirt(surface, palette, seed) {
  paintCachedLayer(surface, paintDirtLayer, palette, seed);
  surface.emboss(0.6, 0.25);
}

function paintSand(surface, palette, seed) {
  const shade = ramp([palette.dark, palette.base, palette.light]);
  const rgb = [0, 0, 0];
  surface.each((x, y, u, v, index) => {
    const grain = fbm(u, v, 40, 40, 1, seed);
    const drift = fbm(u, v, 4, 4, 3, seed + 1);
    const rippleWarp = fbm(u, v, 2, 2, 2, seed + 2) * 0.12;
    const ripple = Math.sin((v + rippleWarp + u * 0.15) * TAU * 5);
    const height = clamp01(0.5 + grain * 0.14 + drift * 0.16 + ripple * 0.1);
    shade(clamp01(0.5 + grain * 0.2 + drift * 0.24 + ripple * 0.06), rgb);
    surface.set(index, rgb, height);
    worley(u, v, 26, seed + 3, WORLEY, 1);
    const kind = hash01(WORLEY.id, 1, seed);
    if (WORLEY.f1 < 0.22 && kind < 0.2) {
      const color = kind < 0.07 ? palette.speckDark : palette.speckLight;
      surface.blend(index, hexToRgb(color), (1 - WORLEY.f1 / 0.2) * 0.6);
    }
  });
  surface.emboss(0.35, 0.1);
}

function paintGrassTop(surface, palette, seed) {
  const shade = ramp([palette.deep, palette.dark, palette.base, palette.light, palette.tip]);
  const rgb = [0, 0, 0];
  const size = surface.size;
  surface.each((x, y, u, v, index) => {
    const patch = fbm(u, v, 3, 3, 3, seed + 1);
    shade(0.18 + patch * 0.12, rgb);
    surface.set(index, rgb, 0.2);
  });
  const random = createRandom(seed);
  const blades = Math.round(size * size * 0.2);
  for (let blade = 0; blade < blades; blade += 1) {
    const x = random() * size;
    const y = random() * size;
    const angle = random() * TAU;
    const length = size * (0.028 + random() * 0.045);
    const width = size / 128 * (1.1 + random() * 0.9);
    const patch = fbm(x / size, y / size, 3, 3, 3, seed + 1);
    const tone = clamp01(0.3 + random() * 0.45 + patch * 0.25);
    const x1 = x + Math.cos(angle) * length;
    const y1 = y + Math.sin(angle) * length;
    surface.stroke(
      x, y, x1, y1, width, width * 0.35,
      (t, across, out) => shade(clamp01(tone + t * 0.28 - across * 0.08), out),
      (t) => 0.35 + t * 0.55 * tone + 0.1,
    );
  }
  // Tiny clover-like flecks and dried blades break the uniform green.
  for (let fleck = 0; fleck < size * 0.9; fleck += 1) {
    const x = random() * size;
    const y = random() * size;
    const angle = random() * TAU;
    const length = size * (0.02 + random() * 0.03);
    const dry = hexToRgb(palette.dry);
    surface.stroke(x, y, x + Math.cos(angle) * length, y + Math.sin(angle) * length, size / 128 * 1.2, size / 128 * 0.5,
      (t, across, out) => { out[0] = dry[0]; out[1] = dry[1]; out[2] = dry[2]; return out; },
      () => 0.6, 0.7);
  }
  surface.smoothHeight(1);
  surface.emboss(0.5, 0.3);
}

function paintGrassSide(surface, palette, seed, options) {
  surface.wrapY = false;
  const size = surface.size;
  paintCachedLayer(surface, paintDirtLayer, options.soil, options.soilSeed);
  surface.emboss(0.6, 0.25);
  const shade = ramp([palette.deep, palette.dark, palette.base, palette.light, palette.tip]);
  const rgb = [0, 0, 0];
  const depthAt = new Float32Array(size);
  for (let x = 0; x < size; x += 1) {
    const u = (x + 0.5) / size;
    depthAt[x] = size * (0.2 + gradientNoise(u * 4, 0.5, 4, 1, seed) * 0.05 + gradientNoise(u * 13, 0.5, 13, 1, seed + 3) * 0.03);
  }
  // Soft contact shadow where the turf overhangs the soil.
  surface.each((x, y, u, v, index) => {
    const below = y - depthAt[x];
    if (below > 0 && below < size * 0.06) surface.scale(index, 0.62 + 0.38 * (below / (size * 0.06)));
  });
  surface.each((x, y, u, v, index) => {
    if (y >= depthAt[x]) return;
    const streak = fbm(u, v, 32, 3, 2, seed + 5);
    const patch = fbm(u, v, 3, 2, 2, seed + 6);
    const depth = y / depthAt[x];
    shade(clamp01(0.4 + streak * 0.3 + patch * 0.15 - depth * 0.2), rgb);
    surface.set(index, rgb, 0.7 + streak * 0.2);
  });
  const random = createRandom(seed + 9);
  // The turf band itself is built from short blades so it has the same texture
  // as the top face instead of reading as a painted stripe.
  const bandBlades = Math.round(size * size * 0.09);
  for (let blade = 0; blade < bandBlades; blade += 1) {
    const x = random() * size;
    const column = Math.max(0, Math.min(size - 1, Math.floor(x)));
    const y = random() * depthAt[column];
    const length = size * (0.03 + random() * 0.05);
    const lean = (random() - 0.5) * size * 0.04;
    const tone = clamp01(0.3 + random() * 0.5 + fbm(x / size, 0.5, 3, 1, 2, seed + 6) * 0.2);
    surface.stroke(
      x, y, x + lean, y + length, size / 128 * (1.3 + random() * 0.8), size / 128 * 0.5,
      (t, across, out) => shade(clamp01(tone - t * 0.15 - across * 0.12), out),
      (t) => 0.8 - t * 0.1,
    );
  }
  // A lighter lip where the turf turns over onto the top face.
  surface.each((x, y, u, v, index) => {
    if (y < size * 0.025) surface.scale(index, 1.12 - (y / (size * 0.025)) * 0.12);
  });
  // Blades hanging over the lip.
  const blades = Math.round(size * 0.9);
  for (let blade = 0; blade < blades; blade += 1) {
    const x = random() * size;
    const column = Math.max(0, Math.min(size - 1, Math.floor(x)));
    const top = depthAt[column] - size * 0.03;
    const length = size * (0.02 + random() * random() * 0.12);
    const lean = (random() - 0.5) * size * 0.03;
    const tone = 0.35 + random() * 0.4;
    surface.stroke(
      x, top, x + lean, top + length, size / 128 * (1.8 + random()), size / 128 * 0.5,
      (t, across, out) => shade(clamp01(tone - t * 0.25 - across * 0.1), out),
      (t) => 0.75 - t * 0.2,
    );
  }
  surface.emboss(0.3, 0);
}

function paintLeaves(surface, palette, seed) {
  const shade = ramp([palette.deep, palette.dark, palette.base, palette.light]);
  const vein = hexToRgb(palette.vein);
  const rgb = [0, 0, 0];
  const size = surface.size;
  surface.each((x, y, u, v, index) => {
    const depth = fbm(u, v, 4, 4, 3, seed + 1);
    shade(0.06 + depth * 0.06, rgb);
    surface.set(index, rgb, 0.05);
  });
  const random = createRandom(seed);
  const leaves = Math.round(size * size / 20);
  for (let leaf = 0; leaf < leaves; leaf += 1) {
    const cx = random() * size;
    const cy = random() * size;
    const angle = random() * TAU;
    const length = size * (0.04 + random() * 0.03);
    const width = length * (0.42 + random() * 0.18);
    const cluster = fbm(cx / size, cy / size, 3, 3, 3, seed + 7);
    const tone = clamp01(0.32 + random() * 0.38 + cluster * 0.35);
    const cos = Math.cos(angle);
    const sin = Math.sin(angle);
    const extent = Math.ceil(length + 2);
    for (let oy = -extent; oy <= extent; oy += 1) {
      for (let ox = -extent; ox <= extent; ox += 1) {
        const px = Math.floor(cx) + ox;
        const py = Math.floor(cy) + oy;
        const dx = px + 0.5 - cx;
        const dy = py + 0.5 - cy;
        const along = (dx * cos + dy * sin) / length;
        const across = (-dx * sin + dy * cos) / width;
        if (Math.abs(along) >= 1) continue;
        // Lens profile: pointed at both tips, widest in the middle.
        const halfWidth = 1 - along * along;
        const margin = (halfWidth - Math.abs(across)) * width;
        const coverage = clamp01(margin + 0.5);
        if (coverage <= 0) continue;
        const index = surface.index(px, py);
        const side = across > 0 ? -0.1 : 0.08;
        shade(clamp01(tone + side - Math.abs(along) * 0.12), rgb);
        const rim = 1 - smoothstep(0.4, 1.6, margin);
        rgb[0] *= 1 - rim * 0.35;
        rgb[1] *= 1 - rim * 0.35;
        rgb[2] *= 1 - rim * 0.35;
        const midrib = Math.abs(across * width) < 0.55 && Math.abs(along) < 0.85;
        if (midrib) {
          rgb[0] = rgb[0] * 0.55 + vein[0] * 0.45;
          rgb[1] = rgb[1] * 0.55 + vein[1] * 0.45;
          rgb[2] = rgb[2] * 0.55 + vein[2] * 0.45;
        }
        surface.blend(index, rgb, coverage, 0.35 + tone * 0.6 - Math.abs(across) * 0.15);
      }
    }
  }
  surface.emboss(0.45, 0.2);
}

function paintBark(surface, palette, seed) {
  const shade = ramp([palette.deep, palette.dark, palette.base, palette.light]);
  const rgb = [0, 0, 0];
  surface.each((x, y, u, v, index) => {
    const wander = fbm(u, v, 2, 4, 2, seed + 1) * 0.04;
    const ridges = fbm(u + wander, v, 7, 1, 4, seed);
    const fissure = smoothstep(0.0, 0.3, Math.abs(ridges));
    const plates = fbm(u, v, 10, 6, 3, seed + 3);
    const crossCrack = 1 - smoothstep(0.0, 0.05, Math.abs(fbm(u, v, 4, 10, 2, seed + 5)));
    const fibre = fbm(u, v, 24, 3, 1, seed + 7);
    const height = clamp01(0.12 + fissure * 0.7 + plates * 0.12 + fibre * 0.06 - crossCrack * fissure * 0.25);
    shade(clamp01(0.1 + fissure * 0.6 + plates * 0.18 + fibre * 0.1 - crossCrack * 0.2), rgb);
    surface.set(index, rgb, height);
  });
  surface.emboss(0.75, 0.3);
}

function paintWoodRings(surface, palette, seed) {
  surface.wrapX = false;
  surface.wrapY = false;
  const shade = ramp([palette.ring, palette.dark, palette.base, palette.light]);
  const bark = ramp([palette.barkDark, palette.bark]);
  const rgb = [0, 0, 0];
  const crackAngle = hash01(1, 2, seed) * TAU;
  surface.each((x, y, u, v, index) => {
    const dx = u - 0.5 + fbm(u, v, 3, 3, 2, seed + 1) * 0.02;
    const dy = v - 0.5 + fbm(u, v, 3, 3, 2, seed + 2) * 0.02;
    const round = Math.sqrt(dx * dx + dy * dy);
    const square = Math.max(Math.abs(dx), Math.abs(dy));
    const distance = round * 0.55 + square * 0.45;
    const border = 0.44 + fbm(u, v, 8, 8, 2, seed + 3) * 0.015;
    if (square > border) {
      const fissure = smoothstep(0.0, 0.3, Math.abs(fbm(u, v, 12, 12, 3, seed + 4)));
      bark(fissure, rgb);
      surface.set(index, rgb, 0.3 + fissure * 0.5);
      return;
    }
    const rings = distance * 12 + fbm(u, v, 4, 4, 2, seed + 5) * 0.35;
    const phase = rings - Math.floor(rings);
    const line = 1 - smoothstep(0.0, 0.12, Math.min(phase, 1 - phase));
    const fibre = fbm(u, v, 24, 24, 2, seed + 6);
    let angle = Math.atan2(dy, dx) - crackAngle;
    angle = Math.atan2(Math.sin(angle), Math.cos(angle));
    const crack = (1 - smoothstep(0.0, 0.03 + distance * 0.02, Math.abs(angle))) * smoothstep(0.05, 0.2, distance);
    const tone = clamp01(0.64 - phase * 0.12 - line * 0.28 + fibre * 0.1 - crack * 0.45);
    shade(tone, rgb);
    const rim = smoothstep(border - 0.03, border, square);
    rgb[0] *= 1 - rim * 0.22;
    rgb[1] *= 1 - rim * 0.22;
    rgb[2] *= 1 - rim * 0.22;
    surface.set(index, rgb, clamp01(0.6 - line * 0.15 - crack * 0.4 + fibre * 0.05));
  });
  surface.emboss(0.45, 0.15);
}

function paintWater(surface, palette, seed) {
  const shade = ramp([palette.deep, palette.base, palette.light]);
  const rgb = [0, 0, 0];
  surface.each((x, y, u, v, index) => {
    const warpU = fbm(u, v, 2, 2, 3, seed + 1) * 0.12;
    const warpV = fbm(u, v, 2, 2, 3, seed + 2) * 0.12;
    worley(u + warpU, v + warpV, 4, seed, WORLEY, 1);
    const caustic = (1 - smoothstep(0.0, 0.2, WORLEY.f2 - WORLEY.f1)) * smoothstep(-0.2, 0.3, fbm(u, v, 3, 3, 2, seed + 4));
    const body = fbm(u, v, 3, 3, 3, seed + 3);
    shade(clamp01(0.45 + body * 0.25 + caustic * 0.14), rgb);
    surface.set(index, rgb, clamp01(0.5 + body * 0.2 + caustic * 0.2));
  });
}

function paintLava(surface, palette, seed) {
  const shade = ramp([palette.crust, palette.dark, palette.base, palette.hot, palette.white]);
  const rgb = [0, 0, 0];
  surface.each((x, y, u, v, index) => {
    const warpU = fbm(u, v, 2, 2, 3, seed + 1) * 0.18;
    const warpV = fbm(u, v, 2, 2, 3, seed + 2) * 0.18;
    const flow = fbm(u + warpU, v + warpV, 3, 3, 5, seed);
    const vein = 1 - Math.abs(fbm(u + warpU * 1.5, v + warpV * 1.5, 3, 3, 4, seed + 3));
    const channel = smoothstep(0.72, 0.95, vein);
    const crust = smoothstep(0.12, 0.45, fbm(u + warpV, v + warpU, 4, 4, 3, seed + 5)) * (1 - channel);
    const heat = clamp01(0.58 + flow * 0.4 + channel * 0.3 - crust * 0.5);
    shade(heat, rgb);
    surface.set(index, rgb, clamp01(0.3 + crust * 0.6 + flow * 0.1));
  });
  surface.emboss(0.3, 0);
}

function paintFire(surface, palette, seed) {
  surface.wrapY = false;
  const shade = ramp([palette.smoke, palette.dark, palette.base, palette.hot, palette.white]);
  const rgb = [0, 0, 0];
  surface.each((x, y, u, v, index) => {
    const rise = 1 - v;
    const tongues = fbm(u, v * 0.5, 6, 2, 3, seed) * 0.28 + gradientNoise(u * 10, 0.5, 10, 1, seed + 3) * 0.12;
    const reach = 0.72 + tongues;
    const heat = clamp01(1 - rise / Math.max(0.2, reach));
    const flicker = fbm(u, v, 8, 6, 3, seed + 5) * 0.18;
    shade(clamp01(heat * 1.1 + flicker - 0.05), rgb);
    surface.set(index, rgb, heat);
  });
}

function paintObsidian(surface, palette, seed) {
  const shade = ramp([palette.dark, palette.base, palette.light, palette.sheen]);
  const rgb = [0, 0, 0];
  surface.each((x, y, u, v, index) => {
    const warpU = fbm(u, v, 3, 3, 3, seed + 1) * 0.1;
    const warpV = fbm(u, v, 3, 3, 3, seed + 2) * 0.1;
    const body = fbm(u + warpU, v + warpV, 3, 3, 5, seed);
    const ridge = 1 - Math.abs(fbm(u + warpU, v + warpV, 5, 5, 3, seed + 3));
    const streak = smoothstep(0.78, 0.97, ridge);
    worley(u, v, 5, seed + 7, WORLEY, 1);
    const facet = smoothstep(0.0, 0.3, WORLEY.f2 - WORLEY.f1);
    const tone = clamp01(0.22 + body * 0.2 + streak * 0.5 + (facet - 0.5) * 0.12);
    shade(tone, rgb);
    surface.set(index, rgb, clamp01(0.4 + facet * 0.3 + streak * 0.2));
    worley(u, v, 18, seed + 9, WORLEY, 1);
    if (WORLEY.f1 < 0.14 && hash01(WORLEY.id, 1, seed) < 0.16) {
      surface.blend(index, hexToRgb(palette.sheen), (1 - WORLEY.f1 / 0.14) * 0.7);
    }
  });
  surface.emboss(0.55, 0.1);
}

function paintOre(surface, palette, seed, options) {
  paintCachedLayer(surface, paintStoneLayer, options.stone, options.stoneSeed);
  const size = surface.size;
  const ore = ramp([palette.oreDark, palette.ore, palette.oreLight]);
  const rim = hexToRgb(palette.rim);
  const rgb = [0, 0, 0];
  const random = createRandom(seed);
  const clusters = options.clusters ?? 4;
  const facets = options.facets ?? 0;
  const lightX = -0.7071;
  const lightY = -0.7071;
  for (let cluster = 0; cluster < clusters; cluster += 1) {
    const cx = (cluster + 0.2 + random() * 0.6) / clusters * size;
    const cy = random() * size;
    const blobs = 3 + Math.floor(random() * 4);
    for (let blob = 0; blob < blobs; blob += 1) {
      const bx = cx + (random() - 0.5) * size * 0.16;
      const by = cy + (random() - 0.5) * size * 0.16;
      const radius = size * (0.028 + random() * 0.03) * (options.scale ?? 1);
      const rotation = random() * TAU;
      const extent = Math.ceil(radius * 1.5 + 2);
      for (let oy = -extent; oy <= extent; oy += 1) {
        for (let ox = -extent; ox <= extent; ox += 1) {
          const px = Math.floor(bx) + ox;
          const py = Math.floor(by) + oy;
          const dx = px + 0.5 - bx;
          const dy = py + 0.5 - by;
          const angle = Math.atan2(dy, dx) + rotation;
          const wobble = 1 + gradientNoise(Math.cos(angle) * 1.5 + blob * 3, Math.sin(angle) * 1.5 + cluster * 5, 64, 64, seed) * 0.28;
          let reach = radius * wobble;
          if (facets > 0) {
            const sector = TAU / facets;
            const local = ((angle % sector) + sector) % sector - sector / 2;
            reach *= Math.cos(sector / 2) / Math.cos(local);
          }
          const distance = Math.sqrt(dx * dx + dy * dy);
          const index = surface.index(px, py);
          if (distance < reach) {
            const dome = 1 - distance / reach;
            let lit;
            if (facets > 0) {
              const sector = TAU / facets;
              const facetAngle = (Math.floor((angle - rotation + TAU * 4) / sector) + 0.5) * sector - rotation;
              lit = 0.5 + 0.5 * (Math.cos(facetAngle) * lightX + Math.sin(facetAngle) * lightY) * (1 - dome * 0.6);
            } else {
              lit = 0.5 + 0.5 * ((dx / reach) * lightX + (dy / reach) * lightY) * -1;
            }
            ore(clamp01(0.2 + lit * 0.55 + dome * 0.3), rgb);
            const coverage = clamp01((reach - distance) * 1.2);
            surface.blend(index, rgb, coverage, 0.7 + dome * 0.3);
            if (lit > 0.82 && dome > 0.35) surface.blend(index, hexToRgb(palette.glint), 0.55);
          } else if (distance < reach + size * 0.02) {
            const fade = 1 - (distance - reach) / (size * 0.02);
            surface.blend(index, rim, fade * 0.5, surface.height[index] * (1 - fade * 0.3));
          }
        }
      }
    }
  }
  // Same relief as the stone block, so the stone around the ore is texel for
  // texel the stone next to it.
  surface.emboss(STONE_EMBOSS, STONE_CAVITY);
}

function paintFurnace(surface, palette, seed) {
  surface.wrapX = false;
  surface.wrapY = false;
  paintStoneBricksLayer(surface, palette, seed, 4);
  const voidColor = hexToRgb(palette.void);
  const ember = ramp([palette.void, palette.emberDark, palette.ember, palette.emberHot]);
  const rgb = [0, 0, 0];
  // Fire mouth.
  rect(surface, 0.2, 0.5, 0.8, 0.86, (x, y, lu, lv, index, u, v) => {
    const glow = clamp01((lv - 0.35) / 0.65);
    const flicker = fbm(u, v, 8, 8, 3, seed + 3);
    const coals = smoothstep(0.62, 0.9, lv) * (0.6 + flicker * 0.6);
    ember(clamp01(glow * 0.45 + coals * 0.7 + flicker * 0.1), rgb);
    const lintel = 1 - smoothstep(0.0, 0.22, lv);
    rgb[0] *= 1 - lintel * 0.7;
    rgb[1] *= 1 - lintel * 0.7;
    rgb[2] *= 1 - lintel * 0.7;
    surface.set(index, rgb, 0.05 + coals * 0.2);
  });
  // Grate bars across the mouth.
  for (let bar = 0; bar < 4; bar += 1) {
    const u0 = 0.28 + bar * 0.15;
    rect(surface, u0, 0.5, u0 + 0.035, 0.86, (x, y, lu, lv, index) => {
      const iron = hexToRgb(palette.iron);
      const edge = 1 - Math.abs(lu - 0.5) * 2;
      surface.set(index, [iron[0] * (0.7 + edge * 0.5), iron[1] * (0.7 + edge * 0.5), iron[2] * (0.7 + edge * 0.5)], 0.55);
    });
  }
  // Vent slot above.
  rect(surface, 0.3, 0.17, 0.7, 0.29, (x, y, lu, lv, index) => {
    const slat = Math.sin(lu * Math.PI * 7);
    surface.set(index, [voidColor[0] * 1.4, voidColor[1] * 1.4, voidColor[2] * 1.4], 0.1);
    if (slat > 0.3) surface.blend(index, hexToRgb(palette.iron), 0.7, 0.4);
  });
  bevelFrame(surface, 0.17, 0.47, 0.83, 0.89, 0.035, -0.28);
  bevelFrame(surface, 0.27, 0.14, 0.73, 0.32, 0.03, -0.25);
  bevelFrame(surface, 0, 0, 1, 1, 0.04, 0.12);
  surface.emboss(0.55, 0.2);
}

function paintTorch(surface, palette, seed) {
  surface.wrapX = false;
  surface.wrapY = false;
  const wall = ramp([palette.wallDark, palette.wall]);
  const glowColor = hexToRgb(palette.glow);
  const flame = ramp([palette.flameEdge, palette.flame, palette.flameHot, palette.flameCore]);
  const wood = ramp([palette.woodDark, palette.wood, palette.woodLight]);
  const rgb = [0, 0, 0];
  surface.each((x, y, u, v, index) => {
    const body = fbm(u, v, 5, 5, 4, seed);
    wall(clamp01(0.5 + body * 0.4), rgb);
    const dx = u - 0.5;
    const dy = v - 0.3;
    const glow = Math.exp(-(dx * dx + dy * dy) / 0.045);
    rgb[0] += glowColor[0] * glow * 0.55;
    rgb[1] += glowColor[1] * glow * 0.55;
    rgb[2] += glowColor[2] * glow * 0.55;
    surface.set(index, rgb, 0.3 + body * 0.1);
  });
  rect(surface, 0.44, 0.36, 0.56, 0.92, (x, y, lu, lv, index, u, v) => {
    const grain = fbm(u, v, 16, 2, 2, seed + 3);
    const round = Math.sin(lu * Math.PI);
    wood(clamp01(0.2 + round * 0.55 + grain * 0.2), rgb);
    // The top of the stick is charred where the flame sits on it.
    const char = 1 - smoothstep(0.0, 0.25, lv);
    rgb[0] *= 1 - char * 0.6;
    rgb[1] *= 1 - char * 0.6;
    rgb[2] *= 1 - char * 0.6;
    surface.set(index, rgb, 0.4 + round * 0.4);
  });
  const size = surface.size;
  surface.each((x, y, u, v, index) => {
    const top = 0.1;
    const bottom = 0.4;
    if (v < top - 0.02 || v > bottom) return;
    const t = (v - top) / (bottom - top);
    const sway = gradientNoise(v * 6, 0.5, 64, 1, seed + 5) * 0.012;
    const halfWidth = 0.1 * Math.pow(Math.sin(clamp01(t) * Math.PI * 0.92 + 0.08), 0.85);
    const across = Math.abs(u - 0.5 - sway) / Math.max(0.001, halfWidth);
    if (across >= 1.15) return;
    const coverage = clamp01((1.15 - across) * size * halfWidth * 0.5);
    const heat = clamp01((1 - across) * 0.8 + t * 0.55 - 0.1);
    flame(heat, rgb);
    surface.blend(index, rgb, coverage, 0.8);
  });
  surface.emboss(0.4, 0.1);
}

function paintBed(surface, palette, seed) {
  surface.wrapX = false;
  surface.wrapY = false;
  paintFabricLayer(surface, { dark: palette.clothDark, base: palette.cloth, light: palette.clothLight }, seed, 40);
  const wood = { dark: palette.woodDark, base: palette.wood, light: palette.woodLight, seam: palette.woodDark };
  const frame = new MaterialSurface(surface.size);
  paintPlanksLayer(frame, wood, seed + 3, { boards: 2, vertical: false, stagger: false });
  const rgb = [0, 0, 0];
  // Blanket fold across the lower edge of the mattress.
  rect(surface, 0, 0.46, 1, 0.58, (x, y, lu, lv, index) => {
    const fold = Math.sin(lv * Math.PI);
    surface.scale(index, 0.9 + fold * 0.22);
    surface.height[index] = 0.6 + fold * 0.3;
  });
  // Pillow.
  const pillow = ramp([palette.pillowDark, palette.pillow]);
  rect(surface, 0.06, 0.08, 0.44, 0.36, (x, y, lu, lv, index, u, v) => {
    const cushion = Math.sin(lu * Math.PI) * Math.sin(lv * Math.PI);
    const weave = fbm(u, v, 48, 48, 1, seed + 5) * 0.06;
    pillow(clamp01(0.25 + cushion * 0.8 + weave), rgb);
    const edge = Math.min(lu, 1 - lu, lv, 1 - lv);
    const coverage = clamp01(edge * surface.size * 0.38 / 1.2);
    surface.blend(index, rgb, coverage, 0.55 + cushion * 0.4);
  });
  // Wooden frame and legs.
  rect(surface, 0, 0.58, 1, 1, (x, y, lu, lv, index) => {
    const source = y * surface.size + x;
    const legs = lv > 0.55 && lu > 0.14 && lu < 0.86;
    if (legs) {
      const shadow = hexToRgb(palette.shadow);
      surface.set(index, shadow, 0.05);
      return;
    }
    surface.set(index, [frame.color[source * 3], frame.color[source * 3 + 1], frame.color[source * 3 + 2]], frame.height[source]);
  });
  bevelFrame(surface, 0, 0.58, 1, 0.84, 0.03, 0.18);
  surface.emboss(0.5, 0.15);
}

function paintDoor(surface, palette, seed, options) {
  surface.wrapX = false;
  surface.wrapY = false;
  const wood = { dark: palette.woodDark, base: palette.wood, light: palette.woodLight, seam: palette.seam };
  const rgb = [0, 0, 0];
  if (options.open) {
    const shade = ramp([palette.void, palette.voidLight]);
    surface.each((x, y, u, v, index) => {
      const depth = fbm(u, v, 3, 3, 3, seed) * 0.15;
      shade(clamp01(0.25 + v * 0.35 + depth), rgb);
      surface.set(index, rgb, 0.05);
    });
    const slab = new MaterialSurface(surface.size);
    paintPlanksLayer(slab, wood, seed + 1, { boards: 2, vertical: true, stagger: false });
    rect(surface, 0, 0, 0.2, 1, (x, y, lu, lv, index) => {
      const source = y * surface.size + x;
      surface.set(index, [slab.color[source * 3], slab.color[source * 3 + 1], slab.color[source * 3 + 2]], slab.height[source]);
    });
    bevelFrame(surface, 0, 0, 0.2, 1, 0.04, 0.2);
    rect(surface, 0.2, 0, 0.26, 1, (x, y, lu, lv, index) => surface.scale(index, 0.55 + lu * 0.45));
    surface.emboss(0.5, 0.1);
    return;
  }
  paintPlanksLayer(surface, wood, seed, { boards: 4, vertical: true, stagger: false });
  // Rails.
  for (const [v0, v1] of [[0.44, 0.56], [0.88, 0.97]]) {
    rect(surface, 0.06, v0, 0.94, v1, (x, y, lu, lv, index, u, v) => {
      const grain = woodGrain(u, v, seed + 7, false);
      ramp([palette.woodDark, palette.wood, palette.woodLight])(clamp01(0.6 + grain * 0.25), rgb);
      surface.set(index, rgb, 0.75);
    });
    bevelFrame(surface, 0.06, v0, 0.94, v1, 0.02, 0.25);
  }
  // Window panes.
  const glass = ramp([palette.glassDark, palette.glass, palette.glassLight]);
  for (const [u0, u1] of [[0.14, 0.47], [0.53, 0.86]]) {
    rect(surface, u0, 0.09, u1, 0.38, (x, y, lu, lv, index) => {
      const streak = 1 - smoothstep(0.0, 0.07, Math.abs(lu - lv * 0.8 - 0.1));
      glass(clamp01(0.35 + (1 - lv) * 0.3 + streak * 0.5), rgb);
      surface.set(index, rgb, 0.3);
    });
    bevelFrame(surface, u0, 0.09, u1, 0.38, 0.025, -0.35);
  }
  bevelFrame(surface, 0, 0, 1, 1, 0.06, 0.22);
  // Hinges and handle.
  const iron = ramp([palette.ironDark, palette.iron, palette.ironLight]);
  for (const v0 of [0.14, 0.72]) {
    rect(surface, 0.0, v0, 0.14, v0 + 0.08, (x, y, lu, lv, index) => {
      iron(clamp01(0.35 + (1 - lv) * 0.45 + (1 - lu) * 0.1), rgb);
      surface.set(index, rgb, 0.85);
      const rivet = Math.hypot(lu - 0.72, lv - 0.5);
      if (rivet < 0.2) surface.blend(index, hexToRgb(palette.ironLight), 0.6);
    });
  }
  rect(surface, 0.78, 0.47, 0.88, 0.55, (x, y, lu, lv, index) => {
    const knob = Math.hypot(lu - 0.5, lv - 0.5) * 2;
    if (knob > 1) return;
    iron(clamp01(0.9 - knob * 0.4 - (lu + lv - 1) * 0.3), rgb);
    surface.set(index, rgb, 0.95);
  });
  surface.emboss(0.55, 0.15);
}

function paintCrop(surface, palette, seed, options) {
  surface.wrapY = false;
  const size = surface.size;
  const stage = options.stage ?? 0;
  const gap = ramp([palette.soil, palette.gap]);
  const stalk = ramp([palette.stalkDark, palette.stalk, palette.stalkLight]);
  const grain = ramp([palette.grainDark, palette.grain, palette.grainLight]);
  const rgb = [0, 0, 0];
  surface.each((x, y, u, v, index) => {
    const depth = fbm(u, v, 6, 6, 3, seed);
    gap(clamp01(0.3 + (1 - v) * 0.55 + depth * 0.25), rgb);
    surface.set(index, rgb, 0.1);
  });
  const random = createRandom(seed);
  const counts = [55, 90, 120, 140];
  const heights = [0.4, 0.62, 0.84, 0.94];
  const stalks = Math.round(counts[stage] * size / 128);
  for (let index = 0; index < stalks; index += 1) {
    const x = random() * size;
    const reach = heights[stage] * (0.72 + random() * 0.28);
    const top = size * (1 - reach);
    const lean = (random() - 0.5) * size * 0.06;
    const tone = 0.3 + random() * 0.55;
    const width = size / 128 * (1.4 + random() * 0.9);
    // Two segments with the lean concentrated in the upper one, so a stalk
    // bends like a stem under its own weight instead of standing as a ruler line.
    const midX = x + lean * 0.25;
    const midY = size + 2 - (size + 2 - top) * 0.55;
    surface.stroke(
      x, size + 2, midX, midY, width, width * 0.8,
      (t, across, out) => stalk(clamp01(tone + t * 0.1 - across * 0.15), out),
      (t) => 0.4 + t * 0.25,
    );
    surface.stroke(
      midX, midY, x + lean, top, width * 0.8, width * 0.55,
      (t, across, out) => stalk(clamp01(tone + 0.1 + t * 0.12 - across * 0.15), out),
      (t) => 0.65 + t * 0.25,
    );
    if (random() < 0.55) {
      const leafAt = 0.3 + random() * 0.4;
      const lx = x + lean * leafAt;
      const ly = size + 2 - (size + 2 - top) * leafAt;
      const direction = random() < 0.5 ? -1 : 1;
      surface.stroke(
        lx, ly, lx + direction * size * (0.05 + random() * 0.05), ly - size * (0.06 + random() * 0.05), width * 1.4, width * 0.3,
        (t, across, out) => stalk(clamp01(tone * 0.9 + t * 0.15), out),
        () => 0.6,
      );
    }
    if (stage >= 2) {
      const ear = size * (stage === 3 ? 0.13 : 0.09);
      const grains = stage === 3 ? 7 : 5;
      for (let g = 0; g < grains; g += 1) {
        const t = g / grains;
        const gx = x + lean + (g % 2 === 0 ? -1 : 1) * width * 0.7;
        const gy = top + t * ear;
        surface.stroke(
          gx, gy, gx, gy + ear / grains * 1.6, width * 1.7, width * 1.1,
          (tt, across, out) => grain(clamp01((stage === 3 ? 0.55 : 0.35) + (1 - across) * 0.35 - t * 0.2), out),
          () => 0.85,
        );
      }
    }
  }
  surface.emboss(0.4, 0.2);
}

function paintFarmland(surface, palette, seed) {
  const shade = ramp([palette.dark, palette.base, palette.light]);
  const rgb = [0, 0, 0];
  surface.each((x, y, u, v, index) => {
    const wobble = fbm(u, v, 3, 3, 2, seed + 1) * 0.04;
    const furrow = Math.sin((v + wobble) * TAU * 4);
    const ridge = 0.5 + 0.5 * furrow;
    const body = fbm(u, v, 6, 6, 4, seed);
    worley(u, v, 14, seed + 3, WORLEY, 1);
    const clod = smoothstep(0.0, 0.3, WORLEY.f2 - WORLEY.f1) * ridge;
    const height = clamp01(0.2 + ridge * 0.5 + body * 0.15 + clod * 0.15);
    shade(clamp01(0.25 + ridge * 0.4 + body * 0.25 + clod * 0.15), rgb);
    surface.set(index, rgb, height);
  });
  surface.emboss(0.7, 0.3);
}

function paintGlass(surface, palette, seed) {
  surface.wrapX = false;
  surface.wrapY = false;
  const shade = ramp([palette.dark, palette.base, palette.light]);
  const rgb = [0, 0, 0];
  surface.each((x, y, u, v, index) => {
    const tint = fbm(u, v, 2, 2, 3, seed) * 0.12;
    const streakA = 1 - smoothstep(0.0, 0.025, Math.abs(u - v * 0.9 - 0.18));
    const streakB = 1 - smoothstep(0.0, 0.012, Math.abs(u - v * 0.9 - 0.3));
    const streakC = 1 - smoothstep(0.0, 0.018, Math.abs(u - v * 0.9 + 0.35));
    shade(clamp01(0.4 + (1 - v) * 0.12 + tint + streakA * 0.4 + streakB * 0.35 + streakC * 0.3), rgb);
    surface.set(index, rgb, 0.45);
  });
  const frame = ramp([palette.edge, palette.frame]);
  surface.each((x, y, u, v, index) => {
    const nearest = Math.min(u, v, 1 - u, 1 - v);
    if (nearest > 0.07) return;
    const lit = nearest === u || nearest === v;
    frame(lit ? 0.9 : 0.55, rgb);
    const inner = 1 - smoothstep(0.055, 0.07, nearest);
    surface.blend(index, rgb, inner, 0.8);
    if (nearest > 0.058 && nearest < 0.07) surface.scale(index, 0.78);
  });
  surface.emboss(0.3, 0);
}

function paintChest(surface, palette, seed) {
  surface.wrapX = false;
  surface.wrapY = false;
  paintPlanksLayer(surface, { dark: palette.woodDark, base: palette.wood, light: palette.woodLight, seam: palette.seam }, seed, { boards: 4, vertical: false, stagger: true });
  const iron = ramp([palette.ironDark, palette.iron, palette.ironLight]);
  const rgb = [0, 0, 0];
  // Lid seam.
  rect(surface, 0, 0.34, 1, 0.4, (x, y, lu, lv, index) => {
    const groove = Math.sin(lv * Math.PI);
    surface.set(index, hexToRgb(palette.seam), 0.05);
    surface.scale(index, 0.7 + (1 - groove) * 0.5);
  });
  // Iron corner bands.
  surface.each((x, y, u, v, index) => {
    const nearest = Math.min(u, v, 1 - u, 1 - v);
    if (nearest > 0.07) return;
    const lit = nearest === u || nearest === v;
    iron(clamp01((lit ? 0.7 : 0.35) + fbm(u, v, 16, 16, 2, seed + 5) * 0.15), rgb);
    surface.set(index, rgb, 0.85);
    worley(u, v, 8, seed + 9, WORLEY, 0.2);
    if (WORLEY.f1 < 0.13 && nearest > 0.015 && nearest < 0.055) surface.blend(index, hexToRgb(palette.ironLight), 0.8, 1);
  });
  // Latch.
  const gold = ramp([palette.latchDark, palette.latch, palette.latchLight]);
  rect(surface, 0.42, 0.3, 0.58, 0.5, (x, y, lu, lv, index) => {
    gold(clamp01(0.3 + (1 - lv) * 0.45 + (1 - lu) * 0.2), rgb);
    surface.set(index, rgb, 0.95);
    if (Math.hypot(lu - 0.5, (lv - 0.45) * 1.3) < 0.14 || (Math.abs(lu - 0.5) < 0.05 && lv > 0.45 && lv < 0.72)) {
      surface.set(index, hexToRgb(palette.shadow), 0.2);
    }
  });
  bevelFrame(surface, 0.42, 0.3, 0.58, 0.5, 0.02, 0.3);
  surface.emboss(0.55, 0.15);
}

function paintCraftingTable(surface, palette, seed) {
  surface.wrapX = false;
  surface.wrapY = false;
  paintPlanksLayer(surface, { dark: palette.woodDark, base: palette.wood, light: palette.woodLight, seam: palette.seam }, seed, { boards: 4, vertical: false, stagger: true });
  const rgb = [0, 0, 0];
  const top = ramp([palette.woodDark, palette.top, palette.woodLight]);
  // Work surface with a 3x3 grid.
  rect(surface, 0.17, 0.17, 0.83, 0.83, (x, y, lu, lv, index, u, v) => {
    const grain = woodGrain(u, v, seed + 3, false);
    top(clamp01(0.55 + grain * 0.25), rgb);
    const cellU = lu * 3 - Math.floor(lu * 3);
    const cellV = lv * 3 - Math.floor(lv * 3);
    const line = Math.min(cellU, 1 - cellU, cellV, 1 - cellV) * surface.size * 0.66 / 3;
    const groove = 1 - smoothstep(0.5, 1.6, line);
    surface.set(index, rgb, 0.7 - groove * 0.5);
    if (groove > 0) surface.blend(index, hexToRgb(palette.seam), groove * 0.85);
  });
  bevelFrame(surface, 0.17, 0.17, 0.83, 0.83, 0.03, -0.3);
  // Frame and metal corner brackets.
  bevelFrame(surface, 0, 0, 1, 1, 0.05, 0.2);
  const iron = ramp([palette.ironDark, palette.iron, palette.ironLight]);
  for (const [u0, v0] of [[0, 0], [0.86, 0], [0, 0.86], [0.86, 0.86]]) {
    rect(surface, u0, v0, u0 + 0.14, v0 + 0.14, (x, y, lu, lv, index) => {
      const outer = u0 === 0 ? lu : 1 - lu;
      const outerV = v0 === 0 ? lv : 1 - lv;
      if (outer > 0.45 && outerV > 0.45) return;
      iron(clamp01(0.4 + (1 - lv) * 0.4), rgb);
      surface.set(index, rgb, 0.9);
      if (Math.hypot(outer - 0.22, outerV - 0.22) < 0.1) surface.blend(index, hexToRgb(palette.ironLight), 0.8, 1);
    });
  }
  surface.emboss(0.55, 0.15);
}

function paintSkin(surface, palette, seed, options) {
  paintSkinLayer(surface, palette, seed);
  if (options.nostrils) {
    const rgb = hexToRgb(palette.dark);
    surface.each((x, y, u, v, index) => {
      for (const cx of [0.32, 0.68]) {
        const d = Math.hypot((u - cx) / 0.08, (v - 0.5) / 0.13);
        if (d < 1) surface.blend(index, [rgb[0] * 0.55, rgb[1] * 0.45, rgb[2] * 0.45], clamp01((1 - d) * 4), 0.1);
      }
    });
    bevelFrame(surface, 0, 0, 1, 1, 0.08, 0.14);
  }
  surface.emboss(0.35, 0.1);
}

function paintFabric(surface, palette, seed, options) {
  paintFabricLayer(surface, palette, seed, options.threads ?? 42);
  if (palette.trim !== undefined) {
    const trim = hexToRgb(palette.trim);
    const baseColor = hexToRgb(palette.base);
    const baseLuminance = Math.max(0.05, (baseColor[0] + baseColor[1] + baseColor[2]) / 3);
    surface.each((x, y, u, v, index) => {
      const nearest = Math.min(u, v, 1 - u, 1 - v);
      if (nearest > 0.065) return;
      const offset = index * 3;
      const lum = (surface.color[offset] + surface.color[offset + 1] + surface.color[offset + 2]) / 3;
      const factor = lum / baseLuminance;
      surface.blend(index, [trim[0] * factor, trim[1] * factor, trim[2] * factor], 0.75);
      if (nearest > 0.052) surface.scale(index, 0.82);
    });
  }
  surface.emboss(0.22, 0.08);
}

function paintEye(surface, palette, seed) {
  surface.wrapX = false;
  surface.wrapY = false;
  const shade = ramp([palette.dark, palette.base, palette.light]);
  const rgb = [0, 0, 0];
  surface.each((x, y, u, v, index) => {
    const d = Math.hypot(u - 0.5, v - 0.5) * 2;
    const iris = 1 - smoothstep(0.55, 0.75, d);
    const pupil = 1 - smoothstep(0.25, 0.32, d);
    const fibre = fbm(u, v, 12, 12, 2, seed) * 0.15;
    shade(clamp01(0.2 + iris * 0.45 - pupil * 0.6 + fibre * iris), rgb);
    surface.set(index, rgb, 0.5 + iris * 0.3);
    const glint = Math.hypot(u - 0.36, v - 0.34);
    if (glint < 0.09) surface.blend(index, hexToRgb(palette.glint), clamp01((0.09 - glint) * 30), 1);
  });
  surface.emboss(0.3, 0);
}

/**
 * Painter registry. The key is what a texture descriptor names in `painter`,
 * and `palette` lists the colours that painter reads from the descriptor.
 */
export const MATERIAL_PAINTERS = Object.freeze({
  stone: Object.freeze({ paint: paintStone, palette: ["base", "light", "dark", "crack"] }),
  cobblestone: Object.freeze({ paint: paintCobblestone, palette: ["base", "light", "dark", "mortar", "warm"] }),
  dirt: Object.freeze({ paint: paintDirt, palette: ["base", "light", "dark", "pebble", "pebbleLight", "pebbleDark"] }),
  sand: Object.freeze({ paint: paintSand, palette: ["base", "light", "dark", "speckLight", "speckDark"] }),
  grass_top: Object.freeze({ paint: paintGrassTop, palette: ["deep", "dark", "base", "light", "tip", "dry"] }),
  grass_side: Object.freeze({ paint: paintGrassSide, palette: ["deep", "dark", "base", "light", "tip"] }),
  leaves: Object.freeze({ paint: paintLeaves, palette: ["deep", "dark", "base", "light", "vein"] }),
  bark: Object.freeze({ paint: paintBark, palette: ["deep", "dark", "base", "light"] }),
  wood_rings: Object.freeze({ paint: paintWoodRings, palette: ["ring", "dark", "base", "light", "bark", "barkDark"] }),
  water: Object.freeze({ paint: paintWater, palette: ["deep", "base", "light"] }),
  lava: Object.freeze({ paint: paintLava, palette: ["crust", "dark", "base", "hot", "white"] }),
  fire: Object.freeze({ paint: paintFire, palette: ["smoke", "dark", "base", "hot", "white"] }),
  obsidian: Object.freeze({ paint: paintObsidian, palette: ["dark", "base", "light", "sheen"] }),
  ore: Object.freeze({ paint: paintOre, palette: ["ore", "oreLight", "oreDark", "rim", "glint"] }),
  furnace: Object.freeze({ paint: paintFurnace, palette: ["base", "light", "dark", "mortar", "void", "iron", "ember", "emberDark", "emberHot"] }),
  torch: Object.freeze({ paint: paintTorch, palette: ["wall", "wallDark", "glow", "wood", "woodDark", "woodLight", "flame", "flameEdge", "flameHot", "flameCore"] }),
  bed: Object.freeze({ paint: paintBed, palette: ["cloth", "clothDark", "clothLight", "pillow", "pillowDark", "wood", "woodDark", "woodLight", "shadow"] }),
  door: Object.freeze({ paint: paintDoor, palette: ["wood", "woodDark", "woodLight", "seam", "glass", "glassDark", "glassLight", "iron", "ironDark", "ironLight", "void", "voidLight"] }),
  crop: Object.freeze({ paint: paintCrop, palette: ["soil", "gap", "stalk", "stalkDark", "stalkLight", "grain", "grainDark", "grainLight"] }),
  farmland: Object.freeze({ paint: paintFarmland, palette: ["base", "light", "dark"] }),
  glass: Object.freeze({ paint: paintGlass, palette: ["base", "light", "dark", "frame", "edge"] }),
  chest: Object.freeze({ paint: paintChest, palette: ["wood", "woodDark", "woodLight", "seam", "iron", "ironDark", "ironLight", "latch", "latchDark", "latchLight", "shadow"] }),
  crafting_table: Object.freeze({ paint: paintCraftingTable, palette: ["wood", "woodDark", "woodLight", "top", "seam", "iron", "ironDark", "ironLight"] }),
  skin: Object.freeze({ paint: paintSkin, palette: ["base", "light", "dark"] }),
  fabric: Object.freeze({ paint: paintFabric, palette: ["base", "light", "dark"] }),
  eye: Object.freeze({ paint: paintEye, palette: ["base", "light", "dark", "glint"] }),
});

/**
 * Paint one tile. Returns `size * size * 4` RGBA bytes. `options` carries the
 * painter's non-colour parameters (a crop stage, an ore's facet count, the
 * stone an ore is embedded in).
 */
export function paintMaterial(painterName, size, seed, palette, { opacity = 1, options = {} } = {}) {
  const painter = MATERIAL_PAINTERS[painterName];
  if (painter === undefined) throw new Error(`Unknown material painter ${painterName}.`);
  for (const key of painter.palette) {
    if (palette[key] === undefined) throw new Error(`Painter ${painterName} needs palette colour ${key}.`);
  }
  const surface = new MaterialSurface(size);
  painter.paint(surface, palette, seed | 0, options);
  return surface.toRgba(opacity);
}

/** Stable per-name seed, so a texture keeps its look when tiles are reordered. */
export function materialSeed(name) {
  let value = 0x811c9dc5;
  for (const character of String(name)) {
    value ^= character.codePointAt(0);
    value = Math.imul(value, 0x01000193);
  }
  return value >>> 0;
}
