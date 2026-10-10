# This file's goal is to become a bend version of the bend-lint tool.
# This file must remain self-contained for the time-being(aside from base or bendhub, and aside from effects), even if it contains laws and/or proofs.
# Every comment on this file stays here.
# Bend doesn't run natively on windows, with one exception: there's a sibling folder where a branch exists called feature/cuda-and-windows. This one works natively. If not that, you must use WSL. Effect code must be written with windows in mind anyway(or as agnostic as possible). We also have WSL iff not in the windows version.
# Drifts are intentional: Ergonomics win over 1:1 parity. Every drift is documented in the table below,
# with a stated reason.
#
# | Drift from the TS version                                   | Reason                                                       |
# | ----------------------------------------------------------- | ------------------------------------------------------------ |
# | No "suggested" fixes: only Safe and Dangerous.              | Reporting matters more than autofixing, for agents.          |
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
# | get_lint_report returns findings, suppressed findings and   | Callers need little else. Other failures stop the program    |
# | the linted files; errors use IO.die, not a Result.          | with a message.                                              |
# | EVERY path the linter touches is a normalized POSIX path,   | One spelling per file, on every system.                      |
# | symlinks included. Base and BendHub paths are exempt.       |                                                              |
# | On Windows, C:\x\y becomes /c/x/y.                          |                                                              |
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

def get_real_path(path: String) -> IO(Result<&1, &1, U32 & String, String>):
  import "./effs/get_real_path.c"
  import "./effs/get_real_path.js"

def get_normalized_path.pop.up(up: Bool, h: String, t: List<&2, String>) -> List<&2, String>:
  match up:
    case True{}:
      ".." <> (h <> t)
    case False{}:
      t

def get_normalized_path.pop.root(abs: Bool) -> List<&2, String>:
  match abs:
    case True{}:
      Nil{}
    case False{}:
      [".."]

def get_normalized_path.pop(stack: List<&2, String>, abs: Bool) -> List<&2, String>:
  match stack:
    case Nil{}:
      get_normalized_path.pop.root(abs)
    case Con{+h, t}:
      get_normalized_path.pop.up(String.eq(h, ".."), h, t)

def get_normalized_path.step(
  skip: Bool,
  up: Bool,
  s: String,
  stack: List<&2, String>,
  abs: Bool
) -> List<&2, String>:
  match skip:
    case True{}:
      stack
    case False{}:
      match up:
        case True{}:
          get_normalized_path.pop(stack, abs)
        case False{}:
          s <> stack

def get_normalized_path.go(
  segs: List<&2, String>,
  stack: List<&2, String>,
  +abs: Bool
) -> List<&2, String>:
  match segs:
    case Nil{}:
      stack
    case Con{+s, t}:
      get_normalized_path.go(
        t,
        get_normalized_path.step(
          String.eq(s, "") || String.eq(s, "."),
          String.eq(s, ".."),
          s,
          stack,
          abs
        ),
        abs
      )

def get_normalized_path.dotted(up: Bool, body: String) -> String:
  match up:
    case True{}:
      body
    case False{}:
      "./" ++ body

def get_normalized_path.relative(kept: List<&2, String>) -> String:
  match kept:
    case Nil{}:
      "."
    case Con{+h, t}:
      get_normalized_path.dotted(String.eq(h, ".."), String.join(h <> t, "/"))

def get_normalized_path.finish(unc: Bool, abs: Bool, kept: List<&2, String>) -> String:
  match unc:
    case True{}:
      "//" ++ String.join(kept, "/")
    case False{}:
      match abs:
        case True{}:
          "/" ++ String.join(kept, "/")
        case False{}:
          get_normalized_path.relative(kept)

def get_normalized_path(+p: String) -> String:
  +abs = String.starts_with(p, "/")
  get_normalized_path.finish(
    String.starts_with(p, "//") && Bool.not(String.starts_with(p, "///")),
    abs,
    List.reverse(&2, String, get_normalized_path.go(String.split(p, '/'), Nil{}, abs))
  )

def get_posix_path.slash(backslash: Bool, c: Char) -> Char:
  match backslash:
    case True{}:
      '/'
    case False{}:
      c

def get_posix_path.slashes(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, t}:
      SCon{get_posix_path.slash(Char.is_eq(h, '\\'), h), get_posix_path.slashes(t)}

def get_posix_path.shape(drive: Bool, unc: Bool, c: Char, d: Char, t: String) -> String:
  match drive:
    case True{}:
      "/" ++ SCon{Char.to_lower(c), SNil{}} ++ get_posix_path.slashes(t)
    case False{}:
      match unc:
        case True{}:
          get_posix_path.slashes(SCon{c, SCon{d, t}})
        case False{}:
          SCon{c, SCon{d, t}}

def get_posix_path.pair(+c: Char, rest: String) -> String:
  match rest:
    case SNil{}:
      SCon{c, SNil{}}
    case SCon{+d, t}:
      get_posix_path.shape(
        Char.is_alpha(c) && Char.is_eq(d, ':'),
        Char.is_eq(c, '\\') && Char.is_eq(d, '\\'),
        c,
        d,
        t
      )

def get_posix_path.shaped(native: String) -> String:
  match native:
    case SNil{}:
      SNil{}
    case SCon{+c, rest}:
      get_posix_path.pair(c, rest)

def get_posix_path(native: String) -> String:
  get_normalized_path(get_posix_path.shaped(native))

def get_is_windows_path.pair(+c: Char, rest: String) -> Bool:
  match rest:
    case SNil{}:
      False{}
    case SCon{+d, t}:
      (Char.is_alpha(c) && Char.is_eq(d, ':')) || (Char.is_eq(c, '\\') && Char.is_eq(d, '\\'))

def get_is_windows_path(native: String) -> Bool:
  match native:
    case SNil{}:
      False{}
    case SCon{+c, rest}:
      get_is_windows_path.pair(c, rest)

def get_linter_path.separators(windows: Bool, path: String) -> String:
  match windows:
    case True{}:
      get_posix_path.slashes(path)
    case False{}:
      path

def get_linter_path.root(empty: Bool, drive: Bool, joined: String) -> String:
  match empty:
    case True{}:
      "/"
    case False{}:
      match drive:
        case True{}:
          joined ++ "/"
        case False{}:
          joined

def get_linter_path.folder(rev: List<&2, String>) -> String:
  +joined = String.join(List.reverse(&2, String, rev), "/")
  get_linter_path.root(String.is_empty(joined), String.ends_with(joined, ":"), joined)

def get_linter_path.rest(empty: Bool, name: String, rest: String) -> String:
  match empty:
    case True{}:
      name
    case False{}:
      name ++ "/" ++ rest

def get_linter_path.candidates(rev: List<&2, String>, +rest: String) -> List<&1, String & String>:
  match rev:
    case Nil{}:
      [(".", rest)]
    case Con{+h, +t}:
      (
        get_linter_path.folder(h <> t),
        rest
      )
        <> get_linter_path.candidates(t, get_linter_path.rest(String.is_empty(rest), h, rest))

def get_linter_path.found(
  missing: Bool,
  retry: IO(Result<&1, &1, U32 & String, String>),
  code: U32,
  text: String
) -> IO(Result<&1, &1, U32 & String, String>):
  match missing:
    case True{}:
      retry
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{(code, text)})

def get_linter_path.tried(
  r: Result<&1, &1, U32 & String, String>,
  rest: String,
  retry: IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Done{value}:
      IO.pure(
        Result<&1, &1, U32 & String, String>,
        Done{get_normalized_path(get_posix_path(value) ++ "/" ++ rest)}
      )
    case Fail{error}:
      match error:
        case (+code, text):
          get_linter_path.found(U32.is_eq(code, 2), retry, code, text)

def get_linter_path.try(
  cands: List<&1, String & String>
) -> IO(Result<&1, &1, U32 & String, String>):
  match cands:
    case Nil{}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{(2, "No such file or directory")})
    case Con{head, tail}:
      match head:
        case (folder, rest):
          IO.bind(
            Result<&1, &1, U32 & String, String>,
            Result<&1, &1, U32 & String, String>,
            get_real_path(folder),
            r => get_linter_path.tried(r, rest, get_linter_path.try(tail))
          )

def get_linter_path.here(
  here: Result<&1, &1, U32 & String, String>,
  path: String
) -> IO(Result<&1, &1, U32 & String, String>):
  match here:
    case Done{value}:
      get_linter_path.try(
        get_linter_path.candidates(
          List.reverse(
            &2,
            String,
            String.split(get_linter_path.separators(get_is_windows_path(value), path), '/')
          ),
          ""
        )
      )
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{error})

def get_linter_path(path: String) -> IO(Result<&1, &1, U32 & String, String>):
  IO.bind(
    Result<&1, &1, U32 & String, String>,
    Result<&1, &1, U32 & String, String>,
    get_real_path("."),
    here => get_linter_path.here(here, path)
  )

def get_lint_report(file: BendSource, rules: List<&1, Rule>, config: LintConfig) -> IO(LintReport):
  IO.pure(LintReport, LintReport{[], [], [file]})

def get_fix_outcome(report: LintReport, level: Maybe<&2, FixApplicability>) -> FixOutcome:
  FixOutcome{[], []}
