# no-unused/imports: an import that nothing in its file uses. What uses an import is the linter's (Imports in
# program.bend): a name written through its alias, or, for Base, a name that only Base declares.
import Base
import ../../lint.bend as Lint

def unused(d: Lint.Declaration) -> List<&2, Lint.Finding>:
  match d:
    case Lint.Declaration{Lint.Node{id, parent, owner, Lint.Import{}, name, binder, quantity, Some{span}, target}, Nil{}}:
      [Lint.Finding{Lint.Warning{}, span, "Remove the import " ++ name ++ ": nothing uses it."}]
    case _:
      []

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(Lint.findings(~Lint.Declaration, ~unused, Lint.Here.declarations(here)))

def rule() -> Lint.Rule:
  Lint.FileRule{"no-unused/imports", Lint.Needs{False{}}, [], run}
