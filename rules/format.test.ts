import { afterAll, describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { applyFixes, createLinter } from "../src/lint.ts";
import type { LintOptions, LintResult, LintRule, Options } from "../src/lint.ts";
import { unwrap } from "../src/result.ts";
import { format, rules } from "./format.ts";
import type { FormatOptions } from "./format.ts";

const linter = unwrap(await createLinter());
const lint = async (
  file: string,
  rules: LintRule[],
  options?: LintOptions,
): Promise<LintResult> => {
  const res = unwrap(await linter.lint(file, rules, options));
  const crash = res.diags.find((d) => d.code === "bend-lint/rule-crash");
  if (crash !== undefined) {
    throw new Error(crash.message);
  }
  return res;
};
const clean = (res: LintResult): boolean => !res.diags.some((d) => d.severity === "error");
const { render } = linter;

// The error `p` rejects with; a `p` that fulfills fails the test.
const rejection = async (p: Promise<unknown>): Promise<Error> => {
  try {
    await p;
  } catch (e) {
    return e instanceof Error ? e : new Error(String(e));
  }
  throw new Error("expected a rejection");
};

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "bend-format-"));
afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));
const opts = { tabWidth: 2, wrapAtWidth: 100, endOfLine: "lf" } as const;
const fixture = (text: string, name = "main.bend") => {
  const file = path.join(dir, name);
  fs.writeFileSync(file, text);
  return file;
};
async function fixed(text: string, options: FormatOptions = opts) {
  const result = await lint(fixture(text), rules, {
    config: { rules: { "format/layout": options } },
  });
  if (!clean(result)) throw new Error(result.diags.map(render).join("\n"));
  expect(clean(result)).toBe(true);
  expect(result.diags.every((d) => d.fixes.length === 1)).toBe(true);
  const source = result.sources.find((s) => s.root)!;
  const output = applyFixes(source, result.diags).text;
  expect(format(output, options)).toBe(output);
  const again = await lint(fixture(output), rules, {
    config: { rules: { "format/layout": options } },
  });
  expect([clean(again), again.diags]).toEqual([true, []]);
  const Bend = result.unstable.Bend;
  const bodies = [result.unstable.book, again.unstable.book].map((book) =>
    Object.fromEntries(
      book.order.flatMap((name) => {
        const tld = book.tlds[name];
        return tld.$ === "Def" && tld.e !== undefined && !tld.b
          ? [[name, Bend.term_show(tld.e)]]
          : [];
      }),
    ),
  );
  expect(bodies[1]).toEqual(bodies[0]);
  return output;
}

describe("format/layout", () => {
  test("ordinary names cannot open delimiter groups", () => {
    const source =
      "import Base\ndef constructor() -> U32: 1\ndef toString() -> U32: 2\ndef valueOf() -> U32: 3\n";
    expect(format(source, opts)).toBe(
      "import Base\n\ndef constructor() -> U32:\n  1\n\ndef toString() -> U32:\n  2\n\ndef valueOf() -> U32:\n  3\n",
    );
  });
  test("its options: defaults, the wrapAtWidth union, and what it rejects", async () => {
    const file = fixture("import Base\n\ndef main() -> U32:\n  1\n");
    const run = (options: Options) =>
      lint(file, rules, { config: { rules: { "format/layout": options } } });
    expect((await run({})).diags).toEqual([]);
    for (const good of [
      { wrapAtWidth: "never" },
      ...["lf", "crlf", "preserve"].map((e) => ({ endOfLine: e })),
    ]) {
      expect(clean(await run(good))).toBe(true);
    }
    for (const bad of [0, -1, 1.5, "2", true]) {
      expect((await rejection(run({ tabWidth: bad }))).message).toMatch("tabWidth must match");
      expect((await rejection(run({ wrapAtWidth: bad }))).message).toMatch(
        "wrapAtWidth must match",
      );
    }
    expect((await rejection(run({ wrapAtWidth: "always" }))).message).toMatch(
      "wrapAtWidth must match",
    );
    for (const endOfLine of ["auto", "LF", "", 1, true]) {
      expect((await rejection(run({ endOfLine }))).message).toMatch("endOfLine must match");
    }
    expect((await rejection(run({ breakLines: true }))).message).toMatch("no option breakLines");
  });

  test("formats a file with a type error, but not one that does not parse", async () => {
    const run = async (text: string) =>
      (await lint(fixture("import Base\n\n\ndef main() -> U32:\n    " + text + "\n"), rules)).diags;
    const typed = await run('"x"');
    expect(typed.map((d) => d.code)).toEqual(["bend/check", "format/layout"]);
    expect(typed[1].fixes.length).toBe(1);
    const parsed = await run("(1");
    expect(parsed.map((d) => [d.code, d.fixes.length])).not.toContainEqual(["format/layout", 1]);
  });

  test("one sweep formats spacing, indentation, gaps, CRLF and final newline", async () => {
    const output = await fixed(
      "import   Base\r\n\r\n\r\ntype N is Data:\r\n    Z{}  \r\n    S{p:N}\r\ndef id(x:N)->N:\r\n\tx  \r\ndef main()->N: id(S{Z{}})",
    );
    expect(output).toBe(
      "import Base\n\ntype N is Data:\n  Z{}\n  S{p: N}\n\ndef id(x: N) -> N:\n  x\n\ndef main() -> N:\n  id(S{Z{}})\n",
    );
  });

  test("CRLF applies to declarations, wrapping, comments and the final newline", async () => {
    const source =
      "import Base\n#header\ndef f(first: U32, second: U32) -> U32: first\ndef main() -> U32: f(123456789, 234567890)";
    const options = { ...opts, wrapAtWidth: 20 };
    const lf = await fixed(source, options);
    expect(await fixed(source, { ...options, endOfLine: "crlf" })).toBe(
      lf.replaceAll("\n", "\r\n"),
    );
  });

  test("preserve uses the first ending in mixed files and falls back to LF", async () => {
    const options = { ...opts, endOfLine: "preserve" } as const;
    const source = "import Base\ndef main() -> U32: 1\n";
    const lf = await fixed(source);
    expect(await fixed(source.replace("\n", "\r\n"), options)).toBe(lf.replaceAll("\n", "\r\n"));
    expect(await fixed(source.replace(/\n$/, "\r\n"), options)).toBe(lf);
    expect(await fixed("def main() -> Type: Type", options)).toBe("def main() -> Type:\n  Type\n");
  });

  test("line ending options preserve literal contents", () => {
    const source = 'def main() -> String:\n  "first\r\nsecond\nthird"\n';
    for (const endOfLine of ["lf", "crlf", "preserve"] as const) {
      const options = { ...opts, endOfLine };
      const newline = endOfLine === "crlf" ? "\r\n" : "\n";
      const output = format(source, options);
      expect(output).toBe(
        "def main() -> String:" + newline + '  "first\r\nsecond\nthird"' + newline,
      );
      expect(format(output, options)).toBe(output);
    }
  });

  test("wrapped lists use one item per line and relative indentation", async () => {
    const source =
      "import Base\ndef choose(first: U32, second: U32, third: U32) -> U32:\n  first\ndef main() -> U32:\n  choose(123456789, 234567890, 345678901)\n";
    const output = await fixed(source, { tabWidth: 4, wrapAtWidth: 28 });
    expect(output).toContain(
      "def choose(\n    first: U32,\n    second: U32,\n    third: U32\n) -> U32:",
    );
    expect(output).toContain(
      "    choose(\n        123456789,\n        234567890,\n        345678901\n    )",
    );
  });

  test('"never" collapses optional wrapping but retains statement boundaries', async () => {
    const source =
      "import Base\ndef f(x: U32, y: U32) -> U32:\n  x\ndef main() -> U32:\n  x = f(\n    1,\n    2\n  )\n  f(x, 3)\n";
    expect(await fixed(source, { tabWidth: 2, wrapAtWidth: "never" })).toContain(
      "  x = f(1, 2)\n  f(x, 3)",
    );
  });

  test("preserves strings, escapes, char literals and comments", async () => {
    const source = String.raw`import Base
# header,= and http://example.org
def main() -> String:
    "a,b=c # quoted \"" ++ "longer-than-width"  # trailing,=comment
`;
    const output = await fixed(source, { tabWidth: 2, wrapAtWidth: 15 });
    expect(output).toContain('"a,b=c # quoted \\\""');
    expect(output).toContain("# header,= and http://example.org");
    expect(output).toContain("# trailing,=comment");
    expect(await fixed("import Base\ndef main() -> Char:\n  '='\n")).toContain("  '='");
  });

  test("keeps inline argument comments attached when wrapping", async () => {
    const source =
      "import Base\ndef f(x: U32, y: U32) -> U32:\n  x\ndef main() -> U32:\n  f(123, # first\n    456 # second\n  )\n";
    const output = await fixed(source, { tabWidth: 2, wrapAtWidth: 20 });
    expect(output).toContain("123,  # first\n");
    expect(output).toContain("456  # second\n");
  });

  test("comment markers get a space, while literals and special markers stay intact", async () => {
    const source = String.raw`import Base #import-comment
#header
##Heading
#!directive
#|expectation
#
# already spaced
def apostrophe() -> Char:
  '\''
def main() -> String:
  "${String.fromCodePoint(0x1f600)}#inside \"#escaped\"" #tail
`;
    const output = await fixed(source.replaceAll("\n", "\r\n"));
    expect(output).toContain("import Base  # import-comment");
    expect(output).toContain(
      "# header\n##Heading\n#!directive\n#|expectation\n#\n# already spaced",
    );
    const literal = source
      .split("\n")
      .find((line) => line.includes("#inside"))!
      .split(" #tail")[0]
      .trim();
    expect(output).toContain(literal);
    expect(output).toContain(String.fromCodePoint(0x1f600));
    expect(output).toContain("  # tail");
    const multiline =
      'import Base\ndef main() -> String:\n  "first line\n#inside literal\nlast line" #outside\n';
    expect(await fixed(multiline)).toContain('#inside literal\nlast line"  # outside');
  });

  test("handles nested type arguments, successors, quantities and templates", async () => {
    await fixed(
      "import Base\ndef identity(~T: Type, x: T) -> T:\n  x\ndef main() -> List<List<U32>>:\n  identity(~List<List<U32>>, [[1, 2], [3]])\n",
      { tabWidth: 2, wrapAtWidth: 25 },
    );
    await fixed(
      "import Base\ndef successor(+x: Nat) -> Nat:\n  1n+x\ndef main() -> Nat:\n  successor(2n)\n",
    );
    await fixed(
      "import Base\ntype Box<-Value: Data> is Data:\n  Box{value: Value}\ndef main() -> Box<U32>:\n  Box{1}\n",
      { tabWidth: 4, wrapAtWidth: 18 },
    );
    await fixed(
      "import Base\ndef main() -> List<U32>:\n  List.map(~U32, ~U32, ~(x => (x + 123456789 : U32)), [1, 2, 3, 4])\n",
      { tabWidth: 4, wrapAtWidth: 30 },
    );
    await fixed(
      "import Base\ndef identity(-T: Type, x: T) -> T:\n  x\ndef main() -> U32:\n  identity(U32 {1 : U32})\n",
    );
  });

  test("preserves nested match, do and lambda body scopes", async () => {
    await fixed(
      "import Base\ndef f(x: Nat) -> Nat:\n    match x:\n        case 0n:\n            0n\n        case 1n+p:\n            p\ndef main() -> Nat:\n    f(1n)\n",
      { tabWidth: 4, wrapAtWidth: 30 },
    );
    await fixed(
      'import Base\ndef main() -> IO(Unit):\n  do IO<Unit>:\n    IO.print("a long message")\n',
      { tabWidth: 4, wrapAtWidth: 18 },
    );
    await fixed(
      "import Base\ndef main() -> U32:\n  f: U32 -> U32 = x => (\n    y = x\n    y\n  )\n  f(1)\n",
      { tabWidth: 4, wrapAtWidth: 20 },
    );
  });

  test("law/proof and unsafe syntax are preserved", async () => {
    await fixed(
      "import Base\nlaw same:\n  for x: U32\n  {x == x : U32}\ndef same(x):\n  {==}\n@unsafe\ndef identity(x: U32) -> U32:\n  x\ndef main() -> U32:\n  identity(1)\n",
    );
  });

  test("imports and imported law fills survive the parser guard", async () => {
    fixture("import Base\nlaw same:\n  for x: U32\n  {x == x : U32}\n", "LAWS.bend");
    await fixed("import Base\nimport ./LAWS.bend as Laws\ndef Laws.same(x):\n  {==}\n", opts);
  });

  test("the guard rejects a changed value or scope", async () => {
    const guard: LintRule = {
      id: "test/guard",
      run: (cx) => {
        expect(cx.sameDeclarations("import Base\ndef main() -> U32:\n  2\n")).toBe(false);
        expect(cx.sameDeclarations(format(cx.root.text, opts))).toBe(true);
        return [];
      },
    };
    expect(clean(await lint(fixture("import Base\ndef main() -> U32:\n  1\n"), [guard]))).toBe(
      true,
    );
  });

  test("operator chains wrap at boundaries and stay stable", async () => {
    const source = 'import Base\ndef main() -> String:\n  "aaaaaaaa" ++ "bbbbbbbb" ++ "cccccccc"\n';
    const output = await fixed(source, { tabWidth: 2, wrapAtWidth: 20 });
    expect(output).toContain('  "aaaaaaaa"\n    ++ "bbbbbbbb"\n    ++ "cccccccc"');
    expect(await fixed(source, { tabWidth: 2, wrapAtWidth: "never" })).toContain(
      '  "aaaaaaaa" ++ "bbbbbbbb" ++ "cccccccc"',
    );
  });

  test("empty files, comments and indivisible tokens have a canonical ending", () => {
    expect(format("", opts)).toBe("\n");
    expect(format("\n\n# comment\n\n", opts)).toBe("# comment\n");
    const source = 'import Base\ndef main() -> String:\n  "an indivisible literal with spaces"\n';
    const output = format(source, { tabWidth: 1, wrapAtWidth: 1 });
    expect(output).toContain(' "an indivisible literal with spaces"');
    expect(format(output, { tabWidth: 1, wrapAtWidth: 1 })).toBe(output);
  });

  test("CLI --fix writes the same whole-file formatting in one sweep", () => {
    const file = fixture("import Base\ndef main()->U32: 1  \n");
    const config = fixture(
      JSON.stringify({ rules: { "format/layout": { tabWidth: 4, wrapAtWidth: "never" } } }),
      "config.json",
    );
    const cli = fileURLToPath(new URL("../src/lint.ts", import.meta.url));
    const rule = fileURLToPath(new URL("./format.ts", import.meta.url));
    const args = [cli, file, "--rules", rule, "--config", config, "--fix", "--json"];
    const result = spawnSync(process.execPath, args, { encoding: "utf8" });
    expect(result.status).toBe(0);
    expect(result.stderr).toContain("bend-lint: fixed ");
    const text = fs.readFileSync(file, "utf8");
    expect(text).toBe("import Base\n\ndef main() -> U32:\n    1\n");
    const again = spawnSync(process.execPath, args, { encoding: "utf8" });
    expect([again.status, again.stderr, JSON.parse(again.stdout)]).toEqual([
      0,
      "",
      { ok: true, findings: [] },
    ]);
    expect(fs.readFileSync(file, "utf8")).toBe(text);
  });
});
