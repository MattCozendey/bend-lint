export function createFixedTicker(stepSeconds, onStep) {
  if (!Number.isFinite(stepSeconds) || stepSeconds <= 0) throw new RangeError("stepSeconds must be positive");
  if (typeof onStep !== "function") throw new TypeError("onStep must be a function");
  let accumulated = 0;
  return {
    advance(deltaSeconds) {
      if (!Number.isFinite(deltaSeconds) || deltaSeconds <= 0) return 0;
      accumulated += Math.min(deltaSeconds, stepSeconds * 8);
      let steps = 0;
      while (accumulated + Number.EPSILON >= stepSeconds) {
        accumulated -= stepSeconds;
        onStep(stepSeconds);
        steps += 1;
      }
      return steps;
    },
    remainder() {
      return accumulated;
    },
    reset() {
      accumulated = 0;
    },
  };
}
