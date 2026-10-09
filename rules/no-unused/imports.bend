# no-unused/imports: an import that nothing uses. An import is used when its
# alias is referenced, or when the file it loads, or a file that file
# imports, fills a law of another file. The fix removes the import's line.
# Run: bun src/lint.ts file.bend --rules rules/no-unused/imports.bend --fix
import Base
import ../../src/bend/lint.bend as Lint
import ../shared.bend as Shared

# Types
# =====

# A walk over the files that imports load: whether one fills a law of
# another file, the files still to read, and the files read or queued.
type Walk is Data:
  Walk{found: Bool, todo: List<&2, String>, seen: List<&2, String>}

# Load chain
# ==========
def any_fills(ds: List<&2, Lint.Declaration>) -> Bool:
  match ds:
    case Nil{}:
      False{}
    case Con{Lint.Declaration{kind, name, owner, span, refs, loads, fills, term}, rest}:
      Bool.or(fills, any_fills(rest))

def queue(skip: Bool, p: String, todo: List<&2, String>) -> List<&2, String>:
  match skip:
    case True{}:
      todo
    case False{}:
      Con{p, todo}

# The files the imports in `ds` load, not read or queued yet, put in front
# of `todo`.
def loaded(
  ds: List<&2, Lint.Declaration>,
  +todo: List<&2, String>,
  +seen: List<&2, String>
) -> List<&2, String>:
  match ds:
    case Nil{}:
      todo
    case Con{Lint.Declaration{kind, name, owner, span, refs, Some{+p}, fills, term}, rest}:
      loaded(rest, queue(Bool.or(Shared.known(todo, p), Shared.known(seen, p)), p, todo), seen)
    case Con{d, rest}:
      loaded(rest, todo, seen)

def step(+ds: List<&2, Lint.Declaration>, rest: List<&2, String>, +seen: List<&2, String>) -> Walk:
  Walk{any_fills(ds), loaded(ds, rest, seen), seen}

# Whether the walk finds a fill. Each file is read once, so `fuel`, the
# number of files the check read, is enough.
def chain(fuel: Nat, w: Walk) -> IO(Bool):
  match fuel w:
    case _ Walk{True{}, todo, seen}:
      IO.pure(Bool, True{})
    case 0n _:
      IO.pure(Bool, False{})
    case 1n+k Walk{False{}, Nil{}, seen}:
      IO.pure(Bool, False{})
    case 1n+k Walk{False{}, Con{+p, rest}, seen}:
      IO.bind(
        List<&2, Lint.Declaration>,
        Bool,
        Lint.declarations_of(p),
        ds => chain(k, step(ds, rest, Con{p, seen}))
      )

# Import lines
# ============

# Rule
# ====
def unused(used: Bool, +text: String, name: String, +span: Lint.Span) -> List<&2, Lint.Diag>:
  match used:
    case True{}:
      []
    case False{}:
      [
        Lint.Diag{
          Lint.Warning{},
          "Remove the import " ++ name ++ ": nothing uses it.",
          Some{span},
          [Lint.Fix{"Remove the import", Lint.Safe{}, [Lint.Edit{Shared.line_of(text, span), ""}]}],
          None{}
        }
      ]

def imports(
  ds: List<&2, Lint.Declaration>,
  +text: String,
  +fuel: Nat,
  acc: List<&2, Lint.Diag>
) -> IO(List<&2, Lint.Diag>):
  match ds:
    case Nil{}:
      IO.pure(List<&2, Lint.Diag>, List.reverse(&2, Lint.Diag, acc))
    case Con{Lint.Declaration{Lint.Import{}, name, owner, span, Nil{}, Some{p}, fills, term}, rest}:
      IO.bind(
        Bool,
        List<&2, Lint.Diag>,
        chain(fuel, Walk{False{}, [p], []}),
        used => imports(
          rest,
          text,
          fuel,
          List.append(&2, Lint.Diag, unused(used, text, name, span), acc)
        )
      )
    case Con{d, rest}:
      imports(rest, text, fuel, acc)

def id() -> String:
  "no-unused/imports"

def facts() -> Lint.Want:
  Lint.NoFacts{}

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  match input:
    case Lint.Input{root, sources, options, prior}:
      match root:
        case Lint.Source{path, text, is_root}:
          IO.bind(
            List<&2, Lint.Declaration>,
            List<&2, Lint.Diag>,
            Lint.declarations(),
            ds => imports(ds, text, List.length(&2, Lint.Source, sources), [])
          )

def main() -> IO(Unit):
  Lint.serve(run)
