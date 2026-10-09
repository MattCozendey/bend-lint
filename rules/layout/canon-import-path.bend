# layout/canon-import-path: an import path is the shortest path from the
# importer to the file it names, and starts with ./ or ../. Base and hub
# imports are not paths, so the rule skips them. Bend resolves the written
# path, as text, from the importer's real folder, and so does this rule.
# Run: bun src/lint.ts file.bend --rules rules/layout/canon-import-path.bend --fix
import Base
import ../../src/bend/lint.bend as Lint

# Paths
# -----
def segments.step(p: String, acc: List<&2, String>) -> List<&2, String>:
  match p:
    case SNil{}:
      acc
    case SCon{'.', SNil{}}:
      acc
    case SCon{'.', SCon{'.', SNil{}}}:
      List.tail(&2, String, acc)
    case SCon{c, rest}:
      Con{SCon{c, rest}, acc}

# A path's segments, last first: "" and "." dropped, ".." applied.
def segments.go(parts: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}:
      acc
    case Con{p, rest}:
      segments.go(rest, segments.step(p, acc))

def segments(path: String) -> List<&2, String>:
  List.reverse(&2, String, segments.go(String.split(path, '/'), []))

# A drive letter and its colon, or "" when there is none.
def drive(s: String) -> String:
  match s:
    case SCon{d, SCon{':', rest}}:
      SCon{d, ":"}
    case _:
      ""

# The written path, from the folder of `file`. An absolute one keeps the
# drive of `file`.
def joined(file: String, +written: String) -> String:
  match written:
    case SCon{'/', rest}:
      drive(file) ++ written
    case _:
      file ++ "/../" ++ written

# Each segment of `from` as "..", then `to`.
def ups(from: List<&2, String>, to: List<&2, String>) -> List<&2, String>:
  match from:
    case Nil{}:
      to
    case Con{f, rest}:
      ups(rest, Con{"..", to})

# Whether both lists start with the same segment.
def same_head(from: List<&2, String>, to: List<&2, String>) -> Bool:
  match from to:
    case Con{a, as} Con{b, bs}:
      String.eq(a, b)
    case _ _:
      False{}

def relative.go(from: List<&2, String>, to: List<&2, String>, same: Bool) -> List<&2, String>:
  match from to same:
    case Con{a, +as} Con{b, +bs} True{}:
      relative.go(as, bs, same_head(as, bs))
    case f t _:
      ups(f, t)

# The segments that lead from the folder `from` to `to`.
def relative(+from: List<&2, String>, +to: List<&2, String>) -> List<&2, String>:
  relative.go(from, to, same_head(from, to))

# The segments as a path that starts with ./ or ../.
def canon(+parts: List<&2, String>) -> String:
  match parts:
    case Con{SCon{'.', SCon{'.', SNil{}}}, rest}:
      String.join(parts, "/")
    case _:
      "./" ++ String.join(parts, "/")

# Import lines
# ------------

# The text of the line that holds offset `n` of `s`, up to `n`.
def line_before(s: String, n: Nat, line: String) -> String:
  match s n:
    case _ 0n:
      String.reverse(line)
    case SNil{} _:
      String.reverse(line)
    case SCon{'\n', rest} 1n+k:
      line_before(rest, k, "")
    case SCon{c, rest} 1n+k:
      line_before(rest, k, SCon{c, line})

def drop_blank(+s: String) -> String:
  match s:
    case SCon{' ', rest}:
      drop_blank(rest)
    case SCon{'\t', rest}:
      drop_blank(rest)
    case _:
      s

# The text up to the first blank.
def word(s: String) -> String:
  match s:
    case SCon{' ', rest}:
      ""
    case SCon{'\t', rest}:
      ""
    case SCon{c, rest}:
      SCon{c, word(rest)}
    case SNil{}:
      ""

# What follows "import" and its blanks, on a line that ends before an alias.
def after_import(line: String) -> String:
  drop_blank(String.drop(drop_blank(line), 6n))

# Base, whose line has no path before the alias, and hub paths.
def skipped(+path: String) -> Bool:
  Bool.or(
    String.is_empty(path),
    Bool.or(String.contains(path, "@"), String.starts_with(path, "0x"))
  )

# Rule
# ----
def judge(same: Bool, +want: String, +span: Lint.Span) -> List<&2, Lint.Diag>:
  match same:
    case True{}:
      []
    case False{}:
      [
        Lint.Diag{
          Lint.Warning{},
          "Write \"" ++ want ++ "\": the shortest path from this file, starting with ./ or ../.",
          Some{span},
          [Lint.Fix{"Use the shortest path", Lint.Safe{}, [Lint.Edit{span, want}]}],
          None{}
        }
      ]

def judge.of(+want: String, +written: String, +file: String, +beg: U32) -> List<&2, Lint.Diag>:
  judge(
    String.eq(want, written),
    want,
    Lint.Span{file, beg, U32.add(beg, U32.from_nat(String.length(written)))}
  )

def path_at(skip: Bool, +file: String, +written: String, +beg: U32) -> List<&2, Lint.Diag>:
  match skip:
    case True{}:
      []
    case False{}:
      judge.of(
        canon(relative(segments(file ++ "/.."), segments(joined(file, written)))),
        written,
        file,
        beg
      )

# The import's path ends where its blanks before "as" begin; `after` runs
# from the path to the alias at `beg`.
def path_of(+file: String, +after: String, +beg: U32) -> List<&2, Lint.Diag>:
  path_at(skipped(word(after)), file, word(after), U32.sub(beg, U32.from_nat(String.length(after))))

def check(+text: String, d: Lint.Declaration) -> List<&2, Lint.Diag>:
  match d:
    case Lint.Declaration{Lint.Import{}, name, owner, Lint.Span{file, +beg, end}, refs}:
      path_of(file, after_import(line_before(text, U32.to_nat(beg), "")), beg)
    case _:
      []

def findings(
  ds: List<&2, Lint.Declaration>,
  +text: String,
  acc: List<&2, Lint.Diag>
) -> List<&2, Lint.Diag>:
  match ds:
    case Nil{}:
      List.reverse(&2, Lint.Diag, acc)
    case Con{d, rest}:
      findings(rest, text, List.append(&2, Lint.Diag, check(text, d), acc))

def id() -> String:
  "layout/canon-import-path"

def facts() -> Lint.Want:
  Lint.NoFacts{}

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  match input:
    case Lint.Input{root, sources, options, prior}:
      match root:
        case Lint.Source{path, text, is_root}:
          IO.bind(
            List<&2, Lint.Declaration>,
            List<&2, Lint.Diag>,
            Lint.declarations(),
            ds => IO.pure(List<&2, Lint.Diag>, findings(ds, text, []))
          )

def main() -> IO(Unit):
  Lint.serve(run)
