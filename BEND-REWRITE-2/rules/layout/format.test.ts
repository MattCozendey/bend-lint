// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, lint } from "../../testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when Bend is not given.
const PROGRAM = process.env.BEND_DIR === undefined ? "" : build("rules/layout/format.bend");

const MESSAGE = "Apply canonical formatting.";

// Functions
// =========

const found = (text: string): string[] =>
  lint(PROGRAM, { "main.bend": text }, "main.bend").map(({ at, message }) => at + " " + message);

// Side effects
// ============

setDefaultTimeout(120_000);

(process.env.BEND_DIR === undefined ? describe.skip : describe)("layout/format", () => {
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
    expect(found("import Base\n\ndef pick(n: Nat) -> U32:\n  match n:\n" + cases)).toEqual([]);
    const depth = 300;
    const levels = Array.from({ length: depth }, (_, i) => "  ".repeat(i + 1));
    const nested = [
      "def main() -> U32:",
      ...levels.map((indent) => indent + "("),
      "  ".repeat(depth + 1) + "1",
      ...[...levels].reverse().map((indent) => indent + ")"),
    ];
    expect(found(nested.join("\n") + "\n")).toEqual([]);
  });

  test("a file with a type error is formatted too, but not one that does not parse", () => {
    expect(found('import Base\n\ndef main() -> U32:\n    "text"\n')).toEqual(["4:3 " + MESSAGE]);
    expect(found("import Base\n\ndef main( -> U32:\n    1\n")).toEqual([]);
  });

  test("an empty file ends with a newline; a file of a comment is the comment", () => {
    expect(found("")).toEqual(["1:1 " + MESSAGE]);
    expect(found("\n\n# comment\n\n")).toEqual(["1:1 " + MESSAGE]);
    expect(found("# comment\n")).toEqual([]);
  });
});
