# language/reused_binder: a binder written without `+` that live code uses twice on one path, so the
# check fails ("consumed more than once").
# Heuristics: it checks only the binders whose quantity the syntax gives for sure: a parameter or a
# let's name written without `+`, which can be used once on each path. It leaves out a pattern's
# field, whose quantity also comes from its scrutinee's type, and a law's bare parameter. Two uses are
# on one path unless they are in different cases of one `match`. Both values of a call count, so
# `Bool.pick(T, c, x, x)` uses x twice. Uses in types, and in an argument for an erased parameter
# (`-P`) of a definition of the check or of Base, are dead and do not count; an erased parameter of
# another function (a lambda, a field) is not seen. A binder that a `match` takes apart is skipped:
# in a case, it stands for the matched constructor. Bend's checker stops at its first error; this
# rule reports every such binder at once.
import Base
import ../../linter/api/impl.bend as LintImpl
import ../../linter/api/spec.bend as Lint
import ../../shared.bend as Shared

# Types
# =====

# A binder that can be used once: its number, its name, and its scope, the node it is declared under, with whether that
# node is live (see `is_live_at`). Its uses are all under its scope, so `scan` reads the scope, not the whole definition.
type Once is Data:
  Once{binder: U32, name: String, scope: Lint.Node, live: Bool}

# The live uses of one binder among some nodes: the first, and the first that an earlier one on its path precedes, if
# any. Two uses are on one path unless a match parts them: its cases, and its scrutinees, are each a path of their own.
type Seen is Data:
  Seen{first: Maybe<&2, Lint.Span>, second: Maybe<&2, Lint.Span>}

# The places, among the nodes of an application, of the arguments for each definition's erased parameters, by the name
# the check gives the definition.
type Erased is Data:
  Erased{places: Map<&2, Maybe<&2, List<&2, U32>>>}

# What a look for binders needs: whether the definition's parameters are a law's (`bare`), and the erased places.
type Looking is Data:
  Looking{bare: Bool, erased: Erased}

# Functions
# =========
def message(+name: String) -> String:
  name
    ++ " is used again here, on the same path as an earlier use, but it is declared without `+`, so it can be used once on each path, and the check fails (\"consumed more than once\"). If its type is Data, write `+"
    ++ name
    ++ "` where it is declared (it then carries a reference count at run time); else use it once: a function, an array or an IO handle can never be copied."

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
# pair type, a type's arguments). An annotation's type, and a rewrite's motive, are not either: see `scan`.
def is_live_inside(+node: Lint.Node, live: Bool) -> Bool:
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
      live && Bool.not(Lint.is_pair(kids))
    case _:
      live

# The places of the erased parameters among a definition's nodes, from `at` (the first argument's), onto `out`.
def Erased.params(nodes: List<&2, Lint.Node>, +at: U32, out: List<&2, U32>) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{Lint.Parameter{b, Lint.Erased{}}, n, s, k, f}, rest}:
      Erased.params(rest, (at + 1: U32), at <> out)
    case Con{Lint.Node{Lint.Parameter{b, q}, n, s, k, f}, rest}:
      Erased.params(rest, (at + 1: U32), out)
    case Con{node, rest}:
      Erased.params(rest, at, out)

def Erased.file(
  nodes: List<&2, Lint.Node>,
  out: Map<&2, Maybe<&2, List<&2, U32>>>
) -> Map<&2, Maybe<&2, List<&2, U32>>>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{Lint.Definition{t, u}, n, s, k, f}, rest}:
      Erased.file(
        rest,
        Map.set(&2, Maybe<&2, List<&2, U32>>, out, t, Some{Erased.params(k, 1, [])})
      )
    case Con{node, rest}:
      Erased.file(rest, out)

def Erased.of(sources: List<&2, Lint.Source>, out: Erased) -> Erased:
  match sources out:
    case Nil{} _:
      out
    case Con{Lint.Source{path, namespace, text, nodes}, rest} Erased{places}:
      Erased.of(rest, Erased{Erased.file(nodes, places)})

# The places of the nodes under a node that are dead: an annotation's type, a rewrite's motive, and the arguments of an
# application for the erased parameters of the definition it calls.
def Erased.dead(+node: Lint.Node, +erased: Erased) -> List<&2, U32>:
  match node erased:
    case Lint.Node{Lint.Annotation{}, n, s, k, f} _:
      [1]
    case Lint.Node{Lint.Rewrite{}, n, s, k, f} _:
      [1]
    case Lint.Node{
      Lint.Application{},
      n,
      s,
      Con{Lint.Node{Lint.Reference{t}, rn, rs, rk, rf}, args},
      f
    } Erased{places}:
      Maybe.default(&2, List<&2, U32>, Shared.Names.find(List<&2, U32>, places, t), [])
    case _ _:
      []

def is_match(syntax: Lint.Syntax) -> Bool:
  match syntax:
    case Lint.Match{}:
      True{}
    case _:
      False{}

# Whether the node that `path` leads to (the nodes above it, innermost first) is live, as `scan` finds it from the
# definition down: the definition is not, and each node under it is as its parent makes it (`is_live_inside`), unless
# it is at one of its parent's dead places (`Erased.dead`).
def is_live_at(path: List<&2, Lint.Above>, +erased: Erased) -> Bool:
  match path:
    case Nil{}:
      False{}
    case Con{Lint.Above{+parent, at}, up}:
      is_live_inside(
        parent,
        is_live_at(up, erased)
      )
        && Bool.not(List.contains(~U32, ~U32.is_eq, Erased.dead(parent, erased), at))

# A parameter that can be used once, of a definition whose parameters are a law's if `bare`: none, as its quantity is
# its law's.
def Once.parameter(
  bare: Bool,
  b: U32,
  name: String,
  scope: Lint.Node,
  up: List<&2, Lint.Above>,
  erased: Erased
) -> List<&2, Once>:
  match bare:
    case True{}:
      []
    case False{}:
      [Once{b, name, scope, is_live_at(up, erased)}]

# The binders a definition declares that can be used once, as their syntax says for sure: a parameter written without
# `+` (unless one is `bare`: its quantity is its law's), whose scope is the definition, and a let's name written without
# `+`, whose scope is its let. A pattern's field is left out: its quantity also comes from its scrutinee's type (a field
# of a `List<&2, A>` is reusable), which the rule cannot see.
def Once.of(+looking: Looking, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Once>:
  match looking path node:
    case Looking{
      bare,
      erased
    } Con{Lint.Above{scope, at}, up} Lint.Node{Lint.Parameter{b, Lint.Once{}}, name, s, k, f}:
      Once.parameter(bare, b, name, scope, up, erased)
    case Looking{
      bare,
      erased
    } Con{
      Lint.Above{Lint.Node{Lint.Destructure{q}, pn, ps, pk, pf}, at},
      up
    } Lint.Node{Lint.PatternVariable{b, Lint.Once{}}, name, s, k, f}:
      [Once{b, name, Lint.Node{Lint.Destructure{q}, pn, ps, pk, pf}, is_live_at(up, erased)}]
    case _ _ _:
      []

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
# whether each is a path of its own (a match's), and `dead` the places of those that are not (see `Erased.dead`);
# `at` counts the nodes.
def scan(
  nodes: List<&2, Lint.Node>,
  +b: U32,
  +erased: Erased,
  +live: Bool,
  +apart: Bool,
  +dead: List<&2, U32>,
  +at: U32,
  seen: Seen
) -> Seen:
  match nodes:
    case Nil{}:
      seen
    case Con{Lint.Node{+syntax, name, span, +kids, facts}, rest}:
      +node = {Lint.Node{syntax, name, span, kids, facts}: Lint.Node}
      +here = live && Bool.not(List.contains(~U32, ~U32.is_eq, dead, at))
      scan(
        rest,
        b,
        erased,
        live,
        apart,
        dead,
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
              erased,
              is_live_inside(node, here),
              is_match(syntax),
              Erased.dead(node, erased),
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

# The finding about a binder used twice on one path in its scope, which is live if `live`, unless a match takes it apart
# (`matched`).
def judged(
  matched: Bool,
  b: U32,
  scope: Lint.Node,
  live: Bool,
  erased: Erased,
  name: String
) -> List<&2, Lint.Finding>:
  match matched:
    case True{}:
      []
    case False{}:
      finding(scan([scope], b, erased, live, False{}, [], 0, Seen{None{}, None{}}), name)

# The finding about each of `onces`, binders of a definition, used twice on one path, onto `out`; a binder a match takes
# apart (`matched`) is skipped.
def judge(
  onces: List<&2, Once>,
  +matched: List<&2, U32>,
  +erased: Erased,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match onces:
    case Nil{}:
      out
    case Con{Once{+b, name, scope, live}, rest}:
      judge(
        rest,
        matched,
        erased,
        Shared.Lists.onto(
          &2,
          Lint.Finding,
          judged(List.contains(~U32, ~U32.is_eq, matched, b), b, scope, live, erased, name),
          out
        )
      )

def defs(
  nodes: List<&2, Lint.Node>,
  +erased: Erased,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{Lint.Definition{t, u}, n, s, +k, f}, rest}:
      +owner = {Lint.Node{Lint.Definition{t, u}, n, s, k, f}: Lint.Node}
      defs(
        rest,
        erased,
        judge(
          Lint.visit(
            ~Looking,
            ~Once,
            ~Once.of,
            Looking{Shared.Lists.any(~Lint.Node, ~Lint.Node.is_bare, k), erased},
            [owner]
          ),
          Lint.visit(~Unit, ~U32, ~scrutinee, Unit{}, [owner]),
          erased,
          out
        )
      )
    case Con{node, rest}:
      defs(rest, erased, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(
    defs(
      Lint.Here.nodes(here),
      Erased.of(
        Lint.Here.sources(here),
        Erased{Erased.file(Lint.Here.base(here), Map.new(&2, Maybe<&2, List<&2, U32>>))}
      ),
      []
    )
  )

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
