# no-unused/imports: an import that nothing uses. An import is used when its alias is referenced, or when the file it
# loads, or a file that file imports, fills a law of another file. The fix removes the import's line.
import Base
import ../../main.bend as Lint

type Walk is Data:
  Walk{found: Bool, todo: List<&2, String>, seen: List<&2, String>}

def get_has(xs: List<&2, String>, +x: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      String.eq(h, x) || get_has(t, x)

def get_declarations_of.pick(
  hit: Bool,
  ds: List<&2, Lint.Declaration>,
  rest: List<&2, Lint.Declaration>
) -> List<&2, Lint.Declaration>:
  match hit:
    case True{}:
      ds
    case False{}:
      rest

def get_declarations_of(
  all: List<&2, Lint.SourceDeclarations>,
  +path: String
) -> List<&2, Lint.Declaration>:
  match all:
    case Nil{}:
      []
    case Con{s, t}:
      match s:
        case Lint.SourceDeclarations{p, ds}:
          get_declarations_of.pick(String.eq(p, path), ds, get_declarations_of(t, path))

def get_any_fills(ds: List<&2, Lint.Declaration>) -> Bool:
  match ds:
    case Nil{}:
      False{}
    case Con{d, rest}:
      match d:
        case Lint.Declaration{name, span, references, Lint.DefDeclaration{fills, written_type}}:
          fills || get_any_fills(rest)
        case _:
          get_any_fills(rest)

def get_queued(skip: Bool, p: String, todo: List<&2, String>) -> List<&2, String>:
  match skip:
    case True{}:
      todo
    case False{}:
      p <> todo

def get_loaded(
  ds: List<&2, Lint.Declaration>,
  +todo: List<&2, String>,
  +seen: List<&2, String>
) -> List<&2, String>:
  match ds:
    case Nil{}:
      todo
    case Con{d, rest}:
      match d:
        case Lint.Declaration{name, span, references, Lint.ImportDeclaration{+p}}:
          get_loaded(rest, get_queued(get_has(todo, p) || get_has(seen, p), p, todo), seen)
        case _:
          get_loaded(rest, todo, seen)

def get_step(
  +ds: List<&2, Lint.Declaration>,
  rest: List<&2, String>,
  +seen: List<&2, String>
) -> Walk:
  Walk{get_any_fills(ds), get_loaded(ds, rest, seen), seen}

def get_chain(fuel: Nat, w: Walk, +all: List<&2, Lint.SourceDeclarations>) -> Bool:
  match fuel w:
    case _ Walk{True{}, todo, seen}:
      True{}
    case 0n _:
      False{}
    case 1n+k Walk{False{}, Nil{}, seen}:
      False{}
    case 1n+k Walk{False{}, Con{+p, rest}, seen}:
      get_chain(k, get_step(get_declarations_of(all, p), rest, p <> seen), all)

def get_line_span.pick(
  inside: Bool,
  path: String,
  +at: U32,
  +next: U32,
  later: Lint.BendSourceSpan
) -> Lint.BendSourceSpan:
  match inside:
    case True{}:
      Lint.BendSourceSpan{path, at, next}
    case False{}:
      later

def get_line_span(
  lines: List<&2, String>,
  +at: U32,
  +beg: U32,
  +size: U32,
  +path: String
) -> Lint.BendSourceSpan:
  match lines:
    case Nil{}:
      Lint.BendSourceSpan{path, beg, beg}
    case Con{h, t}:
      +next = U32.min(U32.add(U32.add(at, U32.from_nat(String.length(h))), 1), size)
      get_line_span.pick(
        U32.is_lt(beg, next),
        path,
        at,
        next,
        get_line_span(t, next, beg, size, path)
      )

def get_unused(
  used: Bool,
  name: String,
  span: Lint.BendSourceSpan,
  line: Lint.BendSourceSpan
) -> List<&2, Lint.Finding>:
  match used:
    case True{}:
      []
    case False{}:
      [
        Lint.Finding{
          Lint.Warning{},
          "Remove the import " ++ name ++ ": nothing uses it.",
          span,
          [Lint.Fix{"Remove the import", Lint.Safe{}, [Lint.ReplaceText{line, ""}]}]
        }
      ]

def get_unused_imports(
  ds: List<&2, Lint.Declaration>,
  +all: List<&2, Lint.SourceDeclarations>,
  +fuel: Nat,
  +lines: List<&2, String>,
  +size: U32
) -> List<&2, Lint.Finding>:
  match ds:
    case Nil{}:
      []
    case Con{d, rest}:
      match d:
        case Lint.Declaration{
          name,
          Lint.BendSourceSpan{+path, +beg, end},
          Nil{},
          Lint.ImportDeclaration{p}
        }:
          List.append(
            &2,
            Lint.Finding,
            get_unused(
              get_chain(fuel, Walk{False{}, [p], []}, all),
              name,
              Lint.BendSourceSpan{path, beg, end},
              get_line_span(lines, 0, beg, size, path)
            ),
            get_unused_imports(rest, all, fuel, lines, size)
          )
        case _:
          get_unused_imports(rest, all, fuel, lines, size)

def run(input: Lint.RuleInput) -> List<&2, Lint.Finding>:
  match input:
    case Lint.RuleInput{root, sources, options, prior, +all}:
      match root:
        case Lint.BendSource{+path, text, +lines}:
          get_unused_imports(
            get_declarations_of(all, path),
            all,
            List.length(&2, Lint.BendSource, sources),
            lines,
            U32.from_nat(String.length(text))
          )

def rules() -> List<&1, Lint.Rule>:
  [Lint.Rule{"no-unused/imports", Lint.FileScope{}, [], [], [Lint.DeclarationsNeed{}], run}]
