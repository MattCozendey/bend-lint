import { afterAll, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { applyFixes, createLinter } from "./lint.ts";
import type { Diag, LintOptions, LintResult, LintRule, Severity } from "./lint.ts";
import { unwrap } from "./result.ts";
import { rules as formatRules } from "../rules/format.ts";

// Rules
// =====

// demo/a finds each Z{} and demo/b each W{} (a warning and a hint); demo/s
// finds a V{} and has no span; demo/seen reports what it saw in `prior`. They
// look only below the header, where the test's own text starts.
const START = "# test";
const below = (text: string): number => {
  const m = /# test\r?\n/.exec(text);
  return m === null ? 0 : m.index + m[0].length;
};

const finds = (id: string, marker: string, severity: Severity): LintRule => ({
  id,
  run: (cx) =>
    [...cx.root.text.matchAll(new RegExp(marker.replace(/[{}]/g, "\\$&"), "g"))]
      .filter((m) => m.index >= below(cx.root.text))
      .map((m) =>
        cx.diag({
          message: "found " + marker,
          severity,
          span: { file: cx.root, beg: m.index, end: m.index + marker.length },
        }),
      ),
});
const a = finds("demo/a", "Z{}", "warning");
const b = finds("demo/b", "W{}", "hint");
const spanless: LintRule = {
  id: "demo/s",
  run: (cx) =>
    cx.root.text.slice(below(cx.root.text)).includes("V{}")
      ? [cx.diag({ message: "found V{}" })]
      : [],
};
const seen: LintRule = {
  id: "demo/seen",
  run: (cx) => [cx.diag({ message: cx.prior.map((d) => d.code).join(" ") })],
};

// Helpers
// =======

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "bend-suppress-"));
afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));
const linter = unwrap(await createLinter());
let count = 0;

const text = (...lines: string[]): string => lines.join("\n") + "\n";

// What every file starts with. Its lines after the import do not count in the
// line numbers the tests name: `import Base` is line 1, and the test's own
// text starts on line 2.
const HEADER = text(
  "import Base",
  "",
  "type N is Data:",
  "  Z{}",
  "  W{}",
  "  V{}",
  "",
  "type P is Data:",
  "  P{x: N, y: N}",
  "",
  START,
);
const HEADER_LINES = HEADER.split("\n").length - 2;

const lint = async (
  source: string,
  rules: LintRule[] = [a, b],
  options?: LintOptions,
  eol = "\n",
): Promise<LintResult> => {
  const file = path.join(dir, "main" + count++ + ".bend");
  fs.writeFileSync(file, (HEADER + source).replaceAll("\n", eol));
  return unwrap(await linter.lint(file, rules, options));
};

// The line of a finding, as the tests count it; one without a span is on line 1.
const row = (d: Diag): number =>
  d.span === undefined
    ? 1
    : d.span.file.text.slice(0, d.span.beg).split("\n").length - HEADER_LINES;

const rows = (diags: Diag[], code: string): number[] =>
  diags.filter((d) => d.code === code).map(row);

const codes = (res: LintResult): string[] => res.diags.map((d) => d.code);

const messages = (res: LintResult, code: string): string[] =>
  res.diags.filter((d) => d.code === code).map((d) => d.message);

// Scopes
// ======

test("next covers the next line of code, past blank and comment lines, and stacks", async () => {
  const res = await lint(
    text(
      "def a() -> P:",
      "  # bend-lint: disable-next demo/a -- why",
      "",
      "  # an ordinary comment",
      "  # bend-lint: disable-next demo/b -- why",
      "  P{Z{}, W{}}",
      "def b() -> N:",
      "  Z{}",
    ),
  );
  expect(rows(res.suppressed, "demo/a")).toEqual([7]);
  expect(rows(res.suppressed, "demo/b")).toEqual([7]);
  expect(rows(res.diags, "demo/a")).toEqual([9]);
  expect(codes(res)).toEqual(["demo/a"]);
});

test("line covers its own line only", async () => {
  const res = await lint(
    text(
      "def a() -> N:",
      "  Z{}  # bend-lint: disable-line demo/a -- why",
      "def b() -> N:",
      "  Z{}",
    ),
  );
  expect(rows(res.suppressed, "demo/a")).toEqual([3]);
  expect(rows(res.diags, "demo/a")).toEqual([5]);
});

test("file covers every line, and a finding without a span", async () => {
  const res = await lint(
    text(
      "def a() -> N:",
      "  Z{}",
      "# bend-lint: disable-file demo/a -- generated",
      "# bend-lint: disable-file demo/s -- generated",
      "def b() -> P:",
      "  P{Z{}, V{}}",
    ),
    [a, b, spanless],
  );
  expect(res.suppressed.map((d) => d.code).sort()).toEqual(["demo/a", "demo/a", "demo/s"]);
  expect(codes(res)).toEqual([]);
});

test("a region covers its lines, and regions of one rule nest", async () => {
  const res = await lint(
    text(
      "# bend-lint: disable-begin demo/a -- outer",
      "def a() -> N:",
      "  # bend-lint: disable-begin demo/a -- inner",
      "  Z{}",
      "  # bend-lint: disable-end demo/a",
      "def b() -> N:",
      "  Z{}",
      "# bend-lint: disable-end demo/a",
      "def c() -> N:",
      "  Z{}",
    ),
  );
  expect(rows(res.suppressed, "demo/a")).toEqual([5, 8]);
  expect(rows(res.diags, "demo/a")).toEqual([11]);
  expect(codes(res)).toEqual(["demo/a"]);
});

test("a directive covers only its rule", async () => {
  const res = await lint(
    text("# bend-lint: disable-file demo/b -- why", "def a() -> P:", "  P{Z{}, W{}}"),
  );
  expect(rows(res.diags, "demo/a")).toEqual([4]);
  expect(rows(res.suppressed, "demo/b")).toEqual([4]);
});

test("a # or a directive inside a literal is not a comment", async () => {
  const res = await lint(
    text(
      "def s() -> String:",
      '  "# bend-lint: disable-file demo/a -- not a directive',
      'Z{} is here"',
      "def a() -> N:",
      "  Z{}",
    ),
  );
  expect(rows(res.diags, "demo/a")).toEqual([4, 6]);
  expect(codes(res)).toEqual(["demo/a", "demo/a"]);
});

test("a file with CRLF line ends works the same", async () => {
  const res = await lint(
    text("def a() -> N:", "  # bend-lint: disable-next demo/a -- why", "  Z{}"),
    [a, b],
    undefined,
    "\r\n",
  );
  expect(rows(res.suppressed, "demo/a")).toEqual([4]);
  expect(codes(res)).toEqual([]);
});

// Expectations
// ============

test("an expectation that is met covers the finding and reports nothing", async () => {
  const res = await lint(
    text(
      "def a() -> N:",
      "  # bend-lint: expect-next demo/a@warning -- the sample must warn",
      "  Z{}",
      "def b() -> N:",
      "  # bend-lint: expect-next demo/b@hint -- a hint can be expected",
      "  W{}",
    ),
  );
  expect(rows(res.suppressed, "demo/a")).toEqual([4]);
  expect(rows(res.suppressed, "demo/b")).toEqual([7]);
  expect(codes(res)).toEqual([]);
});

test("an expectation that is not met is an error", async () => {
  const res = await lint(
    text(
      "def a() -> N:",
      "  # bend-lint: expect-next demo/a@warning -- the sample must warn",
      "  V{}",
    ),
  );
  expect(codes(res)).toEqual(["bend-lint/unmet-expectation"]);
  expect(res.diags.at(-1)?.severity).toBe("error");
  expect(rows(res.diags, "bend-lint/unmet-expectation")).toEqual([3]);
});

test("an expectation of another severity covers nothing and is not met", async () => {
  const res = await lint(
    text("def a() -> N:", "  # bend-lint: expect-next demo/a@error -- wrong severity", "  Z{}"),
  );
  expect(codes(res).sort()).toEqual(["bend-lint/unmet-expectation", "demo/a"]);
});

test("the severity of an expectation is the one the config gives the rule", async () => {
  const source = text(
    "def a() -> N:",
    "  # bend-lint: expect-next demo/a@error -- escalated",
    "  Z{}",
  );
  const config = { rules: { "demo/a": { severity: "error" as const } } };
  const res = await lint(source, [a, b], { config });
  expect(codes(res)).toEqual([]);
  expect(rows(res.suppressed, "demo/a")).toEqual([4]);
});

test("a region that expects needs one finding inside it", async () => {
  const met = await lint(
    text(
      "# bend-lint: expect-begin demo/a@warning -- why",
      "def a() -> N:",
      "  Z{}",
      "# bend-lint: expect-end demo/a@warning",
    ),
  );
  expect(codes(met)).toEqual([]);
  const unmet = await lint(
    text(
      "# bend-lint: expect-begin demo/a@warning -- why",
      "def a() -> N:",
      "  V{}",
      "# bend-lint: expect-end demo/a@warning",
    ),
  );
  expect(codes(unmet)).toEqual(["bend-lint/unmet-expectation"]);
});

// Unused disables
// ===============

test("a disable that covers nothing is a warning", async () => {
  const res = await lint(
    text(
      "def a() -> N:",
      "  # bend-lint: disable-next demo/a -- stale",
      "  V{}",
      "  # bend-lint: disable-next demo/a -- nothing follows",
    ),
  );
  expect(codes(res)).toEqual(["bend-lint/unused-disable", "bend-lint/unused-disable"]);
  expect(res.diags.map((d) => d.severity)).toEqual(["warning", "warning"]);
});

test("a directive for a rule that did not run is not judged", async () => {
  const source = text(
    "def a() -> N:",
    "  # bend-lint: disable-next demo/a -- stale",
    "  V{}",
    "def b() -> N:",
    "  # bend-lint: expect-next demo/a@warning -- stale",
    "  V{}",
  );
  expect(codes(await lint(source, [a, b], { config: { rules: { "demo/a": "off" } } }))).toEqual([]);
  const crash: LintRule = {
    id: "demo/a",
    run: () => {
      throw new Error("boom");
    },
  };
  expect(codes(await lint(source, [crash, b]))).toEqual(["bend-lint/rule-crash"]);
});

// Problems
// ========

test("a directive that is wrong is an error and covers nothing", async () => {
  const cases: Array<[string, string]> = [
    ["# bend-lint: disable-next demo/a", "reason"],
    ["# bend-lint: disable-next demo/a --", "reason"],
    ["# bend-lint: disable-next demo/a@warning -- why", "no severity"],
    ["# bend-lint: expect-next demo/a -- why", "pins a severity"],
    ["# bend-lint: expect-next demo/a@loud -- why", "not a severity"],
    ["# bend-lint: disable-next demo/zzz -- why", "no rule demo/zzz"],
    ["# bend-lint: disable-next bend-lint/rule-crash -- why", "cannot be suppressed"],
    ["# bend-lint: disable-next bend/check -- why", "cannot be suppressed"],
    ["# bend-lint: disable-end demo/a -- why", "no reason"],
    ["# bend-lint: disable-sometime demo/a -- why", "Write"],
    ["# bend-lint: disable-next -- why", "Write"],
    ["# bend-lint: hide-next demo/a -- why", "Write"],
    ["# bend-lint: disable-line demo/a -- why", "follow code"],
  ];
  for (const [directive, expected] of cases) {
    const res = await lint(text("def a() -> N:", "  " + directive, "  Z{}"));
    expect(codes(res), directive).toEqual(["demo/a", "bend-lint/directive"]);
    expect(messages(res, "bend-lint/directive")[0], directive).toContain(expected);
    expect(rows(res.diags, "bend-lint/directive"), directive).toEqual([3]);
  }
});

test("a region left open, or an end with no begin, is an error", async () => {
  const open = await lint(
    text("# bend-lint: disable-begin demo/a -- why", "def a() -> N:", "  Z{}"),
  );
  expect(messages(open, "bend-lint/directive")).toEqual(["This begin of demo/a is never closed."]);
  expect(rows(open.suppressed, "demo/a")).toEqual([4]);
  const orphan = await lint(text("def a() -> N:", "  Z{}", "# bend-lint: disable-end demo/a"));
  expect(codes(orphan)).toEqual(["demo/a", "bend-lint/directive"]);
  const mismatch = await lint(
    text(
      "# bend-lint: expect-begin demo/a@warning -- why",
      "def a() -> N:",
      "  Z{}",
      "# bend-lint: expect-end demo/a@hint",
    ),
  );
  expect(messages(mismatch, "bend-lint/directive").length).toBe(2);
});

test("findings about directives cannot be suppressed", async () => {
  const res = await lint(
    text(
      "# bend-lint: disable-file demo/a -- why",
      "# bend-lint: disable-file demo/zzz -- hides nothing",
      "def a() -> N:",
      "  Z{}",
    ),
  );
  expect(codes(res)).toEqual(["bend-lint/directive"]);
});

// Order
// =====

test("stacked directives must be in order, and a fix puts them in order", async () => {
  const source = text(
    "def a() -> P:",
    "  # bend-lint: disable-next demo/b -- second",
    "  # bend-lint: disable-next demo/a -- first",
    "  P{Z{}, W{}}",
  );
  const res = await lint(source);
  expect(codes(res)).toEqual(["bend-lint/directive"]);
  expect(res.diags[0].fixes.map((f) => f.applicability)).toEqual(["safe"]);
  const fixed = applyFixes(res.root!, res.diags).text;
  expect(fixed).toBe(
    HEADER +
      text(
        "def a() -> P:",
        "  # bend-lint: disable-next demo/a -- first",
        "  # bend-lint: disable-next demo/b -- second",
        "  P{Z{}, W{}}",
      ),
  );
  expect(codes(await lint(fixed.slice(HEADER.length)))).toEqual([]);
});

test("one rule stacks by severity, then by keyword", async () => {
  const sorted = text(
    "def a() -> N:",
    "  # bend-lint: disable-next demo/a -- first",
    "  # bend-lint: expect-next demo/a@error -- second",
    "  # bend-lint: expect-next demo/a@warning -- third",
    "  Z{}",
  );
  const res = await lint(sorted);
  expect(messages(res, "bend-lint/directive")).toEqual([]);
  const swapped = text(
    "def a() -> N:",
    "  # bend-lint: expect-next demo/a@warning -- third",
    "  # bend-lint: expect-next demo/a@error -- second",
    "  # bend-lint: disable-next demo/a -- first",
    "  Z{}",
  );
  const bad = await lint(swapped);
  expect(applyFixes(bad.root!, bad.diags).text).toBe(HEADER + sorted);
});

test("a blank line or another comment ends a stack", async () => {
  const res = await lint(
    text(
      "def a() -> P:",
      "  # bend-lint: disable-next demo/b -- second",
      "  # an ordinary comment",
      "  # bend-lint: disable-next demo/a -- first",
      "  P{Z{}, W{}}",
    ),
  );
  expect(messages(res, "bend-lint/directive")).toEqual([]);
});

// Around the findings
// ===================

test("a later rule still sees the findings a directive covered", async () => {
  const res = await lint(
    text("def a() -> N:", "  # bend-lint: disable-next demo/a -- why", "  Z{}"),
    [a, seen],
  );
  expect(messages(res, "demo/seen")).toEqual(["demo/a"]);
  expect(rows(res.suppressed, "demo/a")).toEqual([4]);
});

test("a covered finding gets no fix", async () => {
  const fixes: LintRule = {
    id: "demo/fix",
    run: (cx) => [
      cx.diag({
        message: "fix",
        span: { file: cx.root, beg: 0, end: 0 },
        fixes: [
          {
            title: "x",
            applicability: "safe",
            edits: [{ span: { file: cx.root, beg: 0, end: 0 }, text: "# added\n" }],
          },
        ],
      }),
    ],
  };
  const source = text("# bend-lint: disable-file demo/fix -- why");
  const res = await lint(source, [fixes]);
  expect(applyFixes(res.root!, res.diags).text).toBe(HEADER + source);
});

test("directives in a formatted file stay put under format/layout", async () => {
  const source = text(
    "def a() -> P:",
    "  # bend-lint: disable-next demo/a -- why",
    "  P{Z{}, W{}}  # bend-lint: disable-line demo/b -- why",
  );
  const res = await lint(source, [...formatRules, a, b]);
  expect(codes(res)).toEqual([]);
  expect(res.suppressed.map((d) => d.code).sort()).toEqual(["demo/a", "demo/b"]);
  expect(res.diags.filter((d) => d.code === "format/layout")).toEqual([]);
});
