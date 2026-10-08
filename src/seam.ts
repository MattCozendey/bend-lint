// Everything bend-lint knows about bend2's internals: where bend2 is (or
// its download), what bend-lint changes in it as Bun loads it, and every
// call into it. The files on disk never change. In bend.ts, term_infer and
// term_check are renamed and replaced by the wrappers below, which tell
// `hook.see` what they return; and fs and path come from this module, in
// bend.ts and main.ts: bend.ts builds paths with "/" (path.posix), so here
// real paths use "/" and a Windows drive letter is a root; on POSIX they
// behave as node's. comp.ts exports RUNTIME_MAIN and js_sat, so a rule
// written in Bend is compiled once and run many times. main.ts exports how
// `bend` reads a book (book_read) and words a failure (book_err,
// Check_Fail), so bend-lint checks a file exactly as bend does.
// Each text edit must match exactly once, and each name a tail exports must
// be declared once. The wrappers pass every argument through, so bend
// computes what it would without them; load checks what they record, and
// what main.ts gives, before anything else runs.

import * as nodeFs from "node:fs";
import * as os from "node:os";
import * as nodePath from "node:path";
import * as url from "node:url";

import type { Ann, Book, Ctx, Err, HTerm, LTerm, Name, Quant, Span, Uses } from "bend2/bend.ts";
import type * as BendModule from "bend2/bend.ts";
import type * as CompModule from "bend2/comp.ts";
import type { Diag, Fact, FactFilter, Source, SourceFile } from "./lint.ts";

// Types
// =====

// A file's patch: exact edits, a tail appended to the file, and names it
// must declare once and export (the tail exports those it does not).
type Patch = { edits: Array<[string, string]>; tail: string; exports: string[] };

// What the checker reports for each checked term: what it was checked or
// inferred as, where, and how it was used.
export type See = (
  bok: Book,
  tm: LTerm,
  ty: HTerm,
  ctx: Ctx,
  dep: number,
  def: Name,
  spn: Span | undefined,
  qt: Quant,
  us: Uses,
) => void;

// An HTTP GET.
export type Get = (url: string) => Promise<Response>;

// How bendDir reaches the network, runs `bend`, where it caches, and where
// the bend repo would be; tests give their own. run gives a command's
// stdout, or undefined if it fails.
export type FindOptions = {
  get?: Get;
  run?: (cmd: string[]) => string | undefined;
  cache?: string;
  repo?: string;
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

export type Mapper = { (s: Span): Span; (s: Span | undefined): Span | undefined };

export type Checked = {
  book: Book;
  sources: Source[];
  span: Mapper;
  facts?: Map<LTerm, Fact>;
  failure?: Diag;
};

// A rule written in Bend, checked and compiled: what its id(), facts() and
// main() give.
type Compiled = { id: string; want: FactFilter | null; main: (args: string[]) => number };

// Constants
// =========

export const DriftError: new (message?: string, options?: ErrorOptions) => Error = function (
  message?: string,
  options?: ErrorOptions,
): Error {
  return Object.setPrototypeOf(
    Object.assign(new Error(message, options), { name: "DriftError" }),
    new.target!.prototype,
  );
} as ErrorConstructor;

const HERE = url.fileURLToPath(new URL(".", import.meta.url));
const DRIVE = /^[A-Za-z]:(?=\/)/;
const SHIM = JSON.stringify(url.pathToFileURL(nodePath.join(HERE, "seam.ts")).href);
const SAMPLE = nodePath.join(HERE, "sample.bend");

export const MARK = "BEND_LINT_PATCH";

const GIT = "https://github.com/bendlang/bend.git/info/refs?service=git-upload-pack";
const RAW = "https://raw.githubusercontent.com/bendlang/bend/";
const RELEASE = /^v\d+\.\d+\.\d+$/;
const DAY = 24 * 60 * 60 * 1000;
const EFF = /^effs\/[\w.-]+$/;

// Downloaded bends, one folder per release.
const CACHE = nodePath.join(
  process.env.XDG_CACHE_HOME ??
    (process.platform === "win32"
      ? (process.env.LOCALAPPDATA ?? nodePath.join(os.homedir(), "AppData", "Local"))
      : nodePath.join(os.homedir(), ".cache")),
  "bend-lint",
);

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
    ],
    tail:
      "import { seeInfer, seeCheck } from " +
      SHIM +
      ";\n" +
      "export const term_infer = seeInfer(unseen_term_infer);\n" +
      "export const term_check = seeCheck(unseen_term_check);\n",
    exports: [],
  },
  "comp.ts": { edits: [], tail: "", exports: ["RUNTIME_MAIN", "js_sat"] },
  "main.ts": { edits: SHIMMED, tail: "", exports: ["book_read", "book_err", "Check_Fail"] },
};

// The bend2 files bend-lint patches and imports.
export const PATCHED = Object.keys(PATCHES);

// Where the wrappers report, set for one check at a time.
export const hook: { see?: See } = {};

// Text an editor holds unsaved, by real path, set for one check at a time.
// bend.ts reads it in place of the file on disk.
export const unsaved = new Map<string, string>();

// Checked base.bend books, by the text of base.bend: Base is checked once
// per process, and again only if base.bend changes.
const BASES = new Map<string, Promise<Book>>();

// The check running now, or done; the next check waits for it.
let queue: Promise<unknown> = Promise.resolve();

// Line starts per file object (see starts).
const STARTS = new WeakMap<object, number[]>();

// Binders are explicit in checked terms, so Var.v cells are not followed.
// A new term kind is a type error here, and a DriftError when walked.
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
  readFileSync: ((p: nodeFs.PathOrFileDescriptor, ...rest: unknown[]) =>
    held(p) ??
    (nodeFs.readFileSync as (...a: unknown[]) => unknown)(
      p,
      ...rest,
    )) as typeof nodeFs.readFileSync,
};

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
    throw new DriftError(
      name +
        " takes " +
        f.length +
        " parameters, not " +
        n +
        "; update seeInfer and seeCheck in tools/bend-lint/src/seam.ts",
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
    const [book, lhs, tm, qt, ctx, d] = args;
    hook.see?.(book, r.tm, r.ty, ctx, d, lhs.def, tm.s, qt, r.us);
    return r;
  };
};

export const seeCheck = (f: typeof BendModule.term_check): typeof BendModule.term_check => {
  arity(f, 7, "term_check");
  return (...args) => {
    const r = f(...args);
    const [book, lhs, tm, qt, ty, ctx, d] = args;
    hook.see?.(book, r.tm, ty, ctx, d, lhs.def, tm.s, qt, r.us);
    return r;
  };
};

// `file` is one of PATCHED.
export const patch = (file: string, src: string): string => {
  const { edits, tail, exports } = PATCHES[file];
  const drift = (what: string, n: number): never => {
    throw new DriftError(
      "cannot patch bend2/" +
        file +
        ": found " +
        n +
        " of " +
        what +
        ", expected 1. Update PATCHES in tools/bend-lint/src/seam.ts.",
    );
  };
  const edited = edits.reduce((out, [at, to]) => {
    const n = out.split(at).length - 1;
    return n === 1 ? out.replace(at, () => to) : drift(JSON.stringify(at), n);
  }, src);
  const missing = exports.filter((name) => {
    const n =
      edited.match(
        new RegExp(
          "^(?:export )?(?:async function|function|class|const|let) " + name + "\\b",
          "gm",
        ),
      )?.length ?? 0;
    return n === 1
      ? !new RegExp(
          "^export (?:async function|function|class|const|let) " + name + "\\b",
          "m",
        ).test(edited)
      : drift("a declaration of " + name, n);
  });
  return (
    edited +
    "\n" +
    tail +
    (missing.length === 0 ? "" : "export { " + missing.join(", ") + " };\n") +
    "export const " +
    MARK +
    " = 1;\n"
  );
};

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

// The newest release, from git's list of refs (GitHub's API limits calls).
// It asks at most once a day (a missing or damaged note asks again);
// offline, it takes the newest one cached.
export const latestTag = async (cache: string = CACHE, get: Get = download): Promise<string> => {
  const note = nodePath.join(cache, "latest.json");
  let known: { tag?: unknown; at?: unknown } | undefined;
  try {
    known = JSON.parse(nodeFs.readFileSync(note, "utf8"));
  } catch {
    known = undefined;
  }
  if (
    typeof known?.tag === "string" &&
    RELEASE.test(known.tag) &&
    typeof known.at === "number" &&
    Date.now() - known.at < DAY
  ) {
    return known.tag;
  }
  const newest = (tags: string[]): string | undefined =>
    tags
      .filter((t) => RELEASE.test(t))
      .map((t) => t.slice(1).split(".").map(Number))
      .sort((a, b) => b[0] - a[0] || b[1] - a[1] || b[2] - a[2])
      .map((v) => "v" + v.join("."))[0];
  const listed = await get(GIT)
    .then((res) =>
      res.ok ? res.text() : Promise.reject(new Error("GitHub answered " + res.status)),
    )
    .then(
      (refs) => newest([...refs.matchAll(/refs\/tags\/(v[\d.]+)$/gm)].map((m) => m[1])),
      (e: unknown) => {
        const cached = newest(nodeFs.existsSync(cache) ? nodeFs.readdirSync(cache) : []);
        return (
          cached ??
          Promise.reject(
            new Error(
              "cannot list bend's releases (" +
                (e instanceof Error ? e.message : String(e)) +
                "); give a bend checkout with --bend <dir> or BEND_DIR",
            ),
          )
        );
      },
    );
  if (listed === undefined) {
    throw new Error("bend has no release tags; give a bend checkout with --bend <dir> or BEND_DIR");
  }
  nodeFs.mkdirSync(cache, { recursive: true });
  nodeFs.writeFileSync(note, JSON.stringify({ tag: listed, at: Date.now() }));
  return listed;
};

// bend2 at a release: the PATCHED files, safe.ts (main.ts imports it),
// base.bend, and the effs/ files base.bend imports, kept in
// <cache>/<tag>/bend2. A download goes to a temporary folder first, so the
// cache never holds a partial one; a cached folder without main.ts (from an
// older bend-lint) is downloaded again.
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
  const text = (file: string): Promise<[string, string]> =>
    get(RAW + tag + "/bend2/" + file)
      .then((res) =>
        res.ok
          ? res.text()
          : Promise.reject(new Error("GitHub answered " + res.status + " for bend2/" + file)),
      )
      .then((body) => [file, body]);
  const base = await text("base.bend");
  const effs = [
    ...new Set([...base[1].matchAll(/^\s*import "\.\/(effs\/[^"]+)"/gm)].map((m) => m[1])),
  ];
  const odd = effs.find((f) => !EFF.test(f));
  if (odd !== undefined) {
    throw new Error("base.bend imports " + odd + ", which is not a plain file in effs/");
  }
  const files = [base, ...(await Promise.all([...PATCHED, "safe.ts", ...effs].map(text)))];
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

// The bend2 folder to load: `given` (from --bend), else $BEND_DIR, else
// the bend repo around tools/bend-lint, if there is one, else a release
// from GitHub: the installed bend's version, or the newest. A bend
// checkout works too, for its bend2 folder.
export const bendDir = async (
  given: string | undefined,
  { get = download, run = spawn, cache = CACHE, repo }: FindOptions = {},
): Promise<string> => {
  const chosen = given ?? process.env.BEND_DIR;
  const dir = path.resolve(chosen ?? repo ?? path.join(HERE, "..", "..", "..", "bend2"));
  const found = [path.join(dir, "bend2"), dir].find((d) =>
    nodeFs.existsSync(path.join(d, "bend.ts")),
  );
  if (found !== undefined) {
    return fs.realpathSync(found);
  }
  if (chosen !== undefined) {
    throw new Error(
      "no bend2 at " +
        dir +
        " (it needs bend.ts); give a bend checkout with --bend <dir> or BEND_DIR",
    );
  }
  const tag = installedTag(run) ?? (await latestTag(cache, get));
  const fresh = !nodeFs.existsSync(nodePath.join(cache, tag, "bend2"));
  const got = await fetchBend(tag, cache, get).catch((e: unknown) => {
    throw new Error(
      "could not download bend " +
        tag +
        " (" +
        (e instanceof Error ? e.message : String(e)) +
        "); give a bend checkout with --bend <dir> or BEND_DIR",
    );
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
    const children = (CHILDREN as Record<string, ((tm: LTerm) => LTerm[]) | undefined>)[t.$];
    if (children === undefined) {
      throw new DriftError(
        "unknown term kind " + t.$ + "; update CHILDREN in tools/bend-lint/src/seam.ts",
      );
    }
    yield t;
    const next = children(t);
    for (let i = next.length - 1; i >= 0; i--) {
      stack.push(next[i]);
    }
  }
}

// Where each line of a file starts, computed once per file object.
export const starts = (file: Span["file"]): number[] => {
  const known = STARTS.get(file);
  if (known !== undefined) {
    return known;
  }
  const out = [0, ...[...file.str.matchAll(/\n/g)].map((m) => m.index! + 1)];
  STARTS.set(file, out);
  return out;
};

// The index of the line that holds `off`, given each line's start.
export const line = (starts: number[], off: number): number => {
  let [lo, hi] = [0, starts.length - 1];
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    [lo, hi] = starts[mid] <= off ? [mid, hi] : [lo, mid - 1];
  }
  return lo;
};

// bend.ts parses a copy of each file with its import lines blanked, so a
// span moves to the file on disk by line and column. The copy's namespace,
// folder and lines pick the file; a copy that matches no file, or two, is
// a DriftError.
export const mapper = (sources: Source[]): Mapper => {
  const own = new Set<unknown>(sources.map((s) => s.file));
  const memo = new WeakMap<object, { file: SourceFile; from: number[]; to: number[] }>();
  const find = (
    f: Span["file"] & { dir?: string },
  ): { file: SourceFile; from: number[]; to: number[] } => {
    const lines = f.str.split("\n");
    const found = sources.filter((src) => {
      const theirs = src.text.split("\n");
      return (
        f.ns === src.ns &&
        (f.dir === undefined || f.dir === src.path.slice(0, src.path.lastIndexOf("/") + 1)) &&
        lines.length === theirs.length &&
        lines.every(
          (l, i) => l === theirs[i] || (l.trim() === "" && /^\s*import(\s|$)/.test(theirs[i])),
        )
      );
    });
    if (found.length !== 1) {
      throw new DriftError(
        "cannot map a bend.ts span to a file on disk (" +
          found.length +
          " candidates); bend.ts may mask imports another way now",
      );
    }
    Object.assign(found[0].file.al, f.al);
    const known = { file: found[0].file, from: starts(f), to: starts(found[0].file) };
    memo.set(f, known);
    return known;
  };
  return ((s: Span | undefined): Span | undefined => {
    if (s === undefined || own.has(s.file)) {
      return s;
    }
    const { file, from, to } = memo.get(s.file) ?? find(s.file);
    const at = (off: number): number => {
      const i = line(from, off);
      return to[i] + off - from[i];
    };
    return { file, beg: at(s.beg), end: at(s.end) };
  }) as Mapper;
};

const isErr = (e: unknown): e is Err =>
  typeof e === "object" && e !== null && (e as { $?: unknown }).$ === "Err";

// A term's kind, annotations stripped, and the name a Var or Ref points to.
export const shape = (m: Loaded, tm: LTerm): { kind: string; name: Name } => {
  const t = m.Bend.term_strip(tm);
  return { kind: t.$, name: t.$ === "Var" || t.$ === "Ref" ? t.k : "" };
};

// Whether a fact passes a filter, its scope aside.
export const matches = (f: FactFilter, kind: string, def: Name, name: Name): boolean => {
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
): Promise<Checked> => {
  const { Bend, Main } = m;
  const seen = new Map<string, string | null>();
  const found: Array<Omit<Fact, "inst">> = [];
  const real = fs.existsSync(file) ? fs.realpathSync(file) : "";
  const home = real.slice(0, real.lastIndexOf("/") + 1);
  const far = filters.filter((f) => f.scope === "program");
  const program = far.length > 0;
  const seeded = real !== "" && /^import Base$/m.test(fs.readFileSync(real, "utf8"));
  const key = fs.readFileSync(Bend.BASE_BEND, "utf8");
  if (seeded && !BASES.has(key)) {
    BASES.set(key, Main.book_read(Bend.BASE_BEND));
  }
  let book: Book = Bend.book_nil();
  const caught = await Promise.resolve(seeded ? BASES.get(key) : undefined)
    .then(async (base) => {
      hook.see =
        filters.length > 0
          ? (bok, tm, ty, ctx, dep, def, spn, qt, us) => {
              const at = spn?.file as { dir?: string; ns?: string } | undefined;
              const near = at?.dir === home && at.ns === "" ? filters : far;
              const { kind, name } = near.length > 0 ? shape(m, tm) : { kind: "", name: "" };
              if (near.some((f) => matches(f, kind, def, name))) {
                found.push({ tm, ty, bok, ctx, dep, def, spn, qt, us });
              }
            }
          : undefined;
      book = await Main.book_read(file, base, seen);
    })
    .then(
      () => undefined,
      (e: unknown) => ({ e: e instanceof Main.Check_Fail ? e.why : e }),
    );
  signal.throwIfAborted();
  const root = [...seen.keys()].find((real) => real !== Bend.BASE_BEND || !seeded);
  const sources = [...seen.keys()]
    .filter((real) => fs.existsSync(real))
    .map((real): Source => {
      const text = fs.readFileSync(real, "utf8");
      const ns = seen.get(real) ?? "";
      return {
        path: real,
        ns,
        text,
        root: real === root,
        base: real === Bend.BASE_BEND,
        file: { str: text, ns, al: {}, path: real },
      };
    });
  const span = mapper(sources);
  if (caught === undefined) {
    const insts = new Set(Object.values(book.tmps).flatMap((t) => [...t.values()]));
    const own = new Set<unknown>(
      sources.filter((s) => (program ? !s.base : s.root)).map((s) => s.file),
    );
    const facts = found.flatMap((f): Array<[LTerm, Fact]> => {
      const spn = span(f.spn);
      return spn !== undefined && own.has(spn.file)
        ? [[f.tm, { ...f, inst: insts.has(f.def), spn }]]
        : [];
    });
    return { book, sources, span, facts: filters.length > 0 ? new Map(facts) : undefined };
  }
  const err = isErr(caught.e) ? caught.e : undefined;
  let spn: Span | undefined;
  try {
    spn = span(err?.spn);
  } catch {
    spn = undefined;
  }
  return {
    book,
    sources,
    span,
    failure: {
      code: "bend/check",
      severity: "error",
      message: failure(m, caught.e),
      spn,
      def: err?.def,
      fixes: [],
      core: caught.e,
    },
  };
};

// Checks a book with bend2/main.ts book_read, as `bend <file>` does; it
// does not give main.ts's verdict on @unsafe and foreign code. A file with
// a line exactly `import Base` starts from the checked Base, as `bend
// --checkup` does. `text` (unsaved editor text) is read in place of the
// files on disk. The hook and the text are global to bend, so checks run
// one at a time, in the order asked. A fact is kept as the checker gives
// it only if a filter wants it; with scope file, only if it is from the
// linted file's folder and namespace. After the check, only facts whose
// span maps to the linted file (or, with scope program, to any file but
// Base) stay.
export const check = (
  m: Loaded,
  file: string,
  filters: FactFilter[],
  signal: AbortSignal,
  text?: ReadonlyMap<string, string>,
): Promise<Checked> => {
  const turn = queue.then(async (): Promise<Checked> => {
    signal.throwIfAborted();
    for (const [at, str] of text ?? []) {
      if (fs.existsSync(at)) {
        unsaved.set(fs.realpathSync(at), str);
      }
    }
    try {
      return await checked(m, file, filters, signal);
    } finally {
      hook.see = undefined;
      unsaved.clear();
    }
  });
  queue = turn.catch(() => undefined);
  return turn;
};

export const binder = (m: Loaded, fact: Fact, v: LTerm = m.Bend.term_strip(fact.tm)): Ann | null =>
  v.$ === "Var" ? m.Bend.pmap_get(fact.ctx, v.i) : null;

export const show = (m: Loaded, fact: Fact, ty: HTerm): string =>
  m.Bend.term_show(m.Bend.term_lower(ty, fact.dep));

export const same = (m: Loaded, fact: Fact, a: HTerm, b: HTerm): boolean =>
  m.Bend.term_compare("EQ", fact.bok, a, b, fact.dep);

export const normal = (m: Loaded, fact: Fact, ty: HTerm): HTerm => m.Bend.term_snf(fact.bok, ty);

export const uses = (m: Loaded, fact: Fact): Array<{ name: Name; quantity: Quant }> =>
  m.Bend.pmap_to_array(fact.us).flatMap(([v, quantity]) =>
    quantity.$ === "None" ? [] : [{ name: m.Bend.pmap_get(fact.ctx, v)?.k ?? "", quantity }],
  );

// A fact as a Bend rule sees it; `inner` is the term's span without its
// annotations.
export const view = (
  m: Loaded,
  fact: Fact,
  span: Mapper,
): {
  owner: Name;
  inst: boolean;
  kind: string;
  name: Name;
  quantity: Quant["$"];
  spn?: Span;
  inner?: Span;
} => ({
  owner: fact.def,
  inst: fact.inst,
  ...shape(m, fact.tm),
  quantity: fact.qt.$,
  spn: fact.spn,
  inner: span(m.Bend.term_strip(fact.tm).s),
});

// bend's own error layout for a finding: its message, context and location.
export const layout = (m: Loaded, d: Diag): string =>
  m.Bend.err_show(
    isErr(d.core)
      ? d.core
      : m.Bend.Err(
          d.bok ?? m.Bend.book_nil(),
          d.ctx ?? m.Bend.ctx_nil(),
          d.message,
          undefined,
          d.spn,
          d.def,
        ),
  );

// A Bend rule's id(), facts() and main(), compiled as comp.ts io_run does.
// facts(), checked: NoFacts{} gives null, Want{...} a filter.
export const compile = (m: Loaded, book: Book, file: string): Compiled => {
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
  const texts = (t: LTerm | undefined): string[] | undefined => {
    const out: string[] = [];
    for (let at = t; ; at = args(at, "Con")?.[1]) {
      const [head] = args(at, "Con") ?? [];
      if (args(at, "Nil") !== undefined) {
        return out;
      }
      if (head?.$ !== "Lit" || typeof head.v !== "string") {
        return undefined;
      }
      out.push(head.v);
    }
  };
  const asked = value("facts");
  const [scope, kinds, defs, names] = args(asked, "Want") ?? [];
  const want =
    args(asked, "NoFacts") !== undefined
      ? null
      : {
          scope:
            args(scope, "File") !== undefined
              ? ("file" as const)
              : args(scope, "Program") !== undefined
                ? ("program" as const)
                : undefined,
          kinds: texts(kinds),
          defs: texts(defs),
          names: texts(names),
        };
  if (
    id === undefined ||
    Comp.io_type(book) === null ||
    (want !== null && [want.scope, want.kinds, want.defs, want.names].includes(undefined))
  ) {
    throw new Error(
      file + " must define id() -> String, facts() -> Lint.Want and main() -> IO(Unit)",
    );
  }
  const main = new Function(
    "require",
    Comp.js_lib(book) +
      "\n" +
      Comp.RUNTIME_MAIN +
      "\nreturn (args) => { cli_args = args; return io_run(" +
      Comp.js_sat("main") +
      "); };",
  )(import.meta.require) as (args: string[]) => number;
  return { id, want: want as FactFilter | null, main };
};

// What main.ts must give, as bend-lint calls it; a mismatch is a
// DriftError.
export const guardMain = (Main: Main): void => {
  const wrong = (
    [
      ["book_read(file, base, seen = ...)", Main.book_read?.length === 2],
      ["book_err(e)", Main.book_err?.length === 1],
      [
        "new Check_Fail(why).why",
        typeof Main.Check_Fail === "function" && new Main.Check_Fail(MARK).why === MARK,
      ],
    ] as const
  ).flatMap(([what, ok]) => (ok ? [] : [what]));
  if (wrong.length > 0) {
    throw new DriftError(
      "bend2/main.ts no longer has " +
        wrong.join(", ") +
        "; update PATCHES in tools/bend-lint/src/seam.ts",
    );
  }
};

// Reads sample.bend with book_read and checks what the wrappers record for
// `x` in `def id(x: N) -> N: x`, and that a missing file fails as a
// Check_Fail.
const selfCheck = async (m: Loaded): Promise<void> => {
  const { Bend, Main } = m;
  const seen = new Map<string, string | null>();
  const facts: Fact[] = [];
  hook.see = (bok, tm, ty, ctx, dep, def, spn, qt, us) =>
    void facts.push({ tm, ty, bok, ctx, dep, def, spn, qt, us, inst: false });
  const book = await Main.book_read(SAMPLE, undefined, seen)
    .catch(() => undefined)
    .finally(() => {
      hook.see = undefined;
    });
  const missing = await Main.book_read(path.join(HERE, "missing.bend")).then(
    () => false,
    (e: unknown) => e instanceof Main.Check_Fail,
  );
  const xs = facts.filter((f) => f.def === "id" && Bend.term_strip(f.tm).$ === "Var");
  const kind = (f: Fact, t: HTerm) => (Bend.term_wnf(f.bok, t) as { k?: string }).k;
  const tagged = (x: unknown, tags: string[]) =>
    tags.includes((x as { $?: string } | null)?.$ ?? "");
  const read = (
    [
      ["book (book_read)", book?.tlds.id !== undefined && seen.has(fs.realpathSync(SAMPLE))],
      ["failure (Check_Fail for a missing file)", missing],
    ] as const
  ).flatMap(([what, ok]) => (ok ? [] : [what]));
  const wrong =
    xs.length < 2
      ? ["facts (one from each wrapper)"]
      : xs.flatMap((x) => {
          if (
            typeof x.dep !== "number" ||
            !tagged(x.ctx, ["Emp", "Bin"]) ||
            !tagged(x.us, ["Emp", "Bin"]) ||
            !tagged(x.qt, ["None", "Lone", "Many"])
          ) {
            return ["kinds of values"];
          }
          const v = Bend.term_strip(x.tm) as Extract<LTerm, { $: "Var" }>;
          const bound = Bend.pmap_get(x.ctx, v.i);
          return (
            [
              ["type", kind(x, x.ty) === "N"],
              ["depth", x.dep === 1],
              ["scope", bound?.k === "x" && kind(x, bound.T) === "N"],
              ["quantity", x.qt.$ === "Lone"],
              ["uses", Bend.pmap_get(x.us, v.i)?.$ === "Lone"],
              ["span", x.spn !== undefined && x.spn.file.str.slice(x.spn.beg, x.spn.end) === "x"],
            ] as const
          ).flatMap(([what, ok]) => (ok ? [] : [what]));
        });
  if (read.length + wrong.length > 0) {
    throw new DriftError(
      "self-check failed: the patched bend2 gave the wrong " +
        [...new Set([...read, ...wrong])].join(", ") +
        " for `x` in `def id(x: N) -> N: x` (src/sample.bend); update tools/bend-lint/src/seam.ts",
    );
  }
};

// Finds bend2 (see bendDir), patches its PATCHED files as Bun loads them,
// imports them, then checks what main.ts gives and what the wrappers
// record. Imported, main.ts also registers bend's own loader for
// `import "x.bend"`.
export const load = async (given: string | undefined): Promise<Loaded> => {
  const dir = await bendDir(given);
  const patched = new Map(
    PATCHED.map((f) => [path.join(dir, f), patch(f, fs.readFileSync(path.join(dir, f), "utf8"))]),
  );
  const exact = dir.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replaceAll("/", "[\\\\/]");
  const names = PATCHED.map((f) => f.replace(/\.ts$/, "")).join("|");
  const filter = new RegExp(
    "^" + exact + "[\\\\/](" + names + ")\\.ts$",
    process.platform === "win32" ? "i" : "",
  );
  Bun.plugin({
    name: "bend-lint",
    setup: (build) => {
      build.onLoad({ filter }, (args) => {
        const contents = patched.get(fs.realpathSync(args.path));
        if (contents === undefined) {
          throw new DriftError("bend-lint matched " + args.path + " but did not patch it");
        }
        return { contents, loader: "ts" };
      });
    },
  });
  const [B, C, M]: [
    typeof BendModule & { [MARK]?: number },
    Comp & { [MARK]?: number },
    Main & { [MARK]?: number },
  ] = await Promise.all([
    import(url.pathToFileURL(path.join(dir, "bend.ts")).href),
    import(url.pathToFileURL(path.join(dir, "comp.ts")).href),
    import(url.pathToFileURL(path.join(dir, "main.ts")).href),
  ]);
  if (B[MARK] !== 1 || C[MARK] !== 1 || M[MARK] !== 1) {
    throw new DriftError(
      "bend2 was loaded before bend-lint could patch it; import bend-lint first",
    );
  }
  guardMain(M);
  const loaded = { Bend: B, Comp: C, Main: M, BEND2: dir };
  await selfCheck(loaded);
  return loaded;
};

// Side effects
// ============

Object.setPrototypeOf(DriftError.prototype, Error.prototype);
