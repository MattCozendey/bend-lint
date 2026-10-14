const AO_MERGE_EPSILON = 0.3;

function sameAo(a, b) {
  if (a === b) return true;
  if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
  return a.every((value, index) => Math.abs(value - b[index]) <= AO_MERGE_EPSILON);
}

function materialSignature(quad) {
  return `${quad.light ?? ""}:${quad.tile ?? ""}:${Array.isArray(quad.ao) ? quad.ao.join(",") : ""}`;
}

function sameMaterial(a, b) {
  if (a.block === 4 || b.block === 4) return false;
  return a.faceIndex === b.faceIndex
    && a.fixed === b.fixed
    && a.block === b.block
    && a.light === b.light
    && a.tile === b.tile
    && sameAo(a.ao, b.ao);
}

function mergePass(quads, horizontal) {
  const sorted = [...quads].sort((a, b) => {
    const fields = horizontal
      ? ["faceIndex", "fixed", "block", "light", "tile", "v", "height", "u"]
      : ["faceIndex", "fixed", "block", "light", "tile", "u", "width", "v"];
    for (const field of fields) {
      if (a[field] !== b[field]) return a[field] - b[field];
    }
    return materialSignature(a).localeCompare(materialSignature(b));
  });
  const merged = [];
  for (const quad of sorted) {
    const previous = merged[merged.length - 1];
    const adjacent = horizontal
      ? previous?.u + previous?.width === quad.u && previous?.v === quad.v && previous?.height === quad.height
      : previous?.v + previous?.height === quad.v && previous?.u === quad.u && previous?.width === quad.width;
    if (previous !== undefined && sameMaterial(previous, quad) && adjacent) {
      merged[merged.length - 1] = {
        ...previous,
        width: horizontal ? previous.width + quad.width : previous.width,
        height: horizontal ? previous.height : previous.height + quad.height,
      };
    } else {
      merged.push(quad);
    }
  }
  return merged;
}

export function mergeChunkQuads(quads) {
  let merged = quads;
  for (let pass = 0; pass < 3; pass += 1) {
    const next = mergePass(mergePass(merged, true), false);
    if (next.length === merged.length) return next;
    merged = next;
  }
  return merged;
}
