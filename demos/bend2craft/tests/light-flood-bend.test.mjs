import assert from "node:assert/strict";
import Flood from "../world/light-flood.bend";

const emptyWalls = Flood.empty_walls();
const source = Flood.source(1n, 1n);
const direct = Flood.run(Flood.sources(source), emptyWalls, 96n);
assert.ok(Number(Flood.light_at(direct, 4n, 1n).light) > 0);
const lava = Flood.run(Flood.sources(Flood.lava_source(1n, 1n)), emptyWalls, 96n);
assert.equal(Number(Flood.light_at(lava, 1n, 1n).light), 15);

const blocked = Flood.run(
  Flood.sources(source),
  Flood.wall(2n, 1n),
  128n,
);
assert.ok(Number(Flood.light_at(blocked, 3n, 1n).light) > 0);

let enclosure = emptyWalls;
for (const [x, z] of [[2n, 3n], [3n, 2n], [4n, 3n], [3n, 4n]]) {
  enclosure = Flood.wall_list(enclosure, x, z);
}
const sealed = Flood.run(Flood.sources(source), enclosure, 160n);
assert.equal(Flood.light_at(sealed, 3n, 3n).$, "Dark");
console.log("bend light flood ok");
