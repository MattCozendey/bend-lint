# tests/some: a program rule for run.test.ts, merged as some-entry. In each file of a check, it finds a mark at offset
# 0, and one at the number of files the check read.
import Base
import ../lint.bend as Lint
import ../shared.bend as Shared

def marks(sources: List<&2, Lint.Source>, +n: U32, out: List<&2, Lint.Finding>) -> List<&2, Lint.Finding>:
  match sources:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Source{+path, namespace, text, nodes, facts}, rest}:
      marks(
        rest,
        n,
        Lint.Finding{Lint.Hint{}, Lint.Span{path, n, (n + 1 : U32)}, "at the count", []}
          <> Lint.Finding{Lint.Hint{}, Lint.Span{path, 0, 1}, "at 0", []}
          <> out
      )

def run(+whole: Lint.Whole) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(marks(Lint.Whole.sources(whole), U32.from_nat(Shared.length(&2, Lint.Source, Lint.Whole.sources(whole))), []))

def rule() -> Lint.Rule:
  Lint.ProgramRule{"tests/some", Lint.SomeEntry{}, Lint.Needs{False{}}, [], run}
