import Light from "../world/light.bend";
import Dirty from "../world/light-dirty.bend";

function listLength(list) {
  let count = 0;
  for (let node = list; node?.$ === "Con"; node = node.tail) count += 1;
  return count;
}

function sources(count) {
  let result = { $: "Nil" };
  for (let index = count - 1; index >= 0; index -= 1) {
    const x = 6n + BigInt((index % 5) * 8);
    const z = 6n + BigInt(Math.floor(index / 5) * 8);
    result = { $: "Con", head: Light.source(x, 2n, z), tail: result };
  }
  return result;
}

function cachedFields(current) {
  let fields = { $: "Nil" };
  for (let node = current; node?.$ === "Con"; node = node.tail) {
    fields = Light.append_fields(Light.source_fields_one(node.head, 1337n), fields);
  }
  return fields;
}

function measure(fn, repeats = 2) {
  fn();
  const start = performance.now();
  for (let repeat = 0; repeat < repeats; repeat += 1) fn();
  return (performance.now() - start) / repeats;
}

const dirty = Dirty.cells_plane(24n, 2n, 24n);
const dirtyCount = listLength(dirty);
const columnDirty = Dirty.cells_column(24n, 2n, 24n);
const columnDirtyCount = listLength(columnDirty);
const editAware = {
  $: "Con",
  head: { $: "Edit", x: 24n, y: 2n, z: 24n, block: 0 },
  tail: { $: "Nil" },
};
const rows = [];
for (const count of [1, 4, 20]) {
  const current = sources(count);
  const fields = cachedFields(current);
  const patchMs = measure(() => Light.patch(current, 1337n, dirty), 2);
  const cachedPatchMs = measure(() => Light.patch_fields(fields, 1337n, dirty), 2);
  const editAwarePatchMs = measure(() => Light.patch_fields_with_edits(fields, editAware, 1337n, dirty), 2);
  const columnEditAwarePatchMs = measure(() => Light.patch_fields_with_edits(fields, editAware, 1337n, columnDirty), 2);
  const fullMs = measure(() => Light.chunk(current, 1337n, 1n, 1n), 2);
  rows.push({
    count,
    dirtyCount,
    columnDirtyCount,
    patchMs,
    cachedPatchMs,
    editAwarePatchMs,
    columnEditAwarePatchMs,
    fullMs,
    cachedSpeedup: fullMs / cachedPatchMs,
  });
}
console.log(JSON.stringify(rows));
