// The rewrite's host: see the header of main.bend. The main thread loads and
// patches bend2 and answers effects; main.bend runs in a worker, whose
// effects ask the main thread and wait for the answer, because bend2's JS
// runtime calls an effect and takes its result at once, and a check is
// async.

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

import type { Book, Err, HTerm, Name } from "bend2/bend.ts";
import type { Span as BendSpan } from "bend2/bend.ts";
import type * as BendModule from "bend2/bend.ts";
import type * as CompModule from "bend2/comp.ts";

// Types
// =====

// A file's patch: exact edits, text it must hold once unchanged (needs), and
// names it must declare once and export.
type Patch = { edits: Array<[string, string]>; needs: string[]; exports: string[] };

type Comp = typeof CompModule & { RUNTIME_MAIN: string; js_sat(k: Name): string };

// main.ts as the patch exports it: book_read throws a Check_Fail holding why
// the check failed.
type Main = {
  book_read(file: string, base?: Book, seen?: Map<string, string | null>): Promise<Book>;
  book_err(e: unknown): string;
  Check_Fail: new (why: unknown) => { why: unknown };
};

type Loaded = { Bend: typeof BendModule; Comp: Comp; Main: Main; base: Book };

// A main.bend value as plain data: a String, U32 or Bool as itself, a List
// as an array, a constructor as its name in main.bend or Base with its
// fields.
type Plain = string | number | boolean | Plain[] | { $: string; [field: string]: Plain };

// A constructor as compiled JS spells it: its key, and its fields in order.
type Ctor = { key: string; fields: string[] };

// What an effect asks the main thread.
type Ask = { op: "check"; path: string };

// What the worker gets: the compiled program's file, its argv, the
// constructors of main.bend and Base, and the channel to the main thread.
type Start = {
  file: string;
  args: string[];
  ctors: Record<string, Ctor>;
  port: MessagePort;
  flag: Int32Array;
};

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

const CACHE = nodePath.join(
  process.env.XDG_CACHE_HOME ??
    (process.platform === "win32"
      ? (process.env.LOCALAPPDATA ?? nodePath.join(os.homedir(), "AppData", "Local"))
      : nodePath.join(os.homedir(), ".cache")),
  "bend-lint",
);

// Compiled programs, by their text.
const COMPILED = nodePath.join(CACHE, "host");

const SHIMMED: Array<[string, string]> = [
  ['import * as fs from "node:fs";', `import { fs } from "${SHIM}";`],
  ['import * as path from "node:path";', `import { path } from "${SHIM}";`],
];

const PATCHES: Record<string, Patch> = {
  "bend.ts": { edits: SHIMMED, needs: [], exports: [] },
  "comp.ts": {
    edits: [],
    needs: ["let cli_args = [];", "function io_run(m) {"],
    exports: ["RUNTIME_MAIN", "js_sat"],
  },
  "main.ts": { edits: SHIMMED, needs: [], exports: ["book_read", "book_err", "Check_Fail"] },
};

const PATCHED = Object.keys(PATCHES);

// The program bend2 checks and compiles: main.bend, run with its rules. It
// is never on disk; fs below serves it.
const PROGRAM = nodePath.join(HERE, "program.bend").split(nodePath.sep).join("/");

const PROGRAM_TEXT = `import Base
import ./main.bend as Lint

def main() -> IO(Unit):
  Lint.run([])
`;

// fs and path for bend.ts and main.ts: real paths with "/", so imports
// resolve on Windows, and the program served from memory.
const fs = {
  ...nodeFs,
  existsSync: (p: nodeFs.PathLike): boolean => p === PROGRAM || nodeFs.existsSync(p),
  realpathSync: (p: nodeFs.PathLike): string =>
    p === PROGRAM ? PROGRAM : slash(nodeFs.realpathSync(p)),
  readFileSync: ((p: nodeFs.PathOrFileDescriptor, ...rest: unknown[]) =>
    p === PROGRAM
      ? PROGRAM_TEXT
      : (nodeFs.readFileSync as (...a: unknown[]) => unknown)(
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

// `file` is one of PATCHED. Its line ends become LF, so an edit can span
// lines in a CRLF checkout.
const patch = (file: string, src: string): string => {
  const { edits, needs, exports } = PATCHES[file];
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
  return `${edited}\n${named}export const ${MARK} = 1;\n`;
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
      build.module(SHIM, () => ({ exports: { fs, path }, loader: "object" }));
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
  return { Bend, Comp, Main, base: await Main.book_read(Bend.BASE_BEND) };
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

// bend.ts parses a copy of each file with its import lines blanked, so a
// span moves to the file on disk by line and column. The copy's namespace
// and folder, and its lines, pick the file among those the check read.
const located = (
  seen: Map<string, string | null>,
  s: BendSpan,
): { path: string; beg: number; end: number } | undefined => {
  const copy: BendSpan["file"] & { dir?: string } = s.file;
  const lines = copy.str.split("\n");
  const found = [...seen]
    .filter(
      ([real, ns]) =>
        (ns ?? "") === copy.ns &&
        (copy.dir === undefined || copy.dir === real.slice(0, real.lastIndexOf("/") + 1)),
    )
    .map(([real]) => ({ real, text: fs.readFileSync(real, "utf8").replace(/\r\n/g, "\n") }))
    .filter(({ text }) => {
      const theirs = text.split("\n");
      return (
        theirs.length === lines.length &&
        lines.every(
          (l: string, i: number) =>
            l === theirs[i] || (l.trim() === "" && /^\s*import(\s|$)/.test(theirs[i])),
        )
      );
    });
  if (found.length !== 1) {
    return undefined;
  }
  const [{ real, text }] = found;
  const from = starts(copy.str);
  const to = starts(text);
  const at = (off: number): number => {
    const i = from.reduce((last, start, j) => (start <= off ? j : last), 0);
    return points(text.slice(0, to[i] + off - from[i]));
  };
  return { path: real, beg: at(s.beg), end: at(s.end) };
};

// The bend/check finding of `file` as plain data, or None when it checks.
const checkFailure = async (m: Loaded, file: string): Promise<Plain> => {
  const seen = new Map<string, string | null>();
  const failed = await m.Main.book_read(file, m.base, seen).then(
    () => undefined,
    (e: unknown) => ({ e: why(m, e) }),
  );
  if (failed === undefined) {
    return { $: "None" };
  }
  const at =
    isErr(failed.e) && failed.e.spn !== undefined ? located(seen, failed.e.spn) : undefined;
  return {
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
  };
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

// The program as a module, run as comp.ts io_run runs it, kept in COMPILED
// by its text, so the same program is written once. A file is written whole
// or not at all.
const compiled = (m: Loaded, book: Book): string => {
  const js = [
    'import { createRequire } from "node:module";',
    `const require = createRequire(${JSON.stringify(import.meta.url)});`,
    m.Comp.js_lib(book),
    m.Comp.RUNTIME_MAIN,
    `export default (args) => { cli_args = args; return io_run(${m.Comp.js_sat("main")}); };`,
  ].join("\n");
  const file = nodePath.join(COMPILED, Bun.hash(js).toString(16) + ".mjs");
  if (!nodeFs.existsSync(file)) {
    nodeFs.mkdirSync(COMPILED, { recursive: true });
    const temp = `${file}.${process.pid}`;
    nodeFs.writeFileSync(temp, js);
    nodeFs.renameSync(temp, file);
  }
  return file;
};

// Runs main.bend in a worker, with `args`, and answers its effects; settles
// with its exit code.
const host = async (args: string[]): Promise<number> => {
  const m = await load();
  const seen = new Map<string, string | null>();
  const book = await m.Main.book_read(PROGRAM, m.base, seen).catch((e: unknown) => {
    throw new Error("main.bend does not check:\n" + failure(m, why(m, e)));
  });
  const { port1, port2 } = new MessageChannel();
  const flag = new Int32Array(new SharedArrayBuffer(4));
  const start: Start = {
    file: compiled(m, book),
    args: [PROGRAM, ...args],
    ctors: ctorsOf(m, book, seen),
    port: port2,
    flag,
  };
  const worker = new Worker(url.fileURLToPath(import.meta.url), {
    workerData: start,
    transferList: [port2],
  });
  return new Promise((done, fail) => {
    worker.on("error", fail);
    port1.on("message", (msg: Ask | { exit: number }) => {
      if ("exit" in msg) {
        port1.close();
        done(msg.exit);
        return;
      }
      void checkFailure(m, msg.path).then((reply) => {
        port1.postMessage(reply);
        Atomics.store(flag, 0, 1);
        Atomics.notify(flag, 0);
      }, fail);
    });
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

// The worker: runs the compiled program; an effect asks the main thread and
// waits for its answer.
const work = async (start: Start): Promise<void> => {
  const { file, args, ctors, port, flag } = start;
  const ask = (q: Ask): unknown => {
    Atomics.store(flag, 0, 0);
    port.postMessage(q);
    Atomics.wait(flag, 0, 0);
    return valueOf(ctors, receiveMessageOnPort(port)?.message as Plain);
  };
  (globalThis as typeof globalThis & { BEND_HOST?: Host }).BEND_HOST = { ask };
  const program = (await import(url.pathToFileURL(file).href)) as {
    default: (a: string[]) => number;
  };
  port.postMessage({ exit: program.default(args) });
};

// Side effects
// ============

if (isMainThread) {
  process.exitCode = await host(process.argv.slice(2)).catch((e: unknown) => {
    console.error("bend-lint: " + message(e));
    return 1;
  });
} else {
  await work(workerData as Start);
}
