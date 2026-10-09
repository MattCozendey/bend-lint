import { afterAll, describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { applyFixes, createLinter } from "../../src/lint.ts";
import type { LintResult } from "../../src/lint.ts";
import { unwrap } from "../../src/result.ts";

const linter = unwrap(await createLinter());
const rules = unwrap(
  await linter.loadRules([fileURLToPath(new URL("./case.bend", import.meta.url))]),
);
const dir = fs.realpathSync
  .native(fs.mkdtempSync(path.join(os.tmpdir(), "bend-case-")))
  .replaceAll("\\", "/");
afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));
const fixture = (name: string, text: string): string => {
  const file = path.posix.join(dir, name);
  fs.writeFileSync(file, text);
  return file;
};
fixture("leaf.bend", "import Base\n\ndef one() -> U32:\n  1\n");
fixture("law.bend", "import Base\n\nlaw is_Odd:\n  for x: U32\n  U32\n");

const lint = async (text: string): Promise<LintResult> =>
  unwrap(await linter.lint(fixture("main.bend", text), rules, { config: {} }));

// Each finding as the name it flags and its message.
const flagged = async (text: string): Promise<string[][]> => {
  const res = await lint(text);
  expect(res.diags.filter((d) => d.code !== "layout/case").map(linter.render)).toEqual([]);
  return res.diags.map((d) => [d.span!.file.text.slice(d.span!.beg, d.span!.end), d.message]);
};

// The file the suggested fixes give.
const fixed = async (text: string): Promise<string> => {
  const res = await lint(text);
  return applyFixes(res.root!, res.diags, ["safe", "suggested"]).text;
};

describe("layout/case", () => {
  test("names whose case follows their kind pass", async () => {
    expect(
      await flagged(`import Base
import ./leaf.bend as Leaf

type Box<a, -A: Kind(a)> is Kind(a):
  Box{val: A, n_2: U32}

type Box.OP is Data:
  Word32{}

def Both(-A: Type, -B: Type) -> Type:
  A & B

def Fam(F: @-x: U32 -> Type) -> Type:
  F(1)

def Box.from_u32(n: U32) -> U32:
  n

def keep(-T: Data, _x: T) -> T:
  _x

law add_zero:
  for x: U32
  U32

def add_zero(x):
  x

def main() -> U32:
  Leaf.one()
`),
    ).toEqual([]);
  });

  test("each kind of name is reported with the case it takes", async () => {
    expect(
      await flagged(`import Base
import ./leaf.bend as leaf

type my_box is Data:
  my_Box{myVal: U32}

def pair_of(a: Type) -> Type:
  a

def IdF(X: U32) -> U32:
  X

def main() -> U32:
  leaf.one()
`),
    ).toEqual([
      ["leaf", "Rename leaf to Leaf: an import alias is PascalCase."],
      ["my_box", "Rename my_box to MyBox: a type is PascalCase."],
      ["my_Box", "Rename my_Box to MyBox: a constructor is PascalCase."],
      ["myVal", "Rename myVal to my_val: a field that is not a type is snake_case."],
      ["pair_of", "Rename pair_of to PairOf: a def that returns a type is PascalCase."],
      ["a", "Rename a to A: a parameter that is a type is PascalCase."],
      ["IdF", "Rename IdF to id_f: a def that does not return a type is snake_case."],
      ["X", "Rename X to x: a parameter that is not a type is snake_case."],
    ]);
  });

  test("a dotted name is checked by its last segment", async () => {
    expect(
      await flagged(`import Base

type Box is Data:
  Box{}

def Box.fromU32(n: U32) -> Box:
  Box{}

def main() -> Box:
  Box.fromU32(1)
`),
    ).toEqual([
      [
        "Box.fromU32",
        "Rename Box.fromU32 to Box.from_u32: a def that does not return a type is snake_case.",
      ],
    ]);
  });

  test("words split at capitals, and a run of capitals is one word", async () => {
    expect(
      (
        await flagged(`import Base

def parseHTTPHeader(n: U32) -> U32:
  n

def main() -> U32:
  parseHTTPHeader(1)
`)
      ).map(([name, message]) => [name, message.split(":")[0]]),
    ).toEqual([["parseHTTPHeader", "Rename parseHTTPHeader to parse_http_header"]]);
  });

  test("a variable takes either case, and is reported when it fits neither", async () => {
    expect(
      await flagged(`import Base

def main() -> U32:
  Big : U32 = 1
  small : U32 = Big
  myY : U32 = small
  myY
`),
    ).toEqual([
      ["myY", "Rename myY to my_y: this name is snake_case, or PascalCase if it is a type."],
    ]);
  });

  test("a fill of another file's law and import Base are skipped", async () => {
    expect(
      await flagged(`import Base
import ./law.bend as Laws

def Laws.is_Odd(x):
  x

def main() -> U32:
  Laws.is_Odd(1)
`),
    ).toEqual([]);
  });

  test("the fix renames a parameter or variable with its uses, and only them", async () => {
    const text = `import Base

type my_box is Data:
  MyBox{}

def twice(+inputVal: U32) -> U32:
  outVal : U32 = (inputVal + inputVal : U32)
  outVal

def main() -> U32:
  twice(1)
`;
    const out = await fixed(text);
    expect(out).toBe(`import Base

type my_box is Data:
  MyBox{}

def twice(+input_val: U32) -> U32:
  out_val : U32 = (input_val + input_val : U32)
  out_val

def main() -> U32:
  twice(1)
`);
    expect((await flagged(out)).map(([name]) => name)).toEqual(["my_box"]);
  });

  test("no fix renames to a name already in use in the def", async () => {
    const res = await lint(`import Base

def add(fooBar: U32, foo_bar: U32) -> U32:
  (fooBar + foo_bar : U32)

def main() -> U32:
  add(1, 2)
`);
    expect(res.diags.map((d) => [d.message, d.fixes.length])).toEqual([
      ["Rename fooBar to foo_bar: a parameter that is not a type is snake_case.", 0],
    ]);
  });
});
