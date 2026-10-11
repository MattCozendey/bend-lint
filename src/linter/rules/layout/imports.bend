# layout/imports: an import block out of order, with a file imported twice, or with blank lines. The
# order: import Base, then the other imports by written path, then by alias, by code point; a comment
# line stays with the import below it.
# Fix: writes the block in order, drops a second import of a file, and points its uses at the first
# one's alias (--fix-dangerously).
# Heuristics: two imports name one file if the check loads one file for both.
import Base
import ../../lint.bend as Lint
import ../../shared.bend as Shared

# Types
# =====

# One import: its node's id, whether it is Base, its written path, its alias, the file it loads, and its text (the
# comment lines above it, then its line).
type Entry is Data:
  Entry{id: U32, base: Bool, path: String, alias: String, loads: String, text: String}

# The imports read so far, each file's first only: the files they load, each with its alias; the imports kept (last
# first); and the operations that point a dropped import's uses at the kept one's alias.
type Deduped is Data:
  Deduped{
    seen: List<&2, Shared.Named<String>>,
    kept: List<&2, Entry>,
    renames: List<&2, Lint.Operation>
  }

# The block, as written: where it starts and ends, and its imports, last first.
type Block is Data:
  Block{beg: U32, end: U32, entries: List<&2, Entry>}

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

def kept(+line: String) -> String:
  Bool.pick(String, blank(line), "", line ++ "\n")

# The comment lines of `s`, a run of whole lines, each with its newline; blank lines dropped. `line` is the current
# line, last character first; `acc` the lines so far, last first.
def comments(s: String, line: String, acc: List<&2, String>) -> String:
  match s:
    case SNil{}:
      Shared.joined(kept(String.reverse(line)) <> acc, "")
    case SCon{'\n', rest}:
      comments(rest, "", kept(String.reverse(line)) <> acc)
    case SCon{c, rest}:
      comments(rest, SCon{c, line}, acc)

# `s`, ending with a newline.
def ended(+s: String) -> String:
  Bool.pick(String, String.ends_with(s, "\n"), s, s ++ "\n")

# Block
# =====

# The import on the line from `beg` to `end`, after the block so far.
def add.line(
  +text: String,
  +beg: U32,
  +end: U32,
  id: U32,
  base: Bool,
  path: String,
  alias: String,
  loads: String,
  b: Block
) -> Block:
  match b:
    case Block{first, last, Nil{}}:
      Block{beg, end, [Entry{id, base, path, alias, loads, ended(slice(text, beg, end))}]}
    case Block{first, last, +entries}:
      Block{
        first,
        end,
        Entry{
          id,
          base,
          path,
          alias,
          loads,
          comments(slice(text, last, beg), "", []) ++ ended(slice(text, beg, end))
        }
          <> entries
      }

# The import of the node `id`, whose name is at `at`, after the block so far.
def add(
  +text: String,
  +at: U32,
  id: U32,
  base: Bool,
  path: String,
  alias: String,
  loads: String,
  b: Block
) -> Block:
  +beg = Shared.line_start(text, at)
  add.line(text, beg, Shared.line_end(text, beg), id, base, path, alias, loads, b)

# The block of the imports among `nodes`. A file's imports come first, so the first node of another kind ends them.
def block(nodes: List<&2, Lint.Node>, +text: String, b: Block) -> Block:
  match nodes:
    case Con{
      Lint.Node{i, p, o, Lint.Import{}, alias, n, q, Some{Lint.Span{f, beg, end}}, loads},
      Con{Lint.Node{i2, p2, o2, Lint.ImportPath{}, path, n2, q2, s2, t2}, rest}
    }:
      block(rest, text, add(text, beg, i, False{}, path, alias, loads, b))
    case Con{
      Lint.Node{i, p, o, Lint.Import{}, alias, n, q, Some{Lint.Span{f, beg, end}}, loads},
      rest
    }:
      block(rest, text, add(text, beg, i, True{}, "Base", alias, loads, b))
    case _:
      b

# Duplicates and order
# ====================
def loads_of(e: Entry) -> String:
  match e:
    case Entry{id, base, path, alias, loads, text}:
      loads

# An import read, after those before it: kept, if its file has no import yet; else dropped, with its uses pointed at
# `first`, the alias of the file's first import. A second import Base has none to point: its uses are bare names.
def dedupe.kept(first: Maybe<&2, String>, e: Entry, d: Deduped) -> Deduped:
  match first e d:
    case None{} Entry{id, base, path, +alias, +loads, text} Deduped{seen, kept, renames}:
      Deduped{
        Shared.Named{loads, alias} <> seen,
        Entry{id, base, path, alias, loads, text} <> kept,
        renames
      }
    case Some{a} Entry{id, False{}, path, alias, loads, text} Deduped{seen, kept, renames}:
      Deduped{seen, kept, Lint.RenameUses{id, a} <> renames}
    case Some{a} Entry{id, True{}, path, alias, loads, text} _:
      d

def dedupe.add(+e: Entry, d: Deduped) -> Deduped:
  match d:
    case Deduped{+seen, kept, renames}:
      dedupe.kept(Shared.lookup(String, loads_of(e), seen), e, Deduped{seen, kept, renames})

# The imports of `es`, in order, after those of `d`, each file's first only.
def dedupe(es: List<&2, Entry>, d: Deduped) -> Deduped:
  match es:
    case Nil{}:
      d
    case Con{e, rest}:
      dedupe(rest, dedupe.add(e, d))

# Whether `a` may come before `b`: Base first, then by path, then by alias.
def before(a: Entry, b: Entry) -> Bool:
  match a b:
    case Entry{i, True{}, p, x, l, t} _:
      True{}
    case Entry{i, False{}, p, x, l, t} Entry{j, True{}, q, y, m, u}:
      False{}
    case Entry{i, False{}, +p, x, l, t} Entry{j, False{}, +q, y, m, u}:
      Bool.pick(Bool, String.eq(p, q), String.is_le(x, y), String.is_lt(p, q))

# The texts of `es`, after `acc`, the texts so far, last first.
def texts(es: List<&2, Entry>, acc: List<&2, String>) -> String:
  match es:
    case Nil{}:
      Shared.joined(acc, "")
    case Con{Entry{id, base, path, alias, loads, text}, rest}:
      texts(rest, text <> acc)

# Rule
# ====
def verdict(
  same: Bool,
  +span: Lint.Span,
  ordered: String,
  renames: List<&2, Lint.Operation>
) -> List<&2, Lint.Finding>:
  match same:
    case True{}:
      []
    case False{}:
      [
        Lint.Finding{
          Lint.Warning{},
          span,
          "Order the imports: import Base first, then by path and alias, each file once.",
          [Lint.Fix{"Order the imports", Lint.Replace{span, ordered} <> renames}]
        }
      ]

# The block as written (`written`, at `span`), against its imports in order, each file once.
def judged(+span: Lint.Span, written: String, d: Deduped) -> List<&2, Lint.Finding>:
  match d:
    case Deduped{seen, kept, renames}:
      +ordered = texts(Shared.sort(~Entry, ~before, List.reverse(&2, Entry, kept)), [])
      verdict(String.eq(ordered, written), span, ordered, renames)

def judge(+path: String, +text: String, b: Block) -> List<&2, Lint.Finding>:
  match b:
    case Block{beg, end, Nil{}}:
      []
    case Block{+beg, +end, entries}:
      judged(
        Lint.Span{path, beg, end},
        slice(text, beg, end),
        dedupe(List.reverse(&2, Entry, entries), Deduped{[], [], []})
      )

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(
    judge(
      Lint.Here.path(here),
      Lint.Here.text(here),
      block(Lint.Here.nodes(here), Lint.Here.text(here), Block{0, 0, []})
    )
  )

def rule() -> Lint.Rule:
  Lint.Rule{"layout/imports", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
