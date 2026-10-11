# language/forward-reference: live code that uses a definition of its file defined below it.
# Heuristics: Bend checks definitions in file order, and one below is still a bodiless claim, so live
# code cannot use it: the check fails with "a filled definition". So two definitions cannot call each
# other. Types and equations are dead code, so they may name any definition, and an @unsafe
# definition (`def f?`) may use any. Bend's checker stops at its first error; this rule reports every
# such use at once. A definition used as a type argument of a call is dead too, but the rule cannot
# tell such an argument from a live one.
import Base
import ../../lint.bend as Lint
import ../../shared.bend as Shared

# Types
# =====

# A definition of the file: the name the check gives it, its node's id, and its name as written.
type Def is Data:
  Def{target: String, id: U32, name: String}

# Functions
# =========
def Def.all(nodes: List<&2, Lint.Node>, out: List<&2, Def>) -> List<&2, Def>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{id, p, o, Lint.Definition{}, name, b, q, s, target}, rest}:
      Def.all(rest, Def{target, id, name} <> out)
    case Con{node, rest}:
      Def.all(rest, out)

# The definition named `target`, if the file defines it.
def Def.find(defs: List<&2, Def>, +target: String) -> Maybe<&2, Def>:
  match defs:
    case Nil{}:
      None{}
    case Con{Def{+t, i, n}, rest}:
      Bool.pick(Maybe<&2, Def>, String.eq(t, target), Some{Def{t, i, n}}, Def.find(rest, target))

def message(+used: String, +user: String) -> String:
  used
    ++ " is defined below "
    ++ user
    ++ ", and Bend checks definitions in file order: live code can use only what is defined above it, so this use fails the check (\"a filled definition\"). Move "
    ++ used
    ++ " above "
    ++ user
    ++ ". If the two call each other, merge them into one definition with an argument that selects which to run: Bend does not allow mutual recursion. This is a false positive if the use is an argument for an erased parameter (`-x`): that is dead code."

# The finding about a use of `used`, a definition of the file, from the definition numbered `owner`.
def judged(
  used: Maybe<&2, Def>,
  +owner: U32,
  +id: U32,
  span: Maybe<&2, Lint.Span>,
  +here: Lint.Here
) -> List<&2, Lint.Finding>:
  match used span:
    case Some{Def{t, +at, +name}} Some{s}:
      Bool.pick(
        List<&2, Lint.Finding>,
        U32.is_gt(
          at,
          owner
        )
          && Bool.not(Lint.Here.unsafe(here, Lint.Here.node(here, owner)))
          && Lint.Here.live(here, id),
        [
          Lint.Finding{
            Lint.Warning{},
            s,
            message(name, Lint.Node.name(Lint.Here.node(here, owner))),
            []
          }
        ],
        []
      )
    case _ _:
      []

def scan(
  nodes: List<&2, Lint.Node>,
  +defs: List<&2, Def>,
  +here: Lint.Here,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{+id, p, +owner, Lint.Reference{}, n, b, q, span, +target}, rest}:
      scan(
        rest,
        defs,
        here,
        Shared.onto(&2, Lint.Finding, judged(Def.find(defs, target), owner, id, span, here), out)
      )
    case Con{node, rest}:
      scan(rest, defs, here, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +nodes = Lint.Here.nodes(here)
  Lint.done(scan(nodes, Def.all(nodes, []), here, []))

def rule() -> Lint.Rule:
  Lint.Rule{"language/forward-reference", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
