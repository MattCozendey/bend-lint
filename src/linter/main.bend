import Base
import ./cli.bend as Cli
import ./rules/layout/canon-import-path.bend as CanonImportPath
import ./rules/layout/case.bend as Case
import ./rules/layout/directive-order.bend as DirectiveOrder
import ./rules/layout/format.bend as Format
import ./rules/layout/imports.bend as Imports
import ./rules/no-unused/imports.bend as UnusedImports
import ./rules/performance/append-in-loop.bend as AppendInLoop
import ./rules/performance/deep-call-in-fork.bend as DeepCallInFork
import ./rules/performance/list-index-loop.bend as ListIndexLoop
import ./rules/performance/missed-fork.bend as MissedFork

def main() -> IO(Unit):
  Cli.run(
    ~[
      CanonImportPath.rule(),
      Case.rule(),
      DirectiveOrder.rule(),
      Format.rule(),
      Imports.rule(),
      UnusedImports.rule(),
      AppendInLoop.rule(),
      DeepCallInFork.rule(),
      ListIndexLoop.rule(),
      MissedFork.rule()
    ]
  )
