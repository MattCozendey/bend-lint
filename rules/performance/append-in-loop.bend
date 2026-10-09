# performance/append-in-loop: a loop that grows an accumulator at its end.
# A def passes `List.append(acc, ..)` or `acc ++ ..` to its own call, for
# its parameter `acc`. Each append copies `acc`, so building it is O(n²)
# where building it at its head is O(n). The finding has no fix: the
# rewrite changes the loop's end.
# Run: bun src/lint.ts file.bend --rules rules/performance/append-in-loop.bend
import Base
import ../../src/bend/lint.bend as Lint
import ../shared.bend as Shared

# Types
# =====

# A function that copies its argument at `at` to append to it: its name,
# as the finding shows it, and its arity.
type Appender is Data:
  Appender{name: String, shown: String, arity: Nat, at: Nat}

# An append to the accumulator `acc` of def `self`: the call's span, its
# appender and its arguments.
type Append is Data:
  Append{
    self: String,
    acc: String,
    span: Maybe<&2, Lint.Span>,
    appender: Appender,
    args: List<&2, Shared.Arg>
  }

# Constants
# =========
def appenders() -> List<&2, Appender>:
  [Appender{"List.append", "List.append", 4n, 2n}, Appender{"String.append", "++", 2n, 0n}]

# Functions
# =========
def same_span(a: Maybe<&2, Lint.Span>, b: Maybe<&2, Lint.Span>) -> Bool:
  match a b:
    case Some{Lint.Span{p, x, y}} Some{Lint.Span{q, u, v}}:
      Bool.and(String.eq(p, q), Bool.and(U32.is_eq(x, u), U32.is_eq(y, v)))
    case _ _:
      False{}

# The appender a call of `head` with `arity` arguments is, if it appends
# to `acc`.
def appender_of(
  as: List<&2, Appender>,
  +head: String,
  +args: List<&2, String>,
  +acc: String
) -> Maybe<&2, Appender>:
  match as:
    case Nil{}:
      None{}
    case Con{Appender{+name, +shown, +arity, +at}, rest}:
      Bool.pick(
        Maybe<&2, Appender>,
        Bool.and(
          Bool.and(String.eq(name, head), Nat.is_eq(List.length(&2, String, args), arity)),
          String.eq(Shared.nth(args, at), acc)
        ),
        Some{Appender{name, shown, arity, at}},
        appender_of(rest, head, args, acc)
      )

def found(
  +self: String,
  +acc: String,
  span: Maybe<&2, Lint.Span>,
  args: List<&2, Shared.Arg>,
  m: Maybe<&2, Appender>
) -> List<&2, Append>:
  match m:
    case Some{a}:
      [Append{self, acc, span, a, args}]
    case None{}:
      []

# The appends among the calls `cs` that are the argument at `span`, for
# the parameter `acc`.
def appends(
  cs: List<&2, Shared.Call>,
  +self: String,
  +acc: String,
  +span: Maybe<&2, Lint.Span>
) -> List<&2, Append>:
  match cs:
    case Nil{}:
      []
    case Con{Shared.Call{+head, +args, +at}, rest}:
      List.append(
        &2,
        Append,
        Bool.pick(
          List<&2, Append>,
          same_span(at, span),
          found(self, acc, at, args, appender_of(appenders(), head, Shared.names(args), acc)),
          []
        ),
        appends(rest, self, acc, span)
      )

# The appends in the arguments of one call of `self` to itself, each for
# the parameter at its position.
def in_args(
  +cs: List<&2, Shared.Call>,
  +self: String,
  params: List<&2, String>,
  args: List<&2, Shared.Arg>
) -> List<&2, Append>:
  match params args:
    case Con{p, ps} Con{Shared.Arg{name, span}, rest}:
      List.append(&2, Append, appends(cs, self, p, span), in_args(cs, self, ps, rest))
    case _ _:
      []

def in_calls(
  +all: List<&2, Shared.Call>,
  cs: List<&2, Shared.Call>,
  +self: String,
  +params: List<&2, String>
) -> List<&2, Append>:
  match cs:
    case Nil{}:
      []
    case Con{Shared.Call{head, +args, span}, rest}:
      List.append(
        &2,
        Append,
        Bool.pick(
          List<&2, Append>,
          Bool.and(
            String.eq(head, self),
            Nat.is_eq(List.length(&2, Shared.Arg, args), List.length(&2, String, params))
          ),
          in_args(all, self, params, args),
          []
        ),
        in_calls(all, rest, self, params)
      )

def judge(bs: List<&2, Shared.Body>) -> List<&2, Append>:
  match bs:
    case Nil{}:
      []
    case Con{Shared.Body{name, params, +cs}, rest}:
      List.append(&2, Append, List.reverse(&2, Append, in_calls(cs, cs, name, params)), judge(rest))

# The text under a span, if there is one.
def text_at(m: Maybe<&2, Lint.Span>) -> IO(String):
  match m:
    case Some{s}:
      Lint.text(s)
    case None{}:
      IO.pure(String, "")

def arg_span(args: List<&2, Shared.Arg>, n: Nat) -> Maybe<&2, Lint.Span>:
  match args n:
    case Con{Shared.Arg{name, span}, rest} 0n:
      span
    case Con{a, rest} 1n+k:
      arg_span(rest, k)
    case Nil{} _:
      None{}

def message(+shown: String, +acc: String, +self: String, advice: String) -> String:
  shown
    ++ " copies "
    ++ acc
    ++ " on each call of "
    ++ self
    ++ ", so building it is O(n²). "
    ++ advice

# The finding for an append. Its advice spells the quantity and type of
# the List.append call, so that it compiles as written.
def diag(a: Append) -> IO(Lint.Diag):
  match a:
    case Append{+self, +acc, span, Appender{"List.append", +shown, arity, at}, +args}:
      do IO<Lint.Diag>:
        q: String <- text_at(arg_span(args, 0n))
        t: String <- text_at(arg_span(args, 1n))
        return Lint.Diag{
          Lint.Warning{},
          message(
            shown,
            acc,
            self,
            "Build it at its head with `x <> "
              ++ acc
              ++ "`, and reverse it once when the loop ends: `List.reverse("
              ++ q
              ++ ", "
              ++ t
              ++ ", "
              ++ acc
              ++ ")`."
          ),
          span,
          [],
          None{}
        }
    case Append{+self, +acc, span, Appender{name, +shown, arity, at}, args}:
      IO.pure(
        Lint.Diag,
        Lint.Diag{
          Lint.Warning{},
          message(
            shown,
            acc,
            self,
            "Collect the pieces in a list with `piece <> "
              ++ acc
              ++ "`, and join them once when the loop ends: `String.concat(List.reverse(&2, String, "
              ++ acc
              ++ "))`."
          ),
          span,
          [],
          None{}
        }
      )

def diags(as: List<&2, Append>) -> IO(List<&2, Lint.Diag>):
  match as:
    case Nil{}:
      IO.pure(List<&2, Lint.Diag>, [])
    case Con{a, rest}:
      do IO<List<&2, Lint.Diag>>:
        d: Lint.Diag <- diag(a)
        ds: List<&2, Lint.Diag> <- diags(rest)
        return Con{d, ds}

# Rule
# ====
def id() -> String:
  "performance/append-in-loop"

def facts() -> Lint.Want:
  Lint.NoFacts{}

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  do IO<List<&2, Lint.Diag>>:
    +ds: List<&2, Lint.Declaration> <- Lint.declarations()
    bs: List<&2, Shared.Body> <- Shared.bodies(ds, ds, [])
    diags(judge(bs))

def main() -> IO(Unit):
  Lint.serve(run)
