// Imports
// =======

import { afterAll, describe, expect, setDefaultTimeout, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { lintIn } from "../../testing.ts";
import type { Found } from "../../testing.ts";

// Constants
// =========

const RULE = fileURLToPath(new URL("./missed-fork.bend", import.meta.url));
const CODE = "performance/missed-fork";

const dir = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), "bend-rewrite-fork-")));

// Functions
// =========

// A def of depth `d` whose step is `step`, written under `case 1n++p:`.
const def = (name: string, step: string, returns = "U32", leaf = "1"): string =>
  `def ${name}(d: Nat) -> ${returns}:\n  match d:\n    case 0n:\n      ${leaf}\n    case 1n++p:\n${step}\n`;

const file = (...defs: string[]): string =>
  "import Base\n\ntype T is Data:\n  Leaf{}\n  Node{l: T, r: T}\n\n" + defs.join("\n");

// The findings of the rule on `text`, which must pass Bend's check.
const reported = (
  text: string,
): Array<Pick<Found, "code" | "file" | "text" | "message" | "fixes">> => {
  const out = lintIn(dir, { "main.bend": text }, "main.bend", ["--rules", RULE]);
  expect(out.filter((f) => f.code !== CODE)).toEqual([]);
  return out.map(({ code, file, text: at, message, fixes }) => ({
    code,
    file,
    text: at,
    message,
    fixes,
  }));
};

// Side effects
// ============

setDefaultTimeout(300_000);

afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));

describe("performance/missed-fork", () => {
  test("two calls in one call's arguments are reported, with a fix", () => {
    expect(reported(file(def("f", "      U32.add(f(p), f(p))")))).toEqual([
      {
        code: CODE,
        file: "main.bend",
        text: "U32.add(f(p), f(p))",
        message:
          "These 2 calls to f run one after another. Bend forks only the values of a parallel let: `a b = f(..) f(..)`.",
        fixes: ["Fork the calls [dangerous]"],
      },
    ]);
  });

  test("two calls in a constructor are reported", () => {
    expect(
      reported(file(def("f", "      Node{f(p), f(p)}", "T", "Leaf{}"))).map((f) => f.fixes),
    ).toEqual([["Fork the calls [dangerous]"]]);
  });

  test("two calls under an operator are reported", () => {
    expect(reported(file(def("f", "      (f(p) + f(p) : U32)"))).length).toBe(1);
  });

  test("calls nested in other calls of one expression are reported once", () => {
    expect(
      reported(file(def("f", "      U32.add(U32.mul(2, f(p)), f(p))"))).map((f) => f.text),
    ).toEqual(["U32.add(U32.mul(2, f(p)), f(p))"]);
  });

  test("the new names avoid the def's own names", () => {
    expect(
      reported(file(def("f", "      +a = p\n      U32.add(f(a), f(p))"))).map((f) => f.message),
    ).toEqual([
      "These 2 calls to f run one after another. Bend forks only the values of a parallel let: `b c = f(..) f(..)`.",
    ]);
  });

  test("lets that follow each other are reported from the first, with a fix", () => {
    expect(
      reported(file(def("f", "      +l = f(p)\n      r = f(p)\n      (l + r + l : U32)"))),
    ).toEqual([
      {
        code: CODE,
        file: "main.bend",
        text: "+l = f(p)\n      r = f(p)",
        message:
          "These 2 calls to f run one after another. Bend forks only the values of a parallel let: `+l r = f(..) f(..)`.",
        fixes: ["Merge into a parallel let [dangerous]"],
      },
    ]);
  });

  test("three lets that follow each other are one finding", () => {
    expect(
      reported(
        file(def("f", "      x = f(p)\n      y = f(p)\n      z = f(p)\n      (x + y + z : U32)")),
      ).map((f) => f.message),
    ).toEqual([
      "These 3 calls to f run one after another. Bend forks only the values of a parallel let: `x y z = f(..) f(..) f(..)`.",
    ]);
  });

  test("a typed let is reported without a fix", () => {
    expect(
      reported(file(def("f", "      l = f(p)\n      r: U32 = f(p)\n      (l + r : U32)"))).map(
        (f) => f.fixes,
      ),
    ).toEqual([[]]);
  });

  test("a let whose call uses the one before is not reported", () => {
    expect(
      reported(
        file(
          "def f(d: Nat, x: U32) -> U32:\n  match d:\n    case 0n:\n      x\n    case 1n++p:\n      +l = f(p, x)\n      r = f(p, l)\n      (l + r : U32)\n",
        ),
      ),
    ).toEqual([]);
  });

  test("a parallel let passes", () => {
    expect(reported(file(def("f", "      a b = f(p) f(p)\n      U32.add(a, b)")))).toEqual([]);
  });

  test("one call per expression passes", () => {
    expect(reported(file(def("f", "      U32.add(f(p), 1)")))).toEqual([]);
  });

  test("calls to other defs pass", () => {
    expect(reported(file(def("g", "      g(p)"), def("f", "      U32.add(g(p), g(p))")))).toEqual(
      [],
    );
  });

  test("a def that returns IO passes", () => {
    expect(
      reported(
        file(def("f", "      IO.bind(Unit, Unit, f(p), u => f(p))", "IO(Unit)", 'IO.print("x")')),
      ),
    ).toEqual([]);
  });
});

describe("performance/missed-fork fixes", () => {
  // The file `text` becomes when the fixes are applied, dangerous ones included.
  const fixed = (text: string): string => {
    lintIn(dir, { "main.bend": text }, "main.bend", ["--rules", RULE, "--fix-dangerously"]);
    return fs.readFileSync(path.join(dir, "main.bend"), "utf8");
  };
  // The fixed file passes Bend's check, and the rule finds nothing in it.
  const settled = (text: string): void => {
    expect(lintIn(dir, { "main.bend": text }, "main.bend", ["--rules", RULE])).toEqual([]);
  };
  const cases: Array<[string, string, string, string?, string?]> = [
    [
      "two calls in one call's arguments are forked",
      "      U32.add(f(p), f(p))",
      "      a b = f(p) f(p)\n      U32.add(a, b)",
    ],
    [
      "two calls in a constructor are forked",
      "      Node{f(p), f(p)}",
      "      a b = f(p) f(p)\n      Node{a, b}",
      "T",
      "Leaf{}",
    ],
    [
      "two calls under an operator are forked",
      "      (f(p) + f(p) : U32)",
      "      a b = f(p) f(p)\n      (a + b : U32)",
    ],
    [
      "calls nested in other calls of one expression are forked",
      "      U32.add(U32.mul(2, f(p)), f(p))",
      "      a b = f(p) f(p)\n      U32.add(U32.mul(2, a), b)",
    ],
    [
      "a let's value is forked on a line before the let",
      "      x = U32.add(f(p), f(p))\n      x",
      "      a b = f(p) f(p)\n      x = U32.add(a, b)\n      x",
    ],
    [
      "the new names avoid the def's own names",
      "      +a = p\n      U32.add(f(a), f(p))",
      "      +a = p\n      b c = f(a) f(p)\n      U32.add(b, c)",
    ],
    [
      "lets that follow each other are merged",
      "      +l = f(p)\n      r = f(p)\n      (l + r + l : U32)",
      "      +l r = f(p) f(p)\n      (l + r + l : U32)",
    ],
    [
      "three lets that follow each other are merged into one",
      "      x = f(p)\n      y = f(p)\n      z = f(p)\n      (x + y + z : U32)",
      "      x y z = f(p) f(p) f(p)\n      (x + y + z : U32)",
    ],
  ];
  for (const [name, step, want, returns, leaf] of cases) {
    test(name, () => {
      const out = fixed(file(def("f", step, returns, leaf)));
      expect(out).toBe(file(def("f", want, returns, leaf)));
      settled(out);
    });
  }

  test("--fix alone leaves the dangerous fixes", () => {
    const text = file(def("f", "      U32.add(f(p), f(p))"));
    lintIn(dir, { "main.bend": text }, "main.bend", ["--rules", RULE, "--fix"]);
    expect(fs.readFileSync(path.join(dir, "main.bend"), "utf8")).toBe(text);
  });
});
