function validInteger(value) {
  return Number.isInteger(value);
}

// A Bend Nat cannot be negative and the 2.0.32 JS lane refuses one outright,
// so the caller encodes each point through the same cell rule the rest of the
// adapter uses. The value is already encoded when it arrives here, and encoding
// it twice would name a different cell.
function toSurfacePointList(points) {
  let list = { $: "Nil" };
  for (let index = points.length - 1; index >= 0; index -= 1) {
    const point = points[index];
    list = {
      $: "Con",
      head: { $: "SurfacePoint", x: BigInt(point.x), z: BigInt(point.z) },
      tail: list,
    };
  }
  return list;
}

function materialize(values, count) {
  if (Array.isArray(values) || ArrayBuffer.isView(values)) {
    if (values.length < count) throw new TypeError("surface sampler returned too few cells");
    return Array.from({ length: count }, (_, index) => Number(values[index] ?? 0));
  }

  const result = [];
  let node = values;
  while (node?.$ === "Con" && result.length < count) {
    result.push(Number(node.head));
    node = node.tail;
  }
  if (result.length !== count || node?.$ !== "Nil") {
    throw new TypeError("surface sampler must return a fixed-size array or list");
  }
  return result;
}

export function sampleSignedSurfaceGrid({
  minX,
  minZ,
  columns,
  rows,
  step,
  encodeCoordinate,
  sample,
}) {
  if (![minX, minZ, columns, rows, step].every(validInteger)) {
    throw new TypeError("signed surface grid arguments must be integers");
  }
  if (columns < 1 || rows < 1 || step < 1) {
    throw new RangeError("signed surface grid dimensions must be positive");
  }
  if (typeof encodeCoordinate !== "function" || typeof sample !== "function") {
    throw new TypeError("signed surface grid requires coordinate encoding and sampling functions");
  }

  const points = [];
  const coordinates = [];
  for (let row = 0; row < rows; row += 1) {
    for (let column = 0; column < columns; column += 1) {
      const worldX = minX + column * step;
      const worldZ = minZ + row * step;
      coordinates.push([worldX, worldZ]);
      points.push({
        x: encodeCoordinate(worldX),
        z: encodeCoordinate(worldZ),
      });
    }
  }

  const values = materialize(
    sample(BigInt(points.length), toSurfacePointList(points)),
    points.length,
  );
  return { values, coordinates };
}
