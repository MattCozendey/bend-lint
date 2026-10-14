# language/forward_reference: live code that uses a definition of its file defined below it.
# Heuristics: Bend checks definitions in file order, and one below is still a bodiless claim, so live
# code cannot use it: the check fails with "a filled definition". So two definitions cannot call each
# other. Types and equations are dead code, so they may name any definition, and an @unsafe
# definition (`def f?`) may use any. Bend's checker stops at its first error; this rule reports every
# such use at once. A definition used as a type argument of a call is dead too, but the rule cannot
# tell such an argument from a live one.
import Base
import ../../src/linter/lint.bend as Lint
import ../../src/shared/lists.bend as Lists
import ../../src/shared/names.bend as Names

# Types
# =====

# A definition of the file: where it is among the file's nodes, and its name as written.
type Place is Data:
  Place{at: U32, name: String}

# What judging the uses in one definition reads: where each definition of the file is, by the name the check gives it;
# and where the definition is, with its name.
type User is Data:
  User{places: Map<&2, Maybe<&2, Place>>, at: U32, name: String}

# Functions
# =========
def message(+used: String, +user: String) -> String:
  used
    ++ " is defined below "
    ++ user
    ++ ", and Bend checks definitions in file order: live code can use only what is defined above it, so this use fails the check (\"a filled definition\"). Move "
    ++ used
    ++ " above "
    ++ user
    ++ ". If the two call each other, merge them into one definition with an argument that selects which to run: Bend does not allow mutual recursion. This is a false positive if the use is an argument for an erased parameter (`-x`): that is dead code."

# Where each definition among `nodes`, the file's, is, from `at`, onto `out`.
def places(
  nodes: List<&2, Lint.Node>,
  +at: U32,
  out: Map<&2, Maybe<&2, Place>>
) -> Map<&2, Maybe<&2, Place>>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{Lint.Definition{t, u}, name, s, k, f}, rest}:
      places(rest, (at + 1: U32), Map.set(&2, Maybe<&2, Place>, out, t, Some{Place{at, name}}))
    case Con{node, rest}:
      places(rest, (at + 1: U32), out)

# The finding about a use of `used` from `user`, if `used` is below it. Whether the use is live is asked only then:
# `&&` computes both sides.
def below(
  hit: Bool,
  path: List<&2, Lint.Above>,
  used: String,
  user: String,
  span: Maybe<&2, Lint.Span>
) -> List<&2, Lint.Finding>:
  match hit:
    case True{}:
      Lint.finding(Lint.Warning{}, Lint.is_live(path), span, message(used, user))
    case False{}:
      []

def judged(
  path: List<&2, Lint.Above>,
  place: Maybe<&2, Place>,
  user: User,
  span: Maybe<&2, Lint.Span>
) -> List<&2, Lint.Finding>:
  match place user:
    case Some{Place{p, used}} User{places, at, name}:
      below(U32.is_gt(p, at), path, used, name, span)
    case _ _:
      []

def User.places(user: User) -> Map<&2, Maybe<&2, Place>>:
  match user:
    case User{places, at, name}:
      places

def use(+user: User, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Lint.Finding>:
  match node:
    case Lint.Node{Lint.Reference{t}, n, span, k, f}:
      judged(path, Names.find(Place, User.places(user), t), user, span)
    case _:
      []

# The findings in the definitions among `nodes`, from `at`, onto `out`. An @unsafe definition may use any.
def users(
  nodes: List<&2, Lint.Node>,
  +places: Map<&2, Maybe<&2, Place>>,
  +at: U32,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{Lint.Definition{t, False{}}, +name, s, k, f}, rest}:
      users(
        rest,
        places,
        (at + 1: U32),
        Lists.onto(
          &2,
          Lint.Finding,
          Lint.visit(
            ~User,
            ~Lint.Finding,
            ~use,
            User{places, at, name},
            [Lint.Node{Lint.Definition{t, False{}}, name, s, k, f}]
          ),
          out
        )
      )
    case Con{node, rest}:
      users(rest, places, (at + 1: U32), out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +nodes = Lint.Here.nodes(here)
  Lint.done(users(nodes, places(nodes, 0, Map.new(&2, Maybe<&2, Place>)), 0, []))

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
