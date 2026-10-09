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
# PascalCase is a capital, then letters and digits: `IO`, `OP` and `U32`
# pass. snake_case has no capital. A dotted name is checked by its last
# segment; the segments before it name its parent, checked where the parent
# is declared. The type is the written one; a name without one is
# snake_case. import Base, and a def that fills a law of another file, are
# skipped: their names are not this file's to choose. The fix renames a
# parameter or variable and its uses, when each use is written as the name
# and the new name is not in use in its def. Other names can be used by
# other files, so they get no fix.
# Run: bun src/lint.ts file.bend --rules rules/layout/case.bend --fix-suggested
import Base
import ../../src/bend/lint.bend as Lint
import ../shared.bend as Shared

# Types
# =====

# Either: a name with no written type, which can be a type or not.
type Case is Data:
  Pascal{}
  Snake{}
  Either{}

# Case
# ====

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

# What a shown type gives after its last arrow. `seg`: the part so far,
# last character first.
def codomain(s: String, seg: String) -> String:
  match s:
    case SNil{}:
      String.reverse(seg)
    case SCon{'-', SCon{'>', SCon{' ', rest}}}:
      codomain(rest, "")
    case SCon{c, rest}:
      codomain(rest, SCon{c, seg})

# Whether a shown type is a sort, or a function that returns one.
def sort(shown: String) -> Bool:
  +end = codomain(shown, "")
  Bool.or(
    Bool.or(String.eq(end, "Type"), String.eq(end, "Data")),
    String.eq(String.take(end, 5n), "Kind(")
  )

def typed(+shown: String) -> Case:
  Bool.pick(Case, String.is_empty(shown), Either{}, Bool.pick(Case, sort(shown), Pascal{}, Snake{}))

def wanted(kind: Lint.DeclarationKind, +shown: String) -> Case:
  match kind:
    case Lint.Import{}:
      Pascal{}
    case Lint.Datatype{}:
      Pascal{}
    case Lint.Constructor{}:
      Pascal{}
    case _:
      typed(shown)

# A name of `kind`, in a message. `sort`: whether it is a type.
def noun(kind: Lint.DeclarationKind, sort: Bool) -> String:
  match kind sort:
    case Lint.Import{} _:
      "an import alias"
    case Lint.Datatype{} _:
      "a type"
    case Lint.Constructor{} _:
      "a constructor"
    case Lint.Definition{} True{}:
      "a def that returns a type"
    case Lint.Definition{} False{}:
      "a def that does not return a type"
    case Lint.Parameter{} True{}:
      "a parameter that is a type"
    case Lint.Parameter{} False{}:
      "a parameter that is not a type"
    case Lint.Field{} True{}:
      "a field that is a type"
    case Lint.Field{} False{}:
      "a field that is not a type"
    case Lint.Variable{} _:
      "a variable"

def what(kind: Lint.DeclarationKind, want: Case) -> String:
  match want:
    case Pascal{}:
      noun(kind, True{}) ++ " is PascalCase"
    case Snake{}:
      noun(kind, False{}) ++ " is snake_case"
    case Either{}:
      "this name is snake_case, or PascalCase if it is a type"

# The last segment of a dotted name. `seg` is the segment so far, last
# character first.
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

# `s` in snake_case: a word starts at a capital after a small letter or
# digit, or at the last capital of a run before a small letter. `capital`:
# whether `s` starts with a capital. `prev`: the character before is none
# or `_` (0), a small letter or digit (1), or a capital (2). `acc`: the
# result so far, last character first.
def snake(s: String, capital: Bool, +prev: U32, acc: String) -> String:
  match s capital:
    case SNil{} _:
      String.reverse(acc)
    case SCon{c, +rest} True{}:
      snake(
        rest,
        capital_head(rest),
        2,
        snake_cap(Bool.or(U32.is_eq(prev, 1), Bool.and(U32.is_eq(prev, 2), small_head(rest))), c, acc)
      )
    case SCon{+c, +rest} False{}:
      snake(rest, capital_head(rest), Bool.pick(U32, Char.is_eq(c, '_'), 0, 1), SCon{c, acc})

# `s` in PascalCase: `_` goes, and the character after it becomes a capital.
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

# Fix
# ===

def spans(refs: List<&2, Lint.Reference>) -> List<&2, Lint.Span>:
  match refs:
    case Nil{}:
      []
    case Con{Lint.Reference{owner, span}, rest}:
      Con{span, spans(rest)}

def kept(hit: Bool, x: Lint.Span, xs: List<&2, Lint.Span>) -> List<&2, Lint.Span>:
  match hit:
    case True{}:
      Con{x, xs}
    case False{}:
      xs

def owned_spans(refs: List<&2, Lint.Reference>, +o: String) -> List<&2, Lint.Span>:
  match refs:
    case Nil{}:
      []
    case Con{Lint.Reference{owner, span}, rest}:
      kept(String.eq(owner, o), span, owned_spans(rest, o))

# The spans of the uses inside def `o`, of any declaration.
def uses_in(ds: List<&2, Lint.Declaration>, +o: String) -> List<&2, Lint.Span>:
  match ds:
    case Nil{}:
      []
    case Con{Lint.Declaration{kind, name, owner, span, refs, loads, fills, term}, rest}:
      List.append(&2, Lint.Span, owned_spans(refs, o), uses_in(rest, o))

def owned_name(owner: Maybe<&2, String>, +o: String, name: String) -> List<&2, String>:
  match owner:
    case Some{x}:
      Bool.pick(List<&2, String>, String.eq(x, o), [name], [])
    case None{}:
      []

# The names declared inside def `o`.
def names_in(ds: List<&2, Lint.Declaration>, +o: String) -> List<&2, String>:
  match ds:
    case Nil{}:
      []
    case Con{Lint.Declaration{kind, name, owner, span, refs, loads, fills, term}, rest}:
      List.append(&2, String, owned_name(owner, o, name), names_in(rest, o))

def all_are(xs: List<&2, String>, +x: String) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{y, rest}:
      Bool.and(String.eq(y, x), all_are(rest, x))

def edits(ss: List<&2, Lint.Span>, +to: String) -> List<&2, Lint.Edit>:
  match ss:
    case Nil{}:
      []
    case Con{s, rest}:
      Con{Lint.Edit{s, to}, edits(rest, to)}

def renames(ok: Bool, +to: String, +span: Lint.Span, refs: List<&2, Lint.Reference>) -> List<&2, Lint.Fix> :
  match ok:
    case True{}:
      [Lint.Fix{"Rename to " ++ to, Lint.Suggested{}, edits(Con{span, spans(refs)}, to)}]
    case False{}:
      []

# The rename of a parameter or variable of def `o`: each use is written as
# `name`, and `to` is not in use in `o`.
def rename(
  +ds: List<&2, Lint.Declaration>,
  +o: String,
  +name: String,
  +to: String,
  +span: Lint.Span,
  +refs: List<&2, Lint.Reference>
) -> IO(List<&2, Lint.Fix>):
  do IO<List<&2, Lint.Fix>>:
    own : List<&2, String> <- Shared.texts(spans(refs))
    near : List<&2, String> <- Shared.texts(uses_in(ds, o))
    return renames(
      Bool.and(
        all_are(own, name),
        Bool.not(Bool.or(Shared.known(near, to), Shared.known(names_in(ds, o), to)))
      ),
      to,
      span,
      refs
    )

def local(kind: Lint.DeclarationKind) -> Bool:
  match kind:
    case Lint.Parameter{}:
      True{}
    case Lint.Variable{}:
      True{}
    case _:
      False{}

def fixes(
  +ds: List<&2, Lint.Declaration>,
  fixable: Bool,
  owner: Maybe<&2, String>,
  +name: String,
  +to: String,
  +span: Lint.Span,
  +refs: List<&2, Lint.Reference>
) -> IO(List<&2, Lint.Fix>):
  match fixable owner:
    case True{} Some{o}:
      rename(ds, o, name, to, span, refs)
    case _ _:
      IO.pure(List<&2, Lint.Fix>, [])

# Rule
# ====

# A finding for a name that does not fit: renamed to `to` when `to` fits.
def misfit(
  +ds: List<&2, Lint.Declaration>,
  +kind: Lint.DeclarationKind,
  +want: Case,
  owner: Maybe<&2, String>,
  +name: String,
  +span: Lint.Span,
  +refs: List<&2, Lint.Reference>
) -> IO(List<&2, Lint.Diag>):
  +seg = segment(name, "")
  +to = String.take(name, Nat.sub(String.length(name), String.length(seg))) ++ recased(want, seg)
  +ok = fits(want, recased(want, seg))
  +message = Bool.pick(String, ok, "Rename " ++ name ++ " to " ++ to, "Rename " ++ name)
    ++ ": "
    ++ what(kind, want)
    ++ "."
  IO.bind(
    List<&2, Lint.Fix>,
    List<&2, Lint.Diag>,
    fixes(ds, Bool.and(ok, local(kind)), owner, name, to, span, refs),
    fs => IO.pure(List<&2, Lint.Diag>, [Lint.Diag{Lint.Warning{}, message, Some{span}, fs, None{}}])
  )

def verdict(
  fit: Bool,
  +ds: List<&2, Lint.Declaration>,
  +kind: Lint.DeclarationKind,
  +want: Case,
  owner: Maybe<&2, String>,
  +name: String,
  +span: Lint.Span,
  +refs: List<&2, Lint.Reference>
) -> IO(List<&2, Lint.Diag>):
  match fit:
    case True{}:
      IO.pure(List<&2, Lint.Diag>, [])
    case False{}:
      misfit(ds, kind, want, owner, name, span, refs)

def judge(
  +ds: List<&2, Lint.Declaration>,
  +kind: Lint.DeclarationKind,
  owner: Maybe<&2, String>,
  +name: String,
  +span: Lint.Span,
  +refs: List<&2, Lint.Reference>,
  +shown: String
) -> IO(List<&2, Lint.Diag>):
  +want = wanted(kind, shown)
  verdict(fits(want, segment(name, "")), ds, kind, want, owner, name, span, refs)

def shown(term: Maybe<&2, Lint.Term>) -> IO(String):
  match term:
    case Some{t}:
      Lint.show(t)
    case None{}:
      IO.pure(String, "")

def check(+ds: List<&2, Lint.Declaration>, d: Lint.Declaration) -> IO(List<&2, Lint.Diag>):
  match d:
    case Lint.Declaration{kind, name, owner, span, refs, loads, True{}, term}:
      IO.pure(List<&2, Lint.Diag>, [])
    case Lint.Declaration{Lint.Import{}, "Base", owner, span, refs, loads, fills, term}:
      IO.pure(List<&2, Lint.Diag>, [])
    case Lint.Declaration{kind, name, owner, span, refs, loads, fills, term}:
      IO.bind(String, List<&2, Lint.Diag>, shown(term), s => judge(ds, kind, owner, name, span, refs, s))

def checks(
  +all: List<&2, Lint.Declaration>,
  ds: List<&2, Lint.Declaration>,
  acc: List<&2, Lint.Diag>
) -> IO(List<&2, Lint.Diag>):
  match ds:
    case Nil{}:
      IO.pure(List<&2, Lint.Diag>, List.reverse(&2, Lint.Diag, acc))
    case Con{d, rest}:
      IO.bind(
        List<&2, Lint.Diag>,
        List<&2, Lint.Diag>,
        check(all, d),
        found => checks(all, rest, List.append(&2, Lint.Diag, found, acc))
      )

def start(+ds: List<&2, Lint.Declaration>) -> IO(List<&2, Lint.Diag>):
  checks(ds, ds, [])

def id() -> String:
  "layout/case"

def facts() -> Lint.Want:
  Lint.NoFacts{}

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  IO.bind(List<&2, Lint.Declaration>, List<&2, Lint.Diag>, Lint.declarations(), ds => start(ds))

def main() -> IO(Unit):
  Lint.serve(run)
