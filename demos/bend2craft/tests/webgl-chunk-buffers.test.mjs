import assert from "node:assert/strict";
import {
  bindInterleavedPositions,
  bindInterleavedTerrain,
  createWebglChunkBuffers,
} from "../web/webgl-chunk-buffers.js";
import { extractClipPlanes } from "../web/chunk-frustum.js";

function fakeGl() {
  let nextId = 1;
  const live = new Set();
  const calls = [];
  return {
    ARRAY_BUFFER: 34962,
    STATIC_DRAW: 35044,
    FLOAT: 5126,
    live,
    calls,
    createBuffer() {
      const buffer = { id: nextId += 1 };
      live.add(buffer);
      return buffer;
    },
    deleteBuffer(buffer) {
      assert.ok(live.has(buffer), "deleting a buffer that is not live");
      live.delete(buffer);
    },
    bindBuffer(target, buffer) { calls.push(["bind", buffer?.id ?? null]); },
    bufferData(target, data) { calls.push(["data", data.length]); },
    enableVertexAttribArray(location) { calls.push(["enable", location]); },
    vertexAttribPointer(location, size, type, normalized, stride, offset) {
      calls.push(["pointer", location, size, stride, offset]);
    },
  };
}

function quadLayer(x, y, z) {
  const positions = [];
  for (const [dx, dz] of [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]) positions.push(x + dx, y, z + dz);
  const vertices = positions.length / 3;
  return {
    positions: new Float32Array(positions),
    colors: new Float32Array(vertices * 3).fill(1),
    lights: new Float32Array(vertices * 2).fill(1),
    normals: new Float32Array(vertices * 3),
    uvs: new Float32Array(vertices * 2),
    materials: new Float32Array(vertices),
    tiles: new Float32Array(vertices * 4),
    quadCount: 1,
  };
}

const gl = fakeGl();
const buffers = createWebglChunkBuffers(gl);
const a = { key: "0,0", vertexData: { opaque: quadLayer(0, 5, 0), water: null } };
const b = { key: "1,0", vertexData: { opaque: quadLayer(16, 5, 0), water: quadLayer(16, 7, 0) } };
let result = buffers.update([a, b]);
assert.equal(result.mode, "resync");
assert.equal(result.changed, 2);
assert.equal(gl.live.size, 3, "one opaque buffer each and one water buffer");
assert.deepEqual(buffers.totals(), { opaqueVertices: 12, waterVertices: 6, opaqueQuads: 2, waterQuads: 1 });

// Same vertex objects: nothing is re-uploaded.
result = buffers.update([a, b]);
assert.equal(result.mode, "edit");
assert.equal(result.changed, 0);
assert.equal(buffers.stats().reuses, 2);

// An edit replaces one chunk's data in place.
const edited = { key: "0,0", vertexData: { opaque: quadLayer(0, 6, 0), water: null } };
result = buffers.update([edited, b]);
assert.equal(result.mode, "edit");
assert.equal(result.changed, 1);
assert.equal(gl.live.size, 3);

// A chunk leaving the resident set is retired.
result = buffers.update([edited]);
assert.equal(result.mode, "resync");
assert.equal(buffers.size, 1);
assert.equal(gl.live.size, 1);

// Culling: an identity view-projection only keeps geometry inside [-1, 1].
const identity = new Float32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
const near = { key: "n", vertexData: { opaque: { ...quadLayer(-0.5, 0, -0.5) }, water: null } };
buffers.update([edited, near]);
const { visible, metrics } = buffers.select(extractClipPlanes(identity));
assert.deepEqual(visible.map((entry) => entry.key), ["n"]);
assert.equal(metrics.culledChunks, 1);
assert.equal(buffers.select(null).visible.length, 2);

// Interleaved binding follows the shared 72-byte layout.
gl.calls.length = 0;
bindInterleavedTerrain(gl, { id: 99 }, { position: 0, color: 1, light: 2, normal: 3, uv: 4, material: 5, tile: 6 });
const pointers = gl.calls.filter((call) => call[0] === "pointer");
assert.deepEqual(pointers.map((call) => call[4]), [0, 12, 24, 32, 44, 52, 56]);
assert.ok(pointers.every((call) => call[3] === 72));
gl.calls.length = 0;
bindInterleavedTerrain(gl, { id: 99 }, { position: 0, color: 1, light: 2, normal: 3, uv: 4, material: -1, tile: 6 });
assert.equal(gl.calls.filter((call) => call[0] === "pointer").length, 6, "a missing location is skipped");
gl.calls.length = 0;
bindInterleavedPositions(gl, { id: 5 }, 0);
assert.deepEqual(gl.calls.at(-1), ["pointer", 0, 3, 72, 0]);

buffers.dispose();
assert.equal(gl.live.size, 0);
console.log("webgl chunk buffers ok");
