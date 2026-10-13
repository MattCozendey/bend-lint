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

# What judging a definition's calls of itself reads: its parameters, the binders its lets bind (an argument that is one
# stands for its value, which the rule does not follow), and the file's text.
type Loop is Data:
  Loop{params: List<&2, Param>, lets: List<&2, U32>, text: String}

# Functions
# =========
def Param.erased(bare: Bool, quantity: Lint.Quantity) -> Bool:
  match bare quantity:
    case False{} Lint.Erased{}:
      True{}
    case _ _:
      False{}

def Param.all(nodes: List<&2, Lint.Node>, out: List<&2, Param>) -> List<&2, Param>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Param, out)
    case Con{Lint.Node{Lint.Parameter{+b, +q}, +n, +s, +k, +f}, rest}:
      Param.all(rest, Param{b, Param.erased(Lint.Node.bare(Lint.Node{Lint.Parameter{b, q}, n, s, k, f}), q), n} <> out)
    case Con{node, rest}:
      Param.all(rest, out)

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
  +smaller: List<&2, Smaller>
) -> List<&2, Smaller>:
  match scrutinees patterns:
    case Con{
      Lint.Node{Lint.Variable{s}, n, sp, k, f},
      more
    } Con{Lint.Node{Lint.PatternConstructor{t}, pn, ps, kids, pf}, rest}:
      taken(
        more,
        rest,
        Lists.onto(&2, Smaller, pairs(roots(smaller, s, []), Lint.Node.bound(kids, []), []), smaller)
      )
    case Con{x, more} Con{y, rest}:
      taken(more, rest, smaller)
    case _ _:
      smaller

# What a case below `parent` takes apart, if `node` is one and `parent` its match.
def known.at(parent: Maybe<&2, Lint.Node>, node: Lint.Node, smaller: List<&2, Smaller>) -> List<&2, Smaller>:
  match parent node:
    case Some{Lint.Node{Lint.Match{}, mn, ms, +scrutinees, mf}} Lint.Node{Lint.Case{}, n, s, patterns, f}:
      taken(Lint.Node.scrutinees(Lint.Node{Lint.Match{}, mn, ms, scrutinees, mf}), patterns, smaller)
    case _ _:
      smaller

# What the cases above a call (`chain`, outermost first; `parent` is the node above the first) take apart.
def known(chain: List<&2, Lint.Above>, parent: Maybe<&2, Lint.Node>, smaller: List<&2, Smaller>) -> List<&2, Smaller>:
  match chain:
    case Nil{}:
      smaller
    case Con{Lint.Above{+node, at}, rest}:
      known(rest, Some{node}, known.at(parent, node, smaller))

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
    case Con{Param{+b, False{}, +n}, ps} Con{Lint.Node{Lint.Variable{+a}, x, s, k, f}, rest} None{}:
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
    case Con{Param{b, False{}, n}, ps} Con{Lint.Node{Lint.Application{}, x, s, k, f}, rest} None{}:
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

# The findings about a call of its definition to itself, below `path`.
def call(+loop: Loop, +path: List<&2, Lint.Above>, node: Lint.Node) -> List<&2, Lint.Finding>:
  match loop node:
    case Loop{params, lets, text} Lint.Node{syntax, name, span, Con{Lint.Node{hs, callee, hp, hk, hf}, +args}, facts}:
      finding(
        verdict(params, args, None{}, known(List.reverse(&2, Lint.Above, path), None{}, []), lets, 0n),
        span,
        callee,
        text,
        args
      )
    case _ _:
      []

# The same, if `node` is a live call of its definition to itself (`recursive`).
def calls(recursive: Bool, +loop: Loop, +path: List<&2, Lint.Above>, node: Lint.Node) -> List<&2, Lint.Finding>:
  match recursive:
    case True{}:
      Bool.pick(List<&2, Lint.Finding>, Lint.live(path), call(loop, path, node), [])
    case False{}:
      []

def visit(+loop: Loop, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Lint.Finding>:
  calls(Lint.recursive(path, node), loop, path, node)

# The binders the lets of a definition bind, below `path`.
def let(+u: Unit, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, U32>:
  match path node:
    case Con{Lint.Above{Lint.Node{Lint.Destructure{q}, n, s, k, f}, at}, up} Lint.Node{Lint.PatternVariable{b, pq}, pn, ps, pk, pf}:
      [b]
    case _ _:
      []

# The findings in each definition among `nodes`, onto `out`. An @unsafe definition (`def f?`) may call itself freely.
def defs(nodes: List<&2, Lint.Node>, +text: String, out: List<&2, Lint.Finding>) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{Lint.Definition{+t, False{}}, +n, +s, +k, +f}, rest}:
      +owner = {Lint.Node{Lint.Definition{t, False{}}, n, s, k, f}: Lint.Node}
      defs(
        rest,
        text,
        Lists.onto(
          &2,
          Lint.Finding,
          Lint.visit(
            ~Loop,
            ~Lint.Finding,
            ~visit,
            Loop{Param.all(k, []), Lint.visit(~Unit, ~U32, ~let, Unit{}, [owner]), text},
            [owner]
          ),
          out
        )
      )
    case Con{node, rest}:
      defs(rest, text, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(defs(Lint.Here.nodes(here), Lint.Here.text(here), []))

def rule() -> Lint.Rule:
  Lint.Rule{"language/decreasing-call", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
