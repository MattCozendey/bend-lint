export const CLOUD_TEXTURE_SIZE = 64;

function fade(value) {
  return value * value * (3 - 2 * value);
}

function latticeValue(x, y, period) {
  const wrappedX = ((x % period) + period) % period;
  const wrappedY = ((y % period) + period) % period;
  let value = Math.imul(wrappedX + 17, 374761393)
    + Math.imul(wrappedY + 31, 668265263)
    + Math.imul(period + 11, 1442695041);
  value = Math.imul(value ^ (value >>> 13), 1274126177);
  return ((value ^ (value >>> 16)) >>> 0) / 4294967295;
}

function periodicNoise(x, y, period) {
  const scaledX = x / CLOUD_TEXTURE_SIZE * period;
  const scaledY = y / CLOUD_TEXTURE_SIZE * period;
  const cellX = Math.floor(scaledX);
  const cellY = Math.floor(scaledY);
  const localX = fade(scaledX - cellX);
  const localY = fade(scaledY - cellY);
  const top = latticeValue(cellX, cellY, period) * (1 - localX)
    + latticeValue(cellX + 1, cellY, period) * localX;
  const bottom = latticeValue(cellX, cellY + 1, period) * (1 - localX)
    + latticeValue(cellX + 1, cellY + 1, period) * localX;
  return top * (1 - localY) + bottom * localY;
}

export function createCloudTextureData() {
  const pixels = new Uint8Array(CLOUD_TEXTURE_SIZE * CLOUD_TEXTURE_SIZE * 4);
  const octaves = [
    { period: 4, amplitude: 0.6 },
    { period: 8, amplitude: 0.28 },
    { period: 16, amplitude: 0.12 },
  ];
  for (let y = 0; y < CLOUD_TEXTURE_SIZE; y += 1) {
    for (let x = 0; x < CLOUD_TEXTURE_SIZE; x += 1) {
      let density = 0;
      for (const octave of octaves) {
        density += periodicNoise(x, y, octave.period) * octave.amplitude;
      }
      const value = Math.round(Math.max(0, Math.min(1, density)) * 255);
      const offset = (y * CLOUD_TEXTURE_SIZE + x) * 4;
      pixels[offset] = value;
      pixels[offset + 1] = value;
      pixels[offset + 2] = value;
      pixels[offset + 3] = 255;
    }
  }
  return pixels;
}
