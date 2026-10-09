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
  await linter.loadRules([fileURLToPath(new URL("./list-index-loop.bend", import.meta.url))]),
);
const dir = fs.realpathSync
  .native(fs.mkdtempSync(path.join(os.tmpdir(), "bend-list-loop-")))
  .replaceAll("\\", "/");
afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));

const lint = async (text: string): Promise<LintResult> => {
  const file = path.posix.join(dir, "main.bend");
  fs.writeFileSync(file, text);
  return unwrap(await linter.lint(file, rules, { config: {} }));
};

const file = (...defs: string[]): string =>
  "import Base\n\ndef or_zero(m: Maybe<&2, U32>) -> U32:\n  match m:\n    case None{}:\n      0\n    case Some{x}:\n      x\n\n" +
  defs.join("\n");

// A loop of `n` steps over `xs`, whose step is `step`.
const loop = (step: string): string =>
  `def f(n: Nat, +xs: List<&2, U32>, +i: Nat, acc: U32) -> U32:\n  match n:\n    case 0n:\n      acc\n    case 1n+p:\n${step}\n`;

// Each finding's text and message. The file must pass Bend's check.
const found = async (text: string): Promise<Array<{ text: string; message: string }>> => {
  const res = await lint(text);
  expect(
    res.diags.filter((d) => d.code !== "performance/list-index-loop").map(linter.render),
  ).toEqual([]);
  expect(res.diags.every((d) => (d.fixes ?? []).length === 0)).toBe(true);
  return res.diags.map((d) => ({
    text: d.span!.file.text.slice(d.span!.beg, d.span!.end),
    message: d.message,
  }));
};

describe("performance/list-index-loop", () => {
  test("List.get on a list the loop passes unchanged is reported", async () => {
    const out = await found(
      file(loop("      f(p, xs, Nat.add(i, 1n), U32.add(acc, or_zero(List.get(&2, U32, xs, i))))")),
    );
    expect(out).toEqual([
      {
        text: "List.get(&2, U32, xs, i)",
        message:
          "List.get walks xs from its head, and f passes xs unchanged to each call of itself: the loop is O(n²). Walk it instead: match it, use its head, and pass its tail to the next call.",
      },
    ]);
  });

  test("List.length in such a loop asks to compute it once", async () => {
    const out = await found(
      file(loop("      f(p, xs, i, U32.add(acc, U32.from_nat(List.length(&2, U32, xs))))")),
    );
    expect(out.map((o) => o.message)).toEqual([
      "List.length walks xs from its head, and f passes xs unchanged to each call of itself: the loop is O(n²). Compute it once before the loop, and pass it as a parameter.",
    ]);
  });

  test("a loop that passes the list's rest passes", async () => {
    expect(
      await found(
        file(
          loop(
            "      f(p, List.drop(&2, U32, xs, 1n), i, U32.add(acc, or_zero(List.get(&2, U32, xs, 0n))))",
          ),
        ),
      ),
    ).toEqual([]);
  });

  test("a loop that walks the list passes", async () => {
    expect(
      await found(
        file(
          "def f(xs: List<&2, U32>, acc: U32) -> U32:\n  match xs:\n    case Nil{}:\n      acc\n    case h <> t:\n      f(t, U32.add(acc, h))\n",
        ),
      ),
    ).toEqual([]);
  });

  test("List.get outside a loop passes", async () => {
    expect(
      await found(file("def f(xs: List<&2, U32>) -> U32:\n  or_zero(List.get(&2, U32, xs, 3n))\n")),
    ).toEqual([]);
  });

  test("a list that is not a parameter passes", async () => {
    expect(
      await found(
        file(
          "def f(n: Nat, acc: U32) -> U32:\n  match n:\n    case 0n:\n      acc\n    case 1n++p:\n      f(p, U32.add(acc, or_zero(List.get(&2, U32, [1, 2, 3], p))))\n",
        ),
      ),
    ).toEqual([]);
  });
});
