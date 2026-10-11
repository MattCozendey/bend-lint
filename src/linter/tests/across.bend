# tests/across: a program rule for run.test.ts. In each file of a check, it finds a mark at offset 0, with a fix that
# writes a comment line at the start of every file.
import Base
import ../lint.bend as Lint

def inserts(sources: List<&2, Lint.Source>, out: List<&2, Lint.Operation>) -> List<&2, Lint.Operation>:
  match sources:
    case Nil{}:
      out
    case Con{Lint.Source{path, namespace, text, nodes, facts}, rest}:
      inserts(rest, Lint.Replace{Lint.Span{path, 0, 0}, "# fixed\n"} <> out)

def marks(sources: List<&2, Lint.Source>, +fix: Lint.Fix, out: List<&2, Lint.Finding>) -> List<&2, Lint.Finding>:
  match sources:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Source{path, namespace, text, nodes, facts}, rest}:
      marks(rest, fix, Lint.Finding{Lint.Hint{}, Lint.Span{path, 0, 1}, "at 0", [fix]} <> out)

def run(+whole: Lint.Whole) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(marks(Lint.Whole.sources(whole), Lint.Fix{"Mark every file", inserts(Lint.Whole.sources(whole), [])}, []))

def rule() -> Lint.Rule:
  Lint.Rule{"tests/across", Lint.Needs{False{}, False{}}, [], Lint.OnProgram{False{}, run}}
