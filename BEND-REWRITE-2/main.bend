import Base
import ./lint.bend as Lint
import ./rules/no-unused/imports.bend as UnusedImports

def main() -> IO(Unit):
  Lint.cli(~[UnusedImports.rule()])
