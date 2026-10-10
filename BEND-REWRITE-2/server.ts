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
// parser has it, before the checker lowers it. Facts are read after the
// check, from what the checker leaves in the book: each def's elaborated body
// (`e`, what Bend compiles), and each declaration's type.

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

// A syntax node a checked term can be: its id, kind, name and target, the
// span objects of its children, and, for a variable, its binder's key in its
// top-level declaration.
type Origin = {
  id: number;
  kind: string;
  name: string;
  target: string;
  kids: Array<Span | undefined>;
  binder?: string;
};

// The binders around a checked term, innermost first: each level's name and
// token, the id of the syntax node that writes its binder, or the checked
// binder itself if no node does. Cells are shared, never copied.
type Scope = { level: number; name: string; token: unknown; up: Scope } | null;

// A type a rule holds a handle to: the type, the book, depth and binders of
// its scope, and the file whose spelling shows it.
type Typed = { ty: HTerm; bok: Book; dep: number; scope: Scope; file: Span["file"] };

// What the checker found of a node: the type of the term it is, or the type
// its binder declares, with the term's demand or the binder's quantity.
type Judged = Typed & { role: "term" | "binder"; qt: Quant };

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
  // The span object the parser gave the term or binder: what ties a checked
  // term to its node.
  origin?: Span;
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

// The syntax of the nodes that declare a binder.
const BINDERS = new Set(["Parameter", "Field", "PatternVariable", "Lambda", "Forall", "Binding"]);

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
              origin: t.s,
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
      return tree("Application", [term(head), ...args.map(term)], range(t.s));
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
          origin: q.s,
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
            origin: s,
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
// with a span object is registered in `origins`; each binder, by its key in
// its top-level declaration, in `binders`.
// One pass, so it is linear in the nodes: `out` is local to it.
const nodeRecords = (
  trees: Tree[],
  first: number,
  origins: Map<Span, Origin[]>,
  binders: Map<string, number>,
): string[] => {
  const out: string[] = [];
  const visit = (t: Tree, parent: number, owner: number): void => {
    const id = first + out.length;
    const key = (owner === 0 ? id : owner) + ":" + t.binder;
    if (t.origin !== undefined) {
      const at = origins.get(t.origin);
      const origin: Origin = {
        id,
        kind: t.kind,
        name: t.name,
        target: t.target,
        kids: t.kids.map((kid) => kid.origin),
        binder: t.kind === "Variable" ? key : undefined,
      };
      if (at === undefined) {
        origins.set(t.origin, [origin]);
      } else {
        at.push(origin);
      }
    }
    if (t.binder !== "" && BINDERS.has(t.kind)) {
      binders.set(key, id);
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

// The checker wraps each term of an elaborated body it returns in an
// annotation without a span, which holds the term's type (Infer, Check); an
// annotation the source writes is gone by then.
const isTyping = (t: LTerm): t is Extract<LTerm, { $: "Ann" }> =>
  t.$ === "Ann" && t.s === undefined && t.T.$ === "Var" && t.T.i < 0;

// An elaborated term without the checker's annotations.
const bare = (t: LTerm): LTerm => {
  let u = t;
  while (isTyping(u)) {
    u = u.x;
  }
  return u;
};

// The type the checker gave an elaborated term, if it annotated it.
const typeOf = (t: LTerm): HTerm | undefined =>
  isTyping(t) && t.T.$ === "Var" ? t.T.v : undefined;

// The token of a scope's binder at `level`, if it has one.
const tokenAt = (scope: Scope, level: number): unknown => {
  let at = scope;
  while (at !== null && at.level !== level) {
    at = at.up;
  }
  return at?.token;
};

// What a scope has at each level, from 0 to `dep`: its binders' tokens or
// names.
const levels = <T>(scope: Scope, dep: number, of: (at: NonNullable<Scope>) => T): T[] => {
  const out: T[] = Array.from({ length: dep });
  const seen: boolean[] = Array.from({ length: dep }, () => false);
  for (let at = scope; at !== null; at = at.up) {
    if (at.level < dep && !seen[at.level]) {
      seen[at.level] = true;
      out[at.level] = of(at);
    }
  }
  return out;
};

// The deepest level a lowered type uses free (below `dep`), or -1.
const deepest = (t: LTerm, dep: number): number => {
  let max = -1;
  const stack: unknown[] = [t];
  while (stack.length > 0) {
    const x = stack.pop();
    if (Array.isArray(x)) {
      stack.push(...(x as unknown[]));
    } else if (typeof x === "object" && x !== null && "$" in x) {
      const u = x as Record<string, unknown>;
      if (u.$ === "Var" && typeof u.i === "number" && u.i >= 0 && u.i < dep) {
        max = Math.max(max, u.i);
      }
      Object.entries(u).forEach(([k, v]) => {
        if (k !== "s" && k !== "v") {
          stack.push(v);
        }
      });
    }
  }
  return max;
};

// Whether two types are the same: from one check, and equal by the checker,
// over the binders their scopes share. A type that uses a binder the other's
// scope does not have is not the same: its level names another variable.
const sameType = (Bend: Bend, a: Typed, b: Typed): boolean => {
  if (a.bok !== b.bok) {
    return false;
  }
  const dep = Math.min(a.dep, b.dep);
  const ta = a.scope === b.scope ? [] : levels(a.scope, dep, (at) => at.token);
  const tb = a.scope === b.scope ? [] : levels(b.scope, dep, (at) => at.token);
  let shared = a.scope === b.scope ? dep : 0;
  while (shared < dep && ta[shared] !== undefined && ta[shared] === tb[shared]) {
    shared++;
  }
  const inside = (t: Typed): boolean =>
    t.dep <= shared || deepest(Bend.term_lower(t.ty, t.dep), t.dep) < shared;
  try {
    return (
      inside(a) && inside(b) && Bend.term_compare("EQ", a.bok, a.ty, b.ty, Math.max(a.dep, b.dep))
    );
  } catch {
    return false;
  }
};

const judge = (judged: Map<number, Judged[]>, id: number, j: Judged): void => {
  const at = judged.get(id);
  if (at === undefined) {
    judged.set(id, [j]);
  } else {
    at.push(j);
  }
};

// The binder node a checked binder named `k` at span `s` is, if any.
const binderAt = (
  origins: Map<Span, Origin[]>,
  s: Span | undefined,
  k: string,
): Origin | undefined =>
  s === undefined ? undefined : origins.get(s)?.find((o) => BINDERS.has(o.kind) && o.name === k);

// The quantities of a telescope's domains.
const quantities = (Bend: Bend, T: HTerm): Quant[] => {
  const out: Quant[] = [];
  for (let t = T, i = 0; t.$ === "All"; t = t.B(Bend.Var(t.k, i)), i++) {
    out.push(t.q);
  }
  return out;
};

// The facts of each declaration's binders: each domain of its type's
// telescope is the type its binder declares, with its quantity. The type
// opens each binder in turn, so a domain is at the depth of its place.
const signature = (
  Bend: Bend,
  book: Book,
  T: HTerm,
  origins: Map<Span, Origin[]>,
  judged: Map<number, Judged[]>,
): void => {
  let scope: Scope = null;
  for (let t = T, i = 0; t.$ === "All"; t = t.B(Bend.Var(t.k, i)), i++) {
    const binder = binderAt(origins, t.s, t.k);
    if (binder !== undefined && t.s !== undefined) {
      judge(judged, binder.id, {
        role: "binder",
        ty: t.A,
        bok: book,
        dep: i,
        scope,
        qt: t.q,
        file: t.s.file,
      });
    }
    scope = { level: i, name: t.k, token: binder?.id ?? t, up: scope };
  }
};

// The facts of an elaborated body: each term the checker typed is a node's
// if it has the node's span object, kind and name, and, for a call or a
// constructor, the node's children; a variable must also name the node's
// binder. So a term the checker made from another (a pattern put for a
// scrutinee, a partial call, a list's tail) is no node's. A lambda's, let's
// or case's binder declares the type its function type gives it; a
// parameter's is its signature's, if its signature has it (a law's fill
// takes the law's). Each term's demand flows as the checker
// passes it: `quant_dem` of a domain's quantity for an argument, a field or a
// let value, erased for types.
const body = (
  Bend: Bend,
  book: Book,
  e: LTerm,
  origins: Map<Span, Origin[]>,
  binders: Map<string, number>,
  judged: Map<number, Judged[]>,
): void => {
  const erased = Bend.None();
  const telescopes = new Map<string, Quant[]>();
  const sameKids = (xs: LTerm[], o: Origin): boolean =>
    xs.length === o.kids.length && xs.every((x, j) => bare(x).s === o.kids[j]);
  // Whether `t` is the node `o`; `scope` binds its variables.
  const matches = (t: LTerm, o: Origin, scope: Scope): boolean => {
    if (o.kind !== SYNTAX[t.$]) {
      return false;
    }
    switch (t.$) {
      case "Var":
        return (
          o.name === t.k && o.binder !== undefined && binders.get(o.binder) === tokenAt(scope, t.i)
        );
      case "Ref":
        return o.target === t.k;
      case "Lit":
        return o.name === String(t.v);
      case "Lam":
      case "All":
        return o.name === t.k;
      case "Ctr":
      case "ADT":
        return o.target === t.k && sameKids(t.x, o);
      default:
        return true;
    }
  };
  // Whether a call, as its head and arguments, is the node `o`: they are its
  // children, but the leading ones a template's instance took as `~`
  // arguments.
  const call = (head: LTerm, args: LTerm[], o: Origin): boolean => {
    const skip = o.kids.length - 1 - args.length;
    return (
      o.kind === "Application" &&
      head.s === o.kids[0] &&
      (skip === 0 || (skip > 0 && head.$ === "Ref" && head.k.includes("~"))) &&
      args.every((x, j) => bare(x).s === o.kids[1 + skip + j])
    );
  };
  const record = (
    id: number,
    role: "term" | "binder",
    ty: HTerm,
    dep: number,
    scope: Scope,
    qt: Quant,
    file: Span["file"],
  ): void => judge(judged, id, { role, ty, bok: book, dep, scope, qt, file });
  // The binder node a checked binder is, recording the type it declares,
  // unless it is a parameter its signature declared.
  const binder = (
    s: Span | undefined,
    k: string,
    ty: HTerm | undefined,
    dep: number,
    scope: Scope,
    q: Quant,
  ): Origin | undefined => {
    const o = binderAt(origins, s, k);
    if (o !== undefined && s !== undefined && ty !== undefined) {
      if (o.kind !== "Parameter" || judged.get(o.id) === undefined) {
        record(o.id, "binder", ty, dep, scope, q, s.file);
      }
    }
    return o;
  };
  const pi = (ty: HTerm): HTerm => (ty.$ === "All" ? ty : Bend.term_wnf(book, ty));
  // The quantities of a type's or constructor's telescope, read once.
  const telescope = (k: string, T: HTerm | undefined): Quant[] => {
    const at = telescopes.get(k);
    if (at !== undefined) {
      return at;
    }
    const qs = T === undefined ? [] : quantities(Bend, T);
    telescopes.set(k, qs);
    return qs;
  };
  // The children of a term that binds nothing, each with its demand: a
  // field's or parameter's quantity under the term's, erased in a type.
  const descend = (t: LTerm, dep: number, scope: Scope, qt: Quant): void => {
    switch (t.$) {
      case "Ctr": {
        const qs = telescope(t.k, book.ctrs[t.k]?.T);
        const first = qs.length - t.x.length;
        t.x.forEach((x, j) => walk(x, dep, scope, Bend.quant_dem(qs[first + j] ?? erased, qt)));
        return;
      }
      case "ADT": {
        const qs = telescope(t.k, book.tlds[t.k]?.T);
        t.x.forEach((x, j) => walk(x, dep, scope, Bend.quant_dem(qs[j] ?? erased, qt)));
        return;
      }
      case "Typ":
        walk(t.g, dep, scope, erased);
        return;
      case "Min":
        walk(t.a, dep, scope, qt);
        walk(t.b, dep, scope, qt);
        return;
      case "Mat":
        walk(t.h, dep, scope, qt);
        walk(t.m, dep, scope, qt);
        return;
      case "Eql":
        walk(t.a, dep, scope, erased);
        walk(t.b, dep, scope, erased);
        walk(t.T, dep, scope, erased);
        return;
      case "Rwt":
        walk(t.e, dep, scope, qt);
        walk(t.p, dep, scope, erased);
        walk(t.f, dep, scope, qt);
        return;
      case "Ann":
        walk(t.x, dep, scope, qt);
        return;
      case "Sub":
        walk(t.f, dep, scope, qt);
        return;
      default:
        return;
    }
  };
  // A call: the applications that share its span object, outermost first,
  // are one; each argument's demand is its function's domain quantity under
  // the call's.
  const walkCall = (
    t: Extract<LTerm, { $: "App" }>,
    ty: HTerm | undefined,
    here: Origin[] | undefined,
    dep: number,
    scope: Scope,
    qt: Quant,
  ): void => {
    const args: LTerm[] = [];
    const fns: Array<HTerm | undefined> = [];
    let typed: LTerm = t;
    let head: LTerm = t;
    while (head.$ === "App" && head.s === t.s) {
      args.push(head.x);
      fns.push(typeOf(head.f));
      typed = head.f;
      head = bare(typed);
    }
    args.reverse();
    fns.reverse();
    here?.forEach((o) => {
      if (ty !== undefined && t.s !== undefined && call(head, args, o)) {
        record(o.id, "term", ty, dep, scope, qt, t.s.file);
      }
    });
    walk(typed, dep, scope, qt);
    args.forEach((x, j) => {
      const fn = fns[j];
      const f = qt.$ === "None" || fn === undefined ? undefined : pi(fn);
      walk(x, dep, scope, f?.$ === "All" ? Bend.quant_dem(f.q, qt) : qt);
    });
  };
  const walk = (u: LTerm, dep: number, scope: Scope, qt: Quant): void => {
    const ty = typeOf(u);
    const t = bare(u);
    const s = t.s;
    const here = s === undefined || ty === undefined ? undefined : origins.get(s);
    if (t.$ === "App") {
      walkCall(t, ty, here, dep, scope, qt);
      return;
    }
    here?.forEach((o) => {
      if (ty !== undefined && s !== undefined && matches(t, o, scope)) {
        record(o.id, "term", ty, dep, scope, qt, s.file);
      }
    });
    switch (t.$) {
      case "Lam": {
        const f = ty === undefined ? undefined : pi(ty);
        const declared = f?.$ === "All" ? f : undefined;
        const q = t.q?.$ === "Many" && declared?.q.$ === "Lone" ? t.q : declared?.q;
        const o = binder(s, t.k, declared?.A, t.i, scope, q ?? erased);
        walk(t.f, t.i + 1, { level: t.i, name: t.k, token: o?.id ?? t, up: scope }, qt);
        return;
      }
      case "Let": {
        let inner = scope;
        t.v.forEach((v, j) => {
          walk(v, dep, scope, Bend.quant_dem(t.q[j], qt));
          const o = binder(s, t.k[j], typeOf(v), dep, scope, t.q[j]);
          inner = { level: t.i[j], name: t.k[j], token: o?.id ?? v, up: inner };
        });
        walk(t.f, dep + t.k.length, inner, qt);
        return;
      }
      case "All": {
        walk(t.A, dep, scope, erased);
        const o = binderAt(origins, s, t.k);
        walk(t.B, t.i + 1, { level: t.i, name: t.k, token: o?.id ?? t, up: scope }, erased);
        return;
      }
      default:
        descend(t, dep, scope, qt);
    }
  };
  walk(e, 0, null, Bend.Lone());
};

// The checker's facts on the nodes of the files a check read: from each own
// declaration's type (its binders), then each def's elaborated body. Template
// instances (`k~n`) are other defs, so they are left out.
const factsOf = (
  Bend: Bend,
  book: Book,
  own: string[],
  origins: Map<Span, Origin[]>,
  binders: Map<string, number>,
): Map<number, Judged[]> => {
  const judged = new Map<number, Judged[]>();
  const tlds = [...new Set(own)].flatMap((k) => {
    const tld = book.tlds[k];
    return tld === undefined || k.includes("~") ? [] : [tld];
  });
  tlds.forEach((tld) => {
    signature(Bend, book, tld.T, origins, judged);
    if (tld.$ === "ADT") {
      tld.c.forEach((c) => signature(Bend, book, c.T, origins, judged));
    }
  });
  tlds.forEach((tld) => {
    if (tld.$ === "Def" && tld.e !== undefined) {
      body(Bend, book, tld.e, origins, binders, judged);
    }
  });
  return judged;
};

// A node's judgments, those the checker counts the same (same role and
// quantity, and the same type) once each: copies of one term, as pattern
// compilation makes them.
const distinct = (Bend: Bend, js: Judged[]): Judged[] =>
  js.length < 2
    ? js
    : js.reduce<Judged[]>((out, j) => {
        if (!out.some((u) => u.role === j.role && u.qt.$ === j.qt.$ && sameType(Bend, u, j))) {
          out.push(j);
        }
        return out;
      }, []);

// The records of the nodes numbered from `first`, each followed by its
// facts: each of its distinct judgments, with a new handle to its type in
// check `id`.
const nodesWithFacts = (
  Bend: Bend,
  nodes: string[],
  judged: Map<number, Judged[]>,
  first: number,
  id: number,
): string[] => {
  const out: string[] = [];
  const types = TYPES[id - 1];
  nodes.forEach((node, j) => {
    out.push(node);
    distinct(Bend, judged.get(first + j) ?? []).forEach(
      ({ role, ty, bok, dep, scope, qt, file }) => {
        types.push({ ty, bok, dep, scope, file });
        out.push(record(["fact", role, String(id), String(types.length - 1), QUANTITIES[qt.$]]));
      },
    );
  });
  return out;
};

// The answer to `check <path> <facts|syntax>`: each file the check parsed
// (path, namespace, text), then its syntax nodes, each followed, with facts,
// by the checker's facts on it; or, if the check failed, the files it read, then
// why. The probes are global, so checks must not overlap.
const check = async ({ Bend, base }: Checker, path: string, facts: boolean): Promise<string> => {
  const book = seeded(Bend, base);
  const seen = new Map<string, string | null>([[Bend.BASE_BEND, ""]]);
  const reported: Seen[] = [];
  const origins = new Map<Span, Origin[]>();
  const binders = new Map<string, number>();
  const hook = globalThis as { BEND_LINT_SEE?: (seen: Seen) => void };
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
        return [
          ...done,
          {
            file: parsed.file,
            nodes: nodeRecords(trees, first, origins, binders),
            first,
          },
        ];
      },
      [],
    );
    Bend.book_valid(book, base.order.length);
    const judged = facts
      ? factsOf(Bend, book, book.order.slice(base.order.length), origins, binders)
      : new Map<number, Judged[]>();
    TYPES.push([]);
    const id = TYPES.length;
    return sections
      .flatMap(({ file, nodes, first }) => [
        record(["file", file.real, file.ns, file.text]),
        ...nodesWithFacts(Bend, nodes, judged, first, id),
      ])
      .join("");
  } catch (e) {
    return [
      ...[...seen.keys()].filter((p) => p !== Bend.BASE_BEND).map((p) => record(["read", p])),
      record(["fail", isErr(e) ? Bend.err_show(e) : message(e)]),
    ].join("");
  } finally {
    hook.BEND_LINT_SEE = undefined;
  }
};

// A lowered type with each template parameter as written: the checker checks
// a template's body with `k~A`, in no book, for its parameter `A`
// (def_check).
const written = (t: LTerm, bok: Book): LTerm => {
  const go = (x: unknown): unknown => {
    if (Array.isArray(x)) {
      return x.map(go);
    }
    if (typeof x !== "object" || x === null || !("$" in x)) {
      return x;
    }
    const u = x as Record<string, unknown>;
    if (u.$ === "Ref" && typeof u.k === "string" && u.k.includes("~") && !(u.k in bok.tlds)) {
      return { ...u, k: u.k.slice(u.k.lastIndexOf("~") + 1) };
    }
    return Object.fromEntries(
      Object.entries(u).map(([k, v]) => [k, k === "s" || k === "v" ? v : go(v)]),
    );
  };
  return go(t) as LTerm;
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
    return record([
      "shown",
      Bend.term_show(
        written(Bend.term_lower(t.ty, t.dep), t.bok),
        -1,
        levels(t.scope, t.dep, (at) => at.name),
        t.file,
      ),
    ]);
  }
  if (op === "same") {
    const a = at(c, i);
    const b = at(d, j);
    return record(["same", String(sameType(Bend, a, b))]);
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

// A JS build of the program runs on this runtime; a native one, as itself.
const [command, commandArgs] = /\.m?js$/.test(program)
  ? [process.execPath, [program, ...args]]
  : [program, args];
const child = spawn(command, commandArgs, {
  env: { ...process.env, BEND_LINT_PORT: String((server.address() as net.AddressInfo).port) },
  stdio: "inherit",
});
const [code] = (await once(child, "exit")) as [number | null];
server.close();
process.exit(code ?? 1);
