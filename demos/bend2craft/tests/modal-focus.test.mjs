import assert from "node:assert/strict";
import {
  focusableElements,
  nextFocusTarget,
  setShellInert,
} from "../web/modal-focus.js";

function element({ hidden = false, disabled = false, tabIndex = null } = {}) {
  return {
    hidden,
    disabled,
    inert: false,
    tabIndex,
    getAttribute(name) {
      return name === "aria-hidden" && hidden ? "true" : null;
    },
    hasAttribute() {
      return false;
    },
    toggleAttribute() {},
  };
}

const close = element();
const first = element();
const disabled = element({ disabled: true });
const last = element();
const panel = {
  querySelectorAll() {
    return [close, first, disabled, last];
  },
};

assert.deepEqual(focusableElements(panel), [close, first, last]);
assert.equal(nextFocusTarget(panel, close), first);
assert.equal(nextFocusTarget(panel, first, true), close);
assert.equal(nextFocusTarget(panel, last), close);
assert.equal(nextFocusTarget(panel, null, true), last);
assert.equal(nextFocusTarget({ querySelectorAll: () => [] }, null), null);

const shell = { children: [element(), element(), element()] };
setShellInert(shell, shell.children[1]);
assert.equal(shell.children[0].inert, true);
assert.equal(shell.children[1].inert, false);
assert.equal(shell.children[2].inert, true);
setShellInert(shell, null);
assert.ok(shell.children.every((child) => child.inert === false));

console.log("modal focus ok");
