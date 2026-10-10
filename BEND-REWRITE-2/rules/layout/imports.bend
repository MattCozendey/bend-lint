# layout/imports: the import block. import Base comes first, then the other imports by written path, then by alias,
# compared by code point. Each file is imported once. A comment line stays with the import below it, and the block has
# no blank lines.
import Base
import ../../lint.bend as Lint
import ../../shared.bend as Shared

# Types
# =====

# One import: whether it is Base, its written path, its alias, the file it loads, and its text (the comment lines
# above it, then its line).
type Entry is Data:
  Entry{base: Bool, path: String, alias: String, loads: String, text: String}

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
# line, last character first.
def comments(s: String, line: String, acc: String) -> String:
  match s:
    case SNil{}:
      acc ++ kept(String.reverse(line))
    case SCon{'\n', rest}:
      comments(rest, "", acc ++ kept(String.reverse(line)))
    case SCon{c, rest}:
      comments(rest, SCon{c, line}, acc)

# `s`, ending with a newline.
def ended(+s: String) -> String:
  Bool.pick(String, String.ends_with(s, "\n"), s, s ++ "\n")

# Block
# =====

# The import on the line from `beg` to `end`, after the block so far.
def add.line(+text: String, +beg: U32, +end: U32, base: Bool, path: String, alias: String, loads: String, b: Block) -> Block:
  match b:
    case Block{first, last, Nil{}}:
      Block{beg, end, [Entry{base, path, alias, loads, ended(slice(text, beg, end))}]}
    case Block{first, last, +entries}:
      Block{first, end, Entry{base, path, alias, loads, comments(slice(text, last, beg), "", "") ++ ended(slice(text, beg, end))} <> entries}

# The import whose name is at `at`, after the block so far.
def add(+text: String, +at: U32, base: Bool, path: String, alias: String, loads: String, b: Block) -> Block:
  +beg = Shared.line_start(text, at)
  add.line(text, beg, Shared.line_end(text, beg), base, path, alias, loads, b)

# The block of the imports among `nodes`. A file's imports come first, so the first node of another kind ends them.
def block(nodes: List<&2, Lint.Node>, +text: String, b: Block) -> Block:
  match nodes:
    case Con{Lint.Node{i, p, o, Lint.Import{}, alias, n, q, Some{Lint.Span{f, beg, end}}, loads}, Con{Lint.Node{i2, p2, o2, Lint.ImportPath{}, path, n2, q2, s2, t2}, rest}}:
      block(rest, text, add(text, beg, False{}, path, alias, loads, b))
    case Con{Lint.Node{i, p, o, Lint.Import{}, alias, n, q, Some{Lint.Span{f, beg, end}}, loads}, rest}:
      block(rest, text, add(text, beg, True{}, "Base", alias, loads, b))
    case _:
      b

# Duplicates and order
# ====================

def loads_of(e: Entry) -> String:
  match e:
    case Entry{base, path, alias, loads, text}:
      loads

def keep(seen: Bool, e: Entry, out: List<&2, Entry>) -> List<&2, Entry>:
  match seen:
    case True{}:
      out
    case False{}:
      e <> out

# The imports, each file's first only, onto `out` (last first); `seen` holds the files kept.
def dedupe(es: List<&2, Entry>, +seen: List<&2, String>, out: List<&2, Entry>) -> List<&2, Entry>:
  match es:
    case Nil{}:
      out
    case Con{+e, rest}:
      +loads = loads_of(e)
      dedupe(rest, loads <> seen, keep(List.contains(~String, ~String.eq, seen, loads), e, out))

# Whether `a` may come before `b`: Base first, then by path, then by alias.
def before(a: Entry, b: Entry) -> Bool:
  match a b:
    case Entry{True{}, p, x, l, t} _:
      True{}
    case Entry{False{}, p, x, l, t} Entry{True{}, q, y, m, u}:
      False{}
    case Entry{False{}, +p, x, l, t} Entry{False{}, +q, y, m, u}:
      Bool.pick(Bool, String.eq(p, q), String.is_le(x, y), String.is_lt(p, q))

def texts(es: List<&2, Entry>, acc: String) -> String:
  match es:
    case Nil{}:
      acc
    case Con{Entry{base, path, alias, loads, text}, rest}:
      texts(rest, acc ++ text)

# Rule
# ====

# The fix that writes the block in order, if it drops no import: a dropped one's uses would need its alias renamed.
def reorders(whole: Bool, +span: Lint.Span, +text: String) -> List<&2, Lint.Fix>:
  match whole:
    case True{}:
      [Lint.Fix{"Order the imports", [Lint.Replace{span, text}]}]
    case False{}:
      []

def verdict(same: Bool, +span: Lint.Span, fixes: List<&2, Lint.Fix>) -> List<&2, Lint.Finding>:
  match same:
    case True{}:
      []
    case False{}:
      [Lint.Finding{Lint.Warning{}, span, "Order the imports: import Base first, then by path and alias, each file once.", fixes}]

def judged(+span: Lint.Span, written: String, entries: Nat, +kept: List<&2, Entry>) -> List<&2, Lint.Finding>:
  +ordered = texts(Shared.sort(~Entry, ~before, kept), "")
  verdict(
    String.eq(ordered, written),
    span,
    reorders(Nat.is_eq(entries, Shared.length(&2, Entry, kept)), span, ordered)
  )

def judge(+path: String, +text: String, b: Block) -> List<&2, Lint.Finding>:
  match b:
    case Block{beg, end, Nil{}}:
      []
    case Block{+beg, +end, +entries}:
      judged(
        Lint.Span{path, beg, end},
        slice(text, beg, end),
        Shared.length(&2, Entry, entries),
        List.reverse(&2, Entry, dedupe(List.reverse(&2, Entry, entries), [], []))
      )

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(judge(Lint.Here.path(here), Lint.Here.text(here), block(Lint.Here.nodes(here), Lint.Here.text(here), Block{0, 0, []})))

def rule() -> Lint.Rule:
  Lint.FileRule{"layout/imports", Lint.Needs{False{}}, [], run}
