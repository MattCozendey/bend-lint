# layout/case: a name's case follows the kind of what it names.
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
# A sort is `Type`, `Data` or `Kind(..)`; a type ends in one when it is one, or a function type whose result does. A
# binder written bare (`<a>`, `(x)`) is a quantity, so snake_case. PascalCase is a capital, then letters and digits:
# `IO`, `OP` and `U32` pass. snake_case has no capital. A dotted name is checked by its last segment; the segments
# before it name its parent, checked where the parent is declared. `import Base`, and a def that fills a law of another
# file, are skipped: their names are not this file's to choose.
import Base
import ../../lint.bend as Lint
import ../../shared.bend as Shared

# Types
# =====

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

# The last segment of a dotted name. `seg` is the segment so far, last character first.
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

# Written types
# =============

# Whether the type a node writes ends in a sort, from whether its last child's does.
def ends(syntax: Lint.Syntax, last: Maybe<&2, Bool>) -> Bool:
  match syntax:
    case Lint.Sort{}:
      True{}
    case Lint.Forall{}:
      Maybe.default(&2, Bool, last, False{})
    case _:
      False{}

def Sorts.at(sorts: Map<&2, Maybe<&2, Bool>>, key: String) -> Maybe<&2, Bool>:
  Pair.snd(Map<&2, Maybe<&2, Bool>>, Maybe<&2, Bool>, Map.get(Maybe<&2, Bool>, None{}, sorts, key))

# Where a def's return type is kept: under its id, after "r".
def Sorts.returns_of(def_id: String) -> String:
  "r" ++ def_id

def Sorts.first(sorts: Map<&2, Maybe<&2, Bool>>, key: String, x: Bool, got: Maybe<&2, Bool>) ->
  Map<&2, Maybe<&2, Bool>>:
  match got:
    case None{}:
      Map.set(&2, Maybe<&2, Bool>, sorts, key, Some{x})
    case Some{y}:
      sorts

def Sorts.returns(syntax: Lint.Syntax, sorts: Map<&2, Maybe<&2, Bool>>, parent: String, last: Maybe<&2, Bool>) ->
  Map<&2, Maybe<&2, Bool>>:
  match syntax:
    case Lint.Returns{}:
      Map.set(&2, Maybe<&2, Bool>, sorts, Sorts.returns_of(parent), last)
    case _:
      sorts

# One node, children before parents: the first child seen of a parent is its last.
def Sorts.step(+sorts: Map<&2, Maybe<&2, Bool>>, node: Lint.Node) -> Map<&2, Maybe<&2, Bool>>:
  match node:
    case Lint.Node{id, parent, owner, +syntax, name, binder, quantity, span, target}:
      +last = Sorts.at(sorts, U32.show(id))
      +key = U32.show(parent)
      +more = Sorts.returns(syntax, sorts, key, last)
      Sorts.first(more, key, ends(syntax, last), Sorts.at(more, key))

# For each node, whether its last child's written type ends in a sort: for a parameter or field, its own type. `nodes`
# go children first.
def Sorts.of(nodes: List<&2, Lint.Node>, sorts: Map<&2, Maybe<&2, Bool>>) -> Map<&2, Maybe<&2, Bool>>:
  match nodes:
    case Nil{}:
      sorts
    case Con{n, rest}:
      Sorts.of(rest, Sorts.step(sorts, n))

# Rule
# ====

def typed(sorted: Maybe<&2, Bool>) -> Case:
  match sorted:
    case Some{True{}}:
      Pascal{}
    case Some{False{}}:
      Snake{}
    case None{}:
      Either{}

# The case a declaration's name takes, if the file chooses it.
def wanted(
  syntax: Lint.Syntax,
  +sorts: Map<&2, Maybe<&2, Bool>>,
  +id: U32,
  namespace: String,
  target: String,
  name: String
) -> Maybe<&2, Case>:
  match syntax:
    case Lint.Import{}:
      Shared.when(Case, Bool.not(String.eq(name, "Base")), Pascal{})
    case Lint.Datatype{}:
      Some{Pascal{}}
    case Lint.Constructor{}:
      Some{Pascal{}}
    case Lint.Law{}:
      Some{Snake{}}
    case Lint.Definition{}:
      Bool.pick(
        Maybe<&2, Case>,
        String.eq(Lint.Name.namespace(target), namespace),
        Some{typed(Sorts.at(sorts, Sorts.returns_of(U32.show(id))))},
        None{}
      )
    case Lint.Parameter{}:
      Some{typed(Sorts.at(sorts, U32.show(id)))}
    case Lint.Field{}:
      Some{typed(Sorts.at(sorts, U32.show(id)))}
    case _:
      Some{Either{}}

# A name of `syntax`, in a message. `sort`: whether it is a type.
def noun(syntax: Lint.Syntax, sort: Bool) -> String:
  match syntax sort:
    case Lint.Import{} _:
      "an import alias"
    case Lint.Datatype{} _:
      "a type"
    case Lint.Constructor{} _:
      "a constructor"
    case Lint.Law{} _:
      "a law"
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
def local(syntax: Lint.Syntax) -> Bool:
  match syntax:
    case Lint.Parameter{}:
      True{}
    case Lint.PatternVariable{}:
      True{}
    case Lint.Lambda{}:
      True{}
    case Lint.Binding{}:
      True{}
    case Lint.Forall{}:
      True{}
    case _:
      False{}

# The fix that renames a local name to `to`, if recasing made one that fits.
def renames(ok: Bool, +id: U32, +full: String, +to: String) -> List<&2, Lint.Fix>:
  match ok:
    case True{}:
      [Lint.Fix{"Rename to " ++ full, [Lint.Rename{id, to}]}]
    case False{}:
      []

# The finding for a name that does not fit: it says the new name when recasing makes one that fits, and, for a local
# name, offers the rename.
def misfit(+syntax: Lint.Syntax, +want: Case, +name: String, span: Lint.Span, +id: U32) -> List<&2, Lint.Finding>:
  +seg = segment(name, "")
  +to = String.take(name, Nat.sub(String.length(name), String.length(seg))) ++ recased(want, seg)
  +ok = fits(want, recased(want, seg))
  +rename = Bool.pick(String, ok, "Rename " ++ name ++ " to " ++ to, "Rename " ++ name)
  [
    Lint.Finding{
      Lint.Warning{},
      span,
      rename ++ ": " ++ what(syntax, want) ++ ".",
      renames(Bool.and(ok, local(syntax)), id, to, recased(want, seg))
    }
  ]

def verdict(fit: Bool, syntax: Lint.Syntax, want: Case, name: String, span: Lint.Span, id: U32) -> List<&2, Lint.Finding>:
  match fit:
    case True{}:
      []
    case False{}:
      misfit(syntax, want, name, span, id)

def judged(want: Maybe<&2, Case>, syntax: Lint.Syntax, +name: String, span: Lint.Span, id: U32) -> List<&2, Lint.Finding>:
  match want:
    case Some{+w}:
      verdict(fits(w, segment(name, "")), syntax, w, name, span, id)
    case None{}:
      []

# The findings on `declarations`, onto `out`, last first.
def judge(
  +sorts: Map<&2, Maybe<&2, Bool>>,
  +namespace: String,
  declarations: List<&2, Lint.Declaration>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match declarations:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Declaration{Lint.Node{+id, parent, owner, +syntax, +name, binder, quantity, Some{span}, target}, uses}, rest}:
      judge(
        sorts,
        namespace,
        rest,
        Shared.onto(&2, Lint.Finding, judged(wanted(syntax, sorts, id, namespace, target, name), syntax, name, span, id), out)
      )
    case Con{d, rest}:
      judge(sorts, namespace, rest, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(
    judge(
      Sorts.of(List.reverse(&2, Lint.Node, Lint.Here.nodes(here)), Map.new(&2, Maybe<&2, Bool>)),
      Lint.Here.namespace(here),
      Lint.Here.declarations(here),
      []
    )
  )

def rule() -> Lint.Rule:
  Lint.Rule{"layout/case", Lint.Needs{False{}, True{}}, [], Lint.OnFile{run}}
