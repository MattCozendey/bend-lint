export function chunkKey(chunkX, chunkZ) {
  return `${chunkX},${chunkZ}`;
}

function listToArray(list) {
  const values = [];
  for (let node = list; node?.$ === "Con"; node = node.tail) values.push(node.head);
  return values;
}

function arrayToList(values) {
  let list = { $: "Nil" };
  for (let index = values.length - 1; index >= 0; index -= 1) {
    list = { $: "Con", head: values[index], tail: list };
  }
  return list;
}

export function buildChunkBuckets(list, chunkSize, getPosition) {
  if (!Number.isInteger(chunkSize) || chunkSize <= 0) throw new RangeError("chunkSize must be positive");
  if (typeof getPosition !== "function") throw new TypeError("getPosition must be a function");
  const values = new Map();
  for (const entry of listToArray(list)) {
    const position = getPosition(entry);
    const key = chunkKey(Math.floor(position.x / chunkSize), Math.floor(position.z / chunkSize));
    const bucket = values.get(key);
    if (bucket === undefined) values.set(key, [entry]);
    else bucket.push(entry);
  }
  return new Map([...values].map(([key, entries]) => [key, arrayToList(entries)]));
}

export function concatBendLists(left, right) {
  return arrayToList([...listToArray(left), ...listToArray(right)]);
}
