import { createTextureAtlas, ATLAS_COLUMNS, ATLAS_ROWS, ATLAS_TILE_SIZE } from "./web/texture-atlas.js";

const W = ATLAS_COLUMNS * ATLAS_TILE_SIZE;
const H = ATLAS_ROWS * ATLAS_TILE_SIZE;
const px = new Array(W * H).fill(null);
const ctx = {
  imageSmoothingEnabled: true,
  fillStyle: "#000000",
  strokeStyle: "#000000",
  globalAlpha: 1,
  globalCompositeOperation: "source-over",
  fillRect(x, y, w, h) {
    x = Math.round(x); y = Math.round(y); w = Math.round(w); h = Math.round(h);
    for (let j = y; j < y + h; j++) for (let i = x; i < x + w; i++) {
      if (i < 0 || j < 0 || i >= W || j >= H) continue;
      if (this.globalCompositeOperation === "destination-in") {
        if (px[j * W + i] === null) continue;
      } else if (this.globalCompositeOperation === "multiply") {
        continue; // tint pass, ignore for coverage
      } else {
        px[j * W + i] = this.globalAlpha >= 1 ? this.fillStyle : `${this.fillStyle}@${this.globalAlpha}`;
      }
    }
  },
  strokeRect() {},
  clearRect(x, y, w, h) {
    for (let j = y; j < y + h; j++) for (let i = x; i < x + w; i++) px[j * W + i] = null;
  },
};
const gl = {
  TEXTURE_2D: 1, RGBA: 1, UNSIGNED_BYTE: 1, UNPACK_FLIP_Y_WEBGL: 1,
  TEXTURE_MIN_FILTER: 1, TEXTURE_MAG_FILTER: 1, TEXTURE_WRAP_S: 1, TEXTURE_WRAP_T: 1,
  NEAREST: 1, CLAMP_TO_EDGE: 1,
  createTexture: () => ({}), bindTexture() {}, pixelStorei() {},
  texImage2D() {}, texParameteri() {},
};
globalThis.document = { createElement: () => ({ width: 0, height: 0, getContext: () => ctx }) };
createTextureAtlas(gl, { 1: [0.34, 0.38, 0.42], 7: [0.16, 0.5, 0.82] });

function tileDump(id) {
  const c = id % ATLAS_COLUMNS, r = Math.floor(id / ATLAS_COLUMNS);
  const colors = new Set();
  let painted = 0;
  for (let j = 0; j < ATLAS_TILE_SIZE; j++) for (let i = 0; i < ATLAS_TILE_SIZE; i++) {
    const v = px[(r * ATLAS_TILE_SIZE + j) * W + c * ATLAS_TILE_SIZE + i];
    if (v !== null) { painted++; colors.add(v); }
  }
  console.log(`tile ${id}: painted=${painted}/256 colors=${colors.size}`);
}
for (const id of [0, 1, 2, 3, 4, 5, 6, 7, 11, 20, 21, 22]) tileDump(id);
