// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, BUILDS, lint, run } from "../../testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when bend does not run.
const PROGRAM = BUILDS ? build("rules/layout/format.bend") : "";

const MESSAGE = "Apply canonical formatting.";

// Functions
// =========

const found = (text: string, options?: Record<string, unknown>): string[] =>
  lint(
    PROGRAM,
    {
      "main.bend": text,
      ...(options === undefined
        ? {}
        : { "bend-lint.json": JSON.stringify({ rules: { "layout/format": options } }) }),
    },
    "main.bend",
  ).map(
    ({ at, severity, message }) =>
      at + " " + (severity === "warning" ? "" : severity + " ") + message,
  );

// The config error a run with `options` stops with.
const refused = (options: Record<string, unknown>): string => {
  const ran = run(
    PROGRAM,
    {
      "main.bend": "import Base\n",
      "bend-lint.json": JSON.stringify({ rules: { "layout/format": options } }),
    },
    "main.bend",
  );
  expect(ran.code).toBe(2);
  return ran.err.trim();
};

// Side effects
// ============

setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)("layout/format", () => {
  test("a formatted file passes; spacing, indentation, gaps, CRLF and the final newline are reported", () => {
    expect(
      found(
        "import Base\n\ntype N is Data:\n  Z{}\n  S{p: N}\n\ndef id(x: N) -> N:\n  x\n\ndef main() -> N:\n  id(S{Z{}})\n",
      ),
    ).toEqual([]);
    expect(
      found(
        "import   Base\r\n\r\n\r\ntype N is Data:\r\n    Z{}  \r\n    S{p:N}\r\ndef id(x:N)->N:\r\n\tx  \r\ndef main()->N: id(S{Z{}})",
      ),
    ).toEqual(["1:8 " + MESSAGE]);
  });

  test("a file is reported where it first differs from its formatted text", () => {
    expect(found("import Base\n\ndef main() -> U32:\n    1\n")).toEqual(["4:3 " + MESSAGE]);
    expect(found("import Base\n\ndef main() -> U32:\n  1")).toEqual(["4:4 " + MESSAGE]);
  });

  test("long files and deep nesting format", () => {
    const cases = Array.from({ length: 1000 }, (_, i) => `    case ${i}n: ${i}\n`).join("");
    expect(
      found("import Base\n\ndef pick(n: Nat) -> U32:\n  match n:\n" + cases + "    case _: 1000\n"),
    ).toEqual([]);
    const depth = 300;
    const levels = Array.from({ length: depth }, (_, i) => "  ".repeat(i + 1));
    const nested = [
      "import Base",
      "",
      "def main() -> U32:",
      ...levels.map((indent) => indent + "("),
      "  ".repeat(depth + 1) + "1",
      ...[...levels].reverse().map((indent) => indent + ")"),
    ];
    expect(found(nested.join("\n") + "\n")).toEqual([]);
  });

  test("a file with a type error is formatted too, but not one that does not parse", () => {
    expect(found('import Base\n\ndef main() -> U32:\n    "text"\n')).toEqual([
      "4:5 error Error:",
      "4:3 " + MESSAGE,
    ]);
    expect(found("import Base\n\ndef main( -> U32:\n    1\n")).toEqual(["3:12 error Error:"]);
  });

  test("tabWidth sets the indentation", () => {
    expect(found("import Base\n\ndef main() -> U32:\n    1\n", { tabWidth: 4 })).toEqual([]);
  });

  test('wrapAtWidth sets where lines wrap; "never" wraps none that may stay', () => {
    const long =
      "import Base\n\ndef choose(first: U32, second: U32, third: U32) -> U32:\n  first\n";
    expect(found(long)).toEqual([]);
    expect(found(long, { wrapAtWidth: 28 })).toEqual(["3:12 " + MESSAGE]);
    expect(found(long, { wrapAtWidth: 28, tabWidth: 2, endOfLine: "lf" })).toEqual([
      "3:12 " + MESSAGE,
    ]);
    expect(found(long, { wrapAtWidth: "never" })).toEqual([]);
  });

  test('endOfLine sets line ends: "crlf", or "preserve" the first', () => {
    expect(found("import Base\n\ndef main() -> U32:\n  1\n", { endOfLine: "crlf" })).toEqual([
      "1:12 " + MESSAGE,
    ]);
    const crlf = "import Base\r\n\r\ndef main() -> U32:\r\n  1\r\n";
    expect(found(crlf, { endOfLine: "crlf" })).toEqual([]);
    expect(found(crlf, { endOfLine: "preserve" })).toEqual([]);
  });

  test("the config can set the severity beside the options", () => {
    expect(found("import Base\n\ndef main() -> U32:\n    1\n", { severity: "error" })).toEqual([
      "4:3 error " + MESSAGE,
    ]);
  });

  test("an option it does not declare, or a value it does not take, stops the run", () => {
    expect(refused({ tabwidth: 4 })).toBe(
      "bend-lint config: layout/format: it has no option tabwidth",
    );
    expect(refused({ tabWidth: 0 })).toBe(
      "bend-lint config: layout/format: tabWidth does not take that value",
    );
    expect(refused({ wrapAtWidth: "always" })).toBe(
      "bend-lint config: layout/format: wrapAtWidth does not take that value",
    );
  });

  test("an empty file ends with a newline; a file of a comment is the comment", () => {
    expect(found("")).toEqual(["1:1 " + MESSAGE]);
    expect(found("\n\n# comment\n\n")).toEqual(["1:1 " + MESSAGE]);
    expect(found("# comment\n")).toEqual([]);
  });

  test("--fix-dangerously writes the formatted file; --fix makes no fix it cannot prove safe", () => {
    const text =
      "import   Base\r\n\r\n\r\ntype N is Data:\r\n    Z{}  \r\n    S{p:N}\r\ndef id(x:N)->N:\r\n\tx  \r\ndef main()->N: id(S{Z{}})";
    const safe = run(PROGRAM, { "main.bend": text }, "main.bend", ["--fix"]);
    expect([safe.files["main.bend"], safe.out.trim().split("\n").at(-1)]).toEqual([
      text,
      "bend-lint: 1 finding(s), 0 fixed",
    ]);
    const dangerous = run(PROGRAM, { "main.bend": text }, "main.bend", ["--fix-dangerously"]);
    expect([dangerous.files["main.bend"], dangerous.out.trim().split("\n").at(-1)]).toEqual([
      "import Base\n\ntype N is Data:\n  Z{}\n  S{p: N}\n\ndef id(x: N) -> N:\n  x\n\ndef main() -> N:\n  id(S{Z{}})\n",
      "bend-lint: 1 finding(s), 1 fixed",
    ]);
  });
});
