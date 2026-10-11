# language/reused-binder: a binder written without `+` that live code uses twice on one path, so the
# check fails ("consumed more than once").
# Heuristics: it checks only the binders whose quantity the syntax gives for sure: a parameter or a
# let's name written without `+`, which can be used once on each path. It leaves out a pattern's
# field, whose quantity also comes from its scrutinee's type, and a law's bare parameter. Two uses are
# on one path unless they are in different cases of one `match`. Both values of a call count, so
# `Bool.pick(T, c, x, x)` uses x twice. Uses in types are dead and do not count. A binder that a
# `match` takes apart is skipped: in a case, it stands for the matched constructor. Bend's checker
# stops at its first error; this rule reports every such binder at once.
import Base
import ../../lint.bend as Lint
import ../../shared.bend as Shared

# Types
# =====

# A binder that can be used once: its number, its definition's id, and its name.
type Once is Data:
  Once{binder: U32, owner: U32, name: String}

# A live use of a binder: the binder, its definition's id, and the use's id.
type Use is Data:
  Use{binder: U32, owner: U32, id: U32}

# Functions
# =========

# The definitions with a bare parameter (`def f(x)`, filling a law): their quantities are the law's.
def parent_is_let(node: Maybe<&2, Lint.Node>) -> Bool:
  match node:
    case Some{Lint.Node{i, p, o, Lint.Destructure{}, n, b, q, s, t}}:
      True{}
    case _:
      False{}

# The binders that can be used once, as their syntax says for sure: a parameter written without `+`
# (not bare), and a let's name written without `+`. A pattern's field is left out: its quantity also
# comes from its scrutinee's type (a field of a `List<&2, A>` is reusable), which the rule cannot see.
def Once.all(
  nodes: List<&2, Lint.Node>,
  +bare: List<&2, U32>,
  +here: Lint.Here,
  out: List<&2, Once>
) -> List<&2, Once>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Once, out)
    case Con{Lint.Node{i, p, +o, Lint.Parameter{}, n, Some{b}, Some{Lint.Once{}}, s, t}, rest}:
      Once.all(
        rest,
        bare,
        here,
        Shared.push(
          Once,
          Shared.when(Once, Bool.not(List.contains(~U32, ~U32.is_eq, bare, o)), Once{b, o, n}),
          out
        )
      )
    case Con{
      Lint.Node{i, +p, o, Lint.PatternVariable{}, n, Some{b}, Some{Lint.Once{}}, s, t},
      rest
    }:
      Once.all(
        rest,
        bare,
        here,
        Shared.push(
          Once,
          Shared.when(Once, parent_is_let(Lint.Here.node(here, p)), Once{b, o, n}),
          out
        )
      )
    case Con{node, rest}:
      Once.all(rest, bare, here, out)

def bare(nodes: List<&2, Lint.Node>, +children: Lint.Children, out: List<&2, U32>) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{+i, p, +o, Lint.Parameter{}, n, b, q, s, t}, rest}:
      bare(
        rest,
        children,
        Shared.push(U32, Shared.when(U32, Lint.Children.bare(children, i), o), out)
      )
    case Con{node, rest}:
      bare(rest, children, out)

# Whether the node numbered `parent` is a match: then a variable under it, and not under a case, is a
# scrutinee.
def is_match(node: Maybe<&2, Lint.Node>) -> Bool:
  match node:
    case Some{Lint.Node{i, p, o, Lint.Match{}, n, b, q, s, t}}:
      True{}
    case _:
      False{}

# The live uses of binders in the file, and the binders a match takes apart (scrutinees, as
# `binder` and `owner`).
def Use.all(
  nodes: List<&2, Lint.Node>,
  +here: Lint.Here,
  uses: List<&2, Use>,
  matched: List<&2, Use>
) -> List<&2, Use>
  & List<&2, Use>:
  match nodes:
    case Nil{}:
      (List.reverse(&2, Use, uses), matched)
    case Con{Lint.Node{+i, +p, +o, Lint.Variable{}, n, Some{+b}, q, s, t}, rest}:
      +scrutinee = is_match(Lint.Here.node(here, p))
      Use.all(
        rest,
        here,
        Shared.push(
          Use,
          Shared.when(Use, Bool.not(scrutinee) && Lint.Here.live(here, i), Use{b, o, i}),
          uses
        ),
        Shared.push(Use, Shared.when(Use, scrutinee, Use{b, o, i}), matched)
      )
    case Con{node, rest}:
      Use.all(rest, here, uses, matched)

def Use.of(uses: List<&2, Use>, +binder: U32, +owner: U32, out: List<&2, U32>) -> List<&2, U32>:
  match uses:
    case Nil{}:
      List.reverse(&2, U32, out)
    case Con{Use{b, o, +i}, rest}:
      Use.of(
        rest,
        binder,
        owner,
        Shared.push(U32, Shared.when(U32, U32.is_eq(b, binder) && U32.is_eq(o, owner), i), out)
      )

def ids(nodes: List<&2, Lint.Node>, out: List<&2, U32>) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{i, p, o, s, n, b, q, sp, t}, rest}:
      ids(rest, i <> out)

# The first node of `chain` (innermost first) whose id is in `others`: the two uses' nearest common
# ancestor.
def common(
  chain: List<&2, Lint.Node>,
  found: Maybe<&2, Lint.Node>,
  +others: List<&2, U32>
) -> Maybe<&2, Lint.Node>:
  match chain found:
    case _ Some{node}:
      Some{node}
    case Nil{} None{}:
      None{}
    case Con{Lint.Node{+i, p, o, s, n, b, q, sp, t}, rest} None{}:
      common(
        rest,
        Shared.when(
          Lint.Node,
          List.contains(~U32, ~U32.is_eq, others, i),
          Lint.Node{i, p, o, s, n, b, q, sp, t}
        ),
        others
      )

# Whether two uses are on one path: their nearest common ancestor is not a match, whose cases part
# them.
def one_path(node: Maybe<&2, Lint.Node>) -> Bool:
  match node:
    case Some{Lint.Node{i, p, o, Lint.Match{}, n, b, q, s, t}}:
      False{}
    case _:
      True{}

def twice.with(
  uses: List<&2, U32>,
  found: Maybe<&2, U32>,
  +first: U32,
  +here: Lint.Here
) -> Maybe<&2, U32>:
  match uses found:
    case _ Some{u}:
      Some{u}
    case Nil{} None{}:
      None{}
    case Con{+u, rest} None{}:
      twice.with(
        rest,
        Shared.when(
          U32,
          one_path(
            common(Lint.Here.ancestors(here, first), None{}, ids(Lint.Here.ancestors(here, u), []))
          ),
          u
        ),
        first,
        here
      )

# The second of the first two uses of `uses` (in order) on one path, if there are two.
def twice(uses: List<&2, U32>, found: Maybe<&2, U32>, +here: Lint.Here) -> Maybe<&2, U32>:
  match uses found:
    case _ Some{u}:
      Some{u}
    case Nil{} None{}:
      None{}
    case Con{+u, +rest} None{}:
      twice(rest, twice.with(rest, None{}, u, here), here)

def message(+name: String) -> String:
  name
    ++ " is used again here, on the same path as an earlier use, but it is declared without `+`, so it can be used once on each path, and the check fails (\"consumed more than once\"). If its type is Data, write `+"
    ++ name
    ++ "` where it is declared (it then carries a reference count at run time); else use it once: a function, an array or an IO handle can never be copied. This is a false positive if one of the uses is an argument for an erased parameter (`-x`, as a proof's motive often is): that is dead code."

def finding.at(span: Maybe<&2, Lint.Span>, +name: String) -> List<&2, Lint.Finding>:
  match span:
    case Some{s}:
      [Lint.Finding{Lint.Warning{}, s, message(name), []}]
    case None{}:
      []

def finding(second: Maybe<&2, U32>, +name: String, +here: Lint.Here) -> List<&2, Lint.Finding>:
  match second:
    case Some{+u}:
      finding.at(Lint.Node.span(Lint.Here.node(here, u)), name)
    case None{}:
      []

# The finding about the binder `b` of `o`, unless a match takes it apart.
def unmatched(
  matched: Bool,
  +b: U32,
  +o: U32,
  +n: String,
  +uses: List<&2, Use>,
  +here: Lint.Here
) -> List<&2, Lint.Finding>:
  match matched:
    case True{}:
      []
    case False{}:
      finding(twice(Use.of(uses, b, o, []), None{}, here), n, here)

def judge(
  onces: List<&2, Once>,
  +uses: List<&2, Use>,
  +matched: List<&2, Use>,
  +here: Lint.Here,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match onces:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Once{+b, +o, +n}, rest}:
      judge(
        rest,
        uses,
        matched,
        here,
        Shared.onto(
          &2,
          Lint.Finding,
          unmatched(
            Maybe.is_some(&2, U32, List.head(&2, U32, Use.of(matched, b, o, []))),
            b,
            o,
            n,
            uses,
            here
          ),
          out
        )
      )

def judged(
  found: List<&2, Use> & List<&2, Use>,
  onces: List<&2, Once>,
  +here: Lint.Here
) -> List<&2, Lint.Finding>:
  match found:
    case Tuple{+uses, +matched}:
      judge(onces, uses, matched, here, [])

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +nodes = Lint.Here.nodes(here)
  +children = Lint.Children.of(nodes)
  Lint.done(
    judged(Use.all(nodes, here, [], []), Once.all(nodes, bare(nodes, children, []), here, []), here)
  )

def rule() -> Lint.Rule:
  Lint.Rule{"language/reused-binder", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
