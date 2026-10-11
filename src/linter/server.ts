#!/usr/bin/env bun
// The checker server: see the header of lint.bend. It runs a rules program
// (a build of a file that imports lint.bend), and answers its questions
// about Bend files over local TCP, until the program exits. It is all the
// TypeScript the linter runs on, host and probe, and it goes when Bend's
// checker is Bend, so any optimization is fair here, mutation included
// (AGENTS.md).
//
// Usage: bend-lint [--program <rules program>] <args...>
// The program is main.bend unless named. A .bend program is built with the
// `bend` on PATH, and the build is kept; an executable, or a .js or .mjs
// build, runs as it is. Node 24.2 or later runs a built program too, but
// Bend's checker can need more than its default heap: pass
// --max-old-space-size=8192 for a large program.
//
// It loads a copy of bend.ts in which each TRACED function reports its calls:
// Bend's parser reads a file with some, and the checker judges terms with the
// others. A file's syntax goes out as Bend's parser has it, before the
// checker lowers it. Facts are read after the check, from each def's
// elaborated body (`e`, what Bend compiles) and each declaration's type, with
// what the checker passed each judgment.
//
// Bootstrap: what a rule sees is lint.bend's contract, not Bend's. When
// Bend's checker is Bend, each field comes from what it gives, or bend-lint
// computes it. Bend has no private defs: whatever the checker computes, Bend
// code can import. The worst case is more code of ours, not a lost field.
//
// | What a rule sees               | Now, from                         | Risk   |
// | ------------------------------ | --------------------------------- | ------ |
// | spans, names, binders, targets | the parser                        | low    |
// | types: show, same, normal      | term_show, term_compare, term_snf | low    |
// | declarations and their uses    | program.bend, our own code        | none   |
// | syntax before lowering         | the parser's frames (KEPT)        | medium |
// | quantity, used                 | the judgments (JUDGED)            | high   |
// | which node a fact is on        | Span objects as Map keys          | medium |
//
// - Syntax before lowering: if Bend's parser builds no tree before it lowers,
//   bend-lint calls its parse functions itself, as KEPT follows them now.
// - Quantity and used: a checker in Bend cannot be hooked. It gives them, or
//   bend-lint computes them again, with a walker in Bend.
// - Which node a fact is on: Bend values have no identity, so a fact finds its
//   node by span value, kind, name and children. Sugar that shares a span is
//   then ambiguous.

// Imports
// =======

import { spawn } from "node:child_process";
import { once } from "node:events";
import * as nodeFs from "node:fs";
import * as net from "node:net";
import * as nodePath from "node:path";
import * as readline from "node:readline";
import * as url from "node:url";

import type {
  Ann,
  Body,
  Book,
  Check,
  Ctx,
  Err,
  HTerm,
  Infer,
  LTerm,
  Parse,
  Patt,
  Quant,
  Span,
} from "bend2/bend.ts";
import type * as BendModule from "bend2/bend.ts";

import { getBendLintCacheDir, tryGetBend2SourceUrl } from "../shared/bend2.ts";
import { unwrap } from "../shared/result.ts";
import {
  getLineIndexAtOffset,
  getLineStartOffsets,
  getTextWithEachEditAppliedOnce,
  getTextWithLfLineEnds,
} from "../shared/text.ts";
import {
  getCommandOutcome,
  getErrorMessageFromUnknown,
  getPathWithForwardSlashes,
  getSha256Hex,
  tryGetOrUndefined,
  writeFileAtomically,
} from "../shared/utils.ts";

// Types
// =====

type Bend = typeof BendModule;
type Cell = [Quant, string, number, LTerm, Span];

// Bend, and Base as checked once.
type Loaded = { Bend: Bend; base: Book };

// What a check's answer depends on besides its files (this server, the
// patched bend.ts and Base, as one digest), and Bend, loaded when a check or
// a question first needs it: an answer from the cache needs none.
type Checker = { version: string; loaded: () => Promise<Loaded> };

// A check's answer as the cache keeps it, with 0 for its number: the files it
// read, each with the digest of the text it read, and the answer's digest.
type Entry = { files: Array<[string, string]>; answer: string; digest: string };

// A check this server answered: its root, its mode, and its answer's digest,
// numbered 0. Enough to check it again with the same numbers.
type Answered = { path: string; facts: boolean; digest: string };

// An exact edit of bend.ts: the text it must find once, and its replacement.
type Edit = [string, string];

// A function of bend.ts, as a hook gets it.
type Traced = (...args: unknown[]) => unknown;

// What a TRACED function calls instead of itself: its original, and its
// arguments.
type Hook = (f: Traced, args: unknown[]) => unknown;

// What the server shares with its copy of bend.ts on globalThis: the fs and
// path the copy uses, and, once the copy loads, its setter of hooks.
type Shared = { fs: object; path: object; hook?: (name: string, hook?: Hook) => void };

// A traced call that a Frame KEPT: its name, arguments and result, where the
// parser is after it (-1 for a call without a parser), and the calls it made
// that it KEPT.
type Frame = { name: string; args: unknown[]; out: unknown; end: number; kids: Frame[] };

// A file the check parsed: its real path, its text on disk, the parser that
// read it (with its import lines blanked) if it read a declaration, its
// namespace and aliases, and the calls that loaded its imports and parsed
// its declarations.
type Parsed = {
  real: string;
  text: string;
  read?: Parse;
  ns: string;
  al: Record<string, string>;
  imports: Frame[];
  declarations: Frame[];
};

// What the checker passed a judgment, by the term it gave back: the demand
// on the term, its context and depth, and how often each binder it closed
// (by level) was used.
type Judgment = { qt: Quant; ctx: Ctx; dep: number; used: ReadonlyArray<[number, Quant]> };

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

// The binders around a checked term: the checker's context, and the id of
// the syntax node that writes each of its binders, by the binder's entry in
// a context. A binder no node writes is itself.
type Scope = { ctx: Ctx; ids: Map<unknown, number> };

// A type a rule holds a handle to: the type, the book, depth and binders of
// its scope, and the file whose spelling shows it.
type Typed = { ty: HTerm; bok: Book; dep: number; scope: Scope; file: Span["file"] };

// What the checker found of a node: the type of the term it is, or the type
// its binder declares, with the term's demand or the binder's quantity.
type Judged = Typed & { role: "term" | "binder"; qt: Quant };

// What the checker found of the nodes of a check: each node's judgments,
// and how often each binder node is used (the most of its checked copies).
type Found = { judged: Map<number, Judged[]>; used: Map<number, Quant> };

// What reading a check's facts uses: Bend, the book, the nodes each span
// object is, the binder nodes by key, what the checker passed each judgment,
// the node each binder's context entry is, and what it found so far.
type Reading = {
  Bend: Bend;
  book: Book;
  origins: Map<Span, Origin[]>;
  binders: Map<string, number>;
  judgments: Map<LTerm, Judgment>;
  ids: Map<unknown, number>;
  found: Found;
};

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

const ESCAPES: Record<string, string> = { "\\": "\\\\", "\t": "\\t", "\n": "\\n" };

const SERVER_CACHE_DIR = new URL("server/", getBendLintCacheDir());

// Where the cache keeps checks' answers.
const CHECKS_DIR = url.fileURLToPath(new URL("checks/", SERVER_CACHE_DIR));

// Where the cache keeps the rules programs it builds.
const PROGRAMS_DIR = url.fileURLToPath(new URL("programs/", SERVER_CACHE_DIR));

// The rules program that runs when the command line names none.
const MAIN = url.fileURLToPath(new URL("main.bend", import.meta.url));

// An import of a .bend file by a relative path.
const IMPORT = /^\s*import\s+(\.\.?\/\S+)/gm;

// A drive letter that starts a path with `/`.
const DRIVE = /^[A-Za-z]:(?=\/)/;

// The edits that make bend.ts use the fs and path the server Shares. The copy
// is never type-checked, so it needs no types.
const EDITS: Edit[] = [
  ['import * as fs from "node:fs";', "const { fs } = globalThis.BEND_LINT;"],
  ['import * as path from "node:path";', "const { path } = globalThis.BEND_LINT;"],
];

// The functions of bend.ts whose calls the server sees while Bend loads a
// check's files: those that load a file, parse what it declares and build a
// law's type.
const PARSED = [
  "book_load",
  "parse_book",
  "parse_def",
  "parse_fresh",
  "parse_reso",
  "parse_tele",
  "parse_term",
  "parse_body",
  "term_higher",
];

// The functions of bend.ts whose calls the server sees while Bend checks, for
// facts: those that judge a term and close a binder.
const JUDGED = ["term_infer", "term_check", "uses_close"] as const;

const TRACED = [...PARSED, ...JUDGED];

// The traced calls a Frame keeps, by the function that made them: a check
// loads a file, which loads its imports and parses its declarations, each
// with its name, binders, types and body.
const KEPT: Record<string, ReadonlySet<string> | undefined> = {
  check: new Set(["book_load"]),
  book_load: new Set(["book_load", "parse_book"]),
  parse_book: new Set(["parse_def", "parse_fresh", "parse_tele", "parse_term", "term_higher"]),
  parse_def: new Set(["parse_fresh", "parse_reso", "parse_tele", "parse_term", "parse_body"]),
};

const NONE: ReadonlySet<string> = new Set();

// The hook each TRACED function points at, by its name.
const HOOKED = new Map<string, Hook | undefined>();

// What bend.ts gets appended: a setter, Shared on globalThis, that points a
// TRACED function at a hook, or back at its original. A function a module
// declares is a binding the module can set, so each call in bend.ts goes
// through the hook, and a function without one runs as it is.
const PROBES = `
const BEND_LINT_ORIGINALS = { ${TRACED.join(", ")} };
globalThis.BEND_LINT.hook = (name, hook) => {
  switch (name) {
${TRACED.map(
  (name) => `    case "${name}":
      ${name} = hook === undefined ? BEND_LINT_ORIGINALS.${name} : (...args) => hook(BEND_LINT_ORIGINALS.${name}, args);
      return;`,
).join("\n")}
  }
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

// The checks answered, by number (from 1), and those whose types are gone:
// freed, or answered from the cache. A question about one checks it again.
const ANSWERED: Answered[] = [];
const GONE = new Set<number>();

// The number of each check answered from or to the cache, by its entry's
// path: the files of one entry share one check.
const NUMBERS = new Map<string, number>();

// What a check found without facts.
const NOTHING: Found = { judged: new Map(), used: new Map() };

// The uses of a judgment that closed no binder: one, shared.
const UNUSED: ReadonlyArray<[number, Quant]> = [];

// The binders a telescope declares, by its closing bracket.
const CELLS: Record<string, string> = { ")": "Parameter", ">": "Parameter", "}": "Field" };

// What makes an input of `files` a glob.
const GLOB = /[*?[{]/;

// How long a cached check or build stays unused before the cache deletes it:
// a week, in milliseconds.
const STALE = 7 * 24 * 60 * 60 * 1000;

// How old a kept build gets before a run that uses it marks it as used again:
// a day, in milliseconds. Touching an executable makes a virus scanner check
// it again before it runs (about 0.2 s on Windows), so not on every run.
const USED = 24 * 60 * 60 * 1000;

// Functions
// =========

const field = (text: string): string => text.replace(/[\\\t\n]/g, (c) => ESCAPES[c]);

const unfield = (text: string): string =>
  text.replace(/\\(.)/g, (_, c: string) => (c === "t" ? "\t" : c === "n" ? "\n" : c));

const record = (fields: string[]): string => fields.map(field).join("\t") + "\n";

const isErr = (e: unknown): e is Err =>
  typeof e === "object" && e !== null && (e as { $?: unknown }).$ === "Err";

// A fresh book that holds Base, as main.ts's book_seed makes it.
const seeded = (Bend: Bend, base: Book): Book => ({
  ...Bend.book_nil(),
  tlds: Object.fromEntries(Object.entries(base.tlds).map(([k, tld]) => [k, { ...tld }])),
  ctrs: { ...base.ctrs },
  order: [...base.order],
  tmps: Object.fromEntries(Object.entries(base.tmps).map(([k, m]) => [k, new Map(m)])),
});

const drift = (text: string): Error =>
  Object.assign(new Error(text + "; update EDITS or TRACED in src/linter/server.ts"), {
    name: "DriftError",
  });

// bend.ts with EDITS made and PROBES appended, and BEND_DIR kept at `dir`, so
// the copy finds base.bend where the original does: `true ? dir :` puts
// Bend's own expression in a branch that never runs. Each TRACED function must
// be declared once. Line ends become LF first.
const patched = (dir: string, src: string): string =>
  getTextWithEachEditAppliedOnce(
    getTextWithLfLineEnds(src),
    [
      ...EDITS,
      ...TRACED.map((name): Edit => [`function ${name}(`, `function ${name}(`]),
      ["export const BEND_DIR = ", `export const BEND_DIR = true ? ${JSON.stringify(dir)} : `],
    ],
    (at, n) => {
      throw drift(`bend.ts has ${n} of ${JSON.stringify(at)}, not 1`);
    },
  ) + PROBES;

// The patched copy of the bend.ts in `dir`, written once to the cache.
const copied = (dir: URL): URL => {
  const text = patched(
    getPathWithForwardSlashes(url.fileURLToPath(dir)),
    nodeFs.readFileSync(new URL("bend.ts", dir), "utf8"),
  );
  const file = new URL(`${getSha256Hex(text).slice(0, 16)}/bend.ts`, SERVER_CACHE_DIR);
  if (!nodeFs.existsSync(file)) {
    nodeFs.mkdirSync(new URL(".", file), { recursive: true });
    nodeFs.writeFileSync(file, text);
  }
  return file;
};

// The real path of `p`, with `/`.
const realpath = (p: nodeFs.PathLike): string => getPathWithForwardSlashes(nodeFs.realpathSync(p));

// path.posix.resolve from `cwd`, where a drive letter is a root.
const resolvePosix = (cwd: string, ...ps: string[]): string => {
  const all = [cwd, ...ps].map(getPathWithForwardSlashes);
  const drive =
    all
      .filter((p) => DRIVE.test(p))
      .at(-1)
      ?.slice(0, 2) ?? "";
  return drive + nodePath.posix.resolve(...all.map((p) => p.replace(DRIVE, "")));
};

const relativePosix = (from: string, to: string): string =>
  nodePath.posix.relative(
    getPathWithForwardSlashes(from).replace(DRIVE, ""),
    getPathWithForwardSlashes(to).replace(DRIVE, ""),
  );

// What the server Shares with its copy of bend.ts: Node's fs and path, with
// each path they give real and with `/`, as Bend resolves imports with
// path.posix, where a drive letter is a root.
const shared = (): Shared => ({
  fs: { ...nodeFs, realpathSync: realpath },
  path: {
    ...nodePath,
    join: (...ps: string[]): string => getPathWithForwardSlashes(nodePath.join(...ps)),
    resolve: (...ps: string[]): string => getPathWithForwardSlashes(nodePath.resolve(...ps)),
    posix: {
      ...nodePath.posix,
      resolve: (...ps: string[]): string => resolvePosix(process.cwd(), ...ps),
      relative: relativePosix,
    },
  },
});

// The checker of the bend2 sources in `dir`. The patched bend.ts is written
// now, so a drift stops the run at once; Bend loads, and checks Base, once,
// when first needed.
const load = (dir: URL): Checker => {
  const bend = copied(dir);
  let loading: Promise<Loaded> | undefined;
  const loaded = (): Promise<Loaded> => {
    loading ??= (async () => {
      (globalThis as { BEND_LINT?: Shared }).BEND_LINT = shared();
      const Bend = (await import(bend.href)) as Bend;
      const base = Bend.book_nil();
      await Bend.book_load(base, Bend.BASE_BEND, "", new Map());
      Bend.book_valid(base, 0);
      return { Bend, base };
    })();
    return loading;
  };
  const version = getSha256Hex(
    [
      nodeFs.readFileSync(url.fileURLToPath(import.meta.url), "utf8"),
      bend.href,
      nodeFs.readFileSync(new URL("base.bend", dir), "utf8"),
    ].join("\n"),
  );
  return { version, loaded };
};

// A disk offset of `text` (UTF-16 units) in code points, as Bend counts.
const pointsOf = (text: string): ((off: number) => number) =>
  /[\uD800-\uDFFF]/.test(text)
    ? (off) => text.slice(0, off).match(/./gsu)?.length ?? 0
    : (off) => off;

// A span of what the parser `read` of a file's `text` as a Range on disk. The
// parser reads the file with its import lines blanked, so a span moves by
// line.
const placerOf = (
  text: string,
  read: Span["file"] | undefined,
): ((s: Span | undefined) => Range | undefined) => {
  const disk = getLineStartOffsets(text);
  const lines = getLineStartOffsets(read?.str ?? text);
  const points = pointsOf(text);
  const at = (off: number): number => {
    const line = getLineIndexAtOffset(lines, off);
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

// The trees of a term, a body and a pattern, as the parser read them. A
// node has a range only where the source spells it: the parser makes terms
// of its own from other syntax (a do-block's binds, `A & B`), at the span of
// what it made them from, and copies some (a do-block's type into each
// statement). Those keep their kind and target, but no range or name.
const syntaxOf = (place: (s: Span | undefined) => Range | undefined) => {
  const range = (s: Span | undefined): Partial<Tree> => ({ range: place(s) });
  // The name a span starts with, if any.
  const spelled = (s: Span | undefined): string | undefined => {
    const name = /[A-Za-z_][\w.]*/y;
    name.lastIndex = s?.beg ?? 0;
    return s === undefined ? undefined : (name.exec(s.file.str)?.[0] ?? undefined);
  };
  // A use's name as written: the name its span starts with, if any.
  const used = (k: string, s: Span | undefined): Partial<Tree> => ({
    target: k,
    name: spelled(s) ?? "",
    ...range(s),
  });
  const last = (k: string): string => k.slice(Math.max(k.lastIndexOf("."), k.lastIndexOf(":")) + 1);
  // The spans a written reference owns: a copy of one is the parser's.
  const owned = new Set<Span>();
  // A reference to `k`, written at `s` if `s` spells it (a name of `k`, or an
  // operator) and no reference owns `s` yet.
  const reference = (k: string, s: Span | undefined): Tree => {
    const name = spelled(s);
    if (s === undefined || owned.has(s) || (name !== undefined && last(name) !== last(k))) {
      return tree("Reference", [], { target: k });
    }
    owned.add(s);
    return tree("Reference", [], {
      target: k,
      name: name ?? s.file.str.slice(s.beg, s.end),
      ...range(s),
    });
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
        : reference(t.v.$ === "Ref" ? t.v.k : "", t.s),
    Ref: (t) => reference(t.k, t.s),
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
        ...(spelled(t.s) === t.k ? range(t.s) : {}),
      }),
    // A call whose head shares its span is sugar: written (`A & B`,
    // `return x`) if it spans its written parts and no other part shares its
    // span; else the parser's (a do-block's bind).
    App: (t) => {
      const [head, args] = calls(t);
      const kids = args.map(term);
      const at = place(t.s);
      const spans = (k: Tree): boolean =>
        k.origin !== t.s &&
        (k.range === undefined || (at !== undefined && k.range[0] >= at[0] && k.range[1] <= at[1]));
      const written = head.s !== t.s || kids.every(spans);
      return tree("Application", [term(head), ...kids], written ? { range: at } : {});
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
// signature and body; a constructor under its type. A declaration starts at a
// `def`, or at a fresh name: a constructor's (in the book's constructors), a
// type's or a law's (by what the book holds). A law's signature is the type
// Bend builds from its clauses, last.
const declarationsOf = (book: Book, parsed: Parsed): Tree[] => {
  const place = placerOf(parsed.text, parsed.read);
  const { term, body } = syntaxOf(place);
  const cells = ({ args, out }: Frame): Tree[] => {
    const [, close, tk = []] = args as Parameters<Bend["parse_tele"]>;
    return (out as Cell[]).map(([q, k, i, T, s]) =>
      tree(CELLS[close], [term(T)], {
        name: k,
        binder: String(i),
        quantity: tk.includes(k) ? "Template" : QUANTITIES[q.$],
        range: place(s),
        origin: s,
      }),
    );
  };
  const under = (f: Frame): Tree[] =>
    f.name === "parse_tele"
      ? cells(f)
      : f.name === "parse_term"
        ? [tree("Returns", [term(f.out as LTerm)])]
        : f.name === "parse_body"
          ? [tree("Body", [body(f.out as Body)])]
          : [];
  const all = parsed.declarations;
  const heads = all.flatMap((f, at) => {
    const head =
      f.name === "parse_def"
        ? f.kids.filter((k) => k.name === "parse_fresh" || k.name === "parse_reso").at(-1)
        : f.name === "parse_fresh"
          ? f
          : undefined;
    return head === undefined ? [] : [{ f, head, at }];
  });
  const declared = heads.map(({ f, head, at }, j) => {
    const [p, name, table] = head.args as Parameters<Bend["parse_fresh"]>;
    const k = head.out as string;
    const tld = book.tlds[k];
    const kind =
      f.name === "parse_def"
        ? "Definition"
        : table === book.ctrs
          ? "Constructor"
          : tld?.$ === "ADT"
            ? "Datatype"
            : "Law";
    const group =
      f.name === "parse_def" ? f.kids : all.slice(at + 1, heads[j + 1]?.at ?? all.length);
    const kids =
      kind === "Law"
        ? group
            .filter((g) => g.name === "term_higher")
            .slice(-1)
            .map((g) => tree("Returns", [term(g.args[0] as LTerm)]))
        : group.flatMap(under);
    return tree(kind, kids, {
      name,
      target: k,
      range: place({ file: p, beg: head.end - name.length, end: head.end }),
    });
  });
  const tops = declared.flatMap((d, i) => (d.kind === "Constructor" ? [] : [i]));
  return tops.map((i, j) => ({
    ...declared[i],
    kids: [...declared[i].kids, ...declared.slice(i + 1, tops[j + 1] ?? declared.length)],
  }));
};

// The trees of a file's imports: each alias (or Base) and the file it loads,
// with the path it writes (Base writes none). An import's span is where its
// path is written; its alias is the next of the file's aliases, as Bend adds
// one per import of a file.
const importsOf = (parsed: Parsed, base: string): Tree[] => {
  const points = pointsOf(parsed.text);
  const aliases = Object.keys(parsed.al);
  const aliased = parsed.imports.filter((f) => f.args[1] !== base);
  return parsed.imports.map((f) => {
    const [, file, , , spn] = f.args as Parameters<Bend["book_load"]>;
    const from = spn?.beg ?? 0;
    const word = /\S+/y;
    word.lastIndex = from;
    const path = word.exec(parsed.text)?.[0] ?? "";
    const alias = file === base ? undefined : aliases[aliased.indexOf(f)];
    const beg = alias === undefined ? from : parsed.text.indexOf(alias, from + path.length);
    const name = alias ?? "Base";
    const written =
      alias === undefined
        ? []
        : [
            tree("ImportPath", [], {
              name: path,
              range: [points(from), points(from + path.length)],
            }),
          ];
    return tree("Import", written, {
      name,
      target: file,
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

// The files that the book_load calls in `frames` parsed, in the order Bend
// parsed them: a file's imports first. Bend reads a file without imports as
// it is on disk; else its imports' spans hold its text.
const parsedOf = (frames: Frame[]): Parsed[] =>
  frames.flatMap((f) => {
    const imports = f.kids.filter((k) => k.name === "book_load");
    const book = f.kids.find((k) => k.name === "parse_book");
    if (book === undefined) {
      return parsedOf(imports);
    }
    const [, , read, ns, al] = book.args as Parameters<Bend["parse_book"]>;
    const spn = (imports[0]?.args as Parameters<Bend["book_load"]> | undefined)?.[4];
    return [
      ...parsedOf(imports),
      {
        real: realpath(f.args[1] as string),
        text: spn?.file.str ?? read,
        read: book.kids[0]?.args[0] as Parse | undefined,
        ns,
        al,
        imports,
        declarations: book.kids,
      },
    ];
  });

// Points the TRACED function `name` at `hook`, or back at its original. A
// binding bend.ts sets is code JSC compiles again, so one that would not
// change is left alone.
const setHook = (name: string, hook?: Hook): void => {
  if (HOOKED.get(name) !== hook) {
    HOOKED.set(name, hook);
    (globalThis as { BEND_LINT?: Shared }).BEND_LINT?.hook?.(name, hook);
  }
};

// Points each TRACED function back at its original.
const untrace = (): void => {
  TRACED.forEach((name) => setHook(name));
};

// While Bend loads a check's files: keeps under `root` each call a Frame
// KEPT. Only the calls the Frame on top keeps are hooked, so every other call
// runs as it is: the stack sets the hooks as it grows and shrinks.
const traceParsing = (root: Frame): void => {
  const stack = [root];
  let hooked = NONE;
  const focus = (): void => {
    const keeps = KEPT[stack[stack.length - 1].name] ?? NONE;
    PARSED.forEach((name) => {
      if (hooked.has(name) !== keeps.has(name)) {
        setHook(name, keeps.has(name) ? (f, args) => kept(name, f, args) : undefined);
      }
    });
    hooked = keeps;
  };
  const kept = (name: string, f: Traced, args: unknown[]): unknown => {
    const p = args[0] as { pos?: number };
    const frame: Frame = { name, args, out: undefined, end: -1, kids: [] };
    const done = (out: unknown): unknown => {
      frame.out = out;
      frame.end = p.pos ?? -1;
      stack.pop();
      focus();
      return out;
    };
    const fail = (e: unknown): never => {
      stack.pop();
      focus();
      throw e;
    };
    stack[stack.length - 1].kids.push(frame);
    stack.push(frame);
    focus();
    try {
      const out = f(...args);
      return out instanceof Promise ? out.then(done, fail) : done(out);
    } catch (e) {
      return fail(e);
    }
  };
  focus();
};

// While Bend checks: keeps in `judgments` what the checker passes each
// judgment. A binder's uses are those its judgment closed, after the
// judgments inside it took theirs. A judgment can give back the term of one
// inside it (an annotation's, say): the inner one made it, so it keeps it.
const traceJudgments = (Bend: Bend, judgments: Map<LTerm, Judgment>): void => {
  const closed: Array<[number, Quant]> = [];
  const judge = (f: Traced, args: unknown[], qt: Quant, ctx: Ctx, dep: number): unknown => {
    const mark = closed.length;
    try {
      const judged = f(...args) as Infer | Check;
      const used = closed.length === mark ? UNUSED : closed.slice(mark);
      if (!judgments.has(judged.tm)) {
        judgments.set(judged.tm, { qt, ctx, dep, used });
      }
      return judged;
    } finally {
      closed.length = mark;
    }
  };
  const hooks: Record<(typeof JUDGED)[number], Hook> = {
    term_infer: (f, args) => {
      const [, , , qt, ctx, dep] = args as Parameters<Bend["term_infer"]>;
      return judge(f, args, qt, ctx, dep);
    },
    term_check: (f, args) => {
      const [, , , qt, , ctx, dep] = args as Parameters<Bend["term_check"]>;
      return judge(f, args, qt, ctx, dep);
    },
    uses_close: (f, args) => {
      const [, , us, i] = args as Parameters<Bend["uses_close"]>;
      closed.push([i, Bend.pmap_get(us, i) ?? Bend.None()]);
      return f(...args);
    },
  };
  JUDGED.forEach((name) => setHook(name, hooks[name]));
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

// What a scope has at each level, from 0 to `dep`: what `of` makes of each
// binder's entry in its context.
const levels = <T>(Bend: Bend, scope: Scope, dep: number, of: (entry: Ann) => T): T[] =>
  Array.from({ length: dep }, (_, level) => {
    const entry = Bend.pmap_get(scope.ctx, level);
    return entry === null ? undefined : of(entry);
  }) as T[];

// The token of a binder's entry in a scope: the id of the node that writes
// the binder, or the entry itself.
const tokenOf = (scope: Scope, entry: Ann): unknown => scope.ids.get(entry) ?? entry;

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
  const ta = levels(Bend, a.scope, dep, (entry) => tokenOf(a.scope, entry));
  const tb = levels(Bend, b.scope, dep, (entry) => tokenOf(b.scope, entry));
  let shared = 0;
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

// The facts of each declaration's binders: each domain of its type's
// telescope is the type its binder declares, with its quantity. The type
// opens each binder in turn, so a domain is at the depth of its place.
const signature = ({ Bend, book, origins, ids, found }: Reading, T: HTerm): void => {
  let ctx = Bend.ctx_nil();
  for (let t = T, i = 0; t.$ === "All"; t = t.B(Bend.Var(t.k, i)), i++) {
    const binder = binderAt(origins, t.s, t.k);
    if (binder !== undefined && t.s !== undefined) {
      judge(found.judged, binder.id, {
        role: "binder",
        ty: t.A,
        bok: book,
        dep: i,
        scope: { ctx, ids },
        qt: t.q,
        file: t.s.file,
      });
    }
    ctx = Bend.ctx_bind(ctx, i, t.q, t.k, t.A);
    const entry = Bend.pmap_get(ctx, i);
    if (binder !== undefined && entry !== null) {
      ids.set(entry, binder.id);
    }
  }
};

// Whether `x` is a term, not a quantity, a pattern or a span.
const isTerm = (x: unknown): x is LTerm =>
  typeof x === "object" && x !== null && String((x as { $?: unknown }).$) in SYNTAX;

// The terms right under an elaborated term, in order: none under a variable
// (a value it has is a substitution's), and only the term an annotation
// annotates.
const kids = (t: LTerm): LTerm[] =>
  t.$ === "Var"
    ? []
    : t.$ === "Ann"
      ? [t.x]
      : Object.values(t).flatMap((v: unknown) =>
          Array.isArray(v) ? v.filter(isTerm) : isTerm(v) ? [v] : [],
        );

// The facts of an elaborated body: each term the checker typed is a node's
// if it has the node's span object, kind and name, and, for a call or a
// constructor, the node's children; a variable must also name the node's
// binder. So a term the checker made from another (a pattern put for a
// scrutinee, a partial call, a list's tail) is no node's. A fact has the
// demand, context and depth the checker judged its term with. A lambda's or
// let's binder declares the type and quantity its entry in the context of
// its body has, unless it is a parameter its signature declared (a law's
// fill takes the law's); it is used as often as its judgment closed it.
const body = (r: Reading, e: LTerm): void => {
  const { Bend, book, origins, binders, judgments, ids, found } = r;
  // The judgment of an elaborated term: its outermost annotation's that a
  // traced call returned.
  const judgmentOf = (u: LTerm): Judgment | undefined =>
    judgments.get(u) ?? (isTyping(u) ? judgmentOf(u.x) : undefined);
  const sameKids = (xs: LTerm[], o: Origin): boolean =>
    xs.length === o.kids.length && xs.every((x, j) => bare(x).s === o.kids[j]);
  // Whether a term of a kind, judged `j`, is a node `o` of its syntax; any
  // node of its syntax is a term of a kind left out.
  const fits: {
    [K in LTerm["$"]]?: (t: Extract<LTerm, { $: K }>, o: Origin, j: Judgment) => boolean;
  } = {
    Var: (t, o, j) => {
      const entry = Bend.pmap_get(j.ctx, t.i);
      const token = entry === null ? undefined : tokenOf({ ctx: j.ctx, ids }, entry);
      return o.name === t.k && o.binder !== undefined && binders.get(o.binder) === token;
    },
    Ref: (t, o) => o.target === t.k,
    Lit: (t, o) => o.name === String(t.v),
    Lam: (t, o) => o.name === t.k,
    All: (t, o) => o.name === t.k,
    Ctr: (t, o) => o.target === t.k && sameKids(t.x, o),
    ADT: (t, o) => o.target === t.k && sameKids(t.x, o),
  };
  const matches = (t: LTerm, o: Origin, j: Judgment): boolean => {
    const fit = (
      fits as Record<string, ((t: LTerm, o: Origin, j: Judgment) => boolean) | undefined>
    )[t.$];
    return o.kind === SYNTAX[t.$] && (fit === undefined || fit(t, o, j));
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
    qt: Quant,
    j: Judgment,
    file: Span["file"],
  ): void =>
    judge(found.judged, id, {
      role,
      ty,
      bok: book,
      dep: j.dep,
      scope: { ctx: j.ctx, ids },
      qt,
      file,
    });
  // The binder nodes of the binders a lambda, let or forall at `s` declares at
  // `levels`, each with its entry in the context of its body, judged `inner`.
  // Each node is its binder's token from now on.
  const named = (
    s: Span | undefined,
    names: string[],
    levels: number[],
    inner: Judgment | undefined,
  ): Array<[Origin, Ann, number]> =>
    levels.flatMap((level, n): Array<[Origin, Ann, number]> => {
      const o = binderAt(origins, s, names[n]);
      const entry = inner === undefined ? null : Bend.pmap_get(inner.ctx, level);
      if (o === undefined || entry === null) {
        return [];
      }
      ids.set(entry, o.id);
      return [[o, entry, level]];
    });
  // The facts of the binders a lambda or let at `s`, judged `j`, declares.
  const declare = (
    s: Span | undefined,
    names: string[],
    levels: number[],
    j: Judgment | undefined,
    inner: Judgment | undefined,
  ): void =>
    named(s, names, levels, inner).forEach(([o, entry, level]) => {
      if (j === undefined || s === undefined) {
        return;
      }
      if (o.kind !== "Parameter" || !found.judged.has(o.id)) {
        record(o.id, "binder", entry.T, entry.q, j, s.file);
      }
      const used = j.used.find(([l]) => l === level)?.[1];
      const was = found.used.get(o.id);
      if (used !== undefined) {
        found.used.set(o.id, was === undefined ? used : Bend.quant_join(was, used));
      }
    });
  // A call: the applications that share its span object, outermost first,
  // are one.
  const walkCall = (
    t: Extract<LTerm, { $: "App" }>,
    ty: HTerm | undefined,
    j: Judgment | undefined,
    here: Origin[] | undefined,
  ): void => {
    const args: LTerm[] = [];
    let typed: LTerm = t;
    let head: LTerm = t;
    while (head.$ === "App" && head.s === t.s) {
      args.push(head.x);
      typed = head.f;
      head = bare(typed);
    }
    args.reverse();
    here?.forEach((o) => {
      if (ty !== undefined && j !== undefined && t.s !== undefined && call(head, args, o)) {
        record(o.id, "term", ty, j.qt, j, t.s.file);
      }
    });
    walk(typed, j);
    args.forEach((x) => walk(x, j));
  };
  // A term, with the judgment `up` of the term above it, which a term the
  // checker annotated without a traced call has (a match's absurd case).
  const walk = (u: LTerm, up?: Judgment): void => {
    const ty = typeOf(u);
    const j = judgmentOf(u) ?? up;
    const t = bare(u);
    const s = t.s;
    const here = s === undefined || ty === undefined ? undefined : origins.get(s);
    if (t.$ === "App") {
      walkCall(t, ty, j, here);
      return;
    }
    here?.forEach((o) => {
      if (ty !== undefined && j !== undefined && s !== undefined && matches(t, o, j)) {
        record(o.id, "term", ty, j.qt, j, s.file);
      }
    });
    if (t.$ === "Lam") {
      declare(s, [t.k], [t.i], j, judgmentOf(t.f));
    } else if (t.$ === "Let") {
      declare(s, t.k, t.i, j, judgmentOf(t.f));
    } else if (t.$ === "All") {
      named(s, [t.k], [t.i], judgmentOf(t.B));
    }
    kids(t).forEach((x) => walk(x, j));
  };
  walk(e);
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
  judgments: Map<LTerm, Judgment>,
): Found => {
  const r: Reading = {
    Bend,
    book,
    origins,
    binders,
    judgments,
    ids: new Map(),
    found: { judged: new Map(), used: new Map() },
  };
  const tlds = [...new Set(own)].flatMap((k) => {
    const tld = book.tlds[k];
    return tld === undefined || k.includes("~") ? [] : [tld];
  });
  tlds.forEach((tld) => {
    signature(r, tld.T);
    if (tld.$ === "ADT") {
      tld.c.forEach((c) => signature(r, c.T));
    }
  });
  tlds.forEach((tld) => {
    if (tld.$ === "Def" && tld.e !== undefined) {
      body(r, tld.e);
    }
  });
  return r.found;
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
// check `id`, and, for a binder the checker closed, how often it is used.
const nodesWithFacts = (
  Bend: Bend,
  nodes: string[],
  found: Found,
  first: number,
  id: number,
): string[] => {
  const out: string[] = [];
  const types = TYPES[id - 1];
  nodes.forEach((node, j) => {
    const used = found.used.get(first + j);
    out.push(node);
    distinct(Bend, found.judged.get(first + j) ?? []).forEach(
      ({ role, ty, bok, dep, scope, qt, file }) => {
        types.push({ ty, bok, dep, scope, file });
        out.push(
          record([
            "fact",
            role,
            String(id),
            String(types.length - 1),
            QUANTITIES[qt.$],
            role === "binder" && used !== undefined ? QUANTITIES[used.$] : "",
          ]),
        );
      },
    );
  });
  return out;
};

// Where a failed check's error is, if Bend's error says: its file's real
// path and text, and its range there. A load that fails is in the last file
// it opened and did not finish; a later failure, in a file it parsed.
const located = (
  e: unknown,
  seen: Map<string, string | null>,
  files: Parsed[],
): { path: string; text: string; range: Range } | undefined => {
  const s = isErr(e) ? e.spn : undefined;
  if (s === undefined) {
    return undefined;
  }
  const file = files.find((f) => f.read === s.file);
  const path = file?.real ?? [...seen].filter(([, ns]) => ns === null).pop()?.[0];
  if (path === undefined) {
    return undefined;
  }
  const text = file?.text ?? nodeFs.readFileSync(path, "utf8");
  const range = placerOf(text, s.file)(s);
  return range === undefined ? undefined : { path, text, range };
};

// Bend's message for a failed check, without its location if the finding is
// `placed` there.
const failure = (Bend: Bend, e: unknown, placed: boolean): string => {
  if (!isErr(e)) {
    return getErrorMessageFromUnknown(e);
  }
  const shown = Bend.err_show(e);
  const at = shown.indexOf("\nLocation:");
  return !placed || at < 0 ? shown : shown.slice(0, at) + (e.nte === undefined ? "" : "\n" + e.nte);
};

// The answer to `check <path> <facts|syntax>`: the check's number (for
// `ask` and `forget`), then each file it parsed (path, namespace, text),
// then its syntax nodes, each followed, with facts, by the checker's facts on
// it; or, if the check failed, the files it parsed with their nodes (if it
// got that far), the files it read, then why, and, if Bend's error says,
// where: the file's path, the range, and the file's text. A passed check
// also gives the files it read, with the text it read; its number is
// `number`, or the next. The hooks are global, so checks must not overlap.
const check = async (
  checker: Checker,
  path: string,
  facts: boolean,
  number?: number,
): Promise<{ answer: string; read?: Array<[string, string]>; number?: number }> => {
  const { Bend, base } = await checker.loaded();
  const book = seeded(Bend, base);
  const seen = new Map<string, string | null>([[Bend.BASE_BEND, ""]]);
  const root: Frame = { name: "check", args: [], out: undefined, end: -1, kids: [] };
  const judgments = facts ? new Map<LTerm, Judgment>() : undefined;
  const origins = new Map<Span, Origin[]>();
  const binders = new Map<string, number>();
  let syntax: string[] = [];
  traceParsing(root);
  try {
    await Bend.book_load(book, getPathWithForwardSlashes(nodePath.resolve(path)), "", seen);
    untrace();
    const files = parsedOf(root.kids);
    const sections = files.reduce<Array<{ file: Parsed; nodes: string[]; first: number }>>(
      (done, file) => {
        const first = 1 + done.reduce((n, d) => n + d.nodes.length, 0);
        const trees = [...importsOf(file, Bend.BASE_BEND), ...declarationsOf(book, file)];
        return [...done, { file, nodes: nodeRecords(trees, first, origins, binders), first }];
      },
      [],
    );
    syntax = sections.flatMap(({ file, nodes }) => [
      record(["file", file.real, file.ns, file.text]),
      ...nodes,
    ]);
    if (judgments !== undefined) {
      traceJudgments(Bend, judgments);
    }
    Bend.book_valid(book, base.order.length);
    untrace();
    const found =
      judgments === undefined
        ? NOTHING
        : factsOf(Bend, book, book.order.slice(base.order.length), origins, binders, judgments);
    const id = number ?? TYPES.push([]);
    TYPES[id - 1] = [];
    return {
      answer: [
        record(["check", String(id)]),
        ...sections.flatMap(({ file, nodes, first }) => [
          record(["file", file.real, file.ns, file.text]),
          ...nodesWithFacts(Bend, nodes, found, first, id),
        ]),
      ].join(""),
      read: files.map((file): [string, string] => [file.real, file.text]),
      number: id,
    };
  } catch (e) {
    const at = located(e, seen, parsedOf(root.kids));
    return {
      answer: [
        ...syntax,
        ...[...seen.keys()].filter((p) => p !== Bend.BASE_BEND).map((p) => record(["read", p])),
        record([
          "fail",
          failure(Bend, e, at !== undefined),
          ...(at === undefined ? [] : [at.path, String(at.range[0]), String(at.range[1]), at.text]),
        ]),
      ].join(""),
    };
  } finally {
    untrace();
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
const question = ({ Bend }: Loaded, q: string): string => {
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
        levels(Bend, t.scope, t.dep, (entry) => entry.k),
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

// An answer with `number` as its check's number: in its `check` record and
// in each `fact` record.
const numbered = (answer: string, number: number): string =>
  answer
    .replace(/^(check\t)\d+$/m, "$1" + number)
    .replace(/^(fact\t\w+\t)\d+\t/gm, "$1" + number + "\t");

// Where the cache keeps the check of `path` in mode `facts`.
const entryOf = ({ version }: Checker, path: string, facts: boolean): string =>
  nodePath.join(
    CHECKS_DIR,
    getSha256Hex([version, facts ? "facts" : "syntax", path].join("\n")) + ".json",
  );

// The cached answer at `file`, if each file it read still has the text it
// read. A hit marks the entry used now.
const cached = (file: string): Entry | undefined =>
  tryGetOrUndefined(() => {
    const entry = JSON.parse(nodeFs.readFileSync(file, "utf8")) as Entry;
    if (!entry.files.every(([p, d]) => getSha256Hex(nodeFs.readFileSync(p, "utf8")) === d)) {
      return undefined;
    }
    nodeFs.utimesSync(file, new Date(), new Date());
    return entry;
  });

// Deletes the entries of the cache folder `dir` unused for longer than
// STALE; one that another run deletes first is skipped. A folder that cannot
// be read keeps its entries.
const prune = (dir: string): void => {
  tryGetOrUndefined(() =>
    nodeFs
      .readdirSync(dir)
      .map((name) => nodePath.join(dir, name))
      .filter(
        (old) =>
          Date.now() - (nodeFs.statSync(old, { throwIfNoEntry: false })?.mtimeMs ?? Date.now()) >
          STALE,
      )
      .forEach((old) => nodeFs.rmSync(old, { force: true })),
  );
};

// The .bend file at `file` and every .bend file it imports by a relative
// path, at any depth, each once.
const closure = (file: string, seen: Set<string> = new Set()): string[] => {
  if (seen.has(file)) {
    return [];
  }
  seen.add(file);
  return [
    file,
    ...[...nodeFs.readFileSync(file, "utf8").matchAll(IMPORT)].flatMap((m) =>
      closure(nodePath.resolve(nodePath.dirname(file), m[1]), seen),
    ),
  ];
};

// What a build depends on besides the program's files: the `bend` on PATH
// (its path, size and time: a compiled bend is large), and the paths and
// texts of the bend2 sources in `dir`, which hold Base and the compiler when
// that `bend` runs a checkout.
const builder = (dir: URL): string => {
  const bend = Bun.which("bend");
  const stat = bend === null ? undefined : nodeFs.statSync(bend);
  const sources = url.fileURLToPath(dir);
  return [
    stat === undefined ? "" : [bend, stat.size, stat.mtimeMs].join(" "),
    ...nodeFs
      .readdirSync(sources, { recursive: true, encoding: "utf8" })
      .filter((f) => [".ts", ".bend"].includes(nodePath.extname(f)))
      .sort()
      .flatMap((f) => [f, nodeFs.readFileSync(nodePath.join(sources, f), "latin1")]),
  ].join("\0");
};

// The executable of the rules program `source`, built by the `bend` on PATH
// with the bend2 sources in `dir`. A build is kept, and used again until a
// file the program imports, or the bend that builds it, changes; its use
// keeps it from prune (see USED). It goes to a folder of its own first, so
// a kept executable is never partial, and runs that build one program at
// once share one executable.
export const built = async (source: string, dir: URL): Promise<string> => {
  const file = nodePath.resolve(source);
  const from = nodePath.dirname(file);
  const key = getSha256Hex(
    [
      builder(dir),
      ...closure(file).flatMap((f) => [nodePath.relative(from, f), nodeFs.readFileSync(f, "utf8")]),
    ].join("\0"),
  ).slice(0, 16);
  const name = `${nodePath.basename(source, ".bend")}.${key}`;
  const exe = nodePath.join(PROGRAMS_DIR, name + (process.platform === "win32" ? ".exe" : ""));
  const kept = nodeFs.statSync(exe, { throwIfNoEntry: false });
  if (kept !== undefined) {
    if (Date.now() - kept.mtimeMs > USED) {
      nodeFs.utimesSync(exe, new Date(), new Date());
    }
    return exe;
  }
  nodeFs.mkdirSync(PROGRAMS_DIR, { recursive: true });
  const part = nodeFs.mkdtempSync(nodePath.join(PROGRAMS_DIR, ".part-"));
  try {
    const out = nodePath.join(part, nodePath.basename(exe));
    const ran = await getCommandOutcome(["bend", file, "-o", out], from);
    if (ran.code !== 0) {
      throw new Error(`could not build ${source}:\n${ran.out}${ran.err}`);
    }
    try {
      nodeFs.renameSync(out, exe);
    } catch (e) {
      if (!nodeFs.existsSync(exe)) {
        throw e;
      }
    }
  } finally {
    nodeFs.rmSync(part, { recursive: true, force: true });
  }
  return exe;
};

// Keeps `entry` at `file`, whole or not at all. A cache that cannot be
// written is skipped: the next run checks again.
const keep = (file: string, entry: Entry): void => {
  tryGetOrUndefined(() => {
    nodeFs.mkdirSync(nodePath.dirname(file), { recursive: true });
    writeFileAtomically(file, JSON.stringify(entry));
  });
};

// Notes the check numbered `number`, of the cache entry at `file`; `gone`
// says whether its types are gone. Gives the number.
const answered = (file: string, check: Answered, number: number, gone: boolean): number => {
  ANSWERED[number - 1] = check;
  NUMBERS.set(file, number);
  if (gone) {
    GONE.add(number);
  }
  return number;
};

// The answer to `check <path> <facts|syntax>`: from the cache, if each file
// the check read is unchanged, numbered as before in this server, or anew
// with its types gone; else from Bend, and a passed check goes to the cache.
const checked = async (checker: Checker, path: string, facts: boolean): Promise<string> => {
  const file = entryOf(checker, path, facts);
  const entry = cached(file);
  const known = NUMBERS.get(file);
  if (entry !== undefined) {
    return numbered(
      entry.answer,
      known !== undefined && ANSWERED[known - 1].digest === entry.digest
        ? known
        : answered(file, { path, facts, digest: entry.digest }, TYPES.push([]), true),
    );
  }
  const made = await check(checker, path, facts);
  if (made.read !== undefined && made.number !== undefined) {
    const answer = numbered(made.answer, 0);
    const sum = getSha256Hex(answer);
    answered(file, { path, facts, digest: sum }, made.number, false);
    keep(file, {
      files: made.read.map(([p, text]) => [p, getSha256Hex(text)]),
      answer,
      digest: sum,
    });
  }
  return made.answer;
};

// Checks again the check numbered `number`, whose types are gone, with the
// same numbers. Its answer must be the one rules have.
const revive = async (checker: Checker, number: number): Promise<void> => {
  const { path, facts, digest: was } = ANSWERED[number - 1];
  const made = await check(checker, path, facts, number);
  if (made.read === undefined || getSha256Hex(numbered(made.answer, 0)) !== was) {
    nodeFs.rmSync(entryOf(checker, path, facts), { force: true });
    throw new Error("a check changed since its answer; run again");
  }
  GONE.delete(number);
};

// The answer to `ask <question>...`: one record per question, in order. The
// checks they ask about whose types are gone are checked again first.
const ask = async (checker: Checker, questions: string[]): Promise<string> => {
  try {
    const numbers = new Set(
      questions.flatMap((q) =>
        q
          .split(":")
          .filter((_, i) => i === 1 || i === 3)
          .map(Number),
      ),
    );
    for (const number of [...numbers].filter((n) => GONE.has(n))) {
      await revive(checker, number);
    }
    const loaded = await checker.loaded();
    return questions.map((q) => question(loaded, q)).join("");
  } catch (e) {
    return record(["fail", getErrorMessageFromUnknown(e)]);
  }
};

// The answer to `forget <check>`: the check's types are freed. A question
// about them checks it again.
const forget = (check: number): string => {
  TYPES[check - 1] = [];
  GONE.add(check);
  return record(["forgot"]);
};

// The answer to `files <input>...`: the files the inputs name, each once, in
// order, absolute, links resolved, with "/" between their parts. An input is
// a path, or a glob with "/" between its parts, whose files come sorted. If
// an input names no file, why.
const named = (inputs: string[]): string => {
  const found = inputs.map((input) =>
    (GLOB.test(input) ? nodeFs.globSync(input).sort() : [input]).filter(
      (f) => nodeFs.existsSync(f) && nodeFs.statSync(f).isFile(),
    ),
  );
  const none = inputs.find((_, i) => found[i].length === 0);
  return none !== undefined
    ? record(["fail", none + " matches no file"])
    : [
        ...new Set(
          found
            .flat()
            .map((f) => getPathWithForwardSlashes(nodeFs.realpathSync.native(nodePath.resolve(f)))),
        ),
      ]
        .map((f) => record(["file", f]))
        .join("");
};

const answer = (checker: Checker, line: string): Promise<string> => {
  const [op, ...args] = line.split("\t").map(unfield);
  return op === "check" && args.length === 2
    ? checked(checker, args[0], args[1] === "facts")
    : op === "files"
      ? Promise.resolve(named(args))
      : op === "forget" && args.length === 1
        ? Promise.resolve(forget(Number(args[0])))
        : op === "ask"
          ? ask(checker, args)
          : Promise.resolve(record(["fail", "unknown request: " + line]));
};

// One request: read its line, write the whole answer, close. If Bend does not
// load, the answer says why.
const serve = async (checker: Checker, socket: net.Socket): Promise<void> => {
  const lines = readline.createInterface({ input: socket });
  const [line] = (await once(lines, "line")) as [string];
  lines.close();
  socket.end(
    await answer(checker, line).catch((e: unknown) =>
      record(["fail", getErrorMessageFromUnknown(e)]),
    ),
  );
};

// The checker, and the rules program `named`: built first if it is a .bend
// file. The checker comes first, so a drift stops the run before a build.
const started = async (named: string): Promise<[Checker, string]> => {
  const dir = unwrap(await tryGetBend2SourceUrl());
  const checker = load(dir);
  return [checker, named.endsWith(".bend") ? await built(named, dir) : named];
};

// Side effects
// ============

if (import.meta.main) {
  const argv = process.argv.slice(2);
  const at = argv.indexOf("--program");
  const named = at === -1 ? MAIN : argv[at + 1];
  if (named === undefined) {
    console.error("usage: bend-lint [--program <rules program>] <args...>");
    process.exit(2);
  }
  const args = argv.filter((_, i) => at === -1 || (i !== at && i !== at + 1));

  const [checker, program] = await started(named).catch((e: unknown) => {
    console.error("bend-lint: " + getErrorMessageFromUnknown(e));
    return process.exit(2);
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
  prune(CHECKS_DIR);
  prune(PROGRAMS_DIR);
  process.exit(code ?? 1);
}
