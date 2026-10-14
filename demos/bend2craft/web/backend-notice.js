// Where a failed backend hands the player back to the menu.
//
// The requirement is recovery, not an error screen: a renderer that cannot start,
// or a device that dies mid-session, has to leave the player somewhere they can
// choose a different backend rather than on a dead page.
//
// Two pieces of state travel with the recovery, and they have to go to two
// different stores. The notice is about one attempt, so it belongs in
// sessionStorage and is consumed once. The released backend is a preference, so it
// belongs in localStorage next to the options document the menu actually reads.
// Putting the preference in sessionStorage - which is what this did first - leaves
// the pin in place, so the next launch walks into the same wall and the player
// bounces between the world and the menu forever.

export const BACKEND_NOTICE_KEY = "bend2craft-backend-notice";
export const OPTIONS_KEY = "bend2craft-options";

/**
 * Storage is not trusted input. A reason of `undefined` reaching the player as the
 * literal text "undefined" is worse than a vague sentence, so every reason is
 * reduced to text or replaced.
 */
function reasonText(reason) {
  if (typeof reason === "string" && reason.trim().length > 0) return reason.trim();
  if (typeof reason === "number" && Number.isFinite(reason)) return String(reason);
  return "the browser did not report a reason";
}

function storeOrNull(store) {
  try {
    return store ?? null;
  } catch {
    // Touching window.localStorage throws in a sandboxed frame, and that must not
    // take the recovery down with it.
    return null;
  }
}

export function reportBackendFailureAndReturnToMenu({
  renderer,
  reason,
  noticeStore = globalThis.sessionStorage,
  optionsStore = globalThis.localStorage,
  location = globalThis.location,
  fallbackRenderer = "auto",
} = {}) {
  const message = reasonText(reason);

  // Release the pin first, and read-modify-write: the options document also holds
  // the volume levels, the key bindings and the graphics tier, and overwriting it
  // with only a renderer would silently reset everything the player has set.
  const options = storeOrNull(optionsStore);
  if (options !== null) {
    try {
      const current = JSON.parse(options.getItem(OPTIONS_KEY) ?? "{}");
      const next = typeof current === "object" && current !== null ? current : {};
      next.renderer = fallbackRenderer;
      options.setItem(OPTIONS_KEY, JSON.stringify(next));
    } catch {
      // A corrupt or unreadable options document is replaced rather than trusted.
      try {
        options.setItem(OPTIONS_KEY, JSON.stringify({ renderer: fallbackRenderer }));
      } catch { /* a store that refuses writes cannot be helped here */ }
    }
  }

  const notice = storeOrNull(noticeStore);
  if (notice !== null) {
    try {
      notice.setItem(BACKEND_NOTICE_KEY, JSON.stringify({
        renderer: String(renderer ?? "unknown"),
        reason: message,
      }));
    } catch { /* the navigation below still has to happen */ }
  }

  const target = new URL(location?.href ?? "/", location?.origin ?? "http://localhost");
  target.search = "";
  target.hash = "";
  // A cache-busting parameter keeps a back navigation from resurrecting the
  // crashed session.
  target.searchParams.set("renderer-fallback", "1");
  location.assign(target.toString());
  return message;
}

/** Read and clear a pending notice. The menu shows it once, then it is gone. */
export function takeBackendNotice(store = globalThis.sessionStorage) {
  try {
    const raw = store?.getItem(BACKEND_NOTICE_KEY);
    if (raw === null || raw === undefined) return null;
    store.removeItem(BACKEND_NOTICE_KEY);
    const parsed = JSON.parse(raw);
    if (typeof parsed?.reason !== "string" || parsed.reason.length === 0) return null;
    return { renderer: String(parsed.renderer ?? "unknown"), reason: parsed.reason };
  } catch {
    return null;
  }
}

/** A sentence for the player, naming the backend that failed and why. */
export function describeBackendNotice(notice) {
  if (notice === null || notice === undefined || typeof notice !== "object") return "";
  const label = notice.renderer === "webgpu" ? "WebGPU" : "The selected renderer";
  return `${label} could not start on this browser, so the game fell back to WebGL. Reason: ${reasonText(notice.reason)}`;
}
