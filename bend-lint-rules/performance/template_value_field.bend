# performance/template_value_field: a value field of a record of functions that reads a template whose type is a
# record of functions. Bend writes a template where it is used, so a record of functions passed as one is built
# again at each use; a field that is not a function is computed then, and reading the template builds its whole
# record, closures too, to read a part of it, then frees the rest.
# Heuristics: measured on a combinator of two records of functions, nested 6 deep and run 2M times: 1.7 s with a
# count as a value field, against 1.0 s with the count under a lambda (`u => ..`), on the C lane (one thread), and
# 49 s against 14 s on the JS lane, with the same output; issue #2 measured 6% more time on a nested model, and
# nothing on a shallow one, as the cost doubles with each level. The lambda moves the work to each read: with the
# count read on every step too, it took 2.4 s against 1.9 s. A record of functions is a datatype of the program
# with a field whose written type is a function; a record that the rule judges is built in live code, outside a
# lambda, with a lambda among its fields: a record of values only is a result, built once. A template of another
# type (a number, a function, a list) builds no record of closures, and is not judged. A use in a type, or under a
# lambda, does not run when the record is built.
import Base
import ../../src/linter/lint.bend as Lint
import ../../src/shared/lists.bend as Lists

# Types
# =====

# What judging the uses of one definition's templates reads: the binders of its templates whose type is a record of
# functions, and its name as written.
type Owner is Data:
  Owner{templates: List<&2, U32>, name: String}

# Functions
# =========
def message(+template: String, owner: String) -> String:
  template
    ++ " is a template, so reading it here builds its whole record, closures too, to read a part of it; and a record of functions passed as a template is built again at each use, so "
    ++ owner
    ++ " repeats this wherever its record is used, twice as often at each level of nesting. All lanes. Measured on a combinator nested 6 deep: 1.7 s against 1.0 s after the fix on the C lane, 49 s against 14 s on the JS lane; on a nested model, 6% of the time. Confidence: medium, as the fix moves the work to each read of the field. Make the field a function of Unit (`n: Unit -> U32`, built as `u => ..`), so that "
    ++ template
    ++ " is read only when the field is called. If the field is read about as often as the record is built, expect this finding."

def records.step(+u: Unit, +node: Lint.Node, found: Bool) -> Bool:
  match node:
    case Lint.Node{
      Lint.Field{b, q},
      n,
      s,
      Con{Lint.Node{Lint.Forall{fb, fq}, fn, fs, fk, ff}, rest},
      f
    }:
      True{}
    case _:
      found

# The datatypes among `nodes` with a field whose written type is a function, by the name the check gives them, onto
# `out`.
def records(nodes: List<&2, Lint.Node>, out: List<&2, String>) -> List<&2, String>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{Lint.Datatype{t}, n, s, kids, f}, rest}:
      records(
        rest,
        Lists.push(
          String,
          Lists.when(String, Lint.fold(~Unit, ~Bool, ~records.step, Unit{}, kids, False{}), t),
          out
        )
      )
    case Con{node, rest}:
      records(rest, out)

def program.records(sources: List<&2, Lint.Source>, out: List<&2, String>) -> List<&2, String>:
  match sources:
    case Nil{}:
      out
    case Con{Lint.Source{path, ns, text, nodes}, rest}:
      program.records(rest, records(nodes, out))

# The datatype a type's nodes write, by the name the check gives it, or "" for another form (a function, a sort).
def written(nodes: List<&2, Lint.Node>) -> String:
  match nodes:
    case Con{Lint.Node{Lint.Reference{t}, n, s, k, f}, rest}:
      t
    case Con{Lint.Node{Lint.TypeApplication{t}, n, s, k, f}, rest}:
      t
    case _:
      ""

# The binders of the templates among a definition's nodes whose type is one of `records`, onto `out`.
def templates(
  nodes: List<&2, Lint.Node>,
  +records: List<&2, String>,
  out: List<&2, U32>
) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{Lint.Parameter{b, Lint.Template{}}, n, s, kids, f}, rest}:
      templates(
        rest,
        records,
        Lists.push(
          U32,
          Lists.when(U32, List.contains(~String, ~String.eq, records, written(kids)), b),
          out
        )
      )
    case Con{node, rest}:
      templates(rest, records, out)

def is_lambda(node: Lint.Node) -> Bool:
  match node:
    case Lint.Node{Lint.Lambda{b, q}, n, s, k, f}:
      True{}
    case _:
      False{}

# Whether a node below `path` is computed when a record of functions is built: under no lambda, and in a construction
# with a lambda among its fields (`found`, once one is).
def is_built(path: List<&2, Lint.Above>, found: Bool) -> Bool:
  match path:
    case Nil{}:
      found
    case Con{Lint.Above{Lint.Node{Lint.Lambda{b, q}, n, s, k, f}, at}, rest}:
      False{}
    case Con{Lint.Above{Lint.Node{Lint.Construction{t}, n, s, kids, f}, at}, rest}:
      is_built(rest, Bool.or(found, Lists.any(~Lint.Node, ~is_lambda, kids)))
    case Con{a, rest}:
      is_built(rest, found)

def visit(+owner: Owner, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Lint.Finding>:
  match owner node:
    case Owner{templates, name} Lint.Node{Lint.Variable{b}, template, span, k, f}:
      Lint.finding(
        Lint.Information{},
        Bool.and(
          List.contains(~U32, ~U32.is_eq, templates, b),
          Bool.and(Lint.is_live(path), is_built(path, False{}))
        ),
        span,
        message(template, name)
      )
    case _ _:
      []

# The findings in the definitions among `nodes` that have templates of `records`, onto `out` (last first).
def defs(
  nodes: List<&2, Lint.Node>,
  +records: List<&2, String>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{Lint.Definition{t, u}, +n, s, +kids, f}, rest}:
      defs(
        rest,
        records,
        Lists.onto(
          &2,
          Lint.Finding,
          Lint.visit(
            ~Owner,
            ~Lint.Finding,
            ~visit,
            Owner{templates(kids, records, []), n},
            [Lint.Node{Lint.Definition{t, u}, n, s, kids, f}]
          ),
          out
        )
      )
    case Con{node, rest}:
      defs(rest, records, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(
    List.reverse(
      &2,
      Lint.Finding,
      defs(Lint.Here.nodes(here), program.records(Lint.Here.sources(here), []), [])
    )
  )

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
