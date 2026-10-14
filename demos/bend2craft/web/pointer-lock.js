export function createPointerLockController(isLocked, request) {
  let pending = false;

  function clearPending() {
    pending = false;
  }

  function requestLock() {
    if (isLocked() || pending) return false;
    pending = true;
    try {
      const result = request();
      if (result !== null && typeof result?.then === "function") {
        result.then(clearPending, clearPending);
      } else {
        queueMicrotask(clearPending);
      }
      return true;
    } catch {
      clearPending();
      return false;
    }
  }

  function handleChange() {
    if (!isLocked()) clearPending();
  }

  return { request: requestLock, handleChange };
}
