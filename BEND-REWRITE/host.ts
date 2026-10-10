// The rewrite's host: see the header of main.bend. The main thread loads and
// patches bend2 and answers effects; the program runs in a worker, whose
// effects ask the main thread and wait for the answer, because bend2's JS
// runtime calls an effect and takes its result at once, and a check is
// async.
//
// Rules are compiled in, because Bend cannot load code while it runs. The
// program is main.bend with the rule files it was compiled with, and knows
// them (compiled()). It parses argv and the config itself; when the rule
// files it wants are not the ones it holds, it asks to restart with them
// (restart_with_rules), and the host runs the program compiled with those,
// with the same argv. That program holds what it wants, so it never asks
// again. Once Bend is written in Bend, the same restart is Bend writing the
// program to a file and running bend on it. A compiled program is kept in
// <cache>/host, keyed by its text and checked against the text of every
// file it was made from, so a run whose sources did not change checks and
// compiles nothing.

// Imports
// =======

import * as nodeFs from "node:fs";
import * as os from "node:os";
import * as nodePath from "node:path";
import * as url from "node:url";
import {
  isMainThread,
  MessageChannel,
  receiveMessageOnPort,
  Worker,
  workerData,
} from "node:worker_threads";
import type { MessagePort } from "node:worker_threads";

import pkg from "../package.json" with { type: "json" };

import type { Book, Err, HTerm, LTerm, Name, Parse } from "bend2/bend.ts";
import type { Span as BendSpan } from "bend2/bend.ts";
import type * as BendModule from "bend2/bend.ts";
import type * as CompModule from "bend2/comp.ts";

// Types
// =====

// A file's patch: exact edits, text it must hold once unchanged (needs), a
// tail appended to the file, and names it must declare once and export.
type Patch = { edits: Array<[string, string]>; needs: string[]; tail: string; exports: string[] };

type Comp = typeof CompModule & { RUNTIME_MAIN: string; js_sat(k: Name): string };

// main.ts as the patch exports it: book_read throws a Check_Fail holding why
// the check failed.
type Main = {
  book_read(file: string, base?: Book, seen?: Map<string, string | null>): Promise<Book>;
  book_err(e: unknown): string;
  Check_Fail: new (why: unknown) => { why: unknown };
};

// bend2 as load gives it, with Base checked and the compiler's hash.
type Loaded = { Bend: typeof BendModule; Comp: Comp; Main: Main; base: Book; compiler: string };

// A main.bend value as plain data: a String, U32 or Bool as itself, a List
// as an array, a constructor as its name in main.bend or Base with its
// fields.
type Plain = string | number | boolean | Plain[] | { $: string; [field: string]: Plain };

// A constructor as compiled JS spells it: its key, and its fields in order.
type Ctor = { key: string; fields: string[] };

// A compiled program: its module, and the constructors its values use.
type Program = { module: string; ctors: Record<string, Ctor> };

// A compiled program as the cache keeps it: the compiler that made it, and
// every file it was made from, with its text's hash.
type Kept = Program & { compiler: string; files: Array<[string, string]> };

// What an effect asks the main thread.
type Ask =
  | { op: "check"; path: string; declarations: boolean; bodies: boolean }
  | { op: "restart"; files: string[] }
  | { op: "same"; path: string; text: string };

// A declaration's or import's name, as bend's parser read it.
type Heading = { kind: "def" | "type" | "constructor"; name: Name; span: BendSpan };
type Imported = { path: string; name: Name; beg: number };

// A term as a rule sees it: its sub-terms (kids), and its BendTerm, given
// where they sit in the body's list.
type View = { kids: LTerm[]; term: (at: number[]) => Plain };

// Where the probes report, for one check at a time.
type Hook = {
  declare?: (kind: Heading["kind"], name: Name, span: BendSpan) => void;
  import?: (path: string, name: Name, beg: number) => void;
  term?: (p: Parse, t: LTerm) => void;
  binding?: (name: Name, index: number, span: BendSpan | undefined, kind: Binding["kind"]) => void;
};

// A binding of a file: a parameter (or named type binder), a variable, or a
// constructor field, with the binder it is and its written type.
type Binding = {
  key: string;
  kind: "parameter" | "variable" | "field";
  name: Name;
  owner: Name;
  beg: number;
  end: number;
  type?: Plain;
};

// A written type, as a type handle holds it: the type, the book and depth of
// its scope.
type Scoped = { ty: HTerm; bok: Book; dep: number };

// A file of a check as a span of bend.ts's copy of it moves to: its path and
// text on disk, and where its lines start in the copy and on disk.
type Placed = { path: string; text: string; from: number[]; to: number[] };

// A check that passed: its book, the files it read with their namespaces,
// the names bend's parser read, and the spans' files, found once each.
type Checked = {
  book: Book;
  root: string;
  seen: Map<string, string | null>;
  headings: Heading[];
  imports: Imported[];
  placed: WeakMap<object, Placed | null>;
  types: Scoped[];
  declared?: string;
  aliases?: Map<string, Record<Name, Name>>;
  order?: Order;
};

// Where each declaration first sits in the book's order, where each
// namespace's first declaration does, and the type each constructor
// belongs to.
type Order = { at: Map<Name, number>; first: Map<Name, number>; ctr: Map<Name, Name> };

// How a file spells the check's names (see spellingOf).
type Spelling = {
  ns: Name;
  aliases: Record<Name, Name>;
  qualify: (name: string) => Name;
  spell: (k: Name) => string;
  shown: BendSpan["file"];
};

// A use of a global name in a file: the name, and where it is.
type Use = { key: Name; owner: Name; beg: number; end: number };

// What the worker gets: the program, its argv, and the channel to the main
// thread.
type Start = Program & { args: string[]; port: MessagePort; flag: Int32Array };

type Host = { ask: (ask: Ask) => unknown };

// Constants
// =========

const HERE = nodePath.dirname(url.fileURLToPath(import.meta.url));
const DRIVE = /^[A-Za-z]:(?=\/)/;
const RELEASE = /^v\d+\.\d+\.\d+$/;
const RAW = "https://raw.githubusercontent.com/bendlang/bend/";
const EFF = /^effs\/[\w.-]+$/;
const GIVE = "set BEND_DIR to a bend checkout";
const MARK = "BEND_HOST_PATCH";
const SHIM = "bend-host:shim";

// The program the load-time self-check reads, never on disk.
const SAMPLE = "sample.bend";
const SAMPLE_TEXT = [
  "type N is Data:",
  "  Z{}",
  "",
  "def id(x: N) -> N:",
  "  x",
  "",
  "def main() -> N:",
  "  id(Z{})",
  "",
].join("\n");

// A comment, a string or char literal (maybe over several lines, maybe
// unterminated), a newline, or any other character that is not a space.
const SOURCE_TOKEN = /#[^\r\n]*|"(?:\\[^]|[^"\\])*(?:"|$)|'(?:\\[^]|[^'\\])*(?:'|$)|\n|[^\s#"']+/g;

const HOOK: Hook = {};

// The constructors a literal unfolds to at its root, where the checker
// reads it: a word (U32, F32), a char, a string and a Nat.
const LITERAL_ROOTS = new Set(["U32", "F32", "Chr", "SCon", "SNil", "Succ", "Zero"]);

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

const CACHE = nodePath.join(
  process.env.XDG_CACHE_HOME ??
    (process.platform === "win32"
      ? (process.env.LOCALAPPDATA ?? nodePath.join(os.homedir(), "AppData", "Local"))
      : nodePath.join(os.homedir(), ".cache")),
  "bend-lint",
);

const COMPILED = nodePath.join(CACHE, "host");

const SHIMMED: Array<[string, string]> = [
  ['import * as fs from "node:fs";', `import { fs } from "${SHIM}";`],
  ['import * as path from "node:path";', `import { path } from "${SHIM}";`],
];

const PATCHES: Record<string, Patch> = {
  "bend.ts": {
    edits: [
      ...SHIMMED,
      ["export function parse_term(", "function unseen_parse_term("],
      ["export function parse_bind(", "function unseen_parse_bind("],
      ["export function parse_tele(", "function unseen_parse_tele("],
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
    needs: [],
    tail: `import { seeDeclared, seeImported, seeParseBind, seeParseTele, seeParseTerm } from "${SHIM}";\nexport const parse_bind = seeParseBind(unseen_parse_bind);\nexport const parse_tele = seeParseTele(unseen_parse_tele);\nexport const parse_term = seeParseTerm(unseen_parse_term);\n`,
    exports: [],
  },
  "comp.ts": {
    edits: [],
    needs: ["let cli_args = [];", "function io_run(m) {"],
    tail: "",
    exports: ["RUNTIME_MAIN", "js_sat"],
  },
  "main.ts": {
    edits: SHIMMED,
    needs: [],
    tail: "",
    exports: ["book_read", "book_err", "Check_Fail"],
  },
};

const PATCHED = Object.keys(PATCHES);

// The programs bend2 checks, by path: never on disk; fs below serves them.
const PROGRAMS = new Map<string, string>();

// The last check of each file that passed, by real path.
const CHECKS = new Map<string, Checked>();

// fs and path for bend.ts and main.ts: real paths with "/", so imports
// resolve on Windows, and the programs served from memory.
const fs = {
  ...nodeFs,
  existsSync: (p: nodeFs.PathLike): boolean => PROGRAMS.has(String(p)) || nodeFs.existsSync(p),
  realpathSync: (p: nodeFs.PathLike): string =>
    PROGRAMS.has(String(p)) ? String(p) : slash(nodeFs.realpathSync(p)),
  readFileSync: ((p: nodeFs.PathOrFileDescriptor, ...rest: unknown[]) =>
    PROGRAMS.get(String(p)) ??
    (nodeFs.readFileSync as (...a: unknown[]) => unknown)(
      p,
      ...rest,
    )) as typeof nodeFs.readFileSync,
};

const path = {
  ...nodePath,
  join: (...ps: string[]): string => slash(nodePath.join(...ps)),
  resolve: (...ps: string[]): string => slash(nodePath.resolve(...ps)),
  posix: {
    ...nodePath.posix,
    resolve: (...ps: string[]): string => resolve(process.cwd(), ...ps),
    relative: (from: string, to: string): string =>
      nodePath.posix.relative(slash(from).replace(DRIVE, ""), slash(to).replace(DRIVE, "")),
  },
};

// Functions
// =========

const slash = (p: string): string => p.split(nodePath.sep).join("/");

// path.posix.resolve from `cwd`, where a drive letter is a root.
const resolve = (cwd: string, ...ps: string[]): string => {
  const all = [cwd, ...ps].map(slash);
  const drive =
    all
      .filter((p) => DRIVE.test(p))
      .at(-1)
      ?.slice(0, 2) ?? "";
  return drive + nodePath.posix.resolve(...all.map((p) => p.replace(DRIVE, "")));
};

const drift = (text: string): Error => Object.assign(new Error(text), { name: "DriftError" });

const message = (e: unknown): string => (e instanceof Error ? e.message : String(e));

const digest = (text: string): string => Bun.hash(text).toString(16);

// A file's text's hash, or "" if it cannot be read.
const hashed = (file: string): string => {
  try {
    return digest(nodeFs.readFileSync(file, "utf8"));
  } catch {
    return "";
  }
};

// `file` is one of PATCHED. Its line ends become LF, so an edit can span
// lines in a CRLF checkout.
const patch = (file: string, src: string): string => {
  const { edits, needs, tail, exports } = PATCHES[file];
  const mismatch = (what: string, n: number): never => {
    throw drift(
      `cannot patch bend2/${file}: found ${n} of ${what}, expected 1. Update PATCHES in BEND-REWRITE/host.ts.`,
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

// bend2 at a release (the PATCHED files, safe.ts, base.bend and the effs/
// files Base imports), downloaded once to <cache>/<tag>/bend2.
const fetchBend = async (tag: string): Promise<string> => {
  if (!RELEASE.test(tag)) {
    throw new Error("not a bend release: " + tag);
  }
  const dir = nodePath.join(CACHE, tag, "bend2");
  const whole = (): boolean =>
    [...PATCHED, "safe.ts", "base.bend"].every((f) => nodeFs.existsSync(nodePath.join(dir, f)));
  if (whole()) {
    return dir;
  }
  const fetched = async (file: string): Promise<[string, string]> => {
    const res = await fetch(`${RAW}${tag}/bend2/${file}`, { signal: AbortSignal.timeout(30_000) });
    if (!res.ok) {
      throw new Error(`GitHub answered ${res.status} for bend2/${file}`);
    }
    return [file, await res.text()];
  };
  const base = await fetched("base.bend");
  const effs = [
    ...new Set([...base[1].matchAll(/^\s*import "\.\/(effs\/[^"]+)"/gm)].map((m) => m[1])),
  ];
  const odd = effs.find((f) => !EFF.test(f));
  if (odd !== undefined) {
    throw new Error("base.bend imports " + odd + ", which is not a plain file in effs/");
  }
  const files = [base, ...(await Promise.all([...PATCHED, "safe.ts", ...effs].map(fetched)))];
  nodeFs.mkdirSync(nodePath.join(CACHE, tag), { recursive: true });
  const part = nodeFs.mkdtempSync(nodePath.join(CACHE, tag, ".part-"));
  files.forEach(([file, body]) => {
    nodeFs.mkdirSync(nodePath.dirname(nodePath.join(part, file)), { recursive: true });
    nodeFs.writeFileSync(nodePath.join(part, file), body);
  });
  nodeFs.rmSync(dir, { recursive: true, force: true });
  nodeFs.renameSync(part, dir);
  return dir;
};

// The installed bend's release ("v2.0.36"), or undefined if `bend version`
// does not run.
const installedTag = (): string | undefined => {
  try {
    const run = Bun.spawnSync(["bend", "version"], { stdout: "pipe", stderr: "ignore" });
    const version =
      run.exitCode === 0 ? run.stdout.toString().match(/^bend (\d+\.\d+\.\d+)\b/)?.[1] : undefined;
    return version === undefined ? undefined : "v" + version;
  } catch {
    return undefined;
  }
};

// The bend2 folder: BEND_DIR (a checkout or its bend2 folder), else the
// installed bend's release, else the pinned one.
const bendDir = async (): Promise<string> => {
  const chosen = process.env.BEND_DIR;
  if (chosen === undefined) {
    const tag = installedTag() ?? pkg.bendRelease;
    return fs.realpathSync(
      await fetchBend(tag).catch((e: unknown) => {
        throw new Error(`could not download bend ${tag} (${message(e)}); ${GIVE}`);
      }),
    );
  }
  const dir = path.resolve(chosen);
  const found = [path.join(dir, "bend2"), dir].find((d) =>
    nodeFs.existsSync(path.join(d, "bend.ts")),
  );
  if (found === undefined) {
    throw new Error(`no bend2 at ${dir} (it needs bend.ts); ${GIVE}`);
  }
  return fs.realpathSync(found);
};

// What main.ts must give, as the host calls it.
const guardMain = (Main: Main): void => {
  const checks: Array<[string, boolean]> = [
    ["book_read(file, base, seen = ...)", Main.book_read?.length === 2],
    ["book_err(e)", Main.book_err?.length === 1],
    [
      "new Check_Fail(why).why",
      typeof Main.Check_Fail === "function" && new Main.Check_Fail(MARK).why === MARK,
    ],
  ];
  const wrong = checks.flatMap(([what, ok]) => (ok ? [] : [what]));
  if (wrong.length > 0) {
    throw drift(`bend2/main.ts no longer has ${wrong.join(", ")}; update BEND-REWRITE/host.ts`);
  }
};

// Finds bend2, patches its PATCHED files as Bun loads them, imports them,
// and checks Base once.
const load = async (): Promise<Loaded> => {
  const dir = await bendDir();
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
    name: "bend-host",
    setup: (build) => {
      build.module(SHIM, () => ({
        exports: { fs, path, seeDeclared, seeImported, seeParseBind, seeParseTele, seeParseTerm },
        loader: "object",
      }));
      build.onLoad({ filter }, (args) => {
        const contents = patched.get(fs.realpathSync(args.path));
        if (contents === undefined) {
          throw drift(`the host matched ${args.path} but did not patch it`);
        }
        return { contents, loader: "ts" };
      });
    },
  });
  const modules = await Promise.all(
    PATCHED.map((f) => import(url.pathToFileURL(path.join(dir, f)).href)),
  );
  if (modules.some((module) => module[MARK] !== 1)) {
    throw drift("bend2 was loaded before the host could patch it");
  }
  const [Bend, Comp, Main] = modules as [typeof BendModule, Comp, Main];
  guardMain(Main);
  const compiler = digest(
    [...PATCHED.map((f) => path.join(dir, f)), url.fileURLToPath(import.meta.url)]
      .map(hashed)
      .join("\0"),
  );
  const loaded = { Bend, Comp, Main, base: await Main.book_read(Bend.BASE_BEND), compiler };
  await selfCheck(loaded);
  return loaded;
};

const isErr = (e: unknown): e is Err =>
  typeof e === "object" && e !== null && (e as { $?: unknown }).$ === "Err";

// What a failed book_read holds.
const why = (m: Loaded, e: unknown): unknown => (e instanceof m.Main.Check_Fail ? e.why : e);

// bend's words for a failed check, its location aside: expected and
// observed, with the names in scope, and the note.
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

// Where each line of `text` starts.
const starts = (text: string): number[] => [
  0,
  ...[...text.matchAll(/\n/g)].map((found) => found.index + 1),
];

// How many characters (code points) `text` holds, as Bend counts them.
const points = (text: string): number => text.match(/./gsu)?.length ?? 0;

const bare = (line: string): string => line.replace(/\r$/, "");

// f.length counts the parameters before the first default.
const arity = (f: (...args: never[]) => unknown, n: number, name: string): void => {
  if (f.length !== n) {
    throw drift(`${name} takes ${f.length} parameters, not ${n}; update BEND-REWRITE/host.ts`);
  }
};

// parse_term as bend.ts calls it: every argument passes through, and each
// term it parses is also reported to HOOK.term.
const seeParseTerm = (f: typeof BendModule.parse_term): typeof BendModule.parse_term => {
  arity(f, 1, "parse_term");
  return (...args) => {
    const t = f(...args);
    HOOK.term?.(args[0], t);
    return t;
  };
};

// parse_bind and parse_tele as bend.ts calls them: every argument passes
// through, and each binder they read is also reported to HOOK.binding.
const seeParseBind = (f: typeof BendModule.parse_bind): typeof BendModule.parse_bind => {
  arity(f, 2, "parse_bind");
  return (...args) => {
    const b = f(...args);
    HOOK.binding?.(b.k, b.i, b.s, "variable");
    return b;
  };
};

const seeParseTele = (f: typeof BendModule.parse_tele): typeof BendModule.parse_tele => {
  arity(f, 2, "parse_tele");
  return (...args) => {
    const tele = f(...args);
    tele.forEach(([, k, i, , s]) =>
      HOOK.binding?.(k, i, s, args[1] === "}" ? "field" : "parameter"),
    );
    return tele;
  };
};

// Where bend's parser reads a declaration's name; the name passes through.
const seeDeclared = (p: Parse, name: Name, kind: Heading["kind"]): Name => {
  HOOK.declare?.(kind, name, { file: p, beg: p.pos - name.length, end: p.pos });
  return name;
};

// Where bend reads an import line: `m` is its match, `at` the line's offset.
const seeImported = (file: string, at: number, line: string, m: RegExpExecArray): void => {
  const from = line.indexOf(m[1]);
  HOOK.import?.(
    file,
    m[2] ?? "Base",
    at + (m[2] === undefined ? from : line.indexOf(m[2], from + m[1].length)),
  );
};

// A term's sub-terms, in bend's order.
const children = (t: LTerm): LTerm[] => {
  const of = (CHILDREN as Record<string, ((tm: LTerm) => LTerm[]) | undefined>)[t.$];
  if (of === undefined) {
    throw drift(`unknown term kind ${t.$}; update CHILDREN in BEND-REWRITE/host.ts`);
  }
  return of(t);
};

// Every sub-term, parents first.
const walk = (tm: LTerm): LTerm[] => [tm, ...children(tm).flatMap(walk)];

// A text's offsets (UTF-16 units) as code points, as Bend counts them.
const pointsOf = (text: string): ((off: number) => number) =>
  /[\uD800-\uDFFF]/.test(text) ? (off) => points(text.slice(0, off)) : (off) => off;

// bend.ts parses a copy of each file with its import lines blanked, so a
// span moves to the file on disk by line and column. The copy's namespace
// and folder, and its lines, pick the file among those the check read.
const placeOf = (seen: Map<string, string | null>, copy: BendSpan["file"]): Placed | null => {
  const at: BendSpan["file"] & { dir?: string } = copy;
  const lines = at.str.split("\n").map(bare);
  const found = [...seen]
    .filter(
      ([real, ns]) =>
        (ns ?? "") === at.ns &&
        (at.dir === undefined || at.dir === real.slice(0, real.lastIndexOf("/") + 1)),
    )
    .map(([real]) => ({ real, text: fs.readFileSync(real, "utf8") }))
    .filter(({ text }) => {
      const theirs = text.split("\n").map(bare);
      return (
        theirs.length === lines.length &&
        lines.every(
          (l: string, i: number) =>
            l === theirs[i] || (l.trim() === "" && /^\s*import(\s|$)/.test(theirs[i])),
        )
      );
    });
  return found.length === 1
    ? { path: found[0].real, text: found[0].text, from: starts(at.str), to: starts(found[0].text) }
    : null;
};

// A span of bend.ts's copy as a span of the file on disk (UTF-16 units),
// with the file's code point count; undefined if no file matches.
const placedSpan = (
  seen: Map<string, string | null>,
  placed: WeakMap<object, Placed | null>,
  s: BendSpan,
): { path: string; beg: number; end: number; points: (off: number) => number } | undefined => {
  const known = placed.get(s.file) ?? placeOf(seen, s.file);
  placed.set(s.file, known);
  if (known === null) {
    return undefined;
  }
  const at = (off: number): number => {
    const i = known.from.reduce((last, start, j) => (start <= off ? j : last), 0);
    return known.to[i] + off - known.from[i];
  };
  return { path: known.path, beg: at(s.beg), end: at(s.end), points: pointsOf(known.text) };
};

// A file's text with its import lines blanked, as bend.ts parses it.
const unimported = (text: string): string => {
  const code = text.replace(SOURCE_TOKEN, (s) =>
    ["#", '"', "'"].includes(s[0]) ? s.replace(/[^\r\n]/g, " ") : s,
  );
  const declaration = code.search(/^[ \t]*(?:@unsafe\s+)?(?:def|type|law)\b/m);
  const end = declaration < 0 ? text.length : declaration;
  return text.replace(/^[ \t]*import[^\S\n].*$/gm, (s, at: number) =>
    at < end && /^[ \t]*import\b/.test(code.slice(at)) ? "" : s,
  );
};

// The aliases of each parsed text, from the spans of the book's terms.
const aliasesOf = (m: Loaded, c: Checked): Map<string, Record<Name, Name>> => {
  c.aliases ??= new Map(
    Object.values(c.book.tlds)
      .flatMap((tld) => [tld.T, ...(tld.$ === "Def" && tld.v ? [tld.v] : [])])
      .flatMap((term) => walk(m.Bend.term_lower(term)))
      .flatMap((tm): Array<[string, Record<Name, Name>]> =>
        tm.s === undefined ? [] : [[tm.s.file.str, tm.s.file.al]],
      )
      .reverse(),
  );
  return c.aliases;
};

// How `file` spells the check's names, as bend's own name_show prints them
// for it: its own names bare, an import's through its alias, any other name
// as the check has it. `aliases` maps each alias to the check's namespace
// (from bend's spans, else from the import lines), and `qualify` reads a
// name as `file` would declare it.
const spellingOf = (m: Loaded, c: Checked, file: string, text: string): Spelling => {
  const ns = c.seen.get(file) ?? "";
  const aliases = [...text.matchAll(/^import\s+(\S+)\s+as\s+(\w+)/gm)].reduce<Record<Name, Name>>(
    (known, [, at, alias]) => {
      const target = resolve(file, "..", at);
      return known[alias] !== undefined || !c.seen.has(target)
        ? known
        : { ...known, [alias]: c.seen.get(target) ?? "" };
    },
    /^import\s+\S+\s+as\s+/m.test(text) ? (aliasesOf(m, c).get(unimported(text)) ?? {}) : {},
  );
  const shown = { str: "", ns, al: aliases };
  return {
    ns,
    aliases,
    qualify: (name) => {
      const dot = name.indexOf(".");
      return dot >= 0 && aliases[name.slice(0, dot)] !== undefined
        ? aliases[name.slice(0, dot)] + ":" + name.slice(dot + 1)
        : (ns ? ns + ":" : "") + name;
    },
    spell: (k) => m.Bend.name_show(shown, k),
    shown,
  };
};

const orderOf = (c: Checked): Order => {
  c.order ??= c.book.order.reduce<Order>(
    (out, k, i) => {
      const colon = k.indexOf(":");
      const ns = colon < 0 ? "" : k.slice(0, colon);
      const tld = c.book.tlds[k];
      if (!out.at.has(k)) out.at.set(k, i);
      if (!out.first.has(ns)) out.first.set(ns, i);
      if (tld?.$ === "ADT") tld.c.forEach((ctr) => out.ctr.set(ctr.k, k));
      return out;
    },
    { at: new Map(), first: new Map(), ctr: new Map() },
  );
  return c.order;
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

// Parses `file` again in its original scope, with writes confined to a
// fresh layer: what the check saw when it parsed `file`, and no more.
const parseSource = (
  m: Loaded,
  c: Checked,
  file: string,
  text: string,
  sp: Spelling,
  own: Name[],
): Book => {
  const fills = fillsIn(c.book, sp.ns, own);
  const gone = new Set(own.filter((k) => !fills.has(k)));
  const order = orderOf(c);
  const cut = file === c.root ? Infinity : (order.first.get(sp.ns) ?? Infinity);
  const hidden = (k: Name): boolean => gone.has(k) || (order.at.get(k) ?? -1) >= cut;
  const parsed = m.Bend.book_nil();
  parsed.tlds = layer(c.book.tlds, hidden);
  parsed.ctrs = layer(c.book.ctrs, (k) => {
    const owner = order.ctr.get(k);
    return owner !== undefined && hidden(owner);
  });
  fills.forEach((k) => {
    const tld = c.book.tlds[k];
    parsed.tlds[k] = tld.$ === "Def" ? { ...tld, v: null, i: undefined, u: false } : tld;
  });
  m.Bend.parse_book(
    parsed,
    file.slice(0, file.lastIndexOf("/") + 1),
    unimported(text),
    sp.ns,
    sp.aliases,
  );
  return parsed;
};

const some = (x: Plain | undefined): Plain =>
  x === undefined ? { $: "None" } : { $: "Some", value: x };

const spanOf = (
  file: string,
  points: (off: number) => number,
  beg: number,
  end: number,
): Plain => ({
  $: "BendSourceSpan",
  path: file,
  beg: points(beg),
  end: points(end),
});

// Whether a type, after its arrows, is a sort (Type, Data or Kind(..)).
const endsInSort = (m: Loaded, ty: HTerm, dep: number): boolean => {
  const end = (t: HTerm, d: number): HTerm =>
    t.$ === "All" ? end(t.B(m.Bend.Var(t.k, d)), d + 1) : t.$ === "Ann" ? end(t.x, d) : t;
  return end(ty, dep).$ === "Typ";
};

// A term without the checker's own annotations: those that neither are in
// the source nor have a type that is.
const sourceTerm = (t: LTerm): LTerm =>
  t.$ === "Ann" && t.s === undefined && t.T.s === undefined ? sourceTerm(t.x) : t;

// Whether a term is a literal as written, or as the checker unfolded it: a
// Lit, or constructors and Lits only.
const constant = (t: LTerm): boolean =>
  t.$ === "Lit" || (t.$ === "Ctr" && t.x.every((x) => constant(sourceTerm(x))));

const other = (parts: number[]): Plain => ({ $: "OtherTerm", parts });

// The bits of a word (WCon{bit, ..}), and its tail unless it is WNil{}.
const bitsOf = (w: LTerm): LTerm[] =>
  w.$ === "Ctr" && w.k === "WCon" && w.x.length === 2
    ? [sourceTerm(w.x[0]), ...bitsOf(sourceTerm(w.x[1]))]
    : w.$ === "Ctr" && w.k === "WNil"
      ? []
      : [w];

// A call's head and its arguments, through annotations.
const spineOf = (x: LTerm, args: LTerm[]): LTerm[] =>
  x.$ === "App" ? spineOf(x.f, [x.x, ...args]) : x.$ === "Ann" ? spineOf(x.x, args) : [x, ...args];

// The views of the kinds a rule tells apart; names as `sp` spells them. A
// call has all its arguments, and its head without annotations.
const VIEWS: { [K in LTerm["$"]]?: (t: Extract<LTerm, { $: K }>, sp: Spelling) => View } = {
  Var: (t, sp) => ({ kids: [], term: () => ({ $: "VariableTerm", name: sp.spell(t.k) }) }),
  Ref: (t, sp) => ({ kids: [], term: () => ({ $: "ReferenceTerm", name: sp.spell(t.k) }) }),
  App: (t) => ({
    kids: spineOf(t, []),
    term: ([head, ...args]) => ({ $: "CallTerm", head, arguments: args }),
  }),
  Let: (t) => ({
    kids: [...t.v, t.f],
    term: (at) => ({ $: "LetTerm", names: t.k, values: at.slice(0, -1), body: at[at.length - 1] }),
  }),
  Lam: (t) => ({ kids: [t.f], term: ([body]) => ({ $: "LambdaTerm", name: t.k, body }) }),
  Ctr: (t, sp) => ({
    kids: t.x,
    term: (fields) => ({ $: "ConstructorTerm", name: sp.spell(t.k), fields }),
  }),
  Ann: (t) => ({
    kids: [t.x, t.T],
    term: ([value, annotation]) => ({ $: "AnnotatedTerm", value, annotation }),
  }),
};

// A term as a rule sees it: a literal as one term, as bend prints it back;
// a word the checker built from bits as one term, with its parts that are
// not constant; a kind of VIEWS as its view; any other term with its kids.
const viewOf = (m: Loaded, sp: Spelling, t: LTerm): View => {
  if (t.$ === "Lit" || (t.$ === "Ctr" && LITERAL_ROOTS.has(t.k) && constant(t))) {
    return {
      kids: [],
      term: () => ({ $: "LiteralTerm", shown: m.Bend.term_show(t, -1, [], sp.shown) }),
    };
  }
  const word = t.$ === "Ctr" && (t.k === "U32" || t.k === "F32") && t.x.length === 1;
  const view = (VIEWS as Record<string, ((tm: LTerm, sp: Spelling) => View) | undefined>)[t.$];
  return word
    ? { kids: bitsOf(sourceTerm(t.x[0])).filter((b) => !constant(b)), term: other }
    : view !== undefined
      ? view(t, sp)
      : { kids: children(t), term: other };
};

// The nodes of the term `t` at `index`, parents first, each a BodyNode
// whose index is its place in the body's list; its sub-terms come after it.
const nodesOf = (
  m: Loaded,
  c: Checked,
  sp: Spelling,
  t: LTerm,
  index: number,
  parent: number | undefined,
): Plain[] => {
  const { kids, term } = viewOf(m, sp, t);
  const placed = kids.reduce<{ next: number; at: number[]; trees: Plain[][] }>(
    (acc, kid) => {
      const tree = nodesOf(m, c, sp, sourceTerm(kid), acc.next, index);
      return {
        next: acc.next + tree.length,
        at: [...acc.at, acc.next],
        trees: [...acc.trees, tree],
      };
    },
    { next: index + 1, at: [], trees: [] },
  );
  const at = t.s && placedSpan(c.seen, c.placed, t.s);
  return [
    {
      $: "BodyNode",
      index,
      parent: some(parent),
      span: some(at && spanOf(at.path, at.points, at.beg, at.end)),
      term: term(placed.at),
    },
    ...placed.trees.flat(),
  ];
};

// The headings bend's parser read in `file`, as `file` declares them.
const headingsIn = (
  c: Checked,
  file: string,
  sp: Spelling,
): Array<{ kind: Heading["kind"]; name: Name; beg: number; end: number }> =>
  c.headings.flatMap((h) => {
    const at = placedSpan(c.seen, c.placed, h.span);
    return at?.path === file
      ? [{ kind: h.kind, name: sp.qualify(h.name), beg: at.beg, end: at.end }]
      : [];
  });

// The declarations of `file`, as `file` spells them: its imports, defs,
// datatypes and constructors, and its parameters, variables and fields,
// each with the uses of its name; each def with its checked body if
// `bodies`.
const declarationsIn = (m: Loaded, c: Checked, file: string, bodies: boolean): Plain[] => {
  const text = fs.readFileSync(file, "utf8");
  const sp = spellingOf(m, c, file, text);
  const points = pointsOf(text);
  const mine = headingsIn(c, file, sp);
  const heads = mine.filter((h) => h.kind !== "constructor");
  const enclosing = (beg: number): (typeof heads)[number] => {
    const found = heads.reduce<(typeof heads)[number] | undefined>(
      (last, h) => (h.beg <= beg ? h : last),
      undefined,
    );
    if (found === undefined) {
      throw drift(`no declaration encloses ${file}:${beg}`);
    }
    return found;
  };
  const locals = new Map<string, string>();
  const localKey = (index: number, beg: number): string => {
    const at = [enclosing(beg).beg, index].join("\0");
    const known = locals.get(at) ?? "\0" + locals.size;
    locals.set(at, known);
    return known;
  };
  const bindings: Binding[] = [];
  const binding = (
    name: Name,
    index: number,
    s: BendSpan | undefined,
    kind: Binding["kind"],
    type?: Plain,
  ): void => {
    const at = s && placedSpan(c.seen, c.placed, s);
    const token = at && text.slice(at.beg, at.end).match(/^[@&]?\s*[+-]?\s*([A-Za-z_]\w*)/);
    if (at === undefined || at.path !== file || token?.[1] !== name) {
      return;
    }
    const beg = at.beg + token[0].length - name.length;
    bindings.push({
      key: localKey(index, at.beg),
      kind,
      name,
      owner: enclosing(at.beg).name,
      beg,
      end: beg + name.length,
      type,
    });
  };
  const globals = new Set<LTerm>();
  const localUses: Array<{ index: number; s?: BendSpan }> = [];
  const visited = new WeakSet<LTerm>();
  const visit = (p: Parse, tm: LTerm): void => {
    if (visited.has(tm)) {
      return;
    }
    visited.add(tm);
    if (["Ref", "ADT", "Ctr", "Mat", "Lit"].includes(tm.$)) globals.add(tm);
    if (tm.$ === "Var" && tm.v?.$ === "Ref") globals.add(tm.v);
    if (tm.$ === "Var" && tm.v?.$ !== "Ref") localUses.push({ index: tm.i, s: tm.s });
    if (
      (tm.$ === "All" || tm.$ === "Lam") &&
      tm.s &&
      /^[@&]/.test(p.str.slice(tm.s.beg, tm.s.end))
    ) {
      binding(tm.k, tm.i, tm.s, "parameter");
    }
    children(tm).forEach((kid) => visit(p, kid));
  };
  HOOK.term = visit;
  HOOK.binding = binding;
  const parsed = (() => {
    try {
      return parseSource(
        m,
        c,
        file,
        text,
        sp,
        heads.map((h) => h.name),
      );
    } finally {
      HOOK.term = undefined;
      HOOK.binding = undefined;
    }
  })();
  const typeOf = (ty: HTerm, dep: number): Plain => ({
    $: "BendType",
    id: c.types.push({ ty, bok: parsed, dep }) - 1,
    shown: m.Bend.term_show(m.Bend.term_lower(ty, dep), -1, [], sp.shown),
    ends_in_sort: endsInSort(m, ty, dep),
  });
  const telescope = (T: HTerm, n: number, from: number, kind: Binding["kind"]): Plain => {
    const go = (t: HTerm, i: number): Plain => {
      if (i >= n || t.$ !== "All") {
        return typeOf(t, i);
      }
      if (i >= from) binding(t.k, t.i, t.s, kind, typeOf(t.A, i));
      return go(t.B(m.Bend.Var(t.k, i)), i + 1);
    };
    return go(T, 0);
  };
  const written = new Map(
    heads.flatMap((h): Array<[Name, Plain]> => {
      const tld = parsed.tlds[h.name] as Book["tlds"][string] | undefined;
      if (tld === undefined) {
        return [];
      }
      const type = telescope(tld.T, tld.n, 0, "parameter");
      if (tld.$ === "ADT") tld.c.forEach((ctr) => telescope(ctr.T, tld.n + ctr.n, tld.n, "field"));
      return [[h.name, type]];
    }),
  );
  const bound = [...new Map(bindings.map((d) => [d.beg, d])).values()];
  const binders = new Set(bound.map((d) => d.beg));
  const uses = [
    ...heads.flatMap((h): Use[] =>
      sp.aliases[text.slice(h.beg, h.end).split(".")[0]] !== undefined
        ? [{ key: h.name, owner: h.name, beg: h.beg, end: h.end }]
        : [],
    ),
    ...[...globals].flatMap((tm): Use[] => {
      const at = tm.s && placedSpan(c.seen, c.placed, tm.s);
      return at?.path === file && "k" in tm && typeof tm.k === "string"
        ? [{ key: tm.k, owner: enclosing(at.beg).name, beg: at.beg, end: at.end }]
        : [];
    }),
    ...localUses.flatMap(({ index, s }): Use[] => {
      const at = s && placedSpan(c.seen, c.placed, s);
      return at?.path === file
        ? [
            {
              key: localKey(index, at.beg),
              owner: enclosing(at.beg).name,
              beg: at.beg,
              end: at.end,
            },
          ]
        : [];
    }),
  ].filter((u) => !binders.has(u.beg));
  const unique = [...new Map(uses.map((u) => [[u.key, u.beg].join("\0"), u])).values()];
  const references = (keep: (u: Use) => boolean): Plain[] =>
    unique.filter(keep).map((u) => ({
      $: "DeclarationReference",
      owner: sp.spell(u.owner),
      span: spanOf(file, points, u.beg, u.end),
    }));
  const fills = fillsIn(
    c.book,
    sp.ns,
    heads.filter((h) => h.kind === "def").map((h) => h.name),
  );
  const order = orderOf(c);
  const bodyOf = (k: Name): Plain[] => {
    const tld = c.book.tlds[k];
    return bodies && tld?.$ === "Def" && tld.e !== undefined
      ? nodesOf(m, c, sp, sourceTerm(tld.e), 0, undefined)
      : [];
  };
  const base = m.Bend.BASE_BEND;
  const imports = c.imports
    .filter((i) => i.path === file)
    .map((i): { beg: number; plain: Plain } => {
      const loads =
        i.name === "Base"
          ? base
          : [...c.seen].find(([at, ns]) => at !== base && (ns ?? "") === sp.aliases[i.name])?.[0];
      if (loads === undefined) {
        throw drift(`the import ${i.name} of ${file} loads no file the check read`);
      }
      const usedBy = (u: Use): boolean => {
        if (u.key.startsWith("\0")) return false;
        const explicit = text.slice(u.beg, u.end).match(/^([A-Za-z_]\w*)\./)?.[1];
        if (explicit !== undefined && sp.aliases[explicit] !== undefined)
          return explicit === i.name;
        const ns = u.key.includes(":") ? u.key.slice(0, u.key.indexOf(":")) : "";
        return i.name === "Base"
          ? c.book.tlds[order.ctr.get(u.key) ?? u.key]?.b === true
          : sp.aliases[i.name] === ns;
      };
      return {
        beg: i.beg,
        plain: {
          $: "Declaration",
          name: i.name,
          span: spanOf(file, points, i.beg, i.beg + i.name.length),
          references: references(usedBy),
          kind: { $: "ImportDeclaration", loads },
        },
      };
    });
  const declared = mine.map((h): { beg: number; plain: Plain } => ({
    beg: h.beg,
    plain: {
      $: "Declaration",
      name: sp.spell(h.name),
      span: spanOf(file, points, h.beg, h.end),
      references: references((u) => u.key === h.name),
      kind:
        h.kind === "def"
          ? {
              $: "DefDeclaration",
              fills: fills.has(h.name),
              written_type: some(written.get(h.name)),
              body: bodyOf(h.name),
            }
          : h.kind === "type"
            ? { $: "DatatypeDeclaration", written_type: some(written.get(h.name)) }
            : { $: "ConstructorDeclaration", owner: sp.spell(enclosing(h.beg).name) },
    },
  }));
  const local = bound.map((d): { beg: number; plain: Plain } => ({
    beg: d.beg,
    plain: {
      $: "Declaration",
      name: d.name,
      span: spanOf(file, points, d.beg, d.end),
      references: references((u) => u.key === d.key),
      kind:
        d.kind === "variable"
          ? { $: "VariableDeclaration", owner: sp.spell(d.owner) }
          : {
              $: d.kind === "field" ? "FieldDeclaration" : "ParameterDeclaration",
              owner: sp.spell(d.owner),
              written_type: some(d.type),
            },
    },
  }));
  return [...imports, ...declared, ...local].sort((x, y) => x.beg - y.beg).map((d) => d.plain);
};

// What `file` declares when it holds `text`, parsed in its original scope:
// a key two parses share when they declare the same, or undefined if
// `text` does not parse.
const declaredBy = (m: Loaded, c: Checked, file: string, text: string): string | undefined => {
  const sp = spellingOf(m, c, file, fs.readFileSync(file, "utf8"));
  const lower = (x: HTerm | null): LTerm | null => (x === null ? null : m.Bend.term_lower(x));
  try {
    const parsed = parseSource(
      m,
      c,
      file,
      text,
      sp,
      headingsIn(c, file, sp)
        .filter((h) => h.kind !== "constructor")
        .map((h) => h.name),
    );
    return JSON.stringify(
      parsed.order.map((k) => {
        const tld = parsed.tlds[k];
        return tld.$ === "ADT"
          ? [k, tld.n, tld.g, lower(tld.T), tld.c.map((ctr) => [ctr.k, ctr.n, lower(ctr.T)])]
          : [k, tld.n, tld.x, tld.u ?? false, tld.i, lower(tld.T), lower(tld.v)];
      }),
      (key: string, v: unknown) => (key === "s" ? undefined : v),
    );
  } catch {
    return undefined;
  }
};

// Whether `text` declares what `file` declares, by the last check of `file`
// that passed; false when there is none.
const keepsDeclarations = (m: Loaded, file: string, text: string): boolean => {
  const real = fs.existsSync(file) ? fs.realpathSync(file) : file;
  const c = CHECKS.get(real);
  if (c === undefined) {
    return false;
  }
  c.declared ??= declaredBy(m, c, real, fs.readFileSync(real, "utf8"));
  return c.declared !== undefined && declaredBy(m, c, real, text) === c.declared;
};

// The declarations of every file the check read, Base and hub packages
// aside; each def with its checked body if `bodies`.
const declarationsOf = (m: Loaded, c: Checked, bodies: boolean): Plain[] =>
  [...c.seen]
    .filter(([file, ns]) => file !== m.Bend.BASE_BEND && !/^0x[0-9a-f]+\//.test(ns ?? ""))
    .map(([file]) => ({
      $: "SourceDeclarations",
      path: file,
      declarations: declarationsIn(m, c, file, bodies),
    }));

const sourceOf = (file: string, text: string): Plain => ({
  $: "BendSource",
  path: file,
  text,
  lines: text.split("\n"),
});

// The check of `file` as plain data: its root, every file it read, its
// bend/check finding if it fails, and, if it passes and they are wanted, the
// declarations of every file it read but Base and hub packages, with the
// defs' bodies if those are wanted.
const check = async (
  m: Loaded,
  file: string,
  wanted: { declarations: boolean; bodies: boolean },
): Promise<Plain> => {
  const seen = new Map<string, string | null>();
  const headings: Heading[] = [];
  const imports: Imported[] = [];
  HOOK.declare = (kind, name, span) => headings.push({ kind, name, span });
  HOOK.import = (at, name, beg) => imports.push({ path: at, name, beg });
  const seeded = fs.existsSync(file) && /^import Base$/m.test(fs.readFileSync(file, "utf8"));
  const read = await m.Main.book_read(file, seeded ? m.base : undefined, seen)
    .then(
      (book) => ({ book }),
      (e: unknown) => ({ e: why(m, e) }),
    )
    .finally(() => {
      HOOK.declare = undefined;
      HOOK.import = undefined;
    });
  const real = fs.existsSync(file) ? fs.realpathSync(file) : file;
  const text = (f: string): string => fs.readFileSync(f, "utf8");
  const placed = new WeakMap<object, Placed | null>();
  if ("book" in read) {
    CHECKS.set(real, { book: read.book, root: real, seen, headings, imports, placed, types: [] });
  }
  const failed = "e" in read ? read : undefined;
  const span =
    failed !== undefined && isErr(failed.e) && failed.e.spn !== undefined
      ? placedSpan(seen, placed, failed.e.spn)
      : undefined;
  const at = span && { path: span.path, beg: span.points(span.beg), end: span.points(span.end) };
  return {
    $: "BendCheck",
    root: seen.has(real) ? sourceOf(real, text(real)) : sourceOf(file, ""),
    sources: [...seen.keys()].map((f) => sourceOf(f, text(f))),
    declarations:
      "book" in read && (wanted.declarations || wanted.bodies)
        ? declarationsOf(m, CHECKS.get(real)!, wanted.bodies)
        : [],
    failure:
      failed === undefined
        ? { $: "None" }
        : {
            $: "Some",
            value: {
              $: "RuleFinding",
              rule_id: "bend/check",
              finding: {
                $: "Finding",
                severity: { $: "Error" },
                message: failure(m, failed.e),
                span: {
                  $: "BendSourceSpan",
                  path: at?.path ?? file,
                  beg: at?.beg ?? 0,
                  end: at?.end ?? 0,
                },
                fixes: [],
              },
            },
          },
  };
};

// What a check gives, as the self-check reads it.
type Sampled = {
  failure: { $: string };
  declarations: Array<{
    path: string;
    declarations: Array<{
      name: string;
      span: { beg: number; end: number };
      references: unknown[];
      kind: {
        $: string;
        owner?: string;
        written_type?: { value?: { shown: string; ends_in_sort: boolean } };
        body?: Array<{ term: { $: string; name?: string; head?: number; arguments?: number[] } }>;
      };
    }>;
  }>;
};

// Checks a small program as a rule sees it: `x` in `def id(x: N) -> N: x`
// must be a parameter of id, written as N, used once, at its own span; `id`
// and the constructor `Z` are used once, in main, whose body is the call
// id(Z{}). A bend2 that gives anything else has changed in a way the host
// does not follow.
const selfCheck = async (m: Loaded): Promise<void> => {
  const at = slash(nodePath.join(nodeFs.realpathSync(HERE), SAMPLE));
  PROGRAMS.set(at, SAMPLE_TEXT);
  const run = (await check(m, at, { declarations: true, bodies: true })) as unknown as Sampled;
  const found = run.declarations.find((s) => s.path === at)?.declarations ?? [];
  const named = (name: string, kind: string) =>
    found.find((d) => d.name === name && d.kind.$ === kind);
  const x = named("x", "ParameterDeclaration");
  const main = named("main", "DefDeclaration")?.kind.body;
  const term = (i: number | undefined) => (i === undefined ? undefined : main?.[i]?.term);
  const checks: Array<[string, boolean]> = [
    ["check", run.failure.$ === "None"],
    ["def", named("id", "DefDeclaration")?.references.length === 1],
    ["parameter", x?.kind.owner === "id" && x.references.length === 1],
    ["span", x !== undefined && SAMPLE_TEXT.slice(x.span.beg, x.span.end) === "x"],
    [
      "written type",
      x?.kind.written_type?.value?.shown === "N" && !x.kind.written_type.value.ends_in_sort,
    ],
    [
      "constructor",
      named("Z", "ConstructorDeclaration")?.kind.owner === "N" &&
        named("Z", "ConstructorDeclaration")?.references.length === 1,
    ],
    [
      "body",
      term(0)?.$ === "CallTerm" &&
        term(term(0)?.head)?.$ === "ReferenceTerm" &&
        term(term(0)?.head)?.name === "id" &&
        term(0)?.arguments?.length === 1 &&
        term(term(0)?.arguments?.[0])?.$ === "ConstructorTerm" &&
        term(term(0)?.arguments?.[0])?.name === "Z",
    ],
  ];
  const wrong = checks.flatMap(([what, ok]) => (ok ? [] : [what]));
  PROGRAMS.delete(at);
  CHECKS.delete(at);
  if (wrong.length > 0) {
    throw drift(
      `self-check failed: the patched bend2 gave the wrong ${wrong.join(", ")} for the sample program; update BEND-REWRITE/host.ts`,
    );
  }
};

// A constructor's fields: the names its type binds, after its parameters.
const fieldsOf = (n: number, T: HTerm): string[] => {
  const binders = (t: HTerm): string[] =>
    t.$ === "All" ? [t.k, ...binders(t.B({ $: "Var", k: t.k, i: t.i }))] : [];
  return n === 0 ? [] : binders(T).slice(-n);
};

// The constructors of main.bend and Base, by the names they declare.
const ctorsOf = (m: Loaded, book: Book, seen: Map<string, string | null>): Record<string, Ctor> => {
  const main = slash(nodeFs.realpathSync(nodePath.join(HERE, "main.bend")));
  const spaces = new Set(["", seen.get(main) ?? ""]);
  return Object.fromEntries(
    Object.values(book.ctrs).flatMap((c) => {
      const cut = c.k.lastIndexOf(":");
      return spaces.has(cut < 0 ? "" : c.k.slice(0, cut))
        ? [[c.k.slice(cut + 1), { key: m.Bend.name_key(c.k), fields: fieldsOf(c.n, c.T) }]]
        : [];
    }),
  );
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

// The program: main.bend with the rule files `files` (paths as main.bend
// spells them), each defining rules().
const programText = (files: string[]): string => {
  const here = slash(nodeFs.realpathSync(HERE));
  const far = files.find(
    (f) =>
      (f.match(DRIVE)?.[0] ?? "").toLowerCase() !== (here.match(DRIVE)?.[0] ?? "").toLowerCase(),
  );
  if (far !== undefined) {
    throw new Error(`${far} is on another drive than BEND-REWRITE, so main.bend cannot import it`);
  }
  const rel = (f: string): string => {
    const r = path.posix.relative(here, f);
    return r.startsWith(".") ? r : "./" + r;
  };
  return [
    "import Base",
    "import ./main.bend as Lint",
    ...files.map((f, i) => `import ${rel(f)} as R${i}`),
    "",
    "def rules(u: Unit) -> List<&1, Lint.Rule>:",
    `  List.concat(&1, Lint.Rule, [${files.map((_, i) => `R${i}.rules()`).join(", ")}])`,
    "",
    "def compiled() -> List<&2, String>:",
    `  [${files.map((f) => JSON.stringify(f)).join(", ")}]`,
    "",
    "def main() -> IO(Unit):",
    "  Lint.serve(~rules, compiled())",
    "",
  ].join("\n");
};

const keptAt = (key: string): string => nodePath.join(COMPILED, key + ".json");

// The program kept for `key`, if its compiler and every file it was made
// from are unchanged.
const cached = (m: Loaded, key: string): Program | undefined => {
  try {
    const kept = JSON.parse(nodeFs.readFileSync(keptAt(key), "utf8")) as Kept;
    return kept.compiler === m.compiler &&
      nodeFs.existsSync(kept.module) &&
      kept.files.every(([f, h]) => hashed(f) === h)
      ? { module: kept.module, ctors: kept.ctors }
      : undefined;
  } catch {
    return undefined;
  }
};

// Writes `text` to `file` whole or not at all.
const written = (file: string, text: string): void => {
  nodeFs.mkdirSync(nodePath.dirname(file), { recursive: true });
  const temp = `${file}.${process.pid}`;
  nodeFs.writeFileSync(temp, text);
  nodeFs.renameSync(temp, file);
};

// The program with the rule files `files`: kept, or checked, compiled as
// comp.ts io_run runs it, and kept.
const program = async (m: Loaded, files: string[]): Promise<Program> => {
  const text = programText(files);
  const key = digest(text);
  const known = cached(m, key);
  if (known !== undefined) {
    return known;
  }
  const at = slash(nodePath.join(nodeFs.realpathSync(HERE), `program-${key}.bend`));
  PROGRAMS.set(at, text);
  const seen = new Map<string, string | null>();
  const book = await m.Main.book_read(at, m.base, seen).catch((e: unknown) => {
    throw new Error("the program does not check:\n" + failure(m, why(m, e)));
  });
  const js = [
    'import { createRequire } from "node:module";',
    `const require = createRequire(${JSON.stringify(import.meta.url)});`,
    m.Comp.js_lib(book),
    m.Comp.RUNTIME_MAIN,
    `export default (args) => { cli_args = args; return io_run(${m.Comp.js_sat("main")}); };`,
  ].join("\n");
  const module = nodePath.join(COMPILED, digest(js) + ".mjs");
  written(module, js);
  const kept: Kept = {
    module,
    ctors: ctorsOf(m, book, seen),
    compiler: m.compiler,
    files: [...seen.keys(), m.Bend.BASE_BEND, ...effectsOf(book)]
      .filter((f) => !PROGRAMS.has(f))
      .map((f): [string, string] => [f, hashed(f)]),
  };
  written(keptAt(key), JSON.stringify(kept));
  return { module, ctors: kept.ctors };
};

// Runs the program with the rule files `files` in a worker, with `args`,
// and answers its effects; settles with its exit code. A program that asks
// to restart is run again with the files it asks for, once.
const run = async (m: Loaded, files: string[], args: string[], again: boolean): Promise<number> => {
  const { port1, port2 } = new MessageChannel();
  const flag = new Int32Array(new SharedArrayBuffer(4));
  const start: Start = {
    ...(await program(m, files)),
    args: ["program.bend", ...args],
    port: port2,
    flag,
  };
  const worker = new Worker(url.fileURLToPath(import.meta.url), {
    workerData: start,
    transferList: [port2],
  });
  const reply = (answer: Plain): void => {
    port1.postMessage(answer);
    Atomics.store(flag, 0, 1);
    Atomics.notify(flag, 0);
  };
  return new Promise<{ exit: number } | { restart: string[] }>((done, fail) => {
    worker.on("error", fail);
    port1.on("message", (msg: Ask | { exit: number }) => {
      if ("exit" in msg) {
        port1.close();
        done(msg);
      } else if (msg.op === "same") {
        reply(keepsDeclarations(m, msg.path, msg.text));
      } else if (msg.op === "restart") {
        reply({ $: "Unit" });
        port1.close();
        void worker.terminate();
        done({ restart: msg.files });
      } else {
        void check(m, msg.path, msg).then(reply, fail);
      }
    });
  }).then((end) => {
    if ("exit" in end) {
      return end.exit;
    }
    if (again) {
      throw drift("the program asked to restart with the rule files it was compiled with");
    }
    return run(m, end.restart, args, true);
  });
};

// A plain value as main.bend's runtime holds it. A constructor the
// contract does not declare, or with other fields, is drift.
const valueOf = (ctors: Record<string, Ctor>, x: Plain): unknown => {
  if (typeof x !== "object") {
    return x;
  }
  if (Array.isArray(x)) {
    return x.reduceRight<unknown>(
      (tail, head) => ({ $: ctors.Con.key, head: valueOf(ctors, head), tail }),
      { $: ctors.Nil.key },
    );
  }
  const { $, ...given } = x;
  const ctor = Object.hasOwn(ctors, $) ? ctors[$] : undefined;
  const names = Object.keys(given);
  if (
    ctor === undefined ||
    names.length !== ctor.fields.length ||
    !ctor.fields.every((f) => Object.hasOwn(given, f))
  ) {
    throw drift(
      `the host answered ${$}{${names.join(", ")}}, which main.bend does not declare; update BEND-REWRITE/host.ts`,
    );
  }
  return Object.fromEntries([
    ["$", ctor.key],
    ...ctor.fields.map((f) => [f, valueOf(ctors, given[f])]),
  ]);
};

// The worker: runs the program; an effect asks the main thread and waits
// for its answer.
const work = async (start: Start): Promise<void> => {
  const { module, ctors, args, port, flag } = start;
  const ask = (q: Ask): unknown => {
    Atomics.store(flag, 0, 0);
    port.postMessage(q);
    Atomics.wait(flag, 0, 0);
    return valueOf(ctors, receiveMessageOnPort(port)?.message as Plain);
  };
  (globalThis as typeof globalThis & { BEND_HOST?: Host }).BEND_HOST = { ask };
  const loaded = (await import(url.pathToFileURL(module).href)) as {
    default: (a: string[]) => number;
  };
  port.postMessage({ exit: loaded.default(args) });
};

// Side effects
// ============

if (isMainThread) {
  process.exitCode = await load()
    .then((m) => run(m, [], process.argv.slice(2), false))
    .catch((e: unknown) => {
      console.error("bend-lint: " + message(e));
      return 1;
    });
} else {
  await work(workerData as Start);
}
