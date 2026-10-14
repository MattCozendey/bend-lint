// The Bend list ADT, as the JavaScript side has to speak it.
//
// Bend compiles a `List a` to a linked `{ $: "Con", head, tail }` / `{ $: "Nil" }`
// chain. That shape is a contract with the compiled runtime, not an internal
// detail, so it gets one definition here instead of a private fold-and-walk in
// every module that has to hand a list to Bend or read one back.

/** Fold an array into a Bend list, preserving order. */
export function bendList(values) {
  let list = { $: "Nil" };
  for (let index = values.length - 1; index >= 0; index -= 1) {
    list = { $: "Con", head: values[index], tail: list };
  }
  return list;
}

/** Walk a Bend list into an array, preserving order. */
export function listValues(list) {
  const values = [];
  for (let node = list; node?.$ === "Con"; node = node.tail) values.push(node.head);
  return values;
}

/** Count the elements of a Bend list without materialising them. */
export function listLength(list) {
  let count = 0;
  for (let node = list; node?.$ === "Con"; node = node.tail) count += 1;
  return count;
}

/**
 * Split a flat cell array into the region's y-plane list, the shape
 * `Player.region_block` reads: one list per height, each holding `perPlane` cells in
 * the array's own order.
 *
 * The region is indexed by a list walk, so a flat list makes every cell lookup cost
 * the cell's position in the region. Splitting by height bounds a lookup at
 * `height + perPlane` and leaves the contents of each array untouched, so a fixture
 * written as `for y, for z, for x` keeps meaning the same cells.
 */
export function bendPlanes(values, perPlane) {
  const planes = [];
  for (let start = 0; start + perPlane <= values.length; start += perPlane) {
    planes.push(bendList(values.slice(start, start + perPlane)));
  }
  return bendList(planes);
}
