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
  await linter.loadRules([fileURLToPath(new URL("./missed-fork.bend", import.meta.url))]),
);
const dir = fs.realpathSync
  .native(fs.mkdtempSync(path.join(os.tmpdir(), "bend-fork-")))
  .replaceAll("\\", "/");
afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));

const lint = async (text: string): Promise<LintResult> => {
  const file = path.posix.join(dir, "main.bend");
  fs.writeFileSync(file, text);
  return unwrap(await linter.lint(file, rules, { config: {} }));
};

// A def of depth `d` whose step is `step`, written under `case 1n++p:`.
const def = (name: string, step: string, returns = "U32", leaf = "1"): string =>
  `def ${name}(d: Nat) -> ${returns}:\n  match d:\n    case 0n:\n      ${leaf}\n    case 1n++p:\n${step}\n`;

const file = (...defs: string[]): string =>
  "import Base\n\ntype T is Data:\n  Leaf{}\n  Node{l: T, r: T}\n\n" + defs.join("\n");

// Each finding's text, whether it has a fix, and the file its fixes give.
const fixed = async (
  text: string,
): Promise<{ flagged: string[]; fixable: boolean[]; text: string }> => {
  const res = await lint(text);
  expect(res.diags.filter((d) => d.code !== "performance/missed-fork").map(linter.render)).toEqual(
    [],
  );
  return {
    flagged: res.diags.map((d) => d.span!.file.text.slice(d.span!.beg, d.span!.end)),
    fixable: res.diags.map((d) => (d.fixes ?? []).length > 0),
    text: applyFixes(res.root!, res.diags).text,
  };
};

// The file passes Bend's check, and the rule finds nothing.
const settled = async (text: string): Promise<void> => {
  expect((await lint(text)).diags.map(linter.render)).toEqual([]);
};

describe("performance/missed-fork", () => {
  test("two calls in one call's arguments are forked", async () => {
    const out = await fixed(file(def("f", "      U32.add(f(p), f(p))")));
    expect(out.flagged).toEqual(["U32.add(f(p), f(p))"]);
    expect(out.text).toBe(file(def("f", "      a b = f(p) f(p)\n      U32.add(a, b)")));
    await settled(out.text);
  });

  test("two calls in a constructor are forked", async () => {
    const out = await fixed(file(def("f", "      Node{f(p), f(p)}", "T", "Leaf{}")));
    expect(out.text).toBe(file(def("f", "      a b = f(p) f(p)\n      Node{a, b}", "T", "Leaf{}")));
    await settled(out.text);
  });

  test("two calls under an operator are forked", async () => {
    const out = await fixed(file(def("f", "      (f(p) + f(p) : U32)")));
    expect(out.text).toBe(file(def("f", "      a b = f(p) f(p)\n      (a + b : U32)")));
    await settled(out.text);
  });

  test("calls nested in other calls of one expression are forked", async () => {
    const out = await fixed(file(def("f", "      U32.add(U32.mul(2, f(p)), f(p))")));
    expect(out.text).toBe(file(def("f", "      a b = f(p) f(p)\n      U32.add(U32.mul(2, a), b)")));
    await settled(out.text);
  });

  test("a let's value is forked on a line before the let", async () => {
    const out = await fixed(file(def("f", "      x = U32.add(f(p), f(p))\n      x")));
    expect(out.text).toBe(
      file(def("f", "      a b = f(p) f(p)\n      x = U32.add(a, b)\n      x")),
    );
    await settled(out.text);
  });

  test("the new names avoid the def's own names", async () => {
    const out = await fixed(file(def("f", "      +a = p\n      U32.add(f(a), f(p))")));
    expect(out.text).toBe(
      file(def("f", "      +a = p\n      b c = f(a) f(p)\n      U32.add(b, c)")),
    );
    await settled(out.text);
  });

  test("lets that follow each other are merged", async () => {
    const out = await fixed(
      file(def("f", "      +l = f(p)\n      r = f(p)\n      (l + r + l : U32)")),
    );
    expect(out.flagged).toEqual(["+l = f(p)\n      r = f(p)"]);
    expect(out.text).toBe(file(def("f", "      +l r = f(p) f(p)\n      (l + r + l : U32)")));
    await settled(out.text);
  });

  test("three lets that follow each other are merged into one", async () => {
    const out = await fixed(
      file(def("f", "      x = f(p)\n      y = f(p)\n      z = f(p)\n      (x + y + z : U32)")),
    );
    expect(out.text).toBe(file(def("f", "      x y z = f(p) f(p) f(p)\n      (x + y + z : U32)")));
    await settled(out.text);
  });

  test("a typed let is reported without a fix", async () => {
    const out = await fixed(
      file(def("f", "      l = f(p)\n      r: U32 = f(p)\n      (l + r : U32)")),
    );
    expect(out.fixable).toEqual([false]);
  });

  test("a let whose call uses the one before is not reported", async () => {
    await settled(
      file(
        "def f(d: Nat, x: U32) -> U32:\n  match d:\n    case 0n:\n      x\n    case 1n++p:\n      +l = f(p, x)\n      r = f(p, l)\n      (l + r : U32)\n",
      ),
    );
  });

  test("a parallel let passes", async () => {
    await settled(file(def("f", "      a b = f(p) f(p)\n      U32.add(a, b)")));
  });

  test("one call per expression passes", async () => {
    await settled(file(def("f", "      U32.add(f(p), 1)")));
  });

  test("calls to other defs pass", async () => {
    await settled(file(def("g", "      g(p)"), def("f", "      U32.add(g(p), g(p))")));
  });

  test("a def that returns IO passes", async () => {
    await settled(
      file(def("f", "      IO.bind(Unit, Unit, f(p), u => f(p))", "IO(Unit)", 'IO.print("x")')),
    );
  });
});
