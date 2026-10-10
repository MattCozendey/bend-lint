# This file's goal is to become a bend version of the bend-lint tool.
# This file must remain self-contained for the time-being, even if it contains laws and/or proofs.
# Every comment on this file stays here.
# Drifts are intentional: Ergonomics win over 1:1 parity. Every drift is documented in the table below,
# with a stated reason.
#
# | Drift from the TS version                                  | Reason                                                       |
# | ---------------------------------------------------------- | ------------------------------------------------------------ |
# | No "suggested" fixes: only Safe and Dangerous.             | Reporting matters more than autofixing, for agents.          |
# | AutoFix applies Safe fixes; DangerousFix applies both.     | With no "suggested", two levels of fixing are enough.        |
# | A fix can also create, write, rename and delete files.     | Real fixes move code between files, not only inside one.     |
# | A fix's edits apply in order, each on the result before.   | One edit can build on another, such as a rename then a text  |
# |                                                            | change in the renamed file.                                  |
# | So a later edit shifts its offsets by the edits before it, | A rule's spans come from the text as read. A law will state  |
# | and uses the path of any RenameFile before it.             | this later.                                                  |
# | apply_fixes returns no ReplaceText: only whole files.      | The caller only writes, renames and deletes files. A law     |
# |                                                            | will state this later.                                       |
# | A program rule's fix may touch many files.                 | Only a program rule sees who imports what. TS skips such a   |
# |                                                            | fix.                                                         |
# | apply_fixes never writes: it returns the edits to make.    | One shape for the CLI and the library. An editor or agent    |
# |                                                            | can show the edits, or make them itself.                     |
# | Skipped fixes come back as a list of findings.             | The caller can tell which fixes to run again. TS gives only  |
# |                                                            | counts.                                                      |
# | A finding always has a span.                               | Every finding has a natural place, and readers never unwrap  |
# |                                                            | a Maybe.                                                     |
# | A rule returns plain findings; the runner adds its id.     | A rule cannot give its findings a wrong code.                |
# | Only a program rule has entries (some or every).           | A file rule cannot set a value that would be ignored.        |
# | The config lint takes is resolved: no missing fields.      | lint never guesses. The caller decides defaults and flags    |
# |                                                            | first, so lint takes no separate imports.                    |
# | Per-rule config is a list of settings, not a map.          | Base has no map. RuleOff cannot carry a severity or options. |
# | lint returns findings, suppressed findings and the linted  | Callers need little else. Other failures stop the program    |
# | files; errors use IO.die, not a Result.                    | with a message.                                              |
# | Paths are always normalized POSIX paths.                   | One spelling per file, on every system.                      |
# | Offsets count code points, not UTF-16 units.               | That is how Bend counts String characters.                   |
# | A rule is a value with a run function, not a module.       | Rules are plain Bend data. A Rule cannot be copied, so build |
# |                                                            | the list again where it is needed.                           |
# | No abort signal and no unsaved text yet.                   | Bend cannot hold an abort signal; it will be an effect.      |
# |                                                            | Unsaved text is for editors and can wait.                    |
# | Names carry their family as a prefix (FixEdit, RuleScope). | Long names that say what they are read better than short     |
# |                                                            | ones.                                                        |
import Base

type FixLevel is Data:
  NoFix{}
  AutoFix{}
  DangerousFix{}

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
  RuleFinding{code: String, finding: Finding}

type RuleInput is Data:
  RuleInput{
    root: BendSource,
    sources: List<&2, BendSource>,
    options: List<&2, OptionGiven>,
    prior: List<&2, RuleFinding>
  }

type RuleEntries is Data:
  SomeEntry{}
  EveryEntry{}

type RuleScope is Data:
  FileScope{}
  ProgramScope{entries: RuleEntries}

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

def lint(file: BendSource, rules: List<&1, Rule>, config: LintConfig) -> IO(LintReport):
  IO.pure(LintReport, LintReport{[], [], [file]})

def apply_fixes(
  linted: List<&2, BendSource>,
  findings: List<&2, RuleFinding>,
  level: FixLevel
) -> FixOutcome:
  FixOutcome{[], []}
