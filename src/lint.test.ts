import { afterAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import type { Book, LTerm, Span as BendSpan } from "bend2/bend.ts";
import type * as BendModule from "bend2/bend.ts";
import * as api from "./lint.ts";
import { applyFixes, createLinter } from "./lint.ts";
import type {
  Diag,
  Edit,
  Fact,
  FactFilter,
  LintOptions,
  LintResult,
  LintRule,
  RuleContext,
  Source,
} from "./lint.ts";
import { ERROR, unwrap } from "./result.ts";
import type { Result } from "./result.ts";
import {
  DRIFT,
  bendDir,
  fetchBend,
  guardMain,
  installedTag,
  latestTag,
  mapper,
  patch,
  relative,
  resolve,
  seeCheck,
  seeInfer,
  walk,
} from "./seam.ts";
import type { Raw } from "./seam.ts";

// Types
// =====

type Loose = Raw & { tm: { x?: { $: string; k?: string; i?: number } } };
type Seen = { kind: string; def: string; name: string; path: string };

// Constants
// =========

const linter = unwrap(await createLinter());
const { BEND2, render } = linter;

// bend2's modules as bend-lint patched them, for what the tests inspect.
const Bend: typeof BendModule = await import(pathToFileURL(path.join(BEND2, "bend.ts")).href);
const Comp: Record<string, unknown> = await import(pathToFileURL(path.join(BEND2, "comp.ts")).href);

const USERLAND = String.raw`type N is Data:
  Z{}
  S{p: N}

def Alias() -> Type:
  N

def id(x: Alias()) -> Alias():
  x

def generic(~T: Type, x: T) -> T:
  x

def proof(-x: N) -> {x == x : N}:
  {==}

def peel(x: N) -> N:
  match x:
    case Z{}:
      Z{}
    case S{p}:
      p

def main() -> N:
  a = id(S{Z{}})
  generic(~N,a)
`;

const ERASURE = String.raw`type N is Data:
  Z{}
  S{p: N}

def Alias() -> Type:
  N

def direct(x: N) -> N:
  copy : N = x
  copy

def alias(x: N) -> N:
  copy : Alias() = x
  copy

def generic(~T: Type, x: T) -> T:
  copy : T = x
  copy

def dependent(-x: N, p: {x == x : N}) -> {x == x : N}:
  copy : {x == x : N} = p
  copy

def required_lambda(x: N) -> N:
  f : N -> N = y => y
  f(x)

def required_constructor() -> N:
  value : N = Z{}
  value

def main() -> N:
  direct(alias(generic(~N, required_lambda(required_constructor()))))
`;

// Tests in the bend checkout (bend2/../tests) whose first expected line
// says if the check passes.
const BEND_TESTS = [
  "check/alpha_equivalence",
  "check/assert_plain_fill",
  "check/dependent_telescope",
  "check/beta_ann_body",
  "check/ctor_arity",
  "check/forward_reference",
  "check/hole_todo",
  "check/typed_let_mismatch",
  "import/base_prelude",
  "import/string_literal",
  "import/alias_shadow",
  "import/duplicate_name",
];

// Inside the repo, so a Bend rule here can import ../../bend/lint.bend;
// .tmp/ is ignored by git.
const TMP = fileURLToPath(new URL("./.tmp", import.meta.url));
const DIR = (fs.mkdirSync(TMP, { recursive: true }), fs.mkdtempSync(path.join(TMP, "run-")));
const CLI = fileURLToPath(new URL("./lint.ts", import.meta.url));

// The comma-space rule, written in Bend: source text only.
const COMMA_BEND = String.raw`import Base
import ../../bend/lint.bend as Lint

def id() -> String:
  "style/comma-space"

def facts() -> Lint.Want:
  Lint.NoFacts{}

def is_word(+c: Char) -> Bool:
  Bool.or(Char.is_alpha(c), Bool.or(Char.is_digit(c), Char.is_eq(c, '_')))

def comma_before_word(+c: Char, rest: String) -> Bool:
  match rest:
    case SNil{}:
      False{}
    case SCon{n, t}:
      Bool.and(Char.is_eq(c, ','), is_word(n))

def keep(hit: Bool, +at: U32, tail: List<&2, U32>) -> List<&2, U32>:
  match hit:
    case True{}:
      U32.add(at, 1) <> tail
    case False{}:
      tail

# A tail call: bend runs it as a loop, so a long file does not overflow the
# stack.
def commas(s: String, +at: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match s:
    case SNil{}:
      acc
    case SCon{+c, +rest}:
      commas(rest, U32.add(at, 1), keep(comma_before_word(c, rest), at, acc))

def diag_at(+span: Lint.Span) -> Lint.Diag:
  Lint.Diag{Lint.Warning{}, "Add a space after the comma.", Some{span}, [Lint.Fix{"Insert space", Lint.Safe{}, [Lint.Edit{span, " "}]}]}

def diag(path: String, +at: U32) -> Lint.Diag:
  diag_at(Lint.Span{path, at, at})

def diags(+path: String, ats: List<&2, U32>) -> List<&2, Lint.Diag>:
  match ats:
    case Nil{}:
      []
    case Con{+at, rest}:
      diag(path, at) <> diags(path, rest)

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  match input:
    case Lint.Input{Lint.Source{+path, text, root}, sources, options}:
      IO.pure(List<&2, Lint.Diag>, diags(path, commas(text, 0, [])))

def main() -> IO(Unit):
  Lint.serve(run)
`;

// A typed rule written in Bend: for each Var in def id, its type and normal
// form, whether the checker finds it equal to its binder's, its text, how
// many times it is demanded, and what it uses.
const TYPES_BEND = String.raw`import Base
import ../../bend/lint.bend as Lint

def id() -> String:
  "test/types"

def facts() -> Lint.Want:
  Lint.Want{Lint.File{}, ["Var"], ["id"], [], False{}}

def verdict(same: Bool) -> String:
  match same:
    case True{}:
      " (same as its binder)"
    case False{}:
      " (unlike its binder)"

def compare(b: Maybe<&2, Lint.Term>, t: Lint.Term) -> IO(Bool):
  match b:
    case None{}:
      IO.pure(Bool, False{})
    case Some{x}:
      Lint.same(x, t)

def quantity(q: Lint.Quantity) -> String:
  match q:
    case Lint.Erased{}:
      "erased"
    case Lint.Once{}:
      "once"
    case Lint.Many{}:
      "many"

def use_text(u: Lint.Use) -> String:
  match u:
    case Lint.Use{name, q}:
      name ++ " " ++ quantity(q)

def first_use(us: List<&2, Lint.Use>) -> String:
  match us:
    case Nil{}:
      "nothing"
    case Con{u, rest}:
      use_text(u)

def text_of(inner: Maybe<&2, Lint.Span>) -> IO(String):
  match inner:
    case None{}:
      IO.pure(String, "")
    case Some{s}:
      Lint.text(s)

def node_of(f: Lint.Fact) -> Lint.Node:
  match f:
    case Lint.Fact{n, owner, inst, q, t, span}:
      n

def type_of(f: Lint.Fact) -> Lint.Term:
  match f:
    case Lint.Fact{n, owner, inst, q, t, span}:
      t

def quantity_of(f: Lint.Fact) -> Lint.Quantity:
  match f:
    case Lint.Fact{n, owner, inst, q, t, span}:
      q

def fact_span(f: Lint.Fact) -> Maybe<&2, Lint.Span>:
  match f:
    case Lint.Fact{n, owner, inst, q, t, span}:
      span

def name_of(s: Lint.Shape) -> String:
  match s:
    case Lint.Shape{kind, name, span, children}:
      name

def span_of(s: Lint.Shape) -> Maybe<&2, Lint.Span>:
  match s:
    case Lint.Shape{kind, name, span, children}:
      span

def step(found: List<&2, Lint.Diag>, +f: Lint.Fact) -> IO(List<&2, Lint.Diag>):
  do IO<List<&2, Lint.Diag>>:
    n : Lint.Node <- Lint.strip(node_of(f))
    +bare : Lint.Shape <- Lint.shape(n)
    shown : String <- Lint.show(type_of(f))
    nt : Lint.Term <- Lint.normal(type_of(f))
    nf : String <- Lint.show(nt)
    b : Maybe<&2, Lint.Term> <- Lint.binder(f)
    same : Bool <- compare(b, type_of(f))
    here : String <- text_of(span_of(bare))
    us : List<&2, Lint.Use> <- Lint.uses(f)
    return Lint.Diag{Lint.Hint{}, name_of(bare) ++ ": " ++ shown ++ " = " ++ nf ++ verdict(same) ++ ", text " ++ here ++ ", demanded " ++ quantity(quantity_of(f)) ++ ", uses " ++ first_use(us), fact_span(f), []} <> found

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  Lint.fold_facts(~List<&2, Lint.Diag>, ~step, [])

def main() -> IO(Unit):
  Lint.serve(run)
`;

const commaSpace: LintRule = {
  id: "style/comma-space",
  run: (cx) =>
    [...cx.root.text.matchAll(/,(?=\w)/g)].map((m) => {
      const span = { file: cx.root, beg: m.index! + 1, end: m.index! + 1 };
      return cx.diag({
        message: "Add a space after the comma.",
        severity: "warning",
        span,
        fixes: [{ title: "Insert space", applicability: "safe", edits: [{ span, text: " " }] }],
      });
    }),
};

const identity: LintRule = {
  id: "example/identity",
  facts: true,
  run: async (cx) => {
    await Promise.resolve();
    cx.signal.throwIfAborted();
    const body = facts(cx, "id").find(
      (f) => loose(cx, f).dep === 1 && loose(cx, f).tm.x?.$ === "Var",
    )!;
    const raw = loose(cx, body);
    const ann = cx.unstable.Bend.pmap_get(raw.ctx, raw.tm.x!.i!)!;
    expect(ann.k).toBe("x");
    expect((cx.unstable.Bend.term_wnf(raw.bok, raw.ty) as { k?: string }).k).toBe("N");
    expect(cx.same(body.type, cx.binder(body)!)).toBe(true);
    return [
      cx.diag({
        message: "This function returns its parameter.",
        severity: "information",
        span: body.span,
        fact: body,
      }),
    ];
  },
};

const neverRun: LintRule = {
  id: "test/never-run",
  facts: true,
  run: () => {
    throw new Error("this rule must not run");
  },
};

// x : T = v, where v is a variable that already has type T. Constructors
// and lambdas keep theirs: checking needs the expected type.
const redundantAnnotation: LintRule = {
  id: "erasure/redundant-local-annotation",
  facts: true,
  run: (cx) =>
    cx.facts.flatMap((fact): Diag[] => {
      const { span } = fact;
      const { kind, name: used, span: inner } = cx.shape(cx.strip(fact.node));
      const declared = cx.binder(fact);
      if (
        kind !== "Var" ||
        span === undefined ||
        inner === undefined ||
        declared === undefined ||
        !cx.same(declared, fact.type)
      ) {
        return [];
      }
      const prefix = span.file.text.slice(span.beg, inner.beg);
      const name = prefix.match(/^([A-Za-z_][A-Za-z_0-9]*)\s*:/);
      if (
        span.file !== inner.file ||
        span.beg >= inner.beg ||
        prefix.includes("#") ||
        name === null ||
        !prefix.trimEnd().endsWith("=")
      ) {
        return [];
      }
      const at = {
        file: span.file,
        beg: span.beg + name[1].length,
        end: span.beg + prefix.lastIndexOf("="),
      };
      return [
        cx.diag({
          message:
            "Remove the redundant annotation: " +
            used +
            " already has type " +
            cx.show(declared) +
            ".",
          severity: "hint",
          span: at,
          fact,
          fixes: [
            {
              title: "Remove redundant local type annotation",
              applicability: "suggested",
              edits: [{ span: at, text: " " }],
            },
          ],
        }),
      ];
    }),
};

// A Bend rule that reports its options.
const OPTIONS_BEND = String.raw`import Base
import ../../bend/lint.bend as Lint

def id() -> String:
  "test/options"

def facts() -> Lint.Want:
  Lint.NoFacts{}

def options() -> List<&2, Lint.Declared>:
  [Lint.Declared{"width", Lint.NumberOption{2, 1, 80}}, Lint.Declared{"wrap", Lint.FlagOption{False{}}}, Lint.Declared{"name", Lint.TextOption{"none", []}}]

def summary(+opts: List<&2, Lint.Option>) -> String:
  U32.show(Lint.option_number(opts, "width")) ++ " " ++ Bool.show(Lint.option_flag(opts, "wrap")) ++ " " ++ Lint.option_text(opts, "name")

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  match input:
    case Lint.Input{root, sources, +options}:
      IO.pure(List<&2, Lint.Diag>, [Lint.Diag{Lint.Hint{}, summary(options), None{}, []}])

def main() -> IO(Unit):
  Lint.serve(run)
`;

// A Bend rule that counts the facts it pulls, from the linted file and its
// imports: the Vars.
const COUNT_BEND = String.raw`import Base
import ../../bend/lint.bend as Lint

def id() -> String:
  "test/count"

def facts() -> Lint.Want:
  Lint.Want{Lint.Program{}, ["Var"], [], [], False{}}

def add(n: U32, +f: Lint.Fact) -> IO(U32):
  IO.pure(U32, U32.add(n, 1))

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  do IO<List<&2, Lint.Diag>>:
    n : U32 <- Lint.fold_facts(~U32, ~add, 0)
    return [Lint.Diag{Lint.Hint{}, U32.show(n), None{}, []}]

def main() -> IO(Unit):
  Lint.serve(run)
`;

// A Bend rule that reads the term view: the root of id's body and its
// first child, a Var fact's node, its first child and its fact back, and
// a def that does not exist.
const TREE_BEND = String.raw`import Base
import ../../bend/lint.bend as Lint

def id() -> String:
  "test/tree"

def facts() -> Lint.Want:
  Lint.Want{Lint.File{}, ["Var"], ["id"], [], False{}}

def kind_of(s: Lint.Shape) -> String:
  match s:
    case Lint.Shape{kind, name, span, children}:
      kind

def first(s: Lint.Shape) -> Maybe<&2, Lint.Node>:
  match s:
    case Lint.Shape{kind, name, span, children}:
      match children:
        case Nil{}:
          None{}
        case Con{c, rest}:
          Some{c}

def up(m: Maybe<&2, Lint.Node>) -> String:
  match m:
    case None{}:
      ""
    case Some{p}:
      "^"

def child_kind(m: Maybe<&2, Lint.Node>) -> IO(String):
  match m:
    case None{}:
      IO.pure(String, "nothing")
    case Some{+n}:
      do IO<String>:
        +s : Lint.Shape <- Lint.shape(n)
        p : Maybe<&2, Lint.Node> <- Lint.parent(n)
        return kind_of(s) ++ up(p)

def top(m: Maybe<&2, Lint.Node>) -> IO(String):
  match m:
    case None{}:
      IO.pure(String, "no body")
    case Some{n}:
      do IO<String>:
        +s : Lint.Shape <- Lint.shape(n)
        c : String <- child_kind(first(s))
        return kind_of(s) ++ " > " ++ c

def found(m: Maybe<&2, Lint.Fact>) -> String:
  match m:
    case None{}:
      "lost"
    case Some{f}:
      "found"

def node_of(f: Lint.Fact) -> Lint.Node:
  match f:
    case Lint.Fact{n, owner, inst, q, t, span}:
      n

def about(+f: Lint.Fact) -> IO(String):
  do IO<String>:
    +n : Lint.Node <- IO.pure(Lint.Node, node_of(f))
    +s : Lint.Shape <- Lint.shape(n)
    g : Maybe<&2, Lint.Fact> <- Lint.fact(n)
    c : String <- child_kind(first(s))
    return kind_of(s) ++ " > " ++ c ++ " " ++ found(g)

def back(m: Maybe<&2, Lint.Fact>) -> IO(String):
  match m:
    case None{}:
      IO.pure(String, "no fact")
    case Some{f}:
      about(f)

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  do IO<List<&2, Lint.Diag>>:
    b : Maybe<&2, Lint.Node> <- Lint.body("id")
    t : String <- top(b)
    m : Maybe<&2, Lint.Fact> <- Lint.next_fact()
    k : String <- back(m)
    none : Maybe<&2, Lint.Node> <- Lint.body("nope")
    t2 : String <- top(none)
    return [Lint.Diag{Lint.Hint{}, t ++ "; " ++ k ++ "; " ++ t2, None{}, []}]

def main() -> IO(Unit):
  Lint.serve(run)
`;

// A rule that reports its options.
const echo: LintRule = {
  id: "test/echo",
  options: {
    tabWidth: { type: "integer", minimum: 1, default: 2 },
    breakLines: { type: "boolean", default: false },
  },
  run: (cx) => [cx.diag({ message: JSON.stringify(cx.options), severity: "hint" })],
};

// Functions
// =========

// The linter's entry points, unwrapped: a failure throws its message, and
// so does a rule that crashed (an expect in a rule that failed, say).
async function lint(file: string, rules: LintRule[], options?: LintOptions): Promise<LintResult> {
  const res = unwrap(await linter.lint(file, rules, options));
  const crash = res.diags.find((d) => d.code === "bend-lint/rule-crash");
  if (crash !== undefined) {
    throw new Error(crash.message);
  }
  return res;
}

async function bendRule(file: string): Promise<LintRule> {
  return unwrap(await linter.bendRule(file));
}

function findConfig(file: string) {
  return unwrap(api.findConfig(file));
}

function readConfig(file: string) {
  return unwrap(api.readConfig(file));
}

// Whether a run found no error.
function clean(res: LintResult): boolean {
  return !res.diags.some((d) => d.severity === "error");
}

// Whether `f` throws a drift error.
function drifts(f: () => unknown): boolean {
  try {
    f();
  } catch (e) {
    return (e as { [DRIFT]?: boolean })[DRIFT] === true;
  }
  return false;
}

function file2(p: string, ns: string): { str: string; ns: string; al: {}; path: string } {
  return { str: "x\n", ns, al: {}, path: p };
}

function fixture(name: string, text: string): string {
  const file = path.join(DIR, name);
  fs.writeFileSync(file, text);
  return file;
}

// The facts of a def's checked body, parents first.
function facts(cx: RuleContext, name: string): Fact[] {
  const body = cx.body(name);
  return body === undefined ? [] : cx.nodes(body).flatMap((n) => cx.fact(n) ?? []);
}

// A fact as bend2 gives it.
function loose(cx: RuleContext, fact: Fact): Loose {
  return cx.unstable.raw(fact) as Loose;
}

function bodies(book: Book): Record<string, string> {
  return Object.fromEntries(
    book.order.flatMap((name) => {
      const tld = book.tlds[name];
      return tld.$ === "Def" && tld.e !== undefined && !tld.b
        ? [[name, Bend.term_show(tld.e)]]
        : [];
    }),
  );
}

function root(sources: Source[]): Source {
  return sources.find((s) => s.root)!;
}

// The facts a rule with this filter gets: kind, def, name and file.
async function seen(file: string, want: LintRule["facts"]): Promise<Seen[]> {
  let got: Seen[] = [];
  await lint(file, [
    {
      id: "test/seen",
      facts: want,
      run: (cx) => {
        got = cx.facts.map((f) => {
          const { kind, name } = cx.shape(cx.strip(f.node));
          return { kind, def: f.owner, name, path: f.span!.file.path };
        });
        return [];
      },
    },
  ]);
  return got;
}

// A GitHub that lists `tags` and serves this checkout's bend2 at any
// release; it records the URLs it is asked for.
function github(tags: string[]): { get: (url: string) => Promise<Response>; asked: string[] } {
  const asked: string[] = [];
  const get = async (url: string): Promise<Response> => {
    asked.push(url);
    const file = url.match(
      /^https:\/\/raw\.githubusercontent\.com\/bendlang\/bend\/v[\d.]+\/bend2\/(.+)$/,
    )?.[1];
    return url.includes("/info/refs")
      ? new Response(
          [
            "0000 HEAD\0caps",
            ...tags.flatMap((t) => ["0000 refs/tags/" + t, "0000 refs/tags/" + t + "^{}"]),
            "0000 refs/heads/main",
          ].join("\n") + "\n",
        )
      : file !== undefined && fs.existsSync(path.join(BEND2, file))
        ? new Response(fs.readFileSync(path.join(BEND2, file), "utf8"))
        : new Response("", { status: 404 });
  };
  return { get, asked };
}

function run(...args: string[]) {
  return spawnSync(process.execPath, [CLI, ...args], { encoding: "utf8" });
}

function module(name: string, body: string): string {
  return fixture(name, "export const rules = " + body + ";\n");
}

// Tests
// =====

afterAll(() => fs.rmSync(DIR, { recursive: true, force: true }));

describe("patch", () => {
  const src = fs.readFileSync(path.join(BEND2, "bend.ts"), "utf8");
  const comp = fs.readFileSync(path.join(BEND2, "comp.ts"), "utf8");
  const main = fs.readFileSync(path.join(BEND2, "main.ts"), "utf8");

  test("bend.ts: renames term_infer and term_check behind wrappers, and swaps fs and path", () => {
    const out = patch("bend.ts", src);
    expect(out).toContain("function unseen_term_infer(");
    expect(out).toContain("function unseen_term_check(");
    expect(out).toContain("export const term_infer = seeInfer(unseen_term_infer);");
    expect(out).toContain("export const term_check = seeCheck(unseen_term_check);");
    expect(out).not.toMatch(/^export function term_(infer|check)\(/m);
    expect(out).toMatch(/^import \{ fs \} from "file:.*seam\.ts";/m);
    expect(out).toMatch(/^import \{ path \} from "file:.*seam\.ts";/m);
  });

  test("comp.ts: exports RUNTIME_MAIN and js_sat", () => {
    expect(patch("comp.ts", comp)).toContain("export { RUNTIME_MAIN, js_sat };");
  });

  test("main.ts: exports how bend reads a book and words a failure, with the same fs and path", () => {
    const out = patch("main.ts", main);
    expect(out).toContain("export { book_read, book_err, Check_Fail };");
    expect(out).toMatch(/^import \{ fs \} from "file:.*seam\.ts";/m);
    expect(out).toMatch(/^import \{ path \} from "file:.*seam\.ts";/m);
    expect(() =>
      patch("main.ts", main.replace("async function book_read(", "async function book_load_file(")),
    ).toThrow(/main\.ts: found 0 of a declaration of book_read/);
  });

  test("fails loudly when an edit or a needed name is missing or repeated", () => {
    expect(
      drifts(() =>
        patch(
          "bend.ts",
          src.replace("export function term_infer(", "export function term_infer2("),
        ),
      ),
    ).toBe(true);
    expect(() =>
      patch("bend.ts", src.replace('import * as fs from "node:fs";', 'import fs from "node:fs";')),
    ).toThrow(/node:fs/);
    expect(() => patch("bend.ts", src + "\nexport function term_check(\n")).toThrow(
      /found 2 of "export function term_check\("/,
    );
    expect(() => patch("comp.ts", comp.replace("function js_sat(", "function js_name("))).toThrow(
      /comp\.ts: found 0 of a declaration of js_sat/,
    );
    expect(() =>
      patch("comp.ts", comp.replace("function io_run(m) {", "function run(m) {")),
    ).toThrow(/comp\.ts: found 0 of "function io_run\(m\) \{"/);
  });

  test("main.ts must give book_read, book_err and Check_Fail as bend-lint calls them", () => {
    const Check_Fail = function (this: { why: unknown }, why: unknown) {
      this.why = why;
    } as unknown as new (why: unknown) => { why: unknown };
    const good = {
      book_read: (_file: string, _base?: unknown) => Promise.reject(),
      book_err: (_e: unknown) => "",
      Check_Fail,
    };
    expect(() => guardMain(good as never)).not.toThrow();
    expect(() =>
      guardMain({ ...good, book_read: (_file: string) => Promise.reject() } as never),
    ).toThrow(/main\.ts no longer has book_read\(file, base, seen = \.\.\.\)/);
    expect(() => guardMain({ ...good, Check_Fail: function () {} } as never)).toThrow(
      /main\.ts no longer has new Check_Fail\(why\)\.why/,
    );
    expect(drifts(() => guardMain({ ...good, Check_Fail: function () {} } as never))).toBe(true);
  });

  test("the loaded bend.ts and comp.ts are the patched ones", () => {
    expect((Bend as unknown as Record<string, unknown>).BEND_LINT_PATCH).toBe(1);
    expect((Comp as unknown as Record<string, unknown>).BEND_LINT_PATCH).toBe(1);
  });

  test("a check is bend's own: a PROOF.bend that skips ./LAWS.bend fails as bend says", async () => {
    const dir = path.join(DIR, "proof");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "LAWS.bend"), "def one() -> Type:\n  Type\n");
    const res = await lint(fixture("proof/PROOF.bend", "def two() -> Type:\n  Type\n"), []);
    expect([clean(res), res.diags[0].message]).toEqual([
      false,
      "PROOF.bend must import ./LAWS.bend",
    ]);
  });

  test("the wrappers pass every argument through, and need the expected arity", () => {
    const got: unknown[][] = [];
    const fake = ((...args: unknown[]) => (
      got.push(args),
      { tm: null, us: null }
    )) as unknown as typeof Bend.term_check;
    Object.defineProperty(fake, "length", { value: 7 });
    (seeCheck(fake) as unknown as (...a: unknown[]) => unknown)(
      {},
      { def: "d" },
      {},
      1,
      2,
      3,
      4,
      "extra",
    );
    expect(got).toEqual([[{}, { def: "d" }, {}, 1, 2, 3, 4, "extra"]]);
    Object.defineProperty(fake, "length", { value: 5 });
    expect(() => seeInfer(fake as unknown as typeof Bend.term_infer)).toThrow(
      /term_infer takes 5 parameters, not 6/,
    );
  });

  test("bend2 is found from a checkout, its bend2 folder, or the repo; a wrong dir fails", async () => {
    const repo = path.dirname(BEND2);
    expect([await bendDir(repo), await bendDir(BEND2), await bendDir(undefined)]).toEqual([
      BEND2,
      BEND2,
      BEND2,
    ]);
    await expect(bendDir(DIR)).rejects.toThrow(/no bend2 at/);
  });

  test("paths: a drive letter is a root; POSIX paths are unchanged", () => {
    expect(resolve("C:/cwd", "C:/Users/m/", "./dep.bend")).toBe("C:/Users/m/dep.bend");
    expect(resolve("C:/cwd", "C:/Users/m/", "/shared/x.bend")).toBe("C:/shared/x.bend");
    expect(resolve("/home/x", "/a/b/", "../c.bend")).toBe("/a/c.bend");
    expect(resolve("/home/x", "y.bend")).toBe("/home/x/y.bend");
    expect(relative("C:/Users/m/", "C:/Users/m/sub/d.bend")).toBe("sub/d.bend");
    expect(relative("/a/b", "/a/c/d.bend")).toBe("../c/d.bend");
  });
});

describe("downloading bend", () => {
  const cache = () => fs.mkdtempSync(path.join(DIR, "cache-"));
  const offline = () => Promise.reject(new Error("offline"));

  test("the installed bend's version comes first; else the newest release, asked once a day", async () => {
    expect([
      installedTag(() => "bend 2.0.36\n"),
      installedTag(() => undefined),
      installedTag(() => "nope"),
    ]).toEqual(["v2.0.36", undefined, undefined]);
    const gh = github(["v2.0.9", "v2.0.36", "v2.0.10", "nightly"]);
    const at = cache();
    expect([await latestTag(at, gh.get), await latestTag(at, gh.get)]).toEqual([
      "v2.0.36",
      "v2.0.36",
    ]);
    expect(gh.asked.length).toBe(1);
    fs.writeFileSync(path.join(at, "latest.json"), "{ damaged");
    expect(await latestTag(at, gh.get)).toBe("v2.0.36");
    expect(installedTag(() => "bend 2.0.36\nA newer bend is out.\n")).toBe("v2.0.36");
  });

  test("offline, the newest release in the cache is used", async () => {
    const at = cache();
    ["v2.0.3", "v2.0.12", "latest-ish"].forEach((d) => fs.mkdirSync(path.join(at, d)));
    expect(await latestTag(at, offline)).toBe("v2.0.12");
    expect(fs.existsSync(path.join(at, "latest.json"))).toBe(false);
    const gh = github(["v2.0.40"]);
    expect(await latestTag(at, gh.get)).toBe("v2.0.40");
    expect(gh.asked.length).toBe(1);
    await expect(latestTag(cache(), offline)).rejects.toThrow(
      /cannot list bend's releases \(offline\)/,
    );
  });

  test("a release downloads once and whole, and bend-lint runs on it", async () => {
    const gh = github([]);
    const at = cache();
    const dir = await fetchBend("v2.0.36", at, gh.get);
    const effs = fs.readdirSync(path.join(BEND2, "effs"));
    expect(fs.readFileSync(path.join(dir, "bend.ts"), "utf8")).toBe(
      fs.readFileSync(path.join(BEND2, "bend.ts"), "utf8"),
    );
    expect(fs.readFileSync(path.join(dir, "main.ts"), "utf8")).toBe(
      fs.readFileSync(path.join(BEND2, "main.ts"), "utf8"),
    );
    expect(fs.readdirSync(path.join(dir, "effs")).sort()).toEqual(effs.sort());
    expect(gh.asked.length).toBe(5 + effs.length);
    expect(await fetchBend("v2.0.36", at, gh.get)).toBe(dir);
    expect(gh.asked.length).toBe(5 + effs.length);
    fs.rmSync(path.join(dir, "main.ts")); // a cache from before main.ts was patched
    expect(await fetchBend("v2.0.36", at, gh.get)).toBe(dir);
    expect(gh.asked.length).toBe(2 * (5 + effs.length));
    expect(fs.existsSync(path.join(dir, "main.ts"))).toBe(true);
    expect(fs.readdirSync(path.join(at, "v2.0.36"))).toEqual(["bend2"]);
    const out = spawnSync(process.execPath, [CLI, fixture("downloaded.bend", USERLAND)], {
      encoding: "utf8",
      env: { ...process.env, BEND_DIR: dir },
    });
    expect([out.status, out.stderr]).toEqual([0, ""]);
    await expect(fetchBend("../x", at, gh.get)).rejects.toThrow(/not a bend release/);
  });

  test("bendDir downloads only when no bend is given or around it", async () => {
    const saved = process.env.BEND_DIR;
    delete process.env.BEND_DIR; // a given bend would win over all below
    try {
      const gh = github(["v2.0.35"]);
      const at = cache();
      const away = { get: gh.get, cache: at, repo: DIR };
      expect(await bendDir(undefined, { ...away, run: () => "bend 2.0.36\n" })).toBe(
        fs.realpathSync(path.join(at, "v2.0.36", "bend2")).replaceAll("\\", "/"),
      );
      expect(await bendDir(undefined, { ...away, run: () => undefined })).toBe(
        fs.realpathSync(path.join(at, "v2.0.35", "bend2")).replaceAll("\\", "/"),
      );
      await expect(
        bendDir(undefined, { get: offline, cache: at, repo: DIR, run: () => "bend 2.0.40\n" }),
      ).rejects.toThrow(/could not download bend v2\.0\.40 \(offline\)/);
      expect(
        await bendDir(undefined, {
          get: offline,
          cache: at,
          repo: BEND2,
          run: () => "bend 2.0.40\n",
        }),
      ).toBe(BEND2);
    } finally {
      if (saved !== undefined) {
        process.env.BEND_DIR = saved;
      }
    }
  });
});

describe("spans", () => {
  const source = (p: string, text: string) => ({
    str: text,
    ns: "",
    al: {} as Record<string, string>,
    path: p,
  });

  for (const eol of ["\n", "\r\n"]) {
    const text = ["import Base", "import ./a.bend as A", "", "def f() -> N:", "  x", ""].join(eol);
    const lines = text.split("\n");
    for (const [kind, masked] of [
      ["empty", lines.map((l) => (l.startsWith("import") ? "" : l)).join("\n")],
      ["spaces", lines.map((l) => (l.startsWith("import") ? " ".repeat(l.length) : l)).join("\n")],
    ]) {
      test("map past " + kind + " import lines (" + JSON.stringify(eol) + ")", () => {
        const src = source("/p/m.bend", text);
        const beg = masked.indexOf("x");
        const got = mapper([src])({
          file: { str: masked, ns: "", dir: "/p/", al: { A: "a" } },
          beg,
          end: beg + 1,
        } as BendSpan)!;
        expect(got.file).toBe(src);
        expect(text.slice(got.beg, got.end)).toBe("x");
        expect(src.al.A).toBe("a");
      });
    }
  }

  test("a span on disk passes through; a copy that does not match fails", () => {
    const src = source("/p/m.bend", "import Base\ndef f() -> N:\n  x\n");
    const map = mapper([src]);
    const spn = { file: src, beg: 2, end: 3 };
    expect(map(spn)).toBe(spn);
    expect(
      drifts(() =>
        map({ file: { str: "\ndef g() -> N:\n  x\n", ns: "", al: {} }, beg: 0, end: 0 }),
      ),
    ).toBe(true);
    expect(
      drifts(() => map({ file: { str: "def f() -> N:\n  x\n", ns: "", al: {} }, beg: 0, end: 0 })),
    ).toBe(true);
  });

  test("the directory picks between equal files", () => {
    const a = source("/a/m.bend", "import Base\nx\n");
    const b = source("/b/m.bend", "import Base\nx\n");
    const map = mapper([a, b]);
    expect(
      map({ file: { str: "\nx\n", ns: "", dir: "/b/", al: {} }, beg: 1, end: 2 } as BendSpan)!.file,
    ).toBe(b);
  });
});

describe("lint", () => {
  const userland = fixture("userland.bend", USERLAND);

  test("source and typed rules report in order, with fixes on the file on disk", async () => {
    const res = await lint(userland, [commaSpace, identity]);
    expect(clean(res)).toBe(true);
    expect(res.diags.map((d) => d.code)).toEqual([commaSpace.id, identity.id]);
    expect(res.diags[0].fixes[0].edits[0].span.file.text).toBe(USERLAND);
    expect(render(res.diags[0])).toStartWith("Warning [style/comma-space]:");
    expect(render(res.diags[0])).toContain("generic(~N, a)");
    expect(render(res.diags[1])).toContain("Context:");
  });

  test("only rules with facts get facts", async () => {
    const look: LintRule = {
      id: "test/look",
      run: (cx) => {
        expect(cx.facts).toEqual([]);
        return [];
      },
    };
    expect(clean(await lint(userland, [look, identity]))).toBe(true);
    expect((await lint(userland, [commaSpace])).facts).toEqual([]);
  });

  test("nodes lists a body parents first, and parent goes back up", async () => {
    const walk: LintRule = {
      id: "test/walk",
      run: (cx) => {
        const root = cx.body("peel")!;
        const all = cx.nodes(root);
        expect(all[0]).toBe(root);
        expect(all.length).toBeGreaterThan(3);
        expect(cx.parent(root)).toBeUndefined();
        all.slice(1).forEach((n, i) => {
          const up = cx.parent(n)!;
          expect(all.indexOf(up)).toBeLessThanOrEqual(i);
          expect(cx.shape(up).children).toContain(n);
        });
        return [];
      },
    };
    expect(clean(await lint(userland, [walk, walk]))).toBe(true);
  });

  test("the term view: bodies, nodes, shapes, and a node's fact only if the rule asked for it", async () => {
    const tree: LintRule = {
      id: "test/tree",
      facts: { kinds: ["Var"], defs: ["id"] },
      run: (cx) => {
        const all = cx.nodes(cx.body("id")!);
        const x = cx.facts.find((f) => cx.shape(cx.strip(f.node)).name === "x")!;
        expect(all).toContain(x.node);
        expect(cx.fact(x.node)).toBe(x);
        expect(cx.shape(x.node).kind).toBe("Ann");
        expect(cx.shape(cx.strip(x.node))).toEqual(cx.shape(cx.shape(x.node).children[0]));
        expect(cx.shape(cx.shape(x.node).children[0])).toMatchObject({
          kind: "Var",
          name: "x",
        });
        const theirs = all.map((n) => cx.fact(n)).filter((f) => f !== undefined);
        expect(theirs.length).toBeGreaterThan(0);
        expect(theirs.every((f) => cx.shape(cx.strip(f.node)).kind === "Var")).toBe(true);
        expect(cx.body("nope")).toBeUndefined();
        return [];
      },
    };
    const every: LintRule = {
      id: "test/every",
      facts: true,
      run: (cx) => {
        const kept = cx.nodes(cx.body("id")!).flatMap((n) => cx.fact(n) ?? []);
        expect(kept.some((f) => cx.shape(cx.strip(f.node)).kind !== "Var")).toBe(true);
        return [];
      },
    };
    expect(clean(await lint(userland, [tree, every]))).toBe(true);
  });

  test("facts cover templates, proofs, matches and fields", async () => {
    const probe: LintRule = {
      id: "test/probe",
      facts: { instances: true },
      run: (cx) => {
        const named = (def: string, kind: string, name = "") =>
          facts(cx, def).find((f) => {
            const x = loose(cx, f).tm.x;
            return x?.$ === kind && (name === "" || x.k === name);
          })!;
        const generic = named("generic", "Var", "x");
        expect(loose(cx, generic).bok.tlds["generic~T"]).toBeDefined();
        expect(generic.inst).toBe(false);
        const inst = named("generic~0", "Var", "x");
        expect(inst.inst).toBe(true);
        expect(inst.span).toEqual(generic.span);
        expect(["erased", "once", "many"]).toContain(generic.quantity);
        expect(loose(cx, generic).us.$).toBeDefined();
        const proof = named("proof", "Rfl");
        expect(loose(cx, proof).ty.$).toBe("Eql");
        expect(loose(cx, proof).dep).toBe(1);
        const peel = cx.nodes(cx.body("peel")!).map((n) => ({ n, ...cx.shape(n) }));
        expect(peel.some((s) => s.kind === "Mat")).toBe(true);
        expect(
          peel.some(
            (s) =>
              s.kind === "Ann" &&
              cx.shape(s.children[0]).kind === "Efq" &&
              cx.fact(s.n) === undefined,
          ),
        ).toBe(true);
        const field = loose(cx, named("peel", "Var", "p"));
        expect(cx.unstable.Bend.pmap_get(field.ctx, field.tm.x!.i!)!.k).toBe("p");
        return [];
      },
    };
    expect(clean(await lint(userland, [probe]))).toBe(true);
  });

  test("walk reaches every kind in checked bodies; an unknown kind fails", async () => {
    const res = await lint(userland, []);
    const { book } = res.unstable;
    const kinds = new Set(
      book.order.flatMap((name) => {
        const tld = book.tlds[name];
        return tld.$ === "Def" && tld.e !== undefined ? [...walk(tld.e)].map((tm) => tm.$) : [];
      }),
    );
    for (const k of ["Mat", "Lam", "App", "Var", "Ctr"])
      expect(kinds.has(k as LTerm["$"])).toBe(true);
    expect(drifts(() => walk({ $: "Nope" } as unknown as LTerm).next())).toBe(true);
  });

  test("walk preserves constructor and type argument order across traversals", () => {
    const children: LTerm[] = [
      { $: "Ref", k: "first" },
      { $: "Ref", k: "second" },
    ];
    for (const $ of ["Ctr", "ADT"] as const) {
      const term = { $, k: "Pair", x: children } as LTerm;
      const original = [...children];
      expect([...walk(term)]).toEqual([term, ...original]);
      expect(children).toEqual(original);
      expect([...walk(term)]).toEqual([term, ...original]);
      expect(children).toEqual(original);
    }
  });

  test("a failed check is one bend/check error; only rules without facts run", async () => {
    const parse = await lint(fixture("parse.bend", "type N is Data:\n  Z{}\ndef broken(\n"), [
      neverRun,
      commaSpace,
    ]);
    expect(clean(parse)).toBe(false);
    expect(parse.diags.map((d) => d.code)).toEqual(["bend/check"]);
    const commas = await lint(fixture("comma.bend", "def broken(a,b) -> N:\n  a\n"), [
      neverRun,
      commaSpace,
    ]);
    expect(commas.diags.map((d) => d.code)).toEqual(["bend/check", commaSpace.id]);
    expect(render(parse.diags[0])).toStartWith("Error [bend/check]:");
    expect(
      clean(
        await lint(
          fixture("name.bend", "type N is Data:\n  Z{}\ndef broken() -> N:\n  missing\n"),
          [neverRun],
        ),
      ),
    ).toBe(false);
    const todo = await lint(
      fixture("todo.bend", "type N is Data:\n  Z{}\ndef broken() -> N:\n  ?TODO\n"),
      [neverRun],
    );
    expect(todo.diags[0].message).toStartWith("1 TODO found");
    // The message is bend's, its location aside: expected and observed, with the names in scope.
    const types = "type N is Data:\n  Z{}\n\ntype M is Data:\n  W{}\n\n";
    expect(
      (await lint(fixture("mismatch.bend", types + "def bad(x: N) -> M:\n  x\n"), [neverRun]))
        .diags[0].message,
    ).toBe("expected: M\nobserved: N");
    expect(
      (await lint(fixture("bound.bend", types + "def bad(A: Type, x: N) -> A:\n  x\n"), [neverRun]))
        .diags[0].message,
    ).toBe("expected: A\nobserved: N");
    expect(clean(await lint(path.join(DIR, "missing.bend"), [neverRun]))).toBe(false);
  });

  test("an error finding does not stop later rules; the code is always the rule's id", async () => {
    const stamp: LintRule = {
      id: "test/stamp",
      run: (cx) => [{ ...cx.diag({ message: "stamped", severity: "hint" }), code: "other/code" }],
    };
    expect((await lint(userland, [stamp])).diags[0].code).toBe(stamp.id);
    const stop: LintRule = {
      id: "test/error",
      run: (cx) => [cx.diag({ message: "failed", severity: "error" })],
    };
    const res = await lint(userland, [stop, stamp]);
    expect(clean(res)).toBe(false);
    expect(res.diags.map((d) => d.code)).toEqual([stop.id, stamp.id]);
  });

  test("a bad rule and an abort reach the caller; a rule that fails is a finding", async () => {
    await expect(lint(userland, [{ id: "bad", run: () => [] }])).rejects.toThrow(/invalid rule/);
    await expect(lint(userland, [undefined as unknown as LintRule])).rejects.toThrow(
      /invalid rule at 0/,
    );
    const broken: LintRule = {
      id: "test/broken-fix",
      run: (cx) => {
        const span = { file: cx.root, beg: 0, end: 4 };
        return [
          cx.diag({
            message: "b",
            fixes: [
              {
                title: "two",
                applicability: "safe",
                edits: [
                  { span, text: "a" },
                  { span, text: "b" },
                ],
              },
            ],
          }),
        ];
      },
    };
    const boom: LintRule = {
      id: "test/boom",
      run: async () => {
        throw new Error("rule failed");
      },
    };
    const res = unwrap(await linter.lint(userland, [broken, boom, commaSpace]));
    expect(clean(res)).toBe(false);
    expect(res.diags.filter((d) => d.code === "bend-lint/rule-crash")).toMatchObject([
      {
        severity: "error",
        message: 'test/broken-fix: fix "two" has an edit out of bounds, or two that clash',
      },
      { severity: "error", message: "test/boom: rule failed" },
    ]);
    expect(res.diags.some((d) => d.code === commaSpace.id)).toBe(true);
    const controller = new AbortController();
    const abort: LintRule = {
      id: "test/abort",
      run: async () => {
        controller.abort();
        return [];
      },
    };
    await expect(
      lint(userland, [abort, neverRun], { signal: controller.signal }),
    ).rejects.toThrow();
    await expect(lint(userland, [], { signal: controller.signal })).rejects.toThrow();
  });

  test("unsaved text is what bend and the rules see, for that run only", async () => {
    const saved = "import Base\ndef main() -> U32:\n  1\n";
    const edited = "import Base\ndef main() -> U32:\n  2\n";
    const file = fixture("unsaved.bend", saved);
    const seen: LintRule = {
      id: "test/seen",
      run: (cx) => [cx.diag({ message: cx.root.text, severity: "hint" })],
    };
    const text = async (unsaved?: Map<string, string>): Promise<string> =>
      (await lint(file, [seen], { unsaved })).diags[0].message;
    expect(await text(new Map([[file, edited]]))).toBe(edited);
    expect(await text()).toBe(saved);
    const broken = await lint(file, [seen], {
      unsaved: new Map([[file, "import Base\ndef main() -> U32:\n  nope\n"]]),
    });
    expect([clean(broken), broken.diags[0].code]).toEqual([false, "bend/check"]);
    // Runs at the same time wait for each other's check, and each sees its own text.
    const other = "import Base\ndef main() -> U32:\n  3\n";
    expect(
      await Promise.all([text(new Map([[file, edited]])), text(), text(new Map([[file, other]]))]),
    ).toEqual([edited, saved, other]);
    expect(await text()).toBe(saved);
  });

  test("spans after import lines point at the right text on disk", async () => {
    fixture("dep.bend", "type N is Data:\n  Z{}\ndef id(x: N) -> N:\n  x\n");
    const main = fixture(
      "main.bend",
      "import ./dep.bend as D\n\ndef main() -> D.N:\n  D.id(D.Z{})\n",
    );
    const look: LintRule = {
      id: "test/imports",
      facts: true,
      run: (cx) => {
        expect(cx.root.path).toEndWith("/main.bend");
        const texts = cx.facts
          .filter((v) => v.owner === "main" && v.span !== undefined)
          .map(({ span }) => {
            expect(span!.file).toBe(cx.root);
            return cx.root.text.slice(span!.beg, span!.end);
          });
        expect(texts.some((t) => t.startsWith("D.id") || t.startsWith("D.Z"))).toBe(true);
        return [];
      },
    };
    const res = await lint(main, [look]);
    expect(res.diags.map(render)).toEqual([]);
    expect(res.sources.length).toBe(2);
  });

  test("fix offsets must be integers within the source file", async () => {
    for (const [beg, end] of [
      [NaN, 0],
      [0, NaN],
      [Infinity, Infinity],
      [0.5, 1],
      [0, 0.5],
      [-1, 0],
      [2, 1],
      [0, 1000000],
    ]) {
      const rule: LintRule = {
        id: "test/bad-offset",
        run: (cx) => [
          cx.diag({
            message: "bad offset",
            fixes: [
              {
                title: "bad offset",
                applicability: "safe",
                edits: [{ span: { file: cx.root, beg, end }, text: "X" }],
              },
            ],
          }),
        ],
      };
      expect(unwrap(await linter.lint(userland, [rule])).diags[0]).toMatchObject({
        code: "bend-lint/rule-crash",
        message: expect.stringContaining("out of bounds"),
      });
    }
    expect(fs.readFileSync(userland, "utf8")).toBe(USERLAND);
  });

  test("Base is reused, its facts are left out, and it stays out of files that do not import it", async () => {
    const withBase = fixture("with_base.bend", "import Base\n\ndef main() -> Nat:\n  1n\n");
    const probe: LintRule = {
      id: "test/base",
      facts: true,
      run: (cx) => {
        expect(cx.root.path).toEndWith("/with_base.bend");
        expect(cx.sources.some((s) => s.base)).toBe(true);
        const owners = cx.facts.map((f) => f.owner);
        expect(owners.some((def) => def === "main")).toBe(true);
        expect(owners.every((def) => cx.unstable.book.tlds[def]?.b !== true)).toBe(true);
        return [];
      },
    };
    const first = await lint(withBase, [probe]);
    const second = await lint(withBase, [probe]);
    expect([clean(first), clean(second)]).toEqual([true, true]);
    expect(second.unstable.book.order).toEqual(first.unstable.book.order);
    expect(clean(await lint(fixture("without_base.bend", "def main() -> Nat:\n  1n\n"), []))).toBe(
      false,
    );
  });

  test("lints in flight keep their own rules and facts", async () => {
    const gate = Promise.withResolvers<void>();
    const entered = Promise.withResolvers<void>();
    const paused: LintRule = {
      id: "test/paused",
      run: async (cx) => {
        expect(cx.facts).toEqual([]);
        entered.resolve();
        await gate.promise;
        return [];
      },
    };
    const first = lint(userland, [paused]);
    await entered.promise;
    const second = await lint(userland, [identity]).finally(() => gate.resolve());
    expect(second.facts.length).toBeGreaterThan(0);
    expect(second.diags.map((d) => d.code)).toEqual([identity.id]);
    expect((await first).diags).toEqual([]);
  });

  test("a rule may await I/O, and later rules see earlier findings", async () => {
    const server = Bun.serve({
      port: 0,
      fetch: async (req) => new Response("advice for " + (await req.json()).type),
    });
    const remote: LintRule = {
      id: "test/api",
      facts: true,
      run: async (cx) => {
        const fact = loose(cx, cx.fact(cx.body("id")!)!);
        const type = cx.unstable.Bend.term_wnf(fact.bok, fact.ty) as { A: typeof fact.ty };
        const arg = cx.unstable.Bend.term_wnf(fact.bok, type.A) as { k?: string };
        const res = await fetch(server.url, {
          method: "POST",
          body: JSON.stringify({ type: arg.k }),
          signal: cx.signal,
        });
        return [cx.diag({ message: await res.text(), severity: "hint" })];
      },
    };
    const next: LintRule = {
      id: "test/after-api",
      run: (cx) => {
        expect(cx.prior[0].message).toBe("advice for N");
        return [];
      },
    };
    const res = await lint(userland, [remote, next]).finally(() => server.stop(true));
    expect(clean(res)).toBe(true);
  });
});

describe("options", () => {
  const userland = fixture("options_userland.bend", USERLAND);
  const messages = async (config?: object, file = userland) =>
    (await lint(file, [echo], { config })).diags.map((d) => [d.severity, d.message]);

  test("a rule gets its defaults, with the config's values", async () => {
    expect(await messages({})).toEqual([["hint", '{"tabWidth":2,"breakLines":false}']]);
    expect(await messages({ rules: { "test/echo": { tabWidth: 4 } } })).toEqual([
      ["hint", '{"tabWidth":4,"breakLines":false}'],
    ]);
  });

  test("the config turns a rule off, or sets its severity", async () => {
    expect(await messages({ rules: { "test/echo": "off" } })).toEqual([]);
    expect(
      await messages({ rules: { "test/echo": { severity: "warning", breakLines: true } } }),
    ).toEqual([["warning", '{"tabWidth":2,"breakLines":true}']]);
  });

  test("a wrong config fails loudly", async () => {
    await expect(messages({ rules: { "test/echo": { tabSize: 4 } } })).rejects.toThrow(
      /test\/echo has no option tabSize/,
    );
    await expect(messages({ rules: { "test/echo": { tabWidth: "4" } } })).rejects.toThrow(
      /tabWidth must match/,
    );
    await expect(messages({ rules: { "test/echo": { severity: "loud" } } })).rejects.toThrow(
      /severity must be one of/,
    );
    await expect(messages({ rules: { "test/echo": 4 } })).rejects.toThrow(
      /must be "off" or an object/,
    );
  });

  test("bend-lint.json is found in the file's folder or above it", async () => {
    const top = path.join(DIR, "project");
    fs.mkdirSync(path.join(top, "deep", "er"), { recursive: true });
    fs.writeFileSync(
      path.join(top, "bend-lint.json"),
      JSON.stringify({ rules: { "test/echo": { tabWidth: 8 } } }),
    );
    const file = path.join(top, "deep", "er", "file.bend");
    fs.writeFileSync(file, USERLAND);
    expect(findConfig(file)).toEqual({ rules: { "test/echo": { tabWidth: 8 } } });
    expect(await messages(undefined, file)).toEqual([
      ["hint", '{"tabWidth":8,"breakLines":false}'],
    ]);
    expect(await messages({}, file)).toEqual([["hint", '{"tabWidth":2,"breakLines":false}']]);
  });

  for (const extension of ["js", "ts"]) {
    test(`bend-lint.${extension} loads a named config export and relative imports`, async () => {
      const top = path.join(DIR, "config_" + extension);
      fs.mkdirSync(path.join(top, "nested"), { recursive: true });
      fs.writeFileSync(path.join(top, "width.ts"), "export const width: number = 8;");
      fs.writeFileSync(
        path.join(top, "bend-lint." + extension),
        'import { width } from "./width.ts"; export const config = { rules: { "test/echo": { tabWidth: width, severity: "warning" } } };',
      );
      const file = path.join(top, "nested", "file.bend");
      fs.writeFileSync(file, USERLAND);
      expect(findConfig(file)).toEqual({
        rules: { "test/echo": { tabWidth: 8, severity: "warning" } },
      });
      expect(await messages(undefined, file)).toEqual([
        ["warning", '{"tabWidth":8,"breakLines":false}'],
      ]);
      expect(await messages({}, file)).toEqual([["hint", '{"tabWidth":2,"breakLines":false}']]);
    });
  }

  test("nearest config wins; JSON precedes JS, then TS in the same directory", () => {
    const configs = [
      [
        "bend-lint.ts",
        'export const config = { rules: { "test/echo": { tabWidth: 6 } } };',
        { tabWidth: 6 },
      ],
      [
        "bend-lint.js",
        'export const config = { rules: { "test/echo": { tabWidth: 8 } } };',
        { tabWidth: 8 },
      ],
      ["bend-lint.json", '{"rules":{"test/echo":"off"}}', "off"],
    ] as const;
    for (let count = 1; count <= configs.length; count++) {
      const top = path.join(DIR, "config_precedence_" + count);
      const child = path.join(top, "child");
      fs.mkdirSync(child, { recursive: true });
      fs.writeFileSync(path.join(top, "bend-lint.json"), '{"rules":{"test/echo":{"tabWidth":4}}}');
      for (const [name, text] of configs.slice(0, count)) {
        fs.writeFileSync(path.join(child, name), text);
      }
      expect(findConfig(path.join(child, "file.bend"))).toEqual({
        rules: { "test/echo": configs[count - 1][2] },
      });
    }
  });

  test("module configs require a named object export and preserve load errors", () => {
    for (const extension of ["js", "ts"]) {
      for (const [name, text, error] of [
        ["default", "export default {};", /must export a named `config` object/],
        ["missing", "export const rules = {};", /must export a named `config` object/],
        ["null", "export const config = null;", /`config` must be an object/],
        ["array", "export const config = [];", /`config` must be an object/],
        ["function", "export const config = () => ({});", /`config` must be an object/],
        ["throws", 'throw new Error("config exploded");', /config exploded/],
      ] as const) {
        const file = fixture(`config_${name}.${extension}`, text);
        expect(() => readConfig(file)).toThrow(error);
        expect(() => readConfig(file)).toThrow(file);
      }
    }
  });

  test("a config loads rule files, relative to itself, each rule once", async () => {
    const top = path.join(DIR, "config_load");
    fs.mkdirSync(path.join(top, "rules"), { recursive: true });
    fs.writeFileSync(
      path.join(top, "rules", "echo.ts"),
      'export const rules = [{ id: "test/loaded", run: (cx) => [cx.diag({ message: "here", severity: "hint" })] }];',
    );
    fs.writeFileSync(path.join(top, "bend-lint.json"), '{"load":["./rules/echo.ts"]}');
    const file = path.join(top, "file.bend");
    fs.writeFileSync(file, USERLAND);
    expect(findConfig(file)).toEqual({ load: [path.join(top, "rules", "echo.ts")] });
    const { rules } = await import(pathToFileURL(path.join(top, "rules", "echo.ts")).href);
    for (const given of [[], rules]) {
      expect((await lint(file, given)).diags.map((d) => d.code)).toEqual(["test/loaded"]);
    }
    fs.writeFileSync(path.join(top, "bend-lint.json"), '{"load":"./rules/echo.ts"}');
    expect(() => findConfig(file)).toThrow("`load` must be a list of rule files");
  });

  test("module configs use the same rule option validation as JSON", async () => {
    const file = fixture(
      "invalid_options.ts",
      'export const config = { rules: { "test/echo": { tabWidth: "4" } } };',
    );
    await expect(messages(readConfig(file))).rejects.toThrow(/tabWidth must match/);
  });

  test("a Bend rule declares its options and reads them", async () => {
    const rule = await bendRule(fixture("options_rule.bend", OPTIONS_BEND));
    const said = async (config: object) =>
      (await lint(userland, [rule], { config })).diags.map((d) => d.message);
    const [plain] = await said({});
    expect(plain).toMatch(/^2 \S+ none$/);
    const [given] = await said({ rules: { "test/options": { width: 4, wrap: true, name: "x" } } });
    expect(given).toMatch(/^4 \S+ x$/);
    expect(given.split(" ")[1]).not.toBe(plain.split(" ")[1]);
    expect(rule.options).toEqual({
      width: { type: "integer", default: 2, minimum: 1, maximum: 80 },
      wrap: { type: "boolean", default: false },
      name: { type: "string", default: "none" },
    });
    for (const bad of [{ width: 1.5 }, { width: 81 }, { wrap: "yes" }, { other: 1 }]) {
      await expect(said({ rules: { "test/options": bad } })).rejects.toThrow(
        /must match|no option/,
      );
    }
  });
});

describe("review fixes", () => {
  test("facts come only from the linted file: none from Base, with or without seeding", async () => {
    for (const [name, head] of [
      ["base_comment.bend", "import Base # comment"],
      ["base_plain.bend", "import Base"],
    ]) {
      const file = fixture(
        name,
        head + "\n\ntype P is Data:\n  P{n: Nat}\n\ndef main() -> Nat:\n  1n\n",
      );
      const where: LintRule = {
        id: "test/where",
        facts: true,
        run: (cx) => {
          expect(cx.facts.length).toBeGreaterThan(0);
          expect(cx.facts.every((f) => f.span?.file === cx.root)).toBe(true);
          return [];
        },
      };
      expect(clean(await lint(file, [where]))).toBe(true);
    }
  });

  test("checks at the same time keep their facts apart", async () => {
    const files = ["one", "two"].map((name) =>
      fixture(
        "apart_" + name + ".bend",
        "type N is Data:\n  Z{}\n\ndef " + name + "(x: N) -> N:\n  x\n",
      ),
    );
    const where: LintRule = {
      id: "test/where",
      facts: true,
      run: (cx) => [
        cx.diag({
          message: [...new Set(cx.facts.map((f) => f.owner))].join(),
          severity: "hint",
        }),
      ],
    };
    const got = await Promise.all(
      [...files, ...files].map(async (file) => (await lint(file, [where])).diags[0].message),
    );
    expect(got).toEqual(["N,one", "N,two", "N,one", "N,two"]);
  });

  test("identical files map by namespace, not only by text", async () => {
    const dir = path.join(DIR, "twins");
    fs.mkdirSync(dir, { recursive: true });
    for (const f of ["a.bend", "b.bend"])
      fs.writeFileSync(path.join(dir, f), "def one() -> Type:\n  Type\n");
    fs.writeFileSync(
      path.join(dir, "m.bend"),
      "import ./a.bend as A\nimport ./b.bend as B\n\ndef main() -> Type:\n  A.one()\n",
    );
    const all: LintRule = {
      id: "test/all",
      facts: true,
      run: (cx) => cx.facts.map((f) => cx.diag({ message: "f", span: f.span })),
    };
    const res = await lint(path.join(dir, "m.bend"), [all]);
    expect(clean(res)).toBe(true);
    expect(res.diags.length).toBeGreaterThan(0);
    const a = file2("/p/a.bend", "a"),
      b = file2("/p/b.bend", "b");
    expect(
      mapper([a, b])({
        file: { str: "x\n", ns: "b", dir: "/p/", al: {} },
        beg: 0,
        end: 1,
      } as BendSpan)!.file,
    ).toBe(b);
  });

  test("walk is linear in a long list (it took 408 ms at 2,000 elements)", async () => {
    const n = 2000;
    const file = fixture(
      "long_list.bend",
      "import Base\n\ndef xs() -> List<&2, U32>:\n  [" +
        Array.from({ length: n }, (_, i) => i).join(", ") +
        "]\n",
    );
    const res = await lint(file, []);
    expect(res.diags.map(render)).toEqual([]);
    const t = performance.now();
    const count = [...walk((res.unstable.book.tlds.xs as { e: LTerm }).e)].length;
    expect(count).toBeGreaterThan(n);
    expect(performance.now() - t).toBeLessThan(100);
  });

  test("clashing fixes are skipped, not fatal; equal ones merge", () => {
    const file: Source = { path: "<fix>", text: "abcdef", root: true, base: false };
    const fix = (beg: number, end: number, text: string): Diag => ({
      code: "t/f",
      severity: "hint",
      message: "",
      fixes: [{ title: "f", applicability: "safe", edits: [{ span: { file, beg, end }, text }] }],
    });
    expect(
      applyFixes(file, [
        fix(1, 1, " "),
        fix(1, 1, " "),
        fix(3, 5, "X"),
        fix(4, 6, "Y"),
        fix(1, 1, "-"),
      ]),
    ).toEqual({ text: "a bcXf", skipped: 2, elsewhere: 0 });
  });

  test("a fix that also edits another file is skipped whole", () => {
    const file: Source = { path: "<fix>", text: "abc", root: true, base: false };
    const other: Source = { path: "<other>", text: "xyz", root: false, base: false };
    const fix = (edits: Edit[]): Diag => ({
      code: "t/f",
      severity: "hint",
      message: "",
      fixes: [{ title: "f", applicability: "safe", edits }],
    });
    expect(
      applyFixes(file, [
        fix([
          { span: { file, beg: 0, end: 1 }, text: "A" },
          { span: { file: other, beg: 0, end: 1 }, text: "X" },
        ]),
        fix([{ span: { file, beg: 2, end: 3 }, text: "C" }]),
      ]),
    ).toEqual({ text: "abC", skipped: 0, elsewhere: 1 });
  });

  test("comp.ts that already exports js_sat still loads", () => {
    const comp = fs
      .readFileSync(path.join(BEND2, "comp.ts"), "utf8")
      .replace("\nfunction js_sat(", "\nexport function js_sat(");
    const out = patch("comp.ts", comp);
    expect(out).toContain("export { RUNTIME_MAIN };");
    expect(() => new Bun.Transpiler({ loader: "ts" }).transformSync(out)).not.toThrow();
  });

  test("another checkout's bend.ts loads as its own code", () => {
    const other = path.join(DIR, "other");
    fs.cpSync(BEND2, path.join(other, "bend2"), { recursive: true });
    fs.appendFileSync(path.join(other, "bend2", "bend.ts"), "\nexport const OTHER_CHECKOUT = 1;\n");
    const script = fixture(
      "other.ts",
      "import " +
        JSON.stringify(CLI) +
        ";\nconst o = await import(" +
        JSON.stringify(path.join(other, "bend2", "bend.ts")) +
        ");\n" +
        "console.log(JSON.stringify([o.OTHER_CHECKOUT, o.BEND_LINT_PATCH ?? null]));\n",
    );
    const out = spawnSync(process.execPath, [script], { encoding: "utf8" });
    expect(JSON.parse(out.stdout.trim().split("\n").at(-1)!)).toEqual([1, null]);
  });
});

describe("rules", () => {
  test("erasure: four redundant annotations; the fix keeps every body", async () => {
    const file = fixture("erasure.bend", ERASURE);
    const res = await lint(file, [redundantAnnotation]);
    expect(res.diags.map((d) => d.def).sort()).toEqual(["alias", "dependent", "direct", "generic"]);
    const cleaned = applyFixes(root(res.sources), res.diags, ["suggested"]).text;
    expect(cleaned).toContain("f : N -> N = y => y");
    expect(cleaned).toContain("value : N = Z{}");
    const after = await lint(fixture("erasure_fixed.bend", cleaned), [redundantAnnotation]);
    expect(after.diags).toEqual([]);
    expect(bodies(after.unstable.book)).toEqual(bodies(res.unstable.book));
    for (const [annotation, binding] of [
      ["f : N -> N =", "f ="],
      ["value : N =", "value ="],
    ]) {
      const broken = await lint(
        fixture("erasure_broken.bend", cleaned.replace(annotation, binding)),
        [],
      );
      expect(broken.diags.map((d) => d.code)).toEqual(["bend/check"]);
    }
    expect(fs.readFileSync(file, "utf8")).toBe(ERASURE);
  });
});

describe("drift: bend-lint agrees with bend's own tests", () => {
  for (const name of BEND_TESTS) {
    const file = path.join(BEND2, "..", "tests", name + ".bend");
    test.skipIf(!fs.existsSync(file))(name, async () => {
      const first = fs
        .readFileSync(file, "utf8")
        .match(/^#\|(.*)$/m)![1]
        .trim();
      expect(clean(await lint(file, []))).toBe(first !== "SOME PROOFS FAIL");
    });
  }
});

describe("rules written in Bend", () => {
  const userland = fixture("bend_userland.bend", USERLAND);

  test("a source rule finds the comma, with a fix on the file on disk", async () => {
    const rule = await bendRule(fixture("comma_rule.bend", COMMA_BEND));
    expect([rule.id, rule.facts]).toEqual(["style/comma-space", undefined]);
    const res = await lint(userland, [rule]);
    expect(res.diags.map((d) => [d.code, d.severity])).toEqual([["style/comma-space", "warning"]]);
    expect(render(res.diags[0])).toContain("generic(~N, a)");
    expect(applyFixes(root(res.sources), res.diags).text).toContain("generic(~N, a)");
  });

  test("a typed rule asks the checker through effects", async () => {
    const rule = await bendRule(fixture("types_rule.bend", TYPES_BEND));
    expect(rule.facts).toEqual({
      scope: "file",
      kinds: ["Var"],
      defs: ["id"],
      names: [],
      instances: false,
    });
    const res = await lint(userland, [rule, rule]);
    expect(res.diags.map((d) => d.message)).toEqual(
      Array(2).fill("x: Alias = N (same as its binder), text x, demanded once, uses x once"),
    );
    expect(res.diags.every((d) => d.span?.file === root(res.sources))).toBe(true);
  });

  test("a rule reads the term view through effects", async () => {
    const rule = await bendRule(fixture("tree_rule.bend", TREE_BEND));
    const res = await lint(userland, [rule]);
    expect(res.diags.map((d) => d.message)).toEqual(["Ann > Lam^; Ann > Var^ found; no body"]);
  });

  test("Bend fixes reject out-of-bounds code-point offsets instead of clamping them", async () => {
    for (const source of [USERLAND, "# 😀\n" + USERLAND]) {
      const end = [...source].length + 1;
      const code = COMMA_BEND.replace(
        "Lint.Span{path, at, at}",
        "Lint.Span{path, at, " + end + "}",
      );
      const rule = await bendRule(fixture("bad_offset_rule.bend", code));
      const file = fixture("bad_offset_input.bend", source);
      expect(unwrap(await linter.lint(file, [rule])).diags[0]).toMatchObject({
        code: "bend-lint/rule-crash",
        message: expect.stringContaining('fix "Insert space" has an edit out of bounds'),
      });
      expect(fs.readFileSync(file, "utf8")).toBe(source);
      const diagnosticOnly = code.replace(
        '[Lint.Fix{"Insert space", Lint.Safe{}, [Lint.Edit{span, " "}]}]',
        "[]",
      );
      const diagnosticRule = await bendRule(
        fixture("clamped_diagnostic_rule.bend", diagnosticOnly),
      );
      const result = await lint(file, [diagnosticRule]);
      expect(clean(result)).toBe(true);
      expect(result.diags[0].span!.end).toBe(source.length);
    }
  });
});

describe("entry points return a Result", () => {
  const userland = fixture("entry_userland.bend", USERLAND);
  const failure = async (res: Promise<Result<unknown, api.LintError>>) => {
    const got = await res;
    return ERROR in got ? got[ERROR] : undefined;
  };

  test("each failure says its cause", async () => {
    expect(await createLinter({ bend: path.join(DIR, "nowhere") })).toMatchObject({
      [ERROR]: { type: "bend-missing" },
    });
    expect(await createLinter()).toEqual(await createLinter());
    expect(api.readConfig(path.join(DIR, "no-config.json"))).toMatchObject({
      [ERROR]: { type: "config" },
    });
    const config = (rules: object) => ({ config: { rules } as api.Config });
    expect(
      await failure(linter.lint(userland, [echo], config({ "test/echo": { nope: 1 } }))),
    ).toMatchObject({
      type: "config",
    });
    expect(await failure(linter.lint(userland, [{ id: "bad", run: () => [] }]))).toMatchObject({
      type: "rule-module",
    });
    expect(
      await failure(
        linter.lint(userland, [], { config: { load: [path.join(DIR, "missing.ts")] } }),
      ),
    ).toMatchObject({ type: "rule-module" });
    expect(await linter.bendRule(fixture("not_a_rule.bend", "def broken(\n"))).toMatchObject({
      [ERROR]: { type: "rule-module" },
    });
    const controller = new AbortController();
    controller.abort();
    expect(await failure(linter.lint(userland, [], { signal: controller.signal }))).toMatchObject({
      type: "aborted",
    });
  });

  test("a run gives the linted file as root", async () => {
    const res = await lint(userland, []);
    expect(res.root).toBe(res.sources.find((s) => s.root));
    expect(res.root?.path).toEndWith("/entry_userland.bend");
  });
});

describe("fact filters", () => {
  const userland = fixture("filter_userland.bend", USERLAND);

  test("kinds, defs and names narrow the facts; an empty or absent list matches all", async () => {
    const all = await seen(userland, { instances: true });
    const only = async (want: FactFilter, keep: (f: Seen) => boolean) => {
      const got = await seen(userland, { ...want, instances: true });
      expect(got.length).toBeGreaterThan(0);
      expect(got).toEqual(all.filter(keep));
    };
    await only({ kinds: ["Var"] }, (f) => f.kind === "Var");
    await only({ defs: ["generic"] }, (f) => f.def === "generic" || f.def.startsWith("generic~"));
    await only({ kinds: ["Ref"], names: ["id"] }, (f) => f.kind === "Ref" && f.name === "id");
    await only({ kinds: [], defs: [], names: [] }, () => true);
    expect(all.some((f) => f.def.startsWith("generic~"))).toBe(true);
  });

  test("template instances' facts come only with instances: true", async () => {
    const all = await seen(userland, { instances: true });
    expect(await seen(userland, true)).toEqual(all.filter((f) => !f.def.includes("~")));
    const both = await lint(userland, [
      {
        id: "test/plain",
        facts: true,
        run: (cx) => (expect(cx.facts.every((f) => !f.inst)).toBe(true), []),
      },
      {
        id: "test/inst",
        facts: { instances: true },
        run: (cx) => (expect(cx.facts.some((f) => f.inst)).toBe(true), []),
      },
    ]);
    expect(clean(both)).toBe(true);
  });

  test("each rule gets its own facts; bend-lint keeps only what some rule asked for", async () => {
    const got: Record<string, string[]> = {};
    const rule = (id: string, kinds: string[]): LintRule => ({
      id,
      facts: { kinds },
      run: (cx) => ((got[id] = cx.facts.map((f) => cx.shape(cx.strip(f.node)).kind)), []),
    });
    const res = await lint(userland, [rule("test/vars", ["Var"]), rule("test/refs", ["Ref"])]);
    expect(new Set(got["test/vars"])).toEqual(new Set(["Var"]));
    expect(new Set(got["test/refs"])).toEqual(new Set(["Ref"]));
    expect(res.facts.length).toBe(got["test/vars"].length + got["test/refs"].length);
    expect(res.facts.length).toBeLessThan(
      (await lint(userland, [rule("test/all", [])])).facts.length,
    );
  });

  test("scope program adds the imports' facts, never Base's", async () => {
    const dir = path.join(DIR, "program");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "dep.bend"), "import Base\n\ndef one(x: Nat) -> Nat:\n  x\n");
    for (const head of ["import Base", "import Base # comment"]) {
      const main = path.join(dir, "main.bend");
      fs.writeFileSync(
        main,
        head + "\nimport ./dep.bend as D\n\ndef main() -> Nat:\n  D.one(1n)\n",
      );
      const where = async (scope: "file" | "program") =>
        new Set((await seen(main, { scope })).map((f) => path.basename(f.path)));
      expect(await where("file")).toEqual(new Set(["main.bend"]));
      expect(await where("program")).toEqual(new Set(["main.bend", "dep.bend"]));
    }
  });

  test("a bad filter is an invalid rule", async () => {
    for (const facts of [
      { scope: "all" },
      { kinds: "Var" },
      { names: [1] },
      { instances: "yes" },
      3,
    ]) {
      await expect(
        lint(userland, [{ id: "test/bad", facts, run: () => [] } as unknown as LintRule]),
      ).rejects.toThrow(/invalid rule at 0/);
    }
  });

  test("a Bend rule pulls its facts one at a time, any number of them", async () => {
    const rule = await bendRule(fixture("count_rule.bend", COUNT_BEND));
    expect(rule.facts).toEqual({
      scope: "program",
      kinds: ["Var"],
      defs: [],
      names: [],
      instances: false,
    });
    const many = fixture(
      "many_vars.bend",
      "import Base\n\n" +
        Array.from({ length: 5000 }, (_, i) => "def f" + i + "(x: U32) -> U32:\n  x\n").join("\n"),
    );
    expect((await lint(many, [rule])).diags.map((d) => d.message)).toEqual(["5000"]);
  });
});

describe("cli", () => {
  const input = fixture("cli.bend", USERLAND);
  const first = module(
    "first.js",
    `[{ id: "cli/first", facts: true, run(cx) {
    if (!cx.facts?.length || !cx.sources.length) throw new Error("missing metadata");
    return [cx.diag({ message: "First rule", severity: "warning" })];
  } }]`,
  );
  const second = module(
    "second.ts",
    `[{ id: "cli/second", run(cx) {
    if (cx.prior[0]?.code !== "cli/first") throw new Error("wrong rule order");
    return [cx.diag({ message: "Second rule", severity: "hint" })];
  } }]`,
  );

  test("rules run in order and print bend's layout", () => {
    const out = run(input, "--rules", first, "--rules", second);
    expect(out.status).toBe(0);
    expect(out.stdout).toMatch(/Warning \[cli\/first\]:[\s\S]*Hint \[cli\/second\]:/);
  });

  test("an error finding, or a failed check, exits 1", () => {
    const blocking = module(
      "error.js",
      `[{ id: "cli/error", run: (cx) => [cx.diag({ message: "Blocked", severity: "error" })] }]`,
    );
    expect(run(input, "--rules", blocking)).toMatchObject({
      status: 1,
      stdout: expect.stringContaining("Error [cli/error]:"),
    });
    expect(run(fixture("cli_bad.bend", "def broken(\n"))).toMatchObject({
      status: 1,
      stdout: expect.stringContaining("Error [bend/check]:"),
    });
  });

  test("bad usage and bad modules exit 2", () => {
    expect(run().status).toBe(2);
    expect(run(input, "--rules").status).toBe(2);
    expect(run(input, "--nope").status).toBe(2);
    expect(run(input, "--rules", path.join(DIR, "missing.js")).status).toBe(2);
    expect(run(input, "--rules", module("object.js", "{}")).stderr).toMatch(/must export `rules`/);
    expect(
      run(input, "--rules", module("bad.js", `[{ id: "bad", run() { return []; } }]`)).stderr,
    ).toMatch(/invalid rule/);
    expect(
      run(
        input,
        "--rules",
        fixture("no_id.bend", 'import Base\n\ndef main() -> IO(Unit):\n  IO.print("x")\n'),
      ).stderr,
    ).toMatch(/must define id\(\) -> String/);
    expect(run(input, "--rules", fixture("broken_rule.bend", "def broken(\n")).stderr).toMatch(
      /does not check/,
    );
    expect(
      run(
        input,
        "--rules",
        fixture(
          "no_facts.bend",
          COMMA_BEND.replace("def facts() -> Lint.Want:\n  Lint.NoFacts{}\n", ""),
        ),
      ).stderr,
    ).toMatch(/must define id\(\) -> String, facts\(\) -> Lint.Want/);
  });

  test("a rule written in Bend runs from the CLI", () => {
    const out = run(input, "--rules", fixture("cli_comma_rule.bend", COMMA_BEND));
    expect(out.status).toBe(0);
    expect(out.stdout).toContain("Warning [style/comma-space]:");
  });

  test("--json prints findings with LSP ranges, and nothing else", () => {
    const comma = module(
      "json_comma.js",
      `[{ id: "style/comma-space", run: (cx) =>
      [...cx.root.text.matchAll(/,(?=\\w)/g)].map((m) => {
        const span = { file: cx.root, beg: m.index + 1, end: m.index + 1 };
        return cx.diag({ message: "space", severity: "hint", span,
          fixes: [{ title: "Insert space", applicability: "safe", edits: [{ span, text: " " }] }] });
      }) }]`,
    );
    const out = run(input, "--rules", comma, "--json");
    expect(out.status).toBe(0);
    const json = JSON.parse(out.stdout);
    const at = { line: 25, character: 13 };
    expect(json).toEqual({
      ok: true,
      findings: [
        {
          code: "style/comma-space",
          severity: "hint",
          message: "space",
          path: fs.realpathSync(input).replaceAll("\\", "/"),
          range: { start: at, end: at },
          fixes: [
            {
              title: "Insert space",
              applicability: "safe",
              edits: [
                {
                  path: fs.realpathSync(input).replaceAll("\\", "/"),
                  range: { start: at, end: at },
                  text: " ",
                },
              ],
            },
          ],
        },
      ],
    });
    expect(USERLAND.split("\n")[at.line].slice(0, at.character)).toBe("  generic(~N,");
    const bad = JSON.parse(run(fixture("json_bad.bend", "def broken(\n"), "--json").stdout);
    expect([bad.ok, bad.findings[0].code]).toEqual([false, "bend/check"]);
  });

  test("--bend and BEND_DIR choose the bend to load; a wrong one exits 2", () => {
    expect(run(input, "--bend", path.dirname(BEND2)).status).toBe(0);
    const env = spawnSync(process.execPath, [CLI, input], {
      encoding: "utf8",
      env: { ...process.env, BEND_DIR: BEND2 },
    });
    expect(env.status).toBe(0);
    expect(run(input, "--bend", DIR)).toMatchObject({
      status: 2,
      stderr: expect.stringContaining("no bend2 at"),
    });
  });

  test("--config selects JSON, JS or TS explicitly", () => {
    const echoes = module(
      "echo.js",
      `[{ id: "test/echo", options: { tabWidth: { type: "integer", default: 2 } }, run: (cx) => [cx.diag({ message: "w" + cx.options.tabWidth })] }]`,
    );
    const settings = JSON.stringify({ rules: { "test/echo": { tabWidth: 6, severity: "hint" } } });
    for (const extension of ["json", "js", "ts"]) {
      const config = fixture(
        "cli_config." + extension,
        extension === "json" ? settings : "export const config = " + settings + ";",
      );
      const out = run(input, "--rules", echoes, "--config", config, "--json");
      expect(out.status).toBe(0);
      expect(
        JSON.parse(out.stdout).findings.map((f: { severity: string; message: string }) => [
          f.severity,
          f.message,
        ]),
      ).toEqual([["hint", "w6"]]);
    }
    const invalid = fixture("cli_default_config.ts", "export default {};");
    expect(run(input, "--config", invalid)).toMatchObject({
      status: 2,
      stderr: expect.stringContaining("must export a named `config` object"),
    });
  });

  test("--fix writes only the linted file, and prints findings when fixes clash", () => {
    const dir = path.join(DIR, "fixroot");
    fs.mkdirSync(dir, { recursive: true });
    const dep = path.join(dir, "dep.bend");
    fs.writeFileSync(dep, "def one() -> Type:\n  Type\n");
    const main = path.join(dir, "main.bend");
    fs.writeFileSync(main, "import ./dep.bend as D\n\ndef main() -> Type:\n  D.one()\n");
    const everywhere = module(
      "everywhere.js",
      `[{ id: "test/everywhere", run: (cx) => cx.sources.filter((s) => !s.base).flatMap((s) => [0, 0, 1].map((n) => {
      const span = { file: s, beg: n, end: n };
      return cx.diag({ message: "x", span, fixes: [{ title: "x", applicability: "safe", edits: [{ span, text: n === 0 ? "#" : "!" }] }] });
    })) }]`,
    );
    const out = run(main, "--rules", everywhere, "--fix");
    expect(out.status).toBe(0);
    expect(out.stdout).toContain("Warning [test/everywhere]:");
    expect(fs.readFileSync(dep, "utf8")).toBe("def one() -> Type:\n  Type\n");
    expect(fs.readFileSync(main, "utf8").startsWith("#i!mport")).toBe(true);
    expect(out.stderr).not.toContain("skipped");
  });

  test("--fix applies fixes even when a finding is an error", () => {
    const target = fixture("fix_error.bend", "#abc\n");
    const strict = module(
      "strict.js",
      `[{ id: "test/strict", run: (cx) => {
      const span = { file: cx.root, beg: 0, end: 0 };
      return [cx.diag({ message: "e", severity: "error", span, fixes: [{ title: "e", applicability: "safe", edits: [{ span, text: "!" }] }] })];
    } }]`,
    );
    const out = run(target, "--rules", strict, "--fix");
    expect(out.status).toBe(1);
    expect(out.stdout).toContain("bend-lint: FAIL");
    expect(fs.readFileSync(target, "utf8")).toBe("!#abc\n");
  });

  test("--fix-suggested and --fix-dangerously apply wider levels", () => {
    const levels = module(
      "levels.js",
      `[{ id: "test/levels", run: (cx) => ["safe", "suggested", "dangerous"].map((applicability, n) => {
      const span = { file: cx.root, beg: n, end: n };
      return cx.diag({ message: applicability, span, fixes: [{ title: applicability, applicability, edits: [{ span, text: String(n) }] }] });
    }) }]`,
    );
    const fixed = (flag: string) => {
      const target = fixture("levels" + flag + ".bend", "#abc\n");
      expect(run(target, "--rules", levels, flag).status).toBe(0);
      return fs.readFileSync(target, "utf8");
    };
    expect(["--fix", "--fix-suggested", "--fix-dangerously"].map(fixed)).toEqual([
      "0#abc\n",
      "0#1abc\n",
      "0#1a2bc\n",
    ]);
  });

  test("--fix applies safe fixes", () => {
    const target = fixture("fix.bend", USERLAND);
    const comma = module(
      "comma.js",
      `[{ id: "style/comma-space", run: (cx) =>
      [...cx.root.text.matchAll(/,(?=\\w)/g)].map((m) => {
        const span = { file: cx.root, beg: m.index + 1, end: m.index + 1 };
        return cx.diag({ message: "space", severity: "hint", span,
          fixes: [{ title: "Insert space", applicability: "safe", edits: [{ span, text: " " }] }] });
      }) }]`,
    );
    expect(run(target, "--rules", comma, "--fix").status).toBe(0);
    expect(fs.readFileSync(target, "utf8")).toContain("generic(~N, a)");
  });
});
