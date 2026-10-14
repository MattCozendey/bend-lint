// Entry router: the menu boots without the engine, the game boots with it.
// Splitting keeps menu loads fast (no Bend compilation) and guarantees a
// clean engine state per session, since switching screens reloads the page.
const params = new URLSearchParams(window.location.search);
const playSession = params.get("play") === "1";
document.body.dataset.mode = playSession ? "game" : "menu";

async function boot() {
  if (playSession) {
    const loading = document.getElementById("world-loading");
    loading?.removeAttribute("hidden");
    loading?.setAttribute("aria-busy", "true");
    await import("./game.js");
    return;
  }
  const { runMenu } = await import("./menu.js");
  runMenu();
}

boot().catch((error) => {
  const errorEl = document.getElementById("error");
  const message = error instanceof Error ? error.message : String(error);
  if (errorEl !== null) {
    errorEl.textContent = `Could not start Bend2Craft.\n${message}`;
    errorEl.hidden = false;
  }
  throw error;
});
