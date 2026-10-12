# language/decreasing-call: a call of a definition to itself that Bend cannot prove smaller, so the check
# fails ("a decreasing self-call").
# Heuristics: as Bend's checker does, it reads the arguments left to right against the parameters:
# each must be passed unchanged until one is smaller, a field that a `match` on that parameter took
# apart (`p` of `case 1n+p:`). Erased parameters do not count. An argument that is a call, or another
# variable, is not smaller. One that is a literal or a constructor is left to the checker: the rule
# does not report it. Bend's checker stops at its first error; this rule reports every such call at
# once. An @unsafe definition (`def f?`) may call itself freely, and a call in a type (a pair type
# `A & B`, a type's arguments, an equality) is not checked.
import Base
import ../../linter/lint.bend as Lint
import ../../shared/lists.bend as Lists

# Types
# =====

# A parameter: its binder, whether it is erased (it does not count), and its name.
type Param is Data:
  Param{binder: U32, erased: Bool, name: String}

# A binder known smaller than the parameter or field `root`: a field a match took apart from it.
type Smaller is Data:
  Smaller{root: U32, field: U32}

# What the arguments of a call say: it decreases; it does not, at the argument numbered `at` (from 0)
# for the parameter `param`, or with every argument unchanged; or the rule cannot tell.
type Verdict is Data:
  Decreases{}
  Fails{at: Nat, param: String}
  Unchanged{}
  Unknown{}

# Functions
# =========
def Param.erased(bare: Bool, quantity: Maybe<&2, Lint.Quantity>) -> Bool:
  match bare quantity:
    case False{} Some{Lint.Erased{}}:
      True{}
    case _ _:
      False{}

def Param.all(
  nodes: List<&2, Lint.Node>,
  +children: Lint.Children,
  out: List<&2, Param>
) -> List<&2, Param>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Param, out)
    case Con{Lint.Node{i, p, o, Lint.Parameter{}, n, Some{b}, q, s, t}, rest}:
      Param.all(
        rest,
        children,
        Param{b, Param.erased(Lint.Children.bare(children, i), q), n} <> out
      )
    case Con{node, rest}:
      Param.all(rest, children, out)

# The roots that `binder` is smaller than, with `binder` itself.
def roots(smaller: List<&2, Smaller>, +binder: U32, out: List<&2, U32>) -> List<&2, U32>:
  match smaller:
    case Nil{}:
      binder <> out
    case Con{Smaller{r, f}, rest}:
      roots(rest, binder, Lists.push(U32, Lists.when(U32, U32.is_eq(f, binder), r), out))

def pairs.of(+r: U32, fs: List<&2, U32>, out: List<&2, Smaller>) -> List<&2, Smaller>:
  match fs:
    case Nil{}:
      out
    case Con{f, rest}:
      pairs.of(r, rest, Smaller{r, f} <> out)

def pairs(rs: List<&2, U32>, +fs: List<&2, U32>, out: List<&2, Smaller>) -> List<&2, Smaller>:
  match rs:
    case Nil{}:
      out
    case Con{r, rest}:
      pairs(rest, fs, pairs.of(r, fs, out))

# What a case's patterns take apart: each pattern, a constructor, makes its variables smaller than its
# scrutinee, and than all that scrutinee is smaller than.
def taken(
  scrutinees: List<&2, Lint.Node>,
  patterns: List<&2, Lint.Node>,
  +children: Lint.Children,
  +fuel: Nat,
  +smaller: List<&2, Smaller>
) -> List<&2, Smaller>:
  match scrutinees patterns:
    case Con{
      Lint.Node{i, p, o, Lint.Variable{}, n, Some{s}, q, sp, t},
      more
    } Con{Lint.Node{j, pp, po, Lint.PatternConstructor{}, pn, pb, pq, ps, pt}, rest}:
      taken(
        more,
        rest,
        children,
        fuel,
        Lists.onto(
          &2,
          Smaller,
          pairs(
            roots(smaller, s, []),
            Lint.Children.bound(fuel, Lint.Children.get(children, j), children, []),
            []
          ),
          smaller
        )
      )
    case Con{x, more} Con{y, rest}:
      taken(more, rest, children, fuel, smaller)
    case _ _:
      smaller

# What the cases above a call (`chain`, outermost first) take apart.
def known(
  chain: List<&2, Lint.Node>,
  +children: Lint.Children,
  +fuel: Nat,
  smaller: List<&2, Smaller>
) -> List<&2, Smaller>:
  match chain:
    case Nil{}:
      smaller
    case Con{Lint.Node{i, p, o, Lint.Case{}, n, b, q, s, t}, rest}:
      known(
        rest,
        children,
        fuel,
        taken(
          Lint.Children.scrutinees(children, p),
          Lint.Children.get(children, i),
          children,
          fuel,
          smaller
        )
      )
    case Con{node, rest}:
      known(rest, children, fuel, smaller)

def is_smaller(smaller: List<&2, Smaller>, hit: Bool, +root: U32, +field: U32) -> Bool:
  match smaller hit:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{Smaller{r, f}, rest} False{}:
      is_smaller(rest, U32.is_eq(r, root) && U32.is_eq(f, field), root, field)

# What one argument, a variable, says: none to read on (it is the parameter, unchanged), else the
# verdict: it decreases (a field a match took apart), the rule cannot tell (a let's name), or it fails.
def step(same: Bool, smaller: Bool, local: Bool, at: Nat, param: String) -> Maybe<&2, Verdict>:
  match same smaller local:
    case True{} _ _:
      None{}
    case False{} True{} _:
      Some{Decreases{}}
    case False{} False{} True{}:
      Some{Unknown{}}
    case False{} False{} False{}:
      Some{Fails{at, param}}

# The verdict on a call's arguments against the parameters, from the one numbered `at`.
def verdict(
  params: List<&2, Param>,
  args: List<&2, Lint.Node>,
  told: Maybe<&2, Verdict>,
  +smaller: List<&2, Smaller>,
  +lets: List<&2, U32>,
  +at: Nat
) -> Verdict:
  match params args told:
    case _ _ Some{v}:
      v
    case Con{Param{b, True{}, n}, ps} Con{arg, rest} None{}:
      verdict(ps, rest, None{}, smaller, lets, 1n+at)
    case Con{
      Param{+b, False{}, +n},
      ps
    } Con{Lint.Node{i, p, o, Lint.Variable{}, x, Some{+a}, q, s, t}, rest} None{}:
      verdict(
        ps,
        rest,
        step(
          U32.is_eq(a, b),
          is_smaller(smaller, False{}, b, a),
          List.contains(~U32, ~U32.is_eq, lets, a),
          at,
          n
        ),
        smaller,
        lets,
        1n+at
      )
    case Con{
      Param{b, False{}, n},
      ps
    } Con{Lint.Node{i, p, o, Lint.Application{}, x, y, q, s, t}, rest} None{}:
      Fails{at, n}
    case Nil{} Nil{} None{}:
      Unchanged{}
    case _ _ None{}:
      Unknown{}

def ordinal(n: Nat) -> String:
  U32.show(U32.from_nat(1n+n))

def message(verdict: Verdict, loop: String, source: String, args: List<&2, Lint.Node>) -> String:
  match verdict:
    case Fails{+at, param}:
      loop
        ++ " calls itself here, but argument "
        ++ ordinal(at)
        ++ " (`"
        ++ Lint.Span.text(source, Lint.Node.span(List.get(&2, Lint.Node, args, at)))
        ++ "`) is neither the parameter "
        ++ param
        ++ " unchanged nor a part of it that a match took apart, and the arguments before it are unchanged. Bend reads the arguments left to right, so it cannot prove the loop ends, and the check fails (\"a decreasing self-call\"). Put the parameter that shrinks first, pass the ones before it unchanged, and pass a part of it that a match took apart (`p` of `case 1n+p:`)."
    case _:
      loop
        ++ " calls itself here with every argument unchanged, so the loop would never end, and the check fails (\"a decreasing self-call\"). Pass a part of the parameter that shrinks, one that a match took apart (`p` of `case 1n+p:`)."

def finding(
  verdict: Verdict,
  span: Maybe<&2, Lint.Span>,
  loop: String,
  source: String,
  args: List<&2, Lint.Node>
) -> List<&2, Lint.Finding>:
  match verdict span:
    case Fails{at, param} Some{s}:
      [Lint.Finding{Lint.Warning{}, s, message(Fails{at, param}, loop, source, args), []}]
    case Unchanged{} Some{s}:
      [Lint.Finding{Lint.Warning{}, s, message(Unchanged{}, loop, source, args), []}]
    case _ _:
      []

def call(
  nodes: List<&2, Lint.Node>,
  lets: List<&2, U32>,
  owner: U32,
  id: U32,
  span: Maybe<&2, Lint.Span>,
  +here: Lint.Here,
  +children: Lint.Children,
  fuel: Nat
) -> List<&2, Lint.Finding>:
  match nodes:
    case Con{Lint.Node{i, p, o, s, loop, b, q, sp, t}, +args}:
      finding(
        verdict(
          Param.all(Lint.Children.get(children, owner), children, []),
          args,
          None{},
          known(List.reverse(&2, Lint.Node, Lint.Here.ancestors(here, id)), children, fuel, []),
          lets,
          0n
        ),
        span,
        loop,
        Lint.Here.text(here),
        args
      )
    case Nil{}:
      []

# The findings about a call of the definition to itself, if `checks`: the definition is not @unsafe, and
# the call is live.
def checked(
  checks: Bool,
  nodes: List<&2, Lint.Node>,
  lets: List<&2, U32>,
  owner: U32,
  id: U32,
  span: Maybe<&2, Lint.Span>,
  here: Lint.Here,
  children: Lint.Children,
  fuel: Nat
) -> List<&2, Lint.Finding>:
  match checks:
    case True{}:
      call(nodes, lets, owner, id, span, here, children, fuel)
    case False{}:
      []

def visit(
  recursive: Bool,
  node: Lint.Node,
  lets: List<&2, U32>,
  unsafes: List<&2, U32>,
  +here: Lint.Here,
  +children: Lint.Children,
  fuel: Nat
) -> List<&2, Lint.Finding>:
  match recursive node:
    case True{} Lint.Node{+id, p, +owner, s, n, b, q, span, t}:
      checked(
        Bool.not(List.contains(~U32, ~U32.is_eq, unsafes, owner)) && Lint.Here.live(here, id),
        Lint.Children.get(children, id),
        lets,
        owner,
        id,
        span,
        here,
        children,
        fuel
      )
    case _ _:
      []

def scan(
  nodes: List<&2, Lint.Node>,
  +lets: List<&2, U32>,
  +unsafes: List<&2, U32>,
  +here: Lint.Here,
  +children: Lint.Children,
  +fuel: Nat,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{+node, rest}:
      scan(
        rest,
        lets,
        unsafes,
        here,
        children,
        fuel,
        Lists.onto(
          &2,
          Lint.Finding,
          visit(
            Lint.Here.recursive(here, children, node),
            node,
            lets,
            unsafes,
            here,
            children,
            fuel
          ),
          out
        )
      )

def lets.bound(nodes: List<&2, Lint.Node>, out: List<&2, U32>) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{i, p, o, Lint.PatternVariable{}, n, Some{b}, q, s, t}, rest}:
      lets.bound(rest, b <> out)
    case Con{node, rest}:
      lets.bound(rest, out)

# The binders the lets of the file bind: an argument that is one stands for its value, which the rule
# does not follow.
def lets(nodes: List<&2, Lint.Node>, +children: Lint.Children, out: List<&2, U32>) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{i, p, o, Lint.Destructure{}, n, b, q, s, t}, rest}:
      lets(rest, children, lets.bound(Lint.Children.get(children, i), out))
    case Con{node, rest}:
      lets(rest, children, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +nodes = Lint.Here.nodes(here)
  +children = Lint.Children.of(nodes)
  Lint.done(
    scan(
      nodes,
      lets(nodes, children, []),
      Lint.Here.unsafes(here),
      here,
      children,
      Lists.length(&2, Lint.Node, nodes),
      []
    )
  )

def rule() -> Lint.Rule:
  Lint.Rule{"language/decreasing-call", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
