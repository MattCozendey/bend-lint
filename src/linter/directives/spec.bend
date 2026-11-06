# Directives: the `# bend-lint:` comments that disable or expect findings.
import Base
import ../api/spec.bend as Lint

# A comment: where it is (code points), its line (from 0), whether code comes before it on its line, and its text
# after the #.
type Comment is Data:
  Comment{beg: U32, end: U32, line: U32, trailing: Bool, body: String}

# A text's comments, in order, and, for each of its lines, whether it holds code.
type Scanned is Data:
  Scanned{comments: List<&2, Comment>, lines: List<&2, Bool>}

# What a directive does: disable findings, or expect them.
type Action is Data:
  Disable{}
  Expect{}

# How far a directive reaches: the whole file, from a begin to its end, the next line with code, or its own line.
type Scope is Data:
  WholeFile{}
  Begin{}
  End{}
  NextLine{}
  SameLine{}

# A directive's word: what it does, and how far (`disable-next`).
type Keyword is Data:
  Keyword{action: Action, scope: Scope}

# What a directive names: a rule, and the severity it pins, as written.
type Target is Data:
  Target{rule: String, pinned: Maybe<&2, String>}

# A directive as written, before its severity and rule are checked: its reasons are the texts after each `--`.
type Draft is Data:
  Draft{keyword: Keyword, target: Target, reasons: List<&2, String>}

# A file's findings after its directives: those that stay, then the findings about its directives, and those a
# directive covers.
type Suppressed is Data:
  Suppressed{kept: List<&2, Lint.Found>, suppressed: List<&2, Lint.Found>}

# A linted file: its path and text, the ids of the rules there are, and those of the rules that ran on it. A rule
# turned off did not run, so its directives are never unused.
type Linted is Data:
  Linted{path: String, text: String, known: List<&2, String>, ran: List<&2, String>}

# The comments of `text`, and which of its lines hold code.
law Scan.of:
  for text: String
  Scanned

# How `a` is written in a directive.
law Action.show:
  for a: Action
  String

# How `s` is written in a directive, after the dash.
law Scope.show:
  for s: Scope
  String

# What a comment's text says, if it says bend-lint:: a directive's draft, if it is one.
law Draft.read:
  for +body: String
  Maybe<&2, Maybe<&2, Draft>>

# Whether `text` has a directive's mark, "bend-lint:". Only a 'b' starts a comparison, so it is one pass.
law has_mark:
  for text: String
  for found: Bool
  Bool

# The findings `founds` of the file `linted`, after its directives; a file with none keeps them all.
law apply:
  for +linted: Linted
  for founds: List<&2, Lint.Found>
  Suppressed
