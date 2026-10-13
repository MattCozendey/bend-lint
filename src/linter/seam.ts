#!/usr/bin/env bun
// The checker server: the TS half of the seam, which seam.bend reads (design:
// lint.bend's header). It runs a rules program, and answers its questions
// about Bend files over local TCP until the program exits. It goes when
// Bend's checker is Bend, so mutation and any optimization are fair here.
// Node 24.2 or later runs a built program too, but a large program needs
// --max-old-space-size=8192.
//
// It loads a copy of bend.ts in which each TRACED function reports its calls:
// the parser's give each file's syntax before lowering; the checker's
// judgments, on each def's elaborated body, give the facts. The server only
// dumps what Bend made: seam.bend makes the nodes and the facts of it, as it
// will of what Bend's own checker gives.
//
// Bootstrap: what a rule sees is lint.bend's contract, not Bend's. When the
// checker is Bend, each field comes from it, or bend-lint computes it.
//
// | What a rule sees               | Now, from                         | Risk   |
// | ------------------------------ | --------------------------------- | ------ |
// | spans, names, binders, targets | the parser                        | low    |
// | types: show, same, normal      | term_show, term_compare, term_snf | low    |
// | declarations and their uses    | program.bend, our own code        | none   |
// | syntax before lowering         | the parser's frames (KEPT)        | medium |
// | quantity, used                 | the judgments (JUDGED)            | high   |
// | which node a fact is on        | span values (seam.bend)           | medium |
//
// - Syntax before lowering: else bend-lint calls Bend's parse functions
//   itself, as KEPT follows them now.
// - Quantity and used: a checker in Bend cannot be hooked; else a walker in
//   Bend computes them again.
// - Which node a fact is on: Bend values have no identity, so a fact finds its
//   node by span value, kind, name and children; sugar that shares a span is
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
  Ctx,
  Err,
  HTerm,
  LTerm,
  Patt,
  Quant,
  Span,
  TLD,
} from "bend2/bend.ts";
import type * as BendModule from "bend2/bend.ts";

import { getBendLintCacheDir, tryGetBend2SourceUrl } from "../shared/bend2.ts";
import { unwrap } from "../shared/result.ts";
import { getTextWithEachEditAppliedOnce, getTextWithLfLineEnds } from "../shared/text.ts";
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

type Loaded = { Bend: Bend; base: Book };

// What a check's answer depends on besides its files (this server, the
// patched bend.ts and Base, as one digest), and Bend, loaded when a check or
// a question first needs it: an answer from the cache needs none.
type Checker = { version: string; loaded: () => Promise<Loaded> };

// A check's answer as the cache keeps it, with 0 for its number: the files it
// read, each with the digest of the text it read, and the answer's digest.
type Entry = { files: Array<[string, string]>; answer: string; digest: string; types: number };

// The facts a check gives: none, or those of the files at `paths` (all, if
// none).
type Wanted = { paths: string[] } | undefined;

// A check this server answered: its root, the facts it gives, its answer's
// digest, numbered 0, and how many types its dump numbers. Enough to check it
// again with the same numbers.
type Answered = { path: string; facts: Wanted; digest: string; types: number };

// The answers to questions about a check's types, by question with its
// checks numbered 0, kept beside its cache entry (`digest` is the entry's):
// a later run that asks them checks nothing again.
type Memo = { digest: string; answers: Record<string, string> };

// An exact edit of bend.ts: the text it must find once, and its replacement.
type Edit = [string, string];

type Traced = (...args: unknown[]) => unknown;

// What a dump keeps of a call, from its arguments and result: the arguments
// besides its parser (an import's aliases, in order), and its result.
type Kept = (args: unknown[], out: unknown) => [unknown[], unknown];

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

// What the checker passed a judgment, by the term it gave back: the demand
// on the term, its context and depth, and how often each binder it closed
// (by level) was used.
type Judgment = { qt: Quant; ctx: Ctx; dep: number; used: ReadonlyArray<[number, Quant]> };

// The binders around a type: the checker's context, and its depth.
type Scope = { ctx: Ctx; dep: number };

// What a check's dump numbers, and its questions name: its book, each type
// the checker holds, each scope, and each file the parser read.
type Dumped = { bok: Book; types: HTerm[]; scopes: Scope[]; files: Array<Span["file"]> };

// A dump as it is written: the tokens of its section, what it numbered so far
// (by object; a scope by its context, then its depth; a text and a span by
// value), each binder's entry in a context it numbered, and, for facts, what
// the checker passed each judgment.
type Dump = Dumped & {
  tokens: string[];
  texts: Map<string, number>;
  spans: Map<string, number>;
  typeIds: Map<HTerm, number>;
  fileIds: Map<Span["file"], number>;
  scopeIds: Map<Ctx, Map<number, number>>;
  entryIds: Map<Ann, number>;
  entries: Ann[];
  judgments?: Map<LTerm, Judgment>;
};

// A type a question names: the type, its book, and its scope.
type Typed = Scope & { ty: HTerm; bok: Book };

// What has a tag (`$`) in a dump: a term, a pattern, a body that is not a
// term, and a quantity.
type Tagged = LTerm | Patt | Exclude<Body, LTerm> | Quant;

// What a dump writes of its own: a flag, the book's tables, a span, the
// checker's annotation and judgment, a case, a kept call, a binder of a
// telescope, and a declaration.
type Own =
  | "True"
  | "False"
  | "Ctrs"
  | "Tlds"
  | "Span"
  | "Typed"
  | "Judged"
  | "Case"
  | "Frame"
  | "Domain"
  | "Tld";

// Constants
// =========

const ESCAPES: Record<string, string> = { "\\": "\\\\", "\t": "\\t", "\n": "\\n" };

const SERVER_CACHE_DIR = new URL("server/", getBendLintCacheDir());

const CHECKS_DIR = url.fileURLToPath(new URL("checks/", SERVER_CACHE_DIR));

const PROGRAMS_DIR = url.fileURLToPath(new URL("programs/", SERVER_CACHE_DIR));

const MAIN = url.fileURLToPath(new URL("main.bend", import.meta.url));

// An import by a relative path: of a .bend file, or, quoted, of an effect's.
const IMPORT = /^\s*import\s+"?(\.\.?\/[^\s"]+)/gm;

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

// What a dump keeps of a KEPT call, by its function.
const FRAMES: Record<string, Kept> = {
  book_load: (args) => [[args[1], args[4]], undefined],
  parse_book: (args) => [[args[2], args[3], Object.keys(args[4] as object)], undefined],
  parse_def: () => [[], undefined],
  parse_fresh: (args, out) => [[args[1], args[2]], out],
  parse_reso: (args, out) => [[args[1]], out],
  parse_tele: (args, out) => [[args[1], args[2]], out],
  parse_term: (_, out) => [[], out],
  parse_body: (_, out) => [[], out],
  term_higher: (args) => [[args[0]], undefined],
};

// The fields a dump writes of what has a tag, in order (seam.bend reads them
// so). A variable's value is a substitution's, which a dump writes as the
// name of the reference it is, or "".
const FIELDS: { [K in Tagged["$"]]: ReadonlyArray<Exclude<keyof Extract<Tagged, { $: K }>, "$">> } =
  {
    Var: ["k", "i", "v", "s"],
    Ref: ["k", "s"],
    Sub: ["i", "v", "f", "s"],
    Let: ["k", "i", "q", "v", "f", "s"],
    Typ: ["g", "s"],
    Qnt: ["s"],
    Qua: ["q", "s"],
    Min: ["a", "b", "s"],
    All: ["q", "k", "i", "A", "B", "s"],
    Lam: ["k", "i", "f", "q", "s"],
    App: ["f", "x", "s"],
    ADT: ["k", "x", "s"],
    Ctr: ["k", "x", "s"],
    Lit: ["k", "v", "s"],
    Mat: ["k", "h", "m", "s"],
    Efq: ["s"],
    Eql: ["a", "b", "T", "s"],
    Rfl: ["s"],
    Rwt: ["e", "p", "f", "s"],
    Hol: ["k", "s"],
    Ann: ["x", "T", "s"],
    PVar: ["k", "i", "q", "s"],
    PCtr: ["k", "x", "s"],
    Match: ["e", "r", "s"],
    Local: ["k", "q", "v", "f"],
    None: [],
    Lone: [],
    Many: [],
  };

// The tag a dump writes after each tagged value, and after each of the
// dump's own values: one character each (seam.bend reads them).
const TAGS: { [K in Tagged["$"] | Own]: string } = {
  Var: "v",
  Ref: "r",
  Sub: "s",
  Let: "l",
  Typ: "t",
  Qnt: "q",
  Qua: "Q",
  Min: "m",
  All: "a",
  Lam: "L",
  App: "A",
  ADT: "D",
  Ctr: "c",
  Lit: "i",
  Mat: "M",
  Efq: "e",
  Eql: "E",
  Rfl: "R",
  Rwt: "w",
  Hol: "h",
  Ann: "n",
  PVar: "p",
  PCtr: "P",
  Match: "x",
  Local: "X",
  None: "N",
  Lone: "O",
  Many: "Y",
  True: "T",
  False: "F",
  Ctrs: "C",
  Tlds: "Z",
  Span: "S",
  Typed: "y",
  Judged: "j",
  Case: "k",
  Frame: "f",
  Domain: "d",
  Tld: "g",
};

const NONE: ReadonlySet<string> = new Set();

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

// The text of each file bend.ts read while the check that runs read it, by
// the path it read.
const READS = new Map<string, string>();

// The dumps of the checks answered, by number (from 1), and the checks whose
// dumps are gone: freed, or answered from the cache. A question about one
// checks it again.
const CHECKS: Array<Dumped | undefined> = [];
const ANSWERED: Answered[] = [];
const GONE = new Set<number>();

// The number of each check answered from or to the cache, by its entry's
// path: the files of one entry share one check.
const NUMBERS = new Map<string, number>();

// The memo of each check numbered so far that a question asked about, and
// those with answers not kept yet.
const MEMOS = new Map<number, Memo>();
const UNKEPT = new Set<number>();

const STALE = 7 * 24 * 60 * 60 * 1000;

// Touching an executable makes a virus scanner check
// it again before it runs (about 0.2 s on Windows), so not on every run.
const USED = 24 * 60 * 60 * 1000;

// A prune stats each entry of its folder (about 0.1 s for 9000 entries), so
// not on every run.
const PRUNE_EVERY = 24 * 60 * 60 * 1000;

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
  Object.assign(
    new Error(text + "; update EDITS, TRACED, FRAMES or FIELDS in src/linter/seam.ts"),
    { name: "DriftError" },
  );

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

// Node's readFileSync, which keeps in READS each text it reads.
const readFileSync = ((p: nodeFs.PathOrFileDescriptor, options?: unknown) => {
  const read = nodeFs.readFileSync(p, options as BufferEncoding);
  if (typeof read === "string") {
    READS.set(String(p), read);
  }
  return read;
}) as typeof nodeFs.readFileSync;

// What the server Shares with its copy of bend.ts: Node's fs and path, with
// each path they give real and with `/`, as Bend resolves imports with
// path.posix, where a drive letter is a root; and each text Bend reads kept.
const shared = (): Shared => ({
  fs: { ...nodeFs, realpathSync: realpath, readFileSync },
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

// Points the TRACED function `name` at `hook`, or back at its original. A
// binding bend.ts sets is code JSC compiles again, so one that would not
// change is left alone.
const setHook = (name: string, hook?: Hook): void => {
  if (HOOKED.get(name) !== hook) {
    HOOKED.set(name, hook);
    (globalThis as { BEND_LINT?: Shared }).BEND_LINT?.hook?.(name, hook);
  }
};

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
      const judged = f(...args) as { tm: LTerm };
      const used = closed.length === mark ? [] : closed.slice(mark);
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

const isFile = (o: object): o is Span["file"] => "str" in o && "ns" in o && "al" in o;

const isSpan = (o: object): o is Span => "file" in o && "beg" in o && "end" in o;

// The number of `x` among `xs`, which `ids` numbers; a new one goes last.
const numberOf = <T>(ids: Map<T, number>, xs: T[], x: T): number => {
  const known = ids.get(x);
  if (known !== undefined) {
    return known;
  }
  ids.set(x, xs.length);
  xs.push(x);
  return xs.length - 1;
};

const typeOf = (d: Dump, ty: HTerm): string => String(numberOf(d.typeIds, d.types, ty));

const fileOf = (d: Dump, file: Span["file"]): string => String(numberOf(d.fileIds, d.files, file));

const entryOf = (d: Dump, entry: Ann): string => String(numberOf(d.entryIds, d.entries, entry));

const scopeOf = (d: Dump, ctx: Ctx, dep: number): string => {
  const deps = d.scopeIds.get(ctx) ?? new Map<number, number>();
  d.scopeIds.set(ctx, deps);
  const known = deps.get(dep);
  if (known !== undefined) {
    return String(known);
  }
  deps.set(dep, d.scopes.length);
  d.scopes.push({ ctx, dep });
  return String(d.scopes.length - 1);
};

const dumpOf = (bok: Book, judgments?: Map<LTerm, Judgment>): Dump => ({
  bok,
  types: [],
  scopes: [],
  files: [],
  tokens: [],
  texts: new Map(),
  spans: new Map(),
  typeIds: new Map(),
  fileIds: new Map(),
  scopeIds: new Map(),
  entryIds: new Map(),
  entries: [],
  judgments,
});

// Writes `x` to a dump, in postfix (seam.bend reads it), each tag as TAGS
// writes it: a number as itself, a list between `[` and `]` (`[]` if empty),
// a tagged value as its FIELDS then its tag, the book's tables as Ctrs and
// Tlds, and a file as its number. A text is `'` and the text, and a span its
// file, start and end, then Span: each numbered, in the order written, so that
// a text written again is `@` and its number, and a span `#` and its. A typing
// annotation is its term, then its type's number, then Typed; a term the
// checker judged is followed by the judgment's demand, scope and uses, then
// Judged. Anything else is `_`.
const put = (d: Dump, x: unknown): void => {
  if (typeof x === "string") {
    const known = d.texts.get(x);
    d.texts.set(x, known ?? d.texts.size);
    d.tokens.push(known === undefined ? "'" + x : "@" + known);
  } else if (typeof x === "number") {
    d.tokens.push(String(x));
  } else if (typeof x === "boolean") {
    d.tokens.push(x ? TAGS.True : TAGS.False);
  } else if (Array.isArray(x) && x.length === 0) {
    d.tokens.push("[]");
  } else if (Array.isArray(x)) {
    d.tokens.push("[");
    x.forEach((y) => put(d, y));
    d.tokens.push("]");
  } else if (typeof x !== "object" || x === null) {
    d.tokens.push("_");
  } else {
    putObject(d, x as Record<string, unknown>);
  }
};

const putObject = (d: Dump, o: Record<string, unknown>): void => {
  if (o === d.bok.ctrs || o === d.bok.tlds) {
    d.tokens.push(o === d.bok.ctrs ? TAGS.Ctrs : TAGS.Tlds);
  } else if (isFile(o)) {
    d.tokens.push(fileOf(d, o));
  } else if (isSpan(o)) {
    putSpan(d, fileOf(d, o.file), o.beg, o.end);
  } else if (typeof o.$ === "string") {
    putTagged(d, o as Tagged);
  } else if ("p" in o && "f" in o) {
    put(d, o.p);
    put(d, o.f);
    d.tokens.push(TAGS.Case);
  } else {
    d.tokens.push("_");
  }
};

const putSpan = (d: Dump, file: string, beg: number, end: number): void => {
  const key = file + ":" + beg + ":" + end;
  const known = d.spans.get(key);
  d.spans.set(key, known ?? d.spans.size);
  d.tokens.push(
    ...(known === undefined ? [file, String(beg), String(end), TAGS.Span] : ["#" + known]),
  );
};

const putTagged = (d: Dump, t: Tagged): void => {
  const fields = FIELDS[t.$] as ReadonlyArray<string> | undefined;
  if (fields === undefined) {
    throw drift(`unknown kind ${t.$}`);
  }
  if (t.$ === "Ann" && isTyping(t) && t.T.$ === "Var" && t.T.v !== undefined) {
    put(d, t.x);
    d.tokens.push(typeOf(d, t.T.v), TAGS.Typed);
  } else {
    fields.forEach((k) => {
      const v = (t as Record<string, unknown>)[k];
      if (t.$ === "Var" && k === "v") {
        put(d, t.v === undefined ? undefined : t.v.$ === "Ref" ? t.v.k : "");
      } else {
        put(d, v);
      }
    });
    d.tokens.push(TAGS[t.$]);
  }
  const j = d.judgments?.get(t as LTerm);
  if (j !== undefined) {
    put(d, j.qt);
    d.tokens.push(scopeOf(d, j.ctx, j.dep));
    put(d, j.used);
    d.tokens.push(TAGS.Judged);
  }
};

// Writes a kept call: its function, its parser's file, what FRAMES keeps of
// it, where the parser is after it, and the calls it kept, then Frame.
const putFrame = (d: Dump, f: Frame): void => {
  const kept = FRAMES[f.name] as Kept | undefined;
  if (kept === undefined) {
    throw drift(`unknown frame ${f.name}`);
  }
  const [args, out] = kept(f.args, f.out);
  const p = f.args[0];
  put(d, f.name);
  if (typeof p === "object" && p !== null && isFile(p)) {
    d.tokens.push(fileOf(d, p));
  } else {
    d.tokens.push("_");
  }
  put(d, args);
  put(d, out);
  put(d, f.end < 0 ? undefined : f.end);
  d.tokens.push("[");
  f.kids.forEach((kid) => putFrame(d, kid));
  d.tokens.push("]", TAGS.Frame);
};

// Writes the telescope of a declaration's type, opened as the checker opens
// it: each binder's name, quantity, span and type, its scope, and its entry
// in the context of what follows it, then Domain; all as a list.
const putTelescope = (d: Dump, Bend: Bend, T: HTerm): void => {
  let ctx = Bend.ctx_nil();
  d.tokens.push("[");
  for (let t = T, i = 0; t.$ === "All"; t = t.B(Bend.Var(t.k, i)), i++) {
    const scope = scopeOf(d, ctx, i);
    ctx = Bend.ctx_bind(ctx, i, t.q, t.k, t.A);
    const entry = Bend.pmap_get(ctx, i);
    put(d, t.k);
    put(d, t.q);
    put(d, t.s);
    d.tokens.push(typeOf(d, t.A), scope, entry === null ? "_" : entryOf(d, entry), TAGS.Domain);
  }
  d.tokens.push("]");
};

// The first span the parser read of `x`, a term, as it walks it.
const firstSpan = (x: unknown): Span | undefined => {
  const stack: unknown[] = [x];
  while (stack.length > 0) {
    const y = stack.pop();
    if (typeof y === "object" && y !== null) {
      if (isSpan(y)) {
        return y;
      }
      const kids = Array.isArray(y)
        ? (y as unknown[])
        : Object.entries(y).flatMap(([k, v]) => (k === "v" ? [] : [v]));
      stack.push(...kids.reverse());
    }
  }
  return undefined;
};

// The namespace of the file that writes a declaration: of the file its
// checked body is read from (a law's fill is the filler's), else its type's,
// or its first constructor's.
const writtenIn = (tld: TLD): string | undefined =>
  (tld.$ === "Def" && tld.e !== undefined
    ? firstSpan(tld.e)
    : [tld.T, ...(tld.$ === "ADT" ? tld.c.map((c) => c.T) : [])]
        .map((t) => (t.$ === "All" ? t.s : undefined))
        .find((t) => t !== undefined)
  )?.file.ns;

// Writes what a check's files declare: each name and its kind, then Tld;
// for those whose facts are `wanted` (by the namespace of the file that
// writes them; all, if undefined), with its type's telescope, its
// constructors' and its elaborated body. Template instances (`k~n`) are
// other defs, which no file writes.
const putTlds = (
  d: Dump,
  Bend: Bend,
  names: string[],
  wanted: ReadonlySet<string | undefined> | undefined,
): void => {
  d.tokens.push("[");
  [...new Set(names)].forEach((k) => {
    const tld = d.bok.tlds[k] as TLD | undefined;
    if (tld === undefined || k.includes("~")) {
      return;
    }
    put(d, k);
    put(d, tld.$);
    if (wanted === undefined || wanted.has(writtenIn(tld))) {
      putTelescope(d, Bend, tld.T);
      d.tokens.push("[");
      if (tld.$ === "ADT") {
        tld.c.forEach((c) => putTelescope(d, Bend, c.T));
      }
      d.tokens.push("]");
      put(d, tld.$ === "Def" ? tld.e : undefined);
    } else {
      d.tokens.push("_", "_", "_");
    }
    d.tokens.push(TAGS.Tld);
  });
  d.tokens.push("]");
};

// A record of the tokens `write` puts in `d`.
const section = (d: Dump, tag: string, write: () => void): string => {
  d.tokens = [];
  write();
  return record([tag, ...d.tokens]);
};

// The records of what a dump numbered: each scope's entries (by level), each
// entry's quantity and type, and each file's text and namespace. A scope
// numbers entries, so it goes first.
const tables = (Bend: Bend, d: Dump): string[] => [
  section(d, "scopes", () => {
    d.tokens.push("[");
    d.scopes.forEach(({ ctx, dep }) => {
      d.tokens.push("[");
      Array.from({ length: dep }, (_, level) => Bend.pmap_get(ctx, level)).forEach((entry) =>
        d.tokens.push(entry === null ? "_" : entryOf(d, entry)),
      );
      d.tokens.push("]");
    });
    d.tokens.push("]");
  }),
  section(d, "entries", () => {
    d.tokens.push("[");
    d.entries.forEach((entry) => {
      d.tokens.push("[");
      put(d, entry.q);
      d.tokens.push(typeOf(d, entry.T), "]");
    });
    d.tokens.push("]");
  }),
  section(d, "files", () =>
    put(
      d,
      d.files.map((file) => [file.str, file.ns]),
    ),
  ),
];

// Bend's message for a failed check, without its location if `placed`.
const failure = (Bend: Bend, e: unknown, placed: boolean): string => {
  if (!isErr(e)) {
    return getErrorMessageFromUnknown(e);
  }
  const shown = Bend.err_show(e);
  const at = shown.indexOf("\nLocation:");
  return !placed || at < 0 ? shown : shown.slice(0, at) + (e.nte === undefined ? "" : "\n" + e.nte);
};

// The path Bend loads a file at, as `seen` keeps it: real, with `/`.
const rooted = (path: string): string =>
  tryGetOrUndefined(() => realpath(path)) ?? getPathWithForwardSlashes(nodePath.resolve(path));

// The answer to `check <path> <facts|syntax> <paths...>`: the check's number (for
// `ask` and `forget`), then its dump: Base's path, the calls that loaded its
// files (`frames`), what they declare (`tlds`) and the tables (see
// `tables`). A failed check's answer has no number; its frames are
// `loading` if a load failed, and it has no `tlds` then. It ends with the
// files the check read, then why it failed: Bend's message with and
// without its location, and, if Bend's error says, where: the file, start
// and end, and the file a load did not finish, with its text. A passed
// check also gives the files it read, with the text it read; its number is
// `number`, or the next. Facts are only of the files at `paths` (all, if
// none). The hooks are global, so checks must not overlap.
const check = async (
  checker: Checker,
  path: string,
  facts: Wanted,
  number?: number,
): Promise<{ answer: string; read?: Array<[string, string]>; number?: number; types?: number }> => {
  const { Bend, base } = await checker.loaded();
  const book = seeded(Bend, base);
  const seen = new Map<string, string | null>([[Bend.BASE_BEND, ""]]);
  const root: Frame = { name: "check", args: [], out: undefined, end: -1, kids: [] };
  const judgments = facts === undefined ? undefined : new Map<LTerm, Judgment>();
  const d = dumpOf(book, judgments);
  const own = (): string[] => book.order.slice(base.order.length);
  const frames = (tag: string): string =>
    section(d, tag, () => {
      d.tokens.push("[");
      root.kids.forEach((f) => putFrame(d, f));
      d.tokens.push("]");
    });
  let loaded = false;
  READS.clear();
  traceParsing(root);
  try {
    await Bend.book_load(book, rooted(path), "", seen);
    untrace();
    loaded = true;
    if (judgments !== undefined) {
      traceJudgments(Bend, judgments);
    }
    Bend.book_valid(book, base.order.length);
    untrace();
    const dump = [
      record(["base", Bend.BASE_BEND]),
      frames("frames"),
      section(d, "tlds", () =>
        putTlds(
          d,
          Bend,
          own(),
          facts === undefined
            ? new Set()
            : facts.paths.length === 0
              ? undefined
              : new Set(facts.paths.map((p) => seen.get(rooted(p)) ?? undefined)),
        ),
      ),
      ...tables(Bend, d),
    ];
    const id = number ?? CHECKS.push(undefined);
    CHECKS[id - 1] = { bok: d.bok, types: d.types, scopes: d.scopes, files: d.files };
    return {
      answer: [record(["check", String(id)]), ...dump].join(""),
      read: [...READS],
      number: id,
      types: d.types.length,
    };
  } catch (e) {
    untrace();
    const dump = [
      record(["base", Bend.BASE_BEND]),
      frames(loaded ? "frames" : "loading"),
      ...(loaded ? [section(d, "tlds", () => putTlds(d, Bend, own(), new Set()))] : []),
    ];
    const s = isErr(e) ? e.spn : undefined;
    const pending = [...seen].filter(([, ns]) => ns === null).pop()?.[0];
    const where =
      s === undefined
        ? ["", "", "", "", ""]
        : [
            fileOf(d, s.file),
            String(s.beg),
            String(s.end),
            pending ?? "",
            READS.get(pending ?? "") ?? "",
          ];
    return {
      answer: [
        ...dump,
        ...tables(Bend, d),
        ...[...seen.keys()].filter((p) => p !== Bend.BASE_BEND).map((p) => record(["read", p])),
        record(["fail", failure(Bend, e, false), failure(Bend, e, true), ...where]),
      ].join(""),
    };
  } finally {
    untrace();
  }
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

// Whether two types are the same: from one check, equal by the checker, and
// each inside the `shared` levels their scopes share (seam.bend counts
// them): a type that uses a level past them names another variable there.
const sameType = (Bend: Bend, a: Typed, b: Typed, shared: number): boolean => {
  if (a.bok !== b.bok) {
    return false;
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

// The checker checks a template's body with `k~A`, in no book, for its
// parameter `A` (def_check); this writes `A` back.
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

// The answer to one question about types: `show:<check>:<type>:<scope>:<file>`,
// `same:<check>:<type>:<scope>:<check>:<type>:<scope>:<shared>` or
// `normal:<check>:<type>`. A type is a number of its check's dump, in a scope
// of it; a file's aliases spell what a type shows.
const question = ({ Bend }: Loaded, q: string): string => {
  const [op, ...ns] = q.split(":");
  const n = ns.map(Number);
  const dumped = (c: number): Dumped => {
    const d = CHECKS[c - 1];
    if (d === undefined) {
      throw new Error("no check " + c);
    }
    return d;
  };
  const typed = (c: number, t: number, s: number): Typed => {
    const d = dumped(c);
    const ty = d.types[t] as HTerm | undefined;
    const scope = d.scopes[s] as Scope | undefined;
    if (ty === undefined || scope === undefined) {
      throw new Error("no type " + [c, t, s].join(":"));
    }
    return { ty, bok: d.bok, ...scope };
  };
  if (op === "show") {
    const t = typed(n[0], n[1], n[2]);
    const names = Array.from({ length: t.dep }, (_, level) => Bend.pmap_get(t.ctx, level)?.k);
    return record([
      "shown",
      Bend.term_show(
        written(Bend.term_lower(t.ty, t.dep), t.bok),
        -1,
        names as string[],
        dumped(n[0]).files[n[3]],
      ),
    ]);
  }
  if (op === "same" && n[0] !== n[3]) {
    return record(["same", "false"]);
  }
  if (op === "same") {
    return record([
      "same",
      String(sameType(Bend, typed(n[0], n[1], n[2]), typed(n[3], n[4], n[5]), n[6])),
    ]);
  }
  if (op === "normal") {
    const d = dumped(n[0]);
    const ty = d.types[n[1]] as HTerm | undefined;
    if (ty === undefined) {
      throw new Error("no type " + n[0] + ":" + n[1]);
    }
    d.types.push(Bend.term_snf(d.bok, ty));
    return record(["normal", String(n[0]), String(d.types.length - 1)]);
  }
  throw new Error("unknown question " + q);
};

// An answer with `number` as its check's number.
const numbered = (answer: string, number: number): string =>
  answer.replace(/^(check\t)\d+$/m, "$1" + number);

const cachePathOf = ({ version }: Checker, path: string, facts: Wanted): string =>
  nodePath.join(
    CHECKS_DIR,
    getSha256Hex(
      [version, facts === undefined ? "syntax" : ["facts", ...facts.paths].join("\0"), path].join(
        "\n",
      ),
    ) + ".json",
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
// STALE, unless its .pruned file shows a prune in the last PRUNE_EVERY; one
// that another run deletes first is skipped. A folder that cannot be read
// keeps its entries.
const prune = (dir: string): void => {
  const marker = nodePath.join(dir, ".pruned");
  const last = nodeFs.statSync(marker, { throwIfNoEntry: false })?.mtimeMs ?? 0;
  if (Date.now() - last < PRUNE_EVERY) {
    return;
  }
  tryGetOrUndefined(() => nodeFs.writeFileSync(marker, ""));
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

// The .bend file at `file` and every file it imports by a relative path
// (.bend files at any depth, and effects' files), each once.
const closure = (file: string, seen: Set<string> = new Set()): string[] => {
  if (seen.has(file)) {
    return [];
  }
  seen.add(file);
  return [
    file,
    ...(file.endsWith(".bend")
      ? [...nodeFs.readFileSync(file, "utf8").matchAll(IMPORT)].flatMap((m) =>
          closure(nodePath.resolve(nodePath.dirname(file), m[1]), seen),
        )
      : []),
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

// The answer to `check <path> <facts|syntax> <paths...>`: from the cache, if each file
// the check read is unchanged, numbered as before in this server, or anew
// with its dump gone; else from Bend, and a passed check goes to the cache.
const checked = async (checker: Checker, path: string, facts: Wanted): Promise<string> => {
  const file = cachePathOf(checker, path, facts);
  const entry = cached(file);
  const known = NUMBERS.get(file);
  if (entry !== undefined) {
    return numbered(
      entry.answer,
      known !== undefined && ANSWERED[known - 1].digest === entry.digest
        ? known
        : answered(
            file,
            { path, facts, digest: entry.digest, types: entry.types },
            CHECKS.push(undefined),
            true,
          ),
    );
  }
  const made = await check(checker, path, facts);
  if (made.read !== undefined && made.number !== undefined && made.types !== undefined) {
    const answer = numbered(made.answer, 0);
    const sum = getSha256Hex(answer);
    answered(file, { path, facts, digest: sum, types: made.types }, made.number, false);
    keep(file, {
      files: made.read.map(([p, text]) => [p, getSha256Hex(text)]),
      answer,
      digest: sum,
      types: made.types,
    });
  }
  return made.answer;
};

// Checks again the check numbered `number`, whose dump is gone, with the
// same numbers. Its answer must be the one rules have.
const revive = async (checker: Checker, number: number): Promise<void> => {
  const { path, facts, digest: was } = ANSWERED[number - 1];
  const made = await check(checker, path, facts, number);
  if (made.read === undefined || getSha256Hex(numbered(made.answer, 0)) !== was) {
    nodeFs.rmSync(cachePathOf(checker, path, facts), { force: true });
    throw new Error("a check changed since its answer; run again");
  }
  GONE.delete(number);
};

// The checks whose dumps a question reads: its check, or none for a `same`
// of two checks (see `question`).
const checksOf = (q: string): number[] => {
  const [op, c, , , d] = q.split(":");
  return op === "same" && c !== d ? [] : [Number(c)];
};

// Where a question is kept, if its answer is the same in any run: its check,
// and the question with its checks numbered 0. Not `normal`, whose handle is
// the next of this run, nor a question about a type a `normal` of this run
// made.
const memoKeyOf = (q: string): { check: number; key: string } | undefined => {
  const parts = q.split(":");
  const n = parts.map(Number);
  const handles = parts[0] === "show" ? [n[2]] : parts[0] === "same" ? [n[2], n[5]] : [];
  const own = ANSWERED[n[1] - 1]?.types;
  return handles.length === 0 ||
    own === undefined ||
    handles.some((h) => h >= own) ||
    checksOf(q).length === 0
    ? undefined
    : {
        check: n[1],
        key: parts.map((x, i) => (i === 1 || (i === 4 && parts[0] === "same") ? "0" : x)).join(":"),
      };
};

const memoPathOf = (checker: Checker, check: number): string => {
  const { path, facts } = ANSWERED[check - 1];
  return cachePathOf(checker, path, facts) + ".answers";
};

// The memo of the check numbered `check`: kept, if its entry's digest is
// the one this server answered with, else new.
const memoOf = (checker: Checker, check: number): Memo => {
  const known = MEMOS.get(check);
  if (known !== undefined) {
    return known;
  }
  const { digest } = ANSWERED[check - 1];
  const kept = tryGetOrUndefined(
    () => JSON.parse(nodeFs.readFileSync(memoPathOf(checker, check), "utf8")) as Memo,
  );
  const memo = kept?.digest === digest ? kept : { digest, answers: {} };
  MEMOS.set(check, memo);
  return memo;
};

// The answer to `ask <question>...`: one record per question, in order, from
// the memos where they have it. The checks the others ask about whose dumps
// are gone are checked again first; their answers go to the memos.
const ask = async (checker: Checker, questions: string[]): Promise<string> => {
  try {
    const keys = questions.map(memoKeyOf);
    const recalled = keys.map((k) =>
      k === undefined ? undefined : memoOf(checker, k.check).answers[k.key],
    );
    const numbers = new Set(
      questions.flatMap((q, i) => (recalled[i] === undefined ? checksOf(q) : [])),
    );
    for (const number of [...numbers].filter((n) => GONE.has(n))) {
      await revive(checker, number);
    }
    const loaded = recalled.every((r) => r !== undefined) ? undefined : await checker.loaded();
    const answers = questions.map((q, i) => {
      const r = recalled[i];
      if (r !== undefined || loaded === undefined) {
        return r ?? "";
      }
      const got = question(loaded, q);
      const k = keys[i];
      if (k !== undefined) {
        memoOf(checker, k.check).answers[k.key] = got;
        UNKEPT.add(k.check);
      }
      return got;
    });
    UNKEPT.forEach((check) =>
      tryGetOrUndefined(() =>
        writeFileAtomically(memoPathOf(checker, check), JSON.stringify(memoOf(checker, check))),
      ),
    );
    UNKEPT.clear();
    return answers.join("");
  } catch (e) {
    return record(["fail", getErrorMessageFromUnknown(e)]);
  }
};

// The answer to `forget <check>`: the check's dump is freed. A question
// about it checks it again.
const forget = (check: number): string => {
  CHECKS[check - 1] = undefined;
  GONE.add(check);
  return record(["forgot"]);
};

const answer = (checker: Checker, line: string): Promise<string> => {
  const [op, ...args] = line.split("\t").map(unfield);
  return op === "check" && args.length >= 2
    ? checked(checker, args[0], args[1] === "facts" ? { paths: args.slice(2) } : undefined)
    : op === "forget" && args.length === 1
      ? Promise.resolve(forget(Number(args[0])))
      : op === "ask"
        ? ask(checker, args)
        : Promise.resolve(record(["fail", "unknown request: " + line]));
};

// Runs each request it is given after the one before ends: a program's
// workers ask at once, and checks must not overlap (see `check`).
const serially = (): ((run: () => Promise<string>) => Promise<string>) => {
  let last: Promise<unknown> = Promise.resolve();
  return (run) => {
    const next = last.then(run);
    last = next.catch(() => undefined);
    return next;
  };
};

// One request: read its line, write the whole answer, close. If Bend does not
// load, the answer says why.
const serve = async (
  checker: Checker,
  inTurn: (run: () => Promise<string>) => Promise<string>,
  socket: net.Socket,
): Promise<void> => {
  const lines = readline.createInterface({ input: socket });
  const [line] = (await once(lines, "line")) as [string];
  lines.close();
  socket.end(
    await inTurn(() => answer(checker, line)).catch((e: unknown) =>
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

  const inTurn = serially();
  const server = net.createServer((socket) => void serve(checker, inTurn, socket));
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
