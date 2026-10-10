# layout/canon-import-path: an import path is the shortest path from the importer to the file it names, and starts
# with ./ or ../. Base and hub imports are not paths, so the rule skips them. It compares with the real path of the
# file the import loads, symlinks resolved. The fix writes the shortest path; the import line is blanked before the
# runner checks it, so the fix stays Safe.
import Base
import ../../main.bend as Lint
import ../shared.bend as Shared

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

def segments.go(parts: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}:
      acc
    case Con{p, rest}:
      segments.go(rest, segments.step(p, acc))

def segments(path: String) -> List<&2, String>:
  List.reverse(&2, String, segments.go(String.split(path, '/'), []))

def ups(from: List<&2, String>, to: List<&2, String>) -> List<&2, String>:
  match from:
    case Nil{}:
      to
    case Con{f, rest}:
      ups(rest, Con{"..", to})

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

def relative(+from: List<&2, String>, +to: List<&2, String>) -> List<&2, String>:
  relative.go(from, to, same_head(from, to))

def canon(+parts: List<&2, String>) -> String:
  match parts:
    case Con{SCon{'.', SCon{'.', SNil{}}}, rest}:
      String.join(parts, "/")
    case _:
      "./" ++ String.join(parts, "/")

def skipped(+path: String) -> Bool:
  Bool.or(
    String.is_empty(path),
    Bool.or(String.contains(path, "@"), String.starts_with(path, "0x"))
  )

def judge(same: Bool, +want: String, +span: Lint.BendSourceSpan) -> List<&2, Lint.Finding>:
  match same:
    case True{}:
      []
    case False{}:
      [
        Lint.Finding{
          Lint.Warning{},
          "Write \"" ++ want ++ "\": the shortest path from this file, starting with ./ or ../.",
          span,
          [Lint.Fix{"Use the shortest path", Lint.Safe{}, [Lint.ReplaceText{span, want}]}]
        }
      ]

def judge.of(+want: String, +written: String, +file: String, +beg: U32) -> List<&2, Lint.Finding>:
  judge(
    String.eq(want, written),
    want,
    Lint.BendSourceSpan{file, beg, U32.add(beg, U32.from_nat(String.length(written)))}
  )

def path_at(
  skip: Bool,
  +file: String,
  target: String,
  +written: String,
  +beg: U32
) -> List<&2, Lint.Finding>:
  match skip:
    case True{}:
      []
    case False{}:
      judge.of(canon(relative(segments(file ++ "/.."), segments(target))), written, file, beg)

def path_of(+file: String, target: String, +after: String, +beg: U32) -> List<&2, Lint.Finding>:
  path_at(
    skipped(Shared.get_word(after)),
    file,
    target,
    Shared.get_word(after),
    U32.sub(beg, U32.from_nat(String.length(after)))
  )

def check(+lines: List<&2, String>, d: Lint.Declaration) -> List<&2, Lint.Finding>:
  match d:
    case Lint.Declaration{
      name,
      Lint.BendSourceSpan{file, +beg, end},
      references,
      Lint.ImportDeclaration{target}
    }:
      path_of(file, target, Shared.get_after_import(Shared.get_line_before(lines, beg)), beg)
    case _:
      []

def findings(ds: List<&2, Lint.Declaration>, +lines: List<&2, String>) -> List<&2, Lint.Finding>:
  match ds:
    case Nil{}:
      []
    case Con{d, rest}:
      List.append(&2, Lint.Finding, check(lines, d), findings(rest, lines))

def lint(input: Lint.RuleInput) -> List<&2, Lint.Finding>:
  match input:
    case Lint.RuleInput{root, sources, options, prior, declarations, instances}:
      match root:
        case Lint.BendSource{+path, text, +lines}:
          findings(Shared.get_declarations_of(declarations, path), lines)

def run(input: Lint.RuleInput) -> Lint.RuleStep:
  Lint.RuleDone{lint(input)}

def rules() -> List<&1, Lint.Rule>:
  [Lint.Rule{"layout/canon-import-path", Lint.FileScope{}, [], [], [Lint.DeclarationsNeed{}], run}]
