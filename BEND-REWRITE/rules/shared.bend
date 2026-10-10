# Logic more than one rule uses. Not a rule: do not load it as one.
import Base
import ../main.bend as Lint

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

def get_head_size(lines: List<&2, String>) -> U32:
  match lines:
    case Nil{}:
      0
    case Con{h, t}:
      U32.from_nat(String.length(h))

def get_span_text.go(
  lines: List<&2, String>,
  inside: Bool,
  +at: U32,
  +beg: U32,
  +end: U32
) -> String:
  match lines inside:
    case Nil{} _:
      ""
    case Con{h, t} True{}:
      String.take(String.drop(h, U32.to_nat(U32.sub(beg, at))), U32.to_nat(U32.sub(end, beg)))
    case Con{h, +t} False{}:
      +next = U32.add(U32.add(at, U32.from_nat(String.length(h))), 1)
      get_span_text.go(
        t,
        U32.is_lt(beg, U32.add(U32.add(next, get_head_size(t)), 1)),
        next,
        beg,
        end
      )

def get_span_text(+lines: List<&2, String>, span: Lint.BendSourceSpan) -> String:
  match span:
    case Lint.BendSourceSpan{path, +beg, end}:
      get_span_text.go(lines, U32.is_lt(beg, U32.add(get_head_size(lines), 1)), 0, beg, end)
