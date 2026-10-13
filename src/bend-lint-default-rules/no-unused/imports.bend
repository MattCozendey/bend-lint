# no-unused/imports: an import that nothing in its file uses.
# Fix: deletes the import's line (--fix-dangerously).
# Heuristics: a use is a name written through the import's alias, or, for Base, a name that only Base
# declares (Imported in lint.bend).
import Base
import ../../linter/lint.bend as Lint
import ../../shared/lists.bend as Lists
import ../../shared/strings.bend as Strings

# The fix that deletes the import's line.
def deleted(+text: String, path: String, at: U32) -> List<&2, Lint.Fix>:
  +beg = Strings.line_start(text, at)
  [
    Lint.Fix{
      "Remove the import",
      [Lint.Replace{Lint.Span{path, beg, Strings.line_end(text, beg)}, ""}]
    }
  ]

def unused(text: String, d: Lint.Declaration) -> List<&2, Lint.Finding>:
  match d:
    case Lint.Declaration{Lint.Node{Lint.Import{t}, name, Some{Lint.Span{+path, +beg, end}}, k, f}, Nil{}}:
      [
        Lint.Finding{
          Lint.Warning{},
          Lint.Span{path, beg, end},
          "Remove the import " ++ name ++ ": nothing uses it.",
          deleted(text, path, beg)
        }
      ]
    case _:
      []

def findings(
  declarations: List<&2, Lint.Declaration>,
  +text: String,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match declarations:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{d, rest}:
      findings(rest, text, Lists.onto(&2, Lint.Finding, unused(text, d), out))

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(findings(Lint.Here.declarations(here), Lint.Here.text(here), []))

def rule() -> Lint.Rule:
  Lint.Rule{"no-unused/imports", Lint.Needs{False{}, True{}}, [], Lint.OnFile{run}}
