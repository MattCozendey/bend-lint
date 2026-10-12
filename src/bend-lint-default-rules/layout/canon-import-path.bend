# layout/canon-import-path: an import path that is not the shortest path from the importer to the
# file it names, or that does not start with ./ or ../.
# Fix: writes the shortest path (--fix-dangerously).
# Heuristics: it compares real paths, links resolved, so a link to a file is that file. Base and hub
# imports are not paths: it skips them.
import Base
import ../../linter/lint.bend as Lint
import ../../shared/lists.bend as Lists

# Paths
# =====
def segments.step(p: String, acc: List<&2, String>) -> List<&2, String>:
  match p:
    case SNil{}:
      acc
    case SCon{'.', SNil{}}:
      acc
    case SCon{'.', SCon{'.', SNil{}}}:
      List.tail(&2, String, acc)
    case SCon{c, rest}:
      SCon{c, rest} <> acc

# A path's segments, last first: "" and "." dropped, ".." applied.
def segments.go(parts: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}:
      acc
    case Con{p, rest}:
      segments.go(rest, segments.step(p, acc))

def segments(path: String) -> List<&2, String>:
  List.reverse(&2, String, segments.go(String.split(path, '/'), []))

# Each segment of `from` as "..", then `to`.
def ups(from: List<&2, String>, to: List<&2, String>) -> List<&2, String>:
  match from:
    case Nil{}:
      to
    case Con{f, rest}:
      ups(rest, ".." <> to)

# Whether both lists start with the same segment.
def same_head(from: List<&2, String>, to: List<&2, String>) -> Bool:
  match from to:
    case Con{a, as} Con{b, bs}:
      String.eq(a, b)
    case _ _:
      False{}

def relative.go(from: List<&2, String>, to: List<&2, String>, same: Bool) -> List<&2, String>:
  match from to same:
    case Con{a, +as} Con{b, +bs} True{}:
      relative.go(as, bs, same_head(as, bs))
    case f t _:
      ups(f, t)

# The segments that lead from the folder `from` to `to`.
def relative(+from: List<&2, String>, +to: List<&2, String>) -> List<&2, String>:
  relative.go(from, to, same_head(from, to))

# The segments as a path that starts with ./ or ../.
def canon(+parts: List<&2, String>) -> String:
  match parts:
    case Con{SCon{'.', SCon{'.', SNil{}}}, rest}:
      String.join(parts, "/")
    case _:
      "./" ++ String.join(parts, "/")

# Rule
# ====

# Hub imports name a package, not a path.
def hub(+path: String) -> Bool:
  Bool.or(String.contains(path, "@"), String.starts_with(path, "0x"))

def verdict(fine: Bool, +want: String, +span: Lint.Span) -> List<&2, Lint.Finding>:
  match fine:
    case True{}:
      []
    case False{}:
      [
        Lint.Finding{
          Lint.Warning{},
          span,
          "Write \"" ++ want ++ "\": the shortest path from this file, starting with ./ or ../.",
          [Lint.Fix{"Use the shortest path", [Lint.Replace{span, want}]}]
        }
      ]

# A written path, against the one from `file` to `target`, the file its import loads.
def judge(
  file: String,
  +written: String,
  target: Maybe<&2, Lint.Node>,
  span: Lint.Span
) -> List<&2, Lint.Finding>:
  match target:
    case Some{Lint.Node{id, p, o, Lint.Import{}, name, b, q, sp, loads}}:
      +want = canon(relative(segments(file ++ "/.."), segments(loads)))
      verdict(Bool.or(hub(written), String.eq(want, written)), want, span)
    case _:
      []

# The findings on the import paths among `nodes`, onto `out`. A file's imports come first, so the first node of another
# kind ends them.
def paths(
  nodes: List<&2, Lint.Node>,
  +here: Lint.Here,
  +file: String,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Con{Lint.Node{id, parent, o, Lint.ImportPath{}, written, b, q, Some{span}, t}, rest}:
      paths(
        rest,
        here,
        file,
        Lists.onto(&2, Lint.Finding, judge(file, written, Lint.Here.node(here, parent), span), out)
      )
    case Con{Lint.Node{id, parent, o, Lint.Import{}, name, b, q, sp, t}, rest}:
      paths(rest, here, file, out)
    case _:
      List.reverse(&2, Lint.Finding, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(paths(Lint.Here.nodes(here), here, Lint.Here.path(here), []))

def rule() -> Lint.Rule:
  Lint.Rule{"layout/canon-import-path", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
