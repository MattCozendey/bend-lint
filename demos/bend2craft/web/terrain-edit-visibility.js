export function quadContainsCell(quad, x, y, z) {
  if (quad.faceIndex === 0 || quad.faceIndex === 1) {
    return y === quad.y
      && x >= quad.u && x < quad.u + quad.width
      && z >= quad.v && z < quad.v + quad.height;
  }
  if (quad.faceIndex === 2 || quad.faceIndex === 3) {
    return x === quad.x
      && z >= quad.u && z < quad.u + quad.width
      && y >= quad.v && y < quad.v + quad.height;
  }
  return z === quad.z
    && x >= quad.u && x < quad.u + quad.width
    && y >= quad.v && y < quad.v + quad.height;
}

export function canPatchHiddenTerrain(quads, cells) {
  return !quads.some((quad) => (
    (quad.width !== 1 || quad.height !== 1)
    && cells.some(([x, y, z]) => quadContainsCell(quad, x, y, z))
  ));
}
