export function createMeshRebuildScheduler(rebuild, schedule) {
  if (typeof rebuild !== "function") {
    throw new TypeError("mesh rebuild scheduler requires a rebuild function");
  }
  if (typeof schedule !== "function") {
    throw new TypeError("mesh rebuild scheduler requires a frame scheduler");
  }

  let pending = false;
  let requestCount = 0;
  let runCount = 0;

  function request() {
    requestCount += 1;
    if (pending) return false;
    pending = true;
    schedule(() => {
      pending = false;
      runCount += 1;
      rebuild();
    });
    return true;
  }

  return {
    request,
    get pending() { return pending; },
    get requestCount() { return requestCount; },
    get runCount() { return runCount; },
  };
}
