# This file's goal is to become a bend version of the bend-lint tool.
# This file must remain self-contained for the time-being(aside from base or bendhub, and aside from effects, the host, path.bend, testing.ts and the rules folder), even if it contains laws and/or proofs.
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
# | The runner checks every Safe fix: one not shown to keep     | A Safe fix must keep what the program does. Rules are pure,  |
# | what the file declares is not offered, and its finding says | so they cannot ask; the runner enforces it for every rule,   |
# | why.                                                        | and no author has to remember it.                            |
# | A Safe fix the runner cannot check is offered as Dangerous: | Only text edits in the linted file can be checked today, so  |
# | one that edits other files, or creates, renames or deletes  | a wider fix is not called Safe on a promise nobody verified. |
# | a file.                                                     |                                                              |
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
# | A program rule gets each file's declarations as that file   | One spelling per file in every scope; Bend's own names never |
# | spells them, by path; TS gives it the check's names.        | reach a rule. A path and an import's alias tell files apart. |
# | A def's checked body is a BendTerm in its DefDeclaration,   | Rules never see Bend's own terms, so they stay when Bend's   |
# | given only to a rule that needs BodiesNeed: a call with all | checker changes. TS gives Bend's term kinds, bit by bit.     |
# | its arguments, a literal as one term, no annotation the     |                                                              |
# | checker added.                                              |                                                              |
# | A term holds its sub-terms, and a list of terms is a term   | Bend has no mutual recursion, so one def walks a whole body. |
# | too (SomeTerms, NoTerms). No term has a parent.             | A walk passes what it knows down instead.                    |
# | The checker's facts are in the body: with FactsNeed, a term | They are where the checker put them: its annotations. A term |
# | the checker checked is a CheckedTerm with its TermFact.     | checked twice has both facts.                                |
# | A call's partial applications have no facts of their own.  | A call is one term; its head and arguments keep theirs.      |
# | A type is also a term (BendType.term), without spans.       | One representation for terms and types, as in Bend.          |
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
# - The Safe-fix check covers ReplaceText edits of the linted file only; any other Safe fix is offered as Dangerous.
#   Check each file a fix changes, and the files together, so such a fix can stay Safe.
# - The text output shows each fix's title and applicability; the TS output also shows its diff.
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
  BendType{id: U32, shown: String, term: BendTerm}

type Quantity is Data:
  ErasedQuantity{}
  OnceQuantity{}
  ManyQuantity{}

type TermUse is Data:
  TermUse{name: String, quantity: Quantity}

type TermFact is Data:
  TermFact{
    checked_as: BendType,
    quantity: Quantity,
    uses: List<&2, TermUse>,
    binder: Maybe<&2, BendType>
  }

type BendTerm is Data:
  VariableTerm{name: String, span: Maybe<&2, BendSourceSpan>}
  ReferenceTerm{name: String, span: Maybe<&2, BendSourceSpan>}
  CallTerm{head: BendTerm, arguments: BendTerm, span: Maybe<&2, BendSourceSpan>}
  LetTerm{
    names: List<&2, String>,
    values: BendTerm,
    body: BendTerm,
    span: Maybe<&2, BendSourceSpan>
  }
  LambdaTerm{name: String, body: BendTerm, span: Maybe<&2, BendSourceSpan>}
  ConstructorTerm{name: String, fields: BendTerm, span: Maybe<&2, BendSourceSpan>}
  LiteralTerm{shown: String, span: Maybe<&2, BendSourceSpan>}
  AnnotatedTerm{value: BendTerm, annotation: BendTerm, span: Maybe<&2, BendSourceSpan>}
  ForallTerm{
    name: String,
    quantity: Quantity,
    domain: BendTerm,
    body: BendTerm,
    span: Maybe<&2, BendSourceSpan>
  }
  SortTerm{level: BendTerm, span: Maybe<&2, BendSourceSpan>}
  DatatypeTerm{name: String, arguments: BendTerm, span: Maybe<&2, BendSourceSpan>}
  OtherTerm{parts: BendTerm, span: Maybe<&2, BendSourceSpan>}
  CheckedTerm{term: BendTerm, fact: TermFact}
  SomeTerms{first: BendTerm, rest: BendTerm}
  NoTerms{}

type DeclarationReference is Data:
  DeclarationReference{owner: String, span: BendSourceSpan}

type DeclarationKind is Data:
  ImportDeclaration{loads: String}
  DefDeclaration{fills: Bool, written_type: Maybe<&2, BendType>, body: Maybe<&2, BendTerm>}
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
  BodiesNeed{}
  FactsNeed{}

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
    declarations: List<&2, SourceDeclarations>,
    program_paths: List<&2, String>
  }

type RunPlace is Data:
  FileRun{on: BendSource}
  ProgramRun{check: BendCheck}

type RuleHead is Data:
  RuleHead{id: String, after: List<&2, String>, needs: List<&2, RuleNeed>}

# What the reports so far hold: their findings and suppressed findings, each last first.
type LintTally is Data:
  LintTally{findings: List<&2, RuleFinding>, suppressed: List<&2, RuleFinding>}

type JsonValue is Data:
  JsonNull{}
  JsonBool{value: Bool}
  JsonNumber{text: String}
  JsonText{value: String}
  JsonList{items: List<&2, JsonValue>}
  JsonObject{fields: List<&2, JsonField>}

type JsonField is Data:
  JsonField{key: String, value: JsonValue}

type JsonFrame is Data:
  JsonListFrame{items: List<&2, JsonValue>}
  JsonObjectFrame{fields: List<&2, JsonField>, key: String}

type JsonPart is Data:
  JsonPartDone{value: JsonValue, rest: String}
  JsonPartFail{error: String}

type JsonStep is Data:
  JsonWantValue{}
  JsonWantItem{}
  JsonWantKey{first: Bool}
  JsonWantColon{key: String}
  JsonParsed{part: JsonPart}
  JsonParsedKey{part: JsonPart}
  JsonGot{value: JsonValue}

type ConfigFile is Data:
  ConfigFile{
    load: List<&2, String>,
    entries: List<&2, String>,
    imports: Maybe<&2, Bool>,
    rules: List<&2, RuleSetting>
  }

type RuleFile is Data:
  RuleFile{path: String, ids: List<&2, String>}

type LintTarget is Data:
  LintTarget{given: String, path: String, found: Bool, why: String}

type LintJob is Data:
  LintJob{target: LintTarget, config: LintConfig}

# A comment of a linted file: where it is (from its `#`), its line, whether code comes before it on that line, and its
# text after the `#`.
type Comment is Data:
  Comment{beg: U32, end: U32, line: U32, trailing: Bool, body: String}

type ScanMode is Data:
  ScanCode{}
  ScanComment{}
  ScanString{}
  ScanStringEscape{}
  ScanChar{}
  ScanCharEscape{}

# A file's comments, and whether each of its lines holds code, from the first line.
type Scan is Data:
  Scan{comments: List<&2, Comment>, code: List<&2, Bool>}

# A directive's parts as written: action, scope, rule, the severity it names, and its reason.
type DirectiveParts is Data:
  DirectiveParts{
    action: String,
    scope: String,
    rule: String,
    pinned: Maybe<&2, String>,
    reason: Maybe<&2, String>
  }

# A directive: its action (disable or expect), scope (file, begin, end, next or line), rule, the severity it pins, and
# its comment.
type Directive is Data:
  Directive{
    action: String,
    scope: String,
    rule: String,
    severity: Maybe<&2, FindingSeverity>,
    comment: Comment
  }

type DirectiveRead is Data:
  DirectiveFound{directive: Directive}
  DirectiveWrong{why: String, comment: Comment}

# A directive, its number in its file, and the lines it covers, both ends included; none when `from` is past `to`.
type Covering is Data:
  Covering{index: Nat, directive: Directive, from: U32, to: U32}

# An open begin: the key of its action and rule, its number, its severity, and its comment.
type OpenBegin is Data:
  OpenBegin{key: String, index: Nat, severity: Maybe<&2, FindingSeverity>, comment: Comment}

type Closed is Data:
  Closed{index: Nat, line: U32}

# What the directives of a file say: the lines each covers, and the findings about them.
type FileDirectives is Data:
  FileDirectives{
    path: String,
    lines: List<&2, String>,
    coverings: List<&2, Covering>,
    wrong: List<&2, RuleFinding>
  }

# A directive that covered a finding: its file and number.
type Used is Data:
  Used{path: String, index: Nat}

# The findings that stay and those a directive covers, and the directives that covered one.
type SuppressState is Data:
  SuppressState{
    kept: List<&2, RuleFinding>,
    suppressed: List<&2, RuleFinding>,
    used: List<&2, Used>
  }

# What the rules need from a check: declarations, bodies, facts.
type CheckNeeds is Data:
  CheckNeeds{declarations: Bool, bodies: Bool, facts: Bool}

def get_check(path: String, declarations: Bool, bodies: Bool, facts: Bool) -> IO(BendCheck):
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

def get_is_need(a: RuleNeed, b: RuleNeed) -> Bool:
  match a b:
    case DeclarationsNeed{} DeclarationsNeed{}:
      True{}
    case BodiesNeed{} BodiesNeed{}:
      True{}
    case FactsNeed{} FactsNeed{}:
      True{}
    case _ _:
      False{}

def get_needs(needs: List<&2, RuleNeed>, +want: RuleNeed) -> Bool:
  match needs:
    case Nil{}:
      False{}
    case Con{h, t}:
      get_is_need(h, want) || get_needs(t, want)

def get_heads_need(heads: List<&2, RuleHead>, +want: RuleNeed) -> Bool:
  match heads:
    case Nil{}:
      False{}
    case Con{h, t}:
      match h:
        case RuleHead{id, after, needs}:
          get_needs(needs, want) || get_heads_need(t, want)

def get_given_declarations(
  want: Bool,
  declarations: List<&2, SourceDeclarations>
) -> List<&2, SourceDeclarations>:
  match want:
    case True{}:
      declarations
    case False{}:
      []

def get_needless_heads(heads: List<&2, RuleHead>) -> List<&2, RuleHead>:
  match heads:
    case Nil{}:
      []
    case Con{RuleHead{id, after, Nil{}}, t}:
      RuleHead{id, after, []} <> get_needless_heads(t)
    case Con{x, t}:
      get_needless_heads(t)

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

def get_severe(severity: Maybe<&2, FindingSeverity>, f: Finding) -> Finding:
  match severity f:
    case Some{s} Finding{old, message, span, fixes}:
      Finding{s, message, span, fixes}
    case None{} _:
      f

# The findings of rule `id`, with the severity its settings give, if any.
def get_tagged(
  +id: String,
  +severity: Maybe<&2, FindingSeverity>,
  findings: List<&2, Finding>
) -> List<&2, RuleFinding>:
  match findings:
    case Nil{}:
      []
    case Con{f, t}:
      RuleFinding{id, get_severe(severity, f)} <> get_tagged(id, severity, t)

def get_source_path(source: BendSource) -> String:
  match source:
    case BendSource{path, text, lines}:
      path

def get_source_paths(sources: List<&2, BendSource>) -> List<&2, String>:
  match sources:
    case Nil{}:
      []
    case Con{s, t}:
      get_source_path(s) <> get_source_paths(t)

def get_sources_in(sources: List<&2, BendSource>, +paths: List<&2, String>) -> List<&2, BendSource>:
  match sources:
    case Nil{}:
      []
    case Con{+s, t}:
      get_kept(BendSource, get_has_text(paths, get_source_path(s)), s, get_sources_in(t, paths))

def get_finding_path(found: RuleFinding) -> String:
  match found:
    case RuleFinding{rule_id, Finding{severity, message, BendSourceSpan{path, beg, end}, fixes}}:
      path

def get_found_in(found: List<&2, RuleFinding>, +paths: List<&2, String>) -> List<&2, RuleFinding>:
  match found:
    case Nil{}:
      []
    case Con{+f, t}:
      get_kept(RuleFinding, get_has_text(paths, get_finding_path(f)), f, get_found_in(t, paths))

def get_declarations_in(
  all: List<&2, SourceDeclarations>,
  +paths: List<&2, String>
) -> List<&2, SourceDeclarations>:
  match all:
    case Nil{}:
      []
    case Con{SourceDeclarations{+path, declarations}, t}:
      get_kept(
        SourceDeclarations,
        get_has_text(paths, path),
        SourceDeclarations{path, declarations},
        get_declarations_in(t, paths)
      )

def get_is_place(scope: RuleScope, place: RunPlace) -> Bool:
  match scope place:
    case FileScope{} FileRun{on}:
      True{}
    case FileScope{} ProgramRun{c}:
      False{}
    case _ FileRun{on}:
      False{}
    case _ ProgramRun{c}:
      True{}

# The files where a run's findings can show: its file, or every linted file.
def get_place_paths(place: RunPlace, linted_paths: List<&2, String>) -> List<&2, String>:
  match place:
    case FileRun{on}:
      [get_source_path(on)]
    case ProgramRun{c}:
      linted_paths

# What a run sees: for a file run, its file and that file's declarations, from the first check; for a program run,
# its own check.
def get_place_check(place: RunPlace, first: BendCheck) -> BendCheck:
  match place first:
    case FileRun{+on} BendCheck{root, sources, failure, declarations, program_paths}:
      +path = get_source_path(on)
      BendCheck{on, sources, failure, get_declarations_in(declarations, [path]), program_paths}
    case ProgramRun{c} _:
      c

# The path of the first finding outside `path`, if any.
def get_astray(findings: List<&2, Finding>, +path: String) -> Maybe<&2, String>:
  match findings:
    case Nil{}:
      None{}
    case Con{Finding{severity, message, BendSourceSpan{+p, beg, end}, fixes}, t}:
      Bool.pick(Maybe<&2, String>, String.eq(p, path), get_astray(t, path), Some{p})

def get_file_findings(
  +id: String,
  severity: Maybe<&2, FindingSeverity>,
  +path: String,
  astray: Maybe<&2, String>,
  findings: List<&2, Finding>
) -> List<&2, RuleFinding>:
  match astray:
    case None{}:
      get_tagged(id, severity, findings)
    case Some{p}:
      [
        RuleFinding{
          "bend-lint/rule-crash",
          Finding{
            Error{},
            id
              ++ ": it reported in "
              ++ p
              ++ "; a rule of file scope reports only in "
              ++ path
              ++ ". Give it program scope to report in other files",
            BendSourceSpan{path, 0, 0},
            []
          }
        }
      ]

# A run's findings: a file run's, unless one is outside its file, which crashes the run; a program run's that are in
# a linted file.
def get_placed(
  +id: String,
  severity: Maybe<&2, FindingSeverity>,
  place: RunPlace,
  linted_paths: List<&2, String>,
  +findings: List<&2, Finding>
) -> List<&2, RuleFinding>:
  match place:
    case FileRun{BendSource{+path, text, lines}}:
      get_file_findings(id, severity, path, get_astray(findings, path), findings)
    case ProgramRun{c}:
      get_found_in(get_tagged(id, severity, findings), linted_paths)

def get_rule_run(
  hit: Bool,
  id: String,
  severity: Maybe<&2, FindingSeverity>,
  run: RuleInput -> List<&2, Finding>,
  place: RunPlace,
  linted_paths: List<&2, String>,
  input: RuleInput
) -> List<&2, RuleFinding>:
  match hit:
    case True{}:
      get_placed(id, severity, place, linted_paths, run(input))
    case False{}:
      []

# The severity the settings give rule `id`, if any.
def get_set_severity(settings: List<&2, RuleSetting>, +id: String) -> Maybe<&2, FindingSeverity>:
  match settings:
    case Nil{}:
      None{}
    case Con{RuleOn{+i, severity, options}, t}:
      Bool.pick(Maybe<&2, FindingSeverity>, String.eq(i, id), severity, get_set_severity(t, id))
    case Con{RuleOff{i}, t}:
      get_set_severity(t, id)

# The options the settings give rule `id`.
def get_set_options(settings: List<&2, RuleSetting>, +id: String) -> List<&2, OptionGiven>:
  match settings:
    case Nil{}:
      []
    case Con{RuleOn{+i, severity, options}, t}:
      Bool.pick(List<&2, OptionGiven>, String.eq(i, id), options, get_set_options(t, id))
    case Con{RuleOff{i}, t}:
      get_set_options(t, id)

# The ids the settings turn off.
def get_off_ids(settings: List<&2, RuleSetting>) -> List<&2, String>:
  match settings:
    case Nil{}:
      []
    case Con{RuleOff{id}, t}:
      id <> get_off_ids(t)
    case Con{RuleOn{id, severity, options}, t}:
      get_off_ids(t)

def get_given_value(
  given: List<&2, OptionGiven>,
  +key: String,
  default: OptionValue
) -> OptionValue:
  match given:
    case Nil{}:
      default
    case Con{OptionGiven{+k, +v}, t}:
      Bool.pick(OptionValue, String.eq(k, key), v, get_given_value(t, key, default))

# Each declared option, with its given value or its default.
def get_options(
  declared: List<&2, OptionDeclared>,
  +given: List<&2, OptionGiven>
) -> List<&2, OptionGiven>:
  match declared:
    case Nil{}:
      []
    case Con{OptionDeclared{+key, default, spec}, t}:
      OptionGiven{key, get_given_value(given, key, default)} <> get_options(t, given)

# The ids of the rules whose findings stand only when every check finds them.
def get_every_ids(rules: List<&1, Rule>) -> List<&2, String>:
  match rules:
    case Nil{}:
      []
    case Con{Rule{id, ProgramEveryScope{}, options, after, needs, run}, t}:
      id <> get_every_ids(t)
    case Con{r, t}:
      get_every_ids(t)

# The input of a run of a rule that declares `options` and `needs`, on the check `c`.
def get_rule_input(
  c: BendCheck,
  options: List<&2, OptionGiven>,
  prior: List<&2, RuleFinding>,
  +needs: List<&2, RuleNeed>
) -> RuleInput:
  match c:
    case BendCheck{root, sources, failure, declarations, program_paths}:
      RuleInput{
        root,
        sources,
        options,
        prior,
        get_given_declarations(
          get_needs(
            needs,
            DeclarationsNeed{}
          )
            || get_needs(needs, BodiesNeed{})
            || get_needs(needs, FactsNeed{}),
          declarations
        )
      }

def get_level_finding(
  r: Rule,
  +ready: List<&2, String>,
  +found: List<&2, RuleFinding>,
  +place: RunPlace,
  +first: BendCheck,
  +linted_paths: List<&2, String>,
  +settings: List<&2, RuleSetting>
) -> List<&2, RuleFinding>:
  match r:
    case Rule{+id, scope, options, after, needs, run}:
      get_rule_run(
        get_has_text(ready, id) && get_is_place(scope, place),
        id,
        get_set_severity(settings, id),
        run,
        place,
        linted_paths,
        get_rule_input(
          get_place_check(place, first),
          get_options(options, get_set_options(settings, id)),
          get_found_in(get_prior(found, after), get_place_paths(place, linted_paths)),
          needs
        )
      )

def get_level_findings(
  rules: List<&1, Rule>,
  +ready: List<&2, String>,
  +found: List<&2, RuleFinding>,
  +place: RunPlace,
  +first: BendCheck,
  +linted_paths: List<&2, String>,
  +settings: List<&2, RuleSetting>
) -> List<&2, RuleFinding>:
  match rules:
    case Nil{}:
      []
    case Con{r, rest}:
      a b = get_level_finding(
        r,
        ready,
        found,
        place,
        first,
        linted_paths,
        settings
      ) get_level_findings(rest, ready, found, place, first, linted_paths, settings)
      List.append(&2, RuleFinding, a, b)

# What the ready rules find in each place: a file rule on each linted file.
def get_places_findings(
  ~rules: Unit -> List<&1, Rule>,
  places: List<&2, RunPlace>,
  +ready: List<&2, String>,
  +found: List<&2, RuleFinding>,
  +first: BendCheck,
  +linted_paths: List<&2, String>,
  +settings: List<&2, RuleSetting>
) -> List<&2, RuleFinding>:
  match places:
    case Nil{}:
      []
    case Con{p, t}:
      a b = get_level_findings(
        rules(Unit{}),
        ready,
        found,
        p,
        first,
        linted_paths,
        settings
      ) get_places_findings(~rules, t, ready, found, first, linted_paths, settings)
      List.append(&2, RuleFinding, a, b)

# What the ready program rules find in each check, a list per check.
def get_program_runs(
  ~rules: Unit -> List<&1, Rule>,
  checks: List<&2, BendCheck>,
  +ready: List<&2, String>,
  +found: List<&2, RuleFinding>,
  +first: BendCheck,
  +linted_paths: List<&2, String>,
  +settings: List<&2, RuleSetting>
) -> List<&2, List<&2, RuleFinding>>:
  match checks:
    case Nil{}:
      []
    case Con{c, t}:
      a b = get_level_findings(
        rules(Unit{}),
        ready,
        found,
        ProgramRun{c},
        first,
        linted_paths,
        settings
      ) get_program_runs(~rules, t, ready, found, first, linted_paths, settings)
      a <> b

def get_file_places(linted: List<&2, BendSource>) -> List<&2, RunPlace>:
  match linted:
    case Nil{}:
      []
    case Con{s, t}:
      FileRun{s} <> get_file_places(t)

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

def get_severity_rank(s: FindingSeverity) -> U32:
  match s:
    case Error{}:
      0
    case Warning{}:
      1
    case Information{}:
      2
    case Hint{}:
      3

# Whether two runs found the same finding: the same code, severity and span.
def get_same_finding(a: RuleFinding, b: RuleFinding) -> Bool:
  match a b:
    case RuleFinding{
      x,
      Finding{s, m, BendSourceSpan{p, i, j}, f}
    } RuleFinding{y, Finding{t, n, BendSourceSpan{q, k, l}, g}}:
      String.eq(
        x,
        y
      )
        && U32.is_eq(get_severity_rank(s), get_severity_rank(t))
        && String.eq(p, q)
        && U32.is_eq(i, k)
        && U32.is_eq(j, l)

def get_has_finding(xs: List<&2, RuleFinding>, +f: RuleFinding) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, t}:
      get_same_finding(x, f) || get_has_finding(t, f)

def get_in_all(runs: List<&2, List<&2, RuleFinding>>, +f: RuleFinding) -> Bool:
  match runs:
    case Nil{}:
      True{}
    case Con{r, t}:
      get_has_finding(r, f) && get_in_all(t, f)

# The first check's findings that stand: an `every` rule's only when every other check found it too.
def get_merged.first(
  fs: List<&2, RuleFinding>,
  +rest: List<&2, List<&2, RuleFinding>>,
  +every: List<&2, String>
) -> List<&2, RuleFinding>:
  match fs:
    case Nil{}:
      []
    case Con{+f, t}:
      get_kept(
        RuleFinding,
        Bool.not(get_has_text(every, get_rule_id(f))) || get_in_all(rest, f),
        f,
        get_merged.first(t, rest, every)
      )

# `seen`, and the findings of a later check that are new: a `some` rule's, once.
def get_merged.run(
  fs: List<&2, RuleFinding>,
  +every: List<&2, String>,
  +seen: List<&2, RuleFinding>
) -> List<&2, RuleFinding>:
  match fs:
    case Nil{}:
      seen
    case Con{+f, t}:
      get_merged.run(
        t,
        every,
        Bool.pick(
          List<&2, RuleFinding>,
          get_has_text(every, get_rule_id(f)) || get_has_finding(seen, f),
          seen,
          List.append(&2, RuleFinding, seen, [f])
        )
      )

def get_merged.rest(
  runs: List<&2, List<&2, RuleFinding>>,
  +every: List<&2, String>,
  seen: List<&2, RuleFinding>
) -> List<&2, RuleFinding>:
  match runs:
    case Nil{}:
      seen
    case Con{r, t}:
      get_merged.rest(t, every, get_merged.run(r, every, seen))

# The program rules' findings over all checks: a `some` rule's when one check finds it, an `every` rule's when all do.
def get_merged(
  runs: List<&2, List<&2, RuleFinding>>,
  +every: List<&2, String>
) -> List<&2, RuleFinding>:
  match runs:
    case Nil{}:
      []
    case Con{first, +rest}:
      get_merged.rest(rest, every, get_merged.first(first, rest, every))

# The findings of the rules, level by level; `found` holds the findings so far, last first. File rules run on each
# linted file of the first check; program rules on each check, their findings merged.
def get_lint_findings(
  ~rules: Unit -> List<&1, Rule>,
  fuel: Nat,
  ready: List<&2, String>,
  +heads: List<&2, RuleHead>,
  +done: List<&2, String>,
  +found: List<&2, RuleFinding>,
  +files: List<&2, RunPlace>,
  +checks: List<&2, BendCheck>,
  +first: BendCheck,
  +linted_paths: List<&2, String>,
  +settings: List<&2, RuleSetting>,
  +every: List<&2, String>
) -> List<&2, RuleFinding>:
  match fuel ready:
    case 0n _:
      List.reverse(&2, RuleFinding, found)
    case 1n+k Nil{}:
      List.reverse(&2, RuleFinding, found)
    case 1n+k Con{+h, +t}:
      +now = List.append(&2, String, done, h <> t)
      a b = get_places_findings(
        ~rules,
        files,
        h <> t,
        found,
        first,
        linted_paths,
        settings
      ) get_program_runs(~rules, checks, h <> t, found, first, linted_paths, settings)
      get_lint_findings(
        ~rules,
        k,
        get_ready_ids(heads, now),
        heads,
        now,
        List.append(
          &2,
          RuleFinding,
          List.reverse(&2, RuleFinding, List.append(&2, RuleFinding, a, get_merged(b, every))),
          found
        ),
        files,
        checks,
        first,
        linted_paths,
        settings,
        every
      )

def get_failure_list(failure: Maybe<&2, RuleFinding>) -> List<&2, RuleFinding>:
  match failure:
    case None{}:
      []
    case Some{value}:
      [value]

# The rules a check can run: when it fails, only those that need nothing.
def get_check_heads(
  failure: Maybe<&2, RuleFinding>,
  heads: List<&2, RuleHead>
) -> List<&2, RuleHead>:
  match failure:
    case None{}:
      heads
    case Some{value}:
      get_needless_heads(heads)

# The linted files: with imports, every file of the program; else the named one.
def get_linted(
  imports: Bool,
  root: BendSource,
  sources: List<&2, BendSource>,
  program_paths: List<&2, String>
) -> List<&2, BendSource>:
  match imports:
    case True{}:
      get_sources_in(sources, program_paths)
    case False{}:
      [root]

# The findings, file by file in the order of `paths`.
def get_homed(paths: List<&2, String>, +found: List<&2, RuleFinding>) -> List<&2, RuleFinding>:
  match paths:
    case Nil{}:
      []
    case Con{p, t}:
      List.append(&2, RuleFinding, get_found_in(found, [p]), get_homed(t, found))

def get_source_at(sources: List<&2, BendSource>, +path: String) -> Maybe<&2, BendSource>:
  match sources:
    case Nil{}:
      None{}
    case Con{+s, t}:
      Bool.pick(
        Maybe<&2, BendSource>,
        String.eq(get_source_path(s), path),
        Some{s},
        get_source_at(t, path)
      )

# A finding with its Safe fixes checked against the text of its file, a linted one.
# Suppression
# ===========

# The comments of a text and whether each line holds code; a `#` inside a string or char literal is not a comment. A
# literal that spans lines makes each of them hold code.
def get_scan.go(
  s: String,
  mode: ScanMode,
  +at: U32,
  +line: U32,
  +here: Bool,
  +beg: U32,
  body: String,
  comments: List<&2, Comment>,
  code: List<&2, Bool>
) -> Scan:
  match s mode:
    case SNil{} ScanComment{}:
      Scan{
        List.reverse(&2, Comment, Comment{beg, at, line, here, String.reverse(body)} <> comments),
        List.reverse(&2, Bool, here <> code)
      }
    case SNil{} m:
      Scan{List.reverse(&2, Comment, comments), List.reverse(&2, Bool, here <> code)}
    case SCon{'\n', rest} ScanComment{}:
      get_scan.go(
        rest,
        ScanCode{},
        U32.inc(at),
        U32.inc(line),
        False{},
        beg,
        "",
        Comment{beg, at, line, here, String.reverse(body)} <> comments,
        here <> code
      )
    case SCon{c, rest} ScanComment{}:
      get_scan.go(rest, ScanComment{}, U32.inc(at), line, here, beg, SCon{c, body}, comments, code)
    case SCon{'\n', rest} ScanCode{}:
      get_scan.go(
        rest,
        ScanCode{},
        U32.inc(at),
        U32.inc(line),
        False{},
        beg,
        body,
        comments,
        here <> code
      )
    case SCon{'#', rest} ScanCode{}:
      get_scan.go(rest, ScanComment{}, U32.inc(at), line, here, at, "", comments, code)
    case SCon{'"', rest} ScanCode{}:
      get_scan.go(rest, ScanString{}, U32.inc(at), line, True{}, beg, body, comments, code)
    case SCon{'\'', rest} ScanCode{}:
      get_scan.go(rest, ScanChar{}, U32.inc(at), line, True{}, beg, body, comments, code)
    case SCon{' ', rest} ScanCode{}:
      get_scan.go(rest, ScanCode{}, U32.inc(at), line, here, beg, body, comments, code)
    case SCon{'\t', rest} ScanCode{}:
      get_scan.go(rest, ScanCode{}, U32.inc(at), line, here, beg, body, comments, code)
    case SCon{'\r', rest} ScanCode{}:
      get_scan.go(rest, ScanCode{}, U32.inc(at), line, here, beg, body, comments, code)
    case SCon{c, rest} ScanCode{}:
      get_scan.go(rest, ScanCode{}, U32.inc(at), line, True{}, beg, body, comments, code)
    case SCon{'\n', rest} ScanString{}:
      get_scan.go(
        rest,
        ScanString{},
        U32.inc(at),
        U32.inc(line),
        True{},
        beg,
        body,
        comments,
        True{} <> code
      )
    case SCon{'\\', rest} ScanString{}:
      get_scan.go(rest, ScanStringEscape{}, U32.inc(at), line, here, beg, body, comments, code)
    case SCon{'"', rest} ScanString{}:
      get_scan.go(rest, ScanCode{}, U32.inc(at), line, here, beg, body, comments, code)
    case SCon{c, rest} ScanString{}:
      get_scan.go(rest, ScanString{}, U32.inc(at), line, here, beg, body, comments, code)
    case SCon{'\n', rest} ScanStringEscape{}:
      get_scan.go(
        rest,
        ScanString{},
        U32.inc(at),
        U32.inc(line),
        True{},
        beg,
        body,
        comments,
        True{} <> code
      )
    case SCon{c, rest} ScanStringEscape{}:
      get_scan.go(rest, ScanString{}, U32.inc(at), line, here, beg, body, comments, code)
    case SCon{'\n', rest} ScanChar{}:
      get_scan.go(
        rest,
        ScanChar{},
        U32.inc(at),
        U32.inc(line),
        True{},
        beg,
        body,
        comments,
        True{} <> code
      )
    case SCon{'\\', rest} ScanChar{}:
      get_scan.go(rest, ScanCharEscape{}, U32.inc(at), line, here, beg, body, comments, code)
    case SCon{'\'', rest} ScanChar{}:
      get_scan.go(rest, ScanCode{}, U32.inc(at), line, here, beg, body, comments, code)
    case SCon{c, rest} ScanChar{}:
      get_scan.go(rest, ScanChar{}, U32.inc(at), line, here, beg, body, comments, code)
    case SCon{'\n', rest} ScanCharEscape{}:
      get_scan.go(
        rest,
        ScanChar{},
        U32.inc(at),
        U32.inc(line),
        True{},
        beg,
        body,
        comments,
        True{} <> code
      )
    case SCon{c, rest} ScanCharEscape{}:
      get_scan.go(rest, ScanChar{}, U32.inc(at), line, here, beg, body, comments, code)

def get_scan(text: String) -> Scan:
  get_scan.go(text, ScanCode{}, 0, 0, False{}, 0, "", [], [])

def get_drop_spaces(+s: String) -> String:
  match s:
    case SCon{' ', rest}:
      get_drop_spaces(rest)
    case SCon{'\t', rest}:
      get_drop_spaces(rest)
    case _:
      s

def get_starts_blank(s: String) -> Bool:
  match s:
    case SCon{' ', rest}:
      True{}
    case SCon{'\t', rest}:
      True{}
    case _:
      False{}

def get_code(c: Char) -> U32:
  match c:
    case Chr{code}:
      code

def get_is_between(+x: U32, lo: U32, hi: U32) -> Bool:
  U32.is_ge(x, lo) && U32.is_le(x, hi)

def get_is_word_char(c: Char) -> Bool:
  +x = get_code(c)
  get_is_between(
    x,
    48,
    57
  )
    || get_is_between(x, 65, 90)
    || get_is_between(x, 97, 122)
    || U32.is_eq(x, 95)

# The word characters `s` starts with.
def get_word.go(s: String, ok: Bool, c: Char) -> String:
  match s ok:
    case SCon{+d, rest} True{}:
      SCon{c, get_word.go(rest, get_is_word_char(d), d)}
    case SNil{} True{}:
      SCon{c, ""}
    case _ False{}:
      ""

def get_word(s: String) -> String:
  match s:
    case SCon{+c, rest}:
      get_word.go(rest, get_is_word_char(c), c)
    case SNil{}:
      ""

# What `s` starts with, up to a blank.
def get_token(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{' ', rest}:
      ""
    case SCon{'\t', rest}:
      ""
    case SCon{c, rest}:
      SCon{c, get_token(rest)}

def get_before_at(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{'@', rest}:
      ""
    case SCon{c, rest}:
      SCon{c, get_before_at(rest)}

def get_after_at(s: String) -> Maybe<&2, String>:
  match s:
    case SNil{}:
      None{}
    case SCon{'@', rest}:
      Some{rest}
    case SCon{c, rest}:
      get_after_at(rest)

def get_trim_end(s: String) -> String:
  String.reverse(get_drop_spaces(String.reverse(s)))

# Whether `s` holds a slash with a part before and after it, and no second one.
def get_is_rule_name(+s: String) -> Bool:
  +parts = String.split(s, '/')
  U32.is_eq(
    U32.from_nat(List.length(&2, String, parts)),
    2
  )
    && Bool.not(String.eq(String.take(s, 1n), "/"))
    && Bool.not(String.ends_with(s, "/"))

def get_pinned_ok(m: Maybe<&2, String>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{p}:
      Bool.not(String.eq(p, ""))

def get_reason(none: Bool, reason: String) -> Maybe<&2, String>:
  match none:
    case True{}:
      None{}
    case False{}:
      Some{reason}

# A directive's parts, as `bend-lint: <action>-<scope> <rule>[@severity] [-- <reason>]` spells them in `body`, the
# text after `#`; none when it does not follow that form.
def get_directive_parts(body: String) -> Maybe<&2, DirectiveParts>:
  +b1 = get_drop_spaces(String.drop(get_drop_spaces(body), 10n))
  +action = get_word(b1)
  +r1 = String.drop(b1, String.length(action))
  +r2 = String.drop(r1, 1n)
  +scope = get_word(r2)
  +r3 = String.drop(r2, String.length(scope))
  +r4 = get_drop_spaces(r3)
  +token = get_token(r4)
  +r6 = get_drop_spaces(String.drop(r4, String.length(token)))
  +rule = get_before_at(token)
  +pinned = get_after_at(token)
  +tail = String.drop(r6, 2n)
  +reason = get_trim_end(get_drop_spaces(tail))
  Bool.pick(
    Maybe<&2, DirectiveParts>,
    Bool.not(
      String.eq(action, "")
    )
      && String.starts_with(r1, "-")
      && Bool.not(String.eq(scope, ""))
      && get_starts_blank(r3)
      && get_is_rule_name(rule)
      && get_pinned_ok(pinned)
      && (
        String.eq(
          r6,
          ""
        )
          || (
            String.starts_with(
              r6,
              "--"
            )
              && get_starts_blank(tail)
              && Bool.not(String.eq(reason, ""))
          )
      ),
    Some{DirectiveParts{action, scope, rule, pinned, get_reason(String.eq(r6, ""), reason)}},
    None{}
  )

def get_directive_syntax() -> String:
  "Write `# bend-lint: <disable|expect>-<file|begin|end|next|line> <rule>[@severity] -- <reason>`."

def get_first_problem(problems: List<&2, Maybe<&2, String>>) -> Maybe<&2, String>:
  match problems:
    case Nil{}:
      None{}
    case Con{Some{why}, t}:
      Some{why}
    case Con{None{}, t}:
      get_first_problem(t)

def get_problem_if(hit: Bool, why: String) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{why}
    case False{}:
      None{}

def get_severity_named(+name: String) -> Maybe<&2, FindingSeverity>:
  Bool.pick(
    Maybe<&2, FindingSeverity>,
    String.eq(name, "error"),
    Some{Error{}},
    Bool.pick(
      Maybe<&2, FindingSeverity>,
      String.eq(name, "warning"),
      Some{Warning{}},
      Bool.pick(
        Maybe<&2, FindingSeverity>,
        String.eq(name, "information"),
        Some{Information{}},
        Bool.pick(Maybe<&2, FindingSeverity>, String.eq(name, "hint"), Some{Hint{}}, None{})
      )
    )
  )

def get_is_severity_or_none(m: Maybe<&2, String>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{+p}:
      Maybe.is_some(&2, FindingSeverity, get_severity_named(p))

def get_pinned_shown(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      ""
    case Some{p}:
      p

def get_pinned_severity(m: Maybe<&2, String>) -> Maybe<&2, FindingSeverity>:
  match m:
    case None{}:
      None{}
    case Some{p}:
      get_severity_named(p)

def get_directive_checked.made(
  wrong: Maybe<&2, String>,
  action: String,
  scope: String,
  rule: String,
  pinned: Maybe<&2, String>,
  comment: Comment
) -> DirectiveRead:
  match wrong:
    case Some{why}:
      DirectiveWrong{why, comment}
    case None{}:
      DirectiveFound{Directive{action, scope, rule, get_pinned_severity(pinned), comment}}

def get_directive_checked(
  +action: String,
  +scope: String,
  +rule: String,
  +pinned: Maybe<&2, String>,
  +reason: Maybe<&2, String>,
  +comment: Comment,
  +known: List<&2, String>
) -> DirectiveRead:
  match comment:
    case Comment{beg, end, line, +trailing, body}:
      +wrong = get_first_problem(
        [
          get_problem_if(
            Bool.not(
              get_has_text(["disable", "expect"], action)
            )
              || Bool.not(get_has_text(["file", "begin", "end", "next", "line"], scope)),
            get_directive_syntax()
          ),
          get_problem_if(
            Bool.not(get_is_severity_or_none(pinned)),
            get_pinned_shown(pinned) ++ " is not a severity."
          ),
          get_problem_if(
            String.eq(action, "disable") && Maybe.is_some(&2, String, pinned),
            "A disable takes no severity."
          ),
          get_problem_if(
            String.eq(action, "expect") && Maybe.is_none(&2, String, pinned),
            "An expect pins a severity: " ++ rule ++ "@..."
          ),
          get_problem_if(
            String.eq(scope, "end") && Maybe.is_some(&2, String, reason),
            "An end takes no reason; the begin has it."
          ),
          get_problem_if(
            Bool.not(String.eq(scope, "end")) && Maybe.is_none(&2, String, reason),
            "A reason is required, after `--`."
          ),
          get_problem_if(
            String.eq(scope, "line") && Bool.not(trailing),
            "A line directive must follow code on its line."
          ),
          get_problem_if(
            String.starts_with(rule, "bend/") || String.starts_with(rule, "bend-lint/"),
            rule ++ " findings cannot be suppressed."
          ),
          get_problem_if(Bool.not(get_has_text(known, rule)), "There is no rule " ++ rule ++ ".")
        ]
      )
      get_directive_checked.made(
        wrong,
        action,
        scope,
        rule,
        pinned,
        Comment{beg, end, line, trailing, body}
      )

def get_directive_read(
  parts: Maybe<&2, DirectiveParts>,
  comment: Comment,
  +known: List<&2, String>
) -> DirectiveRead:
  match parts:
    case None{}:
      DirectiveWrong{get_directive_syntax(), comment}
    case Some{DirectiveParts{action, scope, rule, pinned, reason}}:
      get_directive_checked(action, scope, rule, pinned, reason, comment, known)

def get_is_directive(body: String) -> Bool:
  String.starts_with(get_drop_spaces(body), "bend-lint:")

# The directives among `comments`, and what is wrong with the ones that are not right.
def get_directives_read(
  comments: List<&2, Comment>,
  +known: List<&2, String>
) -> List<&2, DirectiveRead>:
  match comments:
    case Nil{}:
      []
    case Con{Comment{beg, end, line, trailing, +body}, t}:
      +rest = get_directives_read(t, known)
      Bool.pick(
        List<&2, DirectiveRead>,
        get_is_directive(body),
        get_directive_read(
          get_directive_parts(body),
          Comment{beg, end, line, trailing, body},
          known
        )
          <> rest,
        rest
      )

def get_directive_found(rs: List<&2, DirectiveRead>) -> List<&2, Directive>:
  match rs:
    case Nil{}:
      []
    case Con{DirectiveFound{d}, t}:
      d <> get_directive_found(t)
    case Con{DirectiveWrong{why, c}, t}:
      get_directive_found(t)

def get_directive_finding(+path: String, why: String, c: Comment) -> RuleFinding:
  match c:
    case Comment{beg, end, line, trailing, body}:
      RuleFinding{"bend-lint/directive", Finding{Error{}, why, BendSourceSpan{path, beg, end}, []}}

def get_directive_wrong(rs: List<&2, DirectiveRead>, +path: String) -> List<&2, RuleFinding>:
  match rs:
    case Nil{}:
      []
    case Con{DirectiveWrong{why, c}, t}:
      get_directive_finding(path, why, c) <> get_directive_wrong(t, path)
    case Con{DirectiveFound{d}, t}:
      get_directive_wrong(t, path)

def get_same_severity(a: Maybe<&2, FindingSeverity>, b: Maybe<&2, FindingSeverity>) -> Bool:
  match a b:
    case None{} None{}:
      True{}
    case Some{x} Some{y}:
      U32.is_eq(get_severity_rank(x), get_severity_rank(y))
    case _ _:
      False{}

# The open begin of `key` that an end closes: the latest; it closes it when their severities agree.
def get_top_open(open: List<&2, OpenBegin>, +key: String) -> Maybe<&2, OpenBegin>:
  match open:
    case Nil{}:
      None{}
    case Con{OpenBegin{+k, i, s, c}, t}:
      Bool.pick(
        Maybe<&2, OpenBegin>,
        String.eq(k, key),
        Some{OpenBegin{k, i, s, c}},
        get_top_open(t, key)
      )

def get_without_top(open: List<&2, OpenBegin>, +key: String) -> List<&2, OpenBegin>:
  match open:
    case Nil{}:
      []
    case Con{OpenBegin{+k, i, s, c}, +t}:
      Bool.pick(
        List<&2, OpenBegin>,
        String.eq(k, key),
        t,
        OpenBegin{k, i, s, c} <> get_without_top(t, key)
      )

def get_comment_line(c: Comment) -> U32:
  match c:
    case Comment{beg, end, line, trailing, body}:
      line

def get_closes(top: Maybe<&2, OpenBegin>, severity: Maybe<&2, FindingSeverity>) -> Bool:
  match top:
    case Some{OpenBegin{k, i, s, c}}:
      get_same_severity(s, severity)
    case None{}:
      False{}

def get_closed_of(top: Maybe<&2, OpenBegin>, +line: U32) -> Closed:
  match top:
    case Some{OpenBegin{k, i, s, c}}:
      Closed{i, line}
    case None{}:
      Closed{0n, line}

# The rule of a key: what follows its first blank.
def get_rule_of_key(key: String) -> String:
  match key:
    case SNil{}:
      ""
    case SCon{' ', rest}:
      rest
    case SCon{c, rest}:
      get_rule_of_key(rest)

def get_never_closed(open: List<&2, OpenBegin>, +path: String) -> List<&2, RuleFinding>:
  match open:
    case Nil{}:
      []
    case Con{OpenBegin{key, i, s, c}, t}:
      List.append(
        &2,
        RuleFinding,
        get_never_closed(t, path),
        [
          get_directive_finding(
            path,
            "This begin of " ++ get_rule_of_key(key) ++ " is never closed.",
            c
          )
        ]
      )

# The ends of the begins, and the ends that close none: each end closes the latest open begin of its action and rule,
# when their severities agree.
def get_paired(
  ds: List<&2, Directive>,
  +i: Nat,
  +open: List<&2, OpenBegin>,
  +closed: List<&2, Closed>,
  +wrong: List<&2, RuleFinding>,
  +path: String
) -> (List<&2, Closed> & List<&2, RuleFinding>):
  match ds:
    case Nil{}:
      (closed, List.append(&2, RuleFinding, wrong, get_never_closed(open, path)))
    case Con{Directive{+action, "begin", +rule, severity, comment}, t}:
      get_paired(
        t,
        (1n + i: Nat),
        OpenBegin{action ++ " " ++ rule, i, severity, comment} <> open,
        closed,
        wrong,
        path
      )
    case Con{Directive{+action, "end", +rule, +severity, +comment}, t}:
      +key = action ++ " " ++ rule
      +top = get_top_open(open, key)
      +closes = get_closes(top, severity)
      get_paired(
        t,
        (1n + i: Nat),
        Bool.pick(List<&2, OpenBegin>, closes, get_without_top(open, key), open),
        Bool.pick(
          List<&2, Closed>,
          closes,
          get_closed_of(top, get_comment_line(comment)) <> closed,
          closed
        ),
        Bool.pick(
          List<&2, RuleFinding>,
          closes,
          wrong,
          List.append(
            &2,
            RuleFinding,
            wrong,
            [get_directive_finding(path, "This end closes no begin of " ++ rule ++ ".", comment)]
          )
        ),
        path
      )
    case Con{d, t}:
      get_paired(t, (1n + i: Nat), open, closed, wrong, path)

def get_closed_line(closed: List<&2, Closed>, +i: Nat, +last: U32) -> U32:
  match closed:
    case Nil{}:
      last
    case Con{Closed{+j, +line}, t}:
      Bool.pick(U32, Nat.is_eq(j, i), line, get_closed_line(t, i, last))

# The first line after `l` that holds code, if any; `code` holds whether each line from `at` on does.
def get_following(code: List<&2, Bool>, +l: U32, +at: U32) -> Maybe<&2, U32>:
  match code:
    case Nil{}:
      None{}
    case Con{h, t}:
      Bool.pick(Maybe<&2, U32>, h && U32.is_lt(l, at), Some{at}, get_following(t, l, U32.inc(at)))

def get_cover_next(
  i: Nat,
  d: Directive,
  m: Maybe<&2, U32>,
  rest: List<&2, Covering>
) -> List<&2, Covering>:
  match m:
    case Some{+x}:
      Covering{i, d, x, x} <> rest
    case None{}:
      Covering{i, d, 1, 0} <> rest

# The lines each directive covers: file all of them, line its own, next the next line with code, begin those up to
# its end (or the last line); an end covers none.
def get_coverings(
  ds: List<&2, Directive>,
  +i: Nat,
  +closed: List<&2, Closed>,
  +code: List<&2, Bool>,
  +last: U32
) -> List<&2, Covering>:
  match ds:
    case Nil{}:
      []
    case Con{Directive{action, +scope, rule, severity, +comment}, t}:
      +l = get_comment_line(comment)
      +d: Directive = Directive{action, scope, rule, severity, comment}
      +rest = get_coverings(t, (1n + i: Nat), closed, code, last)
      Bool.pick(
        List<&2, Covering>,
        String.eq(scope, "file"),
        Covering{i, d, 0, last} <> rest,
        Bool.pick(
          List<&2, Covering>,
          String.eq(scope, "line"),
          Covering{i, d, l, l} <> rest,
          Bool.pick(
            List<&2, Covering>,
            String.eq(scope, "next"),
            get_cover_next(i, d, get_following(code, l, 0), rest),
            Bool.pick(
              List<&2, Covering>,
              String.eq(scope, "begin"),
              Covering{i, d, l, get_closed_line(closed, i, last)} <> rest,
              rest
            )
          )
        )
      )

# Text order: less, the same, or more, as 0, 1, 2.
def get_text_order(a: String, b: String) -> U32:
  match a b:
    case SNil{} SNil{}:
      1
    case SNil{} _:
      0
    case _ SNil{}:
      2
    case SCon{x, s} SCon{y, t}:
      +p = get_code(x)
      +q = get_code(y)
      Bool.pick(U32, U32.is_lt(p, q), 0, Bool.pick(U32, U32.is_lt(q, p), 2, get_text_order(s, t)))

def get_severity_name(s: FindingSeverity) -> String:
  match s:
    case Error{}:
      "error"
    case Warning{}:
      "warning"
    case Information{}:
      "information"
    case Hint{}:
      "hint"

def get_severity_key(m: Maybe<&2, FindingSeverity>) -> String:
  match m:
    case None{}:
      ""
    case Some{s}:
      get_severity_name(s)

# Whether `a` comes before `b`, or with it, when directives stack: by rule, then severity, then keyword.
def get_in_order(a: Directive, b: Directive) -> Bool:
  match a b:
    case Directive{x, s, r, v, c} Directive{y, t, q, w, d}:
      +rules = get_text_order(r, q)
      +severities = get_text_order(get_severity_key(v), get_severity_key(w))
      U32.is_lt(
        rules,
        1
      )
        || (
          U32.is_eq(
            rules,
            1
          )
            && (
              U32.is_lt(
                severities,
                1
              )
                || (
                  U32.is_eq(
                    severities,
                    1
                  )
                    && U32.is_lt(get_text_order(x ++ "-" ++ s, y ++ "-" ++ t), 2)
                )
            )
        )

def get_inserted(+d: Directive, sorted: List<&2, Directive>) -> List<&2, Directive>:
  match sorted:
    case Nil{}:
      [d]
    case Con{+h, +t}:
      Bool.pick(List<&2, Directive>, get_in_order(h, d), h <> get_inserted(d, t), d <> h <> t)

def get_sorted(ds: List<&2, Directive>, done: List<&2, Directive>) -> List<&2, Directive>:
  match ds:
    case Nil{}:
      done
    case Con{d, t}:
      get_sorted(t, get_inserted(d, done))

def get_comment_beg(d: Directive) -> U32:
  match d:
    case Directive{action, scope, rule, severity, Comment{beg, end, line, trailing, body}}:
      beg

def get_same_order(a: List<&2, Directive>, b: List<&2, Directive>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Con{x, s} Con{y, t}:
      U32.is_eq(get_comment_beg(x), get_comment_beg(y)) && get_same_order(s, t)
    case _ _:
      False{}

# The edits that put a run in order, last first: each replaces a comment with the one that belongs there.
def get_sort_edits(
  run: List<&2, Directive>,
  sorted: List<&2, Directive>,
  +path: String,
  done: List<&2, FixEdit>
) -> List<&2, FixEdit>:
  match run sorted:
    case Con{
      Directive{a, s, r, v, Comment{beg, end, line, trailing, body}},
      rt
    } Con{Directive{b, u, q, w, Comment{x, y, z, k, put}}, st}:
      get_sort_edits(rt, st, path, ReplaceText{BendSourceSpan{path, beg, end}, "#" ++ put} <> done)
    case _ _:
      done

def get_run_end(run: List<&2, Directive>, end: U32) -> U32:
  match run:
    case Nil{}:
      end
    case Con{Directive{a, s, r, v, Comment{b, e, line, trailing, body}}, t}:
      get_run_end(t, e)

def get_run_beg(run: List<&2, Directive>) -> U32:
  match run:
    case Con{d, t}:
      get_comment_beg(d)
    case Nil{}:
      0

def get_unsorted_run(+run: List<&2, Directive>, +path: String) -> List<&2, RuleFinding>:
  +sorted = get_sorted(run, [])
  Bool.pick(
    List<&2, RuleFinding>,
    get_same_order(run, sorted),
    [],
    [
      RuleFinding{
        "bend-lint/directive",
        Finding{
          Error{},
          "Directives that stack must be in order: by rule, then severity, then keyword.",
          BendSourceSpan{path, get_run_beg(run), get_run_end(run, 0)},
          [Fix{"Sort the directives", Safe{}, get_sort_edits(run, sorted, path, [])}]
        }
      }
    ]
  )

def get_directive_comment(d: Directive) -> Comment:
  match d:
    case Directive{action, scope, rule, severity, comment}:
      comment

def get_is_trailing(d: Directive) -> Bool:
  match d:
    case Directive{action, scope, rule, severity, Comment{b, e, line, trailing, body}}:
      trailing

# The runs of directives on consecutive comment-only lines, each in file order: `run` is the current one, last first,
# `last` its last line.
def get_runs(
  ds: List<&2, Directive>,
  +run: List<&2, Directive>,
  +last: U32,
  +done: List<&2, List<&2, Directive>>
) -> List<&2, List<&2, Directive>>:
  match ds:
    case Nil{}:
      List.reverse(&2, List<&2, Directive>, List.reverse(&2, Directive, run) <> done)
    case Con{+d, t}:
      +l = get_comment_line(get_directive_comment(d))
      +joins = U32.is_eq(l, U32.inc(last)) && Bool.not(List.is_empty(&2, Directive, run))
      get_runs(
        t,
        Bool.pick(
          List<&2, Directive>,
          get_is_trailing(d),
          [],
          Bool.pick(List<&2, Directive>, joins, d <> run, [d])
        ),
        l,
        Bool.pick(
          List<&2, List<&2, Directive>>,
          joins && Bool.not(get_is_trailing(d)),
          done,
          List.reverse(&2, Directive, run) <> done
        )
      )

def get_unsorted(runs: List<&2, List<&2, Directive>>, +path: String) -> List<&2, RuleFinding>:
  match runs:
    case Nil{}:
      []
    case Con{r, t}:
      List.append(&2, RuleFinding, get_unsorted_run(r, path), get_unsorted(t, path))

def get_file_directives.paired(
  +path: String,
  lines: List<&2, String>,
  +found: List<&2, Directive>,
  read: List<&2, DirectiveRead>,
  +code: List<&2, Bool>,
  paired: List<&2, Closed> & List<&2, RuleFinding>
) -> FileDirectives:
  match paired:
    case (closed, unpaired):
      FileDirectives{
        path,
        lines,
        get_coverings(
          found,
          0n,
          closed,
          code,
          U32.sub(U32.from_nat(List.length(&2, Bool, code)), 1)
        ),
        List.append(
          &2,
          RuleFinding,
          List.append(&2, RuleFinding, get_directive_wrong(read, path), unpaired),
          get_unsorted(get_runs(found, [], 0, []), path)
        )
      }

def get_file_directives.scanned(
  +path: String,
  lines: List<&2, String>,
  scan: Scan,
  +known: List<&2, String>
) -> FileDirectives:
  match scan:
    case Scan{comments, code}:
      +read = get_directives_read(comments, known)
      +found = get_directive_found(read)
      get_file_directives.paired(
        path,
        lines,
        found,
        read,
        code,
        get_paired(found, 0n, [], [], [], path)
      )

# What the directives of the linted file `source` say.
def get_file_directives(source: BendSource, +known: List<&2, String>) -> FileDirectives:
  match source:
    case BendSource{path, text, lines}:
      get_file_directives.scanned(path, lines, get_scan(text), known)

# The line of offset `at` in a file whose lines are `lines`, from 0; `beg` is where the first of them starts.
def get_line_at(lines: List<&2, String>, +at: U32, +beg: U32, +row: U32) -> U32:
  match lines:
    case Nil{}:
      row
    case Con{h, t}:
      +next = U32.add(U32.add(beg, U32.from_nat(String.length(h))), 1)
      Bool.pick(U32, U32.is_lt(at, next), row, get_line_at(t, at, next, U32.inc(row)))

def get_directives_of(files: List<&2, FileDirectives>, +path: String) -> Maybe<&2, FileDirectives>:
  match files:
    case Nil{}:
      None{}
    case Con{FileDirectives{+p, lines, coverings, wrong}, t}:
      Bool.pick(
        Maybe<&2, FileDirectives>,
        String.eq(p, path),
        Some{FileDirectives{p, lines, coverings, wrong}},
        get_directives_of(t, path)
      )

# The directives of `coverings` that cover a finding of rule `rule`, severity `severity`, on line `row`.
def get_hits(
  coverings: List<&2, Covering>,
  +rule: String,
  +severity: FindingSeverity,
  +row: U32
) -> List<&2, Nat>:
  match coverings:
    case Nil{}:
      []
    case Con{Covering{+i, Directive{+action, scope, +r, +s, c}, +from, +to}, t}:
      get_kept(
        Nat,
        String.eq(
          r,
          rule
        )
          && U32.is_le(from, row)
          && U32.is_le(row, to)
          && (String.eq(action, "disable") || get_same_severity(s, Some{severity})),
        i,
        get_hits(t, rule, severity, row)
      )

def get_finding_hits(
  m: Maybe<&2, FileDirectives>,
  +rule: String,
  +severity: FindingSeverity,
  +at: U32
) -> List<&2, Nat>:
  match m:
    case None{}:
      []
    case Some{FileDirectives{path, lines, coverings, wrong}}:
      get_hits(coverings, rule, severity, get_line_at(lines, at, 0, 0))

def get_uses(hits: List<&2, Nat>, +path: String) -> List<&2, Used>:
  match hits:
    case Nil{}:
      []
    case Con{i, t}:
      Used{path, i} <> get_uses(t, path)

def get_split(
  +f: RuleFinding,
  hits: List<&2, Nat>,
  +path: String,
  s: SuppressState
) -> SuppressState:
  match hits s:
    case Nil{} SuppressState{kept, suppressed, used}:
      SuppressState{f <> kept, suppressed, used}
    case Con{h, t} SuppressState{kept, suppressed, used}:
      SuppressState{kept, f <> suppressed, List.append(&2, Used, get_uses(h <> t, path), used)}

# The findings split into those that stay and those a directive covers, and the directives that covered one; each
# list last first.
def get_suppressing(
  findings: List<&2, RuleFinding>,
  +files: List<&2, FileDirectives>,
  s: SuppressState
) -> SuppressState:
  match findings:
    case Nil{}:
      s
    case Con{
      RuleFinding{+rule, Finding{+severity, message, BendSourceSpan{+path, +beg, end}, fixes}},
      t
    }:
      get_suppressing(
        t,
        files,
        get_split(
          RuleFinding{rule, Finding{severity, message, BendSourceSpan{path, beg, end}, fixes}},
          get_finding_hits(get_directives_of(files, path), rule, severity, beg),
          path,
          s
        )
      )

def get_is_used(used: List<&2, Used>, +path: String, +i: Nat) -> Bool:
  match used:
    case Nil{}:
      False{}
    case Con{Used{p, j}, t}:
      (String.eq(p, path) && Nat.is_eq(j, i)) || get_is_used(t, path, i)

def get_unmet_finding(+path: String, d: Directive) -> RuleFinding:
  match d:
    case Directive{"expect", scope, rule, severity, Comment{beg, end, line, trailing, body}}:
      RuleFinding{
        "bend-lint/unmet-expectation",
        Finding{
          Error{},
          "Expected a "
            ++ rule
            ++ "@"
            ++ get_severity_key(severity)
            ++ " finding on the lines this covers; none.",
          BendSourceSpan{path, beg, end},
          []
        }
      }
    case Directive{action, scope, rule, severity, Comment{beg, end, line, trailing, body}}:
      RuleFinding{
        "bend-lint/unused-disable",
        Finding{
          Warning{},
          "This disables " ++ rule ++ ", but nothing on the lines it covers needs it.",
          BendSourceSpan{path, beg, end},
          []
        }
      }

def get_directive_rule(d: Directive) -> String:
  match d:
    case Directive{action, scope, rule, severity, comment}:
      rule

# The directives of a file that covered nothing, of rules that ran to their end there (`ran`, and not `crashed`).
def get_unmet(
  coverings: List<&2, Covering>,
  +path: String,
  +used: List<&2, Used>,
  +ran: List<&2, String>,
  +crashed: List<&2, String>
) -> List<&2, RuleFinding>:
  match coverings:
    case Nil{}:
      []
    case Con{Covering{+i, +d, from, to}, t}:
      +rule = get_directive_rule(d)
      get_kept(
        RuleFinding,
        Bool.not(
          get_is_used(used, path, i)
        )
          && get_has_text(ran, rule)
          && Bool.not(get_has_text(crashed, path ++ " " ++ rule)),
        get_unmet_finding(path, d),
        get_unmet(t, path, used, ran, crashed)
      )

def get_files_unmet(
  files: List<&2, FileDirectives>,
  +used: List<&2, Used>,
  +ran: List<&2, String>,
  +crashed: List<&2, String>
) -> List<&2, RuleFinding>:
  match files:
    case Nil{}:
      []
    case Con{FileDirectives{path, lines, coverings, wrong}, t}:
      List.append(
        &2,
        RuleFinding,
        get_unmet(coverings, path, used, ran, crashed),
        get_files_unmet(t, used, ran, crashed)
      )

def get_files_wrong(files: List<&2, FileDirectives>) -> List<&2, RuleFinding>:
  match files:
    case Nil{}:
      []
    case Con{FileDirectives{path, lines, coverings, wrong}, t}:
      List.append(&2, RuleFinding, wrong, get_files_wrong(t))

# The rule a crash finding names: its message up to the first colon.
def get_crash_rule(message: String) -> String:
  match message:
    case SNil{}:
      ""
    case SCon{':', rest}:
      ""
    case SCon{c, rest}:
      SCon{c, get_crash_rule(rest)}

# The file and rule of each rule that crashed, as `path rule`.
def get_crashed(findings: List<&2, RuleFinding>) -> List<&2, String>:
  match findings:
    case Nil{}:
      []
    case Con{
      RuleFinding{
        "bend-lint/rule-crash",
        Finding{s, message, BendSourceSpan{path, beg, end}, fixes}
      },
      t
    }:
      (path ++ " " ++ get_crash_rule(message)) <> get_crashed(t)
    case Con{f, t}:
      get_crashed(t)

def get_with_directives(
  +source: BendSource,
  +known: List<&2, String>,
  +done: List<&2, FileDirectives>
) -> List<&2, FileDirectives>:
  match source:
    case BendSource{path, text, lines}:
      Bool.pick(
        List<&2, FileDirectives>,
        String.contains(text, "bend-lint:"),
        get_file_directives(source, known) <> done,
        done
      )

def get_linted_directives(
  linted: List<&2, BendSource>,
  +known: List<&2, String>
) -> List<&2, FileDirectives>:
  match linted:
    case Nil{}:
      []
    case Con{s, t}:
      get_with_directives(s, known, get_linted_directives(t, known))

def get_suppression.split(
  s: SuppressState,
  +files: List<&2, FileDirectives>,
  +ran: List<&2, String>,
  +crashed: List<&2, String>
) -> List<&2, RuleFinding>
  & List<&2, RuleFinding>:
  match s:
    case SuppressState{kept, suppressed, +used}:
      (
        List.append(
          &2,
          RuleFinding,
          List.append(&2, RuleFinding, List.reverse(&2, RuleFinding, kept), get_files_wrong(files)),
          get_files_unmet(files, used, ran, crashed)
        ),
        List.reverse(&2, RuleFinding, suppressed)
      )

# The findings that stay, with the findings about the directives of the linted files, and those a directive covers.
# A directive that covered nothing is reported only where its rule ran to its end (`ran`, minus the rules that
# crashed).
def get_suppression(
  +findings: List<&2, RuleFinding>,
  linted: List<&2, BendSource>,
  +known: List<&2, String>,
  +ran: List<&2, String>
) -> List<&2, RuleFinding>
  & List<&2, RuleFinding>:
  +files = get_linted_directives(linted, known)
  get_suppression.split(
    get_suppressing(findings, files, SuppressState{[], [], []}),
    files,
    ran,
    get_crashed(findings)
  )

def get_check_failures(checks: List<&2, BendCheck>) -> List<&2, RuleFinding>:
  match checks:
    case Nil{}:
      []
    case Con{BendCheck{root, sources, failure, declarations, program_paths}, t}:
      List.append(&2, RuleFinding, get_failure_list(failure), get_check_failures(t))

def get_rules_off(partial: Bool, +every: List<&2, String>) -> List<&2, String>:
  match partial:
    case True{}:
      every
    case False{}:
      []

# The report on the file at `named`, over `checks`, the first holding the file: `failures` are the failed checks'
# findings, and `partial` tells whether an entry that reads the file failed its check, so that no `every` rule runs.
# The directives of the linted files then suppress findings, and their problems are findings too.
def get_lint_report.made(
  split: List<&2, RuleFinding> & List<&2, RuleFinding>,
  linted: List<&2, BendSource>
) -> LintReport:
  match split:
    case (findings, suppressed):
      LintReport{findings, suppressed, linted}

def get_rule_ids(rules: List<&1, Rule>) -> List<&2, String>:
  get_head_ids(get_rule_heads(rules))

def get_lint_report(
  ~rules: Unit -> List<&1, Rule>,
  checks: List<&2, BendCheck>,
  failures: List<&2, RuleFinding>,
  partial: Bool,
  +named: String,
  config: LintConfig
) -> LintReport:
  match checks config:
    case Con{
      BendCheck{+root, +sources, +failure, +declarations, +program_paths},
      rest
    } LintConfig{load, entries, imports, +settings}:
      +first: BendCheck = BendCheck{root, sources, failure, declarations, program_paths}
      +own = Maybe.default(&2, BendSource, get_source_at(sources, named), root)
      +linted = get_linted(imports, own, sources, program_paths)
      +linted_paths = get_source_paths(linted)
      +heads = get_check_heads(failure, get_rule_heads(rules(Unit{})))
      +every = get_every_ids(rules(Unit{}))
      +done = List.append(&2, String, get_off_ids(settings), get_rules_off(partial, every))
      get_lint_report.made(
        get_suppression(
          List.append(
            &2,
            RuleFinding,
            failures,
            get_homed(
              linted_paths,
              get_lint_findings(
                ~rules,
                (1n + List.length(&2, RuleHead, heads): Nat),
                get_ready_ids(heads, done),
                heads,
                done,
                [],
                get_file_places(linted),
                first <> rest,
                first,
                linted_paths,
                settings,
                every
              )
            )
          ),
          linted,
          get_rule_ids(rules(Unit{})),
          get_texts_where(False{}, get_head_ids(heads), done)
        ),
        linted
      )
    case Nil{} c:
      LintReport{failures, [], []}

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

def get_linter_term_span(span: Maybe<&2, BendSourceSpan>) -> Maybe<&2, BendSourceSpan>:
  match span:
    case None{}:
      None{}
    case Some{value}:
      Some{get_linter_span(value)}

def get_linter_term(term: BendTerm) -> BendTerm:
  match term:
    case VariableTerm{name, span}:
      VariableTerm{name, get_linter_term_span(span)}
    case ReferenceTerm{name, span}:
      ReferenceTerm{name, get_linter_term_span(span)}
    case CallTerm{head, arguments, span}:
      h a = get_linter_term(head) get_linter_term(arguments)
      CallTerm{h, a, get_linter_term_span(span)}
    case LetTerm{names, values, body, span}:
      v b = get_linter_term(values) get_linter_term(body)
      LetTerm{names, v, b, get_linter_term_span(span)}
    case LambdaTerm{name, body, span}:
      LambdaTerm{name, get_linter_term(body), get_linter_term_span(span)}
    case ConstructorTerm{name, fields, span}:
      ConstructorTerm{name, get_linter_term(fields), get_linter_term_span(span)}
    case LiteralTerm{shown, span}:
      LiteralTerm{shown, get_linter_term_span(span)}
    case AnnotatedTerm{value, annotation, span}:
      v a = get_linter_term(value) get_linter_term(annotation)
      AnnotatedTerm{v, a, get_linter_term_span(span)}
    case ForallTerm{name, quantity, domain, body, span}:
      d b = get_linter_term(domain) get_linter_term(body)
      ForallTerm{name, quantity, d, b, get_linter_term_span(span)}
    case SortTerm{level, span}:
      SortTerm{get_linter_term(level), get_linter_term_span(span)}
    case DatatypeTerm{name, arguments, span}:
      DatatypeTerm{name, get_linter_term(arguments), get_linter_term_span(span)}
    case OtherTerm{parts, span}:
      OtherTerm{get_linter_term(parts), get_linter_term_span(span)}
    case CheckedTerm{term, fact}:
      CheckedTerm{get_linter_term(term), fact}
    case SomeTerms{first, rest}:
      f r = get_linter_term(first) get_linter_term(rest)
      SomeTerms{f, r}
    case NoTerms{}:
      NoTerms{}

def get_linter_body(body: Maybe<&2, BendTerm>) -> Maybe<&2, BendTerm>:
  match body:
    case None{}:
      None{}
    case Some{term}:
      Some{get_linter_term(term)}

def get_linter_kind(kind: DeclarationKind) -> DeclarationKind:
  match kind:
    case ImportDeclaration{loads}:
      ImportDeclaration{Path.get_posix_path(loads)}
    case DefDeclaration{fills, written_type, body}:
      DefDeclaration{fills, written_type, get_linter_body(body)}
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

def get_posix_paths(paths: List<&2, String>) -> List<&2, String>:
  match paths:
    case Nil{}:
      []
    case Con{p, t}:
      Path.get_posix_path(p) <> get_posix_paths(t)

def get_linter_check(check: BendCheck) -> BendCheck:
  match check:
    case BendCheck{root, sources, failure, declarations, program_paths}:
      BendCheck{
        get_linter_source(root),
        get_linter_sources(sources),
        get_linter_failure(failure),
        get_linter_source_declarations(declarations),
        get_posix_paths(program_paths)
      }

def get_json_blank(+s: String) -> String:
  match s:
    case SCon{' ', rest}:
      get_json_blank(rest)
    case SCon{'\t', rest}:
      get_json_blank(rest)
    case SCon{'\n', rest}:
      get_json_blank(rest)
    case SCon{'\r', rest}:
      get_json_blank(rest)
    case _:
      s

# A hex digit's value; 16 when `c` is none.
def get_hex_value(c: Char) -> U32:
  +x = get_code(c)
  Bool.pick(
    U32,
    get_is_between(x, 48, 57),
    U32.sub(x, 48),
    Bool.pick(
      U32,
      get_is_between(x, 97, 102),
      U32.sub(x, 87),
      Bool.pick(U32, get_is_between(x, 65, 70), U32.sub(x, 55), 16)
    )
  )

# The code point four hex digits spell; U+FFFD when one is not a hex digit.
def get_hex4(a: Char, b: Char, c: Char, d: Char) -> Char:
  +w = get_hex_value(a)
  +x = get_hex_value(b)
  +y = get_hex_value(c)
  +z = get_hex_value(d)
  Char.from_u32(
    Bool.pick(
      U32,
      U32.is_lt(w, 16) && U32.is_lt(x, 16) && U32.is_lt(y, 16) && U32.is_lt(z, 16),
      U32.add(U32.mul(U32.add(U32.mul(U32.add(U32.mul(w, 16), x), 16), y), 16), z),
      65533
    )
  )

# The string after an opening quote: its text, and what follows its closing quote.
def get_json_text.go(fuel: Nat, s: String, acc: String) -> JsonPart:
  match fuel s:
    case 0n _:
      JsonPartFail{"a string is not closed"}
    case 1n+k SCon{'"', rest}:
      JsonPartDone{JsonText{String.reverse(acc)}, rest}
    case 1n+k SCon{'\\', SCon{'"', rest}}:
      get_json_text.go(k, rest, SCon{'"', acc})
    case 1n+k SCon{'\\', SCon{'\\', rest}}:
      get_json_text.go(k, rest, SCon{'\\', acc})
    case 1n+k SCon{'\\', SCon{'/', rest}}:
      get_json_text.go(k, rest, SCon{'/', acc})
    case 1n+k SCon{'\\', SCon{'n', rest}}:
      get_json_text.go(k, rest, SCon{'\n', acc})
    case 1n+k SCon{'\\', SCon{'t', rest}}:
      get_json_text.go(k, rest, SCon{'\t', acc})
    case 1n+k SCon{'\\', SCon{'r', rest}}:
      get_json_text.go(k, rest, SCon{'\r', acc})
    case 1n+k SCon{'\\', SCon{'b', rest}}:
      get_json_text.go(k, rest, SCon{Char.from_u32(8), acc})
    case 1n+k SCon{'\\', SCon{'f', rest}}:
      get_json_text.go(k, rest, SCon{Char.from_u32(12), acc})
    case 1n+k SCon{'\\', SCon{'u', SCon{a, SCon{b, SCon{c, SCon{d, rest}}}}}}:
      get_json_text.go(k, rest, SCon{get_hex4(a, b, c, d), acc})
    case 1n+k SCon{'\\', rest}:
      JsonPartFail{"a string has a bad escape"}
    case 1n+k SCon{c, rest}:
      get_json_text.go(k, rest, SCon{c, acc})
    case 1n+k SNil{}:
      JsonPartFail{"a string is not closed"}

def get_json_text(+s: String) -> JsonPart:
  get_json_text.go((2n + String.length(s): Nat), s, "")

def get_is_number_char(c: Char) -> Bool:
  +x = get_code(c)
  get_is_between(
    x,
    48,
    57
  )
    || U32.is_eq(x, 45)
    || U32.is_eq(x, 43)
    || U32.is_eq(x, 46)
    || U32.is_eq(x, 101)
    || U32.is_eq(x, 69)

# A number: `c` and the characters of a number after it.
def get_json_number.go(+s: String, ok: Bool, c: Char, acc: String) -> JsonPart:
  match s ok:
    case SCon{+d, rest} True{}:
      get_json_number.go(rest, get_is_number_char(d), d, SCon{c, acc})
    case SNil{} True{}:
      JsonPartDone{JsonNumber{String.reverse(SCon{c, acc})}, ""}
    case _ False{}:
      JsonPartDone{JsonNumber{String.reverse(acc)}, SCon{c, s}}

def get_json_number(s: String) -> JsonPart:
  match s:
    case SCon{+c, rest}:
      Bool.pick(
        JsonPart,
        get_is_between(get_code(c), 48, 57) || U32.is_eq(get_code(c), 45),
        get_json_number.go(rest, True{}, c, ""),
        JsonPartFail{"a value was expected"}
      )
    case SNil{}:
      JsonPartFail{"a value was expected"}

# A JSON value, read with an explicit stack: Bend has no mutual recursion. `step` is what comes next, `stack` the
# lists and objects that are open.
def get_json.go(
  fuel: Nat,
  step: JsonStep,
  s: String,
  stack: List<&2, JsonFrame>
) -> Result<&1, &1, String, JsonValue>:
  match fuel:
    case 0n:
      Fail{"the JSON is too long"}
    case 1n+k:
      match step s stack:
        case JsonWantValue{} SCon{'{', rest} st:
          get_json.go(k, JsonWantKey{True{}}, get_json_blank(rest), JsonObjectFrame{[], ""} <> st)
        case JsonWantValue{} SCon{'[', rest} st:
          get_json.go(k, JsonWantItem{}, get_json_blank(rest), JsonListFrame{[]} <> st)
        case JsonWantValue{} SCon{'"', rest} st:
          get_json.go(k, JsonParsed{get_json_text(rest)}, "", st)
        case JsonWantValue{} SCon{'t', SCon{'r', SCon{'u', SCon{'e', rest}}}} st:
          get_json.go(k, JsonGot{JsonBool{True{}}}, get_json_blank(rest), st)
        case JsonWantValue{} SCon{'f', SCon{'a', SCon{'l', SCon{'s', SCon{'e', rest}}}}} st:
          get_json.go(k, JsonGot{JsonBool{False{}}}, get_json_blank(rest), st)
        case JsonWantValue{} SCon{'n', SCon{'u', SCon{'l', SCon{'l', rest}}}} st:
          get_json.go(k, JsonGot{JsonNull{}}, get_json_blank(rest), st)
        case JsonWantValue{} x st:
          get_json.go(k, JsonParsed{get_json_number(x)}, "", st)
        case JsonWantItem{} SCon{']', rest} Con{JsonListFrame{items}, t}:
          get_json.go(
            k,
            JsonGot{JsonList{List.reverse(&2, JsonValue, items)}},
            get_json_blank(rest),
            t
          )
        case JsonWantItem{} x st:
          get_json.go(k, JsonWantValue{}, x, st)
        case JsonWantKey{True{}} SCon{'}', rest} Con{JsonObjectFrame{fields, key}, t}:
          get_json.go(
            k,
            JsonGot{JsonObject{List.reverse(&2, JsonField, fields)}},
            get_json_blank(rest),
            t
          )
        case JsonWantKey{first} SCon{'"', rest} st:
          get_json.go(k, JsonParsedKey{get_json_text(rest)}, "", st)
        case JsonWantKey{first} x st:
          Fail{"a key was expected"}
        case JsonParsedKey{JsonPartDone{JsonText{key}, rest}} x st:
          get_json.go(k, JsonWantColon{key}, get_json_blank(rest), st)
        case JsonParsedKey{JsonPartFail{e}} x st:
          Fail{e}
        case JsonParsedKey{p} x st:
          Fail{"a key was expected"}
        case JsonWantColon{key} SCon{':', rest} Con{JsonObjectFrame{fields, old}, t}:
          get_json.go(k, JsonWantValue{}, get_json_blank(rest), JsonObjectFrame{fields, key} <> t)
        case JsonWantColon{key} x st:
          Fail{"a colon was expected after the key " ++ key}
        case JsonParsed{JsonPartDone{v, rest}} x st:
          get_json.go(k, JsonGot{v}, get_json_blank(rest), st)
        case JsonParsed{JsonPartFail{e}} x st:
          Fail{e}
        case JsonGot{v} SNil{} Nil{}:
          Done{v}
        case JsonGot{v} x Nil{}:
          Fail{"text follows the JSON value"}
        case JsonGot{v} SCon{',', rest} Con{JsonListFrame{items}, t}:
          get_json.go(k, JsonWantValue{}, get_json_blank(rest), JsonListFrame{v <> items} <> t)
        case JsonGot{v} SCon{']', rest} Con{JsonListFrame{items}, t}:
          get_json.go(
            k,
            JsonGot{JsonList{List.reverse(&2, JsonValue, v <> items)}},
            get_json_blank(rest),
            t
          )
        case JsonGot{v} SCon{',', rest} Con{JsonObjectFrame{fields, key}, t}:
          get_json.go(
            k,
            JsonWantKey{False{}},
            get_json_blank(rest),
            JsonObjectFrame{JsonField{key, v} <> fields, ""} <> t
          )
        case JsonGot{v} SCon{'}', rest} Con{JsonObjectFrame{fields, key}, t}:
          get_json.go(
            k,
            JsonGot{JsonObject{List.reverse(&2, JsonField, JsonField{key, v} <> fields)}},
            get_json_blank(rest),
            t
          )
        case JsonGot{v} x st:
          Fail{"a comma or a closing bracket was expected"}

def get_json(+text: String) -> Result<&1, &1, String, JsonValue>:
  get_json.go(
    (16n + Nat.double(String.length(text)): Nat),
    JsonWantValue{},
    get_json_blank(text),
    []
  )

# A whole number that fits a U32, from its digits; none if `s` is not one.
def get_whole.go(s: String, +acc: U32) -> Maybe<&2, U32>:
  match s:
    case SNil{}:
      Some{acc}
    case SCon{c, rest}:
      +d = U32.sub(get_code(c), 48)
      Bool.pick(
        Maybe<&2, U32>,
        U32.is_lt(
          d,
          10
        )
          && (U32.is_lt(acc, 429496729) || (U32.is_eq(acc, 429496729) && U32.is_le(d, 5))),
        get_whole.go(rest, U32.add(U32.mul(acc, 10), d)),
        None{}
      )

def get_whole(+s: String) -> Maybe<&2, U32>:
  match s:
    case SNil{}:
      None{}
    case _:
      get_whole.go(s, 0)

def get_option_number(+key: String, m: Maybe<&2, U32>) -> Result<&1, &1, String, OptionGiven>:
  match m:
    case Some{n}:
      Done{OptionGiven{key, NumberValue{n}}}
    case None{}:
      Fail{key ++ " must be a whole number from 0 to 4294967295"}

def get_option_given(field: JsonField) -> Result<&1, &1, String, OptionGiven>:
  match field:
    case JsonField{+key, JsonNumber{text}}:
      get_option_number(key, get_whole(text))
    case JsonField{key, JsonBool{b}}:
      Done{OptionGiven{key, FlagValue{b}}}
    case JsonField{key, JsonText{t}}:
      Done{OptionGiven{key, TextValue{t}}}
    case JsonField{key, v}:
      Fail{key ++ " must be a number, true or false, or text"}

def get_rule_severity.named(
  m: Maybe<&2, FindingSeverity>,
  name: String
) -> Result<&1, &1, String, Maybe<&2, FindingSeverity>>:
  match m:
    case Some{s}:
      Done{Some{s}}
    case None{}:
      Fail{name ++ " is not a severity: error, warning, information or hint"}

# A rule's severity in its settings, if given.
def get_rule_severity(
  fields: List<&2, JsonField>
) -> Result<&1, &1, String, Maybe<&2, FindingSeverity>>:
  match fields:
    case Nil{}:
      Done{None{}}
    case Con{JsonField{"severity", JsonText{+name}}, t}:
      get_rule_severity.named(get_severity_named(name), name)
    case Con{JsonField{"severity", v}, t}:
      Fail{"severity must be error, warning, information or hint"}
    case Con{f, t}:
      get_rule_severity(t)

def get_with_given(
  r: Result<&1, &1, String, OptionGiven>,
  xs: List<&2, OptionGiven>
) -> Result<&1, &1, String, List<&2, OptionGiven>>:
  match r:
    case Done{o}:
      Done{o <> xs}
    case Fail{e}:
      Fail{e}

# A rule's options in its settings, after `acc`, last first.
def get_rule_options(
  fields: List<&2, JsonField>,
  acc: Result<&1, &1, String, List<&2, OptionGiven>>
) -> Result<&1, &1, String, List<&2, OptionGiven>>:
  match fields acc:
    case _ Fail{e}:
      Fail{e}
    case Nil{} Done{xs}:
      Done{List.reverse(&2, OptionGiven, xs)}
    case Con{JsonField{"severity", v}, t} Done{xs}:
      get_rule_options(t, Done{xs})
    case Con{f, t} Done{xs}:
      get_rule_options(t, get_with_given(get_option_given(f), xs))

def get_rule_on(
  +id: String,
  severity: Result<&1, &1, String, Maybe<&2, FindingSeverity>>,
  options: Result<&1, &1, String, List<&2, OptionGiven>>
) -> Result<&1, &1, String, RuleSetting>:
  match severity options:
    case Done{s} Done{os}:
      Done{RuleOn{id, s, os}}
    case Fail{e} _:
      Fail{"rules." ++ id ++ ": " ++ e}
    case _ Fail{e}:
      Fail{"rules." ++ id ++ ": " ++ e}

def get_rule_off(+id: String, +v: String) -> Result<&1, &1, String, RuleSetting>:
  Bool.pick(
    Result<&1, &1, String, RuleSetting>,
    String.eq(v, "off"),
    Done{RuleOff{id}},
    Fail{"rules." ++ id ++ " must be \"off\" or an object of options"}
  )

def get_rule_setting(field: JsonField) -> Result<&1, &1, String, RuleSetting>:
  match field:
    case JsonField{+id, JsonText{v}}:
      get_rule_off(id, v)
    case JsonField{+id, JsonObject{+fields}}:
      get_rule_on(id, get_rule_severity(fields), get_rule_options(fields, Done{[]}))
    case JsonField{id, v}:
      Fail{"rules." ++ id ++ " must be \"off\" or an object of options"}

def get_with_setting(
  r: Result<&1, &1, String, RuleSetting>,
  xs: List<&2, RuleSetting>
) -> Result<&1, &1, String, List<&2, RuleSetting>>:
  match r:
    case Done{x}:
      Done{x <> xs}
    case Fail{e}:
      Fail{e}

def get_rule_settings(
  fields: List<&2, JsonField>,
  acc: Result<&1, &1, String, List<&2, RuleSetting>>
) -> Result<&1, &1, String, List<&2, RuleSetting>>:
  match fields acc:
    case _ Fail{e}:
      Fail{e}
    case Nil{} Done{xs}:
      Done{List.reverse(&2, RuleSetting, xs)}
    case Con{f, t} Done{xs}:
      get_rule_settings(t, get_with_setting(get_rule_setting(f), xs))

# Each item's text; none if one is not text.
def get_json_texts(items: List<&2, JsonValue>) -> Maybe<&2, List<&2, String>>:
  match items:
    case Nil{}:
      Some{[]}
    case Con{JsonText{t}, rest}:
      Maybe.map(&2, List<&2, String>, List<&2, String>, ts => t <> ts, get_json_texts(rest))
    case Con{v, rest}:
      None{}

def get_is_absolute(+p: String) -> Bool:
  String.starts_with(p, "/") || Path.get_normalized_path.is_drive(p)

# `p` from the folder `dir`, unless it is absolute.
def get_joined_path(+dir: String, +p: String) -> String:
  Path.get_normalized_path(Bool.pick(String, get_is_absolute(p), p, dir ++ "/" ++ p))

def get_joined_paths(+dir: String, ps: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}:
      []
    case Con{p, t}:
      get_joined_path(dir, Path.get_posix_path(p)) <> get_joined_paths(dir, t)

def get_config_paths.of(
  +dir: String,
  m: Maybe<&2, List<&2, String>>,
  +key: String
) -> Result<&1, &1, String, List<&2, String>>:
  match m:
    case Some{ps}:
      Done{get_joined_paths(dir, ps)}
    case None{}:
      Fail{key ++ " must be a list of paths"}

def get_config_paths(
  +dir: String,
  v: JsonValue,
  +key: String
) -> Result<&1, &1, String, List<&2, String>>:
  match v:
    case JsonList{items}:
      get_config_paths.of(dir, get_json_texts(items), key)
    case _:
      Fail{key ++ " must be a list of paths"}

def get_config_with(
  field: JsonField,
  c: ConfigFile,
  +dir: String
) -> Result<&1, &1, String, ConfigFile>:
  match field c:
    case JsonField{"load", v} ConfigFile{load, entries, imports, rules}:
      Result.map(
        &1,
        &1,
        String,
        List<&2, String>,
        ConfigFile,
        ps => ConfigFile{ps, entries, imports, rules},
        get_config_paths(dir, v, "load")
      )
    case JsonField{"entries", v} ConfigFile{load, entries, imports, rules}:
      Result.map(
        &1,
        &1,
        String,
        List<&2, String>,
        ConfigFile,
        ps => ConfigFile{load, ps, imports, rules},
        get_config_paths(dir, v, "entries")
      )
    case JsonField{"imports", JsonBool{b}} ConfigFile{load, entries, imports, rules}:
      Done{ConfigFile{load, entries, Some{b}, rules}}
    case JsonField{"imports", v} c2:
      Fail{"imports must be true or false"}
    case JsonField{"rules", JsonObject{fields}} ConfigFile{load, entries, imports, rules}:
      Result.map(
        &1,
        &1,
        String,
        List<&2, RuleSetting>,
        ConfigFile,
        rs => ConfigFile{load, entries, imports, rs},
        get_rule_settings(fields, Done{[]})
      )
    case JsonField{"rules", v} c2:
      Fail{"rules must be an object, from rule id to its settings"}
    case JsonField{key, v} c2:
      Done{c2}

def get_config_fields(
  fields: List<&2, JsonField>,
  acc: Result<&1, &1, String, ConfigFile>,
  +dir: String
) -> Result<&1, &1, String, ConfigFile>:
  match fields acc:
    case _ Fail{e}:
      Fail{e}
    case Nil{} Done{c}:
      Done{c}
    case Con{f, t} Done{c}:
      get_config_fields(t, get_config_with(f, c, dir), dir)

# A config file's settings, its paths from its folder `dir`.
def get_config_file(
  json: Result<&1, &1, String, JsonValue>,
  +dir: String
) -> Result<&1, &1, String, ConfigFile>:
  match json:
    case Done{JsonObject{fields}}:
      get_config_fields(fields, Done{ConfigFile{[], [], None{}, []}}, dir)
    case Done{v}:
      Fail{"the config must be a JSON object"}
    case Fail{e}:
      Fail{e}

# The folder of a path: all before its last slash.
def get_folder.go(rev: String) -> String:
  match rev:
    case SNil{}:
      ""
    case SCon{'/', rest}:
      String.reverse(rest)
    case SCon{c, rest}:
      get_folder.go(rest)

def get_folder(p: String) -> String:
  get_folder.go(String.reverse(p))

# `xs` without repeats, the first of each kept, after `seen`, reversed.
def get_unique_texts(xs: List<&2, String>, +seen: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      List.reverse(&2, String, seen)
    case Con{+x, t}:
      get_unique_texts(t, get_kept(String, Bool.not(get_has_text(seen, x)), x, seen))

def get_file_text.closed(
  got: File & Result<&1, &1, U32 & String, String>
) -> IO(Result<&1, &1, U32 & String, String>):
  match got:
    case (f, r):
      IO.bind(
        Unit,
        Result<&1, &1, U32 & String, String>,
        File.close(f),
        u => IO.pure(Result<&1, &1, U32 & String, String>, r)
      )

def get_file_text.sized(
  sized: File & Result<&1, &1, U32 & String, U32>
) -> IO(Result<&1, &1, U32 & String, String>):
  match sized:
    case (f, Done{n}):
      IO.bind(
        File & Result<&1, &1, U32 & String, String>,
        Result<&1, &1, U32 & String, String>,
        File.read(f, n),
        get_file_text.closed
      )
    case (f, Fail{e}):
      IO.bind(
        Unit,
        Result<&1, &1, U32 & String, String>,
        File.close(f),
        u => IO.pure(Result<&1, &1, U32 & String, String>, Fail{e})
      )

def get_file_text.opened(
  r: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Done{f}:
      IO.bind(
        File & Result<&1, &1, U32 & String, U32>,
        Result<&1, &1, U32 & String, String>,
        File.size(f),
        get_file_text.sized
      )
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{e})

# A file's text, as Base reads it.
def get_file_text(path: String) -> IO(Result<&1, &1, U32 & String, String>):
  IO.bind(
    Result<&1, &1, U32 & String, File>,
    Result<&1, &1, U32 & String, String>,
    File.open(path, "r"),
    get_file_text.opened
  )

# `path`, if `r` opened it; the file is closed.
def get_opened_path(r: Result<&1, &1, U32 & String, File>, path: String) -> IO(Maybe<&2, String>):
  match r:
    case Done{f}:
      IO.bind(Unit, Maybe<&2, String>, File.close(f), u => IO.pure(Maybe<&2, String>, Some{path}))
    case Fail{e}:
      IO.pure(Maybe<&2, String>, None{})

# The first of `paths` that opens, unless `found` holds one already.
def get_first_file(paths: List<&2, String>, found: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  match paths found:
    case _ Some{p}:
      IO.pure(Maybe<&2, String>, Some{p})
    case Nil{} None{}:
      IO.pure(Maybe<&2, String>, None{})
    case Con{+p, t} None{}:
      IO.bind(
        Maybe<&2, String>,
        Maybe<&2, String>,
        IO.bind(
          Result<&1, &1, U32 & String, File>,
          Maybe<&2, String>,
          File.open(p, "r"),
          r => get_opened_path(r, p)
        ),
        m => get_first_file(t, m)
      )

# The config files a file in `dir` may take, nearest first: one in each folder from `dir` up, some more than once.
def get_config_candidates(fuel: Nat, +dir: String) -> List<&2, String>:
  match fuel:
    case 0n:
      []
    case 1n+k:
      (dir ++ "/bend-lint.json") <> get_config_candidates(k, get_folder(dir))

def get_config_named(
  r: Result<&1, &1, String, ConfigFile>,
  +path: String
) -> Result<&1, &1, String, ConfigFile>:
  match r:
    case Done{c}:
      Done{c}
    case Fail{e}:
      Fail{path ++ ": " ++ e}

# The config file at `path`.
def get_config_read(
  r: Result<&1, &1, U32 & String, String>,
  +path: String
) -> Result<&1, &1, String, ConfigFile>:
  match r:
    case Done{text}:
      get_config_named(get_config_file(get_json(text), get_folder(path)), path)
    case Fail{error}:
      match error:
        case (code, why):
          Fail{path ++ ": " ++ why}

def get_config_at(+path: String) -> IO(Result<&1, &1, String, ConfigFile>):
  IO.bind(
    Result<&1, &1, U32 & String, String>,
    Result<&1, &1, String, ConfigFile>,
    get_file_text(path),
    r => IO.pure(Result<&1, &1, String, ConfigFile>, get_config_read(r, path))
  )

def get_config_found(m: Maybe<&2, String>) -> IO(Result<&1, &1, String, ConfigFile>):
  match m:
    case Some{p}:
      get_config_at(p)
    case None{}:
      IO.pure(Result<&1, &1, String, ConfigFile>, Done{ConfigFile{[], [], None{}, []}})

# The config of the file at `path`: the one given, else the nearest, else none.
def get_file_config(
  given: Maybe<&2, String>,
  +path: String
) -> IO(Result<&1, &1, String, ConfigFile>):
  match given:
    case Some{c}:
      get_config_at(c)
    case None{}:
      +dir = get_folder(path)
      IO.bind(
        Maybe<&2, String>,
        Result<&1, &1, String, ConfigFile>,
        get_first_file(
          get_unique_texts(get_config_candidates((1n + String.length(dir): Nat), dir), []),
          None{}
        ),
        get_config_found
      )

def get_config_or_die(r: Result<&1, &1, String, ConfigFile>) -> IO(ConfigFile):
  match r:
    case Done{c}:
      IO.pure(ConfigFile, c)
    case Fail{e}:
      IO.die(ConfigFile, 2, "bend-lint: " ++ e)

# The config of each of `files`, in order, after `done`, last first.
def get_file_configs(
  +given: Maybe<&2, String>,
  files: List<&2, String>,
  done: List<&2, ConfigFile>
) -> IO(List<&2, ConfigFile>):
  match files:
    case Nil{}:
      IO.pure(List<&2, ConfigFile>, List.reverse(&2, ConfigFile, done))
    case Con{f, t}:
      IO.bind(
        ConfigFile,
        List<&2, ConfigFile>,
        IO.bind(
          Result<&1, &1, String, ConfigFile>,
          ConfigFile,
          get_file_config(given, f),
          get_config_or_die
        ),
        c => get_file_configs(given, t, c <> done)
      )

def get_glob(pattern: String) -> IO(List<&2, String>):
  import "./effs/host.js"

def get_globbed_or_die(+pattern: String, found: List<&2, String>) -> IO(List<&2, String>):
  match found:
    case Nil{}:
      IO.die(List<&2, String>, 2, "bend-lint: " ++ pattern ++ " matches no file")
    case Con{h, t}:
      IO.pure(List<&2, String>, h <> t)

# The files each of `patterns` matches, in order, after `done`.
def get_globbed(patterns: List<&2, String>, done: List<&2, String>) -> IO(List<&2, String>):
  match patterns:
    case Nil{}:
      IO.pure(List<&2, String>, done)
    case Con{+p, t}:
      IO.bind(
        List<&2, String>,
        List<&2, String>,
        IO.bind(
          List<&2, String>,
          List<&2, String>,
          get_glob(p),
          found => get_globbed_or_die(p, found)
        ),
        found => get_globbed(t, get_unique_texts(List.append(&2, String, done, found), []))
      )

def get_usage() -> String:
  "usage: bun BEND-REWRITE/host.ts <glob>... [--imports | --no-imports] [--rules <rule.bend>]... [--config <bend-lint.json>]"

def get_flag_error(+flag: String) -> String:
  Bool.pick(
    String,
    get_has_text(
      ["--fix", "--fix-dangerously", "--json", "--no-fix", "--no-fix-dangerously", "--no-json"],
      flag
    ),
    flag ++ " is not supported yet",
    "unknown option " ++ flag
  )

def get_shown_suppressed(show: Bool, output: CliOutput) -> CliOutput:
  match output:
    case CliTextOutput{old}:
      CliTextOutput{show}
    case CliJsonOutput{}:
      CliJsonOutput{}

# The command `args` give, after what `acc` holds: its files and rule files last first.
def get_cli_command.go(args: List<String>, acc: CliCommand) -> Result<&1, &1, String, CliCommand>:
  match args acc:
    case Nil{} CliLint{files, rules, config, imports, fix, output}:
      Done{
        CliLint{
          List.reverse(&2, String, files),
          List.reverse(&2, String, rules),
          config,
          imports,
          fix,
          output
        }
      }
    case Con{"--rules", Con{x, t}} CliLint{files, rules, config, imports, fix, output}:
      get_cli_command.go(t, CliLint{files, x <> rules, config, imports, fix, output})
    case Con{"--rules", Nil{}} c:
      Fail{"--rules needs a rule file"}
    case Con{"--config", Con{x, t}} CliLint{files, rules, config, imports, fix, output}:
      get_cli_command.go(t, CliLint{files, rules, Some{x}, imports, fix, output})
    case Con{"--config", Nil{}} c:
      Fail{"--config needs a config file"}
    case Con{"--imports", t} CliLint{files, rules, config, imports, fix, output}:
      get_cli_command.go(t, CliLint{files, rules, config, Some{True{}}, fix, output})
    case Con{"--no-imports", t} CliLint{files, rules, config, imports, fix, output}:
      get_cli_command.go(t, CliLint{files, rules, config, Some{False{}}, fix, output})
    case Con{"--show-suppressed", t} CliLint{files, rules, config, imports, fix, output}:
      get_cli_command.go(
        t,
        CliLint{files, rules, config, imports, fix, get_shown_suppressed(True{}, output)}
      )
    case Con{"--no-show-suppressed", t} CliLint{files, rules, config, imports, fix, output}:
      get_cli_command.go(
        t,
        CliLint{files, rules, config, imports, fix, get_shown_suppressed(False{}, output)}
      )
    case Con{"--help", t} c:
      Done{CliHelp{}}
    case Con{"-h", t} c:
      Done{CliHelp{}}
    case Con{+h, t} CliLint{files, rules, config, imports, fix, output}:
      Bool.pick(
        Result<&1, &1, String, CliCommand>,
        String.starts_with(h, "-"),
        Fail{get_flag_error(h)},
        get_cli_command.go(t, CliLint{h <> files, rules, config, imports, fix, output})
      )
    case _ CliHelp{}:
      Done{CliHelp{}}

def get_cli_command(args: List<String>) -> Result<&1, &1, String, CliCommand>:
  get_cli_command.go(args, CliLint{[], [], None{}, None{}, None{}, CliTextOutput{False{}}})

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

def get_fix_lines(fixes: List<&2, Fix>) -> String:
  match fixes:
    case Nil{}:
      ""
    case Con{Fix{title, Safe{}, edits}, t}:
      "\n  fix: " ++ title ++ " [safe]" ++ get_fix_lines(t)
    case Con{Fix{title, Dangerous{}, edits}, t}:
      "\n  fix: " ++ title ++ " [dangerous]" ++ get_fix_lines(t)

def get_finding_text(f: RuleFinding) -> String:
  match f:
    case RuleFinding{rule_id, Finding{severity, message, BendSourceSpan{path, beg, end}, fixes}}:
      path ++ ":" ++ U32.show(beg) ++ ": " ++ rule_id ++ ": " ++ message ++ get_fix_lines(fixes)

def print_lines(lines: List<&2, String>) -> IO(Unit):
  match lines:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{h, t}:
      IO.bind(Unit, Unit, IO.print(h), u => print_lines(t))

def get_finding_texts(fs: List<&2, RuleFinding>) -> List<&2, String>:
  match fs:
    case Nil{}:
      []
    case Con{f, t}:
      get_finding_text(f) <> get_finding_texts(t)

def get_has_error(fs: List<&2, RuleFinding>) -> Bool:
  match fs:
    case Nil{}:
      False{}
    case Con{RuleFinding{id, Finding{Error{}, m, s, x}}, t}:
      True{}
    case Con{f, t}:
      get_has_error(t)

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

def get_demoted.pick(checkable: Bool, title: String, edits: List<&2, FixEdit>) -> Fix:
  match checkable:
    case True{}:
      Fix{title, Safe{}, edits}
    case False{}:
      Fix{title, Dangerous{}, edits}

def get_demoted(+path: String, fix: Fix) -> Fix:
  match fix:
    case Fix{title, Safe{}, +edits}:
      get_demoted.pick(get_is_checkable(edits, path), title, edits)
    case Fix{title, Dangerous{}, edits}:
      Fix{title, Dangerous{}, edits}

def get_demoted_fixes(fixes: List<&2, Fix>, +path: String) -> List<&2, Fix>:
  match fixes:
    case Nil{}:
      []
    case Con{f, t}:
      get_demoted(path, f) <> get_demoted_fixes(t, path)

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
      message ++ " The fix was not offered: it could not be shown to keep what the file declares."

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
        get_kept_fixes(get_demoted_fixes(fixes, path), path, text),
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

def get_checked_finding.in(source: Maybe<&2, BendSource>, found: RuleFinding) -> IO(RuleFinding):
  match source:
    case None{}:
      IO.pure(RuleFinding, found)
    case Some{BendSource{+path, +text, lines}}:
      get_checked_finding(path, text, found)

def get_checked_findings(
  findings: List<&2, RuleFinding>,
  +linted: List<&2, BendSource>
) -> IO(List<&2, RuleFinding>):
  match findings:
    case Nil{}:
      IO.pure(List<&2, RuleFinding>, [])
    case Con{+f, t}:
      IO.bind(
        RuleFinding,
        List<&2, RuleFinding>,
        get_checked_finding.in(get_source_at(linted, get_finding_path(f)), f),
        one => IO.bind(
          List<&2, RuleFinding>,
          List<&2, RuleFinding>,
          get_checked_findings(t, linted),
          rest => IO.pure(List<&2, RuleFinding>, one <> rest)
        )
      )

def get_checked_report(report: LintReport) -> IO(LintReport):
  match report:
    case LintReport{findings, suppressed, +linted}:
      IO.bind(
        List<&2, RuleFinding>,
        LintReport,
        get_checked_findings(findings, linted),
        checked => IO.pure(LintReport, LintReport{checked, suppressed, linted})
      )

def get_is_choice(+choices: List<&2, String>, +t: String) -> Bool:
  List.is_empty(&2, String, choices) || get_has_text(choices, t)

# Whether `value` fits `spec`, an AnySpec aside.
def get_fits_one(spec: OptionSpec, value: OptionValue) -> Bool:
  match spec value:
    case NumberSpec{lo, hi} NumberValue{n}:
      get_is_between(n, lo, hi)
    case FlagSpec{} FlagValue{b}:
      True{}
    case TextSpec{choices} TextValue{t}:
      get_is_choice(choices, t)
    case _ _:
      False{}

# Whether `value` fits one of `specs`; an AnySpec counts as its own specs.
def get_fits(fuel: Nat, specs: List<&2, OptionSpec>, +value: OptionValue) -> Bool:
  match fuel specs:
    case 0n _:
      False{}
    case 1n+k Nil{}:
      False{}
    case 1n+k Con{AnySpec{inner}, t}:
      get_fits(k, List.append(&2, OptionSpec, inner, t), value)
    case 1n+k Con{s, t}:
      get_fits_one(s, value) || get_fits(k, t, value)

def get_spec_shown(spec: OptionSpec) -> String:
  match spec:
    case NumberSpec{lo, hi}:
      "a whole number from " ++ U32.show(lo) ++ " to " ++ U32.show(hi)
    case FlagSpec{}:
      "true or false"
    case TextSpec{Nil{}}:
      "text"
    case TextSpec{Con{c, cs}}:
      "one of " ++ String.join(c <> cs, ", ")
    case AnySpec{specs}:
      "one of the values it allows"

def get_spec_problems(+spec: OptionSpec, +value: OptionValue, +what: String) -> List<&2, String>:
  Bool.pick(
    List<&2, String>,
    get_fits(64n, [spec], value),
    [],
    [what ++ " must be " ++ get_spec_shown(spec)]
  )

def get_declared_spec(declared: List<&2, OptionDeclared>, +key: String) -> Maybe<&2, OptionSpec>:
  match declared:
    case Nil{}:
      None{}
    case Con{OptionDeclared{+k, default, +spec}, t}:
      Bool.pick(Maybe<&2, OptionSpec>, String.eq(k, key), Some{spec}, get_declared_spec(t, key))

def get_given_problem(
  m: Maybe<&2, OptionSpec>,
  +value: OptionValue,
  +id: String,
  +key: String
) -> List<&2, String>:
  match m:
    case None{}:
      ["bend-lint config: " ++ id ++ ": there is no option " ++ key]
    case Some{spec}:
      get_spec_problems(spec, value, "bend-lint config: " ++ id ++ ": " ++ key)

def get_given_problems(
  given: List<&2, OptionGiven>,
  +declared: List<&2, OptionDeclared>,
  +id: String
) -> List<&2, String>:
  match given:
    case Nil{}:
      []
    case Con{OptionGiven{+key, value}, t}:
      List.append(
        &2,
        String,
        get_given_problem(get_declared_spec(declared, key), value, id, key),
        get_given_problems(t, declared, id)
      )

def get_default_problems(declared: List<&2, OptionDeclared>, +id: String) -> List<&2, String>:
  match declared:
    case Nil{}:
      []
    case Con{OptionDeclared{key, default, spec}, t}:
      List.append(
        &2,
        String,
        get_spec_problems(spec, default, id ++ ": the default of " ++ key),
        get_default_problems(t, id)
      )

# What is wrong with the rules' option defaults, and with the options `settings` give them.
def get_setting_problems(
  rules: List<&1, Rule>,
  +settings: List<&2, RuleSetting>
) -> List<&2, String>:
  match rules:
    case Nil{}:
      []
    case Con{Rule{+id, scope, +options, after, needs, run}, t}:
      List.append(
        &2,
        String,
        List.append(
          &2,
          String,
          get_default_problems(options, id),
          get_given_problems(get_set_options(settings, id), options, id)
        ),
        get_setting_problems(t, settings)
      )

def get_rule_file_paths(files: List<&2, RuleFile>) -> List<&2, String>:
  match files:
    case Nil{}:
      []
    case Con{RuleFile{path, ids}, t}:
      path <> get_rule_file_paths(t)

def get_offs(ids: List<&2, String>) -> List<&2, RuleSetting>:
  match ids:
    case Nil{}:
      []
    case Con{id, t}:
      RuleOff{id} <> get_offs(t)

# The rules of the compiled rule files that are not `active`, turned off.
def get_inactive(files: List<&2, RuleFile>, +active: List<&2, String>) -> List<&2, RuleSetting>:
  match files:
    case Nil{}:
      []
    case Con{RuleFile{+path, ids}, t}:
      List.append(
        &2,
        RuleSetting,
        Bool.pick(List<&2, RuleSetting>, get_has_text(active, path), [], get_offs(ids)),
        get_inactive(t, active)
      )

def get_config_loads(configs: List<&2, ConfigFile>) -> List<&2, String>:
  match configs:
    case Nil{}:
      []
    case Con{ConfigFile{load, entries, imports, rules}, t}:
      List.append(&2, String, load, get_config_loads(t))

# The configs with their rule files' real paths.
def get_configs_resolved(
  configs: List<&2, ConfigFile>,
  done: List<&2, ConfigFile>
) -> IO(List<&2, ConfigFile>):
  match configs:
    case Nil{}:
      IO.pure(List<&2, ConfigFile>, List.reverse(&2, ConfigFile, done))
    case Con{ConfigFile{load, entries, imports, rules}, t}:
      IO.bind(
        List<&2, String>,
        List<&2, ConfigFile>,
        get_linter_paths(load, []),
        ps => get_configs_resolved(t, ConfigFile{ps, entries, imports, rules} <> done)
      )

def get_imports(cli: Maybe<&2, Bool>, file: Maybe<&2, Bool>) -> Bool:
  match cli:
    case Some{b}:
      b
    case None{}:
      Maybe.default(&2, Bool, file, False{})

def get_is_glob(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{'*', rest}:
      True{}
    case SCon{'?', rest}:
      True{}
    case SCon{'[', rest}:
      True{}
    case SCon{'{', rest}:
      True{}
    case SCon{'!', rest}:
      True{}
    case SCon{c, rest}:
      get_is_glob(rest)

def get_cli_file(glob: Bool, +f: String) -> IO(List<&2, String>):
  match glob:
    case True{}:
      get_globbed([f], [])
    case False{}:
      IO.pure(List<&2, String>, [f])

# The files the command line names: a glob is expanded, a path is itself.
def get_cli_files(files: List<&2, String>, done: List<&2, String>) -> IO(List<&2, String>):
  match files:
    case Nil{}:
      IO.pure(List<&2, String>, done)
    case Con{+f, t}:
      IO.bind(
        List<&2, String>,
        List<&2, String>,
        get_cli_file(get_is_glob(f), f),
        fs => get_cli_files(t, get_unique_texts(List.append(&2, String, done, fs), []))
      )

def get_target(+given: String, r: Result<&1, &1, U32 & String, String>) -> LintTarget:
  match r:
    case Done{p}:
      LintTarget{given, p, True{}, ""}
    case Fail{error}:
      match error:
        case (code, why):
          LintTarget{given, Path.get_posix_path(given), False{}, why}

def get_targets(files: List<&2, String>, done: List<&2, LintTarget>) -> IO(List<&2, LintTarget>):
  match files:
    case Nil{}:
      IO.pure(List<&2, LintTarget>, List.reverse(&2, LintTarget, done))
    case Con{+f, t}:
      IO.bind(
        Result<&1, &1, U32 & String, String>,
        List<&2, LintTarget>,
        Path.get_linter_path(f),
        r => get_targets(t, get_target(f, r) <> done)
      )

def get_target_paths(targets: List<&2, LintTarget>) -> List<&2, String>:
  match targets:
    case Nil{}:
      []
    case Con{LintTarget{given, path, found, why}, t}:
      path <> get_target_paths(t)

def get_config_given.of(
  r: Result<&1, &1, U32 & String, String>,
  +c: String
) -> IO(Maybe<&2, String>):
  match r:
    case Done{p}:
      IO.pure(Maybe<&2, String>, Some{p})
    case Fail{error}:
      match error:
        case (code, why):
          IO.die(Maybe<&2, String>, 2, "bend-lint: " ++ c ++ ": " ++ why)

# The config `--config` names, as a real path.
def get_config_given(m: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  match m:
    case None{}:
      IO.pure(Maybe<&2, String>, None{})
    case Some{+c}:
      IO.bind(
        Result<&1, &1, U32 & String, String>,
        Maybe<&2, String>,
        Path.get_linter_path(c),
        r => get_config_given.of(r, c)
      )

def get_job_entries(imports: Bool, entries: List<&2, String>) -> IO(List<&2, String>):
  match imports:
    case True{}:
      IO.pure(List<&2, String>, [])
    case False{}:
      get_globbed(entries, [])

# A lint job per target, with its config: its rules are the given ones and those it loads, and its entries are
# expanded.
def get_jobs(
  targets: List<&2, LintTarget>,
  configs: List<&2, ConfigFile>,
  +given: List<&2, String>,
  +imports: Maybe<&2, Bool>,
  +compiled: List<&2, RuleFile>,
  done: List<&2, LintJob>
) -> IO(List<&2, LintJob>):
  match targets configs:
    case Con{target, tt} Con{ConfigFile{+load, entries, cimports, settings}, ct}:
      +im = get_imports(imports, cimports)
      IO.bind(
        List<&2, String>,
        List<&2, LintJob>,
        get_job_entries(im, entries),
        es => get_jobs(
          tt,
          ct,
          given,
          imports,
          compiled,
          LintJob{
            target,
            LintConfig{
              load,
              es,
              im,
              List.append(
                &2,
                RuleSetting,
                get_inactive(compiled, List.append(&2, String, given, load)),
                settings
              )
            }
          }
            <> done
        )
      )
    case _ _:
      IO.pure(List<&2, LintJob>, List.reverse(&2, LintJob, done))

def get_job_imports(jobs: List<&2, LintJob>) -> Bool:
  match jobs:
    case Nil{}:
      False{}
    case Con{LintJob{target, LintConfig{load, entries, imports, rules}}, t}:
      imports || get_job_imports(t)

def get_checks_reading(checks: List<&2, BendCheck>, +path: String) -> List<&2, BendCheck>:
  match checks:
    case Nil{}:
      []
    case Con{BendCheck{root, +sources, failure, declarations, program_paths}, t}:
      get_kept(
        BendCheck,
        get_has_text(get_source_paths(sources), path),
        BendCheck{root, sources, failure, declarations, program_paths},
        get_checks_reading(t, path)
      )

def get_checks_passed(checks: List<&2, BendCheck>) -> List<&2, BendCheck>:
  match checks:
    case Nil{}:
      []
    case Con{BendCheck{root, sources, None{}, declarations, program_paths}, t}:
      BendCheck{root, sources, None{}, declarations, program_paths} <> get_checks_passed(t)
    case Con{c, t}:
      get_checks_passed(t)

def get_needed_check(path: String, needs: CheckNeeds) -> IO(BendCheck):
  match needs:
    case CheckNeeds{declarations, bodies, facts}:
      get_check(path, declarations, bodies, facts)

# The checks of each entry, in order, after `done`, last first.
def get_entry_checks(
  entries: List<&2, String>,
  +needs: CheckNeeds,
  done: List<&2, BendCheck>
) -> IO(List<&2, BendCheck>):
  match entries:
    case Nil{}:
      IO.pure(List<&2, BendCheck>, List.reverse(&2, BendCheck, done))
    case Con{e, t}:
      IO.bind(
        BendCheck,
        List<&2, BendCheck>,
        get_needed_check(e, needs),
        c => get_entry_checks(t, needs, get_linter_check(c) <> done)
      )

# The report on the file at `path` from its own check, when no entry that reads it passed: `reaching` are the entries'
# checks that read it.
def lint_job.alone(
  ~rules: Unit -> List<&1, Rule>,
  +own: BendCheck,
  +reaching: List<&2, BendCheck>,
  +path: String,
  config: LintConfig
) -> LintReport:
  get_lint_report(
    ~rules,
    [own],
    List.append(&2, RuleFinding, get_check_failures(reaching), get_check_failures([own])),
    Bool.not(List.is_empty(&2, BendCheck, reaching)),
    path,
    config
  )

def lint_job.pick(
  ~rules: Unit -> List<&1, Rule>,
  passed: List<&2, BendCheck>,
  +reaching: List<&2, BendCheck>,
  +path: String,
  config: LintConfig,
  +needs: CheckNeeds
) -> IO(LintReport):
  match passed:
    case Nil{}:
      IO.bind(
        BendCheck,
        LintReport,
        get_needed_check(path, needs),
        c => IO.pure(
          LintReport,
          lint_job.alone(~rules, get_linter_check(c), reaching, path, config)
        )
      )
    case Con{h, t}:
      +all: List<&2, BendCheck> = h <> t
      IO.pure(
        LintReport,
        get_lint_report(
          ~rules,
          all,
          get_check_failures(reaching),
          U32.is_lt(
            U32.from_nat(List.length(&2, BendCheck, all)),
            U32.from_nat(List.length(&2, BendCheck, reaching))
          ),
          path,
          config
        )
      )

def lint_job.entries(
  ~rules: Unit -> List<&1, Rule>,
  +checks: List<&2, BendCheck>,
  +path: String,
  config: LintConfig,
  +needs: CheckNeeds
) -> IO(LintReport):
  +reaching = get_checks_reading(checks, path)
  lint_job.pick(~rules, get_checks_passed(reaching), reaching, path, config, needs)

# The report on the file at `path`: from the checks of the entries that read it, or else from its own.
def lint_job.found(
  ~rules: Unit -> List<&1, Rule>,
  +path: String,
  config: LintConfig,
  +needs: CheckNeeds
) -> IO(LintReport):
  match config:
    case LintConfig{load, +entries, imports, settings}:
      IO.bind(
        List<&2, BendCheck>,
        LintReport,
        get_entry_checks(entries, needs, []),
        cs => lint_job.entries(
          ~rules,
          cs,
          Path.get_posix_path(path),
          LintConfig{load, entries, imports, settings},
          needs
        )
      )

def lint_job(~rules: Unit -> List<&1, Rule>, job: LintJob, +needs: CheckNeeds) -> IO(LintReport):
  match job:
    case LintJob{LintTarget{given, path, True{}, why}, config}:
      lint_job.found(~rules, path, config, needs)
    case LintJob{LintTarget{given, path, False{}, why}, config}:
      IO.pure(
        LintReport,
        LintReport{
          [RuleFinding{"bend-lint/path", Finding{Error{}, why, BendSourceSpan{path, 0, 0}, []}}],
          [],
          []
        }
      )

def get_summary(failed: Bool, +found: Nat, +suppressed: Nat) -> String:
  match failed:
    case True{}:
      "bend-lint: FAIL"
    case False{}:
      "bend-lint: "
        ++ Nat.show(found)
        ++ " finding(s)"
        ++ Bool.pick(
          String,
          Nat.is_eq(suppressed, 0n),
          "",
          ", " ++ Nat.show(suppressed) ++ " suppressed"
        )

def get_suppressed_lines(show: Bool, fs: List<&2, RuleFinding>) -> List<&2, String>:
  match show fs:
    case True{} Con{h, t}:
      "bend-lint: suppressed" <> get_finding_texts(h <> t)
    case _ _:
      []

def get_shows_suppressed(output: CliOutput) -> Bool:
  match output:
    case CliTextOutput{show}:
      show
    case CliJsonOutput{}:
      False{}

def lint_jobs.exit(failed: Bool) -> IO(Unit):
  match failed:
    case True{}:
      IO.die(Unit, 1, "")
    case False{}:
      IO.pure(Unit, Unit{})

# Prints what every report found, and fails when a finding is an error.
def lint_jobs.finish(output: CliOutput, tally: LintTally) -> IO(Unit):
  match tally:
    case LintTally{found, suppressed}:
      +all = List.reverse(&2, RuleFinding, found)
      +hidden = List.reverse(&2, RuleFinding, suppressed)
      +failed = get_has_error(all)
      IO.bind(
        Unit,
        Unit,
        print_lines(
          List.append(
            &2,
            String,
            List.append(
              &2,
              String,
              get_finding_texts(all),
              get_suppressed_lines(get_shows_suppressed(output), hidden)
            ),
            [
              get_summary(
                failed,
                List.length(&2, RuleFinding, all),
                List.length(&2, RuleFinding, hidden)
              )
            ]
          )
        ),
        u => lint_jobs.exit(failed)
      )

def get_tallied(report: LintReport, tally: LintTally) -> LintTally:
  match report tally:
    case LintReport{findings, suppressed, linted} LintTally{f, s}:
      LintTally{
        List.append(&2, RuleFinding, List.reverse(&2, RuleFinding, findings), f),
        List.append(&2, RuleFinding, List.reverse(&2, RuleFinding, suppressed), s)
      }

def lint_jobs(
  ~rules: Unit -> List<&1, Rule>,
  jobs: List<&2, LintJob>,
  +needs: CheckNeeds,
  output: CliOutput,
  tally: LintTally
) -> IO(Unit):
  match jobs:
    case Nil{}:
      lint_jobs.finish(output, tally)
    case Con{j, t}:
      IO.bind(
        LintReport,
        Unit,
        IO.bind(LintReport, LintReport, lint_job(~rules, j, needs), get_checked_report),
        report => lint_jobs(~rules, t, needs, output, get_tallied(report, tally))
      )

def serve.problems(problems: List<&2, String>) -> IO(Unit):
  match problems:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{h, t}:
      IO.die(Unit, 2, "bend-lint: " ++ String.join(h <> t, "\nbend-lint: "))

# What is wrong with the rules, or with the settings the configs give them.
def get_configs_problems(
  ~rules: Unit -> List<&1, Rule>,
  configs: List<&2, ConfigFile>
) -> List<&2, String>:
  match configs:
    case Nil{}:
      []
    case Con{ConfigFile{load, entries, imports, settings}, t}:
      List.append(
        &2,
        String,
        get_setting_problems(rules(Unit{}), settings),
        get_configs_problems(~rules, t)
      )

def get_order_lines(problems: List<&2, String>) -> List<&2, String>:
  match problems:
    case Nil{}:
      []
    case Con{h, t}:
      ["the order of the rules is broken:\n" ++ String.join(h <> t, "\n")]

def serve.jobs(
  ~rules: Unit -> List<&1, Rule>,
  +jobs: List<&2, LintJob>,
  output: CliOutput
) -> IO(Unit):
  +heads = get_rule_heads(rules(Unit{}))
  IO.bind(
    Unit,
    Unit,
    serve.problems(
      Bool.pick(
        List<&2, String>,
        U32.is_lt(1, U32.from_nat(List.length(&2, LintJob, jobs))) && get_job_imports(jobs),
        [
          "--imports takes one entry file, also from the config; "
            ++ Nat.show(List.length(&2, LintJob, jobs))
            ++ " match\n"
            ++ get_usage()
        ],
        []
      )
    ),
    u => lint_jobs(
      ~rules,
      jobs,
      CheckNeeds{
        get_heads_need(heads, DeclarationsNeed{}),
        get_heads_need(heads, BodiesNeed{}),
        get_heads_need(heads, FactsNeed{})
      },
      output,
      LintTally{[], []}
    )
  )

def serve.compiled(
  ~rules: Unit -> List<&1, Rule>,
  targets: List<&2, LintTarget>,
  +given: List<&2, String>,
  +configs: List<&2, ConfigFile>,
  imports: Maybe<&2, Bool>,
  +compiled: List<&2, RuleFile>,
  output: CliOutput
) -> IO(Unit):
  IO.bind(
    Unit,
    Unit,
    serve.problems(
      List.append(
        &2,
        String,
        get_order_lines(get_order_problems(get_rule_heads(rules(Unit{})))),
        get_configs_problems(~rules, configs)
      )
    ),
    u => IO.bind(
      List<&2, LintJob>,
      Unit,
      get_jobs(targets, configs, given, imports, compiled, []),
      jobs => serve.jobs(~rules, jobs, output)
    )
  )

# Lints, unless the rule files the targets want are not the ones compiled in: then the program restarts with them.
def serve.choose(
  ~rules: Unit -> List<&1, Rule>,
  same: Bool,
  wanted: List<&2, String>,
  targets: List<&2, LintTarget>,
  given: List<&2, String>,
  configs: List<&2, ConfigFile>,
  imports: Maybe<&2, Bool>,
  compiled: List<&2, RuleFile>,
  output: CliOutput
) -> IO(Unit):
  match same:
    case True{}:
      serve.compiled(~rules, targets, given, configs, imports, compiled, output)
    case False{}:
      restart_with_rules(wanted)

def serve.configured(
  ~rules: Unit -> List<&1, Rule>,
  targets: List<&2, LintTarget>,
  +given: List<&2, String>,
  +configs: List<&2, ConfigFile>,
  imports: Maybe<&2, Bool>,
  +compiled: List<&2, RuleFile>,
  output: CliOutput
) -> IO(Unit):
  +wanted = get_unique_texts(List.append(&2, String, given, get_config_loads(configs)), [])
  serve.choose(
    ~rules,
    get_same_texts(wanted, get_rule_file_paths(compiled)),
    wanted,
    targets,
    given,
    configs,
    imports,
    compiled,
    output
  )

def serve.targets(
  ~rules: Unit -> List<&1, Rule>,
  +targets: List<&2, LintTarget>,
  given: List<&2, String>,
  config: Maybe<&2, String>,
  imports: Maybe<&2, Bool>,
  compiled: List<&2, RuleFile>,
  output: CliOutput
) -> IO(Unit):
  IO.bind(
    List<&2, ConfigFile>,
    Unit,
    IO.bind(
      List<&2, ConfigFile>,
      List<&2, ConfigFile>,
      get_file_configs(config, get_target_paths(targets), []),
      configs => get_configs_resolved(configs, [])
    ),
    configs => serve.configured(~rules, targets, given, configs, imports, compiled, output)
  )

def serve.command(
  ~rules: Unit -> List<&1, Rule>,
  command: CliCommand,
  compiled: List<&2, RuleFile>
) -> IO(Unit):
  match command:
    case CliHelp{}:
      IO.print(get_usage())
    case CliLint{files, rule_files, config, imports, fix, output}:
      IO.bind(
        List<&2, String>,
        Unit,
        get_cli_files(files, []),
        named => IO.bind(
          List<&2, String>,
          Unit,
          get_linter_paths(rule_files, []),
          given => IO.bind(
            List<&2, LintTarget>,
            Unit,
            get_targets(named, []),
            targets => IO.bind(
              Maybe<&2, String>,
              Unit,
              get_config_given(config),
              c => serve.targets(~rules, targets, given, c, imports, compiled, output)
            )
          )
        )
      )

def serve.parsed(
  ~rules: Unit -> List<&1, Rule>,
  parsed: Result<&1, &1, String, CliCommand>,
  compiled: List<&2, RuleFile>
) -> IO(Unit):
  match parsed:
    case Done{value}:
      serve.command(~rules, value, compiled)
    case Fail{error}:
      IO.die(Unit, 2, "bend-lint: " ++ error ++ "\n" ++ get_usage())

def serve.args(
  ~rules: Unit -> List<&1, Rule>,
  args: List<String>,
  compiled: List<&2, RuleFile>
) -> IO(Unit):
  match args:
    case Nil{}:
      serve.parsed(~rules, get_cli_command([]), compiled)
    case Con{h, t}:
      serve.parsed(~rules, get_cli_command(t), compiled)

def serve(~rules: Unit -> List<&1, Rule>, compiled: List<&2, RuleFile>) -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), args => serve.args(~rules, args, compiled))
