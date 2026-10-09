import { afterAll, describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { createLinter } from "../../src/lint.ts";
import type { LintResult } from "../../src/lint.ts";
import { unwrap } from "../../src/result.ts";

const linter = unwrap(await createLinter());
const rules = unwrap(
  await linter.loadRules([fileURLToPath(new URL("./deep-call-in-fork.bend", import.meta.url))]),
);
const dir = fs.realpathSync
  .native(fs.mkdtempSync(path.join(os.tmpdir(), "bend-deep-fork-")))
  .replaceAll("\\", "/");
afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));

const lint = async (text: string): Promise<LintResult> => {
  const file = path.posix.join(dir, "main.bend");
  fs.writeFileSync(file, text);
  return unwrap(await linter.lint(file, rules, { config: {} }));
};

// 2^d, recursing without a tail call.
const deep =
  "def pow2(d: Nat) -> U32:\n  match d:\n    case 0n:\n      1\n    case 1n+p:\n      +h = pow2(p)\n      U32.add(h, h)\n";

// 2^d times acc, with a tail call.
const flat =
  "def pow2(d: Nat, +acc: U32) -> U32:\n  match d:\n    case 0n:\n      acc\n    case 1n+p:\n      pow2(p, U32.add(acc, acc))\n";

// A fork over lo .. lo + 2^d - 1, whose leaf is `leaf` and whose step is
// `step`.
const fork = (step: string, leaf = "lo"): string =>
  `def f(d: Nat, +lo: U32) -> U32:\n  match d:\n    case 0n:\n      ${leaf}\n    case 1n++p:\n${step}\n`;

const file = (...defs: string[]): string => "import Base\n\n" + defs.join("\n");

// Each finding's text. The file must pass Bend's check, and no finding has
// a fix.
const found = async (text: string): Promise<string[]> => {
  const res = await lint(text);
  expect(
    res.diags.filter((d) => d.code !== "performance/deep-call-in-fork").map(linter.render),
  ).toEqual([]);
  expect(res.diags.every((d) => (d.fixes ?? []).length === 0)).toBe(true);
  return res.diags.map((d) => d.span!.file.text.slice(d.span!.beg, d.span!.end));
};

describe("performance/deep-call-in-fork", () => {
  test("a call in a fork's value is reported", async () => {
    const res = await lint(
      file(deep, fork("      a b = f(p, lo) f(p, U32.add(lo, pow2(p)))\n      U32.add(a, b)")),
    );
    expect(res.diags.map((d) => d.message)).toEqual([
      "pow2 recurses without a tail call, and f calls it at each fork. In our tests, such a call cut the 16-thread speedup from 10x to 1.9x; a tail call kept it. Make pow2 tail-recursive with an accumulator, compute its value with native operations, or pass it down as a parameter.",
    ]);
    expect(await found(res.root!.text)).toEqual(["pow2(p)"]);
  });

  test("a call in a let just before the fork is reported", async () => {
    expect(
      await found(
        file(
          deep,
          fork(
            "      +h = pow2(p)\n      a b = f(p, lo) f(p, U32.add(lo, h))\n      U32.add(a, b)",
          ),
        ),
      ),
    ).toEqual(["pow2(p)"]);
  });

  test("a def with a tail call passes", async () => {
    expect(
      await found(
        file(flat, fork("      a b = f(p, lo) f(p, U32.add(lo, pow2(p, 1)))\n      U32.add(a, b)")),
      ),
    ).toEqual([]);
  });

  test("the call in a leaf passes", async () => {
    expect(
      await found(
        file(
          deep,
          fork(
            "      a b = f(p, lo) f(p, U32.add(lo, U32.shln(1, p)))\n      U32.add(a, b)",
            "U32.add(lo, pow2(5n))",
          ),
        ),
      ),
    ).toEqual([]);
  });

  test("the call without a fork passes", async () => {
    expect(
      await found(file(deep, fork("      U32.add(f(p, lo), f(p, U32.add(lo, pow2(p))))"))),
    ).toEqual([]);
  });

  test("a fork's calls of its own def pass", async () => {
    expect(
      await found(
        file(fork("      a b = f(p, lo) f(p, U32.add(lo, U32.shln(1, p)))\n      U32.add(a, b)")),
      ),
    ).toEqual([]);
  });
});
