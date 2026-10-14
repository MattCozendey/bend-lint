const FOCUSABLE_SELECTOR = [
  "button:not([disabled])",
  "input:not([disabled]):not([type=\"hidden\"])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  "a[href]",
  "[tabindex]:not([tabindex=\"-1\"])",
].join(",");

function isAvailable(node) {
  return node.disabled !== true
    && node.hidden !== true
    && node.getAttribute?.("aria-hidden") !== "true";
}

export function focusableElements(panel) {
  return [...panel.querySelectorAll(FOCUSABLE_SELECTOR)].filter(isAvailable);
}

export function nextFocusTarget(panel, activeElement, backwards = false) {
  const elements = focusableElements(panel);
  if (elements.length === 0) return null;
  const currentIndex = elements.indexOf(activeElement);
  if (currentIndex === -1) return backwards ? elements.at(-1) : elements[0];
  const offset = backwards ? -1 : 1;
  return elements[(currentIndex + offset + elements.length) % elements.length];
}

export function setShellInert(shell, activePanel) {
  for (const child of shell.children) {
    const inert = activePanel !== null && child !== activePanel;
    if ("inert" in child) child.inert = inert;
    else child.toggleAttribute("inert", inert);
  }
}
