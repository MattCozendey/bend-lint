#!/usr/bin/env bun
// The checker server, and the glue to Bend's checker: the one place that knows bend.ts. It runs
// the program of the rules bend-lint.json names (see getRulesProgram), and answers its requests
// about Bend files over local TCP until the program exits (Seam in cli.bend sends them, and reads
// the answers). A check's answer is the linter's program, as Bend's parser and checker give it:
// each file's syntax tree, and, for facts, what the checker found on its nodes (Lint.Source, in
// lint.bend). When Bend's checker is Bend, glue in Bend makes the same program, and the code here
// that knows bend.ts goes, so mutation and any optimization are fair here. Node 24.2 or later runs
// a built program too, but a large program needs --max-old-space-size=8192.
//
// It loads a copy of bend.ts in which each TRACED function reports its calls: the parser's give
// each file's syntax before lowering; the checker's judgments, on each def's elaborated body, give
// the facts. What a rule sees is lint.bend's contract, not Bend's: when the checker is Bend, its
// glue makes each part from what that checker gives, or bend-lint computes it.
//
// | What a rule sees               | Now, from                         | Risk   |
// | ------------------------------ | --------------------------------- | ------ |
// | spans, names, binders, targets | the parser                        | low    |
// | types: show, same, normal      | term_show, term_compare, term_snf | low    |
// | declarations and their uses    | lint.bend, our own code           | none   |
// | syntax before lowering         | the parser's calls (KEPT)         | medium |
// | quantity, used                 | the judgments (JUDGED)            | high   |
// | which node a fact is on        | span values (`isNodeOf`)          | medium |
//
// - Syntax before lowering: else bend-lint calls Bend's parse functions itself, as KEPT follows
//   them now.
// - Quantity and used: a checker in Bend cannot be hooked; else a walker computes them again.
// - Which node a fact is on: Bend values have no identity, so a checked term finds its node by span
//   value, kind, name and children; sugar that shares a span is then ambiguous.

// Imports
// =======

import { spawn } from "node:child_process";
import { once } from "node:events";
import * as nodeFs from "node:fs";
import * as net from "node:net";
import * as os from "node:os";
import * as nodePath from "node:path";
import * as readline from "node:readline";
import * as url from "node:url";

import type { Ann, Body, Book, Ctx, HTerm, LTerm, Patt, Quant, Span, TLD } from "bend2/bend.ts";
import type * as BendModule from "bend2/bend.ts";

import pkg from "../../package.json" with { type: "json" };
import {
  getBendCli,
  getBendLintCacheDir,
  getBendVersionNote,
  getClang,
  JAVASCRIPT_NOTE,
  PINNED_BEND_NOTE,
  tryGetBend2SourceUrl,
} from "../shared/bend2.ts";
import { unwrap } from "../shared/result.ts";
import {
  getCommandOutcome,
  getErrorMessageFromUnknown,
  getPathWithForwardSlashes,
  getSha256Hex,
  tryGet,
  tryGetJson,
  tryWriteJsonAtomically,
  writeFileAtomically,
  writeNewFileAtomically,
} from "../shared/utils.ts";

// Types
// =====

type Bend = typeof BendModule;

type Loaded = { Bend: Bend; base: Book };

// What a check's answer depends on besides its files (this server, the patched bend.ts and Base,
// as one digest), and Bend, loaded when a check or a question first needs it: an answer from the
// cache needs none.
type Checker = { version: string; getLoaded: () => Promise<Loaded> };

// A check's answer as the cache keeps it, with 0 for its number: the files it read, each with the
// digest of the text it read, the answer's digest, and how many types it names.
type Entry = { files: Array<[string, string]>; answer: string; digest: string; types: number };

// The facts a check gives: none, or those of the files at `paths` (all, if none).
type Wanted = { paths: string[] } | undefined;

// What checking a file gives: its answer, numbered 0 if it passed, each file it read, with the
// text it read, and, if it passed, what it holds.
type Made = { answer: string; read: Array<[string, string]>; held?: Held };

// A passed check this server numbered: its cache entry, its root, the facts it gives, its answer's
// digest (numbered 0) and how many types its answer names, enough to check it again with the same
// handles; what it holds, while a question may read it (a question about a check that holds
// nothing checks it again); and its memo, once a question looks for one.
type Answered = {
  file: string;
  path: string;
  facts: Wanted;
  digest: string;
  types: number;
  held?: Held;
  memo?: Memo;
};

// The answers to questions about a check's types, by question with its checks numbered 0, kept
// beside its cache entry (`digest` is the entry's): a later run that asks them checks nothing
// again.
type Memo = { digest: string; answers: Record<string, string> };

// An exact edit of bend.ts: the text it must find once, and its replacement.
type Edit = [string, string];

type Traced = (...args: unknown[]) => unknown;

// What a TRACED function calls instead of itself: its original, and its arguments.
type Hook = (f: Traced, args: unknown[]) => unknown;

// What the server shares with its copy of bend.ts on globalThis: the fs and path the copy uses,
// and, once the copy loads, its setter of hooks.
type Shared = { fs: object; path: object; setHook?: (name: string, hook?: Hook) => void };

// A traced call that a Frame KEPT: its name, arguments and result, where the parser is after it
// (-1 if it failed, or has no parser), and the calls it made that it KEPT.
type Frame = { name: string; args: unknown[]; out: unknown; end: number; kids: Frame[] };

// What the checker passed a judgment, by the term it gave back: the demand on the term, its
// context and depth, and how often each binder it closed (by level) was used.
type Judgment = Scope & { qt: Quant; used: ReadonlyArray<[number, Quant]> };

// The binders around a type: the checker's context, and its depth.
type Scope = { ctx: Ctx; dep: number };

type File = Span["file"];

// A type a fact names (a Lint.TypeRef's handle points at one): the type, the scope it is in, and
// the file whose aliases spell it.
type Typed = Scope & { ty: HTerm; file: File };

// A check this server holds, for the questions about it: its book, the types its answer and its
// questions named so far (by handle), and the binder node of each context entry its facts' walk
// met (`same` tells binders apart by it).
type Held = { bok: Book; types: Typed[]; binders: Map<Ann, number> };

// What a syntax node is (Lint.Syntax).
type Syntax = keyof typeof TAGS;

// A syntax node (Lint.Node), with what only nodes of its kind have (see Lint.Syntax), and what
// reading facts uses: a number of its own, the span the parser read it at (its origin), for a
// variable the node that declares its binder, the facts on it so far, and how often its body uses
// the binder it declares (the most of its checked copies).
type Tree = {
  id: number;
  syntax: Syntax;
  name: string;
  range: [number, number] | undefined;
  kids: Tree[];
  target?: string;
  binder?: number;
  quantity?: string;
  unsafe?: boolean;
  origin: Span | undefined;
  declarer?: Tree;
  notes: Note[];
  used?: Quant;
};

// A fact on a node: what of the node (its term's type, or the type its binder declares), the type,
// and the quantity (how often the term is demanded, or the binder's).
type Note = { role: "t" | "b"; type: Typed; quantity: Quant };

// A file the check parsed: its path, its text on disk and as its parser read it (with its import
// lines blank), its namespace and its import aliases (in order), the parser that read its
// declarations, the loads of its imports, and the calls that parsed its declarations.
type Parsed = {
  path: string;
  text: string;
  read: string;
  ns: string;
  aliases: string[];
  parser: unknown;
  loads: Frame[];
  frames: Frame[];
};

// Where the spans a file's parser made are on disk: the parser, the text on disk, and, for an
// offset the parser read, where it is on disk in UTF-16 units; and, for one of those, in code
// points.
type Placer = {
  parser: unknown;
  text: string;
  getUnit: (off: number) => number;
  getPoint: (unit: number) => number;
};

// What building one declaration's trees reads: its file's placer, the check's declarations and
// constructors, and the spans that references own so far (see `getReference`).
type Builder = { at: Placer; book: Book; owned: Set<string> };

// A binder of a telescope, as the parser reads it: its quantity, name, level, type and span.
type Cell = [Quant, string, number, LTerm, Span];

// What bend-lint.json says of its rules: the ids of those it turns on, and the BendHub packages
// that rules come from, names to versions.
type Rules = { ids: string[]; packages: Map<string, string> };

// Constants
// =========

const ESCAPES: Record<string, string> = { "\\": "\\\\", "\t": "\\t", "\n": "\\n" };

const SERVER_CACHE_DIR = new URL("server/", getBendLintCacheDir());

const CHECKS_DIR = url.fileURLToPath(new URL("checks/", SERVER_CACHE_DIR));

const PROGRAMS_DIR = url.fileURLToPath(new URL("programs/", SERVER_CACHE_DIR));

// Where the programs bend-lint writes (one per list of rules) live: Bend imports only relative
// paths of plain names, so they live beside cli.bend, which they import.
export const BUILD = url.fileURLToPath(new URL("build/", import.meta.url));

// The config, and the folder of rules beside it.
const CONFIG = "bend-lint.json";
const RULES = "bend-lint-rules";

// The rule API, as rules import it from BendHub: src/linter/lint.bend and the files it imports, at
// their paths from src/, in the package bend-lint-api, at bend-lint's version (see ship.ts).
export const API = `bend-lint-api@${pkg.version}.0`;

// bend-lint's own rules, as projects get them from BendHub, at bend-lint's version: each at its
// path from bend-lint-rules/ (see ship.ts).
export const DEFAULTS = `bend-lint-rules@${pkg.version}.0`;

// A path Bend imports: up, then names (letters, digits, _ and -).
const PLAIN = /^(\.\.\/)*([A-Za-z_][\w-]*\/)*[A-Za-z_][\w-]*\.bend$/;

// Why bend-lint cannot reach a project's rules.
const PER_PROJECT =
  "install bend-lint in this project (bun add -D bend-lint): Bend imports files only by relative paths of plain names, so bend-lint cannot reach your rules from elsewhere";

// What `bend-lint init` writes: a config that turns on the formatter, and the formatter's rule,
// which uses bend-lint's own.
const INIT_CONFIG = `{\n  "rules": {\n    "format": "warning"\n  }\n}\n`;
const INIT_FORMAT =
  "# format: bend-lint's formatter (layout/format). Its options go in bend-lint.json; see\n" +
  "# bend-lint's README.\n" +
  "import Base\n" +
  `import ${API}/linter/lint.bend as Lint\n` +
  `import ${DEFAULTS}/layout/format.bend as Format\n\n` +
  "def rule() -> Lint.Rule:\n" +
  "  Format.rule()\n";

// An import by a relative path: of a .bend file, or, quoted, of an effect's.
export const IMPORT = /^\s*import\s+"?(\.\.?\/[^\s"]+)/gm;

// A drive letter that starts a path with `/`.
const DRIVE = /^[A-Za-z]:(?=\/)/;

// A name as a file writes it: `[A-Za-z_]`, then `[A-Za-z0-9_.]`.
const NAME = /^[A-Za-z_][\w.]*/;

// The edits that make bend.ts use the fs and path the server Shares. The copy is never
// type-checked, so it needs no types.
const EDITS: Edit[] = [
  ['import * as fs from "node:fs";', "const { fs } = globalThis.BEND_LINT;"],
  ['import * as path from "node:path";', "const { path } = globalThis.BEND_LINT;"],
];

// The functions of bend.ts whose calls the server sees while Bend loads a check's files: those that
// load a file, parse what it declares and build a law's type.
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

// The functions of bend.ts whose calls the server sees while Bend checks, for facts: those that
// judge a term and close a binder.
const JUDGED = ["term_infer", "term_check", "uses_close"] as const;

const TRACED = [...PARSED, ...JUDGED];

// The traced calls a Frame keeps, by the function that made them: a check loads a file, which
// loads its imports and parses its declarations, each with its name, binders, types and body.
const KEPT: Record<string, ReadonlySet<string> | undefined> = {
  check: new Set(["book_load"]),
  book_load: new Set(["book_load", "parse_book"]),
  parse_book: new Set(["parse_def", "parse_fresh", "parse_tele", "parse_term", "term_higher"]),
  parse_def: new Set(["parse_fresh", "parse_reso", "parse_tele", "parse_term", "parse_body"]),
};

// The tag an answer writes for each kind of node (Syntax.of in cli.bend reads them).
const TAGS = {
  Import: "I",
  ImportPath: "i",
  Definition: "D",
  Datatype: "T",
  Constructor: "C",
  Law: "W",
  Parameter: "p",
  Field: "f",
  Returns: "R",
  Body: "B",
  Variable: "v",
  Reference: "r",
  Substitution: "s",
  Let: "l",
  Binding: "b",
  Sort: "S",
  QuantityType: "q",
  QuantityLiteral: "Q",
  QuantityMinimum: "m",
  Forall: "F",
  Lambda: "L",
  Application: "A",
  TypeApplication: "t",
  Construction: "c",
  Literal: "n",
  Elimination: "E",
  Absurd: "a",
  Equality: "e",
  Reflexivity: "y",
  Rewrite: "w",
  Hole: "h",
  Annotation: "N",
  Match: "M",
  Case: "k",
  Destructure: "d",
  PatternVariable: "x",
  PatternConstructor: "X",
} as const;

// The kind of node each kind of term makes; but a variable can name a global (see `getTermTree`),
// and the applications at one span make one call (see `getApplication`).
const KINDS: Record<LTerm["$"], Syntax> = {
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

// The kinds of node that declare a binder.
const BINDS: ReadonlySet<Syntax> = new Set([
  "Parameter",
  "Field",
  "PatternVariable",
  "Lambda",
  "Forall",
  "Binding",
]);

const NONE: ReadonlySet<string> = new Set();

// The uses of each judgment that closes no binder, most of them: one array for all.
const UNCLOSED: ReadonlyArray<[number, Quant]> = [];

const HOOKED = new Map<string, Hook | undefined>();

// What bend.ts gets appended: a setter, Shared on globalThis, that points a TRACED function at a
// hook, or back at its original. A function a module declares is a binding the module can set, so
// each call in bend.ts goes through the hook, and a function without one runs as it is.
const PROBES = `
const BEND_LINT_ORIGINALS = { ${TRACED.join(", ")} };
globalThis.BEND_LINT.setHook = (name, hook) => {
  switch (name) {
${TRACED.map(
  (name) => `    case "${name}":
      ${name} = hook === undefined ? BEND_LINT_ORIGINALS.${name} : (...args) => hook(BEND_LINT_ORIGINALS.${name}, args);
      return;`,
).join("\n")}
  }
};
`;

// The text of each file bend.ts read while the check that runs read it, by the path it read.
const READS = new Map<string, string>();

// The texts that `--overlays` gives on stdin, by their files' keys (see `getOverlayKey`): a check
// reads each in place of its file, which need not be on disk.
const OVERLAYS = new Map<string, string>();

// How many syntax nodes the server made: the next one's number.
const MADE = { nodes: 0 };

// A number for each file a span of the check that runs is in.
const FILES = new Map<unknown, number>();

// The passed checks this server numbered, by number (from 1), and the number of each by its cache
// entry: the requests of one entry share one check.
const ANSWERED: Answered[] = [];
const NUMBERS = new Map<string, number>();

const STALE = 7 * 24 * 60 * 60 * 1000;

// Touching an executable makes a virus scanner check it again before it runs (about 0.2 s on
// Windows), so not on every run.
const USED = 24 * 60 * 60 * 1000;

// A prune stats each entry of its folder (about 0.1 s for 9000 entries), so not on every run.
const PRUNE_EVERY = 24 * 60 * 60 * 1000;

// Functions
// =========

const getEscapedField = (text: string): string => text.replace(/[\\\t\n]/g, (c) => ESCAPES[c]);

const getUnescapedField = (text: string): string =>
  text.replace(/\\(.)/g, (_, c: string) => (c === "t" ? "\t" : c === "n" ? "\n" : c));

const getRecord = (fields: string[]): string => fields.map(getEscapedField).join("\t") + "\n";

// A fresh book that holds Base, as main.ts's book_seed makes it: in book_nil's tables, which have
// no prototype, so a name such as `toString` is free.
const getSeededBook = (Bend: Bend, base: Book): Book => {
  const book = Bend.book_nil();
  for (const [k, tld] of Object.entries(base.tlds)) {
    book.tlds[k] = { ...tld };
  }
  Object.assign(book.ctrs, base.ctrs);
  for (const [k, m] of Object.entries(base.tmps)) {
    book.tmps[k] = new Map(m);
  }
  book.order.push(...base.order);
  return book;
};

// bend.ts with EDITS made in order and PROBES appended, and BEND_DIR kept at `dir`, so the copy
// finds base.bend where the original does: `true ? dir :` puts Bend's own expression in a branch
// that never runs. Each edit's first string, and each TRACED function, must occur once in the text
// the edits before it left. Line ends become LF first.
const getPatchedText = (dir: string, src: string): string =>
  (
    [
      ...EDITS,
      ...TRACED.map((name): Edit => [`function ${name}(`, `function ${name}(`]),
      ["export const BEND_DIR = ", `export const BEND_DIR = true ? ${JSON.stringify(dir)} : `],
    ] as Edit[]
  ).reduce(
    (out, [at, to]) => {
      const n = out.split(at).length - 1;
      if (n !== 1) {
        throw new Error(
          `bend.ts has ${n} of ${JSON.stringify(at)}, not 1; update EDITS, TRACED or KEPT in src/linter/seam.ts`,
        );
      }
      return out.replace(at, () => to);
    },
    src.replace(/\r\n/g, "\n"),
  ) + PROBES;

// The patched copy of the bend.ts in `dir`, written once to the cache.
const getPatchedCopy = (dir: URL): URL => {
  const text = getPatchedText(
    getPathWithForwardSlashes(url.fileURLToPath(dir)),
    nodeFs.readFileSync(new URL("bend.ts", dir), "utf8"),
  );
  const file = new URL(`${getSha256Hex(text).slice(0, 16)}/bend.ts`, SERVER_CACHE_DIR);
  writeNewFileAtomically(url.fileURLToPath(file), text);
  return file;
};

const getRealPath = (p: nodeFs.PathLike): string =>
  getPathWithForwardSlashes(nodeFs.realpathSync(p));

// The path of a file as Bend names it once it loads it: its folder's real path, with `/`, then its
// name; or, if its folder is not on disk, its absolute path.
const getOverlayKey = (p: string): string => {
  const absolute = nodePath.resolve(p);
  const folder = nodePath.dirname(absolute);
  return (
    (tryGet(() => getRealPath(folder)) ?? getPathWithForwardSlashes(folder)).replace(/\/$/, "") +
    "/" +
    nodePath.basename(absolute)
  );
};

const getOverlay = (p: nodeFs.PathOrFileDescriptor): string | undefined =>
  OVERLAYS.size === 0 || typeof p === "number" ? undefined : OVERLAYS.get(getOverlayKey(String(p)));

// The text of the file at `p`, as the run sees it: its overlay, or what is on disk.
const getViewText = (p: string): string => getOverlay(p) ?? nodeFs.readFileSync(p, "utf8");

// path.posix.resolve, where a drive letter is a root.
const getResolvedPosixPath = (...ps: string[]): string => {
  const all = [process.cwd(), ...ps].map(getPathWithForwardSlashes);
  const drive =
    all
      .filter((p) => DRIVE.test(p))
      .at(-1)
      ?.slice(0, 2) ?? "";
  return drive + nodePath.posix.resolve(...all.map((p) => p.replace(DRIVE, "")));
};

const getRelativePosixPath = (from: string, to: string): string =>
  nodePath.posix.relative(
    getPathWithForwardSlashes(from).replace(DRIVE, ""),
    getPathWithForwardSlashes(to).replace(DRIVE, ""),
  );

// Node's readFileSync, which reads a file's overlay in its place, and keeps in READS each text it
// reads.
const getKeptRead = ((p: nodeFs.PathOrFileDescriptor, options?: unknown) => {
  const read = getOverlay(p) ?? nodeFs.readFileSync(p, options as BufferEncoding);
  if (typeof read === "string") {
    READS.set(String(p), read);
  }
  return read;
}) as typeof nodeFs.readFileSync;

// What the server Shares with its copy of bend.ts: Node's fs and path, with each path they give
// real and with `/`, as Bend resolves imports with path.posix, where a drive letter is a root; each
// text Bend reads kept; and each file with an overlay there, as its key.
const getShared = (): Shared => ({
  fs: {
    ...nodeFs,
    existsSync: (p: nodeFs.PathLike): boolean =>
      getOverlay(String(p)) !== undefined || nodeFs.existsSync(p),
    realpathSync: (p: nodeFs.PathLike): string =>
      getOverlay(String(p)) === undefined ? getRealPath(p) : getOverlayKey(String(p)),
    readFileSync: getKeptRead,
  },
  path: {
    ...nodePath,
    join: (...ps: string[]): string => getPathWithForwardSlashes(nodePath.join(...ps)),
    resolve: (...ps: string[]): string => getPathWithForwardSlashes(nodePath.resolve(...ps)),
    posix: { ...nodePath.posix, resolve: getResolvedPosixPath, relative: getRelativePosixPath },
  },
});

// The checker of the bend2 sources in `dir`. The patched bend.ts is written now, so a drift stops
// the run at once; Bend loads, and checks Base, once, when first needed.
const getChecker = (dir: URL): Checker => {
  const bend = getPatchedCopy(dir);
  let loading: Promise<Loaded> | undefined;
  return {
    version: getSha256Hex(
      [
        nodeFs.readFileSync(url.fileURLToPath(import.meta.url), "utf8"),
        bend.href,
        nodeFs.readFileSync(new URL("base.bend", dir), "utf8"),
      ].join("\n"),
    ),
    getLoaded: () =>
      (loading ??= (async () => {
        (globalThis as { BEND_LINT?: Shared }).BEND_LINT = getShared();
        const Bend = (await import(bend.href)) as Bend;
        const base = Bend.book_nil();
        await Bend.book_load(base, Bend.BASE_BEND, "", new Map());
        Bend.book_valid(base, 0);
        return { Bend, base };
      })()),
  };
};

// Points the TRACED function `name` at `hook`, or back at its original. A binding bend.ts sets is
// code JSC compiles again, so one that would not change is left alone.
const setHook = (name: string, hook?: Hook): void => {
  if (HOOKED.get(name) !== hook) {
    HOOKED.set(name, hook);
    (globalThis as { BEND_LINT?: Shared }).BEND_LINT?.setHook?.(name, hook);
  }
};

const untrace = (): void => {
  TRACED.forEach((name) => setHook(name));
};

// While Bend loads a check's files: keeps under `root` each call a Frame KEPT. Only the calls the
// Frame on top keeps are hooked, so every other call runs as it is: the stack sets the hooks as it
// grows and shrinks.
const traceParsing = (root: Frame): void => {
  const stack = [root];
  let hooked = NONE;
  const focus = (): void => {
    const keeps = KEPT[stack[stack.length - 1].name] ?? NONE;
    PARSED.forEach((name) => {
      if (hooked.has(name) !== keeps.has(name)) {
        setHook(name, keeps.has(name) ? (f, args) => getKeptCall(name, f, args) : undefined);
      }
    });
    hooked = keeps;
  };
  const getKeptCall = (name: string, f: Traced, args: unknown[]): unknown => {
    const p = args[0] as { pos?: number };
    const frame: Frame = { name, args, out: undefined, end: -1, kids: [] };
    const getKeptOut = (out: unknown): unknown => {
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
      return out instanceof Promise ? out.then(getKeptOut, fail) : getKeptOut(out);
    } catch (e) {
      return fail(e);
    }
  };
  focus();
};

// While Bend checks: keeps in `judgments` what the checker passes each judgment. A binder's uses
// are those its judgment closed, after the judgments inside it took theirs. A judgment can give
// back the term of one inside it (an annotation's, say): the inner one made it, so it keeps it.
const traceJudgments = (Bend: Bend, judgments: Map<LTerm, Judgment>): void => {
  const closed: Array<[number, Quant]> = [];
  const getJudged = (f: Traced, args: unknown[], qt: Quant, ctx: Ctx, dep: number): unknown => {
    const mark = closed.length;
    try {
      const judged = f(...args) as { tm: LTerm };
      if (!judgments.has(judged.tm)) {
        const used = closed.length === mark ? UNCLOSED : closed.slice(mark);
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
      return getJudged(f, args, qt, ctx, dep);
    },
    term_check: (f, args) => {
      const [, , , qt, , ctx, dep] = args as Parameters<Bend["term_check"]>;
      return getJudged(f, args, qt, ctx, dep);
    },
    uses_close: (f, args) => {
      const [, , us, i] = args as Parameters<Bend["uses_close"]>;
      closed.push([i, Bend.pmap_get(us, i) ?? Bend.None()]);
      return f(...args);
    },
  };
  JUDGED.forEach((name) => setHook(name, hooks[name]));
};

const isFile = (o: unknown): o is File =>
  typeof o === "object" && o !== null && "str" in o && "ns" in o && "al" in o;

const isSpan = (o: object): o is Span => "file" in o && "beg" in o && "end" in o;

// A key of a span's value: its file, start and end.
const getSpanKey = (s: Span): string =>
  (FILES.get(s.file) ?? FILES.set(s.file, FILES.size).size - 1) + ":" + s.beg + ":" + s.end;

const isSameSpan = (a: Span | undefined, b: Span | undefined): boolean =>
  a === b ||
  (a !== undefined && b !== undefined && a.file === b.file && a.beg === b.beg && a.end === b.end);

// The quantity an answer writes (Quantity.of in cli.bend reads it): erased, once or many.
const getQuantityLetter = (q: Quant): string => (q.$ === "None" ? "e" : q.$ === "Lone" ? "o" : "m");

// The most of two quantities, as the checker joins uses.
const getJoinedQuantity = (a: Quant, b: Quant): Quant =>
  b.$ === "Many" ? b : a.$ === "Many" ? a : a.$ === "None" ? b : a;

// Files
// -----

// The files that the loads among `frames` parsed, onto `out`, in the order Bend parsed them: a
// file's imports first. A load of a file loaded before parses nothing. A file's text on disk is the
// text its imports' spans are in: a file with no imports is read as it is.
const getParsedFiles = (frames: Frame[], out: Parsed[]): Parsed[] => {
  frames
    .filter((load) => load.name === "book_load")
    .forEach((load) => {
      getParsedFiles(load.kids, out);
      const book = load.kids.find((f) => f.name === "parse_book");
      if (book !== undefined) {
        const loads = load.kids.filter((f) => f.name === "book_load");
        const read = book.args[2] as string;
        out.push({
          path: load.args[1] as string,
          text: (loads[0]?.args[4] as Span | undefined)?.file.str ?? read,
          read,
          ns: book.args[3] as string,
          aliases: Object.keys(book.args[4] as object),
          parser: book.kids.find((f) => isFile(f.args[0]))?.args[0],
          loads,
          frames: book.kids,
        });
      }
    });
  return out;
};

// The starts of the lines of `text`, in UTF-16 units.
const getLineStarts = (text: string): number[] => [
  0,
  ...Array.from(text.matchAll(/\n/g), (m) => m.index + 1),
];

// How many of `xs`, ascending, are below `x`.
const getCountBelow = (xs: number[], x: number): number => {
  let [lo, hi] = [0, xs.length];
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    [lo, hi] = xs[mid] < x ? [mid + 1, hi] : [lo, mid];
  }
  return lo;
};

// The placer of a parsed file: its parser reads it with its import lines blank, so an offset it
// read is on disk at the same place of the same line.
const getPlacer = (file: Parsed): Placer => {
  const read = getLineStarts(file.read);
  const disk = getLineStarts(file.text);
  const astral = Array.from(file.text.matchAll(/[\u{10000}-\u{10FFFF}]/gu), (m) => m.index);
  return {
    parser: file.parser,
    text: file.text,
    getUnit: (off) => {
      const line = getCountBelow(read, off + 1) - 1;
      return disk[line] + off - read[line];
    },
    getPoint: (unit) => unit - getCountBelow(astral, unit),
  };
};

// Where a span is written on disk, in code points, if the file's parser made it.
const getRange = (at: Placer, s: Span | undefined): [number, number] | undefined =>
  s === undefined || s.file !== at.parser
    ? undefined
    : [at.getPoint(at.getUnit(s.beg)), at.getPoint(at.getUnit(s.end))];

// The text on disk from where the file's parser made `s` start to the end of its line.
const getRestOfLine = (at: Placer, s: Span): string => {
  const from = at.getUnit(s.beg);
  const end = at.text.indexOf("\n", from);
  return at.text.slice(from, end < 0 ? undefined : end);
};

// The name a span starts with, as the file writes it there; "" for none.
const getWrittenName = (at: Placer, s: Span | undefined): string =>
  s === undefined || s.file !== at.parser ? "" : (NAME.exec(getRestOfLine(at, s))?.[0] ?? "");

// The text of a span on disk, up to the end of its first line.
const getSpanText = (at: Placer, s: Span): string => {
  const r = getRange(at, s);
  return r === undefined
    ? ""
    : Array.from(getRestOfLine(at, s))
        .slice(0, r[1] - r[0])
        .join("");
};

// Trees
// -----

const getTree = (
  syntax: Syntax,
  name: string,
  range: [number, number] | undefined,
  origin: Span | undefined,
  kids: Tree[],
  more: Partial<Tree> = {},
): Tree => ({ id: MADE.nodes++, syntax, name, range, kids, origin, notes: [], ...more });

// The last part of a global name: after its last `.` or `:`.
const getLastPart = (name: string): string => name.split(/[.:]/).at(-1) ?? "";

// A reference to `k` at `s`, written there if the span spells it (a name of `k`, or an operator)
// and no reference of the declaration owns the span yet: a copy of one is the parser's.
const getReference = (b: Builder, k: string, s: Span | undefined): Tree => {
  const name = getWrittenName(b.at, s);
  if (
    s === undefined ||
    b.owned.has(getSpanKey(s)) ||
    (name !== "" && getLastPart(name) !== getLastPart(k))
  ) {
    return getTree("Reference", "", undefined, s, [], { target: k });
  }
  b.owned.add(getSpanKey(s));
  return getTree("Reference", name === "" ? getSpanText(b.at, s) : name, getRange(b.at, s), s, [], {
    target: k,
  });
};

// A use of the global name `k` at `s`, with its name as written.
const getUse = (b: Builder, syntax: Syntax, k: string, s: Span | undefined, kids: Tree[]): Tree =>
  getTree(syntax, getWrittenName(b.at, s), getRange(b.at, s), s, kids, { target: k });

const getQuantityFields = (q: Quant | undefined): Partial<Tree> =>
  q === undefined ? {} : { quantity: getQuantityLetter(q) };

// A call at `s`: the applications at one span are one call (`f(a, b)`, `a + b`), built as its
// arguments, then its head. A call whose head shares its span is sugar: written (`A & B`,
// `return x`) if it spans its written parts and no other part shares its span; else the parser's
// (a do-block's bind).
const getApplication = (b: Builder, t: Extract<LTerm, { $: "App" }>): Tree => {
  const args = [t.x];
  let head = t.f;
  while (t.s !== undefined && head.$ === "App" && isSameSpan(head.s, t.s)) {
    args.unshift(head.x);
    head = head.f;
  }
  const kids = args.map((x) => getTermTree(b, x));
  const h = getTermTree(b, head);
  const at = getRange(b.at, t.s);
  const written =
    !isSameSpan(h.origin, t.s) ||
    kids.every(
      (k) =>
        !isSameSpan(k.origin, t.s) &&
        (k.range === undefined || (at !== undefined && at[0] <= k.range[0] && k.range[1] <= at[1])),
    );
  return getTree("Application", "", written ? at : undefined, t.s, [h, ...kids]);
};

// The terms right under a term, in order, as the checker walks them: none under a variable (a value
// it has is a substitution's), and only the term an annotation annotates.
const getSubterms = (t: LTerm): LTerm[] => {
  switch (t.$) {
    case "Sub":
      return [t.f];
    case "Let":
      return [...t.v, t.f];
    case "Typ":
      return [t.g];
    case "Min":
      return [t.a, t.b];
    case "All":
      return [t.A, t.B];
    case "Lam":
      return [t.f];
    case "App":
      return [t.f, t.x];
    case "ADT":
    case "Ctr":
      return t.x;
    case "Mat":
      return [t.h, t.m];
    case "Eql":
      return [t.a, t.b, t.T];
    case "Rwt":
      return [t.e, t.p, t.f];
    case "Ann":
      return [t.x];
    default:
      return [];
  }
};

// The trees of the terms right under `t`.
const getKids = (b: Builder, t: LTerm): Tree[] => getSubterms(t).map((x) => getTermTree(b, x));

// The tree of a term, as the parser read it.
const getTermTree = (b: Builder, t: LTerm): Tree => {
  const at = getRange(b.at, t.s);
  switch (t.$) {
    case "Var":
      return t.v === undefined
        ? getTree("Variable", t.k, at, t.s, [], { binder: t.i })
        : getReference(b, t.v.$ === "Ref" ? t.v.k : "", t.s);
    case "Ref":
      return getReference(b, t.k, t.s);
    case "Sub":
      return getTree("Substitution", "", at, t.s, [getPatternTree(b, t.v), getTermTree(b, t.f)]);
    case "Let":
      return getTree("Let", "", at, t.s, [
        ...t.k.map((k, n) =>
          getTree("Binding", k, undefined, t.s, [getTermTree(b, t.v[n])], {
            binder: t.i[n],
            quantity: getQuantityLetter(t.q[n]),
          }),
        ),
        getTermTree(b, t.f),
      ]);
    case "Qua":
      return getTree("QuantityLiteral", "", at, t.s, [], getQuantityFields(t.q));
    case "All":
      return getTree("Forall", t.k, at, t.s, getKids(b, t), {
        binder: t.i,
        ...getQuantityFields(t.q),
      });
    case "Lam":
      return getTree(
        "Lambda",
        t.k,
        getWrittenName(b.at, t.s) === t.k ? at : undefined,
        t.s,
        getKids(b, t),
        { binder: t.i, ...getQuantityFields(t.q) },
      );
    case "App":
      return getApplication(b, t);
    case "ADT":
    case "Ctr":
      return getUse(b, KINDS[t.$], t.k, t.s, getKids(b, t));
    case "Lit":
      return getTree("Literal", String(t.v), at, t.s, [], { target: t.k });
    case "Mat":
      return getTree("Elimination", "", at, t.s, getKids(b, t), { target: t.k });
    case "Hol":
      return getTree("Hole", t.k, at, t.s, []);
    case "Ann":
      return getTree("Annotation", "", at, t.s, [getTermTree(b, t.x), getTermTree(b, t.T)]);
    default:
      return getTree(KINDS[t.$], "", at, t.s, getKids(b, t));
  }
};

const getPatternTree = (b: Builder, p: Patt): Tree =>
  p.$ === "PVar"
    ? getTree("PatternVariable", p.k, getRange(b.at, p.s), p.s, [], {
        binder: p.i,
        quantity: getQuantityLetter(p.q),
      })
    : getUse(
        b,
        "PatternConstructor",
        p.k,
        p.s,
        p.x.map((x) => getPatternTree(b, x)),
      );

// The tree of a def's body, before it is lowered: a match, a destructuring let, or a term.
const getBodyTree = (b: Builder, x: Body): Tree => {
  if (x.$ === "Match") {
    return getTree("Match", "", getRange(b.at, x.s), undefined, [
      ...x.e.map((e) => getTermTree(b, e)),
      ...x.r.map((c) =>
        getTree("Case", "", undefined, undefined, [
          ...c.p.map((p) => getPatternTree(b, p)),
          getBodyTree(b, c.f),
        ]),
      ),
    ]);
  }
  if (x.$ === "Local") {
    return getTree(
      "Destructure",
      "",
      undefined,
      undefined,
      [
        ...x.k.map((p) => getPatternTree(b, p)),
        ...x.v.map((v) => getTermTree(b, v)),
        getBodyTree(b, x.f),
      ],
      getQuantityFields(x.q),
    );
  }
  return getTermTree(b, x);
};

// The binders of a telescope, closed by `close` (a type's fields are in braces), each over the
// tree of its type; `templates` take `~`.
const getTelescopeTrees = (b: Builder, close: string, templates: string[], tele: Cell[]): Tree[] =>
  tele.map(([q, k, i, T, s]) => {
    const kid = getTermTree(b, T);
    return getTree(close === "}" ? "Field" : "Parameter", k, getRange(b.at, s), s, [kid], {
      binder: i,
      quantity: templates.includes(k) ? "t" : getQuantityLetter(q),
    });
  });

const getTreeOver = (syntax: Syntax, kid: Tree): Tree =>
  getTree(syntax, "", undefined, undefined, [kid]);

// Whether a kept call of the parser's is a declared name read, which ends where the parser is
// after it.
const isHead = (f: Frame): boolean =>
  (f.name === "parse_fresh" || f.name === "parse_reso") && f.end >= 0 && typeof f.out === "string";

// What a declaration's calls build: a telescope's binders, its return type, or its body.
const getDeclarationParts = (b: Builder, frames: Frame[]): Tree[] =>
  frames.flatMap((f) =>
    f.end < 0
      ? []
      : f.name === "parse_tele"
        ? getTelescopeTrees(
            b,
            f.args[1] as string,
            (f.args[2] as string[] | undefined) ?? [],
            f.out as Cell[],
          )
        : f.name === "parse_term"
          ? [getTreeOver("Returns", getTermTree(b, f.out as LTerm))]
          : f.name === "parse_body"
            ? [getTreeOver("Body", getBodyTree(b, f.out as Body))]
            : [],
  );

// The declaration of what `syntax` is that a name read at `head` starts, over `kids`.
const getDeclarationAt = (b: Builder, syntax: Syntax, head: Frame, kids: Tree[]): Tree => {
  const written = head.args[1] as string;
  const target = head.out as string;
  const tld = b.book.tlds[target] as TLD | undefined;
  return getTree(
    syntax,
    written,
    getRange(b.at, { file: head.args[0] as File, beg: head.end - written.length, end: head.end }),
    undefined,
    kids,
    { target, unsafe: syntax === "Definition" && tld?.$ === "Def" && tld.u === true },
  );
};

// The declaration a file's calls from `head` on make: a def at the last name it reads; a
// constructor; a type; or a law, whose signature is the type Bend builds from its clauses.
const getDeclarationTrees = (b: Builder, [head, ...frames]: Frame[]): Tree[] => {
  if (head.name === "parse_def") {
    const name = head.kids.filter(isHead).at(-1);
    return name === undefined
      ? []
      : [getDeclarationAt(b, "Definition", name, getDeclarationParts(b, head.kids))];
  }
  const syntax: Syntax =
    head.name === "parse_fresh" && head.args[2] === b.book.ctrs
      ? "Constructor"
      : b.book.tlds[head.out as string]?.$ === "ADT"
        ? "Datatype"
        : "Law";
  const higher = frames.filter((f) => f.name === "term_higher").at(-1);
  return [
    getDeclarationAt(
      b,
      syntax,
      head,
      syntax !== "Law"
        ? getDeclarationParts(b, frames)
        : higher === undefined
          ? []
          : [getTreeOver("Returns", getTermTree(b, higher.args[0] as LTerm))],
    ),
  ];
};

// The imports of a file, each with its alias (Bend gives one to each import but `import Base`, in
// order) and the file it loads, with the path it writes; Base's writes none.
const getImportTrees = (file: Parsed, at: Placer): Tree[] => {
  const aliases = [...file.aliases];
  return file.loads.map((load) => {
    const target = load.args[1] as string;
    const unit = (load.args[4] as Span | undefined)?.beg ?? 0;
    const rest = file.text.slice(unit);
    const written = rest.split(/\s/, 1)[0];
    const from = at.getPoint(unit);
    const to = from + Array.from(written).length;
    if (written === "Base") {
      return getTree("Import", "Base", [from, to], undefined, [], { target });
    }
    const alias = aliases.shift() ?? "";
    const name = to + (/^\s+as\s+/.exec(rest.slice(written.length))?.[0].length ?? 0);
    return getTree(
      "Import",
      alias,
      [name, name + alias.length],
      undefined,
      [getTree("ImportPath", written, [from, to], undefined, [])],
      { target },
    );
  });
};

// The trees of a file: its imports, then its declarations, each constructor under its type. Each
// declaration's references own their spans apart (see `getReference`).
const getFileTrees = (file: Parsed, book: Book): Tree[] => {
  const at = getPlacer(file);
  const heads = file.frames.reduce<Frame[][]>((groups, f) => {
    if (f.name === "parse_def" || isHead(f)) {
      groups.push([f]);
    } else {
      groups.at(-1)?.push(f);
    }
    return groups;
  }, []);
  const tops = heads
    .flatMap((group) => getDeclarationTrees({ at, book, owned: new Set() }, group))
    .reduce<Tree[]>((out, t) => {
      if (t.syntax === "Constructor") {
        out.at(-1)?.kids.push(t);
      } else {
        out.push(t);
      }
      return out;
    }, []);
  return [...getImportTrees(file, at), ...tops];
};

// The nodes of `trees` and under them, parents first, onto `out`.
const getPreorder = (trees: Tree[], out: Tree[]): Tree[] => {
  trees.forEach((t) => {
    out.push(t);
    getPreorder(t.kids, out);
  });
  return out;
};

// Facts
// -----

// The first span the parser read of `x`, a term, as it walks it.
const getFirstSpan = (x: unknown): Span | undefined => {
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

// The namespace of the file that writes a declaration: of the file its checked body is read from
// (a law's fill is the filler's), else its type's, or its first constructor's.
const getWriterNamespace = (tld: TLD): string | undefined =>
  (tld.$ === "Def" && tld.e !== undefined
    ? getFirstSpan(tld.e)
    : [tld.T, ...(tld.$ === "ADT" ? tld.c.map((c) => c.T) : [])]
        .map((t) => (t.$ === "All" ? t.s : undefined))
        .find((t) => t !== undefined)
  )?.file.ns;

// The checker wraps each term of an elaborated body it returns in an annotation without a span,
// which holds the term's type; an annotation the source writes is gone by then.
const isTyping = (t: LTerm): t is Extract<LTerm, { $: "Ann" }> & { T: { v: HTerm } } =>
  t.$ === "Ann" && t.s === undefined && t.T.$ === "Var" && t.T.i < 0 && t.T.v !== undefined;

// A term without the checker's annotations.
const getBareTerm = (t: LTerm): LTerm => (isTyping(t) ? getBareTerm(t.x) : t);

// Whether each of `terms` was read at its place in `spans`.
const hasSameSpans = (terms: LTerm[], spans: Array<Span | undefined>): boolean =>
  terms.length === spans.length && terms.every((t, n) => isSameSpan(getBareTerm(t).s, spans[n]));

// The binder node of each entry of `scope`'s context, by level, as `same` tells them apart: the
// node the facts' walk found it is, else the entry itself.
const getBinders = (Bend: Bend, binders: Map<Ann, number>, { ctx, dep }: Scope): unknown[] =>
  Array.from({ length: dep }, (_, level) => {
    const entry = Bend.pmap_get(ctx, level) ?? undefined;
    return entry === undefined ? Symbol() : (binders.get(entry) ?? entry);
  });

// The deepest level a lowered type uses free (below `dep`), or -1.
const getDeepestLevel = (t: LTerm, dep: number): number => {
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

// Whether two types of one check are the same: equal by the checker, and each inside the levels
// their scopes share (the same binder at each, from the first): a type that uses a level past them
// names another variable there.
const isSameType = (Bend: Bend, held: Held, a: Typed, b: Typed): boolean => {
  const [x, y] = [getBinders(Bend, held.binders, a), getBinders(Bend, held.binders, b)];
  const shared = x.findIndex((v, n) => n >= y.length || v !== y[n]);
  const n = shared < 0 ? Math.min(x.length, y.length) : shared;
  const isInside = (t: Typed): boolean =>
    t.dep <= n || getDeepestLevel(Bend.term_lower(t.ty, t.dep), t.dep) < n;
  try {
    return (
      isInside(a) &&
      isInside(b) &&
      Bend.term_compare("EQ", held.bok, a.ty, b.ty, Math.max(a.dep, b.dep))
    );
  } catch {
    return false;
  }
};

// Puts on the nodes of a check what its checker found, from the declarations written in the
// `wanted` files (by namespace; all, if undefined): from each one's type (its binders, and its
// constructors'), then its checked body. A checked term is a node's if it was read at the node's
// span and has its kind and name, and, for a call or a construction, its children's spans; a
// variable must also name the node's binder. So a term the checker made from another (a pattern
// put for a scrutinee, a partial call, a list's tail) is no node's. A fact has the demand and scope
// the checker judged its term with. A lambda's or let's binder declares the type and quantity its
// entry in the scope of its body has, unless it is a parameter its signature declared (a law's fill
// takes the law's); it is used as often as its judgment closed it. Of a node's facts that the
// checker counts the same (same role, quantity and type), the first stays: pattern compilation
// checks one term in several branches.
const putFacts = (
  Bend: Bend,
  held: Held,
  own: string[],
  judgments: Map<LTerm, Judgment>,
  wanted: ReadonlySet<string | undefined> | undefined,
  tops: Tree[],
): void => {
  const { binders } = held;
  const origins = new Map<string, Tree[]>();
  for (const top of tops) {
    const mine = getPreorder([top], []);
    const declarers = new Map<number, Tree>();
    for (const o of mine) {
      if (o.binder !== undefined && BINDS.has(o.syntax)) {
        declarers.set(o.binder, o);
      }
    }
    for (const o of mine) {
      if (o.syntax === "Variable" && o.binder !== undefined) {
        o.declarer = declarers.get(o.binder);
      }
      if (o.origin !== undefined) {
        const key = getSpanKey(o.origin);
        const known = origins.get(key);
        if (known === undefined) {
          origins.set(key, [o]);
        } else {
          known.push(o);
        }
      }
    }
  }
  const getNodesAt = (s: Span | undefined): Tree[] =>
    s === undefined ? [] : (origins.get(getSpanKey(s)) ?? []);
  const getBinderNode = (s: Span | undefined, k: string): Tree | undefined =>
    getNodesAt(s).find((o) => BINDS.has(o.syntax) && o.name === k);
  const getEntry = (scope: Scope | undefined, level: number): Ann | undefined =>
    scope !== undefined && level < scope.dep
      ? (Bend.pmap_get(scope.ctx, level) ?? undefined)
      : undefined;
  const note = (o: Tree, role: Note["role"], ty: HTerm, scope: Scope, q: Quant, file: File) => {
    o.notes.push({ role, quantity: q, type: { ty, ctx: scope.ctx, dep: scope.dep, file } });
  };
  const getJudgment = (t: LTerm): Judgment | undefined =>
    judgments.get(t) ?? (isTyping(t) ? getJudgment(t.x) : undefined);
  const isNodeOf = (t: LTerm, scope: Scope, o: Tree): boolean => {
    switch (t.$) {
      case "Var": {
        const e = getEntry(scope, t.i);
        return (
          o.syntax === "Variable" &&
          o.name === t.k &&
          (o.declarer === undefined
            ? e === undefined
            : e !== undefined && binders.get(e) === o.declarer.id)
        );
      }
      case "Ref":
        return o.syntax === "Reference" && o.target === t.k;
      case "Lit":
        return o.syntax === "Literal" && o.name === String(t.v);
      case "Lam":
      case "All":
        return o.syntax === KINDS[t.$] && o.name === t.k;
      case "Ctr":
      case "ADT":
        return (
          o.syntax === KINDS[t.$] &&
          o.target === t.k &&
          hasSameSpans(
            t.x,
            o.kids.map((k) => k.origin),
          )
        );
      default:
        return o.syntax === KINDS[t.$];
    }
  };
  // Whether a call's head and arguments are the node's children, but the leading ones a
  // template's instance took as `~` arguments.
  const isNodeOfCall = (head: LTerm, args: LTerm[], o: Tree): boolean => {
    const rest = o.kids.slice(1).map((k) => k.origin);
    return (
      o.syntax === "Application" &&
      o.kids.length > 0 &&
      isSameSpan(head.s, o.kids[0].origin) &&
      (rest.length === args.length
        ? hasSameSpans(args, rest)
        : rest.length > args.length &&
          head.$ === "Ref" &&
          head.k.includes("~") &&
          hasSameSpans(args, rest.slice(rest.length - args.length)))
    );
  };
  // The binders a lambda or let at `s` declares at `levels`, judged `j`, each the node of its
  // entry in the scope of its body (judged `inner`) from now on, with its facts if `declares`.
  const declare = (
    s: Span | undefined,
    names: string[],
    levels: number[],
    j: Judgment | undefined,
    inner: Judgment | undefined,
    declares: boolean,
  ): void => {
    names.forEach((k, n) => {
      const o = getBinderNode(s, k);
      const e = getEntry(inner, levels[n]);
      if (o === undefined || e === undefined) {
        return;
      }
      binders.set(e, o.id);
      if (!declares || s === undefined || j === undefined) {
        return;
      }
      if (o.syntax !== "Parameter" || o.notes.length === 0) {
        note(o, "b", e.T, j, e.q, s.file);
      }
      const q = j.used.find(([l]) => l === levels[n])?.[1];
      if (q !== undefined) {
        o.used = o.used === undefined ? q : getJoinedQuantity(o.used, q);
      }
    });
  };
  // Puts on the nodes that `u` is the type the checker gave it, in the annotation it put over it,
  // judged as `u` was (else as the term above, judged `up`), and walks on: from a call (its
  // applications at one span, as `getApplication` reads them), to its head as the checker typed it,
  // then to its arguments; from another term, to the terms under it.
  const walk = (u: LTerm, up: Judgment | undefined): void => {
    let t = u;
    let ty: HTerm | undefined;
    let j = judgments.get(t);
    while (isTyping(t)) {
      ty ??= t.T.v;
      t = t.x;
      j ??= judgments.get(t);
    }
    j ??= up;
    const args: LTerm[] = [];
    let typed = t;
    let head = t;
    while (head.$ === "App") {
      args.unshift(head.x);
      typed = head.f;
      head = getBareTerm(typed);
      if (!isSameSpan(head.s, t.s)) {
        break;
      }
    }
    if (t.s !== undefined && ty !== undefined && j !== undefined) {
      for (const o of getNodesAt(t.s)) {
        if (t.$ === "App" ? isNodeOfCall(head, args, o) : isNodeOf(t, j, o)) {
          note(o, "t", ty, j, j.qt, t.s.file);
        }
      }
    }
    if (t.$ === "Lam" || t.$ === "Let") {
      const [names, levels] = t.$ === "Lam" ? [[t.k], [t.i]] : [t.k, t.i];
      declare(t.s, names, levels, j, getJudgment(t.f), true);
    } else if (t.$ === "All") {
      declare(t.s, [t.k], [t.i], j, getJudgment(t.B), false);
    }
    (t.$ === "App" ? [typed, ...args] : getSubterms(t)).forEach((x) => walk(x, j));
  };
  // Each binder of a declaration's type, as the checker opens it: the type it declares, with its
  // quantity, in the scope before it; and the node its entry is.
  const noteDomains = (T: HTerm): void => {
    let ctx = Bend.ctx_nil();
    let t = T;
    for (let i = 0; t.$ === "All"; i++) {
      const scope = { ctx, dep: i };
      ctx = Bend.ctx_bind(ctx, i, t.q, t.k, t.A);
      const o = getBinderNode(t.s, t.k);
      if (o !== undefined && t.s !== undefined) {
        note(o, "b", t.A, scope, t.q, t.s.file);
        const e = Bend.pmap_get(ctx, i);
        if (e !== null) {
          binders.set(e, o.id);
        }
      }
      t = t.B(Bend.Var(t.k, i));
    }
  };
  own.forEach((k) => {
    const tld = held.bok.tlds[k] as TLD | undefined;
    if (
      tld === undefined ||
      k.includes("~") ||
      (wanted !== undefined && !wanted.has(getWriterNamespace(tld)))
    ) {
      return;
    }
    noteDomains(tld.T);
    if (tld.$ === "ADT") {
      tld.c.forEach((c) => noteDomains(c.T));
    } else if (tld.e !== undefined) {
      walk(tld.e, undefined);
    }
  });
  origins.forEach((nodes) =>
    nodes.forEach((o) => {
      o.notes = o.notes.filter(
        (a, n) =>
          !o.notes
            .slice(0, n)
            .some(
              (b) =>
                b.role === a.role &&
                b.quantity.$ === a.quantity.$ &&
                isSameType(Bend, held, b.type, a.type),
            ),
      );
    }),
  );
};

// Answers
// -------

// The records of a tree, its children's first (cli.bend builds each node once its children are
// read): each fact on it, then the node. A fact names its type by a handle of `held`'s.
const getTreeRecords = (t: Tree, held: Held, out: string[]): string[] => {
  t.kids.forEach((k) => getTreeRecords(k, held, out));
  t.notes.forEach(({ role, quantity: q, type }) =>
    out.push(
      getRecord([
        "+",
        role,
        getQuantityLetter(q),
        role === "b" && t.used !== undefined ? getQuantityLetter(t.used) : "",
        String(held.types.push(type) - 1),
      ]),
    ),
  );
  out.push(
    getRecord([
      TAGS[t.syntax],
      t.name,
      t.range === undefined ? "" : String(t.range[0]),
      t.range === undefined ? "" : String(t.range[1]),
      String(t.kids.length),
      t.target ?? (t.binder === undefined ? "" : String(t.binder)),
      t.quantity ?? (t.unsafe === true ? "1" : ""),
    ]),
  );
  return out;
};

// A term, or a part of one, with `A` written back for each `k~A`: the checker checks a template's
// body with `k~A`, in no book, for its parameter `A` (def_check).
const getUntemplated = (x: unknown, bok: Book): unknown => {
  if (Array.isArray(x)) {
    return x.map((y) => getUntemplated(y, bok));
  }
  if (typeof x !== "object" || x === null || !("$" in x)) {
    return x;
  }
  const u = x as Record<string, unknown>;
  if (u.$ === "Ref" && typeof u.k === "string" && u.k.includes("~") && !(u.k in bok.tlds)) {
    return { ...u, k: u.k.slice(u.k.lastIndexOf("~") + 1) };
  }
  return Object.fromEntries(
    Object.entries(u).map(([k, v]) => [k, k === "s" || k === "v" ? v : getUntemplated(v, bok)]),
  );
};

// The path Bend loads a file at, as `seen` keeps it: real, with `/`; a file with an overlay, at its
// key.
const getLoadPath = (path: string): string =>
  getOverlay(path) === undefined
    ? (tryGet(() => getRealPath(path)) ?? getPathWithForwardSlashes(nodePath.resolve(path)))
    : getOverlayKey(path);

// Checks the file at `path`, as `check <path> <facts|syntax> <paths...>` asks. Its answer: `check`
// and the check's number, here 0 (see `getNumberedAnswer`), or `failed` and each file it read;
// then each file it parsed, if it loaded them: its path, namespace and text, then its nodes (see
// `getTreeRecords`). A passed check gives the facts of the files at `facts.paths` (all, if none).
// The hooks are global, so checks must not overlap.
const getCheck = async (checker: Checker, path: string, facts: Wanted): Promise<Made> => {
  const { Bend, base } = await checker.getLoaded();
  const book = getSeededBook(Bend, base);
  const seen = new Map<string, string | null>([[Bend.BASE_BEND, ""]]);
  const root: Frame = { name: "check", args: [], out: undefined, end: -1, kids: [] };
  const judgments = new Map<LTerm, Judgment>();
  let loaded = false;
  let passed = false;
  READS.clear();
  FILES.clear();
  traceParsing(root);
  try {
    await Bend.book_load(book, getLoadPath(path), "", seen);
    loaded = true;
    if (facts !== undefined) {
      traceJudgments(Bend, judgments);
    }
    Bend.book_valid(book, base.order.length);
    passed = true;
  } catch (e) {
    // A check that fails gives no facts; `bend <file> --check-only` says why. What bend.ts throws
    // for the file is an Err; anything else is a fault of the checker or of this glue, not of the
    // file, and its message goes to the user.
    if ((e as { $?: unknown } | null)?.$ !== "Err") {
      throw new Error(`checking ${path}: ${getErrorMessageFromUnknown(e)}`, { cause: e });
    }
  } finally {
    untrace();
  }
  const files = loaded ? getParsedFiles(root.kids, []) : [];
  const forest = files.map((file) => getFileTrees(file, book));
  const held: Held = { bok: book, types: [], binders: new Map() };
  if (passed && facts !== undefined) {
    putFacts(
      Bend,
      held,
      [...new Set(book.order.slice(base.order.length))],
      judgments,
      facts.paths.length === 0
        ? undefined
        : new Set(facts.paths.map((p) => seen.get(getLoadPath(p)) ?? undefined)),
      forest.flat(),
    );
  }
  const program = files.flatMap((file, n) =>
    forest[n].reduce(
      (out, t) => getTreeRecords(t, held, out),
      [getRecord(["file", file.path, file.ns, file.text])],
    ),
  );
  const read = [...READS];
  return passed
    ? { answer: [getRecord(["check", "0"]), ...program].join(""), read, held }
    : {
        answer: [
          getRecord(["failed"]),
          ...[...seen.keys()]
            .filter((p) => p !== Bend.BASE_BEND)
            .map((p) => getRecord(["read", p])),
          ...program,
        ].join(""),
        read,
      };
};

// The answer to one question about types: `show:<check>:<type>`,
// `same:<check>:<type>:<check>:<type>` or `normal:<check>:<type>`, each type a handle its check's
// answer, or a `normal` of it, gave. Types of two checks are never the same. A check that holds
// nothing is checked again first.
const getQuestionAnswer = async (checker: Checker, q: string): Promise<string> => {
  const [op, ...ns] = q.split(":");
  const [c, t, d, u] = ns.map(Number);
  if (op === "same" && c !== d) {
    return getRecord(["same", "false"]);
  }
  const answered = ANSWERED[c - 1];
  if (answered === undefined) {
    throw new Error("no check " + c);
  }
  const held = (answered.held ??= await getHeldAgain(checker, answered));
  const { Bend } = await checker.getLoaded();
  const getTyped = (h: number): Typed => {
    const ty = held.types[h] as Typed | undefined;
    if (ty === undefined) {
      throw new Error("no type " + c + ":" + h);
    }
    return ty;
  };
  if (op === "show") {
    const ty = getTyped(t);
    const names = Array.from({ length: ty.dep }, (_, level) => Bend.pmap_get(ty.ctx, level)?.k);
    return getRecord([
      "shown",
      Bend.term_show(
        getUntemplated(Bend.term_lower(ty.ty, ty.dep), held.bok) as LTerm,
        -1,
        names as string[],
        ty.file,
      ),
    ]);
  }
  if (op === "same") {
    return getRecord(["same", String(isSameType(Bend, held, getTyped(t), getTyped(u)))]);
  }
  if (op === "normal") {
    const ty = getTyped(t);
    return getRecord([
      "normal",
      String(c),
      String(held.types.push({ ...ty, ty: Bend.term_snf(held.bok, ty.ty) }) - 1),
    ]);
  }
  throw new Error("unknown question " + q);
};

// An answer with `number` as its check's number.
const getNumberedAnswer = (answer: string, number: number): string =>
  answer.replace(/^(check\t)\d+$/m, "$1" + number);

const getCachePath = ({ version }: Checker, path: string, facts: Wanted): string =>
  nodePath.join(
    CHECKS_DIR,
    getSha256Hex(
      [version, facts === undefined ? "syntax" : ["facts", ...facts.paths].join("\0"), path].join(
        "\n",
      ),
    ) + ".json",
  );

// The cached answer at `file`, if each file it read still has the text it read (its overlay's, if
// it has one). A hit marks the entry used now.
const getCachedEntry = (file: string): Entry | undefined =>
  tryGet(() => {
    const entry = JSON.parse(nodeFs.readFileSync(file, "utf8")) as Entry;
    if (!entry.files.every(([p, d]) => getSha256Hex(getViewText(p)) === d)) {
      return undefined;
    }
    nodeFs.utimesSync(file, new Date(), new Date());
    return entry;
  });

// Deletes the entries of the cache folder `dir` unused for longer than STALE, unless its .pruned
// file shows a prune in the last PRUNE_EVERY; one that another run deletes first is skipped. A
// folder that cannot be read keeps its entries.
const prune = (dir: string): void => {
  const marker = nodePath.join(dir, ".pruned");
  const last = nodeFs.statSync(marker, { throwIfNoEntry: false })?.mtimeMs ?? 0;
  if (Date.now() - last < PRUNE_EVERY) {
    return;
  }
  tryGet(() => nodeFs.writeFileSync(marker, ""));
  tryGet(() =>
    nodeFs
      .readdirSync(dir)
      .map((name) => nodePath.join(dir, name))
      .filter(
        (old) =>
          Date.now() - (nodeFs.statSync(old, { throwIfNoEntry: false })?.mtimeMs ?? Date.now()) >
          STALE,
      )
      .forEach((old) => nodeFs.rmSync(old, { recursive: true, force: true })),
  );
};

// The .bend file at `file` and every file it imports by a relative path (.bend files at any
// depth, and effects' files), each once.
export const getClosure = (file: string, seen: Set<string> = new Set()): string[] => {
  if (seen.has(file)) {
    return [];
  }
  seen.add(file);
  return [
    file,
    ...(file.endsWith(".bend")
      ? [...nodeFs.readFileSync(file, "utf8").matchAll(IMPORT)].flatMap((m) =>
          getClosure(nodePath.resolve(nodePath.dirname(file), m[1]), seen),
        )
      : []),
  ];
};

// What a build depends on besides the program's files: the paths and texts of the bend2 sources in
// `dir`, which hold Base and the compiler.
const getBuildSources = (dir: URL): string => {
  const sources = url.fileURLToPath(dir);
  return nodeFs
    .readdirSync(sources, { recursive: true, encoding: "utf8" })
    .filter((f) => [".ts", ".bend"].includes(nodePath.extname(f)))
    .sort()
    .flatMap((f) => [f, nodeFs.readFileSync(nodePath.join(sources, f), "latin1")])
    .join("\0");
};

// Where the native build of the rules program `source`, by the Bend in the bend2 folder `dir`, is
// kept: named by what it is built of.
export const getNativePath = (source: string, dir: URL): string => {
  const file = nodePath.resolve(source);
  const from = nodePath.dirname(file);
  const key = getSha256Hex(
    [
      getBuildSources(dir),
      ...getClosure(file).flatMap((f) => [
        nodePath.relative(from, f),
        nodeFs.readFileSync(f, "utf8"),
      ]),
    ].join("\0"),
  ).slice(0, 16);
  const name = `${nodePath.basename(source, ".bend")}.${key}`;
  return nodePath.join(PROGRAMS_DIR, name + (process.platform === "win32" ? ".exe" : ""));
};

// The program the rules program `source` builds to, with the Bend in the bend2 folder `dir`:
// native, if clang can build it, else JavaScript, until clang can. A build is kept, and used
// again until a file the program imports, or the Bend that builds it, changes; its use keeps it
// from prune (see USED). It goes to a folder of its own first, so a kept build is never partial,
// and runs that build one program at once share one build.
export const getBuiltProgram = async (source: string, dir: URL): Promise<string> => {
  const file = nodePath.resolve(source);
  const from = nodePath.dirname(file);
  const native = getNativePath(source, dir);
  const exe =
    nodeFs.existsSync(native) || getClang() !== undefined
      ? native
      : native.replace(/(\.exe)?$/, ".js");
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
    const bend = getBendCli(dir);
    const ran = await getCommandOutcome([...bend.cmd, file, "-o", out], from, bend.env);
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

// The answer to `check <path> <facts|syntax> <paths...>`: from the cache, if each file the check
// read is unchanged, else from Bend, and a passed check goes to the cache (whole or not at all; a
// cache that cannot be written is skipped). A passed check is numbered as before in this server,
// or anew. What it holds is large, and only a question reads it, so it holds nothing.
const getCheckAnswer = async (checker: Checker, path: string, facts: Wanted): Promise<string> => {
  const file = getCachePath(checker, path, facts);
  let entry = getCachedEntry(file);
  if (entry === undefined) {
    const made = await getCheck(checker, path, facts);
    if (made.held === undefined) {
      return made.answer;
    }
    entry = {
      files: made.read.map(([p, text]) => [p, getSha256Hex(text)]),
      answer: made.answer,
      digest: getSha256Hex(made.answer),
      types: made.held.types.length,
    };
    tryWriteJsonAtomically(file, entry);
  }
  const known = NUMBERS.get(file);
  const number =
    known !== undefined && ANSWERED[known - 1].digest === entry.digest
      ? known
      : ANSWERED.push({ file, path, facts, digest: entry.digest, types: entry.types });
  NUMBERS.set(file, number);
  return getNumberedAnswer(entry.answer, number);
};

// What the check `answered` holds, checked again: its answer must be the one rules have.
const getHeldAgain = async (checker: Checker, answered: Answered): Promise<Held> => {
  const made = await getCheck(checker, answered.path, answered.facts);
  if (made.held === undefined || getSha256Hex(made.answer) !== answered.digest) {
    nodeFs.rmSync(answered.file, { force: true });
    throw new Error("a check changed since its answer; run again");
  }
  return made.held;
};

const getMemoPath = (answered: Answered): string => answered.file + ".answers";

// Where the answer to `q` is kept, if it is the same in any run: in its check's memo (kept, if its
// digest is the one this server answered with, else new), under the question with its checks
// numbered 0. Not `normal`, whose handle is the next of this run, nor a question about a type a
// `normal` of this run made, nor a `same` of two checks.
const getMemoSlot = (
  q: string,
): { answered: Answered; answers: Record<string, string>; key: string } | undefined => {
  const [op, c, t, d, u] = q.split(":");
  const answered = ANSWERED[Number(c) - 1];
  const handles = op === "show" ? [t] : op === "same" && c === d ? [t, u] : [];
  if (
    answered === undefined ||
    handles.length === 0 ||
    handles.some((h) => Number(h) >= answered.types)
  ) {
    return undefined;
  }
  const kept = answered.memo ?? (tryGetJson(getMemoPath(answered)) as Memo | undefined);
  answered.memo =
    kept?.digest === answered.digest ? kept : { digest: answered.digest, answers: {} };
  return {
    answered,
    answers: answered.memo.answers,
    key: [op, 0, t, ...(op === "same" ? [0, u] : [])].join(":"),
  };
};

// The answer to `ask <question>...`: one record per question, in order, from the memos where they
// have it; the others' answers go to the memos.
const getAskAnswer = async (checker: Checker, questions: string[]): Promise<string> => {
  const asked = new Set<Answered>();
  const answers: string[] = [];
  for (const q of questions) {
    const memo = getMemoSlot(q);
    let got = memo?.answers[memo.key];
    if (got === undefined) {
      got = await getQuestionAnswer(checker, q);
      if (memo !== undefined) {
        memo.answers[memo.key] = got;
        asked.add(memo.answered);
      }
    }
    answers.push(got);
  }
  asked.forEach((answered) => tryWriteJsonAtomically(getMemoPath(answered), answered.memo));
  return answers.join("");
};

// The answer to `forget <check>`: what the server holds of the check is freed. A question about it
// checks it again.
const getForgetAnswer = (check: number): string => {
  const answered = ANSWERED[check - 1];
  if (answered !== undefined) {
    answered.held = undefined;
  }
  return getRecord(["forgot"]);
};

const getAnswer = async (checker: Checker, line: string): Promise<string> => {
  const [op, ...args] = line.split("\t").map(getUnescapedField);
  return op === "check" && args.length >= 2
    ? getCheckAnswer(checker, args[0], args[1] === "facts" ? { paths: args.slice(2) } : undefined)
    : op === "forget" && args.length === 1
      ? getForgetAnswer(Number(args[0]))
      : op === "ask"
        ? getAskAnswer(checker, args)
        : getRecord(["fail", "unknown request: " + line]);
};

// Runs each request it is given after the one before ends: a program's workers ask at once, and
// checks must not overlap (see `getCheck`).
const getSerialRunner = (): ((run: () => Promise<string>) => Promise<string>) => {
  let last: Promise<unknown> = Promise.resolve();
  return (run) => {
    const next = last.then(run);
    last = next.catch(() => undefined);
    return next;
  };
};

// One request: read its line, write the whole answer, close. If Bend does not load, the answer
// says why.
const serve = async (
  checker: Checker,
  inTurn: (run: () => Promise<string>) => Promise<string>,
  socket: net.Socket,
): Promise<void> => {
  const lines = readline.createInterface({ input: socket });
  const [line] = (await once(lines, "line")) as [string];
  lines.close();
  socket.end(
    await inTurn(() => getAnswer(checker, line)).catch((e: unknown) =>
      getRecord(["fail", getErrorMessageFromUnknown(e)]),
    ),
  );
};

// The checker, the rules program `named`, built first, and what to say first of the Bend bend-lint
// uses (see bend2.ts). The checker comes first, so a drift stops the run before a build.
const getRunSetup = async (named: string): Promise<[Checker, string, string[]]> => {
  const dir = unwrap(await tryGetBend2SourceUrl());
  const checker = getChecker(dir);
  const [program, version] = await Promise.all([
    getBuiltProgram(named, dir),
    getBendVersionNote(dir),
  ]);
  const javascript = program.endsWith(".js") ? JAVASCRIPT_NOTE : undefined;
  return [checker, program, [PINNED_BEND_NOTE, version, javascript].filter((n) => n !== undefined)];
};

// The folder of the nearest bend-lint.json up from `dir`, if there is one.
export const getProject = (dir: string): string | undefined => {
  const up = nodePath.dirname(dir);
  return nodeFs.existsSync(nodePath.join(dir, CONFIG))
    ? dir
    : up === dir
      ? undefined
      : getProject(up);
};

// The entries of `value`, if it is a JSON object.
const getObjectEntries = (value: unknown): Array<[string, unknown]> | undefined =>
  typeof value === "object" && value !== null && !Array.isArray(value)
    ? Object.entries(value)
    : undefined;

// Keeps the overlays of `text`, which `--overlays` reads on stdin: a JSON object of paths to texts.
const readOverlays = (text: string): void => {
  const entries = getObjectEntries(tryGet(() => JSON.parse(text) as unknown));
  if (entries === undefined || entries.some(([, t]) => typeof t !== "string")) {
    throw new Error("--overlays reads a JSON object of paths to texts on stdin");
  }
  entries.forEach(([p, t]) => OVERLAYS.set(getOverlayKey(p), t as string));
};

// What the bend-lint.json in `project` says of its rules: those of "rules" but those "off", and
// "packages". Bend checks the packages' names and versions; the runner, the rest of the config.
export const getRules = (project: string): Rules => {
  const config = JSON.parse(nodeFs.readFileSync(nodePath.join(project, CONFIG), "utf8")) as {
    rules?: unknown;
    packages?: unknown;
  };
  const rules = getObjectEntries(config.rules ?? {});
  const packages = getObjectEntries(config.packages ?? {});
  if (rules === undefined) {
    throw new Error(CONFIG + ": rules must map rule ids to settings");
  }
  if (
    packages === undefined ||
    !packages.every((entry): entry is [string, string] => typeof entry[1] === "string")
  ) {
    throw new Error(CONFIG + ": packages must map BendHub names to versions");
  }
  return {
    ids: rules.filter(([, setting]) => setting !== "off").map(([id]) => id),
    packages: new Map(packages),
  };
};

// `to` as Bend imports it from a file in the folder `from`, if it can: see PLAIN.
const getImportPath = (from: string, to: string): string | undefined => {
  const relative = getPathWithForwardSlashes(nodePath.relative(from, to));
  return PLAIN.test(relative) ? relative : undefined;
};

// The program that runs the rules of the project in `project`, written in BUILD and named by its
// text. A rule whose id starts with a package's name, then "/", is that package's file at the rest
// of the id, from BendHub; another is bend-lint-rules/<id>.bend in `project`, imported at its real
// path, so a link is followed. An error says which rule is missing, or why Bend cannot import it.
export const getRulesProgram = (project: string, { ids, packages }: Rules): string => {
  const imports = ids.map((id, n) => {
    if (!/^[A-Za-z_][\w-]*(\/[A-Za-z_][\w-]*)*$/.test(id)) {
      throw new Error(`${id} is not a rule id: a path of plain names, without .bend`);
    }
    const [name, ...rest] = id.split("/");
    const version = packages.get(name);
    if (version !== undefined && rest.length > 0) {
      return `import ${name}@${version}/${rest.join("/")}.bend as Rule${n}`;
    }
    const real = tryGet(() =>
      nodeFs.realpathSync(nodePath.join(project, RULES, ...id.split("/")) + ".bend"),
    );
    if (real === undefined) {
      throw new Error(`there is no rule ${id}: ${RULES}/${id}.bend does not exist`);
    }
    const rule = getImportPath(BUILD, real);
    if (rule === undefined) {
      throw new Error(PER_PROJECT);
    }
    return `import ${rule} as Rule${n}`;
  });
  const run = ids.map((id, n) => `Cli.Rule{${JSON.stringify(id)}, Rule${n}.rule()}`).join(", ");
  const text = [
    "import Base",
    "import ../cli.bend as Cli",
    ...imports,
    "",
    "def main() -> IO(Unit):",
    `  Cli.run(~[${run}])`,
    "",
  ].join("\n");
  const source = nodePath.join(BUILD, `rules.${getSha256Hex(text).slice(0, 16)}.bend`);
  writeNewFileAtomically(source, text);
  return source;
};

// Makes bend-lint.json and bend-lint-rules/format.bend in `dir`, those that are not there; gives
// those it wrote, and those it kept.
const getInitFiles = (dir: string): { wrote: string[]; kept: string[] } => {
  const files: Array<[string, string]> = [
    [nodePath.join(dir, CONFIG), INIT_CONFIG],
    [nodePath.join(dir, RULES, "format.bend"), INIT_FORMAT],
  ];
  const kept = files.filter(([file]) => nodeFs.existsSync(file)).map(([file]) => file);
  const wrote = files
    .filter(([file]) => !kept.includes(file))
    .map(([file, text]) => {
      writeFileAtomically(file, text);
      return file;
    });
  return { wrote, kept };
};

// Side effects
// ============

if (import.meta.main) {
  // A run, and every process it starts (they inherit it), runs at low priority: a long run slows
  // down, not the machine.
  tryGet(() => os.setPriority(os.constants.priority.PRIORITY_BELOW_NORMAL));
  const args = process.argv.slice(2);
  if (args[0] === "init") {
    try {
      const { wrote, kept } = getInitFiles(process.cwd());
      wrote.forEach((file) => console.log("bend-lint: wrote " + file));
      kept.forEach((file) =>
        console.log("bend-lint: " + file + " is there already; it stays as it is"),
      );
    } catch (e) {
      console.error("bend-lint: " + getErrorMessageFromUnknown(e));
      process.exit(2);
    }
    process.exit(0);
  }
  // An install of bend-lint: the project that installs it in its node_modules gets what init
  // makes, and bend-lint downloads its Bend now, not on its first run. It never fails the install.
  if (args[0] === "postinstall") {
    try {
      const project = process.env.INIT_CWD ?? "";
      const modules = tryGet(() => nodeFs.realpathSync(nodePath.join(project, "node_modules")));
      const relative =
        modules === undefined
          ? ".."
          : nodePath.relative(modules, url.fileURLToPath(new URL("../../", import.meta.url)));
      if (!relative.startsWith("..") && !nodePath.isAbsolute(relative)) {
        getInitFiles(project).wrote.forEach((file) => console.log("bend-lint: wrote " + file));
      }
      unwrap(await tryGetBend2SourceUrl());
    } catch (e) {
      console.error("bend-lint: " + getErrorMessageFromUnknown(e) + "; its first run tries again");
    }
    process.exit(0);
  }
  // The runner never sees `--overlays`: it gets the files that have one in BEND_LINT_OVERLAYS, and
  // each argument that names one as its key.
  if (args.includes("--overlays")) {
    try {
      readOverlays(nodeFs.readFileSync(0, "utf8"));
    } catch (e) {
      console.error("bend-lint: " + getErrorMessageFromUnknown(e));
      process.exit(2);
    }
  }
  const runArgs = args
    .filter((a) => a !== "--overlays")
    .map((a) => (getOverlay(a) === undefined ? a : getOverlayKey(a)));
  const project = getProject(process.cwd());
  if (project === undefined) {
    console.error(
      "bend-lint: no " + CONFIG + " in this folder or above it; `bunx bend-lint init` makes one",
    );
    process.exit(2);
  }

  const [checker, program, notes] = await Promise.resolve()
    .then(() => getRunSetup(getRulesProgram(project, getRules(project))))
    .catch((e: unknown) => {
      console.error("bend-lint: " + getErrorMessageFromUnknown(e));
      return process.exit(2);
    });
  notes.forEach((note) => console.error(note));

  const inTurn = getSerialRunner();
  const server = net.createServer((socket) => void serve(checker, inTurn, socket));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");

  // A JS build of the program runs on this runtime; a native one, as itself.
  const [command, commandArgs] = /\.m?js$/.test(program)
    ? [process.execPath, [program, ...runArgs]]
    : [program, runArgs];
  const child = spawn(command, commandArgs, {
    env: {
      ...process.env,
      BEND_LINT_PORT: String((server.address() as net.AddressInfo).port),
      BEND_LINT_PROJECT: getPathWithForwardSlashes(project),
      BEND_LINT_OVERLAYS: [...OVERLAYS.keys()].join("\n"),
    },
    stdio: "inherit",
  });
  const [code] = (await once(child, "exit")) as [number | null];
  server.close();
  prune(CHECKS_DIR);
  prune(PROGRAMS_DIR);
  process.exit(code ?? 1);
}
