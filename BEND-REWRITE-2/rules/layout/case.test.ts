// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, lint } from "../../testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when Bend is not given.
const PROGRAM = process.env.BEND_DIR === undefined ? "" : build("rules/layout/case.bend");

const LEAF = "import Base\n\ndef one() -> U32:\n  1\n";

const LAW = "import Base\n\nlaw is_Odd:\n  for x: U32\n  U32\n";

// Functions
// =========

// Each finding as where it is and its message.
const flagged = (main: string): string[][] =>
  lint(PROGRAM, { "main.bend": main, "leaf.bend": LEAF, "law.bend": LAW }, "main.bend").map(
    ({ at, message }) => [at, message],
  );

// Side effects
// ============

setDefaultTimeout(120_000);

(process.env.BEND_DIR === undefined ? describe.skip : describe)(() => {
  test("names whose case follows their kind pass", () => {
    expect(
      flagged(`import Base
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

  test("each kind of name is reported with the case it takes", () => {
    expect(
      flagged(`import Base
import ./leaf.bend as leaf

type my_box is Data:
  my_Box{myVal: U32}

def pair_of(a: Type) -> Type:
  a

def IdF(X: U32) -> U32:
  X

law Odd_law:
  for x: U32
  U32

def main() -> U32:
  leaf.one()
`),
    ).toEqual([
      ["2:23", "Rename leaf to Leaf: an import alias is PascalCase."],
      ["4:6", "Rename my_box to MyBox: a type is PascalCase."],
      ["5:3", "Rename my_Box to MyBox: a constructor is PascalCase."],
      ["5:10", "Rename myVal to my_val: a field that is not a type is snake_case."],
      ["7:5", "Rename pair_of to PairOf: a def that returns a type is PascalCase."],
      ["7:13", "Rename a to A: a parameter that is a type is PascalCase."],
      ["10:5", "Rename IdF to id_f: a def that does not return a type is snake_case."],
      ["10:9", "Rename X to x: a parameter that is not a type is snake_case."],
      ["13:5", "Rename Odd_law to odd_law: a law is snake_case."],
    ]);
  });

  test("a parameter whose type is a function to a sort is a type", () => {
    expect(
      flagged(`import Base

def Fam(f: @-x: U32 -> Type) -> Type:
  f(1)
`),
    ).toEqual([["3:9", "Rename f to F: a parameter that is a type is PascalCase."]]);
  });

  test("a binder written bare is a quantity, so snake_case", () => {
    expect(
      flagged(`import Base

type Box<A> is Data:
  Box{}
`),
    ).toEqual([["3:10", "Rename A to a: a parameter that is not a type is snake_case."]]);
  });

  test("a dotted name is checked by its last segment", () => {
    expect(
      flagged(`import Base

type Box is Data:
  Box{}

def Box.fromU32(n: U32) -> Box:
  Box{}

def main() -> Box:
  Box.fromU32(1)
`),
    ).toEqual([
      [
        "6:5",
        "Rename Box.fromU32 to Box.from_u32: a def that does not return a type is snake_case.",
      ],
    ]);
  });

  test("words split at capitals, and a run of capitals is one word", () => {
    expect(
      flagged(`import Base

def parseHTTPHeader(n: U32) -> U32:
  n
`).map(([, message]) => message.split(":")[0]),
    ).toEqual(["Rename parseHTTPHeader to parse_http_header"]);
  });

  test("a variable takes either case, and is reported when it fits neither", () => {
    expect(
      flagged(`import Base

def main() -> U32:
  Big : U32 = 1
  small : U32 = Big
  myY : U32 = small
  myY
`),
    ).toEqual([
      ["6:3", "Rename myY to my_y: this name is snake_case, or PascalCase if it is a type."],
    ]);
  });

  test("a fill of another file's law and import Base are skipped", () => {
    expect(
      flagged(`import Base
import ./law.bend as Laws

def Laws.is_Odd(x):
  x

def main() -> U32:
  Laws.is_Odd(1)
`),
    ).toEqual([]);
  });
});
