# ALL LOGIC OF THE REWRITE WILL EXIST ONLY HERE FOR NOW INCLUDING LAWS AND PROOFS IF ANY.
# THIS FILE MUST RUN THROUGH BEND-LINT (THE TS VERSION) - ALL RULES.
# I DECIDED WE WILL DROP "SUGGESTED". REPORTING IS MORE IMPORTANT THAN AUTOFXING FOR AGENTS.
# WE WILL PROVIDE FIXES WHEN WE HAVE THEM.
# ANOTHER DRIFT: EDITS ARE NOT ONLY AN ARRAY OF CHANGES TO A FILE OR FILES, BUT ALSO
# FILE RENAMES, OR FILE DELETIONS, OR FILE CREATIONS.
# THIS FILE MUST BE SELF CONTAINED.
import Base

type FixLevel is Data:
  NoFix{}
  AutoFix{}
  DangerousFix{}

# A file: its path and its text. A path is ALWAYS a normalized POSIX path.
type Source is Data:
  Source{path: String, text: String}

# path: as in Source. Offsets count characters (code points) from the
# start of the file.
type Span is Data:
  Span{path: String, beg: U32, end: U32}

type Severity is Data:
  Error{}
  Warning{}
  Information{}
  Hint{}

type Diag is Data:
  Diag{severity: Severity, message: String, span: Span}

# id: namespace/name, the code of its findings.
type Rule is Type:
  Rule{id: String, run: Source -> List<&2, Diag>}

# An option's value: a whole number, a boolean, or text.
type Value is Data:
  Num{value: U32}
  Flag{value: Bool}
  Text{value: String}

type Option is Data:
  Option{key: String, value: Value}

# How the config sets one rule. severity: None{} keeps the rule's own.
type Setting is Data:
  Off{id: String}
  On{id: String, severity: Maybe<&2, Severity>, options: List<&2, Option>}

# load: rule files to run after the given ones. entries: files whose checks
# lint the files they import. imports: also lint every file the check reads.
type Config is Data:
  Config{load: List<&2, String>, entries: List<&2, String>, imports: Bool, rules: List<&2, Setting>}

# What a run found, and the files it linted, as they were read.
type Report is Data:
  Report{findings: List<&2, Diag>, linted: List<&2, Source>}

# The findings of rules in file, set up by config. Does nothing yet.
def lint(file: Source, rules: List<&1, Rule>, config: Config) -> IO(Report):
  IO.pure(Report, Report{[], [file]})
