export function createWorkerScheduler(size) {
  if (!Number.isInteger(size) || size < 1) {
    throw new RangeError("worker pool size must be a positive integer");
  }
  let cursor = 0;
  return {
    size,
    next() {
      const index = cursor;
      cursor = (cursor + 1) % size;
      return index;
    },
  };
}
