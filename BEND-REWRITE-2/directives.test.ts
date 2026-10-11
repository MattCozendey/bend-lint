// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, lint, run } from "./testing.ts";
import type { Found } from "./testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when Bend is not given.
const PROGRAM = process.env.BEND_DIR === undefined ? "" : build("rules/no-unused/imports.bend");

const UTIL = "import Base\n\ndef two() -> U32:\n  2\n";

// The end of a file whose imports V and W are unused.
const TAIL = "\ndef three() -> U32:\n  3\n";

const UNUSED = "no-unused/imports";
const DIRECTIVE = "bend-lint/directive";

// Functions
// =========

const found = (lines: string[]): Found[] =>
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

(process.env.BEND_DIR === undefined ? describe.skip : describe)("directives", () => {
  test("--show-suppressed lists the findings directives suppressed, before the summary", () => {
    const text = [
      "import Base",
      "# bend-lint: disable-next no-unused/imports -- kept on purpose",
      "import ./util.bend as V",
      "import ./util.bend as W # bend-lint: disable-line no-unused/imports -- also kept",
    ].join("\n");
    const ran = run(PROGRAM, { "main.bend": text + "\n" + TAIL, "util.bend": UTIL }, "main.bend", [
      "--show-suppressed",
    ]);
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

  test("disable-next and disable-line cover their lines; a disable that covers nothing is reported", () => {
    expect(
      found([
        "import Base",
        "# bend-lint: disable-next no-unused/imports -- kept on purpose",
        "import ./util.bend as V",
        "import ./util.bend as W # bend-lint: disable-line no-unused/imports -- also kept",
        "# bend-lint: disable-next no-unused/imports -- nothing to disable here",
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

  test("an expect of the finding's severity is met; one of another severity is not", () => {
    expect(
      found([
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

  test("a wrong directive says what is wrong, in order of the checks", () => {
    expect(
      found([
        "import Base",
        "# bend-lint: nonsense",
        "# bend-lint: disable-next no-unused/imports",
        "# bend-lint: disable-next no-unused/imports@warning -- a disable pins nothing",
        "# bend-lint: expect-next no-unused/imports -- an expect pins one",
        "# bend-lint: disable-line no-unused/imports -- not after code",
        "# bend-lint: disable-next bend/check -- reserved",
        "# bend-lint: disable-next no-such/rule -- unknown",
        "# bend-lint: expect-next no-unused/imports@fatal -- not a severity",
        'def text() -> String:\n  "# bend-lint: disable-file no-unused/imports -- in a string, not a comment"',
      ]),
    ).toEqual([
      finding(
        "2:1",
        "error",
        DIRECTIVE,
        "Write `# bend-lint: <disable|expect>-<file|begin|end|next|line> <rule>[@severity] -- <reason>`.",
      ),
      finding("3:1", "error", DIRECTIVE, "A reason is required, after `--`."),
      finding("4:1", "error", DIRECTIVE, "A disable takes no severity."),
      finding("5:1", "error", DIRECTIVE, "An expect pins a severity: no-unused/imports@..."),
      finding("6:1", "error", DIRECTIVE, "A line directive must follow code on its line."),
      finding("7:1", "error", DIRECTIVE, "bend/check findings cannot be suppressed."),
      finding("8:1", "error", DIRECTIVE, "There is no rule no-such/rule."),
      finding("9:1", "error", DIRECTIVE, "fatal is not a severity."),
    ]);
  });

  test("a rule id may nest namespaces", () => {
    expect(found(["import Base", "# bend-lint: disable-next a/b/c -- nested"])).toEqual([
      finding("2:1", "error", DIRECTIVE, "There is no rule a/b/c."),
    ]);
  });

  test("--fix sorts a stack of directives in place: it only rewrites comments, so it is safe", () => {
    const stack = (first: string, second: string): string =>
      [
        "import Base",
        first,
        second,
        "import ./util.bend as V",
        "import ./util.bend as W",
        TAIL,
      ].join("\n");
    const b = "# bend-lint: expect-next no-unused/imports@warning -- b";
    const a = "# bend-lint: disable-next no-unused/imports -- a";
    const ran = run(PROGRAM, { "main.bend": stack(b, a), "util.bend": UTIL }, "main.bend", [
      "--fix",
    ]);
    expect([ran.files["main.bend"], ran.code]).toEqual([stack(a, b), 1]);
  });

  test("begin and end pair; an end that closes nothing, an open begin, and an unsorted stack are reported", () => {
    expect(
      found([
        "import Base",
        "# bend-lint: disable-begin no-unused/imports -- region",
        "import ./util.bend as V",
        "# bend-lint: disable-end no-unused/imports",
        "import ./util.bend as W",
        "# bend-lint: disable-end no-unused/imports",
        "# bend-lint: disable-begin no-unused/imports -- never closed",
        "# bend-lint: expect-next no-unused/imports@warning -- b",
        "# bend-lint: disable-next no-unused/imports -- a",
      ]),
    ).toEqual([
      finding("5:23", "warning", UNUSED, "Remove the import W: nothing uses it."),
      finding("6:1", "error", DIRECTIVE, "This end closes no begin of no-unused/imports."),
      finding("7:1", "error", DIRECTIVE, "This begin of no-unused/imports is never closed."),
      finding(
        "6:1",
        "error",
        DIRECTIVE,
        "Directives that stack must be in order: by rule, then severity, then keyword.",
      ),
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
