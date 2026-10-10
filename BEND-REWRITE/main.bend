# This file's goal is to become a bend version of the bend-lint tool.
# This file must remain self-contained for the time-being(aside from base or bendhub, and aside from effects, the host, and path.bend), even if it contains laws and/or proofs.
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
# | --rules files are imported by a program written for the     | Bend cannot load code while it runs. The program is cached,  |
# | run, which bend then runs.                                  | keyed by the rule files and their text.                      |
# | No abort signal and no unsaved text yet.                    | Bend cannot hold an abort signal; it will be an effect.      |
# |                                                             | Unsaved text is for editors and can wait.                    |
# | Names carry their family as a prefix (FixEdit, RuleScope).  | Long names that say what they are read better than short     |
# |                                                             | ones.                                                        |
import Base
import ./path.bend as Path

type FixApplicability is Data:
  Safe{}
  Dangerous{}

type BendSource is Data:
  BendSource{path: String, text: String}

type BendSourceSpan is Data:
  BendSourceSpan{path: String, beg: U32, end: U32}

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
    prior: List<&2, RuleFinding>
  }

type RuleScope is Data:
  FileScope{}
  ProgramSomeScope{}
  ProgramEveryScope{}

type Rule is Type:
  Rule{
    id: String,
    scope: RuleScope,
    options: List<&2, OptionDeclared>,
    run: RuleInput -> IO(List<&2, Finding>)
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

def get_check_failure(path: String) -> IO(Maybe<&2, RuleFinding>):
  import "./effs/host.js"

def get_lint_report(file: BendSource, rules: List<&1, Rule>, config: LintConfig) -> IO(LintReport):
  IO.pure(LintReport, LintReport{[], [], [file]})

def get_fix_outcome(report: LintReport, level: Maybe<&2, FixApplicability>) -> FixOutcome:
  FixOutcome{[], []}

def run.print(found: RuleFinding) -> IO(Unit):
  match found:
    case RuleFinding{rule_id, finding}:
      match finding:
        case Finding{severity, message, span, fixes}:
          match span:
            case BendSourceSpan{path, beg, end}:
              at = Path.get_posix_path(path) ++ ":" ++ U32.show(beg)
              IO.print(at ++ ": " ++ rule_id ++ ": " ++ message)

def run.reported(found: Maybe<&2, RuleFinding>) -> IO(Bool):
  match found:
    case None{}:
      IO.pure(Bool, False{})
    case Some{value}:
      IO.bind(Unit, Bool, run.print(value), u => IO.pure(Bool, True{}))

def run.resolved(r: Result<&1, &1, U32 & String, String>) -> IO(Bool):
  match r:
    case Done{value}:
      IO.bind(Maybe<&2, RuleFinding>, Bool, get_check_failure(value), run.reported)
    case Fail{error}:
      match error:
        case (code, text):
          IO.bind(Unit, Bool, IO.print("bend-lint: " ++ text), u => IO.pure(Bool, True{}))

def run.each(files: List<String>, failed: Bool) -> IO(Bool):
  match files:
    case Nil{}:
      IO.pure(Bool, failed)
    case Con{h, t}:
      IO.bind(
        Bool,
        Bool,
        IO.bind(Result<&1, &1, U32 & String, String>, Bool, Path.get_linter_path(h), run.resolved),
        one => run.each(t, failed || one)
      )

def run.finish(failed: Bool) -> IO(Unit):
  match failed:
    case True{}:
      IO.die(Unit, 1, "bend-lint: FAIL")
    case False{}:
      IO.print("bend-lint: 0 finding(s)")

def run.args(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}:
      run.finish(False{})
    case Con{h, t}:
      IO.bind(Bool, Unit, run.each(t, False{}), run.finish)

def run(rules: List<&1, Rule>) -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run.args)
