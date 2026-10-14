const BIGINT_TAG = "__bend2craft_bigint";

export function encodeSave(value) {
  return JSON.stringify(value, (_key, current) => (
    typeof current === "bigint" ? { [BIGINT_TAG]: current.toString() } : current
  ));
}

export function decodeSave(serialized) {
  if (typeof serialized !== "string") return null;
  try {
    return JSON.parse(serialized, (_key, current) => {
      if (current !== null && typeof current === "object" && typeof current[BIGINT_TAG] === "string") {
        return BigInt(current[BIGINT_TAG]);
      }
      return current;
    });
  } catch {
    return null;
  }
}
