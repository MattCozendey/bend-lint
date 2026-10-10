# layout/imports: the import block. import Base comes first, then the other imports by written path, then by alias,
# compared by code point. Each file is imported once. The fix rewrites the block: a comment line moves with the import
# below it, blank lines go, and a duplicate's uses are renamed to the alias that stays. A fix's edits apply in order,
# each on the result before, so the renames, which sit below the block, go from the last to the first, and the block
# comes last.
import Base
import ../../main.bend as Lint
import ../shared.bend as Shared

type Entry is Data:
  Entry{
    base: Bool,
    path: String,
    alias: String,
    loads: String,
    text: String,
    refs: List<&2, Lint.DeclarationReference>
  }

type Block is Data:
  Block{beg: U32, end: U32, entries: List<&2, Entry>}

type Kept is Data:
  Kept{entries: List<&2, Entry>, edits: List<&2, Lint.FixEdit>, ok: Bool}

def slice(text: String, +beg: U32, end: U32) -> String:
  String.take(String.drop(text, U32.to_nat(beg)), U32.to_nat(U32.sub(end, beg)))

def blank(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{' ', rest}:
      blank(rest)
    case SCon{'\t', rest}:
      blank(rest)
    case SCon{'\r', rest}:
      blank(rest)
    case _:
      False{}

def kept_line(+line: String) -> String:
  Bool.pick(String, blank(line), "", line ++ "\n")

def comments(s: String, line: String, acc: String) -> String:
  match s:
    case SNil{}:
      acc ++ kept_line(String.reverse(line))
    case SCon{'\n', rest}:
      comments(rest, "", acc ++ kept_line(String.reverse(line)))
    case SCon{c, rest}:
      comments(rest, SCon{c, line}, acc)

def ended(+s: String) -> String:
  Bool.pick(String, String.ends_with(s, "\n"), s, s ++ "\n")

def line_beg(line: Lint.BendSourceSpan) -> U32:
  match line:
    case Lint.BendSourceSpan{path, beg, end}:
      beg

def line_end(line: Lint.BendSourceSpan) -> U32:
  match line:
    case Lint.BendSourceSpan{path, beg, end}:
      end

def entry(
  +text: String,
  from: U32,
  +line: Lint.BendSourceSpan,
  alias: String,
  refs: List<&2, Lint.DeclarationReference>,
  loads: String
) -> Entry:
  match line:
    case Lint.BendSourceSpan{path, +beg, +end}:
      +written = Shared.get_word(Shared.get_after_import(slice(text, beg, end)))
      Entry{
        String.eq(written, "Base"),
        written,
        alias,
        loads,
        comments(slice(text, from, beg), "", "") ++ ended(slice(text, beg, end)),
        refs
      }

def add(
  +text: String,
  +line: Lint.BendSourceSpan,
  alias: String,
  refs: List<&2, Lint.DeclarationReference>,
  loads: String,
  b: Block
) -> Block:
  match b:
    case Block{beg, end, Nil{}}:
      Block{line_beg(line), line_end(line), [entry(text, line_beg(line), line, alias, refs, loads)]}
    case Block{beg, end, Con{e, es}}:
      Block{beg, line_end(line), Con{entry(text, end, line, alias, refs, loads), Con{e, es}}}

def block(ds: List<&2, Lint.Declaration>, +text: String, b: Block) -> Block:
  match ds:
    case Nil{}:
      b
    case Con{d, rest}:
      match d:
        case Lint.Declaration{name, span, refs, Lint.ImportDeclaration{loads}}:
          block(rest, text, add(text, Shared.get_line_of(text, span), name, refs, loads, b))
        case _:
          block(rest, text, b)

def loads_of(e: Entry) -> String:
  match e:
    case Entry{base, path, alias, loads, text, refs}:
      loads

def alias_of(es: List<&2, Entry>, +loads: String) -> Maybe<&2, String>:
  match es:
    case Nil{}:
      None{}
    case Con{Entry{base, path, +alias, l, text, refs}, rest}:
      Bool.pick(Maybe<&2, String>, String.eq(l, loads), Some{alias}, alias_of(rest, loads))

def rename(
  +text: String,
  +from: String,
  +to: String,
  r: Lint.DeclarationReference
) -> Maybe<&2, Lint.FixEdit>:
  match r:
    case Lint.DeclarationReference{owner, Lint.BendSourceSpan{path, +beg, end}}:
      Bool.pick(
        Maybe<&2, Lint.FixEdit>,
        String.starts_with(slice(text, beg, end), from ++ "."),
        Some{
          Lint.ReplaceText{
            Lint.BendSourceSpan{path, beg, U32.add(beg, U32.from_nat(String.length(from)))},
            to
          }
        },
        None{}
      )

def renamed(m: Maybe<&2, Lint.FixEdit>, k: Kept) -> Kept:
  match m k:
    case Some{e} Kept{es, edits, ok}:
      Kept{es, Con{e, edits}, ok}
    case None{} Kept{es, edits, ok}:
      Kept{es, edits, False{}}

def renames(
  rs: List<&2, Lint.DeclarationReference>,
  +text: String,
  +from: String,
  +to: String,
  k: Kept
) -> Kept:
  match rs:
    case Nil{}:
      k
    case Con{r, rest}:
      renames(rest, text, from, to, renamed(rename(text, from, to, r), k))

def keep(found: Maybe<&2, String>, +text: String, e: Entry, k: Kept) -> Kept:
  match found e k:
    case None{} e2 Kept{es, edits, ok}:
      Kept{Con{e2, es}, edits, ok}
    case Some{to} Entry{True{}, path, alias, loads, t, refs} k2:
      k2
    case Some{to} Entry{False{}, path, alias, loads, t, refs} k2:
      renames(refs, text, alias, to, k2)

def kept_of(k: Kept) -> List<&2, Entry>:
  match k:
    case Kept{es, edits, ok}:
      es

def dedupe(es: List<&2, Entry>, +text: String, +k: Kept) -> Kept:
  match es:
    case Nil{}:
      k
    case Con{+e, rest}:
      dedupe(rest, text, keep(alias_of(kept_of(k), loads_of(e)), text, e, k))

def before(a: Entry, b: Entry) -> Bool:
  match a b:
    case Entry{True{}, p, x, l, t, r} _:
      True{}
    case Entry{False{}, p, x, l, t, r} Entry{True{}, q, y, m, u, s}:
      False{}
    case Entry{False{}, +p, x, l, t, r} Entry{False{}, +q, y, m, u, s}:
      Bool.pick(Bool, String.eq(p, q), String.is_le(x, y), String.is_lt(p, q))

def texts(es: List<&2, Entry>, acc: String) -> String:
  match es:
    case Nil{}:
      acc
    case Con{Entry{base, path, alias, loads, text, refs}, rest}:
      texts(rest, acc ++ text)

def edit_beg(e: Lint.FixEdit) -> U32:
  match e:
    case Lint.ReplaceText{Lint.BendSourceSpan{path, beg, end}, text}:
      beg
    case _:
      0

def later(a: Lint.FixEdit, b: Lint.FixEdit) -> Bool:
  U32.is_lt(edit_beg(b), U32.add(edit_beg(a), 1))

def message() -> String:
  "Order the imports: import Base first, then by path and alias, each file once."

def verdict(
  same: Bool,
  ok: Bool,
  +out: String,
  edits: List<&2, Lint.FixEdit>,
  +span: Lint.BendSourceSpan
) -> List<&2, Lint.Finding>:
  match same ok:
    case True{} _:
      []
    case False{} True{}:
      [
        Lint.Finding{
          Lint.Warning{},
          message(),
          span,
          [
            Lint.Fix{
              "Order the imports",
              Lint.Safe{},
              List.append(
                &2,
                Lint.FixEdit,
                List.sort(~Lint.FixEdit, ~later, edits),
                [Lint.ReplaceText{span, out}]
              )
            }
          ]
        }
      ]
    case False{} False{}:
      [
        Lint.Finding{
          Lint.Warning{},
          message()
            ++ " No fix was offered: a duplicate's alias has a use this rule cannot rename.",
          span,
          []
        }
      ]

def judged(
  +out: String,
  old: String,
  k: Kept,
  +span: Lint.BendSourceSpan
) -> List<&2, Lint.Finding>:
  match k:
    case Kept{es, +edits, ok}:
      verdict(
        Bool.and(String.eq(out, old), List.is_empty(&2, Lint.FixEdit, edits)),
        ok,
        out,
        edits,
        span
      )

def judge(+path: String, +text: String, b: Block) -> List<&2, Lint.Finding>:
  match b:
    case Block{beg, end, Nil{}}:
      []
    case Block{+beg, +end, Con{e, es}}:
      +k = dedupe(List.reverse(&2, Entry, Con{e, es}), text, Kept{[], [], True{}})
      judged(
        texts(List.sort(~Entry, ~before, List.reverse(&2, Entry, kept_of(k))), ""),
        slice(text, beg, end),
        k,
        Lint.BendSourceSpan{path, beg, end}
      )

def lint(input: Lint.RuleInput) -> List<&2, Lint.Finding>:
  match input:
    case Lint.RuleInput{root, sources, options, prior, declarations}:
      match root:
        case Lint.BendSource{+path, +text, lines}:
          judge(
            path,
            text,
            block(Shared.get_declarations_of(declarations, path), text, Block{0, 0, []})
          )

def run(input: Lint.RuleInput) -> Lint.RuleStep:
  Lint.RuleDone{lint(input)}

def rules() -> List<&1, Lint.Rule>:
  [Lint.Rule{"layout/imports", Lint.FileScope{}, [], [], [Lint.DeclarationsNeed{}], run}]
