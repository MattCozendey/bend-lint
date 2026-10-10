import Base
import ./cli.bend as Cli
import ./rules/layout/case.bend as Case
import ./rules/no-unused/imports.bend as UnusedImports

def main() -> IO(Unit):
  Cli.run(~[Case.rule(), UnusedImports.rule()])
