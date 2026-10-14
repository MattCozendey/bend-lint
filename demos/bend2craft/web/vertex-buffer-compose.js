export function concatFloat32Arrays(...sources) {
  let length = 0;
  for (const source of sources) {
    if (!(Array.isArray(source) || ArrayBuffer.isView(source))) {
      throw new TypeError("vertex buffer sources must be arrays or typed arrays");
    }
    length += source.length;
  }
  const result = new Float32Array(length);
  let offset = 0;
  for (const source of sources) {
    result.set(source, offset);
    offset += source.length;
  }
  return result;
}
