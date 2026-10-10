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

import type { Body, Book, Err, LTerm, Parse, Patt, Quant, Span } from "bend2/bend.ts";
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
    return of(t);
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
    App: (t) => tree("Application", [term(t.f), term(t.x)], range(t.s)),
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
// each with its parent's id and its top-level node's (its owner).
// One pass, so it is linear in the nodes: `out` is local to it.
const nodeRecords = (trees: Tree[], first: number): string[] => {
  const out: string[] = [];
  const visit = (t: Tree, parent: number, owner: number): void => {
    const id = first + out.length;
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

// The answer to `check <path>`: each file the check parsed (path, namespace,
// text), then its syntax nodes; or why the check failed. The probe is
// global, so checks must not overlap.
const check = async ({ Bend, base }: Checker, path: string): Promise<string> => {
  const book = seeded(Bend, base);
  const seen = new Map<string, string | null>([[Bend.BASE_BEND, ""]]);
  const reported: Seen[] = [];
  const hook = globalThis as { BEND_LINT_SEE?: (seen: Seen) => void };
  hook.BEND_LINT_SEE = (s) => reported.push(s);
  try {
    await Bend.book_load(book, nodePath.resolve(path).replaceAll("\\", "/"), "", seen);
    Bend.book_valid(book, base.order.length);
  } catch (e) {
    return record(["fail", isErr(e) ? Bend.err_show(e) : message(e)]);
  } finally {
    hook.BEND_LINT_SEE = undefined;
  }
  const real = (ns: string): string =>
    [...seen].find(([at, n]) => at !== Bend.BASE_BEND && n === ns)?.[0] ?? "";
  const imports = reported.filter((s): s is SeenImport => s.$ === "import");
  const files = parsedOf(reported);
  const trees = files.map((parsed) => [
    ...importsOf(
      parsed.file,
      imports.filter((i) => i.real === parsed.file.real),
      real,
      Bend.BASE_BEND,
    ),
    ...declarationsOf(parsed),
  ]);
  return trees
    .reduce<{ sections: string[][]; next: number }>(
      ({ sections, next }, ts, j) => {
        const nodes = nodeRecords(ts, next);
        const { real, ns, text } = files[j].file;
        return {
          sections: [...sections, [record(["file", real, ns, text]), ...nodes]],
          next: next + nodes.length,
        };
      },
      { sections: [], next: 1 },
    )
    .sections.flat()
    .join("");
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
  return args.length !== 1
    ? Promise.resolve(record(["fail", "unknown request: " + line]))
    : op === "check"
      ? check(checker, args[0])
      : op === "real"
        ? Promise.resolve(realPath(args[0]))
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
