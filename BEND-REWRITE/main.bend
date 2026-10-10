# This file's goal is to become a bend version of the bend-lint tool.
# This file must remain self-contained for the time-being(aside from base or bendhub, and aside from effects, the host, path.bend, and the rules folder), even if it contains laws and/or proofs.
# The host (host.ts) is the one TS file of the rewrite, and its entry point: `bun host.ts <args>`. It finds Bend, loads
# its checker and compiler into its own process and patches the checker (the seam), compiles this file with the
# --rules files, runs it, and answers its effects. It holds no linting logic: only what only TS can do.
# An expected consequence of self-contained: `bend main.bend --check-only` always reports the defs that rely on our
# effects ("N defs rely on unsafe or foreign code"). Only other errors are real proof failures.
# Every comment on this file stays here.
# Bend doesn't run natively on windows, with one exception: there's a sibling folder where a branch exists called feature/cuda-and-windows. This one works natively. If not that, you must use WSL. Effect code must be written with windows in mind anyway(or as agnostic as possible). We also have WSL iff not in the windows version.
# Drifts are intentional: Ergonomics win over 1:1 parity. Every drift is documented in the table below,
# with a stated reason.
#
# | Drift from the TS version                                   | Reason                                                       |
# | ----------------------------------------------------------- | ------------------------------------------------------------ |
# | No "suggested" fixes: only Safe and Dangerous.              | Reporting matters more than autofixing, for agents.          |
# | No --fix-suggested flag: it is an unknown flag like any     | There are no suggested fixes to apply.                       |
# | other.                                                      |                                                              |
# | The fix level is a Maybe<&2, FixApplicability>: None        | One type fewer, and each applicability is a level too.       |
# | fixes nothing, Some{Safe} applies Safe fixes, and           |                                                              |
# | Some{Dangerous} applies both.                               |                                                              |
# | A fix can also create, write, rename and delete files.      | Real fixes move code between files, not only inside one.     |
# | A fix's edits apply in order, each on the result before.    | One edit can build on another, such as a rename then a text  |
# |                                                             | change in the renamed file.                                  |
# | So a later edit shifts its offsets by the edits before it,  | A rule's spans come from the text as read. A law will state  |
# | and uses the path of any RenameFile before it.              | this later.                                                  |
# | get_fix_outcome returns no ReplaceText: only whole files.   | The caller only writes, renames and deletes files. A law     |
# |                                                             | will state this later.                                       |
# | A program rule's fix may touch many files.                  | Only a program rule sees who imports what. TS skips such a   |
# |                                                             | fix.                                                         |
# | The runner checks every Safe fix: one whose text declares   | A Safe fix must keep what the program does. Rules are pure,  |
# | something else is not offered, and its finding says why.    | so they cannot ask; the runner enforces it for every rule,   |
# |                                                             | and no author has to remember it.                            |
# | get_fix_outcome takes the LintReport and never writes: it   | One shape for the CLI and the library. An editor or agent    |
# | returns the edits to make.                                  | can show the edits, or make them itself.                     |
# | Skipped fixes come back as a list of findings.              | The caller can tell which fixes to run again. TS gives only  |
# |                                                             | counts.                                                      |
# | A finding always has a span.                                | Every finding has a natural place, and readers never unwrap  |
# |                                                             | a Maybe.                                                     |
# | A rule returns plain findings; the runner adds its rule_id. | A rule cannot give its findings a wrong code.                |
# | Only a program rule has entries: ProgramSomeScope or        | A file rule cannot set a value that would be ignored.        |
# | ProgramEveryScope.                                          |                                                              |
# | The config get_lint_report takes is resolved: no missing    | It never guesses. The caller decides defaults and flags      |
# | fields.                                                     | first, so it takes no separate imports.                      |
# | Per-rule config is a list of settings, not a map.           | Base has no map. RuleOff cannot carry a severity or options. |
# | The config file is bend-lint.json only: no bend-lint.js or  | Bend cannot run JS or TS code.                               |
# | bend-lint.ts.                                               |                                                              |
# | get_lint_report returns findings, suppressed findings and   | Callers need little else. Other failures stop the program    |
# | the linted files; errors use IO.die, not a Result.          | with a message.                                              |
# | EVERY path the linter touches is a normalized POSIX-style   | One spelling per file, on every system.                      |
# | path, symlinks included. Base and BendHub paths are exempt. |                                                              |
# | On Windows, C:\x\y becomes c:/x/y.                          | Windows reads it as it is, so no path is converted on its    |
# |                                                             | way to the OS.                                               |
# | Offsets count code points, not UTF-16 units.                | That is how Bend counts String characters.                   |
# | A rule is a value with a run function, not a module.        | Rules are plain Bend data. A Rule cannot be copied, so build |
# |                                                             | the list again where it is needed.                           |
# | Only Bend rules: no TS rules.                               | A Bend program cannot call TS code.                          |
# | A rule file defines def rules() -> List<&1, Rule>.          | One function, and a file can hold several rules.             |
# | --rules files are compiled into the program: when the rule  | Bend cannot load code while it runs. The program is cached,  |
# | files it wants are not the ones it holds, it restarts       | keyed by its sources.                                        |
# | itself with them.                                           |                                                              |
# | A rule's run is pure: no IO. It gets the data it declared   | Bend's parallel calls split only pure code, so rules can run |
# | up front, in its input.                                     | in parallel where Bend runs parallel calls.                  |
# | A rule names the rules it needs (after). prior holds only   | Only real dependencies make a rule wait. TS's prior is every |
# | their findings.                                             | earlier rule's, which makes each rule wait for all before.   |
# | No abort signal and no unsaved text yet.                    | Bend cannot hold an abort signal; it will be an effect.      |
# |                                                             | Unsaved text is for editors and can wait.                    |
# | Names carry their family as a prefix (FixEdit, RuleScope).  | Long names that say what they are read better than short     |
# |                                                             | ones.                                                        |
#
# TODO
# - performance/missed-fork crashes (machine stack overflow) and performance/append-in-loop hangs on this file.
#   Both are bugs of those rules, not of this file; bend-lint.json turns them off for this folder until they are
#   fixed.
# - A law: when get_order_problems finds none, get_lint_findings runs every rule; its fuel never runs out first.
#   Write it once the pure code has a file of its own, so --check-only means something.
# - For rules with autofixes only:
#   - Idempotence: applying a rule's fixes twice equals applying them once.
#   - Compatibility: no rule's fix undoes another's, so the rules reach a common fixed point.
#   - Linter idempotence: a second --fix run changes nothing. The two above make it hold.
#   - Confluence, ideally: the order fixes are applied in does not change the result.
# - The Safe-fix check covers ReplaceText edits of the linted file only. A fix that edits other files, or creates,
#   renames or deletes one, is offered unchecked; each file it changes must be checked, and the files together.
import Base
import ./path.bend as Path

type FixApplicability is Data:
  Safe{}
  Dangerous{}

type BendSource is Data:
  BendSource{path: String, text: String, lines: List<&2, String>}

type BendSourceSpan is Data:
  BendSourceSpan{path: String, beg: U32, end: U32}

type BendType is Data:
  BendType{id: U32, shown: String, ends_in_sort: Bool}

type DeclarationReference is Data:
  DeclarationReference{owner: String, span: BendSourceSpan}

type DeclarationKind is Data:
  ImportDeclaration{loads: String}
  DefDeclaration{fills: Bool, written_type: Maybe<&2, BendType>}
  DatatypeDeclaration{written_type: Maybe<&2, BendType>}
  ConstructorDeclaration{owner: String}
  ParameterDeclaration{owner: String, written_type: Maybe<&2, BendType>}
  VariableDeclaration{owner: String}
  FieldDeclaration{owner: String, written_type: Maybe<&2, BendType>}

type Declaration is Data:
  Declaration{
    name: String,
    span: BendSourceSpan,
    references: List<&2, DeclarationReference>,
    kind: DeclarationKind
  }

type SourceDeclarations is Data:
  SourceDeclarations{path: String, declarations: List<&2, Declaration>}

type FixEdit is Data:
  ReplaceText{span: BendSourceSpan, text: String}
  CreateOrWriteFile{path: String, text: String}
  RenameFile{from: String, to: String}
  DeleteFile{path: String}

type Fix is Data:
  Fix{title: String, applicability: FixApplicability, edits: List<&2, FixEdit>}

type FindingSeverity is Data:
  Error{}
  Warning{}
  Information{}
  Hint{}

type Finding is Data:
  Finding{severity: FindingSeverity, message: String, span: BendSourceSpan, fixes: List<&2, Fix>}

type OptionValue is Data:
  NumberValue{value: U32}
  FlagValue{value: Bool}
  TextValue{value: String}

type OptionGiven is Data:
  OptionGiven{key: String, value: OptionValue}

type OptionSpec is Data:
  NumberSpec{minimum: U32, maximum: U32}
  FlagSpec{}
  TextSpec{choices: List<&2, String>}
  AnySpec{specs: List<&2, OptionSpec>}

type OptionDeclared is Data:
  OptionDeclared{key: String, default: OptionValue, spec: OptionSpec}

type RuleFinding is Data:
  RuleFinding{rule_id: String, finding: Finding}

type RuleInput is Data:
  RuleInput{
    root: BendSource,
    sources: List<&2, BendSource>,
    options: List<&2, OptionGiven>,
    prior: List<&2, RuleFinding>,
    declarations: List<&2, SourceDeclarations>
  }

type RuleNeed is Data:
  DeclarationsNeed{}

type RuleScope is Data:
  FileScope{}
  ProgramSomeScope{}
  ProgramEveryScope{}

type Rule is Type:
  Rule{
    id: String,
    scope: RuleScope,
    options: List<&2, OptionDeclared>,
    after: List<&2, String>,
    needs: List<&2, RuleNeed>,
    run: RuleInput -> List<&2, Finding>
  }

type RuleSetting is Data:
  RuleOff{id: String}
  RuleOn{id: String, severity: Maybe<&2, FindingSeverity>, options: List<&2, OptionGiven>}

type LintConfig is Data:
  LintConfig{
    load: List<&2, String>,
    entries: List<&2, String>,
    imports: Bool,
    rules: List<&2, RuleSetting>
  }

type LintReport is Data:
  LintReport{
    findings: List<&2, RuleFinding>,
    suppressed: List<&2, RuleFinding>,
    linted: List<&2, BendSource>
  }

type FixOutcome is Data:
  FixOutcome{edits: List<&2, FixEdit>, skipped: List<&2, RuleFinding>}

type CliOutput is Data:
  CliTextOutput{show_suppressed: Bool}
  CliJsonOutput{}

type CliCommand is Data:
  CliHelp{}
  CliLint{
    files: List<&2, String>,
    rules: List<&2, String>,
    config: Maybe<&2, String>,
    imports: Maybe<&2, Bool>,
    fix: Maybe<&2, FixApplicability>,
    output: CliOutput
  }

type BendCheck is Data:
  BendCheck{
    root: BendSource,
    sources: List<&2, BendSource>,
    failure: Maybe<&2, RuleFinding>,
    declarations: List<&2, SourceDeclarations>
  }

type RuleHead is Data:
  RuleHead{id: String, after: List<&2, String>, needs: List<&2, RuleNeed>}

type LintTally is Data:
  LintTally{count: Nat, failed: Bool}

def get_check(path: String, declarations: Bool) -> IO(BendCheck):
  import "./effs/host.js"

def restart_with_rules(files: List<&2, String>) -> IO(Unit):
  import "./effs/host.js"

def get_keeps_declarations(path: String, text: String) -> IO(Bool):
  import "./effs/host.js"

def get_spliced_text(text: String, beg: U32, end: U32, put: String) -> IO(String):
  import "./effs/get_spliced_text.c"
  import "./effs/get_spliced_text.js"

def get_kept(-A: Data, keep: Bool, x: A, xs: List<&2, A>) -> List<&2, A>:
  match keep:
    case True{}:
      x <> xs
    case False{}:
      xs

def get_has_text(xs: List<&2, String>, +x: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      String.eq(h, x) || get_has_text(t, x)

def get_has_texts(xs: List<&2, String>, +all: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{h, t}:
      get_has_text(all, h) && get_has_texts(t, all)

def get_same_texts(a: List<&2, String>, b: List<&2, String>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Con{h, t} Con{g, u}:
      String.eq(h, g) && get_same_texts(t, u)
    case _ _:
      False{}

def get_rule_heads(rules: List<&1, Rule>) -> List<&2, RuleHead>:
  match rules:
    case Nil{}:
      []
    case Con{r, rest}:
      match r:
        case Rule{id, scope, options, after, needs, run}:
          RuleHead{id, after, needs} <> get_rule_heads(rest)

def get_head_ids(heads: List<&2, RuleHead>) -> List<&2, String>:
  match heads:
    case Nil{}:
      []
    case Con{h, t}:
      match h:
        case RuleHead{id, after, needs}:
          id <> get_head_ids(t)

def get_ready_ids(heads: List<&2, RuleHead>, +done: List<&2, String>) -> List<&2, String>:
  match heads:
    case Nil{}:
      []
    case Con{h, t}:
      match h:
        case RuleHead{+id, after, needs}:
          get_kept(
            String,
            Bool.not(get_has_text(done, id)) && get_has_texts(after, done),
            id,
            get_ready_ids(t, done)
          )

def get_needs_declarations(needs: List<&2, RuleNeed>) -> Bool:
  match needs:
    case Nil{}:
      False{}
    case Con{h, t}:
      match h:
        case DeclarationsNeed{}:
          True{}

def get_heads_need_declarations(heads: List<&2, RuleHead>) -> Bool:
  match heads:
    case Nil{}:
      False{}
    case Con{h, t}:
      match h:
        case RuleHead{id, after, needs}:
          get_needs_declarations(needs) || get_heads_need_declarations(t)

def get_given_declarations(
  want: Bool,
  declarations: List<&2, SourceDeclarations>
) -> List<&2, SourceDeclarations>:
  match want:
    case True{}:
      declarations
    case False{}:
      []

def get_rule_id(found: RuleFinding) -> String:
  match found:
    case RuleFinding{rule_id, finding}:
      rule_id

def get_prior(found: List<&2, RuleFinding>, +after: List<&2, String>) -> List<&2, RuleFinding>:
  match found:
    case Nil{}:
      []
    case Con{+f, t}:
      get_kept(RuleFinding, get_has_text(after, get_rule_id(f)), f, get_prior(t, after))

def get_tagged(+id: String, findings: List<&2, Finding>) -> List<&2, RuleFinding>:
  match findings:
    case Nil{}:
      []
    case Con{f, t}:
      RuleFinding{id, f} <> get_tagged(id, t)

def get_rule_run(
  hit: Bool,
  id: String,
  run: RuleInput -> List<&2, Finding>,
  input: RuleInput
) -> List<&2, RuleFinding>:
  match hit:
    case True{}:
      get_tagged(id, run(input))
    case False{}:
      []

def get_level_finding(
  r: Rule,
  +ready: List<&2, String>,
  +found: List<&2, RuleFinding>,
  +root: BendSource,
  +sources: List<&2, BendSource>,
  +declarations: List<&2, SourceDeclarations>
) -> List<&2, RuleFinding>:
  match r:
    case Rule{+id, scope, options, after, needs, run}:
      get_rule_run(
        get_has_text(ready, id),
        id,
        run,
        RuleInput{
          root,
          sources,
          [],
          get_prior(found, after),
          get_given_declarations(get_needs_declarations(needs), declarations)
        }
      )

def get_level_findings(
  rules: List<&1, Rule>,
  +ready: List<&2, String>,
  +found: List<&2, RuleFinding>,
  +root: BendSource,
  +sources: List<&2, BendSource>,
  +declarations: List<&2, SourceDeclarations>
) -> List<&2, RuleFinding>:
  match rules:
    case Nil{}:
      []
    case Con{r, rest}:
      a b = get_level_finding(
        r,
        ready,
        found,
        root,
        sources,
        declarations
      ) get_level_findings(rest, ready, found, root, sources, declarations)
      List.append(&2, RuleFinding, a, b)

def get_texts_where(
  +inside: Bool,
  xs: List<&2, String>,
  +set: List<&2, String>
) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{+h, t}:
      get_kept(
        String,
        (inside && get_has_text(set, h)) || (Bool.not(inside) && Bool.not(get_has_text(set, h))),
        h,
        get_texts_where(inside, t, set)
      )

def get_done_ids(
  fuel: Nat,
  ready: List<&2, String>,
  +heads: List<&2, RuleHead>,
  +done: List<&2, String>
) -> List<&2, String>:
  match fuel ready:
    case 0n _:
      done
    case 1n+k Nil{}:
      done
    case 1n+k Con{+h, +t}:
      +now = List.append(&2, String, done, h <> t)
      get_done_ids(k, get_ready_ids(heads, now), heads, now)

def get_unknown_lines(+id: String, unknown: List<&2, String>) -> List<&2, String>:
  match unknown:
    case Nil{}:
      []
    case Con{x, t}:
      (id ++ " waits on " ++ x ++ ", which no loaded rule has") <> get_unknown_lines(id, t)

def get_stuck_lines(done: Bool, id: String, waiting: List<&2, String>) -> List<&2, String>:
  match done waiting:
    case False{} Con{h, t}:
      [id ++ " waits on " ++ String.join(h <> t, ", ")]
    case _ _:
      []

def get_order_problems.of(
  +all: List<&2, String>,
  +done: List<&2, String>,
  heads: List<&2, RuleHead>
) -> List<&2, String>:
  match heads:
    case Nil{}:
      []
    case Con{h, t}:
      match h:
        case RuleHead{+id, +after, needs}:
          List.append(
            &2,
            String,
            List.append(
              &2,
              String,
              get_unknown_lines(id, get_texts_where(False{}, after, all)),
              get_stuck_lines(
                get_has_text(done, id),
                id,
                get_texts_where(False{}, get_texts_where(True{}, after, all), done)
              )
            ),
            get_order_problems.of(all, done, t)
          )

def get_order_problems(+heads: List<&2, RuleHead>) -> List<&2, String>:
  get_order_problems.of(
    get_head_ids(heads),
    get_done_ids((1n + List.length(&2, RuleHead, heads): Nat), get_ready_ids(heads, []), heads, []),
    heads
  )

def get_lint_findings(
  ~rules: Unit -> List<&1, Rule>,
  fuel: Nat,
  ready: List<&2, String>,
  +heads: List<&2, RuleHead>,
  +done: List<&2, String>,
  +found: List<&2, RuleFinding>,
  +root: BendSource,
  +sources: List<&2, BendSource>,
  +declarations: List<&2, SourceDeclarations>
) -> List<&2, RuleFinding>:
  match fuel ready:
    case 0n _:
      found
    case 1n+k Nil{}:
      found
    case 1n+k Con{+h, +t}:
      +now = List.append(&2, String, done, h <> t)
      get_lint_findings(
        ~rules,
        k,
        get_ready_ids(heads, now),
        heads,
        now,
        List.append(
          &2,
          RuleFinding,
          found,
          get_level_findings(rules(Unit{}), h <> t, found, root, sources, declarations)
        ),
        root,
        sources,
        declarations
      )

def get_lint_report(
  ~rules: Unit -> List<&1, Rule>,
  check: BendCheck,
  config: LintConfig
) -> LintReport:
  match check:
    case BendCheck{+root, +sources, failure, +declarations}:
      match failure:
        case Some{value}:
          LintReport{[value], [], [root]}
        case None{}:
          +heads = get_rule_heads(rules(Unit{}))
          LintReport{
            get_lint_findings(
              ~rules,
              (1n + List.length(&2, RuleHead, heads): Nat),
              get_ready_ids(heads, []),
              heads,
              [],
              [],
              root,
              sources,
              declarations
            ),
            [],
            [root]
          }

def get_fix_outcome(report: LintReport, level: Maybe<&2, FixApplicability>) -> FixOutcome:
  FixOutcome{[], []}

def get_linter_source(source: BendSource) -> BendSource:
  match source:
    case BendSource{path, text, lines}:
      BendSource{Path.get_posix_path(path), text, lines}

def get_linter_sources(sources: List<&2, BendSource>) -> List<&2, BendSource>:
  match sources:
    case Nil{}:
      []
    case Con{s, t}:
      get_linter_source(s) <> get_linter_sources(t)

def get_linter_span(span: BendSourceSpan) -> BendSourceSpan:
  match span:
    case BendSourceSpan{path, beg, end}:
      BendSourceSpan{Path.get_posix_path(path), beg, end}

def get_linter_finding(found: RuleFinding) -> RuleFinding:
  match found:
    case RuleFinding{rule_id, finding}:
      match finding:
        case Finding{severity, message, span, fixes}:
          RuleFinding{rule_id, Finding{severity, message, get_linter_span(span), fixes}}

def get_linter_references(
  references: List<&2, DeclarationReference>
) -> List<&2, DeclarationReference>:
  match references:
    case Nil{}:
      []
    case Con{r, t}:
      match r:
        case DeclarationReference{owner, span}:
          DeclarationReference{owner, get_linter_span(span)} <> get_linter_references(t)

def get_linter_kind(kind: DeclarationKind) -> DeclarationKind:
  match kind:
    case ImportDeclaration{loads}:
      ImportDeclaration{Path.get_posix_path(loads)}
    case _:
      kind

def get_linter_declarations(declarations: List<&2, Declaration>) -> List<&2, Declaration>:
  match declarations:
    case Nil{}:
      []
    case Con{d, t}:
      match d:
        case Declaration{name, span, references, kind}:
          Declaration{
            name,
            get_linter_span(span),
            get_linter_references(references),
            get_linter_kind(kind)
          }
            <> get_linter_declarations(t)

def get_linter_source_declarations(
  all: List<&2, SourceDeclarations>
) -> List<&2, SourceDeclarations>:
  match all:
    case Nil{}:
      []
    case Con{s, t}:
      match s:
        case SourceDeclarations{path, declarations}:
          SourceDeclarations{
            Path.get_posix_path(path),
            get_linter_declarations(declarations)
          }
            <> get_linter_source_declarations(t)

def get_linter_failure(failure: Maybe<&2, RuleFinding>) -> Maybe<&2, RuleFinding>:
  match failure:
    case None{}:
      None{}
    case Some{value}:
      Some{get_linter_finding(value)}

def get_linter_check(check: BendCheck) -> BendCheck:
  match check:
    case BendCheck{root, sources, failure, declarations}:
      BendCheck{
        get_linter_source(root),
        get_linter_sources(sources),
        get_linter_failure(failure),
        get_linter_source_declarations(declarations)
      }

def get_usage() -> String:
  "usage: bun BEND-REWRITE/host.ts <file>... [--rules <rule.bend>]..."

def get_flag_error(+flag: String) -> String:
  Bool.pick(
    String,
    get_has_text(
      [
        "--fix",
        "--fix-dangerously",
        "--json",
        "--imports",
        "--show-suppressed",
        "--config",
        "--no-fix",
        "--no-fix-dangerously",
        "--no-json",
        "--no-imports",
        "--no-show-suppressed"
      ],
      flag
    ),
    flag ++ " is not supported yet",
    "unknown option " ++ flag
  )

def get_cli_command.go(
  args: List<String>,
  files: List<&2, String>,
  rules: List<&2, String>
) -> Result<&1, &1, String, CliCommand>:
  match args:
    case Nil{}:
      Done{
        CliLint{
          List.reverse(&2, String, files),
          List.reverse(&2, String, rules),
          None{},
          None{},
          None{},
          CliTextOutput{False{}}
        }
      }
    case Con{"--rules", Con{x, t}}:
      get_cli_command.go(t, files, x <> rules)
    case Con{"--rules", Nil{}}:
      Fail{"--rules needs a rule file"}
    case Con{"--help", t}:
      Done{CliHelp{}}
    case Con{"-h", t}:
      Done{CliHelp{}}
    case Con{+h, t}:
      Bool.pick(
        Result<&1, &1, String, CliCommand>,
        String.starts_with(h, "-"),
        Fail{get_flag_error(h)},
        get_cli_command.go(t, h <> files, rules)
      )

def get_cli_command(args: List<String>) -> Result<&1, &1, String, CliCommand>:
  get_cli_command.go(args, [], [])

def get_linter_paths.one(r: Result<&1, &1, U32 & String, String>) -> IO(String):
  match r:
    case Done{value}:
      IO.pure(String, value)
    case Fail{error}:
      match error:
        case (code, text):
          IO.die(String, 2, "bend-lint: " ++ text)

def get_linter_paths(paths: List<&2, String>, done: List<&2, String>) -> IO(List<&2, String>):
  match paths:
    case Nil{}:
      IO.pure(List<&2, String>, List.reverse(&2, String, done))
    case Con{h, t}:
      IO.bind(
        String,
        List<&2, String>,
        IO.bind(
          Result<&1, &1, U32 & String, String>,
          String,
          Path.get_linter_path(h),
          get_linter_paths.one
        ),
        path => get_linter_paths(t, path <> done)
      )

def get_tally(tally: LintTally, severity: FindingSeverity) -> LintTally:
  match tally severity:
    case LintTally{count, failed} Error{}:
      LintTally{(1n + count: Nat), True{}}
    case LintTally{count, failed} _:
      LintTally{(1n + count: Nat), failed}

def print_findings(findings: List<&2, RuleFinding>, tally: LintTally) -> IO(LintTally):
  match findings:
    case Nil{}:
      IO.pure(LintTally, tally)
    case Con{f, t}:
      match f:
        case RuleFinding{rule_id, finding}:
          match finding:
            case Finding{severity, message, span, fixes}:
              match span:
                case BendSourceSpan{path, beg, end}:
                  IO.bind(
                    Unit,
                    LintTally,
                    IO.print(path ++ ":" ++ U32.show(beg) ++ ": " ++ rule_id ++ ": " ++ message),
                    u => print_findings(t, get_tally(tally, severity))
                  )

def get_report_findings(report: LintReport) -> List<&2, RuleFinding>:
  match report:
    case LintReport{findings, suppressed, linted}:
      findings

def get_is_checkable(edits: List<&2, FixEdit>, +path: String) -> Bool:
  match edits:
    case Nil{}:
      True{}
    case Con{ReplaceText{BendSourceSpan{p, b, e}, put}, t}:
      String.eq(p, path) && get_is_checkable(t, path)
    case Con{x, t}:
      False{}

def get_fix_text(edits: List<&2, FixEdit>, text: String) -> IO(String):
  match edits:
    case Nil{}:
      IO.pure(String, text)
    case Con{ReplaceText{BendSourceSpan{p, b, e}, put}, t}:
      IO.bind(String, String, get_spliced_text(text, b, e, put), next => get_fix_text(t, next))
    case Con{x, t}:
      get_fix_text(t, text)

def get_fix_kept.check(
  checkable: Bool,
  +path: String,
  text: String,
  edits: List<&2, FixEdit>
) -> IO(Bool):
  match checkable:
    case True{}:
      IO.bind(String, Bool, get_fix_text(edits, text), fixed => get_keeps_declarations(path, fixed))
    case False{}:
      IO.pure(Bool, True{})

def get_fix_kept(+path: String, text: String, fix: Fix) -> IO(Bool):
  match fix:
    case Fix{title, Safe{}, +edits}:
      get_fix_kept.check(get_is_checkable(edits, path), path, text, edits)
    case Fix{title, Dangerous{}, edits}:
      IO.pure(Bool, True{})

def get_kept_fixes(fixes: List<&2, Fix>, +path: String, +text: String) -> IO(List<&2, Fix>):
  match fixes:
    case Nil{}:
      IO.pure(List<&2, Fix>, [])
    case Con{+f, t}:
      IO.bind(
        Bool,
        List<&2, Fix>,
        get_fix_kept(path, text, f),
        ok => IO.bind(
          List<&2, Fix>,
          List<&2, Fix>,
          get_kept_fixes(t, path, text),
          rest => IO.pure(List<&2, Fix>, get_kept(Fix, ok, f, rest))
        )
      )

def get_fix_note(all_kept: Bool, message: String) -> String:
  match all_kept:
    case True{}:
      message
    case False{}:
      message ++ " The fix was not offered: it would change what the file declares."

def get_checked_finding.made(
  rule_id: String,
  severity: FindingSeverity,
  message: String,
  span: BendSourceSpan,
  +kept: List<&2, Fix>,
  offered: Nat
) -> RuleFinding:
  RuleFinding{
    rule_id,
    Finding{
      severity,
      get_fix_note(
        U32.is_eq(U32.from_nat(List.length(&2, Fix, kept)), U32.from_nat(offered)),
        message
      ),
      span,
      kept
    }
  }

def get_checked_finding(+path: String, +text: String, found: RuleFinding) -> IO(RuleFinding):
  match found:
    case RuleFinding{rule_id, Finding{severity, message, span, +fixes}}:
      IO.bind(
        List<&2, Fix>,
        RuleFinding,
        get_kept_fixes(fixes, path, text),
        kept => IO.pure(
          RuleFinding,
          get_checked_finding.made(
            rule_id,
            severity,
            message,
            span,
            kept,
            List.length(&2, Fix, fixes)
          )
        )
      )

def get_checked_findings(
  findings: List<&2, RuleFinding>,
  +path: String,
  +text: String
) -> IO(List<&2, RuleFinding>):
  match findings:
    case Nil{}:
      IO.pure(List<&2, RuleFinding>, [])
    case Con{f, t}:
      IO.bind(
        RuleFinding,
        List<&2, RuleFinding>,
        get_checked_finding(path, text, f),
        one => IO.bind(
          List<&2, RuleFinding>,
          List<&2, RuleFinding>,
          get_checked_findings(t, path, text),
          rest => IO.pure(List<&2, RuleFinding>, one <> rest)
        )
      )

def get_checked_report(report: LintReport) -> IO(LintReport):
  match report:
    case LintReport{findings, suppressed, Con{BendSource{+path, +text, lines}, rest}}:
      IO.bind(
        List<&2, RuleFinding>,
        LintReport,
        get_checked_findings(findings, path, text),
        checked => IO.pure(
          LintReport,
          LintReport{checked, suppressed, BendSource{path, text, lines} <> rest}
        )
      )
    case _:
      IO.pure(LintReport, report)

def lint_file.resolved(
  ~rules: Unit -> List<&1, Rule>,
  r: Result<&1, &1, U32 & String, String>,
  path: String
) -> IO(LintReport):
  match r:
    case Done{value}:
      IO.bind(
        BendCheck,
        LintReport,
        get_check(value, get_heads_need_declarations(get_rule_heads(rules(Unit{})))),
        check => get_checked_report(
          get_lint_report(~rules, get_linter_check(check), LintConfig{[], [], False{}, []})
        )
      )
    case Fail{error}:
      match error:
        case (code, text):
          IO.pure(
            LintReport,
            LintReport{
              [
                RuleFinding{
                  "bend-lint/path",
                  Finding{Error{}, text, BendSourceSpan{path, 0, 0}, []}
                }
              ],
              [],
              []
            }
          )

def lint_file(~rules: Unit -> List<&1, Rule>, +path: String) -> IO(LintReport):
  IO.bind(
    Result<&1, &1, U32 & String, String>,
    LintReport,
    Path.get_linter_path(path),
    r => lint_file.resolved(~rules, r, path)
  )

def lint_files.finish(tally: LintTally) -> IO(Unit):
  match tally:
    case LintTally{count, True{}}:
      IO.die(Unit, 1, "bend-lint: FAIL")
    case LintTally{count, False{}}:
      IO.print("bend-lint: " ++ Nat.show(count) ++ " finding(s)")

def lint_files(
  ~rules: Unit -> List<&1, Rule>,
  files: List<&2, String>,
  tally: LintTally
) -> IO(Unit):
  match files:
    case Nil{}:
      lint_files.finish(tally)
    case Con{h, t}:
      IO.bind(
        LintTally,
        Unit,
        IO.bind(
          LintReport,
          LintTally,
          lint_file(~rules, h),
          report => print_findings(get_report_findings(report), tally)
        ),
        next => lint_files(~rules, t, next)
      )

def serve.ordered(
  ~rules: Unit -> List<&1, Rule>,
  problems: List<&2, String>,
  files: List<&2, String>
) -> IO(Unit):
  match problems:
    case Nil{}:
      lint_files(~rules, files, LintTally{0n, False{}})
    case Con{h, t}:
      IO.die(Unit, 2, "bend-lint: the rules' order is broken:\n" ++ String.join(h <> t, "\n"))

def serve.choose(
  ~rules: Unit -> List<&1, Rule>,
  same: Bool,
  wanted: List<&2, String>,
  files: List<&2, String>
) -> IO(Unit):
  match same:
    case True{}:
      serve.ordered(~rules, get_order_problems(get_rule_heads(rules(Unit{}))), files)
    case False{}:
      restart_with_rules(wanted)

def serve.wanted(
  ~rules: Unit -> List<&1, Rule>,
  +wanted: List<&2, String>,
  compiled: List<&2, String>,
  files: List<&2, String>
) -> IO(Unit):
  serve.choose(~rules, get_same_texts(wanted, compiled), wanted, files)

def serve.command(
  ~rules: Unit -> List<&1, Rule>,
  command: CliCommand,
  +compiled: List<&2, String>
) -> IO(Unit):
  match command:
    case CliHelp{}:
      IO.print(get_usage())
    case CliLint{files, rule_files, config, imports, fix, output}:
      IO.bind(
        List<&2, String>,
        Unit,
        get_linter_paths(rule_files, []),
        wanted => serve.wanted(~rules, wanted, compiled, files)
      )

def serve.parsed(
  ~rules: Unit -> List<&1, Rule>,
  parsed: Result<&1, &1, String, CliCommand>,
  +compiled: List<&2, String>
) -> IO(Unit):
  match parsed:
    case Done{value}:
      serve.command(~rules, value, compiled)
    case Fail{error}:
      IO.die(Unit, 2, "bend-lint: " ++ error ++ "\n" ++ get_usage())

def serve.args(
  ~rules: Unit -> List<&1, Rule>,
  args: List<String>,
  +compiled: List<&2, String>
) -> IO(Unit):
  match args:
    case Nil{}:
      serve.parsed(~rules, get_cli_command([]), compiled)
    case Con{h, t}:
      serve.parsed(~rules, get_cli_command(t), compiled)

def serve(~rules: Unit -> List<&1, Rule>, +compiled: List<&2, String>) -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), args => serve.args(~rules, args, compiled))
