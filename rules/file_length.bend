# style/file-length: warn when a source file exceeds maxLines (default 500).
# Formatting cannot shorten a file's logical contents; no fix is offered.
import Base
import ../src/bend/lint.bend as Lint

def id() -> String:
  "style/file-length"

def facts() -> Lint.Want:
  Lint.NoFacts{}

def options() -> List<&2, Lint.Declared>:
  [Lint.Declared{"maxLines", Lint.NumberOption{500, 0, 4294967295}}]

# Count physical lines in one tail-recursive scan, without allocating a
# line list. An empty file has zero lines; a final newline adds no sentinel.
def line_count.go(s: String, count: U32, last: Bool) -> U32:
  match s:
    case SNil{}:
      match last:
        case True{}:
          count
        case False{}:
          U32.add(count, 1)
    case SCon{c, rest}:
      match c:
        case '\n':
          line_count.go(rest, U32.add(count, 1), True{})
        case _:
          line_count.go(rest, count, False{})

def line_count(text: String) -> U32:
  line_count.go(text, 0, True{})

def finding(long: Bool, path: String, max: U32, count: U32) -> List<&2, Lint.Diag>:
  match long:
    case True{}:
      [Lint.diag(Lint.Warning{}, "Keep the file to " ++ U32.show(max) ++ " lines; it has " ++ U32.show(count) ++ ".", Lint.Span{path, 0, 0})]
    case False{}:
      []

def check_source(+max: U32, path: String, +count: U32) -> List<&2, Lint.Diag>:
  finding(U32.is_gt(count, max), path, max, count)

def check(+max: U32, source: Lint.Source) -> List<&2, Lint.Diag>:
  match source:
    case Lint.Source{path, text, root}:
      check_source(max, path, line_count(text))

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  match input:
    case Lint.Input{root, sources, options}:
      IO.pure(List<&2, Lint.Diag>, check(Lint.option_number(options, "maxLines"), root))

def main() -> IO(Unit):
  Lint.serve(run)
