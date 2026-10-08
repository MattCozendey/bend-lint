// Suppressions and expectations: comments in the linted file that silence
// findings (disable) or demand them (expect). One directive names one rule,
// as SYNTAX says. An expect pins a severity and a disable takes none. file covers the whole
// file; begin and end bound a region; line covers its own line; next covers
// the next line that holds code. A finding is covered when its span starts on
// a covered line (a finding without a span counts as line 1). Directives that
// stack on consecutive comment-only lines must be in order, by rule, severity
// and keyword. A comment covers the findings of its own file: the linted
// file, or an import that a rule reports in. Every file read is checked for
// form and order, and an unused or unmet directive is judged where the rule
// could look: in the linted file, and for a rule of program scope in imports.
// The checker's and bend-lint's own findings cannot be suppressed.

import { line, starts } from "./seam.ts";
import type { Diag, Fix, Severity, Source } from "./lint.ts";

// Types
// =====

type Comment = { beg: number; end: number; line: number; trailing: boolean };

type Parsed = {
  action: (typeof ACTIONS)[number];
  scope: (typeof SCOPES)[number];
  rule: string;
  severity?: Severity;
  reason?: string;
  comment: Comment;
};

// What is wrong with a directive, and where.
type Problem = { at: Comment; why: string };

// A comment that looks like a directive, before its severity is checked.
type Draft = Omit<Parsed, "severity"> & { pinned?: string };

// A directive and the lines it covers, both ends included.
type Covering = { directive: Parsed; from: number; to: number };

// The directives of a rule: those of one line by line, the wider ones in a list.
type Bucket = { lines: Map<number, Covering[]>; ranges: Covering[] };

// What suppress needs to know of the run: every rule it has (a directive for
// another one is an error), the ones that ran (only their directives can be
// unused), those of them that looked at the imports too (only they can be
// judged there), and what a severity is.
type Context = {
  known: ReadonlySet<string>;
  ran: ReadonlySet<string>;
  program: ReadonlySet<string>;
  isSeverity: (s: string) => s is Severity;
};

// Constants
// =========

const ACTIONS = ["disable", "expect"] as const;
const SCOPES = ["file", "begin", "end", "next", "line"] as const;
const SYNTAX =
  "Write `# bend-lint: <disable|expect>-<file|begin|end|next|line> <rule>[@severity] -- <reason>`.";
const PREFIX = /^\s*bend-lint:/;
const DIRECTIVE =
  /^\s*bend-lint:\s*(\w+)-(\w+)\s+([^/\s@]+\/[^/\s@]+)(?:@(\S+))?(?:\s+--\s+(\S.*?))?\s*$/;
// A comment, a string or char literal (maybe over several lines, maybe
// unterminated), a newline, or any other character that is not a space.
const TOKEN = /#[^\r\n]*|"(?:\\[^]|[^"\\])*(?:"|$)|'(?:\\[^]|[^'\\])*(?:'|$)|\n|[^\s#"']+/g;
const RESERVED = new Set(["bend", "bend-lint"]);
const NONE = { from: 1, to: 0 };

// Functions
// =========

// The comments of a text and which of its lines hold code; a `#` inside a
// literal is not a comment.
const scan = (text: string): { comments: Comment[]; code: boolean[] } => {
  const comments: Comment[] = [];
  const code = [false];
  for (const m of text.matchAll(TOKEN)) {
    const token = m[0];
    const row = code.length - 1;
    if (token === "\n") {
      code.push(false);
    } else if (token[0] === "#") {
      comments.push({ beg: m.index, end: m.index + token.length, line: row, trailing: code[row] });
    } else {
      code[row] = true;
      const quoted = token[0] === '"' || token[0] === "'";
      for (let i = quoted ? token.split("\n").length - 1 : 0; i > 0; i--) {
        code.push(true);
      }
    }
  }
  return { comments, code };
};

const cmp = (a: string, b: string): number => Number(a > b) - Number(a < b);

// The order stacked directives must keep.
const order = (a: Parsed, b: Parsed): number =>
  cmp(a.rule, b.rule) ||
  cmp(a.severity ?? "", b.severity ?? "") ||
  cmp(a.action + "-" + a.scope, b.action + "-" + b.scope);

// What makes a directive wrong, each told as the message, or false.
const WRONG: Array<(d: Draft, ctx: Context) => string | false> = [
  (d, ctx) =>
    d.pinned !== undefined && !ctx.isSeverity(d.pinned) && d.pinned + " is not a severity.",
  (d) => d.action === "disable" && d.pinned !== undefined && "A disable takes no severity.",
  (d) =>
    d.action === "expect" &&
    d.pinned === undefined &&
    "An expect pins a severity: " + d.rule + "@...",
  (d) => d.scope === "end" && d.reason !== undefined && "An end takes no reason; the begin has it.",
  (d) => d.scope !== "end" && d.reason === undefined && "A reason is required, after `--`.",
  (d) =>
    d.scope === "line" && !d.comment.trailing && "A line directive must follow code on its line.",
  (d) => RESERVED.has(d.rule.split("/")[0]) && d.rule + " findings cannot be suppressed.",
  (d, ctx) => !ctx.known.has(d.rule) && "There is no rule " + d.rule + ".",
];

// The directive a comment holds, or what is wrong with it.
const parse = (body: string, comment: Comment, ctx: Context): Parsed | string => {
  const m = DIRECTIVE.exec(body);
  if (m === null) {
    return SYNTAX;
  }
  const [, a, sc, rule, pinned, reason] = m;
  const action = ACTIONS.find((x) => x === a);
  const scope = SCOPES.find((x) => x === sc);
  if (action === undefined || scope === undefined) {
    return SYNTAX;
  }
  const draft = { action, scope, rule, pinned, reason, comment };
  for (const wrong of WRONG) {
    const why = wrong(draft, ctx);
    if (why !== false) {
      return why;
    }
  }
  const severity = pinned !== undefined && ctx.isSeverity(pinned) ? pinned : undefined;
  return { action, scope, rule, severity, reason, comment };
};

// The first line after each line that holds code, or -1.
const following = (code: boolean[]): number[] => {
  const out: number[] = Array<number>(code.length).fill(-1);
  for (let i = code.length - 2; i >= 0; i--) {
    out[i] = code[i + 1] ? i + 1 : out[i + 1];
  }
  return out;
};

// Each directive with its lines. An end closes the latest open begin of its
// action and rule (and, for an expect, severity); what does not pair is a
// problem, and so is a begin left open (it then covers to the last line).
const cover = (found: Parsed[], code: boolean[]): { covering: Covering[]; problems: Problem[] } => {
  const after = following(code);
  const open = new Map<string, number[]>();
  const closed = new Map<number, number>();
  const problems: Problem[] = [];
  found.forEach((d, i) => {
    const key = d.action + " " + d.rule;
    const stack = open.get(key) ?? [];
    open.set(key, stack);
    if (d.scope === "begin") {
      stack.push(i);
    } else if (d.scope === "end") {
      const begin = stack[stack.length - 1];
      if (begin === undefined || found[begin].severity !== d.severity) {
        problems.push({ at: d.comment, why: "This end closes no begin of " + d.rule + "." });
      } else {
        stack.pop();
        closed.set(begin, d.comment.line);
      }
    }
  });
  for (const stack of open.values()) {
    for (const i of stack) {
      problems.push({
        at: found[i].comment,
        why: "This begin of " + found[i].rule + " is never closed.",
      });
    }
  }
  const last = code.length - 1;
  const covering = found.flatMap((directive, i): Covering[] => {
    const l = directive.comment.line;
    switch (directive.scope) {
      case "file":
        return [{ directive, from: 0, to: last }];
      case "line":
        return [{ directive, from: l, to: l }];
      case "next":
        return [{ directive, ...(after[l] < 0 ? NONE : { from: after[l], to: after[l] }) }];
      case "begin":
        return [{ directive, from: l, to: closed.get(i) ?? last }];
      default:
        return [];
    }
  });
  return { covering, problems };
};

// The runs of directives on consecutive comment-only lines that are out of
// order; each gets one finding with a fix that puts them in order.
const unsorted = (root: Source, found: Parsed[]): Diag[] => {
  const runs: Parsed[][] = [];
  for (const d of found.filter((f) => !f.comment.trailing)) {
    const run = runs[runs.length - 1];
    if (run?.at(-1)?.comment.line === d.comment.line - 1) {
      run.push(d);
    } else {
      runs.push([d]);
    }
  }
  return runs.flatMap((run) => {
    const sorted = [...run].sort(order);
    if (sorted.every((d, i) => d === run[i])) {
      return [];
    }
    const fix: Fix = {
      title: "Sort the directives",
      applicability: "safe",
      edits: run.flatMap((d, i) =>
        sorted[i] === d
          ? []
          : [
              {
                span: { file: root, beg: d.comment.beg, end: d.comment.end },
                text: root.text.slice(sorted[i].comment.beg, sorted[i].comment.end),
              },
            ],
      ),
    };
    return [
      {
        code: "bend-lint/directive",
        severity: "error",
        message: "Directives that stack must be in order: by rule, then severity, then keyword.",
        span: { file: root, beg: run[0].comment.beg, end: run[run.length - 1].comment.end },
        fixes: [fix],
      },
    ];
  });
};

// The directives of each rule, so a finding finds its own without a scan of
// all the one-line ones.
const index = (covering: Covering[]): Map<string, Bucket> => {
  const out = new Map<string, Bucket>();
  for (const c of covering) {
    const mine: Bucket = out.get(c.directive.rule) ?? { lines: new Map(), ranges: [] };
    out.set(c.directive.rule, mine);
    if (c.from === c.to) {
      mine.lines.set(c.from, [...(mine.lines.get(c.from) ?? []), c]);
    } else if (c.from < c.to) {
      mine.ranges.push(c);
    }
  }
  return out;
};

// The directives that cover a finding of that rule, severity and line.
const covers = (
  by: ReturnType<typeof index>,
  rule: string,
  severity: Severity,
  row: number,
): Parsed[] => {
  const mine = by.get(rule);
  return [
    ...(mine?.lines.get(row) ?? []),
    ...(mine?.ranges ?? []).filter((c) => c.from <= row && row <= c.to),
  ]
    .map((c) => c.directive)
    .filter((d) => d.action === "disable" || d.severity === severity);
};

// What a file's comments say: their directives, the lines they cover, what
// is wrong with them, and the covering ones by rule.
const read = (file: Source, ctx: Context) => {
  const { comments, code } = scan(file.text);
  const parsed = comments.flatMap((c) => {
    const body = file.text.slice(c.beg + 1, c.end);
    return PREFIX.test(body) ? [{ c, result: parse(body, c, ctx) }] : [];
  });
  const found = parsed.flatMap(({ result }) => (typeof result === "string" ? [] : [result]));
  const { covering, problems } = cover(found, code);
  const wrong = [
    ...parsed.flatMap(({ c, result }) =>
      typeof result === "string" ? [{ at: c, why: result }] : [],
    ),
    ...problems,
  ].map(({ at, why }) => ({
    code: "bend-lint/directive",
    severity: "error" as const,
    message: why,
    span: { file, beg: at.beg, end: at.end },
    fixes: [],
  }));
  return { found, covering, wrong, by: index(covering), ss: starts(file, file.text) };
};

// Splits the findings into those that stay and those a directive covers, and
// adds the findings about the directives: a wrong one, a disable that covered
// nothing, an expect that was not met. Those two are judged for rules that
// ran, and in an import for those of program scope.
export const suppress = (
  root: Source,
  sources: Source[],
  diags: Diag[],
  ctx: Context,
): { diags: Diag[]; suppressed: Diag[] } => {
  const files = new Map(
    sources
      .filter((f) => !f.base && f.text.includes("bend-lint:"))
      .map((f) => [f, read(f, ctx)] as const),
  );
  if (files.size === 0) {
    return { diags, suppressed: [] };
  }
  const used = new Set<Parsed>();
  const kept: Diag[] = [];
  const suppressed: Diag[] = [];
  for (const d of diags) {
    const mine = files.get(d.span?.file ?? root);
    const row = d.span === undefined || mine === undefined ? 0 : line(mine.ss, d.span.beg);
    const hits = mine === undefined ? [] : covers(mine.by, d.code, d.severity, row);
    hits.forEach((h) => used.add(h));
    (hits.length > 0 ? suppressed : kept).push(d);
  }
  const unmet = [...files].flatMap(([file, r]) =>
    r.covering.flatMap(({ directive: d }) => {
      const judged = ctx.ran.has(d.rule) && (file.root || ctx.program.has(d.rule));
      if (used.has(d) || !judged) {
        return [];
      }
      const expect = d.action === "expect";
      return [
        {
          code: expect ? "bend-lint/unmet-expectation" : "bend-lint/unused-disable",
          severity: expect ? ("error" as const) : ("warning" as const),
          message: expect
            ? "Expected a " + d.rule + "@" + d.severity + " finding on the lines this covers; none."
            : "This disables " + d.rule + ", but nothing on the lines it covers needs it.",
          span: { file, beg: d.comment.beg, end: d.comment.end },
          fixes: [],
        },
      ];
    }),
  );
  const about = [...files].flatMap(([file, r]) => [...r.wrong, ...unsorted(file, r.found)]);
  return { diags: [...kept, ...about, ...unmet], suppressed };
};
