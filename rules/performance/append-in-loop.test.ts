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
  await linter.loadRules([fileURLToPath(new URL("./append-in-loop.bend", import.meta.url))]),
);
const dir = fs.realpathSync
  .native(fs.mkdtempSync(path.join(os.tmpdir(), "bend-append-loop-")))
  .replaceAll("\\", "/");
afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));

const lint = async (text: string): Promise<LintResult> => {
  const file = path.posix.join(dir, "main.bend");
  fs.writeFileSync(file, text);
  return unwrap(await linter.lint(file, rules, { config: {} }));
};

// A loop of `n` steps over an accumulator of type `T`, whose step is `step`.
const loop = (type: string, step: string): string =>
  `import Base\n\ndef f(n: Nat, acc: ${type}) -> ${type}:\n  match n:\n    case 0n:\n      acc\n    case 1n+p:\n${step}\n`;

// Each finding's text and message. The file must pass Bend's check.
const found = async (text: string): Promise<Array<{ text: string; message: string }>> => {
  const res = await lint(text);
  expect(
    res.diags.filter((d) => d.code !== "performance/append-in-loop").map(linter.render),
  ).toEqual([]);
  expect(res.diags.every((d) => (d.fixes ?? []).length === 0)).toBe(true);
  return res.diags.map((d) => ({
    text: d.span!.file.text.slice(d.span!.beg, d.span!.end),
    message: d.message,
  }));
};

describe("performance/append-in-loop", () => {
  test("List.append to the accumulator of a loop is reported", async () => {
    expect(
      await found(loop("List<&2, U32>", "      f(p, List.append(&2, U32, acc, [1]))")),
    ).toEqual([
      {
        text: "List.append(&2, U32, acc, [1])",
        message:
          "List.append copies acc on each call of f, so building it is O(n²). Build it at its head with `x <> acc`, and reverse it once when the loop ends: `List.reverse(&2, U32, acc)`.",
      },
    ]);
  });

  test("++ to the accumulator of a loop is reported", async () => {
    expect(await found(loop("String", '      f(p, acc ++ "x")'))).toEqual([
      {
        text: 'acc ++ "x"',
        message:
          "++ copies acc on each call of f, so building it is O(n²). Collect the pieces in a list with `piece <> acc`, and join them once when the loop ends: `String.concat(List.reverse(&2, String, acc))`.",
      },
    ]);
  });

  test("a cons at the accumulator's head passes", async () => {
    expect(await found(loop("List<&2, U32>", "      f(p, 1 <> acc)"))).toEqual([]);
  });

  test("an append before the accumulator passes", async () => {
    expect(
      await found(loop("List<&2, U32>", "      f(p, List.append(&2, U32, [1], acc))")),
    ).toEqual([]);
  });

  test("an append that is not passed to the loop passes", async () => {
    expect(
      await found(
        "import Base\n\ndef f(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:\n  match n:\n    case 0n:\n      List.append(&2, U32, acc, [1])\n    case 1n+p:\n      f(p, acc)\n",
      ),
    ).toEqual([]);
  });

  test("an append in a def that does not call itself passes", async () => {
    expect(
      await found(
        "import Base\n\ndef f(acc: List<&2, U32>) -> List<&2, U32>:\n  List.append(&2, U32, acc, [1])\n",
      ),
    ).toEqual([]);
  });
});
