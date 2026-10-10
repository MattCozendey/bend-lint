# performance/list-index-loop: a loop that reads a list from its head on each step. A def passes a list parameter
# unchanged to its own call, and also gives it to List.get, List.drop, List.take, List.last or List.length, or to a def
# of the file that gives it to one of those. Each of those walks the list from its head, so the loop is O(n²) where a
# walk of the list is O(n). The finding has no fix: the rewrite changes the loop's parameters.
import Base
import ../../main.bend as Lint
import ../shared.bend as Shared

# A list function that walks a list from its head: its name, its arity, and what to do instead.
type Walker is Data:
  Walker{name: String, arity: Nat, advice: String}

# A call that walks one of its arguments from its head: the callee, its arity, the argument's position, and the list
# function that walks it.
type Site is Data:
  Site{name: String, arity: Nat, at: Nat, walker: Walker}

def walk_advice() -> String:
  "Walk it instead: match it, use its head, and pass its tail to the next call."

# The list functions that walk a list from its head.
def walkers() -> List<&2, Walker>:
  [
    Walker{"List.get", 4n, walk_advice()},
    Walker{"List.drop", 4n, walk_advice()},
    Walker{"List.take", 4n, walk_advice()},
    Walker{"List.last", 3n, walk_advice()},
    Walker{"List.length", 3n, "Compute it once before the loop, and pass it as a parameter."}
  ]

# Whether a call of `self` passes `v` at position `k`, unchanged.
def passes(cs: List<&2, Shared.Call>, +self: String, +arity: Nat, +k: Nat, +v: String) -> Bool:
  match cs:
    case Nil{}:
      False{}
    case Con{Shared.Call{head, arguments, span}, rest}:
      +args = Shared.get_arg_names(arguments)
      (
        String.eq(
          head,
          self
        )
          && Nat.is_eq(List.length(&2, String, args), arity)
          && String.eq(Shared.get_nth(args, k), v)
      )
        || passes(rest, self, arity, k, v)

def passes_at(
  cs: List<&2, Shared.Call>,
  +self: String,
  arity: Nat,
  at: Maybe<&2, Nat>,
  +v: String
) -> Bool:
  match at:
    case Some{k}:
      passes(cs, self, arity, k, v)
    case None{}:
      False{}

# Whether def `self`, with the `arity` parameters `params`, passes `v` unchanged to its own call.
def kept(
  cs: List<&2, Shared.Call>,
  +self: String,
  +params: List<&2, String>,
  arity: Nat,
  +v: String
) -> Bool:
  passes_at(cs, self, arity, Shared.get_position(params, v, 0n), v)

# The list functions, as sites: each walks its third argument.
def direct(ws: List<&2, Walker>) -> List<&2, Site>:
  match ws:
    case Nil{}:
      []
    case Con{Walker{+name, +arity, advice}, rest}:
      Site{name, arity, 2n, Walker{name, arity, advice}} <> direct(rest)

def fits(s: Site, +head: String, +arity: Nat) -> Bool:
  match s:
    case Site{name, a, at, w}:
      String.eq(name, head) && Nat.is_eq(a, arity)

# The sites that a call of `head` with `arity` arguments is.
def matching(ss: List<&2, Site>, +head: String, +arity: Nat) -> List<&2, Site>:
  match ss:
    case Nil{}:
      []
    case Con{+s, rest}:
      Lint.get_kept(Site, fits(s, head, arity), s, matching(rest, head, arity))

def helper_at(+g: String, arity: Nat, k: Maybe<&2, Nat>, w: Walker) -> List<&2, Site>:
  match k:
    case Some{at}:
      [Site{g, arity, at, w}]
    case None{}:
      []

# The sites that def `g`, with the `arity` parameters `params`, adds when it gives a parameter to the list function of
# `ss`, with the call's arguments `args`.
def helpers(
  +g: String,
  +params: List<&2, String>,
  +arity: Nat,
  +args: List<&2, String>,
  ss: List<&2, Site>
) -> List<&2, Site>:
  match ss:
    case Nil{}:
      []
    case Con{Site{name, a, at, w}, rest}:
      List.append(
        &2,
        Site,
        helper_at(g, arity, Shared.get_position(params, Shared.get_nth(args, at), 0n), w),
        helpers(g, params, arity, args, rest)
      )

def helpers_of_calls(
  +direct: List<&2, Site>,
  +g: String,
  +params: List<&2, String>,
  +arity: Nat,
  cs: List<&2, Shared.Call>
) -> List<&2, Site>:
  match cs:
    case Nil{}:
      []
    case Con{Shared.Call{+head, arguments, span}, rest}:
      +args = Shared.get_arg_names(arguments)
      List.append(
        &2,
        Site,
        helpers(g, params, arity, args, matching(direct, head, List.length(&2, String, args))),
        helpers_of_calls(direct, g, params, arity, rest)
      )

# The sites of the list functions, and of the defs that give one of their parameters to a list function: a call of
# those walks that argument.
def sites(+direct: List<&2, Site>, bs: List<&2, Shared.Body>) -> List<&2, Site>:
  match bs:
    case Nil{}:
      direct
    case Con{Shared.Body{name, +params, cs}, rest}:
      List.append(
        &2,
        Site,
        helpers_of_calls(direct, name, params, List.length(&2, String, params), cs),
        sites(direct, rest)
      )

# How the call of `head` walks the list: itself, or through a list function.
def through(+head: String, +name: String) -> String:
  Bool.pick(String, String.eq(head, name), "", " (through " ++ name ++ ")")

def finding(
  hit: Bool,
  +self: String,
  +head: String,
  +v: String,
  w: Walker,
  span: Lint.BendSourceSpan
) -> List<&2, Lint.Finding>:
  match hit w:
    case True{} Walker{name, arity, advice}:
      [
        Lint.Finding{
          Lint.Warning{},
          head
            ++ " walks "
            ++ v
            ++ " from its head"
            ++ through(head, name)
            ++ ", and "
            ++ self
            ++ " passes "
            ++ v
            ++ " unchanged to each call of itself: the loop is O(n²). "
            ++ advice,
          span,
          []
        }
      ]
    case False{} _:
      []

def judged(
  +cs: List<&2, Shared.Call>,
  +self: String,
  +params: List<&2, String>,
  +arity: Nat,
  +head: String,
  +args: List<&2, String>,
  +span: Lint.BendSourceSpan,
  ss: List<&2, Site>
) -> List<&2, Lint.Finding>:
  match ss:
    case Nil{}:
      []
    case Con{Site{name, a, at, w}, rest}:
      +v = Shared.get_nth(args, at)
      List.append(
        &2,
        Lint.Finding,
        finding(kept(cs, self, params, arity, v), self, head, v, w, span),
        judged(cs, self, params, arity, head, args, span, rest)
      )

# The findings for the calls `cs` of def `self`; its calls of itself are skipped.
def findings(
  +path: String,
  +ss: List<&2, Site>,
  +all: List<&2, Shared.Call>,
  cs: List<&2, Shared.Call>,
  +self: String,
  +params: List<&2, String>,
  +arity: Nat
) -> List<&2, Lint.Finding>:
  match cs:
    case Nil{}:
      []
    case Con{Shared.Call{+head, arguments, span}, rest}:
      +args = Shared.get_arg_names(arguments)
      List.append(
        &2,
        Lint.Finding,
        Bool.pick(
          List<&2, Lint.Finding>,
          String.eq(head, self),
          [],
          judged(
            all,
            self,
            params,
            arity,
            head,
            args,
            Shared.get_span_or_start(path, span),
            matching(ss, head, List.length(&2, String, args))
          )
        ),
        findings(path, ss, all, rest, self, params, arity)
      )

def all_findings(
  +path: String,
  +ss: List<&2, Site>,
  bs: List<&2, Shared.Body>
) -> List<&2, Lint.Finding>:
  match bs:
    case Nil{}:
      []
    case Con{Shared.Body{+name, +params, +cs}, rest}:
      List.append(
        &2,
        Lint.Finding,
        findings(path, ss, cs, cs, name, params, List.length(&2, String, params)),
        all_findings(path, ss, rest)
      )

def run(input: Lint.RuleInput) -> List<&2, Lint.Finding>:
  match input:
    case Lint.RuleInput{root, sources, options, prior, declarations}:
      match root:
        case Lint.BendSource{+path, text, lines}:
          +bs = Shared.get_bodies(Shared.get_declarations_of(declarations, path))
          all_findings(path, sites(direct(walkers()), bs), bs)

def rules() -> List<&1, Lint.Rule>:
  [Lint.Rule{"performance/list-index-loop", Lint.FileScope{}, [], [], [Lint.BodiesNeed{}], run}]
