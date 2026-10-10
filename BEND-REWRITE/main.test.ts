// Imports
// =======

import { afterAll, describe, expect, setDefaultTimeout, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { lintIn, lintRun, lintText } from "./testing.ts";
import type { Found } from "./testing.ts";

// Constants
// =========

const dir = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), "bend-rewrite-main-")));

const LINT = path.posix.relative(
  dir.replaceAll("\\", "/"),
  fileURLToPath(new URL("./main.bend", import.meta.url)).replaceAll("\\", "/"),
);

const UNUSED = fileURLToPath(new URL("./rules/no-unused/imports.bend", import.meta.url));

// A rule of `scope`, needing declarations, whose run reports `body`, a list
// of findings that can use `path` (its file) and `n` (how many files it saw).
const rule = (id: string, scope: string, body: string): string =>
  [
    "import Base",
    `import ${LINT} as Lint`,
    "",
    "def at(path: String, message: String) -> Lint.Finding:",
    "  Lint.Finding{Lint.Hint{}, message, Lint.BendSourceSpan{path, 0, 0}, []}",
    "",
    "def each(sources: List<&2, Lint.SourceDeclarations>, +message: String) -> List<&2, Lint.Finding>:",
    "  match sources:",
    "    case Nil{}:",
    "      []",
    "    case Con{Lint.SourceDeclarations{path, declarations}, t}:",
    "      at(path, message) <> each(t, message)",
    "",
    "def each_at(sources: List<&2, Lint.SourceDeclarations>, +at: U32) -> List<&2, Lint.Finding>:",
    "  match sources:",
    "    case Nil{}:",
    "      []",
    "    case Con{Lint.SourceDeclarations{path, declarations}, t}:",
    '      Lint.Finding{Lint.Hint{}, "here", Lint.BendSourceSpan{path, at, at}, []} <> each_at(t, at)',
    "",
    "def others(sources: List<&2, Lint.BendSource>, +root: String) -> List<&2, Lint.Finding>:",
    "  match sources:",
    "    case Nil{}:",
    "      []",
    "    case Con{Lint.BendSource{+path, text, lines}, t}:",
    '      Lint.get_kept(Lint.Finding, Bool.not(String.eq(path, root)), at(path, "here"), others(t, root))',
    "",
    "def lint(input: Lint.RuleInput) -> List<&2, Lint.Finding>:",
    "  match input:",
    "    case Lint.RuleInput{Lint.BendSource{+path, text, lines}, sources, options, prior, +declarations, instances}:",
    "      +n = Nat.show(List.length(&2, Lint.SourceDeclarations, declarations))",
    "      +c = U32.from_nat(List.length(&2, Lint.SourceDeclarations, declarations))",
    `      ${body}`,
    "",
    "def run(input: Lint.RuleInput) -> Lint.RuleStep:",
    "  Lint.RuleDone{lint(input)}",
    "",
    "def rules() -> List<&1, Lint.Rule>:",
    `  [Lint.Rule{"${id}", Lint.${scope}{}, [], [], [Lint.DeclarationsNeed{}], run}]`,
    "",
  ].join("\n");

// A file rule with the option `width`, a number from 1 to 10 (2 by default),
// that reports its value at the start of its file.
const WIDTH = [
  "import Base",
  `import ${LINT} as Lint`,
  "",
  "def width(options: List<&2, Lint.OptionGiven>) -> String:",
  "  match options:",
  "    case Con{Lint.OptionGiven{k, Lint.NumberValue{n}}, t}:",
  "      U32.show(n)",
  "    case _:",
  '      "none"',
  "",
  "def lint(input: Lint.RuleInput) -> List<&2, Lint.Finding>:",
  "  match input:",
  "    case Lint.RuleInput{Lint.BendSource{path, text, lines}, sources, options, prior, declarations, instances}:",
  "      [Lint.Finding{Lint.Hint{}, width(options), Lint.BendSourceSpan{path, 0, 0}, []}]",
  "",
  "def run(input: Lint.RuleInput) -> Lint.RuleStep:",
  "  Lint.RuleDone{lint(input)}",
  "",
  "def rules() -> List<&1, Lint.Rule>:",
  '  [Lint.Rule{"test/width", Lint.FileScope{}, [Lint.OptionDeclared{"width", Lint.NumberValue{2}, Lint.NumberSpec{1, 10}}], [], [], run}]',
  "",
].join("\n");

// A rule `id` that needs `need`; `run`, after `helpers`, gives its step from
// `seen`: each variable the checker checked in its file, with its quantity,
// span, type and binder's type.
const varsRule = (id: string, need: string, helpers: string[], run: string): string =>
  [
    "import Base",
    `import ${LINT} as Lint`,
    "",
    "def quantity(q: Lint.Quantity) -> String:",
    "  match q:",
    "    case Lint.ErasedQuantity{}:",
    '      "erased"',
    "    case Lint.OnceQuantity{}:",
    '      "once"',
    "    case Lint.ManyQuantity{}:",
    '      "many"',
    "",
    "type Seen is Data:",
    "  Seen{",
    "    name: String,",
    "    quantity: String,",
    "    span: Lint.BendSourceSpan,",
    "    checked: Lint.BendType,",
    "    binder: Maybe<&2, Lint.BendType>",
    "  }",
    "",
    "def found(t: Lint.BendTerm, done: List<&2, Seen>) -> List<&2, Seen>:",
    "  match t:",
    "    case Lint.CheckedTerm{Lint.VariableTerm{name, Some{span}}, Lint.TermFact{checked, q, uses, binder}}:",
    "      Seen{name, quantity(q), span, checked, binder} <> done",
    "    case Lint.CheckedTerm{term, fact}:",
    "      found(term, done)",
    "    case Lint.LambdaTerm{name, body, span}:",
    "      found(body, done)",
    "    case Lint.CallTerm{head, arguments, span}:",
    "      found(arguments, found(head, done))",
    "    case Lint.SomeTerms{first, rest}:",
    "      found(rest, found(first, done))",
    "    case Lint.AnnotatedTerm{value, annotation, span}:",
    "      found(value, done)",
    "    case _:",
    "      done",
    "",
    "def each(ds: List<&2, Lint.Declaration>) -> List<&2, Seen>:",
    "  match ds:",
    "    case Nil{}:",
    "      []",
    "    case Con{Lint.Declaration{name, span, references, Lint.DefDeclaration{fills, written, Some{body}}}, t}:",
    "      List.append(&2, Seen, List.reverse(&2, Seen, found(body, [])), each(t))",
    "    case Con{d, t}:",
    "      each(t)",
    "",
    "def all(sources: List<&2, Lint.SourceDeclarations>) -> List<&2, Seen>:",
    "  match sources:",
    "    case Nil{}:",
    "      []",
    "    case Con{Lint.SourceDeclarations{path, ds}, t}:",
    "      List.append(&2, Seen, each(ds), all(t))",
    "",
    ...helpers,
    "def run(input: Lint.RuleInput) -> Lint.RuleStep:",
    "  match input:",
    "    case Lint.RuleInput{root, sources, options, prior, declarations, instances}:",
    "      +seen = all(declarations)",
    `      ${run}`,
    "",
    "def rules() -> List<&1, Lint.Rule>:",
    `  [Lint.Rule{"${id}", Lint.FileScope{}, [], [], [Lint.${need}{}], run}]`,
    "",
  ].join("\n");

// A rule that needs `need`, and reports each variable the checker checked
// in its file: its name, type and quantity.
const typesRule = (need: string): string =>
  varsRule(
    "test/types",
    need,
    [
      "def asked(seen: List<&2, Seen>) -> List<&2, Lint.TypeQuestion>:",
      "  match seen:",
      "    case Nil{}:",
      "      []",
      "    case Con{Seen{name, quantity, span, checked, binder}, t}:",
      "      Lint.ShowType{checked} <> asked(t)",
      "",
      "def shown(seen: List<&2, Seen>, answers: List<&2, Lint.TypeAnswer>) -> List<&2, Lint.Finding>:",
      "  match seen answers:",
      "    case Con{Seen{name, quantity, span, checked, binder}, t} Con{Lint.ShownAnswer{text}, u}:",
      '      Lint.Finding{Lint.Hint{}, name ++ ": " ++ text ++ ", " ++ quantity, span, []} <> shown(t, u)',
      "    case _ _:",
      "      []",
      "",
    ],
    "Lint.RuleAsk{asked(seen), answers => Lint.RuleDone{shown(seen, answers)}}",
  );

// A rule of `scope` that needs instances and facts, and reports, for each
// template instance, its template and each variable in it with its type.
const instancesRule = (id: string, scope: string): string =>
  [
    "import Base",
    `import ${LINT} as Lint`,
    "",
    "def vars(t: Lint.BendTerm, done: List<&2, Lint.BendType>) -> List<&2, Lint.BendType>:",
    "  match t:",
    "    case Lint.CheckedTerm{Lint.VariableTerm{name, span}, Lint.TermFact{checked, q, uses, binder}}:",
    "      checked <> done",
    "    case Lint.CheckedTerm{term, fact}:",
    "      vars(term, done)",
    "    case Lint.LambdaTerm{name, body, span}:",
    "      vars(body, done)",
    "    case Lint.AnnotatedTerm{value, annotation, span}:",
    "      vars(value, done)",
    "    case _:",
    "      done",
    "",
    "def show_all(ts: List<&2, Lint.BendType>) -> List<&2, Lint.TypeQuestion>:",
    "  match ts:",
    "    case Nil{}:",
    "      []",
    "    case Con{h, t}:",
    "      Lint.ShowType{h} <> show_all(t)",
    "",
    "def asked(xs: List<&2, Lint.TemplateInstance>) -> List<&2, Lint.TypeQuestion>:",
    "  match xs:",
    "    case Nil{}:",
    "      []",
    "    case Con{Lint.TemplateInstance{path, template, body}, t}:",
    "      List.append(&2, Lint.TypeQuestion, show_all(vars(body, [])), asked(t))",
    "",
    "def shown(answers: List<&2, Lint.TypeAnswer>) -> String:",
    "  match answers:",
    "    case Con{Lint.ShownAnswer{text}, t}:",
    '      " " ++ text ++ shown(t)',
    "    case _:",
    '      ""',
    "",
    "def found(xs: List<&2, Lint.TemplateInstance>, +answers: List<&2, Lint.TypeAnswer>) -> List<&2, Lint.Finding>:",
    "  match xs:",
    "    case Nil{}:",
    "      []",
    "    case Con{Lint.TemplateInstance{+path, template, body}, t}:",
    '      [Lint.Finding{Lint.Hint{}, template ++ ":" ++ shown(answers), Lint.BendSourceSpan{path, 0, 0}, []}]',
    "",
    "def run(input: Lint.RuleInput) -> Lint.RuleStep:",
    "  match input:",
    "    case Lint.RuleInput{root, sources, options, prior, declarations, +instances}:",
    "      Lint.RuleAsk{asked(instances), answers => Lint.RuleDone{found(instances, answers)}}",
    "",
    "def rules() -> List<&1, Lint.Rule>:",
    `  [Lint.Rule{"${id}", Lint.${scope}{}, [], [], [Lint.FactsNeed{}, Lint.InstancesNeed{}], run}]`,
    "",
  ].join("\n");

// A rule that reports, at the first variable the checker checked, whether
// its type is the same as its binder's, then its type, its binder's and the
// binder's normal form, as shown: it asks twice.
const SAME = varsRule(
  "test/same",
  "FactsNeed",
  [
    "def said(same: Bool) -> String:",
    "  match same:",
    "    case True{}:",
    '      "same"',
    "    case False{}:",
    '      "not same"',
    "",
    "def shown(answers: List<&2, Lint.TypeAnswer>, span: Lint.BendSourceSpan, same: Bool) -> List<&2, Lint.Finding>:",
    "  match answers:",
    "    case Con{Lint.ShownAnswer{a}, Con{Lint.ShownAnswer{b}, Con{Lint.ShownAnswer{c}, rest}}}:",
    '      [Lint.Finding{Lint.Hint{}, said(same) ++ ": " ++ a ++ ", " ++ b ++ ", " ++ c, span, []}]',
    "    case _:",
    "      []",
    "",
    "def second(",
    "  answers: List<&2, Lint.TypeAnswer>,",
    "  span: Lint.BendSourceSpan,",
    "  checked: Lint.BendType,",
    "  binder: Lint.BendType",
    ") -> Lint.RuleStep:",
    "  match answers:",
    "    case Con{Lint.SameAnswer{same}, Con{Lint.NormalAnswer{normal}, rest}}:",
    "      Lint.RuleAsk{",
    "        [Lint.ShowType{checked}, Lint.ShowType{binder}, Lint.ShowType{normal}],",
    "        shown_answers => Lint.RuleDone{shown(shown_answers, span, same)}",
    "      }",
    "    case _:",
    "      Lint.RuleDone{[]}",
    "",
    "def first(seen: List<&2, Seen>) -> Lint.RuleStep:",
    "  match seen:",
    "    case Con{Seen{name, quantity, span, +checked, Some{+binder}}, t}:",
    "      Lint.RuleAsk{",
    "        [Lint.SameTypes{checked, binder}, Lint.NormalType{binder}],",
    "        answers => second(answers, span, checked, binder)",
    "      }",
    "    case _:",
    "      Lint.RuleDone{[]}",
    "",
  ],
  "first(seen)",
);

const RULES = {
  // Reports, at the start of its file, how many files it saw.
  "seen.bend": rule("test/seen", "FileScope", "[at(path, n)]"),
  // Reports in each file it saw, with how many it saw.
  "everywhere.bend": rule("test/everywhere", "ProgramSomeScope", "each(declarations, n)"),
  // A file rule that reports in every other file the check read.
  "elsewhere.bend": rule("test/elsewhere", "FileScope", "others(sources, path)"),
  "types.bend": typesRule("FactsNeed"),
  "untyped.bend": typesRule("BodiesNeed"),
  "same.bend": SAME,
  "instances.bend": instancesRule("test/instances", "ProgramSomeScope"),
  "file-instances.bend": instancesRule("test/file-instances", "FileScope"),
  // A program rule that reports in each file it saw, at as many characters as
  // it saw files: checks of different programs disagree on where.
  "some.bend": rule("test/some", "ProgramSomeScope", "each_at(declarations, c)"),
  "every.bend": rule("test/every", "ProgramEveryScope", "each_at(declarations, c)"),
  "width.bend": WIDTH,
  // A warning at the start of each line that holds `zap`.
  "mark.bend": [
    "import Base",
    `import ${LINT} as Lint`,
    "",
    "def marked(lines: List<&2, String>, +at: U32, +path: String) -> List<&2, Lint.Finding>:",
    "  match lines:",
    "    case Nil{}:",
    "      []",
    "    case Con{+h, t}:",
    "      Lint.get_kept(",
    "        Lint.Finding,",
    '        String.contains(h, "zap"),',
    '        Lint.Finding{Lint.Warning{}, "zap", Lint.BendSourceSpan{path, at, at}, []},',
    "        marked(t, U32.add(U32.add(at, U32.from_nat(String.length(h))), 1), path)",
    "      )",
    "",
    "def lint(input: Lint.RuleInput) -> List<&2, Lint.Finding>:",
    "  match input:",
    "    case Lint.RuleInput{Lint.BendSource{+path, text, lines}, sources, options, prior, declarations, instances}:",
    "      marked(lines, 0, path)",
    "",
    "def run(input: Lint.RuleInput) -> Lint.RuleStep:",
    "  Lint.RuleDone{lint(input)}",
    "",
    "def rules() -> List<&1, Lint.Rule>:",
    '  [Lint.Rule{"test/mark", Lint.FileScope{}, [], [], [], run}]',
    "",
  ].join("\n"),
};

// main.bend imports util.bend, which imports other.bend and does not use it.
const PROGRAM = {
  "main.bend": "import Base\nimport ./util.bend as U\n\ndef main() -> U32:\n  U.k()\n",
  "util.bend": "import Base\nimport ./other.bend as O\n\ndef k() -> U32:\n  1\n",
  "other.bend": "import Base\n\ndef z() -> U32:\n  0\n",
};

// Functions
// =========

// What the rewrite reports for main.bend with the rule files `rules`.
const found = (
  rules: string[],
  ...flags: string[]
): Array<Pick<Found, "code" | "file" | "message" | "fixes">> =>
  lintIn(dir, { ...RULES, ...PROGRAM }, "main.bend", [
    ...rules.flatMap((r) => ["--rules", path.isAbsolute(r) ? r : path.join(dir, r)]),
    ...flags,
  ]).map(({ code, file, message, fixes }) => ({ code, file, message, fixes }));

// Side effects
// ============

setDefaultTimeout(300_000);

afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));

describe("rule scope", () => {
  test("a file rule runs on the named file, and sees only it", () => {
    expect(found(["seen.bend"])).toEqual([
      { code: "test/seen", file: "main.bend", message: "1", fixes: [] },
    ]);
  });

  test("with --imports, a file rule runs on each file of the program, and sees only it", () => {
    expect(found(["seen.bend"], "--imports")).toEqual([
      { code: "test/seen", file: "main.bend", message: "1", fixes: [] },
      { code: "test/seen", file: "util.bend", message: "1", fixes: [] },
      { code: "test/seen", file: "other.bend", message: "1", fixes: [] },
    ]);
  });

  test("a program rule sees every file, and shows only what it finds in the named one", () => {
    expect(found(["everywhere.bend"])).toEqual([
      { code: "test/everywhere", file: "main.bend", message: "3", fixes: [] },
    ]);
  });

  test("with --imports, a program rule's findings show in every file", () => {
    expect(found(["everywhere.bend"], "--imports")).toEqual([
      { code: "test/everywhere", file: "main.bend", message: "3", fixes: [] },
      { code: "test/everywhere", file: "util.bend", message: "3", fixes: [] },
      { code: "test/everywhere", file: "other.bend", message: "3", fixes: [] },
    ]);
  });

  test("a file rule that reports in another file crashes, and its findings are dropped", () => {
    const out = found(["elsewhere.bend"]);
    expect(out.map((f) => [f.code, f.file])).toEqual([["bend-lint/rule-crash", "main.bend"]]);
    expect(out[0].message).toStartWith("test/elsewhere: it reported in ");
  });

  test("--no-imports undoes --imports", () => {
    expect(found(["seen.bend"], "--imports", "--no-imports").map((f) => f.file)).toEqual([
      "main.bend",
    ]);
  });
});

describe("Safe fixes", () => {
  test("with --imports, a Safe fix in an imported file is checked and offered", () => {
    expect(found([UNUSED], "--imports")).toEqual([
      {
        code: "no-unused/imports",
        file: "util.bend",
        message: "Remove the import O: nothing uses it.",
        fixes: ["Remove the import [safe]"],
      },
    ]);
  });
});

describe("facts", () => {
  const program = {
    "typed.bend":
      "import Base\n\ntype N is Data:\n  Z{}\n\ndef id(x: N) -> N:\n  x\n\ndef main() -> N:\n  id(Z{})\n",
  };
  const facts = (rule: string): Array<Pick<Found, "text" | "message">> =>
    lintIn(dir, { ...RULES, ...program }, "typed.bend", ["--rules", path.join(dir, rule)]).map(
      ({ text, message }) => ({ text, message }),
    );

  test("a rule that needs facts gets each checked term's type and quantity", () => {
    expect(facts("types.bend")).toEqual([{ text: "x", message: "x: N, once" }]);
  });

  test("a rule that needs only bodies gets them without facts", () => {
    expect(facts("untyped.bend")).toEqual([]);
  });

  test("a rule can ask, again after the answers, whether types are the same as the checker compares them, and for a normal form", () => {
    const named = {
      "named.bend":
        "import Base\n\ntype N is Data:\n  Z{}\n\ndef M() -> Type:\n  N\n\ndef id(x: M) -> N:\n  x\n\ndef main() -> N:\n  id(Z{})\n",
    };
    const found = lintIn(dir, { ...RULES, ...named }, "named.bend", [
      "--rules",
      path.join(dir, "same.bend"),
    ]).map(({ text, message }) => ({ text, message }));
    expect(found).toEqual([{ text: "x", message: "same: N, M, N" }]);
  });

  const generic = {
    "generic.bend":
      "import Base\n\ntype N is Data:\n  Z{}\n\ndef generic(~T: Type, x: T) -> T:\n  x\n\ndef main() -> N:\n  generic(~N, Z{})\n",
  };

  test("a program rule that needs instances gets each template instance, with its facts", () => {
    const found = lintIn(dir, { ...RULES, ...generic }, "generic.bend", [
      "--rules",
      path.join(dir, "instances.bend"),
    ]).map(({ message }) => message);
    expect(found).toEqual(["generic: N"]);
  });

  test("a file rule cannot need instances: they depend on who uses a template", () => {
    const { stderr } = lintText(dir, { ...RULES, ...generic }, "generic.bend", [
      "--rules",
      path.join(dir, "file-instances.bend"),
    ]);
    expect(stderr).toContain("test/file-instances needs InstancesNeed");
  });
});

describe("config", () => {
  // A file in the folder `folder`, with a bend-lint.json of `config` there.
  const configured = (folder: string, config: string, ...args: string[]) =>
    lintRun(
      dir,
      {
        ...RULES,
        [folder + "/bend-lint.json"]: config,
        [folder + "/a.bend"]: PROGRAM["other.bend"],
      },
      folder + "/a.bend",
      args,
    );
  const brief = (out: Found[]) => out.map(({ code, message }) => ({ code, message }));

  test("a config's load adds its rules", () => {
    expect(brief(configured("load", '{"load": ["../seen.bend"]}').found)).toEqual([
      { code: "test/seen", message: "1" },
    ]);
  });

  test("a config can turn a rule off", () => {
    expect(
      configured("off", '{"load": ["../seen.bend"], "rules": {"test/seen": "off"}}').found,
    ).toEqual([]);
  });

  test("a rule gets its default options, and the ones a config gives", () => {
    expect(brief(configured("defaults", '{"load": ["../width.bend"]}').found)).toEqual([
      { code: "test/width", message: "2" },
    ]);
    expect(
      brief(
        configured("width", '{"load": ["../width.bend"], "rules": {"test/width": {"width": 7}}}')
          .found,
      ),
    ).toEqual([{ code: "test/width", message: "7" }]);
  });

  test("an option the rule does not declare, or one that does not fit, is a config error", () => {
    const unknown = configured(
      "unknown",
      '{"load": ["../width.bend"], "rules": {"test/width": {"height": 1}}}',
    );
    expect([unknown.code, unknown.found]).toEqual([2, []]);
    expect(unknown.stderr).toContain("test/width: there is no option height");
    const wide = configured(
      "wide",
      '{"load": ["../width.bend"], "rules": {"test/width": {"width": 11}}}',
    );
    expect(wide.stderr).toContain("test/width: width must be a whole number from 1 to 10");
  });

  test("a config that is not JSON is an error that names it", () => {
    const out = configured("broken", '{"load": [');
    expect(out.code).toBe(2);
    expect(out.stderr).toContain("bend-lint.json");
  });

  test("--config names the config, in place of the nearest one", () => {
    const named = path.join(dir, "named.json");
    fs.writeFileSync(named, '{"rules": {"test/seen": "off"}}');
    expect(
      configured(
        "given",
        '{"load": ["../seen.bend"]}',
        "--rules",
        path.join(dir, "seen.bend"),
        "--config",
        named,
      ).found,
    ).toEqual([]);
  });

  test("a glob names every file it matches", () => {
    const out = lintRun(
      dir,
      {
        ...RULES,
        "globbed/x.bend": PROGRAM["other.bend"],
        "globbed/y.bend": PROGRAM["other.bend"],
      },
      "globbed/*.bend",
      ["--rules", path.join(dir, "seen.bend")],
    );
    expect(out.found.map((f) => f.file)).toEqual(["x.bend", "y.bend"]);
  });
});

describe("entries", () => {
  // e1 reads util and other; e2 also reads e2more. util is linted alone.
  const entries = {
    "entries/util.bend": PROGRAM["util.bend"],
    "entries/other.bend": PROGRAM["other.bend"],
    "entries/e1.bend": PROGRAM["main.bend"],
    "entries/e2.bend":
      "import Base\nimport ./util.bend as U\nimport ./e2more.bend as M\n\ndef main() -> U32:\n  U32.add(U.k(), M.z())\n",
    "entries/e2more.bend": PROGRAM["other.bend"],
  };
  const linted = (config: string, rule: string) =>
    lintRun(dir, { ...RULES, ...entries, "entries/bend-lint.json": config }, "entries/util.bend", [
      "--rules",
      path.join(dir, rule),
    ]).found.map(({ code, file, text }) => ({ code, file, at: text.length }));

  test("a program rule sees the whole program of the entry that reads the file", () => {
    expect(
      lintRun(
        dir,
        { ...RULES, ...entries, "entries/bend-lint.json": '{"entries": ["e1.bend"]}' },
        "entries/util.bend",
        ["--rules", path.join(dir, "everywhere.bend")],
      ).found.map(({ file, message }) => ({ file, message })),
    ).toEqual([{ file: "util.bend", message: "3" }]);
  });

  test("a some rule keeps what one entry's check finds; an every rule what all do", () => {
    const config = '{"entries": ["e1.bend", "e2.bend"]}';
    const some = linted(config, "some.bend");
    const every = linted(config, "every.bend");
    expect(some.map((f) => f.code)).toEqual(["test/some", "test/some"]);
    expect(every).toEqual([]);
  });

  test("when an entry that reads the file fails its check, it is shown, and no every rule runs", () => {
    const broken = {
      ...entries,
      "entries/e3.bend":
        "import Base\nimport ./util.bend as U\n\ndef main() -> U32:\n  U.nothing()\n",
    };
    const run = (rule: string) =>
      lintRun(
        dir,
        { ...RULES, ...broken, "entries/bend-lint.json": '{"entries": ["e1.bend", "e3.bend"]}' },
        "entries/util.bend",
        ["--rules", path.join(dir, rule)],
      ).found.map((f) => f.code);
    expect(run("every.bend")).toEqual(["bend/check"]);
    expect(run("some.bend")).toEqual(["bend/check", "test/some"]);
  });
});

describe("directives", () => {
  // The findings of test/mark on `body`, after `import Base`, with the suppressed ones shown.
  const marked = (body: string) => {
    const out = lintRun(dir, { ...RULES, "marked.bend": "import Base\n\n" + body }, "marked.bend", [
      "--rules",
      path.join(dir, "mark.bend"),
      "--show-suppressed",
    ]);
    const brief = (fs: Found[]) => fs.map(({ code, line, fixes }) => ({ code, text: line, fixes }));
    return { found: brief(out.found), suppressed: brief(out.suppressed), code: out.code };
  };
  const zap = (name: string): string => `def ${name}() -> U32:\n  1\n`;

  test("disable-next suppresses the finding on the next line with code", () => {
    const out = marked("# bend-lint: disable-next test/mark -- a sample\n\n" + zap("zap_a"));
    expect(out.found).toEqual([]);
    expect(out.suppressed.map((f) => f.text)).toEqual(["def zap_a() -> U32:"]);
  });

  test("disable-line suppresses the finding on its own line", () => {
    const out = marked(
      "def zap_a() -> U32: # bend-lint: disable-line test/mark -- a sample\n  1\n" + zap("zap_b"),
    );
    expect(out.found.map((f) => f.text)).toEqual(["def zap_b() -> U32:"]);
  });

  test("disable-begin and disable-end suppress the lines between them", () => {
    const out = marked(
      "# bend-lint: disable-begin test/mark -- a sample\n" +
        zap("zap_a") +
        zap("zap_b") +
        "# bend-lint: disable-end test/mark\n" +
        zap("zap_c"),
    );
    expect(out.found.map((f) => f.text)).toEqual(["def zap_c() -> U32:"]);
    expect(out.suppressed.length).toBe(2);
  });

  test("disable-file suppresses the whole file", () => {
    expect(
      marked("# bend-lint: disable-file test/mark -- a sample\n" + zap("zap_a") + zap("zap_b"))
        .found,
    ).toEqual([]);
  });

  test("a met expect is quiet; an unmet one is an error", () => {
    expect(
      marked("# bend-lint: expect-next test/mark@warning -- a sample\n" + zap("zap_a")).found,
    ).toEqual([]);
    const unmet = marked("# bend-lint: expect-next test/mark@warning -- a sample\n" + zap("quiet"));
    expect(unmet.found.map((f) => f.code)).toEqual(["bend-lint/unmet-expectation"]);
    expect(unmet.code).toBe(1);
  });

  test("an expect of another severity is unmet, and the finding stays", () => {
    expect(
      marked("# bend-lint: expect-next test/mark@hint -- a sample\n" + zap("zap_a")).found.map(
        (f) => f.code,
      ),
    ).toEqual(["test/mark", "bend-lint/unmet-expectation"]);
  });

  test("a disable that covers nothing is a warning", () => {
    expect(
      marked("# bend-lint: disable-next test/mark -- a sample\n" + zap("quiet")).found.map(
        (f) => f.code,
      ),
    ).toEqual(["bend-lint/unused-disable"]);
  });

  test("a directive without a reason, or for no rule, is an error", () => {
    expect(
      marked("# bend-lint: disable-next test/mark\n" + zap("quiet")).found.map((f) => f.code),
    ).toEqual(["bend-lint/directive"]);
    const unknown = marked("# bend-lint: disable-next no/such -- a sample\n" + zap("quiet"));
    expect(unknown.found.map((f) => f.code)).toEqual(["bend-lint/directive"]);
  });

  test("stacked directives out of order are an error, with a safe fix", () => {
    const out = marked(
      "# bend-lint: expect-next test/mark@warning -- one\n# bend-lint: disable-next test/mark -- two\n" +
        zap("zap_a"),
    );
    expect(out.found).toEqual([
      {
        code: "bend-lint/directive",
        text: "# bend-lint: expect-next test/mark@warning -- one",
        fixes: ["Sort the directives [safe]"],
      },
    ]);
  });
});

describe("fixes and output", () => {
  const FORMAT = fileURLToPath(new URL("./rules/layout/format.bend", import.meta.url));
  const unused = "import Base\nimport ./other.bend as O\n\ndef z() -> U32:\n  0\n";
  const files = (text: string) => ({
    "fixes/other.bend": PROGRAM["other.bend"],
    "fixes/a.bend": text,
  });
  const read = () => fs.readFileSync(path.join(dir, "fixes/a.bend"), "utf8");

  test("--fix writes the safe fixes to the file", () => {
    lintRun(dir, files(unused), "fixes/a.bend", ["--rules", UNUSED, "--fix"]);
    expect(read()).toBe("import Base\n\ndef z() -> U32:\n  0\n");
  });

  test("a fix that clashes with one taken before is skipped, and taken on the next run", () => {
    const messy = "import Base\nimport ./other.bend as O\n\ndef z() -> U32:\n    0\n";
    const first = lintText(dir, files(messy), "fixes/a.bend", [
      "--rules",
      FORMAT,
      "--rules",
      UNUSED,
      "--fix",
    ]);
    expect(first.stderr).toContain("skipped 1 fix(es)");
    expect(read()).toBe(unused);
    lintText(dir, {}, "fixes/a.bend", ["--rules", FORMAT, "--rules", UNUSED, "--fix"]);
    expect(read()).toBe("import Base\n\ndef z() -> U32:\n  0\n");
  });

  test("the text output gives each finding's line, column, severity and code, and its fixes", () => {
    const out = lintText(dir, files(unused), "fixes/a.bend", ["--rules", UNUSED]);
    expect(out.stdout.replaceAll("\r", "").split("\n").slice(0, 3)).toEqual([
      expect.stringMatching(
        /a\.bend:2:24: warning no-unused\/imports: Remove the import O: nothing uses it\.$/,
      ),
      "  fix: Remove the import [safe]",
      "bend-lint: 1 finding(s)",
    ]);
  });

  test("--json says ok only when no finding is an error", () => {
    const run = (text: string) =>
      JSON.parse(
        lintText(dir, files(text), "fixes/a.bend", ["--rules", UNUSED, "--json"]).stdout,
      ) as { ok: boolean };
    expect(run(unused).ok).toBe(true);
    expect(run("import Base\n\ndef z() -> U32:\n  nothing\n").ok).toBe(false);
  });
});
