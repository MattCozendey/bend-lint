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
import ../../linter/lint.bend as Lint
import ../../shared/lists.bend as Lists

# Types
# =====

# A binder that can be used once: its number, and its name.
type Once is Data:
  Once{binder: U32, name: String}

# The live uses of one binder among some nodes: the first, and the first that an earlier one on its path precedes, if
# any. Two uses are on one path unless a match parts them: its cases, and its scrutinees, are each a path of their own.
type Seen is Data:
  Seen{first: Maybe<&2, Lint.Span>, second: Maybe<&2, Lint.Span>}

# Functions
# =========
def message(+name: String) -> String:
  name
    ++ " is used again here, on the same path as an earlier use, but it is declared without `+`, so it can be used once on each path, and the check fails (\"consumed more than once\"). If its type is Data, write `+"
    ++ name
    ++ "` where it is declared (it then carries a reference count at run time); else use it once: a function, an array or an IO handle can never be copied. This is a false positive if one of the uses is an argument for an erased parameter (`-x`, as a proof's motive often is): that is dead code."

# The binders a definition declares that can be used once, as their syntax says for sure: a parameter written without
# `+` (unless one is `bare`: its quantity is its law's), and a let's name written without `+`. A pattern's field is left
# out: its quantity also comes from its scrutinee's type (a field of a `List<&2, A>` is reusable), which the rule cannot
# see.
def Once.of(+bare: Bool, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Once>:
  match path node:
    case _ Lint.Node{Lint.Parameter{b, Lint.Once{}}, name, s, k, f}:
      Bool.pick(List<&2, Once>, bare, [], [Once{b, name}])
    case Con{
      Lint.Above{Lint.Node{Lint.Destructure{q}, pn, ps, pk, pf}, at},
      up
    } Lint.Node{Lint.PatternVariable{b, Lint.Once{}}, name, s, k, f}:
      [Once{b, name}]
    case _ _:
      []

# The binders a match takes apart: the variables right under it, its scrutinees. In a case, they stand for the matched
# constructor.
def scrutinee(+u: Unit, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, U32>:
  match path node:
    case Con{
      Lint.Above{Lint.Node{Lint.Match{}, mn, ms, mk, mf}, at},
      up
    } Lint.Node{Lint.Variable{b}, n, s, k, f}:
      [b]
    case _ _:
      []

# Whether the nodes under `node`, which is live if `live`, are: a body is; a type is not (an equality, a function or
# pair type, a type's arguments). An annotation's type is not either: see `scan`.
def inner(+node: Lint.Node, live: Bool) -> Bool:
  match node:
    case Lint.Node{Lint.Body{}, n, s, k, f}:
      True{}
    case Lint.Node{Lint.Equality{}, n, s, k, f}:
      False{}
    case Lint.Node{Lint.Forall{b, q}, n, s, k, f}:
      False{}
    case Lint.Node{Lint.TypeApplication{t}, n, s, k, f}:
      False{}
    case Lint.Node{Lint.Application{}, n, s, kids, f}:
      live && Bool.not(Lint.pair(kids))
    case _:
      live

def is_match(syntax: Lint.Syntax) -> Bool:
  match syntax:
    case Lint.Match{}:
      True{}
    case _:
      False{}

def is_annotation(syntax: Lint.Syntax) -> Bool:
  match syntax:
    case Lint.Annotation{}:
      True{}
    case _:
      False{}

# What a node's uses of `b` are: its own, if it is a live use, else `under`'s, those under it.
def Seen.of(+node: Lint.Node, b: U32, live: Bool, under: Seen) -> Seen:
  match node live:
    case Lint.Node{Lint.Variable{v}, n, Some{span}, k, f} True{}:
      Bool.pick(Seen, U32.is_eq(v, b), Seen{Some{span}, None{}}, under)
    case _ _:
      under

# The uses of `seen`, then those of `next`, the nodes after them: on one path, or, if `apart`, on paths of their own.
def Seen.then(apart: Bool, seen: Seen, next: Seen) -> Seen:
  match apart seen next:
    case True{} Seen{f, s} Seen{g, t}:
      Seen{Maybe.or(&2, Lint.Span, f, g), Maybe.or(&2, Lint.Span, s, t)}
    case False{} Seen{Some{f}, s} Seen{g, t}:
      Seen{Some{f}, Maybe.or(&2, Lint.Span, s, g)}
    case False{} Seen{None{}, s} Seen{g, t}:
      Seen{g, Maybe.or(&2, Lint.Span, s, t)}

# The live uses of `b` among `nodes`, the nodes under one, after `seen`: `live` says whether they are live, `apart`
# whether each is a path of its own (a match's), and `typed` whether only the first is live (an annotation's: the
# second is a type); `at` counts the nodes.
def scan(
  nodes: List<&2, Lint.Node>,
  +b: U32,
  +live: Bool,
  +apart: Bool,
  +typed: Bool,
  +at: U32,
  seen: Seen
) -> Seen:
  match nodes:
    case Nil{}:
      seen
    case Con{Lint.Node{+syntax, name, span, +kids, facts}, rest}:
      +node = {Lint.Node{syntax, name, span, kids, facts}: Lint.Node}
      +here = live && Bool.not(typed && U32.is_gt(at, 0))
      scan(
        rest,
        b,
        live,
        apart,
        typed,
        (at + 1: U32),
        Seen.then(
          apart,
          seen,
          Seen.of(
            node,
            b,
            here,
            scan(
              kids,
              b,
              inner(node, here),
              is_match(syntax),
              is_annotation(syntax),
              0,
              Seen{None{}, None{}}
            )
          )
        )
      )

def finding(second: Seen, name: String) -> List<&2, Lint.Finding>:
  match second:
    case Seen{f, s}:
      Lint.finding(Lint.Warning{}, True{}, s, message(name))

# The finding about a binder of `owner` used twice on one path, unless a match takes it apart (`matched`).
def judged(matched: Bool, owner: Lint.Node, b: U32, name: String) -> List<&2, Lint.Finding>:
  match matched:
    case True{}:
      []
    case False{}:
      finding(scan([owner], b, False{}, False{}, False{}, 0, Seen{None{}, None{}}), name)

# The finding about each of `onces`, binders of `owner`, used twice on one path, onto `out`; a binder a match takes
# apart (`matched`) is skipped.
def judge(
  +owner: Lint.Node,
  onces: List<&2, Once>,
  +matched: List<&2, U32>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match onces:
    case Nil{}:
      out
    case Con{Once{+b, name}, rest}:
      judge(
        owner,
        rest,
        matched,
        Lists.onto(
          &2,
          Lint.Finding,
          judged(List.contains(~U32, ~U32.is_eq, matched, b), owner, b, name),
          out
        )
      )

def defs(nodes: List<&2, Lint.Node>, out: List<&2, Lint.Finding>) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{Lint.Definition{t, u}, n, s, +k, f}, rest}:
      +owner = {Lint.Node{Lint.Definition{t, u}, n, s, k, f}: Lint.Node}
      defs(
        rest,
        judge(
          owner,
          Lint.visit(~Bool, ~Once, ~Once.of, Lists.any(~Lint.Node, ~Lint.Node.bare, k), [owner]),
          Lint.visit(~Unit, ~U32, ~scrutinee, Unit{}, [owner]),
          out
        )
      )
    case Con{node, rest}:
      defs(rest, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(defs(Lint.Here.nodes(here), []))

def rule() -> Lint.Rule:
  Lint.Rule{"language/reused-binder", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
