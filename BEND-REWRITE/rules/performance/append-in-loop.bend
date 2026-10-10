# performance/append-in-loop: a loop that grows an accumulator at its end. A def passes `List.append(acc, ..)` or
# `acc ++ ..` to its own call, for its parameter `acc`. Each append copies `acc`, so building it is O(n²) where building
# it at its head is O(n). The finding has no fix: the rewrite changes the loop's end.
import Base
import ../../main.bend as Lint
import ../shared.bend as Shared

# A function that copies its argument at `at` to append to it: its name, as the finding shows it, and its arity.
type Appender is Data:
  Appender{name: String, shown: String, arity: Nat, at: Nat}

def appenders() -> List<&2, Appender>:
  [Appender{"List.append", "List.append", 4n, 2n}, Appender{"String.append", "++", 2n, 0n}]

# The appender a call of `head` with the `count` arguments `args` is, if it appends to `acc`.
def appender_of(
  as: List<&2, Appender>,
  +head: String,
  +args: List<&2, String>,
  +count: Nat,
  +acc: String
) -> Maybe<&2, Appender>:
  match as:
    case Nil{}:
      None{}
    case Con{Appender{+name, +shown, +arity, +at}, rest}:
      Bool.pick(
        Maybe<&2, Appender>,
        String.eq(
          name,
          head
        )
          && Nat.is_eq(count, arity)
          && String.eq(Shared.get_nth(args, at), acc),
        Some{Appender{name, shown, arity, at}},
        appender_of(rest, head, args, count, acc)
      )

def message(+shown: String, +acc: String, +self: String, advice: String) -> String:
  shown
    ++ " copies "
    ++ acc
    ++ " on each call of "
    ++ self
    ++ ", so building it is O(n²). "
    ++ advice

# What to do instead. For List.append, it spells the call's quantity and type, so that it compiles as written.
def advice(
  name: String,
  +acc: String,
  +lines: List<&2, String>,
  +arguments: Lint.BendTerm
) -> String:
  match name:
    case "List.append":
      "Build it at its head with `x <> "
        ++ acc
        ++ "`, and reverse it once when the loop ends: `List.reverse("
        ++ Shared.get_term_text(lines, Shared.get_nth_term(arguments, 0n))
        ++ ", "
        ++ Shared.get_term_text(lines, Shared.get_nth_term(arguments, 1n))
        ++ ", "
        ++ acc
        ++ ")`."
    case _:
      "Collect the pieces in a list with `piece <> "
        ++ acc
        ++ "`, and join them once when the loop ends: `String.concat(List.reverse(&2, String, "
        ++ acc
        ++ "))`."

def finding(
  m: Maybe<&2, Appender>,
  +self: String,
  +acc: String,
  +lines: List<&2, String>,
  +path: String,
  +arguments: Lint.BendTerm,
  span: Maybe<&2, Lint.BendSourceSpan>
) -> List<&2, Lint.Finding>:
  match m:
    case None{}:
      []
    case Some{Appender{name, shown, arity, at}}:
      [
        Lint.Finding{
          Lint.Warning{},
          message(shown, acc, self, advice(name, acc, lines, arguments)),
          Shared.get_span_or_start(path, span),
          []
        }
      ]

# The append that `arg`, an argument of a call of `self`, is, for the parameter `acc` at its position.
def in_arg(
  arg: Lint.BendTerm,
  +self: String,
  +acc: String,
  +lines: List<&2, String>,
  +path: String
) -> List<&2, Lint.Finding>:
  match arg:
    case Lint.CallTerm{head, +arguments, span}:
      finding(
        appender_of(
          appenders(),
          Shared.get_reference_name(head),
          Shared.get_arg_names(arguments),
          Shared.get_term_count(arguments),
          acc
        ),
        self,
        acc,
        lines,
        path,
        arguments,
        span
      )
    case _:
      []

def in_args(
  params: List<&2, String>,
  args: Lint.BendTerm,
  +self: String,
  +lines: List<&2, String>,
  +path: String
) -> List<&2, Lint.Finding>:
  match params args:
    case Con{p, ps} Lint.SomeTerms{first, rest}:
      List.append(
        &2,
        Lint.Finding,
        in_arg(Shared.get_bare(first), self, p, lines, path),
        in_args(ps, rest, self, lines, path)
      )
    case _ _:
      []

def in_call(
  hit: Bool,
  +params: List<&2, String>,
  arguments: Lint.BendTerm,
  +self: String,
  +lines: List<&2, String>,
  +path: String
) -> List<&2, Lint.Finding>:
  match hit:
    case True{}:
      in_args(params, arguments, self, lines, path)
    case False{}:
      []

# The appends in the calls `cs` of def `self` to itself, with all its `arity` parameters `params`.
def in_calls(
  cs: List<&2, Shared.Call>,
  +self: String,
  +params: List<&2, String>,
  +arity: Nat,
  +lines: List<&2, String>,
  +path: String
) -> List<&2, Lint.Finding>:
  match cs:
    case Nil{}:
      []
    case Con{Shared.Call{head, +arguments, span}, rest}:
      List.append(
        &2,
        Lint.Finding,
        in_call(
          String.eq(head, self) && Nat.is_eq(Shared.get_term_count(arguments), arity),
          params,
          arguments,
          self,
          lines,
          path
        ),
        in_calls(rest, self, params, arity, lines, path)
      )

def judge(
  bs: List<&2, Shared.Body>,
  +lines: List<&2, String>,
  +path: String
) -> List<&2, Lint.Finding>:
  match bs:
    case Nil{}:
      []
    case Con{Shared.Body{+name, +params, cs}, rest}:
      List.append(
        &2,
        Lint.Finding,
        in_calls(cs, name, params, List.length(&2, String, params), lines, path),
        judge(rest, lines, path)
      )

def lint(input: Lint.RuleInput) -> List<&2, Lint.Finding>:
  match input:
    case Lint.RuleInput{root, sources, options, prior, declarations, instances}:
      match root:
        case Lint.BendSource{+path, text, +lines}:
          judge(Shared.get_bodies(Shared.get_declarations_of(declarations, path)), lines, path)

def run(input: Lint.RuleInput) -> Lint.RuleStep:
  Lint.RuleDone{lint(input)}

def rules() -> List<&1, Lint.Rule>:
  [Lint.Rule{"performance/append-in-loop", Lint.FileScope{}, [], [], [Lint.BodiesNeed{}], run}]
