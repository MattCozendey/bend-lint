// The checker server: see the header of lint.bend. It runs a rules program
// (a build of a file that imports lint.bend), and answers its questions
// about Bend files over local TCP, until the program exits. It is the one TS
// file of this folder, and it goes when Bend's checker is Bend, so any
// optimization is fair here, local mutation included (AGENTS.md).
//
// Usage: bun server.ts <program> <args...>
// Node 24 or later works too, but Bend's checker can need more than its
// default heap: pass --max-old-space-size=8192 for a large program.
//
// It loads a copy of bend.ts with EDITS made: probes that report what Bend's
// parser reads, while the check parses it. A file's syntax goes out as Bend's
// parser has it, before the checker lowers it.

// Imports
// =======

import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { once } from "node:events";
import * as nodeFs from "node:fs";
import * as net from "node:net";
import * as os from "node:os";
import * as nodePath from "node:path";
import * as readline from "node:readline";
import * as url from "node:url";

import type { Body, Book, Err, HTerm, LTerm, Parse, Patt, Quant, Span } from "bend2/bend.ts";
import type * as BendModule from "bend2/bend.ts";

// Types
// =====

type Bend = typeof BendModule;
type Cell = [Quant, string, number, LTerm, Span];

// Bend, and Base as checked once.
type Checker = { Bend: Bend; base: Book };

// An exact edit of bend.ts: the text it must find once, and its replacement.
type Edit = [string, string];

// What the probes report, in the order the parser reads it.
type Seen =
  | { $: "file"; real: string; text: string; ns: string; al: Record<string, string> }
  | { $: "import"; real: string; at: number; line: string; path: string; alias?: string }
  | { $: "declared"; p: Parse; kind: string; k: string; nm?: string; end: number }
  | { $: "tele"; close: string; tele: Cell[]; tk: string[] }
  | { $: "term"; t: LTerm }
  | { $: "body"; b: Body };

type SeenFile = Extract<Seen, { $: "file" }>;
type SeenImport = Extract<Seen, { $: "import" }>;

// What the checker reports of a term it checked: the term (as it checked
// it), the type it checked it as, the book, depth and quantity it checked it
// in, and the def it was checking.
type Checked = { tm: LTerm; ty: HTerm; bok: Book; dep: number; qt: Quant; def: string };

// A syntax node a checked term can come from: its id, its kind, and, for a
// call, how many arguments it applies.
type Origin = { id: number; kind: string; arity: number };

// A type a rule holds a handle to: the type, the book and depth of its
// scope, and the file whose spelling shows it.
type Typed = { ty: HTerm; bok: Book; dep: number; file: Span["file"] };

// A file the check parsed, with what its parser read, in order.
type Parsed = { file: SeenFile; seen: Seen[] };

// Where a span of a file is, in code points of the file on disk.
type Range = [number, number];

// A syntax node and the nodes under it.
type Tree = {
  kind: string;
  name: string;
  binder: string;
  quantity: string;
  range?: Range;
  target: string;
  kids: Tree[];
  // The span object the parser gave the term: what ties a checked term to
  // its node. And, for a call, how many arguments it applies.
  origin?: Span;
  arity?: number;
};

// Constants
// =========

const GIVE = "set BEND_DIR to a bend checkout";

const ESCAPES: Record<string, string> = { "\\": "\\\\", "\t": "\\t", "\n": "\\n" };

const CACHE = nodePath.join(
  process.env.XDG_CACHE_HOME ??
    (process.platform === "win32"
      ? (process.env.LOCALAPPDATA ?? nodePath.join(os.homedir(), "AppData", "Local"))
      : nodePath.join(os.homedir(), ".cache")),
  "bend-lint",
  "server",
);

// The edits that make bend.ts report what it parses to PROBES.
const EDITS: Edit[] = [
  [
    'parse_book(book, dir, body.join("\\n"), ns, al);',
    'seeFile(real, text, ns, al);\n  parse_book(book, dir, body.join("\\n"), ns, al);',
  ],
  ['body[i] = "";', 'seeImport(real, at, lines[i], m);\n    body[i] = "";'],
  [
    "const k   = law ? q : parse_fresh(p, nm);",
    'const k   = seeDeclared(p, "Definition", law ? q : parse_fresh(p, nm), nm);',
  ],
  ["tele_bind(tele, parse_term(p))", "tele_bind(tele, seeTerm(parse_term(p)))"],
  ["body_flatten(parse_body(p), vars,", "body_flatten(seeBody(parse_body(p)), vars,"],
  [
    'if (parse_word(p, "type")) {\n      const k = parse_fresh(p, parse_name(p));',
    'if (parse_word(p, "type")) {\n      const k = seeDeclared(p, "Datatype", parse_fresh(p, parse_name(p)));',
  ],
  ["const K = parse_term(p);", "const K = seeTerm(parse_term(p));"],
  [
    'const c = parse_fresh(p, parse_name(p), book.ctrs, "a fresh constructor name");',
    'const c = seeDeclared(p, "Constructor", parse_fresh(p, parse_name(p), book.ctrs, "a fresh constructor name"));',
  ],
  [
    'if (parse_word(p, "law")) {\n      const k = parse_fresh(p, parse_name(p));',
    'if (parse_word(p, "law")) {\n      const k = seeDeclared(p, "Law", parse_fresh(p, parse_name(p)));',
  ],
  ["T: term_higher(T), v: null, x: tc,", "T: term_higher(seeTerm(T)), v: null, x: tc,"],
  ["export function parse_tele(", "function unseen_parse_tele("],
  ["export function term_infer(", "function unseen_term_infer("],
  ["export function term_check(", "function unseen_term_check("],
];

// What EDITS call, appended to bend.ts. Each reports to the probe the
// server sets on globalThis, and hands its value on.
const PROBES = `
const BEND_LINT_SEE = (seen: unknown): void => {
  (globalThis as { BEND_LINT_SEE?: (seen: unknown) => void }).BEND_LINT_SEE?.(seen);
};
function seeFile(real: string, text: string, ns: string, al: Record<Name, Name>): void {
  BEND_LINT_SEE({ $: "file", real, text, ns, al });
}
function seeImport(real: string, at: number, line: string, m: RegExpExecArray): void {
  BEND_LINT_SEE({ $: "import", real, at, line, path: m[1], alias: m[2] });
}
function seeDeclared(p: Parse, kind: string, k: Name, nm?: Name): Name {
  BEND_LINT_SEE({ $: "declared", p, kind, k, nm, end: p.pos });
  return k;
}
function seeTerm(t: LTerm): LTerm {
  BEND_LINT_SEE({ $: "term", t });
  return t;
}
function seeBody(b: Body): Body {
  BEND_LINT_SEE({ $: "body", b });
  return b;
}
const BEND_LINT_CHECKED = (checked: unknown): void => {
  (globalThis as { BEND_LINT_CHECKED?: (checked: unknown) => void }).BEND_LINT_CHECKED?.(checked);
};
export const UNSEEN = { term_infer: unseen_term_infer, term_check: unseen_term_check };
export const term_infer = (...args: Parameters<typeof unseen_term_infer>): Infer => {
  const r = unseen_term_infer(...args);
  BEND_LINT_CHECKED({ tm: r.tm, ty: r.ty, bok: args[0], dep: args[5], qt: args[3], def: args[1].def });
  return r;
};
export const term_check = (...args: Parameters<typeof unseen_term_check>): Check => {
  const r = unseen_term_check(...args);
  BEND_LINT_CHECKED({ tm: r.tm, ty: args[4], bok: args[0], dep: args[6], qt: args[3], def: args[1].def });
  return r;
};
export const parse_tele = (p: Parse, close: string, tk: Name[] = []): Array<[Quant, Name, number, LTerm, Span]> => {
  const tele = unseen_parse_tele(p, close, tk);
  BEND_LINT_SEE({ $: "tele", close, tele, tk });
  return tele;
};
`;

const QUANTITIES: Record<Quant["$"], string> = { None: "Erased", Lone: "Once", Many: "Many" };

// The syntax of a checked term, by its kind.
const SYNTAX: Record<LTerm["$"], string> = {
  Var: "Variable",
  Ref: "Reference",
  Sub: "Substitution",
  Let: "Let",
  Typ: "Sort",
  Qnt: "QuantityType",
  Qua: "QuantityLiteral",
  Min: "QuantityMinimum",
  All: "Forall",
  Lam: "Lambda",
  App: "Application",
  ADT: "TypeApplication",
  Ctr: "Construction",
  Lit: "Literal",
  Mat: "Elimination",
  Efq: "Absurd",
  Eql: "Equality",
  Rfl: "Reflexivity",
  Rwt: "Rewrite",
  Hol: "Hole",
  Ann: "Annotation",
};

// The types rules hold handles to, by check (from 1), then by handle.
const TYPES: Typed[][] = [];

// The binders a telescope declares, by its closing bracket.
const CELLS: Record<string, string> = { ")": "Parameter", ">": "Parameter", "}": "Field" };

// Functions
// =========

const message = (e: unknown): string => (e instanceof Error ? e.message : String(e));

const field = (text: string): string => text.replace(/[\\\t\n]/g, (c) => ESCAPES[c]);

const unfield = (text: string): string =>
  text.replace(/\\(.)/g, (_, c: string) => (c === "t" ? "\t" : c === "n" ? "\n" : c));

const record = (fields: string[]): string => fields.map(field).join("\t") + "\n";

const isErr = (e: unknown): e is Err =>
  typeof e === "object" && e !== null && (e as { $?: unknown }).$ === "Err";

// The bend2 folder: BEND_DIR, a checkout or its bend2 folder.
const bendDir = (): string => {
  const chosen = process.env.BEND_DIR;
  if (chosen === undefined) {
    throw new Error("no BEND_DIR; " + GIVE);
  }
  const dir = nodePath.resolve(chosen);
  const found = [nodePath.join(dir, "bend2"), dir].find((d) =>
    nodeFs.existsSync(nodePath.join(d, "bend.ts")),
  );
  if (found === undefined) {
    throw new Error(`no bend2 at ${dir} (it needs bend.ts); ${GIVE}`);
  }
  return found;
};

// A fresh book that holds Base, as main.ts's book_seed makes it.
const seeded = (Bend: Bend, base: Book): Book => ({
  ...Bend.book_nil(),
  tlds: Object.fromEntries(Object.entries(base.tlds).map(([k, tld]) => [k, { ...tld }])),
  ctrs: { ...base.ctrs },
  order: [...base.order],
  tmps: Object.fromEntries(Object.entries(base.tmps).map(([k, m]) => [k, new Map(m)])),
});

const drift = (text: string): Error =>
  Object.assign(new Error(text + "; update EDITS in BEND-REWRITE-2/server.ts"), {
    name: "DriftError",
  });

// bend.ts with EDITS made and PROBES appended, and BEND_DIR kept at `dir`, so
// the copy finds base.bend where the original does. Line ends become LF
// first.
const patched = (dir: string, src: string): string =>
  [
    ...EDITS,
    ["export const BEND_DIR = (", `export const BEND_DIR = ${JSON.stringify(dir)} ?? (`],
  ].reduce(
    (out, [at, to]) => {
      const n = out.split(at).length - 1;
      if (n !== 1) {
        throw drift(`bend.ts has ${n} of ${JSON.stringify(at)}, not 1`);
      }
      return out.replace(at, () => to);
    },
    src.replace(/\r\n/g, "\n"),
  ) + PROBES;

// The patched copy of the bend.ts in `dir`, written once to the cache.
const copied = (dir: string): string => {
  const text = patched(
    dir.replaceAll("\\", "/"),
    nodeFs.readFileSync(nodePath.join(dir, "bend.ts"), "utf8"),
  );
  const file = nodePath.join(
    CACHE,
    createHash("sha256").update(text).digest("hex").slice(0, 16),
    "bend.ts",
  );
  if (!nodeFs.existsSync(file)) {
    nodeFs.mkdirSync(nodePath.dirname(file), { recursive: true });
    nodeFs.writeFileSync(file, text);
  }
  return file;
};

const load = async (): Promise<Checker> => {
  const Bend = (await import(url.pathToFileURL(copied(bendDir())).href)) as Bend;
  const unseen = (Bend as unknown as { UNSEEN: Record<string, (...args: never[]) => unknown> })
    .UNSEEN;
  [
    ["term_infer", 6],
    ["term_check", 7],
  ].forEach(([name, n]) => {
    if (unseen[name].length !== n) {
      throw drift(`${name} takes ${unseen[name].length} parameters, not ${n}`);
    }
  });
  const base = Bend.book_nil();
  await Bend.book_load(base, Bend.BASE_BEND, "", new Map());
  Bend.book_valid(base, 0);
  return { Bend, base };
};

// Where each line of `text` starts.
const starts = (text: string): number[] => [
  0,
  ...[...text.matchAll(/\n/g)].map((found) => found.index + 1),
];

// The last index in sorted `xs` whose value is at most `x`.
const lastAtMost = (xs: number[], x: number, lo = 0, hi = xs.length - 1): number => {
  if (lo >= hi) {
    return lo;
  }
  const mid = Math.ceil((lo + hi) / 2);
  return xs[mid] <= x ? lastAtMost(xs, x, mid, hi) : lastAtMost(xs, x, lo, mid - 1);
};

// A disk offset of `text` (UTF-16 units) in code points, as Bend counts.
const pointsOf = (text: string): ((off: number) => number) =>
  /[\uD800-\uDFFF]/.test(text)
    ? (off) => text.slice(0, off).match(/./gsu)?.length ?? 0
    : (off) => off;

// A span of what the parser `read` of `file` as a Range on disk. The parser
// reads the file with its import lines blanked, so a span moves by line.
const placerOf = (
  file: SeenFile,
  read: Parse | undefined,
): ((s: Span | undefined) => Range | undefined) => {
  const disk = starts(file.text);
  const lines = starts(read?.str ?? file.text);
  const points = pointsOf(file.text);
  const at = (off: number): number => {
    const line = lastAtMost(lines, off);
    return points(disk[line] + off - lines[line]);
  };
  return (s) => (s === undefined || s.file !== read ? undefined : [at(s.beg), at(s.end)]);
};

const tree = (kind: string, kids: Tree[], more: Partial<Tree> = {}): Tree => ({
  kind,
  name: "",
  binder: "",
  quantity: "",
  target: "",
  kids,
  ...more,
});

// The trees of a term, a body and a pattern, as the parser read them.
const syntaxOf = (place: (s: Span | undefined) => Range | undefined) => {
  const range = (s: Span | undefined): Partial<Tree> => ({ range: place(s) });
  // A use's name as written: the name its span starts with, if any.
  const used = (k: string, s: Span | undefined): Partial<Tree> => {
    const name = /[A-Za-z_][\w.]*/y;
    name.lastIndex = s?.beg ?? 0;
    return { target: k, name: (s && name.exec(s.file.str)?.[0]) ?? "", ...range(s) };
  };
  const term = (t: LTerm): Tree => {
    const of = (TERMS as Record<string, ((t: LTerm) => Tree) | undefined>)[t.$];
    if (of === undefined) {
      throw drift(`unknown term kind ${t.$}`);
    }
    return { ...of(t), origin: t.s };
  };
  // A call's head and arguments: the applications that share its span
  // object are one call (`f(a, b)`, `a + b`).
  const calls = (t: Extract<LTerm, { $: "App" }>): [LTerm, LTerm[]] => {
    const go = (u: LTerm, args: LTerm[]): [LTerm, LTerm[]] =>
      u.$ === "App" && u.s === t.s ? go(u.f, [u.x, ...args]) : [u, args];
    return t.s === undefined ? [t.f, [t.x]] : go(t, []);
  };
  const leaf =
    (kind: string) =>
    (t: LTerm): Tree =>
      tree(kind, [], range(t.s));
  const TERMS: { [K in LTerm["$"]]: (t: Extract<LTerm, { $: K }>) => Tree } = {
    Var: (t) =>
      t.v === undefined
        ? tree("Variable", [], { name: t.k, binder: String(t.i), ...range(t.s) })
        : tree("Reference", [], { name: t.k, target: t.v.$ === "Ref" ? t.v.k : "", ...range(t.s) }),
    Ref: (t) => tree("Reference", [], used(t.k, t.s)),
    Sub: (t) =>
      tree("Substitution", [patt(t.v), term(t.f)], { binder: String(t.i), ...range(t.s) }),
    Let: (t) =>
      tree(
        "Let",
        [
          ...t.k.map((k, j) =>
            tree("Binding", [term(t.v[j])], {
              name: k,
              binder: String(t.i[j]),
              quantity: QUANTITIES[t.q[j].$],
            }),
          ),
          term(t.f),
        ],
        range(t.s),
      ),
    Typ: (t) => tree("Sort", [term(t.g)], range(t.s)),
    Qnt: leaf("QuantityType"),
    Qua: (t) => tree("QuantityLiteral", [], { quantity: QUANTITIES[t.q.$], ...range(t.s) }),
    Min: (t) => tree("QuantityMinimum", [term(t.a), term(t.b)], range(t.s)),
    All: (t) =>
      tree("Forall", [term(t.A), term(t.B)], {
        name: t.k,
        binder: String(t.i),
        quantity: QUANTITIES[t.q.$],
        ...range(t.s),
      }),
    Lam: (t) =>
      tree("Lambda", [term(t.f)], {
        name: t.k,
        binder: String(t.i),
        quantity: t.q === undefined ? "" : QUANTITIES[t.q.$],
        ...range(t.s),
      }),
    App: (t) => {
      const [head, args] = calls(t);
      return tree("Application", [term(head), ...args.map(term)], {
        arity: args.length,
        ...range(t.s),
      });
    },
    ADT: (t) => tree("TypeApplication", t.x.map(term), used(t.k, t.s)),
    Ctr: (t) => tree("Construction", t.x.map(term), used(t.k, t.s)),
    Lit: (t) => tree("Literal", [], { name: String(t.v), target: t.k, ...range(t.s) }),
    Mat: (t) => tree("Elimination", [term(t.h), term(t.m)], { target: t.k, ...range(t.s) }),
    Efq: leaf("Absurd"),
    Eql: (t) => tree("Equality", [term(t.a), term(t.b), term(t.T)], range(t.s)),
    Rfl: leaf("Reflexivity"),
    Rwt: (t) => tree("Rewrite", [term(t.e), term(t.p), term(t.f)], range(t.s)),
    Hol: (t) => tree("Hole", [], { name: t.k, ...range(t.s) }),
    Ann: (t) => tree("Annotation", [term(t.x), term(t.T)], range(t.s)),
  };
  const patt = (q: Patt): Tree =>
    q.$ === "PVar"
      ? tree("PatternVariable", [], {
          name: q.k,
          binder: String(q.i),
          quantity: QUANTITIES[q.q.$],
          ...range(q.s),
        })
      : tree("PatternConstructor", q.x.map(patt), used(q.k, q.s));
  const body = (b: Body): Tree =>
    b.$ === "Match"
      ? tree(
          "Match",
          [...b.e.map(term), ...b.r.map((row) => tree("Case", [...row.p.map(patt), body(row.f)]))],
          range(b.s),
        )
      : b.$ === "Local"
        ? tree("Destructure", [...b.k.map(patt), ...b.v.map(term), body(b.f)], {
            quantity: QUANTITIES[b.q.$],
          })
        : term(b);
  return { term, body };
};

// The trees of what a file declares: each declaration with its binders,
// signature and body; a constructor under its type.
const declarationsOf = (parsed: Parsed): Tree[] => {
  const heads = parsed.seen.flatMap((seen, at) => (seen.$ === "declared" ? [{ seen, at }] : []));
  const place = placerOf(parsed.file, heads[0]?.seen.p);
  const { term, body } = syntaxOf(place);
  const under = (seen: Seen): Tree[] =>
    seen.$ === "tele"
      ? seen.tele.map(([q, k, i, T, s]) =>
          tree(CELLS[seen.close], [term(T)], {
            name: k,
            binder: String(i),
            quantity: seen.tk.includes(k) ? "Template" : QUANTITIES[q.$],
            range: place(s),
          }),
        )
      : seen.$ === "term"
        ? [tree("Returns", [term(seen.t)])]
        : seen.$ === "body"
          ? [tree("Body", [body(seen.b)])]
          : [];
  const own = (k: string): string =>
    parsed.file.ns !== "" && k.startsWith(parsed.file.ns + ":")
      ? k.slice(parsed.file.ns.length + 1)
      : k;
  const declared = heads.map(({ seen, at }, j) => {
    const name = seen.nm ?? own(seen.k);
    const next = heads[j + 1]?.at ?? parsed.seen.length;
    return tree(seen.kind, parsed.seen.slice(at + 1, next).flatMap(under), {
      name,
      target: seen.k,
      range: place({ file: seen.p, beg: seen.end - name.length, end: seen.end }),
    });
  });
  const tops = declared.flatMap((d, i) => (d.kind === "Constructor" ? [] : [i]));
  return tops.map((i, j) => ({
    ...declared[i],
    kids: [...declared[i].kids, ...declared.slice(i + 1, tops[j + 1] ?? declared.length)],
  }));
};

// The trees of a file's imports: each alias (or Base) and the file it loads.
const importsOf = (
  file: SeenFile,
  imports: SeenImport[],
  real: (ns: string) => string,
  base: string,
): Tree[] => {
  const points = pointsOf(file.text);
  return imports.map((i) => {
    const from = i.line.indexOf(i.path);
    const beg =
      i.at + (i.alias === undefined ? from : i.line.indexOf(i.alias, from + i.path.length));
    const name = i.alias ?? "Base";
    return tree("Import", [], {
      name,
      target: i.alias === undefined ? base : real(file.al[i.alias]),
      range: [points(beg), points(beg + name.length)],
    });
  });
};

// The records of the nodes of `trees`, parents first, numbered from `first`,
// each with its parent's id and its top-level node's (its owner). Each node
// with a term's span object is registered in `origins`.
// One pass, so it is linear in the nodes: `out` is local to it.
const nodeRecords = (trees: Tree[], first: number, origins: Map<Span, Origin[]>): string[] => {
  const out: string[] = [];
  const visit = (t: Tree, parent: number, owner: number): void => {
    const id = first + out.length;
    if (t.origin !== undefined) {
      origins.set(t.origin, [
        ...(origins.get(t.origin) ?? []),
        { id, kind: t.kind, arity: t.arity ?? 0 },
      ]);
    }
    out.push(
      record([
        "node",
        String(id),
        String(parent),
        String(owner === 0 ? id : owner),
        t.kind,
        t.name,
        t.binder,
        t.quantity,
        t.range === undefined ? "" : String(t.range[0]),
        t.range === undefined ? "" : String(t.range[1]),
        t.target,
      ]),
    );
    t.kids.forEach((kid) => visit(kid, id, owner === 0 ? id : owner));
  };
  trees.forEach((t) => visit(t, 0, 0));
  return out;
};

// The files the check parsed, each with what its parser read.
const parsedOf = (seen: Seen[]): Parsed[] => {
  const at = seen.flatMap((s, i) => (s.$ === "file" ? [i] : []));
  return at.map((i, j) => ({
    file: seen[i] as SeenFile,
    seen: seen.slice(i + 1, at[j + 1] ?? seen.length).filter((s) => s.$ !== "import"),
  }));
};

// A checked term without the annotations the checker wraps it in: those
// have no span. An annotation the source writes has one.
const source = (t: LTerm): LTerm => (t.$ === "Ann" && t.s === undefined ? source(t.x) : t);

// How many arguments a checked call applies: the applications that share
// its span object.
const arity = (t: LTerm, s: Span): number =>
  t.$ === "App" && t.s === s ? 1 + arity(source(t.f), s) : 0;

// Whether a checked term is the node `o`'s: the same syntax (a literal
// unfolds to constructors; a variable can check as a reference), and, for a
// call, the whole call.
const fits = (o: Origin, t: LTerm): boolean =>
  (o.kind === SYNTAX[t.$] ||
    (o.kind === "Literal" && t.$ === "Ctr") ||
    (o.kind === "Variable" && t.$ === "Ref")) &&
  (t.$ !== "App" || t.s === undefined || arity(t, t.s) === o.arity);

// The checker's judgments on each node, by node id: a report goes to the
// node its term's span object came from, if it fits it. Template instances
// are left out.
const attach =
  (origins: Map<Span, Origin[]>, judged: Map<number, Checked[]>) =>
  (c: Checked): void => {
    const tm = source(c.tm);
    const os = c.def.includes("~") || tm.s === undefined ? undefined : origins.get(tm.s);
    os?.filter((o) => fits(o, tm)).forEach((o) => {
      const list = judged.get(o.id) ?? [];
      list.push({ ...c, tm });
      judged.set(o.id, list);
    });
  };

// A node's judgments, those the checker counts the same (same quantity, and
// types its equality says are equal) once each: copies of one term, as
// pattern compilation makes them.
const distinct = (Bend: Bend, cs: Checked[]): Checked[] =>
  cs.reduce<Checked[]>((out, c) => {
    const same = (u: Checked): boolean => {
      try {
        return u.qt.$ === c.qt.$ && Bend.term_compare("EQ", c.bok, u.ty, c.ty, c.dep);
      } catch {
        return false;
      }
    };
    if (!out.some(same)) {
      out.push(c);
    }
    return out;
  }, []);

// The fact records of the nodes numbered from `first` to `last`: each of a
// node's distinct judgments, with a new handle to its type in check `id`.
const factRecords = (
  Bend: Bend,
  judged: Map<number, Checked[]>,
  first: number,
  last: number,
  id: number,
): string[] =>
  Array.from({ length: last - first }, (_, j) => first + j).flatMap((node) =>
    distinct(Bend, judged.get(node) ?? []).map((c) => {
      const types = TYPES[id - 1];
      types.push({ ty: c.ty, bok: c.bok, dep: c.dep, file: c.tm.s!.file });
      return record([
        "fact",
        String(node),
        String(id),
        String(types.length - 1),
        QUANTITIES[c.qt.$],
      ]);
    }),
  );

// The answer to `check <path> <facts|syntax>`: each file the check parsed
// (path, namespace, text), then its syntax nodes, then, with facts, the
// checker's judgments on them; or, if the check failed, the files it read,
// then why. The syntax is read before the check, so a judgment can find
// its node. The probes are global, so checks must not overlap.
const check = async ({ Bend, base }: Checker, path: string, facts: boolean): Promise<string> => {
  const book = seeded(Bend, base);
  const seen = new Map<string, string | null>([[Bend.BASE_BEND, ""]]);
  const reported: Seen[] = [];
  const origins = new Map<Span, Origin[]>();
  const judged = new Map<number, Checked[]>();
  const hook = globalThis as {
    BEND_LINT_SEE?: (seen: Seen) => void;
    BEND_LINT_CHECKED?: (checked: Checked) => void;
  };
  hook.BEND_LINT_SEE = (s) => reported.push(s);
  try {
    await Bend.book_load(book, nodePath.resolve(path).replaceAll("\\", "/"), "", seen);
    hook.BEND_LINT_SEE = undefined;
    const real = (ns: string): string =>
      [...seen].find(([at, n]) => at !== Bend.BASE_BEND && n === ns)?.[0] ?? "";
    const imports = reported.filter((x): x is SeenImport => x.$ === "import");
    const files = parsedOf(reported);
    const sections = files.reduce<Array<{ file: SeenFile; nodes: string[]; first: number }>>(
      (done, parsed) => {
        const first = 1 + done.reduce((n, d) => n + d.nodes.length, 0);
        const trees = [
          ...importsOf(
            parsed.file,
            imports.filter((i) => i.real === parsed.file.real),
            real,
            Bend.BASE_BEND,
          ),
          ...declarationsOf(parsed),
        ];
        return [...done, { file: parsed.file, nodes: nodeRecords(trees, first, origins), first }];
      },
      [],
    );
    hook.BEND_LINT_CHECKED = facts ? attach(origins, judged) : undefined;
    Bend.book_valid(book, base.order.length);
    TYPES.push([]);
    const id = TYPES.length;
    return sections
      .flatMap(({ file, nodes, first }) => [
        record(["file", file.real, file.ns, file.text]),
        ...nodes,
        ...factRecords(Bend, judged, first, first + nodes.length, id),
      ])
      .join("");
  } catch (e) {
    return [
      ...[...seen.keys()].filter((p) => p !== Bend.BASE_BEND).map((p) => record(["read", p])),
      record(["fail", isErr(e) ? Bend.err_show(e) : message(e)]),
    ].join("");
  } finally {
    hook.BEND_LINT_SEE = undefined;
    hook.BEND_LINT_CHECKED = undefined;
  }
};

// The answer to one question about types: `show:<check>:<id>`,
// `same:<check>:<id>:<check>:<id>` or `normal:<check>:<id>`.
const question = ({ Bend }: Checker, q: string): string => {
  const [op, ...ns] = q.split(":");
  const at = (c: number, i: number): Typed => {
    const t = TYPES[c - 1]?.[i];
    if (t === undefined) {
      throw new Error("no type " + c + ":" + i);
    }
    return t;
  };
  const [c, i, d, j] = ns.map(Number);
  if (op === "show") {
    const t = at(c, i);
    return record(["shown", Bend.term_show(Bend.term_lower(t.ty, t.dep), -1, [], t.file)]);
  }
  if (op === "same") {
    const a = at(c, i);
    const b = at(d, j);
    return record(["same", String(c === d && Bend.term_compare("EQ", a.bok, a.ty, b.ty, a.dep))]);
  }
  if (op === "normal") {
    const t = at(c, i);
    TYPES[c - 1].push({ ...t, ty: Bend.term_snf(t.bok, t.ty) });
    return record(["normal", String(c), String(TYPES[c - 1].length - 1)]);
  }
  throw new Error("unknown question " + q);
};

// The answer to `ask <question>...`: one record per question, in order.
const ask = (checker: Checker, questions: string[]): string => {
  try {
    return questions.map((q) => question(checker, q)).join("");
  } catch (e) {
    return record(["fail", message(e)]);
  }
};

// The answer to `real <path>`: the path, absolute, with links resolved if it
// exists, and "/" between its parts.
const realPath = (path: string): string => {
  const absolute = nodePath.resolve(path);
  return record([
    "real",
    (nodeFs.existsSync(absolute) ? nodeFs.realpathSync.native(absolute) : absolute).replaceAll(
      "\\",
      "/",
    ),
  ]);
};

const answer = (checker: Checker, line: string): Promise<string> => {
  const [op, ...args] = line.split("\t").map(unfield);
  return op === "check" && args.length === 2
    ? check(checker, args[0], args[1] === "facts")
    : op === "real" && args.length === 1
      ? Promise.resolve(realPath(args[0]))
      : op === "ask"
        ? Promise.resolve(ask(checker, args))
        : Promise.resolve(record(["fail", "unknown request: " + line]));
};

// One request: read its line, write the whole answer, close.
const serve = async (checker: Checker, socket: net.Socket): Promise<void> => {
  const lines = readline.createInterface({ input: socket });
  const [line] = (await once(lines, "line")) as [string];
  lines.close();
  socket.end(await answer(checker, line));
};

// Side effects
// ============

const [program, ...args] = process.argv.slice(2);
if (program === undefined) {
  console.error("usage: bun server.ts <program> <args...>");
  process.exit(2);
}

const checker = await load().catch((e: unknown) => {
  console.error("bend-lint: " + message(e));
  process.exit(2);
});

const server = net.createServer((socket) => void serve(checker, socket));
server.listen(0, "127.0.0.1");
await once(server, "listening");

const child = spawn(program, args, {
  env: { ...process.env, BEND_LINT_PORT: String((server.address() as net.AddressInfo).port) },
  stdio: "inherit",
});
const [code] = (await once(child, "exit")) as [number | null];
server.close();
process.exit(code ?? 1);
