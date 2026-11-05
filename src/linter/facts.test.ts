// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { buildRule, BUILDS, getRunOutcome } from "./testing.ts";

// Constants
// =========

// The test rule this file runs: tests/types runs the def types of tests.bend.
const TYPES = "tests/types";

// Side effects
// ============

await buildRule(TYPES);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)("facts", () => {
  test("a later run sees each file as it is now, the checker's types included", async () => {
    const getAddFile = (t: string): string =>
      `import Base\n\ndef add(a: ${t}, b: ${t}) -> ${t}:\n  (a + b : ${t})\n`;
    const first = await getRunOutcome(TYPES, { "main.bend": getAddFile("U32") }, "main.bend");
    const again = await getRunOutcome(TYPES, {}, "main.bend", [], first.dir);
    const changed = await getRunOutcome(
      TYPES,
      { "main.bend": getAddFile("F32") },
      "main.bend",
      [],
      first.dir,
    );
    expect([first.out.includes("type: U32"), again.out, changed.out.includes("type: F32")]).toEqual(
      [true, first.out, true],
    );
  });
});
