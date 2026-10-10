# layout/case: a name's case follows the kind of what it names.
#
# | Kind                                             | Case              | Examples                     |
# | ------------------------------------------------ | ----------------- | ---------------------------- |
# | type, constructor, import alias                  | PascalCase        | `Maybe`, `Some{}`, `M`       |
# | def that returns `Type`, `Data` or `Kind(..)`    | PascalCase        | `IO`, `Pair`, `Set()`        |
# | parameter or field of type `Type`, `Data`, `Kind`| PascalCase        | `-A: Type`, `-A: Kind(a)`    |
# | law, other def, parameter or field, variable     | snake_case        | `add_comm`, `from_list`, `a` |
# | namespace segment                                | its parent's case | `IO.print`, `Set.from_list`  |
#
# PascalCase is a capital, then letters and digits: `IO`, `OP` and `U32` pass. snake_case has no capital. A dotted
# name is checked by its last segment; the segments before it name its parent, checked where the parent is declared.
# The type is the written one; a name without one takes either case. import Base, and a def that fills a law of
# another file, are skipped: their names are not this file's to choose. The fix renames a parameter or variable and
# its uses, when each use is written as the name and the new name is not in use in its def; it is Dangerous, so
# --fix alone does not rename. Other names can be used by other files, so they get no fix.
# The rename may well be Safe: it touches only a def's own bindings, and only to a name the def does not use. It
# stays Dangerous until that is shown.
import Base
import ../../main.bend as Lint
import ../shared.bend as Shared

type Case is Data:
  Pascal{}
  Snake{}
  Either{}

def no_underscore(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{'_', rest}:
      False{}
    case SCon{c, rest}:
      no_underscore(rest)

def no_capital(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, rest}:
      Bool.and(Bool.not(Char.is_upper(c)), no_capital(rest))

def is_pascal(s: String) -> Bool:
  match s:
    case SCon{c, rest}:
      Bool.and(Char.is_upper(c), no_underscore(rest))
    case SNil{}:
      False{}

def is_snake(+s: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(s)), no_capital(s))

def fits(want: Case, +s: String) -> Bool:
  match want:
    case Pascal{}:
      is_pascal(s)
    case Snake{}:
      is_snake(s)
    case Either{}:
      Bool.or(is_pascal(s), is_snake(s))

def typed.of(sort: Bool) -> Case:
  match sort:
    case True{}:
      Pascal{}
    case False{}:
      Snake{}

def typed(written: Maybe<&2, Lint.BendType>) -> Case:
  match written:
    case None{}:
      Either{}
    case Some{Lint.BendType{id, shown, term}}:
      typed.of(Shared.get_ends_in_sort(term))

def written_of(kind: Lint.DeclarationKind) -> Maybe<&2, Lint.BendType>:
  match kind:
    case Lint.DefDeclaration{fills, written_type, body}:
      written_type
    case Lint.DatatypeDeclaration{written_type}:
      written_type
    case Lint.ParameterDeclaration{owner, written_type}:
      written_type
    case Lint.FieldDeclaration{owner, written_type}:
      written_type
    case _:
      None{}

def owner_of(kind: Lint.DeclarationKind) -> Maybe<&2, String>:
  match kind:
    case Lint.ConstructorDeclaration{owner}:
      Some{owner}
    case Lint.ParameterDeclaration{owner, written_type}:
      Some{owner}
    case Lint.VariableDeclaration{owner}:
      Some{owner}
    case Lint.FieldDeclaration{owner, written_type}:
      Some{owner}
    case _:
      None{}

def wanted(kind: Lint.DeclarationKind, written: Maybe<&2, Lint.BendType>) -> Case:
  match kind:
    case Lint.ImportDeclaration{loads}:
      Pascal{}
    case Lint.DatatypeDeclaration{written_type}:
      Pascal{}
    case Lint.ConstructorDeclaration{owner}:
      Pascal{}
    case _:
      typed(written)

def noun(kind: Lint.DeclarationKind, sort: Bool) -> String:
  match kind sort:
    case Lint.ImportDeclaration{loads} _:
      "an import alias"
    case Lint.DatatypeDeclaration{written_type} _:
      "a type"
    case Lint.ConstructorDeclaration{owner} _:
      "a constructor"
    case Lint.DefDeclaration{fills, written_type, body} True{}:
      "a def that returns a type"
    case Lint.DefDeclaration{fills, written_type, body} False{}:
      "a def that does not return a type"
    case Lint.ParameterDeclaration{owner, written_type} True{}:
      "a parameter that is a type"
    case Lint.ParameterDeclaration{owner, written_type} False{}:
      "a parameter that is not a type"
    case Lint.FieldDeclaration{owner, written_type} True{}:
      "a field that is a type"
    case Lint.FieldDeclaration{owner, written_type} False{}:
      "a field that is not a type"
    case Lint.VariableDeclaration{owner} _:
      "a variable"

def what(kind: Lint.DeclarationKind, want: Case) -> String:
  match want:
    case Pascal{}:
      noun(kind, True{}) ++ " is PascalCase"
    case Snake{}:
      noun(kind, False{}) ++ " is snake_case"
    case Either{}:
      "this name is snake_case, or PascalCase if it is a type"

def segment(s: String, seg: String) -> String:
  match s:
    case SNil{}:
      String.reverse(seg)
    case SCon{'.', rest}:
      segment(rest, "")
    case SCon{c, rest}:
      segment(rest, SCon{c, seg})

def small_head(s: String) -> Bool:
  match s:
    case SCon{c, rest}:
      Char.is_lower(c)
    case SNil{}:
      False{}

def capital_head(s: String) -> Bool:
  match s:
    case SCon{c, rest}:
      Char.is_upper(c)
    case SNil{}:
      False{}

def snake_cap(cut: Bool, c: Char, acc: String) -> String:
  match cut:
    case True{}:
      SCon{Char.to_lower(c), SCon{'_', acc}}
    case False{}:
      SCon{Char.to_lower(c), acc}

def snake(s: String, capital: Bool, +prev: U32, acc: String) -> String:
  match s capital:
    case SNil{} _:
      String.reverse(acc)
    case SCon{c, +rest} True{}:
      snake(
        rest,
        capital_head(rest),
        2,
        snake_cap(
          Bool.or(U32.is_eq(prev, 1), Bool.and(U32.is_eq(prev, 2), small_head(rest))),
          c,
          acc
        )
      )
    case SCon{+c, +rest} False{}:
      snake(rest, capital_head(rest), Bool.pick(U32, Char.is_eq(c, '_'), 0, 1), SCon{c, acc})

def pascal(s: String, up: Bool, acc: String) -> String:
  match s up:
    case SNil{} _:
      String.reverse(acc)
    case SCon{'_', rest} _:
      pascal(rest, True{}, acc)
    case SCon{c, rest} True{}:
      pascal(rest, False{}, SCon{Char.to_upper(c), acc})
    case SCon{c, rest} False{}:
      pascal(rest, False{}, SCon{c, acc})

def recased(want: Case, +s: String) -> String:
  match want:
    case Pascal{}:
      pascal(s, True{}, "")
    case _:
      snake(s, capital_head(s), 0, "")

def spans(refs: List<&2, Lint.DeclarationReference>) -> List<&2, Lint.BendSourceSpan>:
  match refs:
    case Nil{}:
      []
    case Con{Lint.DeclarationReference{owner, span}, rest}:
      span <> spans(rest)

def kept(
  hit: Bool,
  x: Lint.BendSourceSpan,
  xs: List<&2, Lint.BendSourceSpan>
) -> List<&2, Lint.BendSourceSpan>:
  match hit:
    case True{}:
      x <> xs
    case False{}:
      xs

def owned_spans(
  refs: List<&2, Lint.DeclarationReference>,
  +o: String
) -> List<&2, Lint.BendSourceSpan>:
  match refs:
    case Nil{}:
      []
    case Con{Lint.DeclarationReference{owner, span}, rest}:
      kept(String.eq(owner, o), span, owned_spans(rest, o))

def uses_in(ds: List<&2, Lint.Declaration>, +o: String) -> List<&2, Lint.BendSourceSpan>:
  match ds:
    case Nil{}:
      []
    case Con{Lint.Declaration{name, span, references, kind}, rest}:
      List.append(&2, Lint.BendSourceSpan, owned_spans(references, o), uses_in(rest, o))

def owned_name(owner: Maybe<&2, String>, +o: String, name: String) -> List<&2, String>:
  match owner:
    case Some{x}:
      Bool.pick(List<&2, String>, String.eq(x, o), [name], [])
    case None{}:
      []

def names_in(ds: List<&2, Lint.Declaration>, +o: String) -> List<&2, String>:
  match ds:
    case Nil{}:
      []
    case Con{Lint.Declaration{name, span, references, kind}, rest}:
      List.append(&2, String, owned_name(owner_of(kind), o, name), names_in(rest, o))

def texts(ss: List<&2, Lint.BendSourceSpan>, +lines: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}:
      []
    case Con{s, rest}:
      Shared.get_span_text(lines, s) <> texts(rest, lines)

def all_are(xs: List<&2, String>, +x: String) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{y, rest}:
      Bool.and(String.eq(y, x), all_are(rest, x))

def edits(ss: List<&2, Lint.BendSourceSpan>, +to: String) -> List<&2, Lint.FixEdit>:
  match ss:
    case Nil{}:
      []
    case Con{s, rest}:
      Lint.ReplaceText{s, to} <> edits(rest, to)

def renames(
  ok: Bool,
  +to: String,
  span: Lint.BendSourceSpan,
  refs: List<&2, Lint.DeclarationReference>
) -> List<&2, Lint.Fix>:
  match ok:
    case True{}:
      [Lint.Fix{"Rename to " ++ to, Lint.Dangerous{}, edits(span <> spans(refs), to)}]
    case False{}:
      []

def rename(
  +ds: List<&2, Lint.Declaration>,
  +lines: List<&2, String>,
  +o: String,
  +name: String,
  +to: String,
  span: Lint.BendSourceSpan,
  +refs: List<&2, Lint.DeclarationReference>
) -> List<&2, Lint.Fix>:
  renames(
    Bool.and(
      all_are(texts(spans(refs), lines), name),
      Bool.not(
        Bool.or(
          Shared.get_has(texts(uses_in(ds, o), lines), to),
          Shared.get_has(names_in(ds, o), to)
        )
      )
    ),
    to,
    span,
    refs
  )

def local(kind: Lint.DeclarationKind) -> Bool:
  match kind:
    case Lint.ParameterDeclaration{owner, written_type}:
      True{}
    case Lint.VariableDeclaration{owner}:
      True{}
    case _:
      False{}

def fixes(
  +ds: List<&2, Lint.Declaration>,
  +lines: List<&2, String>,
  fixable: Bool,
  owner: Maybe<&2, String>,
  +name: String,
  +to: String,
  span: Lint.BendSourceSpan,
  +refs: List<&2, Lint.DeclarationReference>
) -> List<&2, Lint.Fix>:
  match fixable owner:
    case True{} Some{o}:
      rename(ds, lines, o, name, to, span, refs)
    case _ _:
      []

def misfit(
  +ds: List<&2, Lint.Declaration>,
  +lines: List<&2, String>,
  +kind: Lint.DeclarationKind,
  +want: Case,
  +name: String,
  +span: Lint.BendSourceSpan,
  +refs: List<&2, Lint.DeclarationReference>
) -> List<&2, Lint.Finding>:
  +seg = segment(name, "")
  +to = String.take(name, Nat.sub(String.length(name), String.length(seg))) ++ recased(want, seg)
  +ok = fits(want, recased(want, seg))
  +message = Bool.pick(
    String,
    ok,
    "Rename " ++ name ++ " to " ++ to,
    "Rename " ++ name
  )
    ++ ": "
    ++ what(kind, want)
    ++ "."
  [
    Lint.Finding{
      Lint.Warning{},
      message,
      span,
      fixes(ds, lines, Bool.and(ok, local(kind)), owner_of(kind), name, to, span, refs)
    }
  ]

def verdict(
  fit: Bool,
  +ds: List<&2, Lint.Declaration>,
  +lines: List<&2, String>,
  +kind: Lint.DeclarationKind,
  +want: Case,
  +name: String,
  +span: Lint.BendSourceSpan,
  +refs: List<&2, Lint.DeclarationReference>
) -> List<&2, Lint.Finding>:
  match fit:
    case True{}:
      []
    case False{}:
      misfit(ds, lines, kind, want, name, span, refs)

def check(
  +ds: List<&2, Lint.Declaration>,
  +lines: List<&2, String>,
  d: Lint.Declaration
) -> List<&2, Lint.Finding>:
  match d:
    case Lint.Declaration{name, span, references, Lint.DefDeclaration{True{}, written_type, body}}:
      []
    case Lint.Declaration{"Base", span, references, Lint.ImportDeclaration{loads}}:
      []
    case Lint.Declaration{+name, +span, +references, +kind}:
      +want = wanted(kind, written_of(kind))
      verdict(fits(want, segment(name, "")), ds, lines, kind, want, name, span, references)

def checks(
  +all: List<&2, Lint.Declaration>,
  +lines: List<&2, String>,
  ds: List<&2, Lint.Declaration>
) -> List<&2, Lint.Finding>:
  match ds:
    case Nil{}:
      []
    case Con{d, rest}:
      List.append(&2, Lint.Finding, check(all, lines, d), checks(all, lines, rest))

def run(input: Lint.RuleInput) -> List<&2, Lint.Finding>:
  match input:
    case Lint.RuleInput{root, sources, options, prior, declarations}:
      match root:
        case Lint.BendSource{+path, text, +lines}:
          +ds = Shared.get_declarations_of(declarations, path)
          checks(ds, lines, ds)

def rules() -> List<&1, Lint.Rule>:
  [Lint.Rule{"layout/case", Lint.FileScope{}, [], [], [Lint.DeclarationsNeed{}], run}]
