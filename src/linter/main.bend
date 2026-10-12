import Base
import ../bend-lint-default-rules/language/decreasing-call.bend as DecreasingCall
import ../bend-lint-default-rules/language/forward-reference.bend as ForwardReference
import ../bend-lint-default-rules/language/reused-binder.bend as ReusedBinder
import ../bend-lint-default-rules/layout/canon-import-path.bend as CanonImportPath
import ../bend-lint-default-rules/layout/case.bend as Case
import ../bend-lint-default-rules/layout/directive-order.bend as DirectiveOrder
import ../bend-lint-default-rules/layout/format.bend as Format
import ../bend-lint-default-rules/layout/imports.bend as Imports
import ../bend-lint-default-rules/no-unused/imports.bend as UnusedImports
import ../bend-lint-default-rules/performance/append-in-loop.bend as AppendInLoop
import ../bend-lint-default-rules/performance/deep-call-in-fork.bend as DeepCallInFork
import ../bend-lint-default-rules/performance/eager-branch.bend as EagerBranch
import ../bend-lint-default-rules/performance/gpu-fit.bend as GpuFit
import ../bend-lint-default-rules/performance/list-index-loop.bend as ListIndexLoop
import ../bend-lint-default-rules/performance/missed-fork.bend as MissedFork
import ../bend-lint-default-rules/performance/unneeded-plus.bend as UnneededPlus
import ./cli.bend as Cli

def main() -> IO(Unit):
  Cli.run(
    ~[
      CanonImportPath.rule(),
      Case.rule(),
      DirectiveOrder.rule(),
      Format.rule(),
      Imports.rule(),
      DecreasingCall.rule(),
      ForwardReference.rule(),
      ReusedBinder.rule(),
      UnusedImports.rule(),
      AppendInLoop.rule(),
      DeepCallInFork.rule(),
      EagerBranch.rule(),
      GpuFit.rule(),
      ListIndexLoop.rule(),
      MissedFork.rule(),
      UnneededPlus.rule()
    ]
  )
