// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, BUILDS, lint, run } from "./testing.ts";
import type { Found } from "./testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when bend does not run.
const PROGRAM = BUILDS ? await build("no-unused/imports") : "";

const UTIL = "import Base\n\ndef two() -> U32:\n  2\n";

// The end of a file whose imports V and W are unused.
const TAIL = "\ndef three() -> U32:\n  3\n";

const UNUSED = "no-unused/imports";
const DIRECTIVE = "bend-lint/directive";

// Functions
// =========

const found = (lines: string[]): Promise<Found[]> =>
  lint(PROGRAM, { "main.bend": lines.join("\n") + "\n" + TAIL, "util.bend": UTIL }, "main.bend");

const finding = (at: string, severity: string, code: string, message: string): Found => ({
  file: "main.bend",
  at,
  severity,
  code,
  message,
});

// Side effects
// ============

setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)("directives", () => {
  test("--show-suppressed lists the findings directives suppressed, before the summary", async () => {
    const text = [
      "import Base",
      "# bend-lint: disable-next no-unused/imports -- kept on purpose not-expected-because: it is not always found",
      "import ./util.bend as V",
      "import ./util.bend as W # bend-lint: disable-line no-unused/imports -- also kept not-expected-because: it is not always found",
    ].join("\n");
    const ran = await run(
      PROGRAM,
      { "main.bend": text + "\n" + TAIL, "util.bend": UTIL },
      "main.bend",
      ["--show-suppressed"],
    );
    expect(
      ran.out
        .trim()
        .split("\n")
        .map((line) => line.replace(/^.*\/(?=[\w.]+:\d)/, "")),
    ).toEqual([
      "bend-lint: suppressed",
      "main.bend:3:23: warning no-unused/imports: Remove the import V: nothing uses it.",
      "main.bend:4:23: warning no-unused/imports: Remove the import W: nothing uses it.",
      "bend-lint: 0 finding(s), 2 suppressed",
    ]);
  });

  test("disable-next and disable-line cover their lines; a disable that covers nothing is reported", async () => {
    expect(
      await found([
        "import Base",
        "# bend-lint: disable-next no-unused/imports -- kept on purpose not-expected-because: it is not always found",
        "import ./util.bend as V",
        "import ./util.bend as W # bend-lint: disable-line no-unused/imports -- also kept not-expected-because: it is not always found",
        "# bend-lint: disable-next no-unused/imports -- nothing to disable here not-expected-because: it is not always found",
      ]),
    ).toEqual([
      finding(
        "5:1",
        "warning",
        "bend-lint/unused-disable",
        "This disables no-unused/imports, but nothing on the lines it covers needs it.",
      ),
    ]);
  });

  test("an expect of the finding's severity is met; one of another severity is not", async () => {
    expect(
      await found([
        "import Base",
        "# bend-lint: expect-next no-unused/imports@warning -- met",
        "import ./util.bend as V",
        "# bend-lint: expect-next no-unused/imports@error -- wrong severity",
        "import ./util.bend as W",
      ]),
    ).toEqual([
      finding("5:23", "warning", UNUSED, "Remove the import W: nothing uses it."),
      finding(
        "4:1",
        "error",
        "bend-lint/unmet-expectation",
        "Expected a no-unused/imports@error finding on the lines this covers; none.",
      ),
    ]);
  });

  test("a wrong directive says what is wrong, in order of the checks", async () => {
    expect(
      await found([
        "import Base",
        "# bend-lint: nonsense",
        "# bend-lint: disable-next no-unused/imports",
        "# bend-lint: disable-next no-unused/imports@warning -- a disable pins nothing not-expected-because: it is not always found",
        "# bend-lint: disable-next no-unused/imports -- a reason, but not why it is no expect",
        "# bend-lint: disable-next no-unused/imports -- a reason -- with dashes not-expected-because:",
        "# bend-lint: expect-next no-unused/imports -- an expect pins one",
        "# bend-lint: disable-line no-unused/imports -- not after code not-expected-because: it is not always found",
        "# bend-lint: disable-next bend-lint/directive -- reserved not-expected-because: it is not always found",
        "# bend-lint: disable-next no-such/rule -- unknown not-expected-because: it is not always found",
        "# bend-lint: expect-next no-unused/imports@fatal -- not a severity",
        'def text() -> String:\n  "# bend-lint: disable-file no-unused/imports -- in a string, not a comment"',
      ]),
    ).toEqual([
      finding(
        "2:1",
        "error",
        DIRECTIVE,
        "Write `# bend-lint: <disable|expect>-<file|begin|end|next|line> <rule>[@severity] -- <reason>`, and, for a disable, not-expected-because: <why> after it.",
      ),
      finding("3:1", "error", DIRECTIVE, "A reason is required, after `--`."),
      finding("4:1", "error", DIRECTIVE, "A disable takes no severity."),
      finding(
        "5:1",
        "error",
        DIRECTIVE,
        "A disable says why it is not an expect, after its reason: not-expected-because: <why>",
      ),
      finding(
        "6:1",
        "error",
        DIRECTIVE,
        "Say why it is not an expect, after not-expected-because:",
      ),
      finding("7:1", "error", DIRECTIVE, "An expect pins a severity: no-unused/imports@..."),
      finding("8:1", "error", DIRECTIVE, "A line directive must follow code on its line."),
      finding("9:1", "error", DIRECTIVE, "bend-lint/directive findings cannot be suppressed."),
      finding("10:1", "error", DIRECTIVE, "There is no rule no-such/rule."),
      finding("11:1", "error", DIRECTIVE, "fatal is not a severity."),
    ]);
  });

  test("a rule id may nest namespaces", async () => {
    expect(
      await found([
        "import Base",
        "# bend-lint: disable-next a/b/c -- nested not-expected-because: it is not always found",
      ]),
    ).toEqual([finding("2:1", "error", DIRECTIVE, "There is no rule a/b/c.")]);
  });

  test("begin and end pair; an end that closes nothing, and an open begin, are reported", async () => {
    expect(
      await found([
        "import Base",
        "# bend-lint: disable-begin no-unused/imports -- region not-expected-because: it is not always found",
        "import ./util.bend as V",
        "# bend-lint: disable-end no-unused/imports",
        "import ./util.bend as W",
        "# bend-lint: disable-end no-unused/imports",
        "# bend-lint: disable-begin no-unused/imports -- never closed not-expected-because: it is not always found",
        "# bend-lint: expect-next no-unused/imports@warning -- b",
        "# bend-lint: disable-next no-unused/imports -- a not-expected-because: it is not always found",
      ]),
    ).toEqual([
      finding("5:23", "warning", UNUSED, "Remove the import W: nothing uses it."),
      finding("6:1", "error", DIRECTIVE, "This end closes no begin of no-unused/imports."),
      finding("7:1", "error", DIRECTIVE, "This begin of no-unused/imports is never closed."),
      finding(
        "7:1",
        "warning",
        "bend-lint/unused-disable",
        "This disables no-unused/imports, but nothing on the lines it covers needs it.",
      ),
      finding(
        "8:1",
        "error",
        "bend-lint/unmet-expectation",
        "Expected a no-unused/imports@warning finding on the lines this covers; none.",
      ),
      finding(
        "9:1",
        "warning",
        "bend-lint/unused-disable",
        "This disables no-unused/imports, but nothing on the lines it covers needs it.",
      ),
    ]);
  });
});
