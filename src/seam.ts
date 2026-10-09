// Everything bend-lint knows about bend2's internals: finding (or
// downloading) bend2, patching it as Bun loads it, and every call into it.
// The docs say what the patch does and how drift stops it. Each text edit
// must match exactly once; the wrappers pass every argument through, so
// bend computes what it would without them.

import * as nodeFs from "node:fs";
import * as os from "node:os";
import * as nodePath from "node:path";
import * as url from "node:url";

import pkg from "../package.json" with { type: "json" };

import type { Book, Ctx, Err, HTerm, LTerm, Name, Parse, Quant, Uses } from "bend2/bend.ts";
import type { Span as BendSpan } from "bend2/bend.ts";
import type * as BendModule from "bend2/bend.ts";
import type * as CompModule from "bend2/comp.ts";
import type {
  Diag,
  Declaration,
  Fact,
  FactFilter,
  LintRule,
  Node,
  OptionValue,
  Quantity,
  RuleContext,
  Shape,
  Source,
  Span,
  Type,
} from "./lint.ts";

// Types
// =====

// A file's patch: exact edits, text it must hold once unchanged (needs), a
// tail appended to the file, and names it must declare once and export (the
// tail exports those it does not).
type Patch = { edits: Array<[string, string]>; needs?: string[]; tail: string; exports: string[] };

export type Get = (url: string) => Promise<Response>;

// How bendDir reaches the network, runs `bend`, and where it caches;
// tests give their own. run gives a command's stdout, or undefined if it
// fails.
export type FindOptions = {
  get?: Get;
  run?: (cmd: string[]) => string | undefined;
  cache?: string;
};

// comp.ts as the patch exports it.
type Comp = typeof CompModule & { RUNTIME_MAIN: string; js_sat(k: Name): string };

// What bend-lint uses of main.ts, as the patch exports it: book_read throws
// a Check_Fail holding why the check failed.
type Main = {
  book_read(file: string, base?: Book, seen?: Map<string, string | null>): Promise<Book>;
  book_err(e: unknown): string;
  Check_Fail: new (why: unknown) => { why: unknown };
};

// bend2 as load gives it: the patched modules and their folder.
export type Loaded = { Bend: typeof BendModule; Comp: Comp; Main: Main; BEND2: string };

// A source as bend.ts spans point at it.
type File = { str: string; ns: string; al: Record<Name, Name>; path: string };

type Mapper = (s: BendSpan | undefined) => BendSpan | undefined;

// A fact as the checker gives it: `tm` checked (or inferred) as `ty` at
// depth `dep` in `ctx`, in def `def`, demanded `qt` times, using the
// variables in `us`, in book `bok` (a template body has its own). `inst`
// marks an instance's fact.
export type Raw = {
  tm: LTerm;
  ty: HTerm;
  bok: Book;
  ctx: Ctx;
  dep: number;
  def: Name;
  qt: Quant;
  us: Uses;
  inst: boolean;
  spn?: BendSpan;
};

// What the wrappers report for each checked term.
type Report = Omit<Raw, "inst">;

type Syntax = {
  declarations: Array<
    Omit<Declaration, "references" | "type"> & { key: Name | number; type?: Scoped }
  >;
  references: Array<{ key: Name | number; owner: string; span: Span }>;
};

// A rule option's schema and default.
type Declared = NonNullable<LintRule["options"]>[string];

// What a file's stat said, and when it was taken (before the file was
// read).
type Stamp = { at: number; size: number; mtimeMs: number; ctimeMs: number; ino: number };

// A type handle's content: the type, the book and depth of its scope, and
// the file whose spelling shows it (none: the check's names). A Raw is one, for
// the type its term was checked as.
type Scoped = { ty: HTerm; bok: Book; dep: number; spelled?: File };

// How one file spells names (see spellingOf).
type Spelling = {
  ns: Name;
  aliases: Record<Name, Name>;
  file: File;
  qualify: (name: string) => Name;
  spell: (k: Name) => Name;
  key: (name: string) => Name;
};

// bend2's own objects, for code that accepts to break when bend2 changes.
export type Unstable = { Bend: typeof BendModule; book: Book; raw: (fact: Fact) => Raw };

// The rule context's operations that ask bend2.
export type Operations = Omit<
  RuleContext,
  "sources" | "root" | "options" | "facts" | "prior" | "signal" | "fact" | "diag" | "unstable"
>;

// A declaration's or import's name, as bend's parser read it.
type Heading = Omit<Declaration, "owner" | "references" | "type">;

// root: the file checked, unless bend could not read it. beyond: whether
// facts were kept beyond the root; instances: whether instances' were.
// headings: what bend's parser read, by file and offset; none on failure.
export type Checked = {
  book: Book;
  sources: Source[];
  root?: Source;
  map: Mapper;
  facts: Fact[];
  headings: Heading[];
  beyond: boolean;
  instances: boolean;
  failure?: Diag;
};

// A rule written in Bend, checked and compiled: what its id(), facts(),
// options() (if it has them) and main() give, and whether the compiler and
// every file it was made from are unchanged.
export type Compiled = {
  id: string;
  want: FactFilter | null;
  options?: LintRule["options"];
  entries?: LintRule["entries"];
  main: (args: string[]) => number;
  current: () => boolean;
};

// A compiled Bend rule as the disk keeps it: its file, the compiler's hash,
// each file it was made from with its text's hash, and main() as Bend's JS.
type Kept = {
  file: string;
  compiler: string;
  files: Array<[string, string]>;
  rule: Omit<Compiled, "main" | "current"> & { js: string };
};

// Constants
// =========

// Marks an error as drift: bend2 changed in a way bend-lint does not follow.
export const DRIFT = Symbol("DriftError");

const HERE = url.fileURLToPath(new URL(".", import.meta.url));
const DRIVE = /^[A-Za-z]:(?=\/)/;
const SHIM = JSON.stringify(url.pathToFileURL(nodePath.join(HERE, "seam.ts")).href);
const SAMPLE = nodePath.join(HERE, "bend", "sample.bend");

export const MARK = "BEND_LINT_PATCH";

const RAW = "https://raw.githubusercontent.com/bendlang/bend/";
const RELEASE = /^v\d+\.\d+\.\d+$/;
const EFF = /^effs\/[\w.-]+$/;
const GIVE = "give a bend checkout with --bend <dir> or BEND_DIR";

// The newest bend release this repo's checks passed with; scripts/sync-bend.ts
// moves it.
export const PIN: string = pkg.bendRelease;

// Downloaded bends, one folder per release, and compiled Bend rules.
const CACHE = nodePath.join(
  process.env.XDG_CACHE_HOME ??
    (process.platform === "win32"
      ? (process.env.LOCALAPPDATA ?? nodePath.join(os.homedir(), "AppData", "Local"))
      : nodePath.join(os.homedir(), ".cache")),
  "bend-lint",
);

const KEPT = nodePath.join(CACHE, "rules");

// Each loaded bend2's compiler hash, made once.
const COMPILERS = new WeakMap<Loaded, string>();

const SHIMMED: Array<[string, string]> = [
  ['import * as fs from "node:fs";', "import { fs } from " + SHIM + ";"],
  ['import * as path from "node:path";', "import { path } from " + SHIM + ";"],
];

const PATCHES: Record<string, Patch> = {
  "bend.ts": {
    edits: [
      ...SHIMMED,
      ["export function term_infer(", "function unseen_term_infer("],
      ["export function term_check(", "function unseen_term_check("],
      ["export function parse_bind(", "function unseen_parse_bind("],
      ["export function parse_tele(", "function unseen_parse_tele("],
      ["export function parse_term(", "function unseen_parse_term("],
      ["const nm  = parse_name(p);", 'const nm  = seeDeclared(p, parse_name(p), "def");'],
      [
        'if (parse_word(p, "type")) {\n      const k = parse_fresh(p, parse_name(p));',
        'if (parse_word(p, "type")) {\n      const k = parse_fresh(p, seeDeclared(p, parse_name(p), "type"));',
      ],
      [
        'if (parse_word(p, "law")) {\n      const k = parse_fresh(p, parse_name(p));',
        'if (parse_word(p, "law")) {\n      const k = parse_fresh(p, seeDeclared(p, parse_name(p), "def"));',
      ],
      [
        "parse_fresh(p, parse_name(p), book.ctrs,",
        'parse_fresh(p, seeDeclared(p, parse_name(p), "constructor"), book.ctrs,',
      ],
      ['body[i] = "";', 'body[i] = "";\n    seeImported(real, at, lines[i], m);'],
    ],
    tail: `import { seeInfer, seeCheck, seeParseBind, seeParseTele, seeParseTerm, seeDeclared, seeImported } from ${SHIM};\nexport const term_infer = seeInfer(unseen_term_infer);\nexport const term_check = seeCheck(unseen_term_check);\nexport const parse_bind = seeParseBind(unseen_parse_bind);\nexport const parse_tele = seeParseTele(unseen_parse_tele);\nexport const parse_term = seeParseTerm(unseen_parse_term);\n`,
    exports: [],
  },
  "comp.ts": {
    edits: [],
    needs: ["let cli_args = [];", "function io_run(m) {"],
    tail: "",
    exports: ["RUNTIME_MAIN", "js_sat"],
  },
  "main.ts": { edits: SHIMMED, tail: "", exports: ["book_read", "book_err", "Check_Fail"] },
};

// The bend2 files bend-lint patches and imports.
export const PATCHED = Object.keys(PATCHES);

// Where the wrappers and probes report: see, declare and import for one
// check at a time, parse while a rule's source metadata is read.
export const hook: {
  see?: (report: Report) => void;
  declare?: (kind: Heading["kind"], name: Name, span: BendSpan) => void;
  import?: (path: string, name: Name, beg: number) => void;
  parse?: {
    binding: (
      name: Name,
      index: number,
      span: BendSpan | undefined,
      kind: Declaration["kind"],
    ) => void;
    term: (p: Parse, t: LTerm) => void;
  };
} = {};

// A comment, a string or char literal (maybe over several lines, maybe
// unterminated), a newline, or any other character that is not a space.
export const SOURCE_TOKEN =
  /#[^\r\n]*|"(?:\\[^]|[^"\\])*(?:"|$)|'(?:\\[^]|[^'\\])*(?:'|$)|\n|[^\s#"']+/g;

// Text an editor holds unsaved, by real path, set for one check at a time.
// bend.ts reads it in place of the file on disk.
export const unsaved = new Map<string, string>();

// The text bend.ts read in the check running now, by real path, with the
// file's stamp (none for unsaved text). Sources take their text from it, so
// a save during the check cannot set them apart from what bend parsed.
let reads: Map<string, { text: string; stamp?: Stamp }> | undefined;

// The checked base.bend book, with the text of base.bend it was checked
// from: Base is checked once per process, and again only if base.bend
// changes. Only the latest is kept.
let BASE: { key: string; book: Promise<Book> } | undefined;

// The last check that passed of each file asked to reuse it, by real path,
// with the bend2 folder and filters it was made for.
const REUSED = new Map<string, { key: string; run: Checked }>();

// The check running now, or done; the next check waits for it.
let queue: Promise<unknown> = Promise.resolve();

const STARTS = new WeakMap<object, number[]>();

// Each checked source's File, and back.
const FILES = new WeakMap<Source, File>();
const SOURCES = new WeakMap<object, Source>();

// A source that is not the user's: Base, or a hub package (its namespace
// starts with the hash bend names it by).
export const foreign = (s: Source): boolean => s.base || /^0x[0-9a-f]+\//.test(FILES.get(s)!.ns);

// Each source's stamp, from when it was read or last found unchanged.
const STAMPS = new WeakMap<Source, Stamp>();

// How close, in milliseconds, a file's last change can be to its stamp
// before a later write could leave the stat the same (FAT counts in 2 s).
const RACY = 2000;

const QUANTITY: Record<Quant["$"], Quantity> = { None: "erased", Lone: "once", Many: "many" };

// Binders are explicit in checked terms, so Var.v cells are not followed.
// A new term kind is a type error here, and a drift error when walked.
const CHILDREN: { [K in LTerm["$"]]: (tm: Extract<LTerm, { $: K }>) => LTerm[] } = {
  Let: (tm) => [...tm.v, tm.f],
  Lam: (tm) => [tm.f],
  Sub: (tm) => [tm.f],
  App: (tm) => [tm.f, tm.x],
  Ctr: (tm) => tm.x,
  ADT: (tm) => tm.x,
  Mat: (tm) => [tm.h, tm.m],
  Rwt: (tm) => [tm.e, tm.p, tm.f],
  Typ: (tm) => [tm.g],
  Min: (tm) => [tm.a, tm.b],
  All: (tm) => [tm.A, tm.B],
  Eql: (tm) => [tm.a, tm.b, tm.T],
  Ann: (tm) => [tm.x, tm.T],
  Var: () => [],
  Ref: () => [],
  Qnt: () => [],
  Qua: () => [],
  Lit: () => [],
  Efq: () => [],
  Rfl: () => [],
  Hol: () => [],
};

// Functions
// =========

const slash = (p: string): string => p.split(nodePath.sep).join("/");

const held = (p: nodeFs.PathOrFileDescriptor): string | undefined =>
  typeof p === "string" && unsaved.size > 0 && nodeFs.existsSync(p)
    ? unsaved.get(slash(nodeFs.realpathSync(p)))
    : undefined;

// path.posix.resolve from `cwd`, where a drive letter is a root.
export const resolve = (cwd: string, ...ps: string[]): string => {
  const all = [cwd, ...ps].map(slash);
  const drive =
    all
      .filter((p) => DRIVE.test(p))
      .at(-1)
      ?.slice(0, 2) ?? "";
  return drive + nodePath.posix.resolve(...all.map((p) => p.replace(DRIVE, "")));
};

export const relative = (from: string, to: string): string =>
  nodePath.posix.relative(slash(from).replace(DRIVE, ""), slash(to).replace(DRIVE, ""));

// fs and path for bend.ts and main.ts.
export const fs = {
  ...nodeFs,
  realpathSync: (p: nodeFs.PathLike): string => slash(nodeFs.realpathSync(p)),
  readFileSync: ((p: nodeFs.PathOrFileDescriptor, ...rest: unknown[]) => {
    const kept = held(p);
    const stamp =
      reads !== undefined && kept === undefined && typeof p === "string" ? stampOf(p) : undefined;
    const out = kept ?? (nodeFs.readFileSync as (...a: unknown[]) => unknown)(p, ...rest);
    if (reads !== undefined && typeof p === "string" && typeof out === "string") {
      reads.set(slash(nodeFs.realpathSync(p)), { text: out, stamp });
    }
    return out;
  }) as typeof nodeFs.readFileSync,
};

// A file's stamp, taken now, or undefined if it cannot be.
const stampOf = (p: string): Stamp | undefined => {
  const at = Date.now();
  const st = tried(() => nodeFs.statSync(p));
  return st && { at, size: st.size, mtimeMs: st.mtimeMs, ctimeMs: st.ctimeMs, ino: st.ino };
};

// Whether a stamp still vouches for its file: the stat is the same, and the
// file's last change was well before the stamp, so a write in the same tick
// of the file system's clock cannot hide behind it.
const holds = (old: Stamp | undefined, now: Stamp | undefined): boolean =>
  old !== undefined &&
  now !== undefined &&
  Math.max(old.mtimeMs, old.ctimeMs) < old.at - RACY &&
  old.size === now.size &&
  old.mtimeMs === now.mtimeMs &&
  old.ctimeMs === now.ctimeMs &&
  old.ino === now.ino;

export const path = {
  ...nodePath,
  join: (...ps: string[]): string => slash(nodePath.join(...ps)),
  resolve: (...ps: string[]): string => slash(nodePath.resolve(...ps)),
  posix: {
    ...nodePath.posix,
    resolve: (...ps: string[]): string => resolve(process.cwd(), ...ps),
    relative,
  },
};

// f.length counts the parameters before the first default.
const arity = (f: (...args: never[]) => unknown, n: number, name: string): void => {
  if (f.length !== n) {
    throw drift(
      `${name} takes ${f.length} parameters, not ${n}; update the observers in src/seam.ts`,
    );
  }
};

// term_infer and term_check as bend.ts calls them: every argument passes
// through, and each result is also reported to hook.see. tsc checks the
// names against bend.ts's signatures; a function that no longer takes the
// arguments read here stops loading.
export const seeInfer = (f: typeof BendModule.term_infer): typeof BendModule.term_infer => {
  arity(f, 6, "term_infer");
  return (...args) => {
    const r = f(...args);
    const [bok, lhs, tm, qt, ctx, dep] = args;
    hook.see?.({ tm: r.tm, ty: r.ty, bok, ctx, dep, def: lhs.def, qt, us: r.us, spn: tm.s });
    return r;
  };
};

export const seeCheck = (f: typeof BendModule.term_check): typeof BendModule.term_check => {
  arity(f, 7, "term_check");
  return (...args) => {
    const r = f(...args);
    const [bok, lhs, tm, qt, ty, ctx, dep] = args;
    hook.see?.({ tm: r.tm, ty, bok, ctx, dep, def: lhs.def, qt, us: r.us, spn: tm.s });
    return r;
  };
};

export const seeParseBind = (f: typeof BendModule.parse_bind): typeof BendModule.parse_bind => {
  arity(f, 2, "parse_bind");
  return (...args) => {
    const t = f(...args);
    hook.parse?.binding(t.k, t.i, t.s, "variable");
    return t;
  };
};

export const seeParseTele = (f: typeof BendModule.parse_tele): typeof BendModule.parse_tele => {
  arity(f, 2, "parse_tele");
  return (...args) => {
    const t = f(...args);
    t.forEach(([, k, i, , s]) =>
      hook.parse?.binding(k, i, s, args[1] === "}" ? "field" : "parameter"),
    );
    return t;
  };
};

export const seeParseTerm = (f: typeof BendModule.parse_term): typeof BendModule.parse_term => {
  arity(f, 1, "parse_term");
  return (...args) => {
    const t = f(...args);
    hook.parse?.term(args[0], t);
    return t;
  };
};

// Where bend's parser reads a declaration's name; the name passes through.
export const seeDeclared = (p: Parse, name: Name, kind: Heading["kind"]): Name => {
  hook.declare?.(kind, name, { file: p, beg: p.pos - name.length, end: p.pos });
  return name;
};

// Where bend reads an import line: `m` is its match, `at` the line's offset.
export const seeImported = (path: string, at: number, line: string, m: RegExpExecArray): void => {
  const from = line.indexOf(m[1]);
  hook.import?.(
    path,
    m[2] ?? "Base",
    at + (m[2] === undefined ? from : line.indexOf(m[2], from + m[1].length)),
  );
};

// `file` is one of PATCHED. Its line ends become LF, as JS reads them
// anyway, so an edit can span lines in a CRLF checkout.
export const patch = (file: string, src: string): string => {
  const { edits, needs = [], tail, exports } = PATCHES[file];
  const mismatch = (what: string, n: number): never => {
    throw drift(
      `cannot patch bend2/${file}: found ${n} of ${what}, expected 1. Update PATCHES in src/seam.ts.`,
    );
  };
  const edited = [...edits, ...needs.map((t): [string, string] => [t, t])].reduce(
    (out, [at, to]) => {
      const n = out.split(at).length - 1;
      return n === 1 ? out.replace(at, () => to) : mismatch(JSON.stringify(at), n);
    },
    src.replace(/\r\n/g, "\n"),
  );
  const declared = (name: string, exported: string): RegExp =>
    new RegExp(`^${exported}(?:async function|function|class|const|let) ${name}\\b`, "gm");
  const missing = exports.filter((name) => {
    const n = edited.match(declared(name, "(?:export )?"))?.length ?? 0;
    return n === 1
      ? !declared(name, "export ").test(edited)
      : mismatch("a declaration of " + name, n);
  });
  const named = missing.length === 0 ? "" : `export { ${missing.join(", ")} };\n`;
  return `${edited}\n${tail}${named}export const ${MARK} = 1;\n`;
};

export const drift = (message: string): Error =>
  Object.assign(new Error(message), { name: "DriftError", [DRIFT]: true });

export const message = (e: unknown): string => (e instanceof Error ? e.message : String(e));

// A response's text, or a rejection naming its status.
const text = (res: Response, what: string): Promise<string> =>
  res.ok ? res.text() : Promise.reject(new Error(`GitHub answered ${res.status}${what}`));

// fetch, given up after 30 seconds.
const download = (url: string): Promise<Response> =>
  fetch(url, { signal: AbortSignal.timeout(30_000) });

// A command's stdout, or undefined if it does not run or fails.
const spawn = (cmd: string[]): string | undefined => {
  try {
    const r = Bun.spawnSync(cmd, { stdout: "pipe", stderr: "ignore" });
    return r.exitCode === 0 ? r.stdout.toString() : undefined;
  } catch {
    return undefined;
  }
};

// The installed bend's release ("v2.0.36"), or undefined if `bend version`
// does not run.
export const installedTag = (
  run: (cmd: string[]) => string | undefined = spawn,
): string | undefined => {
  const version = run(["bend", "version"])?.match(/^bend (\d+\.\d+\.\d+)\b/)?.[1];
  return version === undefined ? undefined : "v" + version;
};

// bend2 at a release (the PATCHED files, safe.ts, base.bend and the effs/
// files Base imports), kept in <cache>/<tag>/bend2.
// A download goes to a temporary folder first, so the cache never holds a
// partial one.
export const fetchBend = async (
  tag: string,
  cache: string = CACHE,
  get: Get = download,
): Promise<string> => {
  if (!RELEASE.test(tag)) {
    throw new Error("not a bend release: " + tag);
  }
  const dir = nodePath.join(cache, tag, "bend2");
  const whole = (): boolean =>
    [...PATCHED, "safe.ts", "base.bend"].every((f) => nodeFs.existsSync(nodePath.join(dir, f)));
  if (whole()) {
    return dir;
  }
  const fetched = (file: string): Promise<[string, string]> =>
    get(`${RAW}${tag}/bend2/${file}`)
      .then((res) => text(res, ` for bend2/${file}`))
      .then((body) => [file, body]);
  const base = await fetched("base.bend");
  const effs = [
    ...new Set([...base[1].matchAll(/^\s*import "\.\/(effs\/[^"]+)"/gm)].map((m) => m[1])),
  ];
  const odd = effs.find((f) => !EFF.test(f));
  if (odd !== undefined) {
    throw new Error("base.bend imports " + odd + ", which is not a plain file in effs/");
  }
  const files = [base, ...(await Promise.all([...PATCHED, "safe.ts", ...effs].map(fetched)))];
  nodeFs.mkdirSync(nodePath.join(cache, tag), { recursive: true });
  const part = nodeFs.mkdtempSync(nodePath.join(cache, tag, ".part-"));
  files.forEach(([file, body]) => {
    nodeFs.mkdirSync(nodePath.dirname(nodePath.join(part, file)), { recursive: true });
    nodeFs.writeFileSync(nodePath.join(part, file), body);
  });
  try {
    nodeFs.rmSync(dir, { recursive: true, force: true });
    nodeFs.renameSync(part, dir);
  } catch (e) {
    nodeFs.rmSync(part, { recursive: true, force: true });
    if (!whole()) {
      throw e;
    }
  }
  return dir;
};

// The bend2 folder to load, found in the order the docs give.
export const bendDir = async (
  given: string | undefined,
  { get = download, run = spawn, cache = CACHE }: FindOptions = {},
): Promise<string> => {
  const chosen = given ?? process.env.BEND_DIR;
  if (chosen !== undefined) {
    const dir = path.resolve(chosen);
    const found = [path.join(dir, "bend2"), dir].find((d) =>
      nodeFs.existsSync(path.join(d, "bend.ts")),
    );
    if (found === undefined) {
      throw new Error(`no bend2 at ${dir} (it needs bend.ts); ${GIVE}`);
    }
    return fs.realpathSync(found);
  }
  const tag = installedTag(run) ?? PIN;
  const fresh = !nodeFs.existsSync(nodePath.join(cache, tag, "bend2"));
  const got = await fetchBend(tag, cache, get).catch((e: unknown) => {
    throw new Error(`could not download bend ${tag} (${message(e)}); ${GIVE}`);
  });
  if (fresh) {
    console.error("bend-lint: downloaded bend " + tag + " to " + got);
  }
  return fs.realpathSync(got);
};

// Every sub-term, parents first, with an explicit stack: linear in the
// size of the term, at any depth.
export function* walk(tm: LTerm): Generator<LTerm> {
  const stack = [tm];
  for (let t = stack.pop(); t !== undefined; t = stack.pop()) {
    const next = children(t);
    yield t;
    for (let i = next.length - 1; i >= 0; i--) {
      stack.push(next[i]);
    }
  }
}

// A term's sub-terms, in bend's order.
const children = (t: LTerm): LTerm[] => {
  const of = (CHILDREN as Record<string, ((tm: LTerm) => LTerm[]) | undefined>)[t.$];
  if (of === undefined) {
    throw drift(`unknown term kind ${t.$}; update CHILDREN in src/seam.ts`);
  }
  return of(t);
};

// Where each line of `text` starts, computed once per owner of the text.
export const starts = (owner: object, text: string): number[] => {
  const known = STARTS.get(owner);
  if (known !== undefined) {
    return known;
  }
  const out = [0, ...[...text.matchAll(/\n/g)].map((m) => m.index! + 1)];
  STARTS.set(owner, out);
  return out;
};

// The index of the line that holds `off`, given each line's start.
export const line = (starts: number[], off: number): number => {
  let lo = 0;
  let hi = starts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (starts[mid] <= off) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
};

// bend.ts parses a copy of each file with its import lines blanked, so a
// span moves to the file on disk by line and column. The copy's namespace,
// folder and lines pick the file; a copy that matches no file, or two, is
// a drift error. A copy with the file's own text keeps its offsets.
export const mapper = (files: File[]): Mapper => {
  const own = new Set<unknown>(files);
  const memo = new WeakMap<object, { file: File; from: number[]; to: number[] }>();
  // Each file's lines, split once.
  const split = new Map<File, string[]>();
  const linesOf = (file: File): string[] => {
    const known = split.get(file) ?? file.str.split("\n");
    split.set(file, known);
    return known;
  };
  const find = (f: BendSpan["file"] & { dir?: string }) => {
    const lines = f.str.split("\n");
    const found = files.filter((file) => {
      if (
        f.ns !== file.ns ||
        (f.dir !== undefined && f.dir !== file.path.slice(0, file.path.lastIndexOf("/") + 1))
      ) {
        return false;
      }
      const theirs = linesOf(file);
      return (
        lines.length === theirs.length &&
        lines.every(
          (l, i) => l === theirs[i] || (l.trim() === "" && /^\s*import(\s|$)/.test(theirs[i])),
        )
      );
    });
    if (found.length !== 1) {
      throw drift(
        `cannot map a bend.ts span to a file on disk (${found.length} candidates); bend.ts may mask imports another way now`,
      );
    }
    Object.assign(found[0].al, f.al);
    const to = starts(found[0], found[0].str);
    const known = { file: found[0], from: f.str === found[0].str ? to : starts(f, f.str), to };
    memo.set(f, known);
    return known;
  };
  return (s) => {
    if (s === undefined || own.has(s.file)) {
      return s;
    }
    const { file, from, to } = memo.get(s.file) ?? find(s.file);
    if (from === to) {
      return { file, beg: s.beg, end: s.end };
    }
    const at = (off: number): number => {
      const i = line(from, off);
      return to[i] + off - from[i];
    };
    return { file, beg: at(s.beg), end: at(s.end) };
  };
};

// A mapped bend.ts span as a span of a checked source, and back.
const toSpan = (s: BendSpan | undefined): Span | undefined => {
  const file = s && SOURCES.get(s.file);
  return s && file && { file, beg: s.beg, end: s.end };
};

const fromSpan = (s: Span | undefined): BendSpan | undefined =>
  s && { file: FILES.get(s.file)!, beg: s.beg, end: s.end };

// A type or node handle as what it holds, and back.
const scoped = (t: Type): Scoped => t as unknown as Scoped;
const typed = (s: Scoped): Type => s as unknown as Type;
const tree = (n: Node): LTerm => n as unknown as LTerm;
const node = (t: LTerm): Node => t as unknown as Node;

// A fact is its Raw with the public fields added, one object per checked
// term; its type's scope is the Raw itself. `r` must be fresh.
const raw = (fact: Fact): Raw => fact as unknown as Raw;

const record = (r: Raw): Fact =>
  Object.assign(r, {
    node: node(r.tm),
    owner: r.def,
    quantity: QUANTITY[r.qt.$],
    type: typed(r),
    span: toSpan(r.spn),
  });

// Throws a drift error that names each check that failed.
const demand = (checks: Array<[string, boolean]>, say: (wrong: string) => string): void => {
  const wrong = checks.flatMap(([what, ok]) => (ok ? [] : [what]));
  if (wrong.length > 0) {
    throw drift(say(wrong.join(", ")));
  }
};

// f's value, or undefined if it throws.
const tried = <T>(f: () => T): T | undefined => {
  try {
    return f();
  } catch {
    return undefined;
  }
};

const isErr = (e: unknown): e is Err =>
  typeof e === "object" && e !== null && (e as { $?: unknown }).$ === "Err";

// A term's kind, and the name a Var or Ref points to.
const kindOf = (t: LTerm): { kind: string; name: Name } => ({
  kind: t.$,
  name: t.$ === "Var" || t.$ === "Ref" ? t.k : "",
});

// Whether a fact passes a filter, its scope aside.
const matches = (f: FactFilter, kind: string, def: Name, name: Name): boolean => {
  const all = (xs: string[] | undefined, x: string): boolean =>
    xs === undefined || xs.length === 0 || xs.includes(x);
  return (
    all(f.kinds, kind) &&
    (all(f.defs, def) || all(f.defs, def.replace(/~\d+$/, ""))) &&
    all(f.names, name)
  );
};

// bend's words for a failed check, its location aside (a finding has its
// own): expected and observed, with the names in scope, and the note.
const failure = (m: Loaded, e: unknown): string => {
  if (!isErr(e)) {
    return m.Main.book_err(e).replace(/^Error: /, "");
  }
  const show = (x: Err["exp"]): string =>
    m.Bend.expr_show(e.bok, x, m.Bend.ctx_scope(e.ctx), e.spn?.file);
  return (
    (e.obs === undefined
      ? show(e.exp)
      : "expected: " + show(e.exp) + "\nobserved: " + show(e.obs)) +
    (e.nte === undefined ? "" : "\n" + e.nte)
  );
};

// check's work, in its turn. A failure in a file bend did not finish
// loading may not map; it still reports, without a span.
const checked = async (
  m: Loaded,
  file: string,
  filters: FactFilter[],
  signal: AbortSignal,
  all: boolean,
): Promise<Checked> => {
  const { Bend, Main } = m;
  const seen = new Map<string, string | null>();
  const found: Report[] = [];
  const declared: Array<{ kind: Heading["kind"]; name: Name; span: BendSpan }> = [];
  const imported: Array<{ path: string; name: Name; beg: number }> = [];
  const real = fs.existsSync(file) ? fs.realpathSync(file) : "";
  const home = real.slice(0, real.lastIndexOf("/") + 1);
  // A file filter's names are matched later, as each file spells them (see
  // select); the root spells its own defs as the check names them.
  const near = filters.map((f) =>
    f.scope === "program" ? f : { kinds: f.kinds, defs: f.defs, instances: f.instances },
  );
  const far = filters.flatMap((f): FactFilter[] =>
    f.scope === "program" ? [f] : all ? [{ kinds: f.kinds }] : [],
  );
  const beyond = far.length > 0;
  const texts = new Map<string, { text: string; stamp?: Stamp }>();
  reads = texts;
  const instances = filters.some((f) => f.instances === true);
  const seeded = real !== "" && /^import Base$/m.test(fs.readFileSync(real, "utf8"));
  const key = fs.readFileSync(Bend.BASE_BEND, "utf8");
  if (seeded && BASE?.key !== key) {
    BASE = { key, book: Main.book_read(Bend.BASE_BEND) };
  }
  const see = (report: Report): void => {
    const at = report.spn?.file as { dir?: string; ns?: string } | undefined;
    const these = at?.dir === home && at.ns === "" ? near : far;
    if (these.length === 0) {
      return;
    }
    const { kind, name } = kindOf(Bend.term_strip(report.tm));
    if (these.some((f) => matches(f, kind, report.def, name))) {
      found.push(report);
    }
  };
  const read = await Promise.resolve(seeded ? BASE?.book : undefined)
    .then((base) => {
      hook.see = filters.length > 0 ? see : undefined;
      hook.declare = (kind, name, span) => declared.push({ kind, name, span });
      hook.import = (path, name, beg) => imported.push({ path, name, beg });
      return Main.book_read(file, base, seen);
    })
    .then(
      (book) => ({ book }),
      (e: unknown) => ({ e: e instanceof Main.Check_Fail ? e.why : e }),
    );
  reads = undefined;
  signal.throwIfAborted();
  const first = [...seen.keys()].find((real) => real !== Bend.BASE_BEND || !seeded);
  const sources = [...seen.keys()]
    .filter((real) => texts.has(real) || fs.existsSync(real))
    .map((real): Source => {
      const { stamp, text } = texts.get(real) ?? {
        stamp: stampOf(real),
        text: fs.readFileSync(real, "utf8"),
      };
      const source = { path: real, text, base: real === Bend.BASE_BEND };
      if (stamp !== undefined) STAMPS.set(source, stamp);
      const file = { str: text, ns: seen.get(real) ?? "", al: {}, path: real };
      FILES.set(source, file);
      SOURCES.set(file, source);
      return source;
    });
  const root = sources.find((s) => s.path === first);
  const map = mapper(sources.map((s) => FILES.get(s)!));
  if ("book" in read) {
    const { book } = read;
    const insts = new Set(Object.values(book.tmps).flatMap((t) => [...t.values()]));
    const own = new Set<unknown>(
      sources.filter((s) => (beyond ? !foreign(s) : s === root)).map((s) => FILES.get(s)),
    );
    const facts = found.flatMap((f): Array<[LTerm, Fact]> => {
      const spn = map(f.spn);
      const inst = insts.has(f.def);
      return spn !== undefined && own.has(spn.file) && (instances || !inst)
        ? [[f.tm, record({ ...f, inst, spn })]]
        : [];
    });
    const headings = [
      ...imported.flatMap(({ path, name, beg }): Heading[] => {
        const at = sources.find((s) => s.path === path);
        return at === undefined
          ? []
          : [{ kind: "import", name, span: { file: at, beg, end: beg + name.length } }];
      }),
      ...declared.flatMap(({ kind, name, span }): Heading[] => {
        const at = toSpan(map(span));
        return at === undefined ? [] : [{ kind, name, span: at }];
      }),
    ].sort(
      (a, b) =>
        sources.indexOf(a.span.file) - sources.indexOf(b.span.file) || a.span.beg - b.span.beg,
    );
    return {
      book,
      sources,
      root,
      map,
      facts: [...new Map(facts).values()],
      headings,
      beyond,
      instances,
    };
  }
  const err = isErr(read.e) ? read.e : undefined;
  return {
    book: Bend.book_nil(),
    sources,
    root,
    map,
    facts: [],
    headings: [],
    beyond,
    instances,
    failure: {
      code: "bend/check",
      severity: "error",
      message: failure(m, read.e),
      span: tried(() => toSpan(map(err?.spn))),
      def: err?.def,
      fixes: [],
      core: read.e,
    },
  };
};

// Whether every file a check read still has the text it read; `text` is
// what an editor holds unsaved, by real path. A file whose stamp holds is
// unchanged; any other is read and compared, and stamped again if it is.
const fresh = (run: Checked, text: ReadonlyMap<string, string>): boolean =>
  run.sources.every((s) => {
    const kept = text.get(s.path);
    if (kept !== undefined) {
      return kept === s.text;
    }
    const now = stampOf(s.path);
    if (holds(STAMPS.get(s), now)) {
      return true;
    }
    const same = tried(() => nodeFs.readFileSync(s.path, "utf8")) === s.text;
    if (same && now !== undefined) {
      STAMPS.set(s, now);
    }
    return same;
  });

// Checks a book as `bend <file>` does (not main.ts's verdict on @unsafe and
// foreign code), with `text` in place of the files on disk, one check at a
// time. A fact is kept only if a filter wants it, and only if its span maps
// to the root (with `all`, or a filter of scope program, to any file but
// Base). With `reuse`, the last check of `file` that passed is given again
// while the filters and every file it read are unchanged.
export const check = (
  m: Loaded,
  file: string,
  filters: FactFilter[],
  signal: AbortSignal,
  {
    text,
    all = false,
    reuse = false,
  }: { text?: ReadonlyMap<string, string>; all?: boolean; reuse?: boolean } = {},
): Promise<Checked> => {
  const turn = queue.then(async (): Promise<Checked> => {
    signal.throwIfAborted();
    const held = new Map(
      [...(text ?? [])]
        .filter(([at]) => fs.existsSync(at))
        .map(([at, str]) => [fs.realpathSync(at), str]),
    );
    const real = fs.existsSync(file) ? fs.realpathSync(file) : file;
    const key = JSON.stringify([m.BEND2, filters, all]);
    const known = REUSED.get(real);
    if (reuse && known?.key === key && fresh(known.run, held)) {
      return known.run;
    }
    held.forEach((str, at) => unsaved.set(at, str));
    try {
      const run = await checked(m, file, filters, signal, all);
      if (reuse && run.failure === undefined) {
        REUSED.set(real, { key, run });
      }
      return run;
    } finally {
      hook.see = undefined;
      hook.declare = undefined;
      hook.import = undefined;
      reads = undefined;
      unsaved.clear();
    }
  });
  queue = turn.catch(() => undefined);
  return turn;
};

// What every rule of a run shares over one check, each made once, when
// first asked: walks, each file's spelling and declarations, aliases by
// parsed text, the book's order, the sources by path, and the facts by file.
type Shared = {
  walked: Map<LTerm, LTerm[]>;
  parents?: Map<LTerm, LTerm>;
  spellings: Map<Source, Spelling>;
  declares: Map<Source, (text: string) => boolean>;
  aliases?: Map<string, Record<Name, Name>>;
  order?: Order;
  paths?: Map<string, Source>;
  byFile?: Map<unknown, Fact[]>;
  syntax?: Map<Source, Syntax>;
};

const SHARED = new WeakMap<Checked, Shared>();

const sharedOf = (run: Checked): Shared => {
  const known = SHARED.get(run) ?? {
    walked: new Map(),
    spellings: new Map(),
    declares: new Map(),
  };
  SHARED.set(run, known);
  return known;
};

// The files `file` imports by path (not Base or the hub), with their
// aliases, of those the check read.
const importsOf = (run: Checked, shared: Shared, file: Source): Array<[Name, Source]> => {
  shared.paths ??= new Map(run.sources.map((s) => [s.path, s]));
  return [...file.text.matchAll(/^import\s+(\S+)\s+as\s+(\w+)/gm)].flatMap(([, at, alias]) => {
    const imported = shared.paths!.get(resolve(file.path, "..", at));
    return imported === undefined ? [] : [[alias, imported]];
  });
};

// The aliases of each parsed text, from the spans of the book's terms:
// one walk per check.
const aliasesOf = (m: Loaded, book: Book): Map<string, Record<Name, Name>> => {
  const out = new Map<string, Record<Name, Name>>();
  for (const tld of Object.values(book.tlds)) {
    for (const t of [tld.T, ...(tld.$ === "Def" && tld.v ? [tld.v] : [])]) {
      for (const tm of walk(m.Bend.term_lower(t))) {
        if (tm.s !== undefined && !out.has(tm.s.file.str)) {
          out.set(tm.s.file.str, tm.s.file.al);
        }
      }
    }
  }
  return out;
};

const unimported = (text: string): string => {
  const code = text.replace(SOURCE_TOKEN, (t) =>
    ["#", '"', "'"].includes(t[0]) ? t.replace(/[^\r\n]/g, " ") : t,
  );
  const declaration = code.search(/^[ \t]*(?:@unsafe\s+)?(?:def|type|law)\b/m);
  const end = declaration < 0 ? text.length : declaration;
  return text.replace(/^[ \t]*import[^\S\n].*$/gm, (s, at: number) =>
    at < end && /^[ \t]*import\b/.test(code.slice(at)) ? "" : s,
  );
};

// How `file` spells the check's names, as bend's own name_show prints them
// for it: its own names bare, an import's through its alias, any other
// name as the check has it. `aliases` maps each alias to the check's
// namespace (from bend's spans, else from the import lines), `qualify`
// reads a name as `file` would declare it, and `key` finds the check's
// name for a spelling.
const spellingOf = (m: Loaded, run: Checked, shared: Shared, file: Source): Spelling => {
  const ns = FILES.get(file)!.ns;
  const aliases = importsOf(run, shared, file).reduce<Record<Name, Name>>(
    (known, [alias, imported]) =>
      known[alias] !== undefined ? known : { ...known, [alias]: FILES.get(imported)!.ns },
    /^import\s+\S+\s+as\s+/m.test(file.text)
      ? ((shared.aliases ??= aliasesOf(m, run.book)).get(unimported(file.text)) ?? {})
      : {},
  );
  const shown = { str: "", ns, al: aliases, path: file.path };
  const qualify = (name: string): Name => {
    const dot = name.indexOf(".");
    return dot >= 0 && aliases[name.slice(0, dot)] !== undefined
      ? aliases[name.slice(0, dot)] + ":" + name.slice(dot + 1)
      : (ns ? ns + ":" : "") + name;
  };
  return {
    ns,
    aliases,
    file: shown,
    qualify,
    spell: (k) => m.Bend.name_show(shown, k),
    key: (name) =>
      [qualify(name), name, name.replace(".", ":")].find((k) => run.book.tlds[k] !== undefined) ??
      name,
  };
};

const spellingIn = (m: Loaded, run: Checked, file: Source): Spelling => {
  const shared = sharedOf(run);
  const known = shared.spellings.get(file) ?? spellingOf(m, run, shared, file);
  shared.spellings.set(file, known);
  return known;
};

const factsByFile = (facts: Fact[]): Map<unknown, Fact[]> => {
  const out = new Map<unknown, Fact[]>();
  for (const f of facts) {
    const at = raw(f).spn?.file;
    out
      .set(at, out.get(at) ?? [])
      .get(at)!
      .push(f);
  }
  return out;
};

// A fact as `spelling` names it: its owner, and the names its type shows.
const spelled = (fact: Fact, spelling: Spelling): Fact => {
  const r = raw(fact);
  return {
    ...fact,
    owner: spelling.spell(fact.owner),
    type: typed({ ty: r.ty, bok: r.bok, dep: r.dep, spelled: spelling.file }),
  };
};

// The facts one rule asked for, of those kept for all rules, for a run on
// `file`. A file rule matches defs and names as `file` spells
// them, and gets its facts spelled so; a program rule gets the check's
// names.
export const select = (m: Loaded, run: Checked, want: FactFilter, file: Source): Fact[] => {
  const program = want.scope === "program";
  const spelling = program ? undefined : spellingIn(m, run, file);
  const shared = sharedOf(run);
  const byFile = (shared.byFile ??= factsByFile(run.facts));
  const near = program || !run.beyond ? run.facts : (byFile.get(FILES.get(file)) ?? []);
  const named = (k: Name): Name => (spelling === undefined ? k : spelling.spell(k));
  const kept =
    [want.kinds, want.defs, want.names].every((xs) => !xs?.length) &&
    (want.instances === true || !run.instances)
      ? near
      : near.filter((fact) => {
          const r = raw(fact);
          const { kind, name } = kindOf(m.Bend.term_strip(r.tm));
          return (
            (want.instances === true || !r.inst) && matches(want, kind, named(r.def), named(name))
          );
        });
  return spelling === undefined ? kept : kept.map((f) => spelled(f, spelling));
};

// Where each declaration first sits in the book's order, where each
// namespace's first declaration does, and the type each constructor
// belongs to.
type Order = { at: Map<Name, number>; first: Map<Name, number>; ctr: Map<Name, Name> };

const orderOf = (book: Book): Order => {
  const out: Order = { at: new Map(), first: new Map(), ctr: new Map() };
  book.order.forEach((k, i) => {
    const colon = k.indexOf(":");
    const ns = colon < 0 ? "" : k.slice(0, colon);
    const tld = book.tlds[k];
    if (!out.at.has(k)) out.at.set(k, i);
    if (!out.first.has(ns)) out.first.set(ns, i);
    if (tld?.$ === "ADT") for (const c of tld.c) out.ctr.set(c.k, k);
  });
  return out;
};

// `under` without the keys `hidden` names; what is written goes to a layer
// of its own, so `under` never changes. bend's parser only reads, tests and
// writes keys.
const layer = <T>(under: Record<Name, T>, hidden: (k: Name) => boolean): Record<Name, T> => {
  const over: Record<Name, T> = Object.create(null);
  const shown = (k: string | symbol): k is string =>
    typeof k === "string" && (Object.hasOwn(over, k) || (!hidden(k) && k in under));
  return new Proxy(over, {
    has: (_, k) => shown(k),
    get: (_, k) => (!shown(k) ? undefined : Object.hasOwn(over, k) ? over[k] : under[k]),
    ownKeys: () => [
      ...new Set([...Object.keys(over), ...Object.keys(under).filter((k) => !hidden(k))]),
    ],
    getOwnPropertyDescriptor: (_, k) =>
      shown(k)
        ? {
            value: Object.hasOwn(over, k) ? over[k] : under[k],
            writable: true,
            enumerable: true,
            configurable: true,
          }
        : undefined,
  });
};

// Of the check's names a file in namespace `ns` declares, those that fill a
// law of another file: a def of an aliased name fills it.
const fillsIn = (book: Book, ns: Name, own: Name[]): Set<Name> =>
  new Set(
    own.filter((k) => k.includes(":") && !k.startsWith(ns + ":") && book.tlds[k]?.$ === "Def"),
  );

// Parse in the file's original scope, with writes confined to a fresh layer.
const parseSource = (m: Loaded, run: Checked, shared: Shared, file: Source, text: string): Book => {
  const { Bend } = m;
  const { book, root } = run;
  const { ns, aliases, qualify } = spellingIn(m, run, file);
  const dir = file.path.slice(0, file.path.lastIndexOf("/") + 1);
  const own = run.headings
    .filter((d) => d.span.file === file && (d.kind === "def" || d.kind === "type"))
    .map((d) => qualify(d.name));
  const fills = fillsIn(book, ns, own);
  const gone = new Set(own.filter((k) => !fills.has(k)));
  const order = (shared.order ??= orderOf(book));
  const cut = file === root ? Infinity : (order.first.get(ns) ?? Infinity);
  const hidden = (k: Name): boolean => gone.has(k) || (order.at.get(k) ?? -1) >= cut;
  const parsed = Bend.book_nil();
  parsed.tlds = layer(book.tlds, hidden);
  parsed.ctrs = layer(book.ctrs, (c) => {
    const owner = order.ctr.get(c);
    return owner !== undefined && hidden(owner);
  });
  for (const k of fills) {
    const tld = book.tlds[k];
    parsed.tlds[k] = tld.$ === "Def" ? { ...tld, v: null, i: undefined, u: false } : tld;
  }
  // A check can be waiting on I/O meanwhile; its headings are not this parse's.
  const held = hook.declare;
  hook.declare = undefined;
  try {
    Bend.parse_book(parsed, dir, unimported(text), ns, aliases);
  } finally {
    hook.declare = held;
  }
  return parsed;
};

const sameDeclarations = (
  m: Loaded,
  run: Checked,
  shared: Shared,
  file: Source,
): ((text: string) => boolean) => {
  const { Bend } = m;
  const snapshot = (text: string) => {
    const parsed = parseSource(m, run, shared, file, text);
    const lower = (t: HTerm | null) => (t === null ? null : Bend.term_lower(t));
    return JSON.stringify(
      parsed.order.map((k) => {
        const t = parsed.tlds[k];
        return t.$ === "ADT"
          ? [k, t.n, t.g, lower(t.T), t.c.map((c) => [c.k, c.n, lower(c.T)])]
          : [k, t.n, t.x, t.u ?? false, t.i, lower(t.T), lower(t.v)];
      }),
      (k, v) => (k === "s" ? undefined : v),
    );
  };
  const original = tried(() => snapshot(file.text));
  return (text) => original !== undefined && tried(() => snapshot(text)) === original;
};

const syntaxOf = (m: Loaded, run: Checked, shared: Shared, file: Source): Syntax => {
  const out: Syntax = { declarations: [], references: [] };
  const { qualify, aliases } = spellingIn(m, run, file);
  const read = run.headings
    .filter((d) => d.span.file === file)
    .map((d) => ({ ...d, name: qualify(d.name) }));
  const heads = read.filter((d) => d.kind === "def" || d.kind === "type");
  const backwards = [...heads].reverse();
  // bend reads only imports before the first declaration, so one encloses
  // every span it parses after them.
  const enclosing = (span: Span) => {
    const found = backwards.find((d) => d.span.beg <= span.beg);
    if (found === undefined) {
      throw drift(`no declaration encloses ${file.path}:${span.beg}`);
    }
    return found;
  };
  out.declarations.push(
    ...read
      .filter((d) => d.kind === "constructor")
      .map((d) => ({ ...d, key: d.name, owner: enclosing(d.span).name })),
  );
  const indices = new Map<string, number>();
  const localKey = (index: number, span: Span): number => {
    const key = [enclosing(span).span.beg, index].join("\0");
    const known = indices.get(key) ?? indices.size;
    indices.set(key, known);
    return known;
  };
  const at = (s: BendSpan | undefined): Span | undefined => toSpan(run.map(s));
  const reference = (key: Name | number, s: BendSpan | undefined): void => {
    const span = at(s);
    if (span !== undefined)
      out.references.push({
        key: typeof key === "number" ? localKey(key, span) : key,
        owner: enclosing(span).name,
        span,
      });
  };
  heads.forEach((d) => {
    const alias = file.text.slice(d.span.beg, d.span.end).split(".")[0];
    if (aliases[alias] !== undefined) reference(d.name, fromSpan(d.span));
  });
  const binding = (
    name: Name,
    index: number,
    s: BendSpan | undefined,
    kind: Declaration["kind"],
    type?: Scoped,
  ): void => {
    const span = at(s);
    if (span === undefined || span.file !== file) return;
    const token = file.text.slice(span.beg, span.end).match(/^[@&]?\s*[+-]?\s*([A-Za-z_]\w*)/);
    if (token?.[1] !== name) return;
    const beg = span.beg + token[0].length - name.length;
    out.declarations.push({
      key: localKey(index, span),
      kind,
      name,
      owner: enclosing(span).name,
      span: { file, beg, end: beg + name.length },
      ...(type === undefined ? {} : { type }),
    });
  };
  const visited = new WeakSet<LTerm>();
  const globals = new Set<Extract<LTerm, { $: "Ref" | "ADT" | "Ctr" | "Mat" | "Lit" }>>();
  hook.parse = {
    binding,
    term: (p, root) => {
      const stack = [root];
      for (let t = stack.pop(); t !== undefined; t = stack.pop()) {
        if (visited.has(t)) continue;
        visited.add(t);
        stack.push(...children(t));
        switch (t.$) {
          case "Ref":
          case "ADT":
          case "Ctr":
          case "Mat":
          case "Lit":
            globals.add(t);
            break;
          case "Var":
            if (t.v?.$ === "Ref") globals.add(t.v);
            else reference(t.i, t.s);
            break;
          case "All":
          case "Lam":
            if (t.s !== undefined && /^[@&]/.test(p.str.slice(t.s.beg, t.s.end))) {
              binding(t.k, t.i, t.s, "parameter");
            }
        }
      }
    },
  };
  try {
    const parsed = parseSource(m, run, shared, file, file.text);
    // The first `n` binders of `T`, those from `from` on declared as
    // `kind` with their written types, and the type after them.
    const telescope = (T: HTerm, n: number, from: number, kind: Declaration["kind"]): Scoped => {
      let t = T;
      let i = 0;
      for (; i < n && t.$ === "All"; i += 1) {
        if (i >= from) binding(t.k, t.i, t.s, kind, { ty: t.A, bok: parsed, dep: i });
        t = t.B(m.Bend.Var(t.k, i));
      }
      return { ty: t, bok: parsed, dep: i };
    };
    for (const d of heads) {
      const tld = parsed.tlds[d.name];
      out.declarations.push({ ...d, key: d.name, type: telescope(tld.T, tld.n, 0, "parameter") });
      if (tld.$ === "ADT") {
        tld.c.forEach((c) => telescope(c.T, tld.n + c.n, tld.n, "field"));
      }
    }
  } finally {
    hook.parse = undefined;
  }
  for (const t of globals) {
    reference(t.k, t.s);
  }
  const declarations = [...new Map(out.declarations.map((d) => [d.span.beg, d])).values()];
  const binders = new Set(
    declarations.filter((d) => typeof d.key === "number").map((d) => d.span.beg),
  );
  const references = [
    ...new Map(
      out.references
        .filter((r) => !binders.has(r.span.beg))
        .map((r) => [[r.key, r.span.beg].join("\0"), r]),
    ).values(),
  ];
  return { declarations, references };
};

const declarationsOf = (
  m: Loaded,
  run: Checked,
  shared: Shared,
  file: Source,
  program: boolean,
): Declaration[] => {
  if (run.failure !== undefined) return [];
  const files = program ? run.sources.filter((s) => !foreign(s)) : [file];
  const syntax = files.map((f) => {
    shared.syntax ??= new Map();
    const known = shared.syntax.get(f) ?? syntaxOf(m, run, shared, f);
    shared.syntax.set(f, known);
    return { file: f, ...known };
  });
  const target = (key: Name | number, file: Source): string =>
    typeof key === "string" ? "global\0" + key : [file.path, key].join("\0");
  const references = syntax
    .flatMap((s) => s.references)
    .reduce((groups, r) => {
      const key = target(r.key, r.span.file);
      groups.set(key, groups.get(key) ?? []);
      groups.get(key)!.push(r);
      return groups;
    }, new Map<string, Syntax["references"]>());
  const spelling = program ? undefined : spellingIn(m, run, file);
  const name = (k: Name): Name => (spelling === undefined ? k : spelling.spell(k));
  const symbols = syntax.flatMap((s) => {
    const fills = fillsIn(
      run.book,
      spellingIn(m, run, s.file).ns,
      s.declarations.flatMap((d) => (d.kind === "def" && typeof d.key === "string" ? [d.key] : [])),
    );
    return s.declarations.map((d): Declaration => ({
      kind: d.kind,
      name: typeof d.key === "number" ? d.name : name(d.name),
      owner: d.owner === undefined ? undefined : name(d.owner),
      span: d.span,
      references: (references.get(target(d.key, s.file)) ?? []).map((r) => ({
        owner: name(r.owner),
        span: r.span,
      })),
      ...(typeof d.key === "string" && fills.has(d.key) ? { fills: true } : {}),
      ...(d.type === undefined
        ? {}
        : {
            type: typed({
              ...d.type,
              ...(program ? {} : { spelled: spellingIn(m, run, s.file).file }),
            }),
          }),
    }));
  });
  const imports = syntax.flatMap((s) =>
    run.headings
      .filter((d) => d.span.file === s.file && d.kind === "import")
      .map(({ name: alias, span }): Declaration => {
        const aliases = spellingIn(m, run, s.file).aliases;
        const loads = run.sources.find((f) =>
          alias === "Base" ? f.base : !f.base && FILES.get(f)!.ns === aliases[alias],
        );
        const refs = s.references.filter((r) => {
          if (typeof r.key !== "string") return false;
          const explicit = s.file.text
            .slice(r.span.beg, r.span.end)
            .match(/^([A-Za-z_]\w*)\./)?.[1];
          if (explicit !== undefined && aliases[explicit] !== undefined) return explicit === alias;
          const ns = r.key.includes(":") ? r.key.slice(0, r.key.indexOf(":")) : "";
          const family = (shared.order ??= orderOf(run.book)).ctr.get(r.key);
          return alias === "Base"
            ? run.book.tlds[family ?? r.key]?.b === true
            : aliases[alias] === ns;
        });
        return {
          kind: "import",
          name: alias,
          span,
          references: refs.map((r) => ({ owner: name(r.owner), span: r.span })),
          ...(loads === undefined ? {} : { loads }),
        };
      }),
  );
  return [...symbols, ...imports].sort(
    (a, b) => files.indexOf(a.span.file) - files.indexOf(b.span.file) || a.span.beg - b.span.beg,
  );
};

// What a rule asks bend2, over one check's book and facts, for a run on
// `file`: a file rule's names are spelled as `file` spells them, a program
// rule's are the check's. Walks are shared by every rule of the run: each
// root's nodes, and the parents of every node of the program's bodies (Base
// aside), are found once, when first asked.
export const operations = (m: Loaded, run: Checked, file: Source, program: boolean): Operations => {
  const { Bend } = m;
  const shared = sharedOf(run);
  const spelling = program ? undefined : spellingIn(m, run, file);
  const nodes = (t: LTerm): LTerm[] => {
    const known = shared.walked.get(t) ?? [...walk(t)];
    shared.walked.set(t, known);
    return known;
  };
  return {
    declarations: (of) =>
      of === undefined
        ? declarationsOf(m, run, shared, file, program)
        : of.base || !run.sources.includes(of)
          ? []
          : declarationsOf(m, run, shared, of, false),
    body: (name) => {
      const tld = run.book.tlds[spelling === undefined ? name : spelling.key(name)];
      return tld?.$ === "Def" && tld.e !== undefined ? node(tld.e) : undefined;
    },
    shape: (n): Shape => {
      const t = tree(n);
      const { kind, name } = kindOf(t);
      return {
        kind,
        name: spelling === undefined || name === "" ? name : spelling.spell(name),
        span: toSpan(run.map(t.s)),
        children: children(t).map(node),
      };
    },
    nodes: (n) => nodes(tree(n)).map(node),
    parent: (n) => {
      shared.parents ??= new Map(
        Object.values(run.book.tlds)
          .flatMap((tld) => (tld.$ === "Def" && tld.e !== undefined && !tld.b ? nodes(tld.e) : []))
          .flatMap((t) => children(t).map((c): [LTerm, LTerm] => [c, t])),
      );
      const p = shared.parents.get(tree(n));
      return p === undefined ? undefined : node(p);
    },
    strip: (n) => node(Bend.term_strip(tree(n))),
    binder: (fact) => {
      const r = raw(fact);
      const v = Bend.term_strip(r.tm);
      const ann = v.$ === "Var" ? Bend.pmap_get(r.ctx, v.i) : null;
      return ann === null
        ? undefined
        : typed({ ty: ann.T, bok: r.bok, dep: r.dep, spelled: scoped(fact.type).spelled });
    },
    uses: (fact) => {
      const r = raw(fact);
      return Bend.pmap_to_array(r.us).flatMap(([v, q]) =>
        q.$ === "None" ? [] : [{ name: Bend.pmap_get(r.ctx, v)?.k ?? "", quantity: QUANTITY[q.$] }],
      );
    },
    same: (a, b) => {
      const { ty, bok, dep } = scoped(a);
      return Bend.term_compare("EQ", bok, ty, scoped(b).ty, dep);
    },
    show: (t) => {
      const { ty, dep, spelled } = scoped(t);
      return Bend.term_show(Bend.term_lower(ty, dep), -1, [], spelled);
    },
    normal: (t) => {
      const { ty, bok, dep, spelled } = scoped(t);
      return typed({ ty: Bend.term_snf(bok, ty), bok, dep, spelled });
    },
    sameDeclarations: (text) => {
      const known = shared.declares.get(file) ?? sameDeclarations(m, run, shared, file);
      shared.declares.set(file, known);
      return known(text);
    },
  };
};

export const unstable = (m: Loaded, run: Checked): Unstable => ({
  Bend: m.Bend,
  book: run.book,
  raw,
});

// bend's own error layout for a finding, under `head`: its message,
// context and location.
export const layout = (m: Loaded, d: Diag, head: string): string => {
  const r = d.fact && raw(d.fact);
  return m.Bend.err_show(
    isErr(d.core)
      ? d.core
      : m.Bend.Err(
          r?.bok ?? m.Bend.book_nil(),
          r?.ctx ?? m.Bend.ctx_nil(),
          d.message,
          undefined,
          fromSpan(d.span),
          d.def,
        ),
  ).replace(/^Error:/, head);
};

const digest = (text: string): string => Bun.hash(text).toString(36);

const hashed = (p: string): string | undefined => {
  const text = tried(() => nodeFs.readFileSync(p, "utf8"));
  return text === undefined ? undefined : digest(text);
};

// The compiler's hash: bend2's sources, and this file, which patches them.
const compilerOf = (m: Loaded): string => {
  const known =
    COMPILERS.get(m) ??
    digest(
      [...["bend.ts", "comp.ts", "main.ts"].map((f) => nodePath.join(m.BEND2, f)), import.meta.path]
        .map((p) => hashed(p) ?? "")
        .join("\0"),
    );
  COMPILERS.set(m, known);
  return known;
};

// The .js files of a book's foreign defs: comp.ts copies them into the JS.
const effectsOf = (book: Book): string[] => [
  ...new Set(
    Object.values(book.tlds).flatMap((t) =>
      t.$ === "Def" && t.i !== undefined
        ? t.i.filter((x) => x.endsWith(".js")).map((x) => slash(nodeFs.realpathSync(x)))
        : [],
    ),
  ),
];

const keptPath = (file: string): string =>
  nodePath.join(KEPT, digest(slash(nodePath.resolve(file))) + ".json");

const unchanged = (m: Loaded, kept: Kept): boolean =>
  kept.compiler === compilerOf(m) && kept.files.every(([p, h]) => hashed(p) === h);

const made = (m: Loaded, kept: Kept): Compiled => {
  const { js, ...rule } = kept.rule;
  return {
    ...rule,
    // The rule is Bend's own compiled JS, run as comp.ts io_run runs it.
    // oxlint-disable-next-line typescript/no-implied-eval
    main: new Function("require", js)(import.meta.require) as (args: string[]) => number,
    current: () => unchanged(m, kept),
  };
};

// Writes `kept` whole or not at all, and drops the entries of rule files
// that are gone. A cache that cannot be written is skipped.
const keep = (kept: Kept): void => {
  tried(() => {
    nodeFs.mkdirSync(KEPT, { recursive: true });
    for (const name of nodeFs.readdirSync(KEPT)) {
      const at = nodePath.join(KEPT, name);
      const old = tried(() => JSON.parse(nodeFs.readFileSync(at, "utf8")) as Kept);
      if (old === undefined || !nodeFs.existsSync(old.file)) tried(() => nodeFs.rmSync(at));
    }
    const to = keptPath(kept.file);
    const temp = `${to}.${process.pid}.${Date.now()}`;
    nodeFs.writeFileSync(temp, JSON.stringify(kept));
    nodeFs.renameSync(temp, to);
  });
};

// A Bend rule's id(), facts(), options(), entries() and main(), compiled as
// comp.ts io_run does. facts(), checked: NoFacts{} gives null, Want{...} a
// filter. options(): each Lint.Declared as a schema with its default.
// entries(), if defined: SomeEntry{} or EveryEntry{}. The result is also kept
// on disk, for cachedRule.
export const compile = (m: Loaded, checked: Checked, file: string): Compiled => {
  const { book } = checked;
  const { Bend, Comp } = m;
  const value = (k: Name): LTerm | undefined => {
    const tld = book.tlds[k];
    return tld?.$ === "Def" && tld.n === 0 && tld.v !== null
      ? Bend.term_lower(Bend.term_snf(book, tld.v))
      : undefined;
  };
  const shown = value("id");
  const id = shown === undefined ? undefined : Bend.term_show(shown).match(/^"([^"\\]*)"$/)?.[1];
  const args = (t: LTerm | undefined, ctr: string): LTerm[] | undefined =>
    t?.$ === "Ctr" && (t.k === ctr || t.k.endsWith(":" + ctr)) ? t.x : undefined;
  const list = <T>(t: LTerm | undefined, of: (x: LTerm) => T | undefined): T[] | undefined => {
    const [head, tail] = args(t, "Con") ?? [];
    const first = head && of(head);
    const rest = tail && list(tail, of);
    return args(t, "Nil") !== undefined
      ? []
      : first !== undefined && rest
        ? [first, ...rest]
        : undefined;
  };
  const text = (t: LTerm | undefined): string | undefined =>
    t?.$ === "Lit" && typeof t.v === "string" ? t.v : undefined;
  const whole = (t: LTerm | undefined): number | undefined =>
    t?.$ === "Lit" && t.k === "U32" ? t.v : undefined;
  const texts = (t: LTerm | undefined): string[] | undefined => list(t, text);
  // The first of `table`'s constructors that `t` is, read by its decoder.
  const one = <T>(t: LTerm | undefined, table: Record<string, (xs: LTerm[]) => T>): T | undefined =>
    Object.entries(table).flatMap(([k, of]) => {
      const xs = args(t, k);
      return xs === undefined ? [] : [of(xs)];
    })[0];
  const bool = (t: LTerm | undefined): boolean | undefined =>
    one(t, { True: () => true, False: () => false });
  const known = <T extends object>(x: T | undefined): T | undefined =>
    x === undefined || Object.values(x).includes(undefined) ? undefined : x;
  // A Lint.Spec as a schema, and a Lint.Value as an option value.
  const schema = (t: LTerm | undefined): Record<string, unknown> | undefined =>
    known(
      one<Record<string, unknown>>(t, {
        NumberOption: ([lo, hi]) => ({ type: "integer", minimum: whole(lo), maximum: whole(hi) }),
        FlagOption: () => ({ type: "boolean" }),
        TextOption: ([choices]) =>
          args(choices, "Nil") === undefined
            ? { type: "string", enum: texts(choices) }
            : { type: "string" },
        AnyOption: ([specs]) => ({ anyOf: list(specs, schema) }),
      }),
    );
  const optionValue = (t: LTerm | undefined): OptionValue | undefined =>
    one<OptionValue | undefined>(t, {
      Num: ([n]) => whole(n),
      Flag: ([b]) => bool(b),
      Text: ([x]) => text(x),
    });
  const declare = (t: LTerm): [string, Declared] | undefined => {
    const [key, given, spec] = args(t, "Declared") ?? [];
    const name = text(key);
    const accepts = schema(spec);
    const fallback = optionValue(given);
    return name === undefined || accepts === undefined || fallback === undefined
      ? undefined
      : [name, { ...accepts, default: fallback }];
  };
  const asked = value("facts");
  const [scope, kinds, defs, names, instances] = args(asked, "Want") ?? [];
  const want =
    args(asked, "NoFacts") !== undefined
      ? null
      : known({
          scope: one(scope, { File: () => "file" as const, Program: () => "program" as const }),
          kinds: texts(kinds),
          defs: texts(defs),
          names: texts(names),
          instances: bool(instances),
        });
  const declared = book.tlds.options === undefined ? [] : list(value("options"), declare);
  const entries =
    book.tlds.entries === undefined
      ? null
      : one(value("entries"), {
          SomeEntry: () => "some" as const,
          EveryEntry: () => "every" as const,
        });
  if (
    id === undefined ||
    Comp.io_type(book) === null ||
    want === undefined ||
    declared === undefined ||
    entries === undefined
  ) {
    throw new Error(
      file +
        " must define id() -> String, facts() -> Lint.Want, main() -> IO(Unit), options() -> List<&2, Lint.Declared> if it has options, and entries() -> Lint.Entries if it says how entries count",
    );
  }
  const kept: Kept = {
    file: slash(nodePath.resolve(file)),
    compiler: compilerOf(m),
    files: [
      ...checked.sources.map((s): [string, string] => [s.path, digest(s.text)]),
      ...effectsOf(book).map((p): [string, string] => [p, hashed(p) ?? ""]),
    ],
    rule: {
      id,
      want,
      ...(declared.length === 0 ? {} : { options: Object.fromEntries(declared) }),
      ...(entries === null ? {} : { entries }),
      js: `${Comp.js_lib(book)}\n${Comp.RUNTIME_MAIN}\nreturn (args) => { cli_args = args; return io_run(${Comp.js_sat("main")}); };`,
    },
  };
  keep(kept);
  return made(m, kept);
};

// The rule kept on disk for `file`, if its compiler and every file it was
// made from are unchanged.
export const cachedRule = (m: Loaded, file: string): Compiled | undefined =>
  tried(() => {
    const kept = JSON.parse(nodeFs.readFileSync(keptPath(file), "utf8")) as Kept;
    return unchanged(m, kept) ? made(m, kept) : undefined;
  });

// What main.ts must give, as bend-lint calls it; a mismatch is a drift
// error.
export const guardMain = (Main: Main): void =>
  demand(
    [
      ["book_read(file, base, seen = ...)", Main.book_read?.length === 2],
      ["book_err(e)", Main.book_err?.length === 1],
      [
        "new Check_Fail(why).why",
        typeof Main.Check_Fail === "function" && new Main.Check_Fail(MARK).why === MARK,
      ],
    ],
    (wrong) => `bend2/main.ts no longer has ${wrong}; update PATCHES in src/seam.ts`,
  );

// Checks src/bend/sample.bend as a rule sees it. `x` in `def id(x: N) -> N: x`
// must be a Var typed N, bound as an N, used once, at its own span; `id` in
// main is reported only by term_infer, and the Lam only by term_check.
const selfCheck = async (m: Loaded): Promise<void> => {
  const run = await check(m, SAMPLE, [{}], new AbortController().signal);
  const ops = operations(m, run, run.root!, false);
  const views = run.facts.map((fact) => ({ fact, ...ops.shape(ops.strip(fact.node)) }));
  const x = views.find((v) => v.kind === "Var" && v.name === "x");
  const bound = x && ops.binder(x.fact);
  const declarations = ops.declarations();
  demand(
    [
      ["check", run.failure === undefined],
      ["Ref id (term_infer)", views.some((v) => v.kind === "Ref" && v.name === "id")],
      ["Lam (term_check)", views.some((v) => v.kind === "Lam")],
      ["type", x !== undefined && ops.show(x.fact.type) === "N"],
      ["scope", bound !== undefined && ops.show(bound) === "N"],
      ["quantity", x?.fact.quantity === "once"],
      ["uses", JSON.stringify(x && ops.uses(x.fact)) === '[{"name":"x","quantity":"once"}]'],
      ["span", x?.fact.span?.file.text.slice(x.fact.span.beg, x.fact.span.end) === "x"],
      [
        "declarations",
        declarations.some((d) => d.kind === "def" && d.name === "id" && d.references.length === 1),
      ],
      [
        "bindings",
        declarations.some(
          (d) =>
            d.kind === "parameter" &&
            d.name === "x" &&
            d.owner === "id" &&
            d.references.length === 1,
        ),
      ],
      [
        "constructors",
        declarations.some(
          (d) =>
            d.kind === "constructor" &&
            d.name === "Z" &&
            d.owner === "N" &&
            d.references.length === 1,
        ),
      ],
    ],
    (wrong) =>
      `self-check failed: the patched bend2 gave the wrong ${wrong} for src/bend/sample.bend; update src/seam.ts`,
  );
};

// Finds bend2, patches its PATCHED files as Bun loads them, imports them,
// and checks them (guardMain, selfCheck).
export const load = async (given: string | undefined): Promise<Loaded> => {
  const dir = await bendDir(given);
  const patched = new Map(
    PATCHED.map((f) => [path.join(dir, f), patch(f, fs.readFileSync(path.join(dir, f), "utf8"))]),
  );
  const exact = dir.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replaceAll("/", "[\\\\/]");
  const names = PATCHED.map((f) => f.replace(/\.ts$/, "")).join("|");
  const filter = new RegExp(
    `^${exact}[\\\\/](${names})\\.ts$`,
    process.platform === "win32" ? "i" : "",
  );
  Bun.plugin({
    name: "bend-lint",
    setup: (build) => {
      build.onLoad({ filter }, (args) => {
        const contents = patched.get(fs.realpathSync(args.path));
        if (contents === undefined) {
          throw drift(`bend-lint matched ${args.path} but did not patch it`);
        }
        return { contents, loader: "ts" };
      });
    },
  });
  const modules = await Promise.all(
    PATCHED.map((f) => import(url.pathToFileURL(path.join(dir, f)).href)),
  );
  if (modules.some((module) => module[MARK] !== 1)) {
    throw drift("bend2 was loaded before bend-lint could patch it; call createLinter first");
  }
  const [B, C, M] = modules as [typeof BendModule, Comp, Main];
  guardMain(M);
  const loaded = { Bend: B, Comp: C, Main: M, BEND2: dir };
  await selfCheck(loaded);
  return loaded;
};
