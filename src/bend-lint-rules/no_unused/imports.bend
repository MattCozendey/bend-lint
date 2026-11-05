# no_unused/imports: an import that nothing in its file uses.
# Fix: deletes the import's line.
# Heuristics: a use is a name written through the import's alias, or, for Base, a name that only Base
# declares (Imported in the rule API). An import of an impl.bend whose file also imports the spec.bend beside it is
# used: it fills the spec's laws, which the file uses through the spec's names (see the experimental-bend-spec skill).
import Base
import ../../linter/api/impl.bend as LintImpl
import ../../linter/api/spec.bend as Lint
import ../../shared.bend as Shared

# The fix that deletes the import's line.
def deleted(+text: String, path: String, at: U32) -> List<&2, Lint.Fix>:
  +beg = Shared.Strings.line_start(text, at)
  [
    Lint.Fix{
      "Remove the import",
      [Lint.Replace{Lint.Span{path, beg, Shared.Strings.line_end(text, beg)}, ""}]
    }
  ]

# An import's target without .bend, if the check names it so.
def stem(+target: String) -> String:
  Bool.pick(
    String,
    String.ends_with(target, ".bend"),
    Shared.Strings.take(target, Nat.sub(String.length(target), 5n)),
    target
  )

# The targets of the imports among `declarations`, without .bend, onto `out`.
def targets(declarations: List<&2, Lint.Declaration>, out: List<&2, String>) -> List<&2, String>:
  match declarations:
    case Nil{}:
      out
    case Con{Lint.Declaration{Lint.Node{Lint.Import{t}, name, s, k, f}, uses}, rest}:
      targets(rest, stem(t) <> out)
    case Con{d, rest}:
      targets(rest, out)

# Whether `x` is one of `targets`, or `found`.
def has(targets: List<&2, String>, +x: String, found: Bool) -> Bool:
  match targets found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{t, rest} False{}:
      has(rest, x, String.eq(t, x))

def links.if(impl: Bool, +s: String, targets: List<&2, String>) -> Bool:
  match impl:
    case True{}:
      has(targets, Shared.Strings.take(s, Nat.sub(String.length(s), 4n)) ++ "spec", False{})
    case False{}:
      False{}

# Whether the import of `target` fills laws its file uses: it is an impl.bend, and the file imports the spec.bend
# beside it, among `targets`.
def links(target: String, targets: List<&2, String>) -> Bool:
  +s = stem(target)
  links.if(String.ends_with(s, "/impl") || String.eq(s, "impl"), s, targets)

def reported(
  linked: Bool,
  text: String,
  +path: String,
  +beg: U32,
  end: U32,
  name: String
) -> List<&2, Lint.Finding>:
  match linked:
    case True{}:
      []
    case False{}:
      [
        Lint.Finding{
          Lint.Warning{},
          Lint.Span{path, beg, end},
          "Remove the import " ++ name ++ ": nothing uses it.",
          deleted(text, path, beg)
        }
      ]

def unused(text: String, targets: List<&2, String>, d: Lint.Declaration) -> List<&2, Lint.Finding>:
  match d:
    case Lint.Declaration{
      Lint.Node{Lint.Import{t}, name, Some{Lint.Span{path, beg, end}}, k, f},
      Nil{}
    }:
      reported(links(t, targets), text, path, beg, end, name)
    case _:
      []

def findings(
  declarations: List<&2, Lint.Declaration>,
  +text: String,
  +targets: List<&2, String>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match declarations:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{d, rest}:
      findings(
        rest,
        text,
        targets,
        Shared.Lists.onto(&2, Lint.Finding, unused(text, targets, d), out)
      )

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +declarations = Lint.Here.declarations(here)
  Lint.done(findings(declarations, Lint.Here.text(here), targets(declarations, []), []))

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{False{}, True{}}, [], Lint.OnFile{run}}
