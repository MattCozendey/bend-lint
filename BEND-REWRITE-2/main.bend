import Base
import ./cli.bend as Cli
import ./rules/no-unused/imports.bend as UnusedImports

def main() -> IO(Unit):
  Cli.run(~[UnusedImports.rule()])
