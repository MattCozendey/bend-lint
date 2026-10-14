export const DEFAULT_SEED = 1337n;
export const SEED_MODULUS = 1n << 48n;

export function normalizeSeed(value) {
  const seed = typeof value === "bigint" ? value : BigInt(value);
  const normalized = seed % SEED_MODULUS;
  return normalized < 0n ? normalized + SEED_MODULUS : normalized;
}

export function hashSeedText(text) {
  let hash = 1469598103934665603n;
  for (const character of text) {
    hash ^= BigInt(character.codePointAt(0));
    hash = (hash * 1099511628211n) % SEED_MODULUS;
  }
  return hash;
}

export function seedFromSearch(search, fallback = DEFAULT_SEED) {
  const raw = new URLSearchParams(search).get("seed")?.trim();
  if (!raw) return normalizeSeed(fallback);
  if (/^-?\d+$/.test(raw)) return normalizeSeed(BigInt(raw));
  return hashSeedText(raw);
}

export function seedLabel(seed) {
  return normalizeSeed(seed).toString();
}
