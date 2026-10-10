# no-unused/imports: an import that nothing in its file uses. An import is used when a name written through its
# alias is used (`U.two`, a fill `def U.law(x):`); `import Base`, when a name with no namespace that the file does not
# declare is used.
import Base
import ../../lint.bend as Lint

# What uses an import: a name written with its alias's prefix, or, for Base, a name with no namespace that the file
# does not declare.
type Wanted is Data:
  ByAlias{prefix: String}
  ByBase{declared: List<&2, String>}

def uses.base(+declared: List<&2, String>, used: Maybe<&2, String>) -> Bool:
  match used:
    case Some{+name}:
      String.is_empty(Lint.Name.namespace(name)) && Bool.not(List.contains(~String, ~String.eq, declared, name))
    case None{}:
      False{}

def uses(+wanted: Wanted, node: Lint.Node) -> Bool:
  match wanted node:
    case ByAlias{+prefix} Lint.Node{id, parent, syntax, name, binder, quantity, span, target}:
      String.starts_with(name, prefix)
    case ByBase{+declared} _:
      uses.base(declared, Lint.Node.used(node))

def wanted(base: Bool, alias: String, +here: Lint.Here) -> Wanted:
  match base:
    case True{}:
      ByBase{Lint.Here.declared(here)}
    case False{}:
      ByAlias{alias ++ "."}

def report(used: Bool, name: String, span: Lint.Span) -> List<&2, Lint.Finding>:
  match used:
    case True{}:
      []
    case False{}:
      [Lint.Finding{Lint.Warning{}, span, "Remove the import " ++ name ++ ": nothing uses it."}]

def unused(+here: Lint.Here, node: Lint.Node) -> List<&2, Lint.Finding>:
  match node:
    case Lint.Node{id, parent, Lint.Import{}, +name, binder, quantity, Some{span}, target}:
      report(
        Lint.any(
          ~Wanted,
          ~uses,
          wanted(String.is_empty(Lint.Here.namespace_of(here, target)), name, here),
          Lint.Here.nodes(here)
        ),
        name,
        span
      )
    case _:
      []

def run(+here: Lint.Here) -> List<&2, Lint.Finding>:
  Lint.each(~Lint.Here, ~unused, here, Lint.Here.nodes(here))

def rule() -> Lint.Rule:
  Lint.Rule{"no-unused/imports", run}
