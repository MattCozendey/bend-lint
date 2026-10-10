// Imports
// =======

import { afterAll, describe, expect, setDefaultTimeout, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { lintIn, lintRun } from "./testing.ts";
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
    "def run(input: Lint.RuleInput) -> List<&2, Lint.Finding>:",
    "  match input:",
    "    case Lint.RuleInput{Lint.BendSource{+path, text, lines}, sources, options, prior, +declarations}:",
    "      +n = Nat.show(List.length(&2, Lint.SourceDeclarations, declarations))",
    "      +c = U32.from_nat(List.length(&2, Lint.SourceDeclarations, declarations))",
    `      ${body}`,
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
  "def run(input: Lint.RuleInput) -> List<&2, Lint.Finding>:",
  "  match input:",
  "    case Lint.RuleInput{Lint.BendSource{path, text, lines}, sources, options, prior, declarations}:",
  "      [Lint.Finding{Lint.Hint{}, width(options), Lint.BendSourceSpan{path, 0, 0}, []}]",
  "",
  "def rules() -> List<&1, Lint.Rule>:",
  '  [Lint.Rule{"test/width", Lint.FileScope{}, [Lint.OptionDeclared{"width", Lint.NumberValue{2}, Lint.NumberSpec{1, 10}}], [], [], run}]',
  "",
].join("\n");

// A rule that needs `need`, and reports each variable the checker checked
// in its file: its name, type and quantity.
const typesRule = (need: string): string =>
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
    "def found(t: Lint.BendTerm, done: List<&2, Lint.Finding>) -> List<&2, Lint.Finding>:",
    "  match t:",
    "    case Lint.CheckedTerm{",
    "      Lint.VariableTerm{name, Some{span}},",
    "      Lint.TermFact{Lint.BendType{id, shown, term}, q, uses, binder}",
    "    }:",
    '      Lint.Finding{Lint.Hint{}, name ++ ": " ++ shown ++ ", " ++ quantity(q), span, []} <> done',
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
    "def each(ds: List<&2, Lint.Declaration>) -> List<&2, Lint.Finding>:",
    "  match ds:",
    "    case Nil{}:",
    "      []",
    "    case Con{Lint.Declaration{name, span, references, Lint.DefDeclaration{fills, written, Some{body}}}, t}:",
    "      List.append(&2, Lint.Finding, List.reverse(&2, Lint.Finding, found(body, [])), each(t))",
    "    case Con{d, t}:",
    "      each(t)",
    "",
    "def all(sources: List<&2, Lint.SourceDeclarations>) -> List<&2, Lint.Finding>:",
    "  match sources:",
    "    case Nil{}:",
    "      []",
    "    case Con{Lint.SourceDeclarations{path, ds}, t}:",
    "      List.append(&2, Lint.Finding, each(ds), all(t))",
    "",
    "def run(input: Lint.RuleInput) -> List<&2, Lint.Finding>:",
    "  match input:",
    "    case Lint.RuleInput{root, sources, options, prior, declarations}:",
    "      all(declarations)",
    "",
    "def rules() -> List<&1, Lint.Rule>:",
    `  [Lint.Rule{"test/types", Lint.FileScope{}, [], [], [Lint.${need}{}], run}]`,
    "",
  ].join("\n");

const RULES = {
  // Reports, at the start of its file, how many files it saw.
  "seen.bend": rule("test/seen", "FileScope", "[at(path, n)]"),
  // Reports in each file it saw, with how many it saw.
  "everywhere.bend": rule("test/everywhere", "ProgramSomeScope", "each(declarations, n)"),
  // A file rule that reports in every other file the check read.
  "elsewhere.bend": rule("test/elsewhere", "FileScope", "others(sources, path)"),
  "types.bend": typesRule("FactsNeed"),
  "untyped.bend": typesRule("BodiesNeed"),
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
    "def run(input: Lint.RuleInput) -> List<&2, Lint.Finding>:",
    "  match input:",
    "    case Lint.RuleInput{Lint.BendSource{+path, text, lines}, sources, options, prior, declarations}:",
    "      marked(lines, 0, path)",
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
const found = (rules: string[], ...flags: string[]): Array<Omit<Found, "text">> =>
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
    const brief = (fs: Found[]) => fs.map(({ code, text, fixes }) => ({ code, text, fixes }));
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
