# performance/deep-call-in-fork: a fork that first calls a def that recurses without a tail call. A def has a parallel
# let, and its values, or the lets just before it, call a def of the file whose call of itself is not in tail position.
# In our tests, on the native lane, such a call at each fork cut the 16-thread speedup from 10x to 1.9x; the same def
# with a tail call kept it. The finding has no fix.
# A tail position is the body of a let, a lambda, a match's case or an annotation, and a value of a parallel let: a
# fork is not a loop. A call's head and arguments, a constructor's fields and a value of a let with one value are not.
import Base
import ../../main.bend as Lint
import ../shared.bend as Shared

# What a walk of a def's body found: whether the def calls itself out of tail position, and the calls at its forks,
# last first.
type Walk is Data:
  Walk{deep: Bool, calls: List<&2, Shared.Call>}

# A def of the file: its name, its number of parameters, and what a walk of its body found.
type Walked is Data:
  Walked{name: String, arity: Nat, walk: Walk}

# The calls in `ts`, before `done`, last first.
def calls_in(ts: List<&2, Lint.BendTerm>, done: List<&2, Shared.Call>) -> List<&2, Shared.Call>:
  match ts:
    case Nil{}:
      done
    case Con{t, rest}:
      calls_in(rest, Shared.get_calls(t, done))

def terms_of(ts: Lint.BendTerm) -> List<&2, Lint.BendTerm>:
  match ts:
    case Lint.SomeTerms{first, rest}:
      first <> terms_of(rest)
    case _:
      []

# A walk that also saw the fork whose values are `values`, with `before`, the values of the lets just before it.
def at_fork(
  fork: Bool,
  +before: List<&2, Lint.BendTerm>,
  +values: List<&2, Lint.BendTerm>,
  w: Walk
) -> Walk:
  match fork w:
    case True{} Walk{deep, calls}:
      Walk{deep, calls_in(List.append(&2, Lint.BendTerm, before, values), calls)}
    case False{} _:
      w

def own(+deep: Bool, hit: Bool) -> Bool:
  deep || hit

def deepened(hit: Bool, w: Walk) -> Walk:
  match w:
    case Walk{deep, calls}:
      Walk{own(deep, hit), calls}

# The values of the lets just before a let's value or body: for a let with one value, the ones before it and that
# value; for any other, none.
def lets_before(
  one: Bool,
  before: List<&2, Lint.BendTerm>,
  values: List<&2, Lint.BendTerm>
) -> List<&2, Lint.BendTerm>:
  match one:
    case True{}:
      List.append(&2, Lint.BendTerm, before, values)
    case False{}:
      []

# Walks `t`, in def `self` of `arity` parameters; `tail` tells whether `t` is in tail position, and `before` holds the
# values of the lets just before it.
def walk(
  t: Lint.BendTerm,
  +self: String,
  +arity: Nat,
  +tail: Bool,
  +before: List<&2, Lint.BendTerm>,
  w: Walk
) -> Walk:
  match t:
    case Lint.CallTerm{+head, +arguments, span}:
      walk(
        arguments,
        self,
        arity,
        False{},
        [],
        walk(
          head,
          self,
          arity,
          False{},
          [],
          deepened(
            Bool.not(
              tail
            )
              && String.eq(Shared.get_reference_name(head), self)
              && Nat.is_eq(Shared.get_term_count(arguments), arity),
            w
          )
        )
      )
    case Lint.LetTerm{names, +values, body, span}:
      +n = Shared.get_term_count(values)
      +listed = terms_of(values)
      +near = lets_before(Nat.is_eq(n, 1n), before, listed)
      walk(
        body,
        self,
        arity,
        tail,
        near,
        walk(
          values,
          self,
          arity,
          Nat.is_ge(n, 2n),
          near,
          at_fork(Nat.is_ge(n, 2n), before, listed, w)
        )
      )
    case Lint.LambdaTerm{name, body, span}:
      walk(body, self, arity, tail, [], w)
    case Lint.AnnotatedTerm{value, annotation, span}:
      walk(annotation, self, arity, tail, before, walk(value, self, arity, tail, before, w))
    case Lint.CheckedTerm{term, fact}:
      walk(term, self, arity, tail, before, w)
    case Lint.ConstructorTerm{name, fields, span}:
      walk(fields, self, arity, False{}, [], w)
    case Lint.ForallTerm{name, quantity, domain, body, span}:
      walk(body, self, arity, tail, [], walk(domain, self, arity, tail, [], w))
    case Lint.SortTerm{level, span}:
      walk(level, self, arity, tail, [], w)
    case Lint.DatatypeTerm{name, arguments, span}:
      walk(arguments, self, arity, tail, [], w)
    case Lint.OtherTerm{parts, span}:
      walk(parts, self, arity, tail, [], w)
    case Lint.SomeTerms{first, rest}:
      walk(rest, self, arity, tail, before, walk(first, self, arity, tail, before, w))
    case _:
      w

def walked(defs: List<&2, Shared.Def>) -> List<&2, Walked>:
  match defs:
    case Nil{}:
      []
    case Con{Shared.Def{+name, params, body}, t}:
      +arity = List.length(&2, String, params)
      Walked{name, arity, walk(body, name, arity, True{}, [], Walk{False{}, []})} <> walked(t)

def deep_named(ws: List<&2, Walked>, +name: String, +arity: Nat) -> Bool:
  match ws:
    case Nil{}:
      False{}
    case Con{Walked{n, a, Walk{deep, calls}}, rest}:
      (deep && String.eq(n, name) && Nat.is_eq(a, arity)) || deep_named(rest, name, arity)

def finding(
  hit: Bool,
  +self: String,
  +callee: String,
  +path: String,
  span: Maybe<&2, Lint.BendSourceSpan>
) -> List<&2, Lint.Finding>:
  match hit:
    case True{}:
      [
        Lint.Finding{
          Lint.Warning{},
          callee
            ++ " recurses without a tail call, and "
            ++ self
            ++ " calls it at each fork. In our tests, such a call cut the 16-thread speedup from 10x to 1.9x; a tail call kept it. Make "
            ++ callee
            ++ " tail-recursive with an accumulator, compute its value with native operations, or pass it down as a parameter.",
          Shared.get_span_or_start(path, span),
          []
        }
      ]
    case False{}:
      []

def call_findings(
  +ws: List<&2, Walked>,
  +self: String,
  +path: String,
  cs: List<&2, Shared.Call>
) -> List<&2, Lint.Finding>:
  match cs:
    case Nil{}:
      []
    case Con{Shared.Call{+head, arguments, span}, rest}:
      List.append(
        &2,
        Lint.Finding,
        finding(
          Bool.not(String.eq(head, self)) && deep_named(ws, head, Shared.get_term_count(arguments)),
          self,
          head,
          path,
          span
        ),
        call_findings(ws, self, path, rest)
      )

def findings(+all: List<&2, Walked>, ws: List<&2, Walked>, +path: String) -> List<&2, Lint.Finding>:
  match ws:
    case Nil{}:
      []
    case Con{Walked{+name, arity, Walk{deep, calls}}, rest}:
      List.append(
        &2,
        Lint.Finding,
        call_findings(all, name, path, List.reverse(&2, Shared.Call, calls)),
        findings(all, rest, path)
      )

def lint(input: Lint.RuleInput) -> List<&2, Lint.Finding>:
  match input:
    case Lint.RuleInput{root, sources, options, prior, declarations, instances}:
      match root:
        case Lint.BendSource{+path, text, lines}:
          +ws = walked(Shared.get_defs(Shared.get_declarations_of(declarations, path)))
          findings(ws, ws, path)

def run(input: Lint.RuleInput) -> Lint.RuleStep:
  Lint.RuleDone{lint(input)}

def rules() -> List<&1, Lint.Rule>:
  [Lint.Rule{"performance/deep-call-in-fork", Lint.FileScope{}, [], [], [Lint.BodiesNeed{}], run}]
