# layout/directive-order: directives that stack on consecutive comment-only lines, out of order: by
# rule, then severity, then keyword.
# Fix: writes them in that order, over the same comments (--fix: it writes only comments).
import Base
import ../../linter/directives.bend as Directives
import ../../linter/lint.bend as Lint
import ../../shared/lists.bend as Lists

# Types
# =====

# A directive of a stack: its key, where its comment is, and the comment's text.
type Slot is Data:
  Slot{key: String, beg: U32, end: U32, text: String}

# A stack of directives: where it starts and ends, its last line, its last key, whether it is in order, and its
# directives (last first).
type Run is Data:
  Run{beg: U32, end: U32, line: U32, key: String, sorted: Bool, slots: List<&2, Slot>}

# The stacks so far: the open one, and the findings about the closed ones that are out of order (last first).
type Runs is Data:
  Runs{open: Maybe<&2, Run>, out: List<&2, Lint.Finding>}

# Functions
# =========

# What a comment's directive is sorted by: its rule, then the severity it pins, then its keyword; none if it is no
# directive.
def key(draft: Maybe<&2, Maybe<&2, Directives.Draft>>) -> Maybe<&2, String>:
  match draft:
    case Some{
      Some{Directives.Draft{Directives.Keyword{a, s}, Directives.Target{r, pinned}, reasons}}
    }:
      Some{
        r
          ++ "\t"
          ++ Maybe.default(&2, String, pinned, "")
          ++ "\t"
          ++ Directives.Action.show(a)
          ++ "-"
          ++ Directives.Scope.show(s)
      }
    case _:
      None{}

def Slot.le(a: Slot, b: Slot) -> Bool:
  match a b:
    case Slot{k, x, y, t} Slot{j, v, w, u}:
      String.is_le(k, j)

# The edits that write the directives of `sorted` into the places of `slots` (both in order), onto `out`.
def Slot.order(
  slots: List<&2, Slot>,
  sorted: List<&2, Slot>,
  +path: String,
  out: List<&2, Lint.Operation>
) -> List<&2, Lint.Operation>:
  match slots sorted:
    case Con{Slot{k, beg, end, t}, rest} Con{Slot{j, b, e, text}, more}:
      Slot.order(rest, more, path, Lint.Replace{Lint.Span{path, beg, end}, text} <> out)
    case _ _:
      List.reverse(&2, Lint.Operation, out)

def Runs.close(
  open: Maybe<&2, Run>,
  +path: String,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match open:
    case Some{Run{beg, end, line, key, False{}, slots}}:
      +ordered = List.reverse(&2, Slot, slots)
      Lint.Finding{
        Lint.Warning{},
        Lint.Span{path, beg, end},
        "Directives that stack must be in order: by rule, then severity, then keyword.",
        [
          Lint.Fix{
            "Order the directives",
            Slot.order(ordered, Lists.sort(~Slot, ~Slot.le, ordered), path, [])
          }
        ]
      }
        <> out
    case _:
      out

# A stack of one directive: its key, and its comment's place, line and text after the #.
def Run.first(+key: String, +beg: U32, +end: U32, line: U32, body: String) -> Run:
  Run{beg, end, line, key, True{}, [Slot{key, beg, end, "#" ++ body}]}

def Runs.extend(
  continues: Bool,
  run: Run,
  comment: Directives.Comment,
  +key: String,
  path: String,
  out: List<&2, Lint.Finding>
) -> Runs:
  match continues run comment:
    case True{} Run{beg, end, line, last, sorted, slots} Directives.Comment{b, +e, l, t, body}:
      Runs{
        Some{
          Run{
            beg,
            e,
            l,
            key,
            sorted && String.is_le(last, key),
            Slot{key, b, e, "#" ++ body} <> slots
          }
        },
        out
      }
    case False{} _ Directives.Comment{b, e, l, t, body}:
      Runs{Some{Run.first(key, b, e, l, body)}, Runs.close(Some{run}, path, out)}

# The stacks, with a comment read: a directive on its own line, `key`, stacks on the one on the line before it.
def Runs.step(
  key: Maybe<&2, String>,
  comment: Directives.Comment,
  path: String,
  runs: Runs
) -> Runs:
  match key comment runs:
    case Some{
      k
    } Directives.Comment{b, e, +l, False{}, body} Runs{Some{Run{rb, re, +rl, rk, rs, slots}}, out}:
      Runs.extend(
        U32.is_eq(l, (rl + 1: U32)),
        Run{rb, re, rl, rk, rs, slots},
        Directives.Comment{b, e, l, False{}, body},
        k,
        path,
        out
      )
    case Some{+k} Directives.Comment{b, e, l, False{}, body} Runs{None{}, out}:
      Runs{Some{Run.first(k, b, e, l, body)}, out}
    case _ _ _:
      runs

def Runs.go(
  comments: List<&2, Directives.Comment>,
  +path: String,
  runs: Runs
) -> List<&2, Lint.Finding>:
  match comments runs:
    case Nil{} Runs{open, out}:
      List.reverse(&2, Lint.Finding, Runs.close(open, path, out))
    case Con{Directives.Comment{b, e, l, t, +body}, rest} _:
      Runs.go(
        rest,
        path,
        Runs.step(
          key(Directives.Draft.read(body)),
          Directives.Comment{b, e, l, t, body},
          path,
          runs
        )
      )

def stacks(scanned: Directives.Scanned, path: String) -> List<&2, Lint.Finding>:
  match scanned:
    case Directives.Scanned{comments, lines}:
      Runs.go(comments, path, Runs{None{}, []})

# The stacks out of order in a file that has a directive's mark.
def found(marked: Bool, text: String, path: String) -> List<&2, Lint.Finding>:
  match marked:
    case True{}:
      stacks(Directives.Scan.of(text), path)
    case False{}:
      []

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +text = Lint.Here.text(here)
  Lint.done(found(Directives.marked(text, False{}), text, Lint.Here.path(here)))

def rule() -> Lint.Rule:
  Lint.Rule{"layout/directive-order", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
