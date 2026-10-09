// One formatter owns indentation, spacing, declaration gaps and wrapping.
// Run: bun src/lint.ts file.bend --rules rules/format.ts --fix
// Config: { "rules": { "format/layout": { "tabWidth": 2, "wrapAtWidth": 100 } } }
// "never" disables optional wrapping. endOfLine "preserve" keeps the first
// ending, or LF if there is none.

import type { LintRule } from "../src/lint.ts";

// Types
// =====

export type FormatOptions = {
  tabWidth: number;
  wrapAtWidth: number | "never";
  endOfLine?: "lf" | "crlf" | "preserve";
};
type Token = {
  text: string;
  beg: number;
  end: number;
  col: number;
  kind: "code" | "literal" | "comment" | "newline";
};
type Node = Token | { open: Token; close: Token; children: Node[] };
type Doc =
  | string
  | { kind: "line"; flat: string; hard?: boolean; offset?: number }
  | { kind: "group" | "nest"; doc: Doc; amount?: number }
  | Doc[];
type Frame = { doc: Doc; indent: number; flat: boolean };

// Constants
// =========

const DELIMITERS = new Map([
  ["(", ")"],
  ["[", "]"],
  ["{", "}"],
  ["<", ">"],
]);
// Whitespace, as Bend's parser reads it.
const BLANK = " \t\n\r";
const UNSPACED_COMMENT = new RegExp(`^#[^${BLANK}#!|]`, "u");
const IMPORT = new RegExp(`^import[${BLANK}]+`);
const ALIAS = new RegExp(`[${BLANK}]+as[${BLANK}]+`);
// A word, a number, or a symbol of more than one character, at lastIndex.
const ATOM =
  /[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*|\d+(?:n\+?|\.\d+(?:[eE][+-]?\d+)?)?|<&>|\.&\.|\.\|\.|\.\^\.|->|=>|<-|==|!=|<=|>=|<<|&&|\|\||\+\+|<>|&[012]/y;
const OPERATORS = new Set([
  "+",
  "-",
  "*",
  "/",
  "%",
  "^",
  "++",
  "&&",
  "||",
  "<&>",
  ".&.",
  ".|.",
  ".^.",
  "<<",
  ">>",
  "<>",
  "<",
  ">",
  "<=",
  ">=",
  "==",
  "!=",
  "&",
  "|",
]);

// Functions
// =========

// Preserve literals and comment text verbatim. In particular, a quote or #
// inside a string is not syntax; successor notation and quantities are atoms.
const tokens = (source: string): Token[] => {
  const out: Token[] = [];
  let at = 0,
    start = 0;
  while (at < source.length) {
    const beg = at,
      c = String.fromCodePoint(source.codePointAt(at)!);
    if (c !== "\n" && BLANK.includes(c)) {
      at++;
      continue;
    }
    let kind: Token["kind"] = "code";
    if (c === "\n") {
      at++;
      kind = "newline";
    } else if (c === "#") {
      while (at < source.length && source[at] !== "\n" && source[at] !== "\r") at++;
      kind = "comment";
    } else if (c === '"' || c === "'") {
      at++;
      while (at < source.length) {
        if (source[at] === "\\") {
          at += 2;
          continue;
        }
        if (source[at++] === c) break;
      }
      kind = "literal";
    } else {
      ATOM.lastIndex = at;
      if (source.startsWith("<-", at) && /[\w.]/.test(source[at - 1] ?? "")) at++;
      else if (source.startsWith(">>", at) && at > 0 && BLANK.includes(source[at - 1])) at += 2;
      else at += (ATOM.exec(source)?.[0] ?? c).length;
    }
    out.push({ text: source.slice(beg, at), beg, end: at, col: beg - start, kind });
    if (kind === "newline") start = at;
    else if (kind === "literal") {
      const newline = out[out.length - 1].text.lastIndexOf("\n");
      if (newline >= 0) start = beg + newline + 1;
    }
  }
  return out;
};

const tree = (ts: Token[]): Node[] => {
  const root: Node[] = [];
  const stack: Array<{ children: Node[]; group?: Extract<Node, { open: Token }> }> = [
    { children: root },
  ];
  for (let i = 0; i < ts.length; i++) {
    const t = ts[i],
      prev = ts[i - 1];
    const close = DELIMITERS.get(t.text);
    // Bend distinguishes type arguments from comparisons by a glued '<'.
    const angle = t.text === "<" && prev?.end === t.beg && /^[\w.]+$/.test(prev.text);
    const frame = stack[stack.length - 1];
    if (close && (t.text !== "<" || angle)) {
      const group = { open: t, close: { ...t, text: close }, children: [] as Node[] };
      frame.children.push(group);
      stack.push({ children: group.children, group });
    } else if (frame.group?.close.text === t.text) {
      frame.group.close = t;
      stack.pop();
    } else frame.children.push(t);
  }
  if (stack.length !== 1) throw new Error("unbalanced delimiters");
  return root;
};

// Width counts code points, as Bend does.
// oxlint-disable-next-line typescript/no-misused-spread
const points = (text: string): number => [...text].length;
// A loop, not /[ \t\n\r]+$/: that regex scans every whitespace run to its end.
const trimEnd = (text: string): string => {
  let end = text.length;
  while (end > 0 && BLANK.includes(text[end - 1])) end--;
  return text.slice(0, end);
};

const first = (n: Node): Token => ("open" in n ? n.open : n);
const last = (n: Node): Token => ("open" in n ? n.close : n);
const soft = (flat = " "): Doc => ({ kind: "line", flat });
const hard = (offset = 0): Doc => ({ kind: "line", flat: "", hard: true, offset });
const nest = (doc: Doc, amount: number): Doc => ({ kind: "nest", doc, amount });
const group = (doc: Doc): Doc => ({ kind: "group", doc });

const gluedPrefix = (a: Token, b: Node | undefined): boolean =>
  ["+", "-", "%", "&"].includes(a.text) && b !== undefined && a.end === first(b).beg;

// Closes the levels deeper than `col`, then opens `col` if it is deeper.
const indented = (levels: number[], col: number): void => {
  while (levels.length > 1 && col < levels[levels.length - 1]) levels.pop();
  if (col > levels[levels.length - 1]) levels.push(col);
};

const separator = (a: Node, b: Node): string => {
  const x = last(a),
    y = first(b),
    l = x.text,
    r = y.text;
  if (y.kind === "comment") return "  ";
  if ([",", ";", ":", "?", "!", "."].includes(r)) return "";
  if ([",", ";", ":"].includes(l)) return " ";
  if (["~", "@", "?", "!", "\\"].includes(l)) return "";
  if (gluedPrefix(x, b)) return "";
  if (l.endsWith("n+")) return "";
  // A constructor brace must be glued to its name; a separated brace can
  // instead be the next (annotated) argument in a comma-optional call.
  if ("open" in b && r === "{" && x.end !== y.beg) return " ";
  if ("open" in b && ["(", "[", "{", "<"].includes(r)) {
    if (
      (/^[\w.]+$/.test(l) || l === "!" || [")", "]", "}"].includes(l)) &&
      !["return", "case", "match", "for", "exs", "is"].includes(l)
    )
      return "";
  }
  // Module paths are printed separately; other atoms need a separator.
  return " ";
};

const sequence = (nodes: Node[], opts: FormatOptions, base: number, raw = false): Doc => {
  const out: Doc[] = [];
  const levels = [base];
  let continuation: Doc[] | undefined;
  let prev: Node | undefined;
  for (let i = 0; i < nodes.length; i++) {
    const n = nodes[i],
      t = first(n);
    if (!("open" in n) && t.kind === "newline") {
      if (raw || (prev && last(prev).kind === "comment")) {
        let next = i + 1;
        while (next < nodes.length && first(nodes[next]).kind === "newline") next++;
        if (next < nodes.length) {
          indented(levels, first(nodes[next]).col);
          (continuation ?? out).push(hard((levels.length - 1) * opts.tabWidth));
        } else if (prev && last(prev).kind === "comment") (continuation ?? out).push(hard());
        i = next - 1;
        prev = undefined;
      }
      continue;
    }
    if (prev) {
      const prefix = gluedPrefix(t, nodes[i + 1]);
      if (!raw && !("open" in n) && OPERATORS.has(t.text) && !prefix) {
        if (!continuation) {
          continuation = [];
          out.push(nest(continuation, opts.tabWidth));
        }
        continuation.push(soft());
      } else (continuation ?? out).push(separator(prev, n));
    }
    (continuation ?? out).push(nodeDoc(n, opts, base));
    prev = n;
  }
  return group(out);
};

const nodeDoc = (n: Node, opts: FormatOptions, base: number): Doc => {
  if (!("open" in n))
    return n.kind === "newline" ? "" : n.kind === "comment" ? commentText(n.text) : n.text;
  const children = n.children;
  if (!children.length) return n.open.text + n.close.text;
  // Embedded statement bodies have significant line/column boundaries.
  // They retain those boundaries, while nested ordinary calls still wrap.
  const block = children.some(
    (c) => !("open" in c) && ["match", "case", "do", "=", ";", "%", "\\"].includes(c.text),
  );
  if (block) return [n.open.text, sequence(children, opts, base, true), n.close.text];
  const parts: Node[][] = [[]];
  for (let i = 0; i < children.length; i++) {
    const c = children[i];
    if (!("open" in c) && c.text === ",") {
      const next = children[i + 1];
      if (next && first(next).kind === "comment") {
        parts[parts.length - 1].push(c, next);
        i++;
      }
      parts.push([]);
    } else parts[parts.length - 1].push(c);
  }
  while (parts.length > 1 && parts[parts.length - 1].every((c) => first(c).kind === "newline"))
    parts.pop();
  const content: Doc[] = [];
  for (let i = 0; i < parts.length; i++) {
    if (i) {
      const prev = parts[i - 1].filter((n) => first(n).kind !== "newline");
      if (prev.length && last(prev[prev.length - 1]).kind === "comment") content.push(hard());
      else content.push(",", soft());
    }
    content.push(sequence(parts[i], opts, base));
  }
  const comments = children.some((c) => first(c).kind === "comment");
  // A generic closing '>' must stay glued to its preceding term: a spaced
  // '>' is parsed as a comparison by Bend, even across a newline.
  const closing: Doc = n.close.text === ">" ? "" : comments ? hard() : soft("");
  return group([
    n.open.text,
    nest([comments ? hard() : soft(""), content], opts.tabWidth),
    closing,
    n.close.text,
  ]);
};

// Keep empty comments, whitespace, test expectations, directives and headings.
const commentText = (text: string): string =>
  UNSPACED_COMMENT.test(text) ? "# " + text.slice(1) : text;

// A small document printer: a group is entirely flat if it fits; otherwise
// its list separators break together. Nesting is relative, never alignment
// under a function name. The width is a target, not a license to split atoms.
const print = (doc: Doc, width: number, indent: number, newline: string): string => {
  const stack: Frame[] = [{ doc, indent, flat: false }];
  let out = " ".repeat(indent),
    col = indent;
  const fits = (remaining: number, pending: Frame[]): boolean => {
    while (remaining >= 0 && pending.length) {
      const f = pending.pop()!,
        d = f.doc;
      if (typeof d === "string") {
        if (d.includes("\n")) return true;
        remaining -= points(d);
      } else if (Array.isArray(d)) pending.push(...d.map((doc) => ({ ...f, doc })).reverse());
      else if (d.kind === "line") {
        if (d.hard || !f.flat) return true;
        remaining -= points(d.flat);
      } else pending.push({ doc: d.doc, indent: f.indent + (d.amount ?? 0), flat: true });
    }
    return remaining >= 0;
  };
  while (stack.length) {
    const f = stack.pop()!,
      d = f.doc;
    if (typeof d === "string") {
      out += d;
      col = d.includes("\n") ? points(d.slice(d.lastIndexOf("\n") + 1)) : col + points(d);
    } else if (Array.isArray(d)) stack.push(...d.map((doc) => ({ ...f, doc })).reverse());
    else if (d.kind === "line") {
      if (!d.hard && (f.flat || width === Infinity)) {
        out += d.flat;
        col += points(d.flat);
      } else {
        col = f.indent + (d.offset ?? 0);
        out = trimEnd(out) + newline + " ".repeat(col);
      }
    } else if (d.kind === "nest")
      stack.push({ doc: d.doc, indent: f.indent + d.amount!, flat: f.flat });
    else
      stack.push({
        doc: d.doc,
        indent: f.indent,
        flat:
          f.flat ||
          width === Infinity ||
          fits(width - col, [...stack, { doc: d.doc, indent: f.indent, flat: true }]),
      });
  }
  return trimEnd(out);
};

export const format = (source: string, opts: FormatOptions): string => {
  const newline =
    opts.endOfLine === "preserve"
      ? (/\r?\n/.exec(source)?.[0] ?? "\n")
      : opts.endOfLine === "crlf"
        ? "\r\n"
        : "\n";
  const nodes = tree(tokens(source));
  const records: Node[][] = [[]];
  for (let i = 0; i < nodes.length; i++) {
    const n = nodes[i];
    if (!("open" in n) && n.kind === "newline") {
      const next = nodes[i + 1],
        following = nodes[i + 2];
      const prefix = next && gluedPrefix(first(next), following);
      const previous = records[records.length - 1].at(-1);
      if (
        next &&
        previous &&
        last(previous).kind !== "comment" &&
        first(next).kind !== "comment" &&
        ((!prefix && !("open" in next) && OPERATORS.has(next.text)) ||
          ["->", "=", "++", "&&", "||"].includes(last(previous).text))
      )
        continue;
      records.push([]);
    } else records[records.length - 1].push(n);
  }
  const rows: string[] = [],
    levels = [0];
  let blank = false,
    previous = "",
    previousComment = false;
  for (const record of records) {
    if (!record.length) {
      blank = true;
      continue;
    }
    const head = first(record[0]),
      col = head.col;
    indented(levels, col);
    const indent = (levels.length - 1) * opts.tabWidth;
    const declaration = /^(def|type|law)$/.test(head.text) || head.text === "@";
    const comment = head.kind === "comment";
    const gap =
      col === 0
        ? (declaration && !previousComment && previous !== "@unsafe") || (comment && blank)
        : blank;
    if (gap && rows.length && rows[rows.length - 1] !== "") rows.push("");
    let doc: Doc;
    if (head.text === "import") {
      // Paths and aliases use their own grammar; do not treat / or - as operators.
      const text = trimEnd(source.slice(head.beg, last(record[record.length - 1]).end));
      const at = text.indexOf("#");
      doc = trimEnd(at < 0 ? text : text.slice(0, at))
        .replace(IMPORT, "import ")
        .replace(ALIAS, " as ");
      if (at >= 0) doc = [doc, "  ", commentText(text.slice(at))];
    } else {
      // Canonicalize an inline declaration body into the indented body form.
      const colon =
        col === 0 && declaration ? record.findIndex((n) => !("open" in n) && n.text === ":") : -1;
      if (colon >= 0 && colon < record.length - 1 && first(record[colon + 1]).kind !== "comment") {
        doc = [
          sequence(record.slice(0, colon + 1), opts, col),
          nest([hard(), sequence(record.slice(colon + 1), opts, col)], opts.tabWidth),
        ];
      } else doc = sequence(record, opts, col);
    }
    rows.push(
      print(doc, opts.wrapAtWidth === "never" ? Infinity : opts.wrapAtWidth, indent, newline),
    );
    previous = record.map((n) => first(n).text).join("");
    previousComment = comment;
    blank = false;
  }
  return trimEnd(rows.join(newline)) + newline;
};

export const rules: LintRule[] = [
  {
    id: "format/layout",
    options: {
      tabWidth: { type: "integer", minimum: 1, default: 2 },
      wrapAtWidth: { anyOf: [{ type: "integer", minimum: 1 }, { enum: ["never"] }], default: 100 },
      endOfLine: { enum: ["lf", "crlf", "preserve"], default: "lf" },
    },
    run(cx) {
      const span = { file: cx.root, beg: 0, end: cx.root.text.length };
      const formatted = (): string | Error => {
        try {
          return format(cx.root.text, cx.options as FormatOptions);
        } catch (e) {
          return e instanceof Error ? e : new Error(String(e));
        }
      };
      const text = formatted();
      if (text instanceof Error) {
        return [
          cx.diag({
            message: "Cannot format this file: " + text.message + ". No fix was offered.",
            span,
          }),
        ];
      }
      if (text === cx.root.text) return [];
      if (!cx.sameDeclarations(text))
        return [
          cx.diag({
            message:
              "Cannot safely format this syntax: the result parses differently. No fix was offered.",
            span,
          }),
        ];
      return [
        cx.diag({
          message: "Apply canonical formatting.",
          span,
          fixes: [{ title: "Format file", applicability: "safe", edits: [{ span, text }] }],
        }),
      ];
    },
  },
];
