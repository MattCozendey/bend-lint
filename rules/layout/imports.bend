# layout/imports: the import block. import Base comes first, then the other
# imports by written path, then by alias, compared by code point. Each file
# is imported once. The fix rewrites the block: a comment line moves with
# the import below it, blank lines go, and a duplicate's uses are renamed to
# the alias that stays.
# Run: bun src/lint.ts file.bend --rules rules/layout/imports.bend --fix
import Base
import ../../src/bend/lint.bend as Lint
import ../shared.bend as Shared

# Types
# =====

# One import: whether it is Base, its written path, its alias, the file it
# loads, its text (the comment lines above it, then its line), and the uses
# of its alias.
type Entry is Data:
  Entry{
    base: Bool,
    path: String,
    alias: String,
    loads: String,
    text: String,
    refs: List<&2, Lint.Reference>
  }

# The block, as found: where it starts and ends, and its imports, last
# first.
type Block is Data:
  Block{beg: U32, end: U32, entries: List<&2, Entry>}

# The imports to keep, last first; the renames of the duplicates' uses; and
# whether every use could be renamed.
type Kept is Data:
  Kept{entries: List<&2, Entry>, edits: List<&2, Lint.Edit>, ok: Bool}

# Text
# ====
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

# The comment lines of `s`, a run of whole lines, each with its newline;
# blank lines dropped. `line` is the current line, last character first.
def comments(s: String, line: String, acc: String) -> String:
  match s:
    case SNil{}:
      acc ++ kept_line(String.reverse(line))
    case SCon{'\n', rest}:
      comments(rest, "", acc ++ kept_line(String.reverse(line)))
    case SCon{c, rest}:
      comments(rest, SCon{c, line}, acc)

# Block
# =====

# `s`, ending with a newline.
def ended(+s: String) -> String:
  Bool.pick(String, String.ends_with(s, "\n"), s, s ++ "\n")

def line_beg(line: Lint.Span) -> U32:
  match line:
    case Lint.Span{path, beg, end}:
      beg

def line_end(line: Lint.Span) -> U32:
  match line:
    case Lint.Span{path, beg, end}:
      end

# The import on `line`, with the comment lines from `from` to it.
def entry(
  +text: String,
  from: U32,
  +line: Lint.Span,
  alias: String,
  refs: List<&2, Lint.Reference>,
  loads: String
) -> Entry:
  match line:
    case Lint.Span{path, +beg, +end}:
      +written = Shared.word(Shared.after_import(slice(text, beg, end)))
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
  +line: Lint.Span,
  alias: String,
  refs: List<&2, Lint.Reference>,
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
    case Con{Lint.Declaration{Lint.Import{}, name, owner, span, refs, Some{loads}, fills, term}, rest}:
      block(rest, text, add(text, Shared.line_of(text, span), name, refs, loads, b))
    case Con{d, rest}:
      block(rest, text, b)

# Duplicates
# ==========
def loads_of(e: Entry) -> String:
  match e:
    case Entry{base, path, alias, loads, text, refs}:
      loads

# The alias of the kept import that loads `loads`, if there is one.
def alias_of(es: List<&2, Entry>, +loads: String) -> Maybe<&2, String>:
  match es:
    case Nil{}:
      None{}
    case Con{Entry{base, path, +alias, l, text, refs}, rest}:
      Bool.pick(Maybe<&2, String>, String.eq(l, loads), Some{alias}, alias_of(rest, loads))

# The edit that renames one use of `from` to `to`, if its text starts with
# "from.".
def rename(+text: String, +from: String, +to: String, r: Lint.Reference) -> Maybe<&2, Lint.Edit>:
  match r:
    case Lint.Reference{owner, Lint.Span{path, +beg, end}}:
      Bool.pick(
        Maybe<&2, Lint.Edit>,
        String.starts_with(slice(text, beg, end), from ++ "."),
        Some{Lint.Edit{Lint.Span{path, beg, U32.add(beg, U32.from_nat(String.length(from)))}, to}},
        None{}
      )

def renamed(m: Maybe<&2, Lint.Edit>, k: Kept) -> Kept:
  match m k:
    case Some{e} Kept{es, edits, ok}:
      Kept{es, Con{e, edits}, ok}
    case None{} Kept{es, edits, ok}:
      Kept{es, edits, False{}}

def renames(
  rs: List<&2, Lint.Reference>,
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

# Keeps `e`, or, when an import kept already loads its file, drops it and
# renames its uses (Base has no alias to rename).
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

# Order
# =====

# Whether `a` may come before `b`: Base first, then by path, then by alias.
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

# Rule
# ====
def message() -> String:
  "Order the imports: import Base first, then by path and alias, each file once."

def verdict(
  same: Bool,
  ok: Bool,
  +out: String,
  edits: List<&2, Lint.Edit>,
  +span: Lint.Span
) -> List<&2, Lint.Diag>:
  match same ok:
    case True{} _:
      []
    case False{} True{}:
      [
        Lint.Diag{
          Lint.Warning{},
          message(),
          Some{span},
          [Lint.Fix{"Order the imports", Lint.Safe{}, Con{Lint.Edit{span, out}, edits}}],
          None{}
        }
      ]
    case False{} False{}:
      [
        Lint.diag(
          Lint.Warning{},
          message()
            ++ " No fix was offered: a duplicate's alias has a use this rule cannot rename.",
          span
        )
      ]

def judged(+out: String, old: String, k: Kept, +span: Lint.Span) -> List<&2, Lint.Diag>:
  match k:
    case Kept{es, +edits, ok}:
      verdict(
        Bool.and(String.eq(out, old), List.is_empty(&2, Lint.Edit, edits)),
        ok,
        out,
        edits,
        span
      )

def judge(+path: String, +text: String, b: Block) -> List<&2, Lint.Diag>:
  match b:
    case Block{beg, end, Nil{}}:
      []
    case Block{+beg, +end, Con{e, es}}:
      +k = dedupe(List.reverse(&2, Entry, Con{e, es}), text, Kept{[], [], True{}})
      judged(
        texts(List.sort(~Entry, ~before, List.reverse(&2, Entry, kept_of(k))), ""),
        slice(text, beg, end),
        k,
        Lint.Span{path, beg, end}
      )

def id() -> String:
  "layout/imports"

def facts() -> Lint.Want:
  Lint.NoFacts{}

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  match input:
    case Lint.Input{root, sources, options, prior}:
      match root:
        case Lint.Source{+path, +text, is_root}:
          IO.bind(
            List<&2, Lint.Declaration>,
            List<&2, Lint.Diag>,
            Lint.declarations(),
            ds => IO.pure(List<&2, Lint.Diag>, judge(path, text, block(ds, text, Block{0, 0, []})))
          )

def main() -> IO(Unit):
  Lint.serve(run)
