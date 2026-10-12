# language/forward-reference: live code that uses a definition of its file defined below it.
# Heuristics: Bend checks definitions in file order, and one below is still a bodiless claim, so live
# code cannot use it: the check fails with "a filled definition". So two definitions cannot call each
# other. Types and equations are dead code, so they may name any definition, and an @unsafe
# definition (`def f?`) may use any. Bend's checker stops at its first error; this rule reports every
# such use at once. A definition used as a type argument of a call is dead too, but the rule cannot
# tell such an argument from a live one.
import Base
import ../../linter/lint.bend as Lint
import ../../linter/shared.bend as Shared
import ../../shared/lists.bend as Lists
import ../../shared/names.bend as Names

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

# The finding about a use, numbered `id`, if the definition it uses (`at`) is below the one it is in (`owner`). Whether
# the use is live is asked only then: `&&` computes both sides.
def below(
  hit: Bool,
  name: String,
  owner: U32,
  id: U32,
  span: Lint.Span,
  +here: Lint.Here
) -> List<&2, Lint.Finding>:
  match hit:
    case True{}:
      Shared.finding(
        Lint.Warning{},
        Lint.Here.live(here, id),
        Some{span},
        message(name, Lint.Node.name(Lint.Here.node(here, owner)))
      )
    case False{}:
      []

# The finding about a use of `used`, a definition of the file, from the definition numbered `owner`.
def judged(
  used: Maybe<&2, Lint.Node>,
  +owner: U32,
  id: U32,
  span: Maybe<&2, Lint.Span>,
  here: Lint.Here,
  unsafes: List<&2, U32>
) -> List<&2, Lint.Finding>:
  match used span:
    case Some{Lint.Node{at, up, o, sy, name, b, q, sp, t}} Some{s}:
      below(
        U32.is_gt(at, owner) && Bool.not(List.contains(~U32, ~U32.is_eq, unsafes, owner)),
        name,
        owner,
        id,
        s,
        here
      )
    case _ _:
      []

def scan(
  nodes: List<&2, Lint.Node>,
  +defs: Map<&2, Maybe<&2, Lint.Node>>,
  +here: Lint.Here,
  +unsafes: List<&2, U32>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{id, p, owner, Lint.Reference{}, n, b, q, span, target}, rest}:
      scan(
        rest,
        defs,
        here,
        unsafes,
        Lists.onto(
          &2,
          Lint.Finding,
          judged(Names.find(Lint.Node, defs, target), owner, id, span, here, unsafes),
          out
        )
      )
    case Con{node, rest}:
      scan(rest, defs, here, unsafes, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +nodes = Lint.Here.nodes(here)
  Lint.done(scan(nodes, Shared.definitions(nodes), here, Lint.Here.unsafes(here), []))

def rule() -> Lint.Rule:
  Lint.Rule{"language/forward-reference", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
