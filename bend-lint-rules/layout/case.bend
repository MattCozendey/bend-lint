# layout/case: a name whose case does not follow the kind of what it names.
# Fix: renames the declaration, with its uses.
# Heuristics: the kind comes from the syntax and the written types, not from the checker:
#
# | Kind                                              | Case              | Examples                     |
# | ------------------------------------------------- | ----------------- | ---------------------------- |
# | type, constructor, import alias                   | PascalCase        | `Maybe`, `Some{}`, `M`       |
# | def whose written return type ends in a sort      | PascalCase        | `IO`, `Pair`, `Set()`        |
# | parameter or field whose written type ends in one | PascalCase        | `-A: Type`, `F: U32 -> Type` |
# | law, other def, parameter or field                | snake_case        | `add_comm`, `from_list`, `n` |
# | variable, lambda, forall, def without a return    | either            | `Big`, `small`               |
# | namespace segment                                 | its parent's case | `IO.print`, `Set.from_list`  |
#
# A sort is `Type`, `Data` or `Kind(..)`; a type ends in one when it is one, or a function type whose
# result does. A binder written bare (`<a>`, `(x)`) is a quantity, so snake_case. PascalCase is a
# capital, then letters and digits: `IO`, `OP` and `U32` pass. snake_case has no capital. A dotted
# name is checked by its last segment; the segments before it name its parent, checked where the parent
# is declared. `import Base`, and a def that fills a law of another file, are skipped: their names are
# not this file's to choose.
import Base
import ../../src/linter/lint.bend as Lint
import ../../src/shared/lists.bend as Lists
import ../../src/shared/strings.bend as Strings

# Types
# =====
type Case is Data:
  Pascal{}
  Snake{}
  Either{}

# Case
# ====
def has_no_underscore(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{'_', rest}:
      False{}
    case SCon{c, rest}:
      has_no_underscore(rest)

def has_no_capital(s: String, ok: Bool) -> Bool:
  match s ok:
    case _ False{}:
      False{}
    case SNil{} True{}:
      True{}
    case SCon{c, rest} True{}:
      has_no_capital(rest, Bool.not(Char.is_upper(c)))

def is_pascal.rest(upper: Bool, rest: String) -> Bool:
  match upper:
    case True{}:
      has_no_underscore(rest)
    case False{}:
      False{}

def is_pascal(s: String) -> Bool:
  match s:
    case SCon{c, rest}:
      is_pascal.rest(Char.is_upper(c), rest)
    case SNil{}:
      False{}

def is_snake.of(empty: Bool, s: String) -> Bool:
  match empty:
    case True{}:
      False{}
    case False{}:
      has_no_capital(s, True{})

def is_snake(+s: String) -> Bool:
  is_snake.of(String.is_empty(s), s)

def fits(want: Case, +s: String) -> Bool:
  match want:
    case Pascal{}:
      is_pascal(s)
    case Snake{}:
      is_snake(s)
    case Either{}:
      Bool.or(is_pascal(s), is_snake(s))

def has_small_head(s: String) -> Bool:
  match s:
    case SCon{c, rest}:
      Char.is_lower(c)
    case SNil{}:
      False{}

def has_capital_head(s: String) -> Bool:
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

# `s` in snake_case: a word starts at a capital after a small letter or digit, or at the last capital of a run before a
# small letter. `capital`: whether `s` starts with a capital. `prev`: the character before is none or `_` (0), a small
# letter or digit (1), or a capital (2). `acc`: the result so far, last character first.
def snake(s: String, capital: Bool, +prev: U32, acc: String) -> String:
  match s capital:
    case SNil{} _:
      String.reverse(acc)
    case SCon{c, +rest} True{}:
      snake(
        rest,
        has_capital_head(rest),
        2,
        snake_cap(
          Bool.or(U32.is_eq(prev, 1), Bool.and(U32.is_eq(prev, 2), has_small_head(rest))),
          c,
          acc
        )
      )
    case SCon{+c, +rest} False{}:
      snake(rest, has_capital_head(rest), Bool.pick(U32, Char.is_eq(c, '_'), 0, 1), SCon{c, acc})

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
      snake(s, has_capital_head(s), 0, "")

# Written types
# =============

# Whether the type the last of `nodes` writes ends in a sort: it is one, or a function type whose result does.
def ends(nodes: List<&2, Lint.Node>) -> Bool:
  match nodes:
    case Con{Lint.Node{Lint.Sort{}, n, s, k, f}, Nil{}}:
      True{}
    case Con{Lint.Node{Lint.Forall{b, q}, n, s, kids, f}, Nil{}}:
      ends(kids)
    case Con{x, Nil{}}:
      False{}
    case Con{x, rest}:
      ends(rest)
    case Nil{}:
      False{}

# The case of a name whose written type is the last of `nodes`: none written, either.
def typed(+nodes: List<&2, Lint.Node>) -> Case:
  match nodes:
    case Nil{}:
      Either{}
    case _:
      Bool.pick(Case, ends(nodes), Pascal{}, Snake{})

# The case of a def's name, by its written return type, among its nodes.
def returns(nodes: List<&2, Lint.Node>) -> Case:
  match nodes:
    case Nil{}:
      Either{}
    case Con{Lint.Node{Lint.Returns{}, n, s, kids, f}, rest}:
      typed(kids)
    case Con{x, rest}:
      returns(rest)

# Rule
# ====

# The case a declaration's name takes, if the file chooses it.
def wanted(+node: Lint.Node, namespace: String) -> Maybe<&2, Case>:
  match node:
    case Lint.Node{Lint.Import{t}, name, s, k, f}:
      Lists.when(Case, Bool.not(String.eq(name, "Base")), Pascal{})
    case Lint.Node{Lint.Datatype{t}, name, s, k, f}:
      Some{Pascal{}}
    case Lint.Node{Lint.Constructor{t}, name, s, k, f}:
      Some{Pascal{}}
    case Lint.Node{Lint.Law{t}, name, s, k, f}:
      Some{Snake{}}
    case Lint.Node{Lint.Definition{t, u}, name, s, kids, f}:
      Lists.when(Case, String.eq(Lint.Name.namespace(t), namespace), returns(kids))
    case Lint.Node{Lint.Parameter{b, q}, name, s, kids, f}:
      Some{typed(kids)}
    case Lint.Node{Lint.Field{b, q}, name, s, kids, f}:
      Some{typed(kids)}
    case _:
      Some{Either{}}

# A name of `syntax`, in a message. `sort`: whether it is a type.
def noun(syntax: Lint.Syntax, sort: Bool) -> String:
  match syntax sort:
    case Lint.Import{t} _:
      "an import alias"
    case Lint.Datatype{t} _:
      "a type"
    case Lint.Constructor{t} _:
      "a constructor"
    case Lint.Law{t} _:
      "a law"
    case Lint.Definition{t, u} True{}:
      "a def that returns a type"
    case Lint.Definition{t, u} False{}:
      "a def that does not return a type"
    case Lint.Parameter{b, q} True{}:
      "a parameter that is a type"
    case Lint.Parameter{b, q} False{}:
      "a parameter that is not a type"
    case Lint.Field{b, q} True{}:
      "a field that is a type"
    case Lint.Field{b, q} False{}:
      "a field that is not a type"
    case _ _:
      "a variable"

def what(syntax: Lint.Syntax, want: Case) -> String:
  match want:
    case Pascal{}:
      noun(syntax, True{}) ++ " is PascalCase"
    case Snake{}:
      noun(syntax, False{}) ++ " is snake_case"
    case Either{}:
      "this name is snake_case, or PascalCase if it is a type"

# Whether a name is a binder's: only its own declaration names it, so a rename touches no other file.
def is_local.of(declares: Maybe<&2, Bool>) -> Bool:
  match declares:
    case Some{False{}}:
      True{}
    case _:
      False{}

def is_local(syntax: Lint.Syntax) -> Bool:
  is_local.of(Lint.Syntax.declares(syntax))

# The fix that renames a local name to `to`, if recasing made one that fits.
def renames(ok: Bool, at: Lint.Span, full: String, to: String) -> List<&2, Lint.Fix>:
  match ok:
    case True{}:
      [Lint.Fix{"Rename to " ++ full, [Lint.Rename{at, to}]}]
    case False{}:
      []

# The finding for a name that does not fit: it says the new name when recasing makes one that fits, and, for a local
# name, offers the rename.
def misfit(
  +syntax: Lint.Syntax,
  +want: Case,
  +name: String,
  +span: Lint.Span
) -> List<&2, Lint.Finding>:
  +seg = Strings.after_last(name, '.')
  +to = String.take(name, Nat.sub(String.length(name), String.length(seg))) ++ recased(want, seg)
  +ok = fits(want, recased(want, seg))
  rename = Bool.pick(String, ok, "Rename " ++ name ++ " to " ++ to, "Rename " ++ name)
  [
    Lint.Finding{
      Lint.Warning{},
      span,
      rename ++ ": " ++ what(syntax, want) ++ ".",
      renames(Bool.and(ok, is_local(syntax)), span, to, recased(want, seg))
    }
  ]

def verdict(
  fit: Bool,
  syntax: Lint.Syntax,
  want: Case,
  name: String,
  span: Lint.Span
) -> List<&2, Lint.Finding>:
  match fit:
    case True{}:
      []
    case False{}:
      misfit(syntax, want, name, span)

def judged(
  want: Maybe<&2, Case>,
  syntax: Lint.Syntax,
  +name: String,
  span: Lint.Span
) -> List<&2, Lint.Finding>:
  match want:
    case Some{+w}:
      verdict(fits(w, Strings.after_last(name, '.')), syntax, w, name, span)
    case None{}:
      []

def judge(
  +namespace: String,
  declarations: List<&2, Lint.Declaration>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match declarations:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Declaration{Lint.Node{+syntax, +name, Some{+span}, kids, facts}, uses}, rest}:
      judge(
        namespace,
        rest,
        Lists.onto(
          &2,
          Lint.Finding,
          judged(
            wanted(Lint.Node{syntax, name, Some{span}, kids, facts}, namespace),
            syntax,
            name,
            span
          ),
          out
        )
      )
    case Con{d, rest}:
      judge(namespace, rest, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(judge(Lint.Here.namespace(here), Lint.Here.declarations(here), []))

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{False{}, True{}}, [], Lint.OnFile{run}}
