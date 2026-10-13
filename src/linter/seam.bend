# The seam to Bend's checker, for as long as it is TS: all that knows Bend's own shapes, with seam.ts, which dumps what
# Bend's parser and checker made of a check's files. This file holds Bend's core as they give it (terms, patterns and
# bodies, with where the parser read them; the parser's calls that read the files; what the checker found), reads the
# dump into it, makes the linter's program of it (its nodes, then the checker's facts on them), and asks the checker its
# questions about types. When the checker is Bend, seam.ts goes, and the dump becomes calls to it. Names follow
# Lint.Syntax; fields, bend.ts's types.
# - A request is one connection: one line out, the answer in, then the server closes.
# - A line is fields split by a tab. A field escapes \, a tab and a newline as \\, \t and \n.
# - The answer is one line per record. Its first field is its kind.
# - A check's answer dumps what Bend made of the files (see `put` in seam.ts): its sections are tokens, in postfix.
import Base
import ../shared/lists.bend as Lists
import ../shared/names.bend as Names
import ../shared/strings.bend as Strings
import ../shared/tables.bend as Tables
import ./lint.bend as Lint
import ./program.bend as Program

# Terms
# =====

# Where the parser read something: its file's number in the check, and offsets, in UTF-16 units, in the text the
# parser read: the file's text with its import lines blank.
type Span is Data:
  Span{file: U32, beg: U32, end: U32}

# A term. A variable's value is a substitution's: the name of the reference it is, or "" for any other. A checked body
# has two more: the checker's annotation of a term it typed, with a handle to the type, and what the checker passed a
# judgment of a term.
type Term is Data:
  Variable{name: String, level: U32, value: Maybe<&2, String>, span: Maybe<&2, Span>}
  Reference{name: String, span: Maybe<&2, Span>}
  Substitution{level: U32, pattern: Pattern, body: Term, span: Maybe<&2, Span>}
  Let{
    names: List<&2, String>,
    levels: List<&2, U32>,
    quantities: List<&2, Lint.Quantity>,
    values: List<&2, Term>,
    body: Term,
    span: Maybe<&2, Span>
  }
  Sort{quantity: Term, span: Maybe<&2, Span>}
  QuantityType{span: Maybe<&2, Span>}
  QuantityLiteral{quantity: Lint.Quantity, span: Maybe<&2, Span>}
  QuantityMinimum{left: Term, right: Term, span: Maybe<&2, Span>}
  Forall{
    quantity: Lint.Quantity,
    name: String,
    level: U32,
    domain: Term,
    body: Term,
    span: Maybe<&2, Span>
  }
  Lambda{
    name: String,
    level: U32,
    body: Term,
    quantity: Maybe<&2, Lint.Quantity>,
    span: Maybe<&2, Span>
  }
  Application{function: Term, argument: Term, span: Maybe<&2, Span>}
  TypeApplication{name: String, arguments: List<&2, Term>, span: Maybe<&2, Span>}
  Construction{name: String, arguments: List<&2, Term>, span: Maybe<&2, Span>}
  Literal{kind: String, value: String, span: Maybe<&2, Span>}
  Elimination{name: String, hit: Term, miss: Term, span: Maybe<&2, Span>}
  Absurd{span: Maybe<&2, Span>}
  Equality{left: Term, right: Term, carrier: Term, span: Maybe<&2, Span>}
  Reflexivity{span: Maybe<&2, Span>}
  Rewrite{proof: Term, motive: Term, body: Term, span: Maybe<&2, Span>}
  Hole{name: String, span: Maybe<&2, Span>}
  Annotation{term: Term, annotation: Term, span: Maybe<&2, Span>}
  Typed{term: Term, handle: U32}
  Judged{term: Term, judgment: Judgment}

# What the checker passed a judgment: the demand on the term, the scope it judged it in (its number in the check), and
# how often each binder it closed was used.
type Judgment is Data:
  Judgment{demand: Lint.Quantity, scope: U32, uses: List<&2, Use>}

# How often the binder at `level` was used.
type Use is Data:
  Use{level: U32, quantity: Lint.Quantity}

type Pattern is Data:
  PatternVariable{name: String, level: U32, quantity: Lint.Quantity, span: Maybe<&2, Span>}
  PatternConstructor{name: String, arguments: List<&2, Pattern>, span: Maybe<&2, Span>}

# A def's body, before it is lowered to a term: a match, a destructuring let, or a term.
type Body is Data:
  Match{scrutinees: List<&2, Term>, cases: List<&2, Case>, span: Maybe<&2, Span>}
  Destructure{
    patterns: List<&2, Pattern>,
    quantity: Lint.Quantity,
    values: List<&2, Term>,
    body: Body
  }
  Expression{term: Term}

type Case is Data:
  Case{patterns: List<&2, Pattern>, body: Body}

def Span.is_eq(a: Maybe<&2, Span>, b: Maybe<&2, Span>) -> Bool:
  match a b:
    case Some{Span{f, x, y}} Some{Span{g, z, w}}:
      U32.is_eq(f, g) && U32.is_eq(x, z) && U32.is_eq(y, w)
    case None{} None{}:
      True{}
    case _ _:
      False{}

# A term without the checker's annotations.
def Term.bare(u: Term) -> Term:
  match u:
    case Typed{t, h}:
      Term.bare(t)
    case Judged{t, j}:
      Term.bare(t)
    case _:
      u

def Term.span(t: Term) -> Maybe<&2, Span>:
  match t:
    case Variable{k, i, v, s}:
      s
    case Reference{k, s}:
      s
    case Substitution{i, p, b, s}:
      s
    case Let{ks, ls, qs, vs, b, s}:
      s
    case Sort{g, s}:
      s
    case QuantityType{s}:
      s
    case QuantityLiteral{q, s}:
      s
    case QuantityMinimum{a, b, s}:
      s
    case Forall{q, k, i, a, b, s}:
      s
    case Lambda{k, i, b, q, s}:
      s
    case Application{f, x, s}:
      s
    case TypeApplication{k, xs, s}:
      s
    case Construction{k, xs, s}:
      s
    case Literal{k, v, s}:
      s
    case Elimination{k, h, m, s}:
      s
    case Absurd{s}:
      s
    case Equality{a, b, t, s}:
      s
    case Reflexivity{s}:
      s
    case Rewrite{e, p, b, s}:
      s
    case Hole{k, s}:
      s
    case Annotation{x, t, s}:
      s
    case Typed{t, h}:
      None{}
    case Judged{t, j}:
      None{}

# Whether `t` is an application at `span`.
def Term.at(t: Term, span: Maybe<&2, Span>) -> Bool:
  match t:
    case Application{f, x, s}:
      Span.is_eq(s, span)
    case _:
      False{}

# A call's head (as checked) and arguments, onto `args`: the applications at `span` are one call (`f(a, b)`, `a + b`),
# the outermost first. `head` is `typed` without the checker's annotations, and `same` says whether it is one of
# them. `fuel` bounds the call's length.
def Term.spine(
  fuel: Nat,
  head: Term,
  typed: Term,
  +span: Maybe<&2, Span>,
  args: List<&2, Term>,
  same: Bool
) -> Term
  & List<&2, Term>:
  match fuel head same:
    case 1n+k Application{+f, x, s} True{}:
      Term.spine(k, Term.bare(f), f, span, x <> args, Term.at(Term.bare(f), span))
    case _ _ _:
      (typed, args)

# Parsing
# =======

# A binder of a telescope: its quantity, name, level, type and span.
type Cell is Data:
  Cell{quantity: Lint.Quantity, name: String, level: U32, annotation: Term, span: Span}

# A call of the parser's that a check keeps (see KEPT in seam.ts), with the calls it made that it keeps:
# - Load: a file's load: the path it loads, and where its import is written, if it is.
# - Book: a file's declarations parsed: the text it parsed, its namespace, and its import aliases, in order.
# - Declare: a def's (its parser's file).
# - Head: a declared name read: its parser's file, the name as written, whether it names a constructor, the name the
#   check gives it, and where the parser is after it.
# - Tele: a telescope (its closing bracket, and the binders that take `~`), Parsed a term, ParsedBody a body, and
#   Higher a term Bend builds (a law's type).
# - Broken: a call that failed, from its parser's file, if any.
type Frame is Data:
  Load{path: String, at: Maybe<&2, Span>, kids: List<&2, Frame>}
  Book{text: String, namespace: String, aliases: List<&2, String>, kids: List<&2, Frame>}
  Declare{file: Maybe<&2, U32>, kids: List<&2, Frame>}
  Head{file: U32, written: String, is_constructor: Bool, name: String, end: U32}
  Tele{close: String, templates: List<&2, String>, cells: List<&2, Cell>}
  Parsed{term: Term}
  ParsedBody{body: Body}
  Higher{term: Term}
  Broken{file: Maybe<&2, U32>}

# Checking
# ========

# A binder of a declaration's type, as the checker opens the type: its name, quantity and span, its type's handle,
# the scope it is in, and its entry in the scope of what follows it.
type Domain is Data:
  Domain{
    name: String,
    quantity: Lint.Quantity,
    span: Maybe<&2, Span>,
    handle: U32,
    scope: U32,
    entry: Maybe<&2, U32>
  }

# A global name the check's files declare, and whether it names a datatype; for facts, the binders of its type and of
# each of its constructors' types, and its checked body.
type Declared is Data:
  Declared{
    name: String,
    datatype: Bool,
    binders: List<&2, Domain>,
    constructors: List<&2, List<&2, Domain>>,
    body: Maybe<&2, Term>
  }

# A binder's entry in the checker's context: its quantity, and its type's handle.
type Entry is Data:
  Entry{quantity: Lint.Quantity, handle: U32}

# A file the parser read: the text it read, and its namespace.
type ReadFile is Data:
  ReadFile{text: String, namespace: String}

# What a check gives: Base's path, the parser's calls, the declarations, each scope (an entry, if any, by level), each
# entry, and each file, by number.
type Checked is Data:
  Checked{
    base: String,
    frames: List<&2, Frame>,
    declared: List<&2, Declared>,
    scopes: Tables.Indexed<List<&2, Maybe<&2, U32>>>,
    entries: Tables.Indexed<Entry>,
    files: Tables.Indexed<ReadFile>
  }

# Values by the span they are at: those at one start, by file and end.
type Spot<-A: Data> is Data:
  Spot{file: U32, end: U32, values: List<&2, A>}

# Whether the first of `spots` is at the file `file` and end `end`.
def Spot.at(-A: Data, spots: List<&2, Spot<A>>, file: U32, end: U32) -> Bool:
  match spots:
    case Con{Spot{f, e, values}, rest}:
      U32.is_eq(f, file) && U32.is_eq(e, end)
    case Nil{}:
      False{}

# The values at `file` and `end` among `spots`, the last added first: `hit` says whether the first is there.
def Spot.values(
  -A: Data,
  spots: List<&2, Spot<A>>,
  +file: U32,
  +end: U32,
  hit: Bool
) -> List<&2, A>:
  match spots hit:
    case Con{Spot{f, e, values}, rest} True{}:
      values
    case Con{s, +rest} False{}:
      Spot.values(A, rest, file, end, Spot.at(A, rest, file, end))
    case _ _:
      []

def Spot.add(
  -A: Data,
  spots: List<&2, Spot<A>>,
  +file: U32,
  +end: U32,
  x: A,
  hit: Bool
) -> List<&2, Spot<A>>:
  match spots hit:
    case Con{Spot{f, e, values}, rest} True{}:
      Spot{f, e, x <> values} <> rest
    case Con{s, +rest} False{}:
      s <> Spot.add(A, rest, file, end, x, Spot.at(A, rest, file, end))
    case _ _:
      [Spot{file, end, [x]}]

def Spots.at(-A: Data, spots: Maybe<&2, List<&2, Spot<A>>>) -> List<&2, Spot<A>>:
  Maybe.default(&2, List<&2, Spot<A>>, spots, [])

def Spots.get.at(-A: Data, +spots: List<&2, Spot<A>>, +file: U32, +end: U32) -> List<&2, A>:
  List.reverse(&2, A, Spot.values(A, spots, file, end, Spot.at(A, spots, file, end)))

# The values at `span`, in the order added.
def Spots.get(-A: Data, t: Tables.Table<List<&2, Spot<A>>>, span: Span) -> List<&2, A>:
  match span:
    case Span{file, beg, end}:
      Spots.get.at(A, Spots.at(A, Tables.Table.read(List<&2, Spot<A>>, t, beg)), file, end)

def Spots.add.at(
  -A: Data,
  +spots: List<&2, Spot<A>>,
  +file: U32,
  +end: U32,
  x: A
) -> List<&2, Spot<A>>:
  Spot.add(A, spots, file, end, x, Spot.at(A, spots, file, end))

def Spots.put(
  -A: Data,
  +t: Tables.Table<List<&2, Spot<A>>>,
  +beg: U32,
  file: U32,
  end: U32,
  x: A
) -> Tables.Table<List<&2, Spot<A>>>:
  Tables.Table.set(
    List<&2, Spot<A>>,
    t,
    beg,
    Spots.add.at(A, Spots.at(A, Tables.Table.read(List<&2, Spot<A>>, t, beg)), file, end, x)
  )

# `t` with `x` at `span`.
def Spots.add(
  -A: Data,
  t: Tables.Table<List<&2, Spot<A>>>,
  span: Span,
  x: A
) -> Tables.Table<List<&2, Spot<A>>>:
  match span:
    case Span{file, beg, end}:
      Spots.put(A, t, beg, file, end, x)

type Mark is Data:
  Slash{}
  Tab{}
  Newline{}
  Plain{}

# An answer read so far: whether a \ came just before, the field, the record's fields and the records, each last
# first.
type Reading is Data:
  Reading{
    escaped: Bool,
    field: String,
    fields: List<&2, String>,
    records: List<&2, List<&2, String>>
  }

def mark(+c: Char) -> Mark:
  Bool.pick(
    Mark,
    Char.is_eq(c, '\\'),
    Slash{},
    Bool.pick(
      Mark,
      Char.is_eq(c, '\t'),
      Tab{},
      Bool.pick(Mark, Char.is_eq(c, '\n'), Newline{}, Plain{})
    )
  )

# A field's character with its escape undone: the character after a \.
def unescaped(+c: Char) -> Char:
  Bool.pick(Char, Char.is_eq(c, 'n'), '\n', Bool.pick(Char, Char.is_eq(c, 't'), '\t', c))

def read(mark: Mark, c: Char, r: Reading) -> Reading:
  match mark r:
    case _ Reading{True{}, field, fields, records}:
      Reading{False{}, SCon{unescaped(c), field}, fields, records}
    case Slash{} Reading{False{}, field, fields, records}:
      Reading{True{}, field, fields, records}
    case Tab{} Reading{False{}, field, fields, records}:
      Reading{False{}, "", String.reverse(field) <> fields, records}
    case Newline{} Reading{False{}, field, fields, records}:
      Reading{False{}, "", [], List.reverse(&2, String, String.reverse(field) <> fields) <> records}
    case Plain{} Reading{False{}, field, fields, records}:
      Reading{False{}, SCon{c, field}, fields, records}

def read_text(s: String, r: Reading) -> Reading:
  match s:
    case SNil{}:
      r
    case SCon{+c, t}:
      read_text(t, read(mark(c), c, r))

# The records of an answer's chunks, in order. A last record with no newline is dropped.
def records(chunks: List<&2, String>, r: Reading) -> List<&2, List<&2, String>>:
  match chunks r:
    case Nil{} Reading{escaped, field, fields, records}:
      List.reverse(&2, List<&2, String>, records)
    case Con{h, t} _:
      records(t, read_text(h, r))

# A character onto a field, escaped, onto `out`, which is last first.
def write(mark: Mark, c: Char, out: String) -> String:
  match mark:
    case Slash{}:
      SCon{'\\', SCon{'\\', out}}
    case Tab{}:
      SCon{'t', SCon{'\\', out}}
    case Newline{}:
      SCon{'n', SCon{'\\', out}}
    case Plain{}:
      SCon{c, out}

def field(s: String, out: String) -> String:
  match s:
    case SNil{}:
      out
    case SCon{+c, t}:
      field(t, write(mark(c), c, out))

# A request's line, from its fields; `out` is the line so far, last first.
def line(fields: List<&2, String>, out: String) -> String:
  match fields:
    case Nil{}:
      String.reverse(SCon{'\n', out})
    case Con{h, Nil{}}:
      String.reverse(SCon{'\n', field(h, out)})
    case Con{h, t}:
      line(t, SCon{'\t', field(h, out)})

# The chunks read until the server closes, last first, from the last read `step`. `fuel` bounds the reads.
def receive(
  fuel: Nat,
  step: Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>,
  got: List<&2, String>
) -> IO(List<&2, String>):
  match fuel step:
    case 1n+k Tuple{s, Done{Some{text}}}:
      IO.bind(
        Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>,
        List<&2, String>,
        TCP.recv(s, 65536),
        r => receive(k, r, text <> got)
      )
    case _ Tuple{s, Done{None{}}}:
      do IO<List<&2, String>>:
        Socket.close(s)
        return got
    case _ Tuple{s, Fail{Tuple{code, why}}}:
      do IO<List<&2, String>>:
        Socket.close(s)
        IO.die(List<&2, String>, 1, "bend-lint: reading the checker's answer failed: " ++ why)
    case 0n Tuple{s, Done{Some{text}}}:
      do IO<List<&2, String>>:
        Socket.close(s)
        IO.die(List<&2, String>, 1, "bend-lint: the checker's answer is too long")

def sent(r: Socket & Result<&1, &1, (U32 & String) & String, Unit>) -> IO(List<&2, String>):
  match r:
    case Tuple{s, Done{u}}:
      IO.bind(
        Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>,
        List<&2, String>,
        TCP.recv(s, 65536),
        step => receive(4294967295n, step, [])
      )
    case Tuple{s, Fail{Tuple{Tuple{code, why}, rest}}}:
      do IO<List<&2, String>>:
        Socket.close(s)
        IO.die(List<&2, String>, 1, "bend-lint: asking the checker failed: " ++ why)

def port.of(port: Maybe<&2, U32>) -> IO(U32):
  match port:
    case Some{p}:
      IO.pure(U32, p)
    case None{}:
      IO.die(
        U32,
        2,
        "bend-lint: BEND_LINT_PORT is not a port; run this program with `bend-lint --program <it>`"
      )

def port() -> IO(U32):
  do IO<U32>:
    text: String <- IO.try(String, IO.get_env("BEND_LINT_PORT"))
    port.of(U32.read(text))

def ask(request: List<&2, String>) -> IO(List<&2, List<&2, String>>):
  do IO<List<&2, List<&2, String>>>:
    p: U32 <- port()
    sock: Socket <- IO.try(Socket, TCP.connect("127.0.0.1", p))
    s: Socket & Result<&1, &1, (U32 & String) & String, Unit> <- TCP.send(sock, line(request, ""))
    got: List<&2, String> <- sent(s)
    return records(List.reverse(&2, String, got), Reading{False{}, "", [], []})

# Dumps
# =====

# What a dump's reader holds (see `put` in seam.ts): a value read whole, or the start of a list.
type Item is Data:
  IText{text: String}
  INumber{n: U32}
  INothing{}
  IOpen{}
  IList{items: List<&2, Item>}
  IFlag{on: Bool}
  ITable{constructors: Bool}
  IQuantity{quantity: Lint.Quantity}
  ISpan{span: Span}
  ITerm{term: Term}
  IPattern{pattern: Pattern}
  IBody{body: Body}
  IBranch{branch: Case}
  IFrame{frame: Frame}
  IDomain{domain: Domain}
  IDeclared{declared: Declared}

# What a dump's reader has read: its values (the last first), and the texts and spans it numbered so far, by number,
# with how many; or that the dump is malformed.
type Stack is Data:
  Stack{
    items: List<&2, Item>,
    texts: Tables.Table<String>,
    count: U32,
    spans: Tables.Table<Span>,
    spanned: U32
  }
  Malformed{}

def Item.text(i: Item) -> Maybe<&2, String>:
  match i:
    case IText{t}:
      Some{t}
    case _:
      None{}

def Item.number(i: Item) -> Maybe<&2, U32>:
  match i:
    case INumber{n}:
      Some{n}
    case _:
      None{}

def Item.span(i: Item) -> Maybe<&2, Span>:
  match i:
    case ISpan{s}:
      Some{s}
    case _:
      None{}

def Item.quantity(i: Item) -> Maybe<&2, Lint.Quantity>:
  match i:
    case IQuantity{q}:
      Some{q}
    case _:
      None{}

def Item.term(i: Item) -> Maybe<&2, Term>:
  match i:
    case ITerm{t}:
      Some{t}
    case _:
      None{}

def Item.pattern(i: Item) -> Maybe<&2, Pattern>:
  match i:
    case IPattern{p}:
      Some{p}
    case _:
      None{}

def Item.body(i: Item) -> Maybe<&2, Body>:
  match i:
    case IBody{b}:
      Some{b}
    case ITerm{t}:
      Some{Expression{t}}
    case _:
      None{}

def Item.branch(i: Item) -> Maybe<&2, Case>:
  match i:
    case IBranch{c}:
      Some{c}
    case _:
      None{}

def Item.frame(i: Item) -> Maybe<&2, Frame>:
  match i:
    case IFrame{f}:
      Some{f}
    case _:
      None{}

def Item.domain(i: Item) -> Maybe<&2, Domain>:
  match i:
    case IDomain{d}:
      Some{d}
    case _:
      None{}

def Item.declared(i: Item) -> Maybe<&2, Declared>:
  match i:
    case IDeclared{d}:
      Some{d}
    case _:
      None{}

# A level of a scope: an entry's number, or none.
def Item.level(i: Item) -> Maybe<&2, Maybe<&2, U32>>:
  match i:
    case INumber{n}:
      Some{Some{n}}
    case INothing{}:
      Some{None{}}
    case _:
      None{}

def Item.use(i: Item) -> Maybe<&2, Use>:
  match i:
    case IList{Con{INumber{l}, Con{IQuantity{q}, Nil{}}}}:
      Some{Use{l, q}}
    case _:
      None{}

def Item.cell(i: Item) -> Maybe<&2, Cell>:
  match i:
    case IList{
      Con{IQuantity{q}, Con{IText{k}, Con{INumber{l}, Con{ITerm{t}, Con{ISpan{s}, Nil{}}}}}}
    }:
      Some{Cell{q, k, l, t, s}}
    case _:
      None{}

def Item.entry(i: Item) -> Maybe<&2, Entry>:
  match i:
    case IList{Con{IQuantity{q}, Con{INumber{h}, Nil{}}}}:
      Some{Entry{q, h}}
    case _:
      None{}

def Item.file(i: Item) -> Maybe<&2, ReadFile>:
  match i:
    case IList{Con{IText{t}, Con{IText{ns}, Nil{}}}}:
      Some{ReadFile{t, ns}}
    case _:
      None{}

def Items.push(-A: Data, x: Maybe<&2, A>, out: List<&2, A>) -> Maybe<&2, List<&2, A>>:
  match x:
    case Some{v}:
      Some{v <> out}
    case None{}:
      None{}

# Each of `items` as `f` reads it, if it reads each, onto `out` (last first).
def Items.all(
  ~A: Data,
  ~f: Item -> Maybe<&2, A>,
  items: List<&2, Item>,
  out: Maybe<&2, List<&2, A>>
) -> Maybe<&2, List<&2, A>>:
  match items out:
    case _ None{}:
      None{}
    case Nil{} Some{o}:
      Some{List.reverse(&2, A, o)}
    case Con{i, rest} Some{o}:
      Items.all(~A, ~f, rest, Items.push(A, f(i), o))

# A list of values as `f` reads each.
def Items.of(~A: Data, ~f: Item -> Maybe<&2, A>, i: Item) -> Maybe<&2, List<&2, A>>:
  match i:
    case IList{items}:
      Items.all(~A, ~f, items, Some{[]})
    case _:
      None{}

# A literal's value as written: a text, or a number.
def Item.literal(i: Item) -> Maybe<&2, String>:
  match i:
    case IText{t}:
      Some{t}
    case INumber{n}:
      Some{U32.show(n)}
    case _:
      None{}

def Frame.constructors(table: Item) -> Bool:
  match table:
    case ITable{c}:
      c
    case _:
      False{}

def Frame.tele(
  close: String,
  templates: List<&2, String>,
  cells: Maybe<&2, List<&2, Cell>>
) -> Frame:
  match cells:
    case Some{cs}:
      Tele{close, templates, cs}
    case None{}:
      Broken{None{}}

def Frame.names() -> List<&2, Names.Named<U32>>:
  [
    Names.Named{"book_load", 0},
    Names.Named{"parse_book", 1},
    Names.Named{"parse_def", 2},
    Names.Named{"parse_fresh", 3},
    Names.Named{"parse_reso", 4},
    Names.Named{"parse_tele", 5},
    Names.Named{"parse_term", 6},
    Names.Named{"parse_body", 7},
    Names.Named{"term_higher", 8}
  ]

# What a kept call (see Frame) is, from its function's name, its parser's file, what seam.ts's FRAMES keeps of
# its arguments, its result, where the parser is after it, and the calls it kept.
def Frame.of(
  name: Maybe<&2, U32>,
  file: Maybe<&2, U32>,
  args: List<&2, Item>,
  out: Item,
  end: Maybe<&2, U32>,
  kids: List<&2, Frame>
) -> Frame:
  match name file args out end:
    case Some{0} _ Con{IText{path}, Con{at, Nil{}}} _ _:
      Load{path, Item.span(at), kids}
    case Some{1} _ Con{IText{text}, Con{IText{ns}, Con{IList{aliases}, Nil{}}}} _ _:
      Book{
        text,
        ns,
        Maybe.default(&2, List<&2, String>, Items.all(~String, ~Item.text, aliases, Some{[]}), []),
        kids
      }
    case Some{2} _ _ _ _:
      Declare{file, kids}
    case Some{3} Some{f} Con{IText{written}, Con{table, Nil{}}} IText{k} Some{e}:
      Head{f, written, Frame.constructors(table), k, e}
    case Some{4} Some{f} Con{IText{written}, Nil{}} IText{k} Some{e}:
      Head{f, written, False{}, k, e}
    case Some{5} _ Con{IText{close}, Con{templates, Nil{}}} IList{cells} _:
      Frame.tele(
        close,
        Maybe.default(&2, List<&2, String>, Items.of(~String, ~Item.text, templates), []),
        Items.all(~Cell, ~Item.cell, cells, Some{[]})
      )
    case Some{6} _ _ ITerm{t} _:
      Parsed{t}
    case Some{7} _ _ ITerm{t} _:
      ParsedBody{Expression{t}}
    case Some{7} _ _ IBody{b} _:
      ParsedBody{b}
    case Some{8} _ Con{ITerm{t}, Nil{}} _ _:
      Higher{t}
    case _ _ _ _ _:
      Broken{file}

def Maybe.list(-A: Data, xs: Maybe<&2, List<&2, A>>) -> List<&2, A>:
  Maybe.default(&2, List<&2, A>, xs, [])

def Declared.binders(i: Item) -> Maybe<&2, List<&2, Domain>>:
  Items.of(~Domain, ~Item.domain, i)

# What a declaration is, from its fields (see `putTlds` in seam.ts).
def Declared.of(
  name: String,
  kind: String,
  binders: Item,
  constructors: Item,
  body: Item
) -> Declared:
  Declared{
    name,
    String.eq(kind, "ADT"),
    Maybe.list(Domain, Items.of(~Domain, ~Item.domain, binders)),
    Maybe.list(List<&2, Domain>, Items.of(~List<&2, Domain>, ~Declared.binders, constructors)),
    Item.term(body)
  }

def Op.let(
  ks: Maybe<&2, List<&2, String>>,
  ls: Maybe<&2, List<&2, U32>>,
  qs: Maybe<&2, List<&2, Lint.Quantity>>,
  vs: Maybe<&2, List<&2, Term>>,
  f: Term,
  s: Maybe<&2, Span>,
  rest: List<&2, Item>
) -> Maybe<&2, List<&2, Item>>:
  match ks ls qs vs:
    case Some{k} Some{l} Some{q} Some{v}:
      Some{ITerm{Let{k, l, q, v, f, s}} <> rest}
    case _ _ _ _:
      None{}

def Op.terms(
  datatype: Bool,
  k: String,
  xs: Maybe<&2, List<&2, Term>>,
  s: Maybe<&2, Span>,
  rest: List<&2, Item>
) -> Maybe<&2, List<&2, Item>>:
  match datatype xs:
    case True{} Some{x}:
      Some{ITerm{TypeApplication{k, x, s}} <> rest}
    case False{} Some{x}:
      Some{ITerm{Construction{k, x, s}} <> rest}
    case _ _:
      None{}

def Op.literal(
  k: String,
  v: Maybe<&2, String>,
  s: Maybe<&2, Span>,
  rest: List<&2, Item>
) -> Maybe<&2, List<&2, Item>>:
  match v:
    case Some{text}:
      Some{ITerm{Literal{k, text, s}} <> rest}
    case None{}:
      None{}

def Op.patterns(
  k: String,
  xs: Maybe<&2, List<&2, Pattern>>,
  s: Maybe<&2, Span>,
  rest: List<&2, Item>
) -> Maybe<&2, List<&2, Item>>:
  match xs:
    case Some{x}:
      Some{IPattern{PatternConstructor{k, x, s}} <> rest}
    case None{}:
      None{}

def Op.match(
  es: Maybe<&2, List<&2, Term>>,
  cs: Maybe<&2, List<&2, Case>>,
  s: Maybe<&2, Span>,
  rest: List<&2, Item>
) -> Maybe<&2, List<&2, Item>>:
  match es cs:
    case Some{e} Some{c}:
      Some{IBody{Match{e, c, s}} <> rest}
    case _ _:
      None{}

def Op.local(
  ps: Maybe<&2, List<&2, Pattern>>,
  q: Lint.Quantity,
  vs: Maybe<&2, List<&2, Term>>,
  f: Maybe<&2, Body>,
  rest: List<&2, Item>
) -> Maybe<&2, List<&2, Item>>:
  match ps vs f:
    case Some{p} Some{v} Some{b}:
      Some{IBody{Destructure{p, q, v, b}} <> rest}
    case _ _ _:
      None{}

def Op.judged(
  x: Term,
  q: Lint.Quantity,
  scope: U32,
  uses: Maybe<&2, List<&2, Use>>,
  rest: List<&2, Item>
) -> Maybe<&2, List<&2, Item>>:
  match uses:
    case Some{u}:
      Some{ITerm{Judged{x, Judgment{q, scope, u}}} <> rest}
    case None{}:
      None{}

def Op.branch(
  ps: Maybe<&2, List<&2, Pattern>>,
  f: Maybe<&2, Body>,
  rest: List<&2, Item>
) -> Maybe<&2, List<&2, Item>>:
  match ps f:
    case Some{p} Some{b}:
      Some{IBranch{Case{p, b}} <> rest}
    case _ _:
      None{}

def Op.frame(
  name: Maybe<&2, U32>,
  file: Maybe<&2, U32>,
  args: List<&2, Item>,
  out: Item,
  end: Maybe<&2, U32>,
  kids: Maybe<&2, List<&2, Frame>>,
  rest: List<&2, Item>
) -> Maybe<&2, List<&2, Item>>:
  match kids:
    case Some{k}:
      Some{IFrame{Frame.of(name, file, args, out, end, k)} <> rest}
    case None{}:
      None{}

# The values after the tag `tag` (see TAGS in seam.ts) makes what it makes of those before it (the last first); none
# if they are not its fields.
def Op.apply(tag: Char, items: List<&2, Item>) -> Maybe<&2, List<&2, Item>>:
  match tag items:
    case 'v' Con{s, Con{v, Con{INumber{i}, Con{IText{k}, rest}}}}:
      Some{ITerm{Variable{k, i, Item.text(v), Item.span(s)}} <> rest}
    case 'r' Con{s, Con{IText{k}, rest}}:
      Some{ITerm{Reference{k, Item.span(s)}} <> rest}
    case 's' Con{s, Con{ITerm{f}, Con{IPattern{p}, Con{INumber{i}, rest}}}}:
      Some{ITerm{Substitution{i, p, f, Item.span(s)}} <> rest}
    case 'l' Con{s, Con{ITerm{f}, Con{vs, Con{qs, Con{ls, Con{ks, rest}}}}}}:
      Op.let(
        Items.of(~String, ~Item.text, ks),
        Items.of(~U32, ~Item.number, ls),
        Items.of(~Lint.Quantity, ~Item.quantity, qs),
        Items.of(~Term, ~Item.term, vs),
        f,
        Item.span(s),
        rest
      )
    case 't' Con{s, Con{ITerm{g}, rest}}:
      Some{ITerm{Sort{g, Item.span(s)}} <> rest}
    case 'q' Con{s, rest}:
      Some{ITerm{QuantityType{Item.span(s)}} <> rest}
    case 'Q' Con{s, Con{IQuantity{q}, rest}}:
      Some{ITerm{QuantityLiteral{q, Item.span(s)}} <> rest}
    case 'm' Con{s, Con{ITerm{b}, Con{ITerm{a}, rest}}}:
      Some{ITerm{QuantityMinimum{a, b, Item.span(s)}} <> rest}
    case 'a' Con{
      s,
      Con{ITerm{b}, Con{ITerm{a}, Con{INumber{i}, Con{IText{k}, Con{IQuantity{q}, rest}}}}}
    }:
      Some{ITerm{Forall{q, k, i, a, b, Item.span(s)}} <> rest}
    case 'L' Con{s, Con{q, Con{ITerm{f}, Con{INumber{i}, Con{IText{k}, rest}}}}}:
      Some{ITerm{Lambda{k, i, f, Item.quantity(q), Item.span(s)}} <> rest}
    case 'A' Con{s, Con{ITerm{x}, Con{ITerm{f}, rest}}}:
      Some{ITerm{Application{f, x, Item.span(s)}} <> rest}
    case 'D' Con{s, Con{xs, Con{IText{k}, rest}}}:
      Op.terms(True{}, k, Items.of(~Term, ~Item.term, xs), Item.span(s), rest)
    case 'c' Con{s, Con{xs, Con{IText{k}, rest}}}:
      Op.terms(False{}, k, Items.of(~Term, ~Item.term, xs), Item.span(s), rest)
    case 'i' Con{s, Con{v, Con{IText{k}, rest}}}:
      Op.literal(k, Item.literal(v), Item.span(s), rest)
    case 'M' Con{s, Con{ITerm{m}, Con{ITerm{h}, Con{IText{k}, rest}}}}:
      Some{ITerm{Elimination{k, h, m, Item.span(s)}} <> rest}
    case 'e' Con{s, rest}:
      Some{ITerm{Absurd{Item.span(s)}} <> rest}
    case 'E' Con{s, Con{ITerm{t}, Con{ITerm{b}, Con{ITerm{a}, rest}}}}:
      Some{ITerm{Equality{a, b, t, Item.span(s)}} <> rest}
    case 'R' Con{s, rest}:
      Some{ITerm{Reflexivity{Item.span(s)}} <> rest}
    case 'w' Con{s, Con{ITerm{f}, Con{ITerm{p}, Con{ITerm{e}, rest}}}}:
      Some{ITerm{Rewrite{e, p, f, Item.span(s)}} <> rest}
    case 'h' Con{s, Con{IText{k}, rest}}:
      Some{ITerm{Hole{k, Item.span(s)}} <> rest}
    case 'n' Con{s, Con{ITerm{t}, Con{ITerm{x}, rest}}}:
      Some{ITerm{Annotation{x, t, Item.span(s)}} <> rest}
    case 'p' Con{s, Con{IQuantity{q}, Con{INumber{i}, Con{IText{k}, rest}}}}:
      Some{IPattern{PatternVariable{k, i, q, Item.span(s)}} <> rest}
    case 'P' Con{s, Con{xs, Con{IText{k}, rest}}}:
      Op.patterns(k, Items.of(~Pattern, ~Item.pattern, xs), Item.span(s), rest)
    case 'x' Con{s, Con{cs, Con{es, rest}}}:
      Op.match(
        Items.of(~Term, ~Item.term, es),
        Items.of(~Case, ~Item.branch, cs),
        Item.span(s),
        rest
      )
    case 'X' Con{f, Con{vs, Con{IQuantity{q}, Con{ps, rest}}}}:
      Op.local(
        Items.of(~Pattern, ~Item.pattern, ps),
        q,
        Items.of(~Term, ~Item.term, vs),
        Item.body(f),
        rest
      )
    case 'N' _:
      Some{IQuantity{Lint.Erased{}} <> items}
    case 'O' _:
      Some{IQuantity{Lint.Once{}} <> items}
    case 'Y' _:
      Some{IQuantity{Lint.Many{}} <> items}
    case 'T' _:
      Some{IFlag{True{}} <> items}
    case 'F' _:
      Some{IFlag{False{}} <> items}
    case 'C' _:
      Some{ITable{True{}} <> items}
    case 'Z' _:
      Some{ITable{False{}} <> items}
    case 'y' Con{INumber{h}, Con{ITerm{x}, rest}}:
      Some{ITerm{Typed{x, h}} <> rest}
    case 'j' Con{used, Con{INumber{scope}, Con{IQuantity{q}, Con{ITerm{x}, rest}}}}:
      Op.judged(x, q, scope, Items.of(~Use, ~Item.use, used), rest)
    case 'k' Con{f, Con{ps, rest}}:
      Op.branch(Items.of(~Pattern, ~Item.pattern, ps), Item.body(f), rest)
    case 'f' Con{kids, Con{end, Con{out, Con{IList{args}, Con{file, Con{IText{name}, rest}}}}}}:
      Op.frame(
        Names.lookup(U32, name, Frame.names()),
        Item.number(file),
        args,
        out,
        Item.number(end),
        Items.of(~Frame, ~Item.frame, kids),
        rest
      )
    case 'd' Con{
      e,
      Con{INumber{scope}, Con{INumber{h}, Con{s, Con{IQuantity{q}, Con{IText{k}, rest}}}}}
    }:
      Some{IDomain{Domain{k, q, Item.span(s), h, scope, Item.number(e)}} <> rest}
    case 'g' Con{body, Con{constructors, Con{binders, Con{IText{kind}, Con{IText{name}, rest}}}}}:
      Some{IDeclared{Declared.of(name, kind, binders, constructors, body)} <> rest}
    case _ _:
      None{}

def Stack.push(item: Item, stack: Stack) -> Stack:
  match stack:
    case Stack{items, texts, count, spans, spanned}:
      Stack{item <> items, texts, count, spans, spanned}
    case Malformed{}:
      Malformed{}

def Stack.with(
  items: Maybe<&2, List<&2, Item>>,
  texts: Tables.Table<String>,
  count: U32,
  spans: Tables.Table<Span>,
  spanned: U32
) -> Stack:
  match items:
    case Some{i}:
      Stack{i, texts, count, spans, spanned}
    case None{}:
      Malformed{}

# The values up to the last start of a list, as that list (in order, onto `list`), in its place.
def Stack.list(items: List<&2, Item>, list: List<&2, Item>) -> Maybe<&2, List<&2, Item>>:
  match items:
    case Nil{}:
      None{}
    case Con{IOpen{}, rest}:
      Some{IList{list} <> rest}
    case Con{i, rest}:
      Stack.list(rest, i <> list)

def Stack.close(stack: Stack) -> Stack:
  match stack:
    case Stack{items, texts, count, spans, spanned}:
      Stack.with(Stack.list(items, []), texts, count, spans, spanned)
    case Malformed{}:
      Malformed{}

# A new text, numbered next.
def Stack.text(+text: String, stack: Stack) -> Stack:
  match stack:
    case Stack{items, texts, +count, spans, spanned}:
      Stack{
        IText{text} <> items,
        Tables.Table.set(String, texts, count, text),
        (count + 1: U32),
        spans,
        spanned
      }
    case Malformed{}:
      Malformed{}

def Stack.recalled(
  text: Maybe<&2, String>,
  items: List<&2, Item>,
  texts: Tables.Table<String>,
  count: U32,
  spans: Tables.Table<Span>,
  spanned: U32
) -> Stack:
  match text:
    case Some{t}:
      Stack{IText{t} <> items, texts, count, spans, spanned}
    case None{}:
      Malformed{}

# A text read before, by its number.
def Stack.recall(n: Maybe<&2, U32>, stack: Stack) -> Stack:
  match n stack:
    case Some{n} Stack{items, +texts, count, spans, spanned}:
      Stack.recalled(Tables.Table.read(String, texts, n), items, texts, count, spans, spanned)
    case _ _:
      Malformed{}

# A new span, numbered next.
def Stack.span(
  +span: Span,
  rest: List<&2, Item>,
  texts: Tables.Table<String>,
  count: U32,
  spans: Tables.Table<Span>,
  +spanned: U32
) -> Stack:
  Stack{
    ISpan{span} <> rest,
    texts,
    count,
    Tables.Table.set(Span, spans, spanned, span),
    (spanned + 1: U32)
  }

def Stack.respanned(
  span: Maybe<&2, Span>,
  items: List<&2, Item>,
  texts: Tables.Table<String>,
  count: U32,
  spans: Tables.Table<Span>,
  spanned: U32
) -> Stack:
  match span:
    case Some{s}:
      Stack{ISpan{s} <> items, texts, count, spans, spanned}
    case None{}:
      Malformed{}

# A span read before, by its number.
def Stack.respan(n: Maybe<&2, U32>, stack: Stack) -> Stack:
  match n stack:
    case Some{n} Stack{items, texts, count, +spans, spanned}:
      Stack.respanned(Tables.Table.read(Span, spans, n), items, texts, count, spans, spanned)
    case _ _:
      Malformed{}

def Stack.op(tag: Char, stack: Stack) -> Stack:
  match tag stack:
    case 'S' Stack{
      Con{INumber{e}, Con{INumber{b}, Con{INumber{f}, rest}}},
      texts,
      count,
      spans,
      spanned
    }:
      Stack.span(Span{f, b, e}, rest, texts, count, spans, spanned)
    case t Stack{items, texts, count, spans, spanned}:
      Stack.with(Op.apply(t, items), texts, count, spans, spanned)
    case _ _:
      Malformed{}

def Stack.number(n: Maybe<&2, U32>, stack: Stack) -> Stack:
  match n:
    case Some{n}:
      Stack.push(INumber{n}, stack)
    case None{}:
      Malformed{}

# A token of one character: a digit, or a tag.
def Token.one(digit: Bool, c: Char, stack: Stack) -> Stack:
  match digit:
    case True{}:
      Stack.number(U32.read(SCon{c, SNil{}}), stack)
    case False{}:
      Stack.op(c, stack)

# What a token of a dump makes of the stack (see `put` in seam.ts).
def Token.read(token: String, stack: Stack) -> Stack:
  match token:
    case SCon{'\'', text}:
      Stack.text(text, stack)
    case SCon{'@', n}:
      Stack.recall(U32.read(n), stack)
    case SCon{'#', n}:
      Stack.respan(U32.read(n), stack)
    case SCon{'[', SNil{}}:
      Stack.push(IOpen{}, stack)
    case SCon{'[', SCon{']', SNil{}}}:
      Stack.push(IList{[]}, stack)
    case SCon{']', SNil{}}:
      Stack.close(stack)
    case SCon{'_', SNil{}}:
      Stack.push(INothing{}, stack)
    case SCon{+c, SNil{}}:
      Token.one(Char.is_digit(c), c, stack)
    case _:
      Stack.number(U32.read(token), stack)

def Tokens.read(tokens: List<&2, String>, stack: Stack) -> Stack:
  match tokens:
    case Nil{}:
      stack
    case Con{t, rest}:
      Tokens.read(rest, Token.read(t, stack))

# Answers
# =======

# A record of a check's answer: its number, Base's path, the calls that loaded its files (`frames`, or `loading` if a
# load failed), a section of tokens (`tlds`, `scopes`, `entries` or `files`), a file it read, or why it failed.
type Section is Data:
  SCheck{}
  SBase{}
  SFrames{}
  SLoading{}
  STokens{}
  SRead{}
  SFail{}

def Section.names() -> List<&2, Names.Named<Section>>:
  [
    Names.Named{"check", SCheck{}},
    Names.Named{"base", SBase{}},
    Names.Named{"frames", SFrames{}},
    Names.Named{"loading", SLoading{}},
    Names.Named{"tlds", STokens{}},
    Names.Named{"scopes", STokens{}},
    Names.Named{"entries", STokens{}},
    Names.Named{"files", STokens{}},
    Names.Named{"read", SRead{}},
    Names.Named{"fail", SFail{}}
  ]

# A check's answer as read so far: its number, Base's path, whether it loaded its files, the files it read (last
# first), why it failed, and the reader's stack, which holds the value of each section of tokens (the last first).
type Dumped is Data:
  Dumped{
    check: Maybe<&2, U32>,
    base: String,
    loaded: Bool,
    read: List<&2, String>,
    fail: Maybe<&2, List<&2, String>>,
    stack: Stack
  }
  Unreadable{}

# The answer with a record of `section`, whose fields are `fields`, read.
def Dumped.add(section: Maybe<&2, Section>, fields: List<&2, String>, a: Dumped) -> Dumped:
  match section fields a:
    case Some{SCheck{}} Con{n, Nil{}} Dumped{c, base, loaded, read, fail, stack}:
      Dumped{U32.read(n), base, loaded, read, fail, stack}
    case Some{SBase{}} Con{path, Nil{}} Dumped{check, b, loaded, read, fail, stack}:
      Dumped{check, path, loaded, read, fail, stack}
    case Some{SRead{}} Con{path, Nil{}} Dumped{check, base, loaded, read, fail, stack}:
      Dumped{check, base, loaded, path <> read, fail, stack}
    case Some{SFail{}} _ Dumped{check, base, loaded, read, f, stack}:
      Dumped{check, base, loaded, read, Some{fields}, stack}
    case Some{SFrames{}} _ Dumped{check, base, l, read, fail, stack}:
      Dumped{check, base, True{}, read, fail, Tokens.read(fields, stack)}
    case Some{SLoading{}} _ Dumped{check, base, l, read, fail, stack}:
      Dumped{check, base, False{}, read, fail, Tokens.read(fields, stack)}
    case Some{STokens{}} _ Dumped{check, base, loaded, read, fail, stack}:
      Dumped{check, base, loaded, read, fail, Tokens.read(fields, stack)}
    case _ _ _:
      Unreadable{}

def Dumped.go(
  records: List<&2, List<&2, String>>,
  +sections: Map<&2, Maybe<&2, Section>>,
  a: Dumped
) -> Dumped:
  match records:
    case Nil{}:
      a
    case Con{Con{tag, fields}, rest}:
      Dumped.go(rest, sections, Dumped.add(Names.find(Section, sections, tag), fields, a))
    case Con{Nil{}, rest}:
      Unreadable{}

def Dumped.of(records: List<&2, List<&2, String>>) -> Dumped:
  Dumped.go(
    records,
    Names.table(Section, Section.names(), Map.new(&2, Maybe<&2, Section>)),
    Dumped{
      None{},
      "",
      False{},
      [],
      None{},
      Stack{[], Tables.TLeaf{None{}}, 0, Tables.TLeaf{None{}}, 0}
    }
  )

def Scope.levels(i: Item) -> Maybe<&2, List<&2, Maybe<&2, U32>>>:
  Items.of(~Maybe<&2, U32>, ~Item.level, i)

def Table.of(-A: Data, +xs: List<&2, A>) -> Tables.Indexed<A>:
  Tables.Table.of(A, U32.from_nat(Lists.length(&2, A, xs)), xs)

def Checked.with(
  base: String,
  frames: Item,
  declared: Item,
  scopes: Item,
  entries: Item,
  files: Item
) -> Maybe<&2, Checked>:
  do Maybe<&2, Checked>:
    f: List<&2, Frame> <- Items.of(~Frame, ~Item.frame, frames)
    d: List<&2, Declared> <- Items.of(~Declared, ~Item.declared, declared)
    s: List<
      &2,
      List<&2, Maybe<&2, U32>>> <- Items.of(~List<&2, Maybe<&2, U32>>, ~Scope.levels, scopes)
    e: List<&2, Entry> <- Items.of(~Entry, ~Item.entry, entries)
    r: List<&2, ReadFile> <- Items.of(~ReadFile, ~Item.file, files)
    return Checked{
      base,
      f,
      d,
      Table.of(List<&2, Maybe<&2, U32>>, s),
      Table.of(Entry, e),
      Table.of(ReadFile, r)
    }

# What the sections of tokens say (the last first): the files, entries and scopes, the declarations if the check
# loaded its files, and the calls that loaded them.
def Checked.of(base: String, stack: Stack) -> Maybe<&2, Checked>:
  match stack:
    case Stack{Con{files, Con{entries, Con{scopes, Con{tlds, Con{frames, Nil{}}}}}}, t, c, s, k}:
      Checked.with(base, frames, tlds, scopes, entries, files)
    case Stack{Con{files, Con{entries, Con{scopes, Con{frames, Nil{}}}}}, t, c, s, k}:
      Checked.with(base, frames, IList{[]}, scopes, entries, files)
    case _:
      None{}

# Questions
# =========
def Binder.is_eq(a: Lint.Binder, b: Lint.Binder) -> Bool:
  match a b:
    case Lint.NodeBinder{x} Lint.NodeBinder{y}:
      U32.is_eq(x, y)
    case Lint.EntryBinder{x} Lint.EntryBinder{y}:
      U32.is_eq(x, y)
    case _ _:
      False{}

def Binders.first(a: List<&2, Lint.Binder>, b: List<&2, Lint.Binder>) -> Bool:
  match a b:
    case Con{x, xs} Con{y, ys}:
      Binder.is_eq(x, y)
    case _ _:
      False{}

# How many levels two scopes share from the first: the same binder at each (`going` says whether at the first of
# these), counted onto `n`.
def Binders.shared(a: List<&2, Lint.Binder>, b: List<&2, Lint.Binder>, n: U32, going: Bool) -> U32:
  match a b going:
    case Con{x, +xs} Con{y, +ys} True{}:
      Binders.shared(xs, ys, (n + 1: U32), Binders.first(xs, ys))
    case _ _ _:
      n

def Question.same(a: Lint.TypeRef, b: Lint.TypeRef) -> String:
  match a b:
    case Lint.TypeRef{c, h, s, f, +x} Lint.TypeRef{d, i, r, e, +y}:
      "same:"
        ++ U32.show(c)
        ++ ":"
        ++ U32.show(h)
        ++ ":"
        ++ U32.show(s)
        ++ ":"
        ++ U32.show(d)
        ++ ":"
        ++ U32.show(i)
        ++ ":"
        ++ U32.show(r)
        ++ ":"
        ++ U32.show(Binders.shared(x, y, 0, Binders.first(x, y)))

def Question.field(q: Lint.Question) -> String:
  match q:
    case Lint.Show{Lint.TypeRef{c, h, s, f, b}}:
      "show:" ++ U32.show(c) ++ ":" ++ U32.show(h) ++ ":" ++ U32.show(s) ++ ":" ++ U32.show(f)
    case Lint.Same{a, b}:
      Question.same(a, b)
    case Lint.Normal{Lint.TypeRef{c, h, s, f, b}}:
      "normal:" ++ U32.show(c) ++ ":" ++ U32.show(h)

def Question.fields(questions: List<&2, Lint.Question>, out: List<&2, String>) -> List<&2, String>:
  match questions:
    case Nil{}:
      List.reverse(&2, String, out)
    case Con{q, rest}:
      Question.fields(rest, Question.field(q) <> out)

def Answer.normalized(handle: String) -> Maybe<&2, Lint.Answer>:
  do Maybe<&2, Lint.Answer>:
    h: U32 <- U32.read(handle)
    return Lint.Normalized{h}

def Answer.read.two(which: Maybe<&2, U32>, text: String) -> Maybe<&2, Lint.Answer>:
  match which:
    case Some{0}:
      Some{Lint.Shown{text}}
    case Some{1}:
      Some{Lint.Equal{String.eq(text, "true")}}
    case _:
      None{}

def Answer.read(record: List<&2, String>) -> Maybe<&2, Lint.Answer>:
  match record:
    case Con{tag, Con{text, Nil{}}}:
      Answer.read.two(
        Names.lookup(U32, tag, [Names.Named{"shown", 0}, Names.Named{"same", 1}]),
        text
      )
    case Con{tag, Con{check, Con{handle, Nil{}}}}:
      Answer.normalized(handle)
    case _:
      None{}

def Answer.all(
  records: List<&2, List<&2, String>>,
  out: List<&2, Lint.Answer>
) -> Maybe<&2, List<&2, Lint.Answer>>:
  match records:
    case Nil{}:
      Some{List.reverse(&2, Lint.Answer, out)}
    case Con{r, rest}:
      do Maybe<&2, List<&2, Lint.Answer>>:
        a: Lint.Answer <- Answer.read(r)
        Answer.all(rest, a <> out)

def Answer.got(answers: Maybe<&2, List<&2, Lint.Answer>>) -> IO(List<&2, Lint.Answer>):
  match answers:
    case Some{a}:
      IO.pure(List<&2, Lint.Answer>, a)
    case None{}:
      IO.die(List<&2, Lint.Answer>, 1, "bend-lint: the checker's answers are malformed")

def answers(questions: List<&2, Lint.Question>) -> IO(List<&2, Lint.Answer>):
  IO.bind(
    List<&2, List<&2, String>>,
    List<&2, Lint.Answer>,
    ask("ask" <> Question.fields(questions, [])),
    records => Answer.got(Answer.all(records, []))
  )

# Nodes
# =====

# The syntax nodes of a check (Lint.Node): what the parser read of each file, as trees, numbered parents first. A node
# keeps the span the parser read it at (its origin), so that a checked term finds its node (see Judgments).

# A file the check parsed: its path, its text on disk, its namespace and import aliases, the number of the file its
# parser read, if it read a declaration, the text the parser read, its imports' loads, and the calls that parsed its
# declarations.
type ParsedFile is Data:
  ParsedFile{
    path: String,
    text: String,
    namespace: String,
    aliases: List<&2, String>,
    read: Maybe<&2, U32>,
    parsed: String,
    imports: List<&2, Imported>,
    declarations: List<&2, Frame>
  }

# An import's load: the path it loads, and where its path is written.
type Imported is Data:
  Imported{path: String, at: Maybe<&2, Span>}

# Where something is written on disk, in code points.
type Range is Data:
  Range{beg: U32, end: U32}

# From where, in the text the parser read (in UTF-16 units), it is `by` units short of the file's text on disk: the
# parser reads a file with its import lines blank.
type Shift is Data:
  Shift{from: U32, by: U32}

# A line of a file on disk: where it starts, in code points, and its text.
type Line is Data:
  Line{start: U32, text: String}

# What places a span the parser read of a file in its text on disk, in code points: the file's number, the shifts (the
# last first), where each character outside UTF-16's basic plane is on disk (in order, in UTF-16 units), and the lines
# on disk, by number, with how many.
type Placer is Data:
  Placer{
    file: Maybe<&2, U32>,
    shifts: List<&2, Shift>,
    astral: List<&2, U32>,
    lines: Tables.Indexed<Line>,
    count: U32
  }

# A syntax node before it is numbered: what it is, its name, the binder it declares or uses, its quantity, where it is
# written (if the source writes it), the global name it declares or uses, the span the parser read it at, and the
# nodes under it.
type Tree is Data:
  Tree{
    syntax: Lint.Syntax,
    name: String,
    binder: Maybe<&2, U32>,
    quantity: Maybe<&2, Lint.Quantity>,
    range: Maybe<&2, Range>,
    target: String,
    origin: Maybe<&2, Span>,
    kids: List<&2, Tree>
  }

# What the tree builder builds the trees of: a term, terms, a pattern, patterns, a body, a match's cases, a let's
# bindings (at its span), a telescope's binders (closed by `close`; `templates` take `~`), a node of a kind with no
# name over what a work builds (a declaration's return type or body), a declaration, or several works, in order.
type Work is Data:
  OneTerm{term: Term}
  Terms{terms: List<&2, Term>}
  OnePattern{pattern: Pattern}
  Patterns{patterns: List<&2, Pattern>}
  OneBody{body: Body}
  Cases{cases: List<&2, Case>}
  Bindings{
    names: List<&2, String>,
    levels: List<&2, U32>,
    quantities: List<&2, Lint.Quantity>,
    values: List<&2, Term>,
    at: Maybe<&2, Span>
  }
  Cells{close: String, templates: List<&2, String>, cells: List<&2, Cell>}
  Under{syntax: Lint.Syntax, work: Work}
  Declaration{
    syntax: Lint.Syntax,
    name: String,
    target: String,
    range: Maybe<&2, Range>,
    works: List<&2, Work>
  }
  Works{works: List<&2, Work>}

# A declaration's calls: the one that starts it (a def's, or a declared name's), and the calls after it, last first.
type Group is Data:
  Group{head: Frame, frames: List<&2, Frame>}

# A binder of a top-level declaration: the declaration's node, and the binder's number in it.
type Bound is Data:
  Bound{owner: U32, binder: U32}

# A syntax node a checked term can be: its id, what it is, its name and target, the spans its children were read at,
# and, for a variable, its binder.
type Origin is Data:
  Origin{
    id: U32,
    syntax: Lint.Syntax,
    name: String,
    target: String,
    kids: List<&2, Maybe<&2, Span>>,
    binder: Maybe<&2, Bound>
  }

# The nodes numbered so far: the next id, the nodes (last first), the nodes a checked term can be, by the span they
# were read at (in the order numbered), and the binder nodes, by top-level declaration, then binder.
type Numbering is Data:
  Numbering{
    next: U32,
    nodes: List<&2, Lint.Node>,
    origins: Tables.Table<List<&2, Spot<Origin>>>,
    binders: Tables.Table<Tables.Table<U32>>
  }

# The syntax of a check: its files, each with its nodes, and, for its facts, the nodes a checked term can be and the
# binder nodes (see Numbering).
type Read is Data:
  Read{
    sources: List<&2, Lint.Source>,
    origins: Tables.Table<List<&2, Spot<Origin>>>,
    binders: Tables.Table<Tables.Table<U32>>
  }

# Files
# =====
def Parsed.book(frames: List<&2, Frame>) -> Maybe<&2, Frame>:
  match frames:
    case Nil{}:
      None{}
    case Con{Book{text, namespace, aliases, kids}, rest}:
      Some{Book{text, namespace, aliases, kids}}
    case Con{f, rest}:
      Parsed.book(rest)

def Parsed.loads(frames: List<&2, Frame>, out: List<&2, Imported>) -> List<&2, Imported>:
  match frames:
    case Nil{}:
      List.reverse(&2, Imported, out)
    case Con{Load{path, at, kids}, rest}:
      Parsed.loads(rest, Imported{path, at} <> out)
    case Con{f, rest}:
      Parsed.loads(rest, out)

# The file the parser of a file's first declaration read.
def Parsed.read(frames: List<&2, Frame>) -> Maybe<&2, U32>:
  match frames:
    case Con{Declare{file, kids}, rest}:
      file
    case Con{Head{file, written, is_constructor, name, end}, rest}:
      Some{file}
    case Con{Broken{file}, rest}:
      file
    case _:
      None{}

# A file's text on disk: what its first import's span is in, else what the parser read (a file without imports is read
# as it is).
def ReadFile.text(found: Maybe<&2, ReadFile>, fallback: String) -> String:
  match found:
    case Some{ReadFile{text, namespace}}:
      text
    case None{}:
      fallback

def Parsed.text(
  loads: List<&2, Imported>,
  files: Tables.Indexed<ReadFile>,
  parsed: String
) -> String:
  match loads:
    case Con{Imported{path, Some{Span{file, beg, end}}}, rest}:
      ReadFile.text(Tables.Indexed.get(ReadFile, files, file), parsed)
    case _:
      parsed

def Parsed.of(
  path: String,
  +loads: List<&2, Imported>,
  files: Tables.Indexed<ReadFile>,
  book: Maybe<&2, Frame>
) -> Maybe<&2, ParsedFile>:
  match book:
    case Some{Book{+text, namespace, aliases, +kids}}:
      Some{
        ParsedFile{
          path,
          Parsed.text(loads, files, text),
          namespace,
          aliases,
          Parsed.read(kids),
          text,
          loads,
          kids
        }
      }
    case _:
      None{}

# The files that the loads in `frames` parsed (last first, onto `out`), in the order Bend parsed them: a file's
# imports first. A load of a file already loaded parses nothing.
def Parsed.all(
  frames: List<&2, Frame>,
  +files: Tables.Indexed<ReadFile>,
  out: List<&2, ParsedFile>
) -> List<&2, ParsedFile>:
  match frames:
    case Nil{}:
      out
    case Con{Load{path, at, +kids}, rest}:
      Parsed.all(
        rest,
        files,
        Lists.push(
          ParsedFile,
          Parsed.of(path, Parsed.loads(kids, []), files, Parsed.book(kids)),
          Parsed.all(kids, files, out)
        )
      )
    case Con{f, rest}:
      Parsed.all(rest, files, out)

# Text
# ====

# How many UTF-16 units `c` takes.
def units(c: Char) -> U32:
  Bool.pick(U32, U32.is_gt(Char.to_u32(c), 65535), 2, 1)

def Units.go(s: String, n: U32) -> U32:
  match s:
    case SNil{}:
      n
    case SCon{c, rest}:
      Units.go(rest, (n + units(c): U32))

def Units.of(s: String) -> U32:
  Units.go(s, 0)

# The UTF-16 units of each line of `s` (with its newline), last first, onto `out`; `line` counts the line so far.
def Lines.go(s: String, line: U32, out: List<&2, U32>) -> List<&2, U32>:
  match s:
    case SNil{}:
      line <> out
    case SCon{'\n', rest}:
      Lines.go(rest, 0, (line + 1: U32) <> out)
    case SCon{+c, rest}:
      Lines.go(rest, (line + units(c): U32), out)

def Lines.of(s: String) -> List<&2, U32>:
  List.reverse(&2, U32, Lines.go(s, 0, []))

def Shifts.push(changed: Bool, shift: Shift, out: List<&2, Shift>) -> List<&2, Shift>:
  match changed:
    case True{}:
      shift <> out
    case False{}:
      out

# The shifts after each line, onto `out` (the last first): `disk` and `read` are the lines' units on disk and as read,
# `at` where the line starts as read, and `by` its shift.
def Shifts.go(
  disk: List<&2, U32>,
  read: List<&2, U32>,
  +at: U32,
  +by: U32,
  out: List<&2, Shift>
) -> List<&2, Shift>:
  match disk read:
    case Con{+d, ds} Con{+r, rs}:
      Shifts.go(
        ds,
        rs,
        (at + r: U32),
        ((by + d: U32) - r: U32),
        Shifts.push(U32.is_ne(d, r), Shift{(at + r: U32), ((by + d: U32) - r: U32)}, out)
      )
    case _ _:
      out

def Shifts.first(shifts: List<&2, Shift>, off: U32) -> Bool:
  match shifts:
    case Con{Shift{from, by}, rest}:
      U32.is_le(from, off)
    case Nil{}:
      False{}

# The shift at `off` (as read): that of the last shift from `off` or before, among `shifts` (the last first); `hit`
# says whether the first is one. A file's text is after its imports, so it is mostly the first.
def Shifts.at(shifts: List<&2, Shift>, +off: U32, hit: Bool) -> U32:
  match shifts hit:
    case Con{Shift{from, by}, rest} True{}:
      by
    case Con{s, +rest} False{}:
      Shifts.at(rest, off, Shifts.first(rest, off))
    case _ _:
      0

def Astral.push(hit: Bool, at: U32, out: List<&2, U32>) -> List<&2, U32>:
  match hit:
    case True{}:
      at <> out
    case False{}:
      out

# Where each character outside the basic plane is in `s`, onto `out` (last first); `at` counts UTF-16 units.
def Astral.go(s: String, +at: U32, out: List<&2, U32>) -> List<&2, U32>:
  match s:
    case SNil{}:
      List.reverse(&2, U32, out)
    case SCon{+c, rest}:
      Astral.go(rest, (at + units(c): U32), Astral.push(U32.is_eq(units(c), 2), at, out))

def Astral.first(astral: List<&2, U32>, at: U32) -> Bool:
  match astral:
    case Con{a, rest}:
      U32.is_lt(a, at)
    case Nil{}:
      False{}

# How many of `astral` are before `at`, after `n`: `hit` says whether the first is.
def Astral.before(astral: List<&2, U32>, +at: U32, n: U32, hit: Bool) -> U32:
  match astral hit:
    case Con{a, +rest} True{}:
      Astral.before(rest, at, (n + 1: U32), Astral.first(rest, at))
    case _ _:
      n

# The lines of `s`, onto `out` (last first): `line` is the line so far (last first), from code point `start`; `at`
# counts code points.
def Line.all(s: String, line: String, start: U32, +at: U32, out: List<&2, Line>) -> List<&2, Line>:
  match s:
    case SNil{}:
      List.reverse(&2, Line, Line{start, String.reverse(line)} <> out)
    case SCon{'\n', rest}:
      Line.all(rest, "", (at + 1: U32), (at + 1: U32), Line{start, String.reverse(line)} <> out)
    case SCon{c, rest}:
      Line.all(rest, SCon{c, line}, start, (at + 1: U32), out)

def Line.start(line: Maybe<&2, Line>) -> U32:
  match line:
    case Some{Line{start, text}}:
      start
    case None{}:
      0

# Whether the line numbered `i` starts at `at` or before.
def Line.before(lines: Tables.Indexed<Line>, i: U32, at: U32) -> Bool:
  U32.is_le(Line.start(Tables.Indexed.get(Line, lines, i)), at)

def Line.mid(lo: U32, hi: U32) -> U32:
  U32.shr((lo + hi + 1: U32))

# The number of the line that holds `at`, between the lines `lo` and `hi`: `done` says whether they are one, and `up`
# whether the line between them starts at `at` or before. `fuel` bounds the halvings.
def Line.find(
  fuel: Nat,
  +lines: Tables.Indexed<Line>,
  +at: U32,
  +lo: U32,
  +hi: U32,
  done: Bool,
  up: Bool
) -> U32:
  match fuel done up:
    case 1n+f False{} True{}:
      Line.find(
        f,
        lines,
        at,
        Line.mid(lo, hi),
        hi,
        U32.is_ge(Line.mid(lo, hi), hi),
        Line.before(lines, Line.mid(Line.mid(lo, hi), hi), at)
      )
    case 1n+f False{} False{}:
      Line.find(
        f,
        lines,
        at,
        lo,
        (Line.mid(lo, hi) - 1: U32),
        U32.is_ge(lo, (Line.mid(lo, hi) - 1: U32)),
        Line.before(lines, Line.mid(lo, (Line.mid(lo, hi) - 1: U32)), at)
      )
    case _ _ _:
      lo

# The placer of the file numbered `file`, whose text on disk is `text` and which the parser read as `read`.
def Placer.with(
  file: Maybe<&2, U32>,
  shifts: List<&2, Shift>,
  astral: List<&2, U32>,
  +lines: List<&2, Line>
) -> Placer:
  Placer{
    file,
    shifts,
    astral,
    Tables.Table.of(Line, U32.from_nat(Lists.length(&2, Line, lines)), lines),
    U32.from_nat(Lists.length(&2, Line, lines))
  }

def Placer.of(file: Maybe<&2, U32>, +text: String, read: String) -> Placer:
  Placer.with(
    file,
    Shifts.go(Lines.of(text), Lines.of(read), 0, 0, [Shift{0, 0}]),
    Astral.go(text, 0, []),
    Line.all(text, "", 0, 0, [])
  )

def Placer.at(+disk: U32, +astral: List<&2, U32>) -> U32:
  (disk - Astral.before(astral, disk, 0, Astral.first(astral, disk)): U32)

# Where an offset the parser read is on disk, in code points.
def Placer.point(placer: Placer, +off: U32) -> U32:
  match placer:
    case Placer{file, +shifts, astral, lines, count}:
      Placer.at((off + Shifts.at(shifts, off, Shifts.first(shifts, off)): U32), astral)

def Placer.mine(placer: Placer, file: U32) -> Bool:
  match placer:
    case Placer{Some{f}, shifts, astral, lines, count}:
      U32.is_eq(f, file)
    case _:
      False{}

# Where a span is on disk, if the parser read it in this file.
def Placer.range(+placer: Placer, span: Maybe<&2, Span>) -> Maybe<&2, Range>:
  match span:
    case Some{Span{file, beg, end}}:
      Lists.when(
        Range,
        Placer.mine(placer, file),
        Range{Placer.point(placer, beg), Placer.point(placer, end)}
      )
    case None{}:
      None{}

def Line.from(line: Maybe<&2, Line>, at: U32) -> String:
  match line:
    case Some{Line{start, text}}:
      String.drop(text, U32.to_nat((at - start: U32)))
    case None{}:
      ""

# The text from `at` to the end of its line, among `lines`, `count` of them.
def Placer.lines(+lines: Tables.Indexed<Line>, +count: U32, +at: U32) -> String:
  Line.from(
    Tables.Indexed.get(
      Line,
      lines,
      Line.find(
        33n,
        lines,
        at,
        0,
        (count - 1: U32),
        U32.is_ge(0, (count - 1: U32)),
        Line.before(lines, Line.mid(0, (count - 1: U32)), at)
      )
    ),
    at
  )

# The text on disk from code point `at` to the end of its line.
def Placer.text(placer: Placer, at: U32) -> String:
  match placer:
    case Placer{file, shifts, astral, lines, count}:
      Placer.lines(lines, count, at)

# Whether `c` can start a name (`[A-Za-z_]`), or, with `more`, go on with one (`[A-Za-z0-9_.]`).
def Name.char(+c: Char, more: Bool) -> Bool:
  Char.is_eq(
    c,
    '_'
  )
    || U32.is_le(Char.to_u32('a'), Char.to_u32(c))
    && U32.is_le(Char.to_u32(c), Char.to_u32('z'))
    || U32.is_le(Char.to_u32('A'), Char.to_u32(c))
    && U32.is_le(Char.to_u32(c), Char.to_u32('Z'))
    || more
    && (Char.is_eq(c, '.') || Char.is_digit(c))

def Name.next(s: String) -> Bool:
  match s:
    case SCon{c, rest}:
      Name.char(c, True{})
    case SNil{}:
      False{}

# The name `s` starts with, onto `out` (last first): `hit` says whether its first character goes on it.
def Name.go(s: String, out: String, hit: Bool) -> String:
  match s hit:
    case SCon{c, +rest} True{}:
      Name.go(rest, SCon{c, out}, Name.next(rest))
    case _ _:
      String.reverse(out)

def Name.first(s: String) -> Bool:
  match s:
    case SCon{c, rest}:
      Name.char(c, False{})
    case SNil{}:
      False{}

def Name.of(+text: String) -> String:
  Name.go(text, "", Name.first(text))

def spelled.of(+name: String) -> Maybe<&2, String>:
  Lists.when(String, Bool.not(String.is_empty(name)), name)

def spelled.at(placer: Placer, range: Maybe<&2, Range>) -> Maybe<&2, String>:
  match range:
    case Some{Range{beg, end}}:
      spelled.of(Name.of(Placer.text(placer, beg)))
    case None{}:
      None{}

# The name a span starts with, if any, as the source spells it there.
def spelled(+placer: Placer, span: Maybe<&2, Span>) -> Maybe<&2, String>:
  spelled.at(placer, Placer.range(placer, span))

def slice.at(placer: Placer, range: Maybe<&2, Range>) -> String:
  match range:
    case Some{Range{+beg, end}}:
      Strings.take(Placer.text(placer, beg), U32.to_nat((end - beg: U32)))
    case None{}:
      ""

# The text of a span on disk, up to the end of its first line.
def slice(+placer: Placer, span: Maybe<&2, Span>) -> String:
  slice.at(placer, Placer.range(placer, span))

# Trees
# =====

# The spans that references own (see `reference`).
def Owned() -> Data:
  Tables.Table<List<&2, Spot<Unit>>>

def leaf(
  syntax: Lint.Syntax,
  name: String,
  quantity: Maybe<&2, Lint.Quantity>,
  range: Maybe<&2, Range>,
  target: String,
  origin: Maybe<&2, Span>,
  owned: Owned()
) -> List<&2, Tree>
  & Owned():
  ([Tree{syntax, name, None{}, quantity, range, target, origin, []}], owned)

def node(
  syntax: Lint.Syntax,
  name: String,
  binder: Maybe<&2, U32>,
  quantity: Maybe<&2, Lint.Quantity>,
  range: Maybe<&2, Range>,
  target: String,
  origin: Maybe<&2, Span>,
  built: List<&2, Tree> & Owned()
) -> List<&2, Tree>
  & Owned():
  match built:
    case Tuple{kids, owned}:
      ([Tree{syntax, name, binder, quantity, range, target, origin, kids}], owned)

# The last part of a global name: after its last `.` or `:`.
def last(name: String) -> String:
  Strings.after_last(Strings.after_last(name, '.'), ':')

def Reference.pick(
  none: Bool,
  k: String,
  +s: Span,
  +placer: Placer,
  +name: String,
  owned: Owned()
) -> List<&2, Tree>
  & Owned():
  match none:
    case True{}:
      leaf(Lint.Reference{}, "", None{}, None{}, k, Some{s}, owned)
    case False{}:
      leaf(
        Lint.Reference{},
        Bool.pick(String, String.is_empty(name), slice(placer, Some{s}), name),
        None{},
        Placer.range(placer, Some{s}),
        k,
        Some{s},
        Spots.add(Unit, owned, s, Unit{})
      )

def Reference.of(
  +k: String,
  s: Span,
  placer: Placer,
  +name: String,
  was: Bool,
  owned: Owned()
) -> List<&2, Tree>
  & Owned():
  Reference.pick(
    was || Bool.not(String.is_empty(name)) && Bool.not(String.eq(last(name), last(k))),
    k,
    s,
    placer,
    name,
    owned
  )

# A reference to `k`, written at `span` if the span spells it (a name of `k`, or an operator) and no reference owns
# the span yet: a copy of one is the parser's.
def reference(
  k: String,
  span: Maybe<&2, Span>,
  +placer: Placer,
  +owned: Owned()
) -> List<&2, Tree>
  & Owned():
  match span:
    case Some{+s}:
      Reference.of(
        k,
        s,
        placer,
        Maybe.default(&2, String, spelled(placer, Some{s}), ""),
        Bool.not(List.is_empty(&2, Unit, Spots.get(Unit, owned, s))),
        owned
      )
    case None{}:
      leaf(Lint.Reference{}, "", None{}, None{}, k, None{}, owned)

# A use of the global name `k` at `span`, with its name as written.
def used(
  syntax: Lint.Syntax,
  k: String,
  +span: Maybe<&2, Span>,
  origin: Maybe<&2, Span>,
  +placer: Placer,
  built: List<&2, Tree> & Owned()
) -> List<&2, Tree>
  & Owned():
  node(
    syntax,
    Maybe.default(&2, String, spelled(placer, span), ""),
    None{},
    None{},
    Placer.range(placer, span),
    k,
    origin,
    built
  )

def Tree.origin(t: Tree) -> Maybe<&2, Span>:
  match t:
    case Tree{syntax, name, binder, quantity, range, target, origin, kids}:
      origin

def inside(range: Maybe<&2, Range>, at: Maybe<&2, Range>) -> Bool:
  match range at:
    case None{} _:
      True{}
    case Some{Range{b, e}} Some{Range{x, y}}:
      U32.is_le(x, b) && U32.is_le(e, y)
    case _ _:
      False{}

# Whether the first of a call's arguments is read at another span than the call's, and written inside the call's.
def Argument.inside(args: List<&2, Tree>, span: Maybe<&2, Span>, at: Maybe<&2, Range>) -> Bool:
  match args:
    case Con{Tree{syntax, name, binder, quantity, range, target, origin, kids}, rest}:
      Bool.not(Span.is_eq(origin, span)) && inside(range, at)
    case Nil{}:
      True{}

# Whether each of a call's arguments is (see `Argument.inside`): `ok` says whether the first is.
def Arguments.inside(
  args: List<&2, Tree>,
  +span: Maybe<&2, Span>,
  +at: Maybe<&2, Range>,
  ok: Bool
) -> Bool:
  match args ok:
    case Nil{} _:
      True{}
    case Con{t, +rest} True{}:
      Arguments.inside(rest, span, at, Argument.inside(rest, span, at))
    case _ _:
      False{}

# Whether a call is written at `at`: its head is, or its arguments are inside it.
def application.written(
  own: Bool,
  +args: List<&2, Tree>,
  +span: Maybe<&2, Span>,
  +at: Maybe<&2, Range>
) -> Bool:
  match own:
    case True{}:
      True{}
    case False{}:
      Arguments.inside(args, span, at, Argument.inside(args, span, at))

def application.with(
  +span: Maybe<&2, Span>,
  +at: Maybe<&2, Range>,
  head: Tree,
  +args: List<&2, Tree>,
  own: Bool,
  owned: Owned()
) -> List<&2, Tree>
  & Owned():
  (
    [
      Tree{
        Lint.Application{},
        "",
        None{},
        None{},
        Bool.pick(Maybe<&2, Range>, application.written(own, args, span, at), at, None{}),
        "",
        span,
        head <> args
      }
    ],
    owned
  )

def application.of(
  +span: Maybe<&2, Span>,
  at: Maybe<&2, Range>,
  reversed: List<&2, Tree>,
  owned: Owned()
) -> List<&2, Tree>
  & Owned():
  match reversed:
    case Con{+head, args}:
      application.with(
        span,
        at,
        head,
        List.reverse(&2, Tree, args),
        Bool.not(Span.is_eq(Tree.origin(head), span)),
        owned
      )
    case Nil{}:
      ([], owned)

# A call, built as its arguments, then its head. A call whose head shares its span is sugar: written (`A & B`,
# `return x`) if it spans its written parts and no other part shares its span; else the parser's (a do-block's bind).
def application(
  +span: Maybe<&2, Span>,
  placer: Placer,
  built: List<&2, Tree> & Owned()
) -> List<&2, Tree>
  & Owned():
  match built:
    case Tuple{trees, owned}:
      application.of(span, Placer.range(placer, span), List.reverse(&2, Tree, trees), owned)

# A call's head and arguments (see Term.spine); a call the parser read at no span is one application.
def Calls.of(+f: Term, +x: Term, span: Maybe<&2, Span>) -> Term & List<&2, Term>:
  match span:
    case Some{+s}:
      Term.spine(
        4294967295n,
        Application{f, x, Some{s}},
        Application{f, x, Some{s}},
        Some{s},
        [],
        True{}
      )
    case None{}:
      (f, [x])

def Cell.syntax(close: String) -> Lint.Syntax:
  Bool.pick(Lint.Syntax, String.eq(close, "}"), Lint.Field{}, Lint.Parameter{})

def cell(
  close: String,
  templates: List<&2, String>,
  placer: Placer,
  c: Cell,
  built: List<&2, Tree> & Owned()
) -> List<&2, Tree>
  & Owned():
  match c:
    case Cell{quantity, +name, level, annotation, +span}:
      node(
        Cell.syntax(close),
        name,
        Some{level},
        Some{
          Bool.pick(
            Lint.Quantity,
            List.contains(~String, ~String.eq, templates, name),
            Lint.Template{},
            quantity
          )
        },
        Placer.range(placer, Some{span}),
        "",
        Some{span},
        built
      )

def Cell.annotation(c: Cell) -> Term:
  match c:
    case Cell{quantity, name, level, annotation, span}:
      annotation

def Built.join(first: List<&2, Tree>, more: List<&2, Tree> & Owned()) -> List<&2, Tree> & Owned():
  match more:
    case Tuple{rest, owned}:
      (Lists.append(&2, Tree, first, rest), owned)

# The trees `first` built, then those `next` builds after it.
def Built.then(
  first: List<&2, Tree> & Owned(),
  next: Owned() -> List<&2, Tree> & Owned()
) -> List<&2, Tree>
  & Owned():
  match first:
    case Tuple{trees, owned}:
      Built.join(trees, next(owned))

# The application of a call's head and arguments, built as its arguments, then its head.
def Calls.works(call: Term & List<&2, Term>) -> Work:
  match call:
    case Tuple{head, args}:
      Works{[Terms{args}, OneTerm{head}]}

def Works.terms(terms: List<&2, Term>, out: List<&2, Work>) -> List<&2, Work>:
  match terms:
    case Nil{}:
      List.reverse(&2, Work, out)
    case Con{t, rest}:
      Works.terms(rest, OneTerm{t} <> out)

def Works.patterns(patterns: List<&2, Pattern>, out: List<&2, Work>) -> List<&2, Work>:
  match patterns:
    case Nil{}:
      List.reverse(&2, Work, out)
    case Con{p, rest}:
      Works.patterns(rest, OnePattern{p} <> out)

# The trees a work builds, and the spans that references own after it; `fuel` bounds the depth.
def build(fuel: Nat, work: Work, +placer: Placer, owned: Owned()) -> List<&2, Tree> & Owned():
  match fuel work:
    case 0n _:
      ([], owned)
    case 1n++f Works{Nil{}}:
      ([], owned)
    case 1n++f Works{Con{w, rest}}:
      Built.then(build(f, w, placer, owned), o => build(f, Works{rest}, placer, o))
    case 1n++f Terms{ts}:
      build(f, Works{Works.terms(ts, [])}, placer, owned)
    case 1n++f Patterns{ps}:
      build(f, Works{Works.patterns(ps, [])}, placer, owned)
    case 1n++f Cases{Nil{}}:
      ([], owned)
    case 1n++f Cases{Con{Case{ps, b}, rest}}:
      Built.then(
        node(
          Lint.Case{},
          "",
          None{},
          None{},
          None{},
          "",
          None{},
          build(f, Works{[Patterns{ps}, OneBody{b}]}, placer, owned)
        ),
        o => build(f, Cases{rest}, placer, o)
      )
    case 1n++f Bindings{Con{k, ks}, Con{i, ls}, Con{q, qs}, Con{v, vs}, +at}:
      Built.then(
        node(
          Lint.Binding{},
          k,
          Some{i},
          Some{q},
          None{},
          "",
          at,
          build(f, OneTerm{v}, placer, owned)
        ),
        o => build(f, Bindings{ks, ls, qs, vs, at}, placer, o)
      )
    case 1n++f Bindings{ks, ls, qs, vs, at}:
      ([], owned)
    case 1n++f Cells{close, templates, Nil{}}:
      ([], owned)
    case 1n++f Cells{+close, +templates, Con{+c, rest}}:
      Built.then(
        cell(close, templates, placer, c, build(f, OneTerm{Cell.annotation(c)}, placer, owned)),
        o => build(f, Cells{close, templates, rest}, placer, o)
      )
    case 1n++f Under{syntax, w}:
      node(syntax, "", None{}, None{}, None{}, "", None{}, build(f, w, placer, owned))
    case 1n++f Declaration{syntax, name, target, range, works}:
      node(
        syntax,
        name,
        None{},
        None{},
        range,
        target,
        None{},
        build(f, Works{works}, placer, owned)
      )
    case 1n++f OnePattern{PatternVariable{k, i, q, +s}}:
      (
        [Tree{Lint.PatternVariable{}, k, Some{i}, Some{q}, Placer.range(placer, s), "", s, []}],
        owned
      )
    case 1n++f OnePattern{PatternConstructor{k, ps, s}}:
      used(Lint.PatternConstructor{}, k, s, None{}, placer, build(f, Patterns{ps}, placer, owned))
    case 1n++f OneBody{Match{es, cs, s}}:
      node(
        Lint.Match{},
        "",
        None{},
        None{},
        Placer.range(placer, s),
        "",
        None{},
        build(f, Works{[Terms{es}, Cases{cs}]}, placer, owned)
      )
    case 1n++f OneBody{Destructure{ps, q, vs, b}}:
      node(
        Lint.Destructure{},
        "",
        None{},
        Some{q},
        None{},
        "",
        None{},
        build(f, Works{[Patterns{ps}, Terms{vs}, OneBody{b}]}, placer, owned)
      )
    case 1n++f OneBody{Expression{t}}:
      build(f, OneTerm{t}, placer, owned)
    case 1n++f OneTerm{Variable{k, i, None{}, +s}}:
      ([Tree{Lint.Variable{}, k, Some{i}, None{}, Placer.range(placer, s), "", s, []}], owned)
    case 1n++f OneTerm{Variable{k, i, Some{v}, s}}:
      reference(v, s, placer, owned)
    case 1n++f OneTerm{Reference{k, s}}:
      reference(k, s, placer, owned)
    case 1n++f OneTerm{Substitution{i, p, b, +s}}:
      node(
        Lint.Substitution{},
        "",
        Some{i},
        None{},
        Placer.range(placer, s),
        "",
        s,
        build(f, Works{[OnePattern{p}, OneTerm{b}]}, placer, owned)
      )
    case 1n++f OneTerm{Let{ks, ls, qs, vs, b, +s}}:
      node(
        Lint.Let{},
        "",
        None{},
        None{},
        Placer.range(placer, s),
        "",
        s,
        build(f, Works{[Bindings{ks, ls, qs, vs, s}, OneTerm{b}]}, placer, owned)
      )
    case 1n++f OneTerm{Sort{g, +s}}:
      node(
        Lint.Sort{},
        "",
        None{},
        None{},
        Placer.range(placer, s),
        "",
        s,
        build(f, OneTerm{g}, placer, owned)
      )
    case 1n++f OneTerm{QuantityType{+s}}:
      leaf(Lint.QuantityType{}, "", None{}, Placer.range(placer, s), "", s, owned)
    case 1n++f OneTerm{QuantityLiteral{q, +s}}:
      leaf(Lint.QuantityLiteral{}, "", Some{q}, Placer.range(placer, s), "", s, owned)
    case 1n++f OneTerm{QuantityMinimum{a, b, +s}}:
      node(
        Lint.QuantityMinimum{},
        "",
        None{},
        None{},
        Placer.range(placer, s),
        "",
        s,
        build(f, Terms{[a, b]}, placer, owned)
      )
    case 1n++f OneTerm{Forall{q, k, i, a, b, +s}}:
      node(
        Lint.Forall{},
        k,
        Some{i},
        Some{q},
        Placer.range(placer, s),
        "",
        s,
        build(f, Terms{[a, b]}, placer, owned)
      )
    case 1n++f OneTerm{Lambda{+k, i, b, q, +s}}:
      node(
        Lint.Lambda{},
        k,
        Some{i},
        q,
        Bool.pick(
          Maybe<&2, Range>,
          String.eq(Maybe.default(&2, String, spelled(placer, s), ""), k),
          Placer.range(placer, s),
          None{}
        ),
        "",
        s,
        build(f, OneTerm{b}, placer, owned)
      )
    case 1n++f OneTerm{Application{fn, x, +s}}:
      application(s, placer, build(f, Calls.works(Calls.of(fn, x, s)), placer, owned))
    case 1n++f OneTerm{TypeApplication{k, xs, +s}}:
      used(Lint.TypeApplication{}, k, s, s, placer, build(f, Terms{xs}, placer, owned))
    case 1n++f OneTerm{Construction{k, xs, +s}}:
      used(Lint.Construction{}, k, s, s, placer, build(f, Terms{xs}, placer, owned))
    case 1n++f OneTerm{Literal{k, v, +s}}:
      leaf(Lint.Literal{}, v, None{}, Placer.range(placer, s), k, s, owned)
    case 1n++f OneTerm{Elimination{k, h, m, +s}}:
      node(
        Lint.Elimination{},
        "",
        None{},
        None{},
        Placer.range(placer, s),
        k,
        s,
        build(f, Terms{[h, m]}, placer, owned)
      )
    case 1n++f OneTerm{Absurd{+s}}:
      leaf(Lint.Absurd{}, "", None{}, Placer.range(placer, s), "", s, owned)
    case 1n++f OneTerm{Equality{a, b, t, +s}}:
      node(
        Lint.Equality{},
        "",
        None{},
        None{},
        Placer.range(placer, s),
        "",
        s,
        build(f, Terms{[a, b, t]}, placer, owned)
      )
    case 1n++f OneTerm{Reflexivity{+s}}:
      leaf(Lint.Reflexivity{}, "", None{}, Placer.range(placer, s), "", s, owned)
    case 1n++f OneTerm{Rewrite{e, p, b, +s}}:
      node(
        Lint.Rewrite{},
        "",
        None{},
        None{},
        Placer.range(placer, s),
        "",
        s,
        build(f, Terms{[e, p, b]}, placer, owned)
      )
    case 1n++f OneTerm{Hole{k, +s}}:
      leaf(Lint.Hole{}, k, None{}, Placer.range(placer, s), "", s, owned)
    case 1n++f OneTerm{Annotation{x, t, +s}}:
      node(
        Lint.Annotation{},
        "",
        None{},
        None{},
        Placer.range(placer, s),
        "",
        s,
        build(f, Terms{[x, t]}, placer, owned)
      )
    case 1n++f OneTerm{Typed{t, h}}:
      build(f, OneTerm{t}, placer, owned)
    case 1n++f OneTerm{Judged{t, j}}:
      build(f, OneTerm{t}, placer, owned)

# Declarations
# ============
def Group.add(frame: Frame, current: Maybe<&2, Group>) -> Maybe<&2, Group>:
  match current:
    case Some{Group{head, frames}}:
      Some{Group{head, frame <> frames}}
    case None{}:
      None{}

# The groups of a file's calls (see Group), in order, onto `out` (last first); `current` is the open one. The calls
# before the first are no declaration's.
def Group.all(
  frames: List<&2, Frame>,
  current: Maybe<&2, Group>,
  out: List<&2, Group>
) -> List<&2, Group>:
  match frames:
    case Nil{}:
      List.reverse(&2, Group, Lists.push(Group, current, out))
    case Con{Declare{file, kids}, rest}:
      Group.all(rest, Some{Group{Declare{file, kids}, []}}, Lists.push(Group, current, out))
    case Con{Head{file, written, is_constructor, name, end}, rest}:
      Group.all(
        rest,
        Some{Group{Head{file, written, is_constructor, name, end}, []}},
        Lists.push(Group, current, out)
      )
    case Con{f, rest}:
      Group.all(rest, Group.add(f, current), out)

# The last declared name read among `frames`: a def's own name, after the name it may fill.
def Head.last(frames: List<&2, Frame>, found: Maybe<&2, Frame>) -> Maybe<&2, Frame>:
  match frames:
    case Nil{}:
      found
    case Con{Head{file, written, is_constructor, name, end}, rest}:
      Head.last(rest, Some{Head{file, written, is_constructor, name, end}})
    case Con{f, rest}:
      Head.last(rest, found)

# The last term Bend built among `frames`: a law's type, from its clauses.
def Higher.last(frames: List<&2, Frame>, found: Maybe<&2, Term>) -> Maybe<&2, Term>:
  match frames:
    case Nil{}:
      found
    case Con{Higher{t}, rest}:
      Higher.last(rest, Some{t})
    case Con{f, rest}:
      Higher.last(rest, found)

# What a declaration's calls build: a telescope's binders, its return type, or its body.
def unders(frames: List<&2, Frame>, out: List<&2, Work>) -> List<&2, Work>:
  match frames:
    case Nil{}:
      List.reverse(&2, Work, out)
    case Con{Tele{close, templates, cells}, rest}:
      unders(rest, Cells{close, templates, cells} <> out)
    case Con{Parsed{t}, rest}:
      unders(rest, Under{Lint.Returns{}, OneTerm{t}} <> out)
    case Con{ParsedBody{b}, rest}:
      unders(rest, Under{Lint.Body{}, OneBody{b}} <> out)
    case Con{f, rest}:
      unders(rest, out)

# A law's type, from its clauses.
def Law.works(t: Maybe<&2, Term>) -> List<&2, Work>:
  match t:
    case Some{t}:
      [Under{Lint.Returns{}, OneTerm{t}}]
    case None{}:
      []

# The declaration a name read at `head` starts, of what `syntax` is, over `works`.
def Declaration.at(
  syntax: Lint.Syntax,
  head: Maybe<&2, Frame>,
  placer: Placer,
  works: List<&2, Work>
) -> Maybe<&2, Work>:
  match head:
    case Some{Head{file, +written, is_constructor, name, +end}}:
      Some{
        Declaration{
          syntax,
          written,
          name,
          Placer.range(placer, Some{Span{file, (end - Units.of(written): U32), end}}),
          works
        }
      }
    case _:
      None{}

def Declaration.syntax(is_constructor: Bool, datatype: Bool) -> Lint.Syntax:
  match is_constructor datatype:
    case True{} _:
      Lint.Constructor{}
    case False{} True{}:
      Lint.Datatype{}
    case False{} False{}:
      Lint.Law{}

def Declaration.is_law(syntax: Lint.Syntax) -> Bool:
  match syntax:
    case Lint.Law{}:
      True{}
    case _:
      False{}

# What a declaration's calls build: a law's type, from its clauses; else its binders, return type and body.
def Declaration.works(is_law: Bool, frames: List<&2, Frame>) -> List<&2, Work>:
  match is_law:
    case True{}:
      Law.works(Higher.last(frames, None{}))
    case False{}:
      unders(frames, [])

def Declaration.fresh(
  +syntax: Lint.Syntax,
  head: Frame,
  placer: Placer,
  frames: List<&2, Frame>
) -> Maybe<&2, Work>:
  Declaration.at(syntax, Some{head}, placer, Declaration.works(Declaration.is_law(syntax), frames))

# The declaration a group makes: a def at the last name it reads; a constructor; a type (by `datatypes`, the check's);
# or a law, whose signature is the type Bend builds from its clauses.
def Declaration.of(group: Group, placer: Placer, datatypes: Set()) -> Maybe<&2, Work>:
  match group:
    case Group{Declare{file, +kids}, frames}:
      Declaration.at(Lint.Definition{}, Head.last(kids, None{}), placer, unders(kids, []))
    case Group{Head{file, written, +is_constructor, +name, end}, frames}:
      Declaration.fresh(
        Declaration.syntax(is_constructor, Pair.snd(Set(), Bool, Set.has(datatypes, name))),
        Head{file, written, is_constructor, name, end},
        placer,
        List.reverse(&2, Frame, frames)
      )
    case _:
      None{}

def Declaration.all(
  groups: List<&2, Group>,
  +placer: Placer,
  +datatypes: Set(),
  out: List<&2, Work>
) -> List<&2, Work>:
  match groups:
    case Nil{}:
      List.reverse(&2, Work, out)
    case Con{g, rest}:
      Declaration.all(
        rest,
        placer,
        datatypes,
        Lists.push(Work, Declaration.of(g, placer, datatypes), out)
      )

def Tree.adopt(
  top: Maybe<&2, Tree>,
  constructors: List<&2, Tree>,
  out: List<&2, Tree>
) -> List<&2, Tree>:
  match top:
    case Some{Tree{syntax, name, binder, quantity, range, target, origin, kids}}:
      Tree{
        syntax,
        name,
        binder,
        quantity,
        range,
        target,
        origin,
        Lists.append(&2, Tree, kids, List.reverse(&2, Tree, constructors))
      }
        <> out
    case None{}:
      out

# The declarations of a file, each constructor under the type before it (`top`, with the constructors so far, last
# first), onto `out` (last first).
def Tree.tops(
  trees: List<&2, Tree>,
  top: Maybe<&2, Tree>,
  constructors: List<&2, Tree>,
  out: List<&2, Tree>
) -> List<&2, Tree>:
  match trees:
    case Nil{}:
      List.reverse(&2, Tree, Tree.adopt(top, constructors, out))
    case Con{Tree{Lint.Constructor{}, name, binder, quantity, range, target, origin, kids}, rest}:
      Tree.tops(
        rest,
        top,
        Tree{
          Lint.Constructor{},
          name,
          binder,
          quantity,
          range,
          target,
          origin,
          kids
        }
          <> constructors,
        out
      )
    case Con{t, rest}:
      Tree.tops(rest, Some{t}, [], Tree.adopt(top, constructors, out))

def Built.trees(built: List<&2, Tree> & Owned()) -> List<&2, Tree>:
  match built:
    case Tuple{trees, owned}:
      trees

# The trees of a declaration. A copy of a span is the parser's, which makes it in one declaration, so the spans
# references own are a declaration's own.
def Declaration.trees(+placer: Placer, work: Work) -> List<&2, Tree>:
  Built.trees(build(4294967295n, work, placer, Tables.TLeaf{None{}}))

# The trees of what a file declares, built in parallel: each declaration with its binders, signature and body; a
# constructor under its type.
def declarations(frames: List<&2, Frame>, +placer: Placer, datatypes: Set()) -> List<&2, Tree>:
  Tree.tops(
    Lists.concat(
      &2,
      Tree,
      Lists.fork(
        ~Placer,
        ~Work,
        ~List<&2, Tree>,
        ~Declaration.trees,
        64n,
        placer,
        Lists.Whole{Declaration.all(Group.all(frames, None{}, []), placer, datatypes, [])}
      )
    ),
    None{},
    [],
    []
  )

# Imports
# =======
def space(+c: Char) -> Bool:
  Char.is_eq(c, ' ') || Char.is_eq(c, '\t') || Char.is_eq(c, '\n') || Char.is_eq(c, '\r')

# `s` from `to` UTF-16 units in, and how many code points that skips; `at` counts the units so far, `n` the code
# points, and `going` whether `at` is short of `to`.
def Seek.go(s: String, +to: U32, +at: U32, n: U32, going: Bool) -> String & U32:
  match s going:
    case SCon{+c, rest} True{}:
      Seek.go(rest, to, (at + units(c): U32), (n + 1: U32), U32.is_lt((at + units(c): U32), to))
    case _ _:
      (s, n)

def Word.next(s: String) -> Bool:
  match s:
    case SCon{c, rest}:
      Bool.not(space(c))
    case SNil{}:
      False{}

# The characters of `s` up to its first space, onto `out` (last first); `going` says whether the next one is not one.
def Word.go(s: String, out: String, going: Bool) -> String:
  match s going:
    case SCon{c, +rest} True{}:
      Word.go(rest, SCon{c, out}, Word.next(rest))
    case _ _:
      String.reverse(out)

# Where `needle` first is in `s`, in code points after `n`; `hit` says whether `s` starts with it.
def Find.go(s: String, +needle: String, n: U32, hit: Bool) -> Maybe<&2, U32>:
  match s hit:
    case _ True{}:
      Some{n}
    case SNil{} False{}:
      None{}
    case SCon{c, +rest} False{}:
      Find.go(rest, needle, (n + 1: U32), String.starts_with(rest, needle))

def Import.path(+from: U32, +path: String) -> List<&2, Tree>:
  [
    Tree{
      Lint.ImportPath{},
      path,
      None{},
      None{},
      Some{Range{from, (from + U32.from_nat(String.length(path)): U32)}},
      "",
      None{},
      []
    }
  ]

def Import.range(+beg: Maybe<&2, U32>, name: String) -> Maybe<&2, Range>:
  match beg:
    case Some{+b}:
      Some{Range{b, (b + U32.from_nat(String.length(name)): U32)}}
    case None{}:
      None{}

# An import's node at `rest`, the text from where its path is written (at `from`, in code points): its alias (or Base)
# and the file it loads, with the path it writes (Base writes none). Its alias is after its path.
def Import.of(
  alias: Maybe<&2, String>,
  target: String,
  +from: U32,
  +rest: String,
  +path: String
) -> Tree:
  match alias:
    case Some{+a}:
      Tree{
        Lint.Import{},
        a,
        None{},
        None{},
        Import.range(
          Find.go(
            String.drop(rest, String.length(path)),
            a,
            (from + U32.from_nat(String.length(path)): U32),
            String.starts_with(String.drop(rest, String.length(path)), a)
          ),
          a
        ),
        target,
        None{},
        Import.path(from, path)
      }
    case None{}:
      Tree{
        Lint.Import{},
        "Base",
        None{},
        None{},
        Import.range(Some{from}, "Base"),
        target,
        None{},
        []
      }

def Import.at(alias: Maybe<&2, String>, target: String, sought: String & U32) -> Tree:
  match sought:
    case Tuple{+rest, from}:
      Import.of(alias, target, from, rest, Word.go(rest, "", Word.next(rest)))

def Load.from(at: Maybe<&2, Span>) -> U32:
  match at:
    case Some{Span{file, beg, end}}:
      beg
    case None{}:
      0

# An import's node, and the aliases left: one is its alias, unless it imports Base.
def Import.one(
  base: Bool,
  path: String,
  +at: Maybe<&2, Span>,
  aliases: List<&2, String>,
  text: String
) -> Tree
  & List<&2, String>:
  match base aliases:
    case False{} Con{a, rest}:
      (
        Import.at(Some{a}, path, Seek.go(text, Load.from(at), 0, 0, U32.is_lt(0, Load.from(at)))),
        rest
      )
    case _ _:
      (
        Import.at(None{}, path, Seek.go(text, Load.from(at), 0, 0, U32.is_lt(0, Load.from(at)))),
        aliases
      )

def Import.then(
  made: Tree & List<&2, String>,
  out: List<&2, Tree>
) -> List<&2, String>
  & List<&2, Tree>:
  match made:
    case Tuple{t, aliases}:
      (aliases, t <> out)

# The nodes of a file's imports (in `text`): `made` holds the aliases left, and the nodes so far (last first). Bend
# adds an alias per import but Base's, in order.
def imports(
  loads: List<&2, Imported>,
  made: List<&2, String> & List<&2, Tree>,
  +base: String,
  +text: String
) -> List<&2, Tree>:
  match loads made:
    case Nil{} Tuple{aliases, out}:
      List.reverse(&2, Tree, out)
    case Con{Imported{+path, at}, rest} Tuple{aliases, out}:
      imports(
        rest,
        Import.then(Import.one(String.eq(path, base), path, at, aliases, text), out),
        base,
        text
      )

# Numbering
# =========

# Whether a node of `syntax` declares a binder.
def binds(syntax: Lint.Syntax) -> Bool:
  match syntax:
    case Lint.Parameter{}:
      True{}
    case Lint.Field{}:
      True{}
    case Lint.PatternVariable{}:
      True{}
    case Lint.Lambda{}:
      True{}
    case Lint.Forall{}:
      True{}
    case Lint.Binding{}:
      True{}
    case _:
      False{}

def is_variable(syntax: Lint.Syntax) -> Bool:
  match syntax:
    case Lint.Variable{}:
      True{}
    case _:
      False{}

def Kids.origins(kids: List<&2, Tree>, out: List<&2, Maybe<&2, Span>>) -> List<&2, Maybe<&2, Span>>:
  match kids:
    case Nil{}:
      List.reverse(&2, Maybe<&2, Span>, out)
    case Con{t, rest}:
      Kids.origins(rest, Tree.origin(t) <> out)

def Number.span(path: String, range: Maybe<&2, Range>) -> Maybe<&2, Lint.Span>:
  match range:
    case Some{Range{beg, end}}:
      Some{Lint.Span{path, beg, end}}
    case None{}:
      None{}

# A node's binder in its top-level declaration `top`.
def Number.key(top: U32, binder: Maybe<&2, U32>) -> Maybe<&2, Bound>:
  match binder:
    case Some{b}:
      Some{Bound{top, b}}
    case None{}:
      None{}

def Number.origin(
  origin: Maybe<&2, Span>,
  o: Origin,
  origins: Tables.Table<List<&2, Spot<Origin>>>
) -> Tables.Table<List<&2, Spot<Origin>>>:
  match origin:
    case Some{s}:
      Spots.add(Origin, origins, s, o)
    case None{}:
      origins

def Binders.in(owner: Maybe<&2, Tables.Table<U32>>, binder: U32) -> Maybe<&2, U32>:
  match owner:
    case Some{t}:
      Tables.Table.read(U32, t, binder)
    case None{}:
      None{}

# The binder node of a binder, if `binders` has it.
def Binders.get(binders: Tables.Table<Tables.Table<U32>>, bound: Bound) -> Maybe<&2, U32>:
  match bound:
    case Bound{owner, binder}:
      Binders.in(Tables.Table.read(Tables.Table<U32>, binders, owner), binder)

def Binders.add(
  +binders: Tables.Table<Tables.Table<U32>>,
  +owner: U32,
  binder: U32,
  id: U32
) -> Tables.Table<Tables.Table<U32>>:
  Tables.Table.set(
    Tables.Table<U32>,
    binders,
    owner,
    Tables.Table.set(
      U32,
      Maybe.default(
        &2,
        Tables.Table<U32>,
        Tables.Table.read(Tables.Table<U32>, binders, owner),
        Tables.TLeaf{None{}}
      ),
      binder,
      id
    )
  )

def Number.binder(
  hit: Bool,
  key: Maybe<&2, Bound>,
  id: U32,
  binders: Tables.Table<Tables.Table<U32>>
) -> Tables.Table<Tables.Table<U32>>:
  match hit key:
    case True{} Some{Bound{owner, binder}}:
      Binders.add(binders, owner, binder, id)
    case _ _:
      binders

def Number.variable(variable: Bool, key: Maybe<&2, Bound>) -> Maybe<&2, Bound>:
  match variable:
    case True{}:
      key
    case False{}:
      None{}

# Numbers the node `id`, under `parent` in the top-level declaration `top`.
def Number.add(+id: U32, parent: U32, +top: U32, path: String, t: Tree, n: Numbering) -> Numbering:
  match t n:
    case Tree{
      +syntax,
      +name,
      +binder,
      quantity,
      range,
      +target,
      origin,
      kids
    } Numbering{next, nodes, origins, binders}:
      Numbering{
        (id + 1: U32),
        Lint.Node{
          id,
          parent,
          top,
          syntax,
          name,
          binder,
          quantity,
          Number.span(path, range),
          target
        }
          <> nodes,
        Number.origin(
          origin,
          Origin{
            id,
            syntax,
            name,
            target,
            Kids.origins(kids, []),
            Number.variable(is_variable(syntax), Number.key(top, binder))
          },
          origins
        ),
        Number.binder(binds(syntax), Number.key(top, binder), id, binders)
      }

def Number.next(n: Numbering) -> U32:
  match n:
    case Numbering{next, nodes, origins, binders}:
      next

def Number.owner(+owner: U32, id: U32) -> U32:
  Bool.pick(U32, U32.is_eq(owner, 0), id, owner)

# The nodes of `trees`, parents first, under the node numbered `parent`, in the top-level declaration numbered
# `owner` (0 at the top: a top node is its own).
def Number.go(
  trees: List<&2, Tree>,
  +parent: U32,
  +owner: U32,
  +path: String,
  +n: Numbering
) -> Numbering:
  match trees:
    case Nil{}:
      n
    case Con{Tree{syntax, name, binder, quantity, range, target, origin, +kids}, rest}:
      Number.go(
        rest,
        parent,
        owner,
        path,
        Number.go(
          kids,
          Number.next(n),
          Number.owner(owner, Number.next(n)),
          path,
          Number.add(
            Number.next(n),
            parent,
            Number.owner(owner, Number.next(n)),
            path,
            Tree{syntax, name, binder, quantity, range, target, origin, kids},
            n
          )
        )
      )

# Sources
# =======
def Read.datatypes(declared: List<&2, Declared>, out: Set()) -> Set():
  match declared:
    case Nil{}:
      out
    case Con{Declared{name, True{}, binders, constructors, body}, rest}:
      Read.datatypes(rest, Set.add(out, name))
    case Con{d, rest}:
      Read.datatypes(rest, out)

def Read.trees(
  placer: Placer,
  loads: List<&2, Imported>,
  aliases: List<&2, String>,
  base: String,
  text: String,
  frames: List<&2, Frame>,
  datatypes: Set()
) -> List<&2, Tree>:
  Lists.append(
    &2,
    Tree,
    imports(loads, (aliases, []), base, text),
    declarations(frames, placer, datatypes)
  )

# What every file's trees are built with: Base's path, and the check's datatypes.
type Reader is Data:
  Reader{base: String, datatypes: Set()}

# A file's source, but its nodes, the trees of its nodes, and how many they are.
type Planted is Data:
  Planted{source: Lint.Source, trees: List<&2, Tree>, count: U32}

# A file's trees, and the number of its first node.
type Placed is Data:
  Placed{first: U32, planted: Planted}

# A file's source with its nodes, the nodes a checked term can be, and its binder nodes (see Numbering).
type Numbered is Data:
  Numbered{
    source: Lint.Source,
    origins: Tables.Table<List<&2, Spot<Origin>>>,
    binders: Tables.Table<Tables.Table<U32>>
  }

# How many nodes `trees` are, after `n`.
def Tree.count(trees: List<&2, Tree>, n: U32) -> U32:
  match trees:
    case Nil{}:
      n
    case Con{Tree{syntax, name, binder, quantity, range, target, origin, kids}, rest}:
      Tree.count(rest, Tree.count(kids, (n + 1: U32)))

def Planted.with(source: Lint.Source, +trees: List<&2, Tree>) -> Planted:
  Planted{source, trees, Tree.count(trees, 0)}

def Planted.of(+reader: Reader, file: ParsedFile) -> Planted:
  match reader file:
    case Reader{
      base,
      datatypes
    } ParsedFile{path, +text, namespace, aliases, read, parsed, loads, frames}:
      Planted.with(
        Lint.Source{path, namespace, text, [], []},
        Read.trees(Placer.of(read, text, parsed), loads, aliases, base, text, frames, datatypes)
      )

# Each file of `planted` with the number of its first node, `first` for the first file.
def Placed.all(planted: List<&2, Planted>, +first: U32, out: List<&2, Placed>) -> List<&2, Placed>:
  match planted:
    case Nil{}:
      List.reverse(&2, Placed, out)
    case Con{Planted{source, trees, +count}, rest}:
      Placed.all(rest, (first + count: U32), Placed{first, Planted{source, trees, count}} <> out)

def Numbered.of(source: Lint.Source, n: Numbering) -> Numbered:
  match source n:
    case Lint.Source{path, namespace, text, none, facts} Numbering{next, nodes, origins, binders}:
      Numbered{
        Lint.Source{path, namespace, text, List.reverse(&2, Lint.Node, nodes), facts},
        origins,
        binders
      }

# A file's nodes, numbered from its first.
def Placed.number(+u: Unit, p: Placed) -> Numbered:
  match p:
    case Placed{first, Planted{Lint.Source{+path, namespace, text, none, facts}, trees, count}}:
      Numbered.of(
        Lint.Source{path, namespace, text, [], facts},
        Number.go(
          trees,
          0,
          0,
          path,
          Numbering{first, [], Tables.TLeaf{None{}}, Tables.TLeaf{None{}}}
        )
      )

# The nodes at one start of two files' spans: one file's, then the other's.
def Spot.join(a: List<&2, Spot<Origin>>, b: List<&2, Spot<Origin>>) -> List<&2, Spot<Origin>>:
  Lists.append(&2, Spot<Origin>, a, b)

# The binder nodes of two files' declarations: no declaration is both's.
def Binders.join(a: Tables.Table<U32>, b: Tables.Table<U32>) -> Tables.Table<U32>:
  a

# The sources of the files `numbered`, in order, onto `out` (last first), with the nodes a checked term can be and
# the binder nodes of all of them.
def Read.gather(
  numbered: List<&2, Numbered>,
  origins: Tables.Table<List<&2, Spot<Origin>>>,
  binders: Tables.Table<Tables.Table<U32>>,
  out: List<&2, Lint.Source>
) -> Read:
  match numbered:
    case Nil{}:
      Read{List.reverse(&2, Lint.Source, out), origins, binders}
    case Con{Numbered{source, o, b}, rest}:
      Read.gather(
        rest,
        Tables.Table.merge(~List<&2, Spot<Origin>>, ~Spot.join, origins, o),
        Tables.Table.merge(~Tables.Table<U32>, ~Binders.join, binders, b),
        source <> out
      )

def Read.sources(r: Read) -> List<&2, Lint.Source>:
  match r:
    case Read{sources, origins, binders}:
      sources

def Parsed.of_check(
  files: Tables.Indexed<ReadFile>,
  frames: List<&2, Frame>
) -> List<&2, ParsedFile>:
  List.reverse(&2, ParsedFile, Parsed.all(frames, files, []))

# The syntax of a check: each file it parsed, with its nodes, numbered from 1. The files' trees are built, and
# their nodes numbered, in parallel.
def Read.of(checked: Checked) -> Read:
  match checked:
    case Checked{base, frames, declared, scopes, entries, files}:
      Read.gather(
        Lists.fork(
          ~Unit,
          ~Placed,
          ~Numbered,
          ~Placed.number,
          64n,
          Unit{},
          Lists.Whole{
            Placed.all(
              Lists.fork(
                ~Reader,
                ~ParsedFile,
                ~Planted,
                ~Planted.of,
                64n,
                Reader{base, Read.datatypes(declared, Set.new())},
                Lists.Whole{Parsed.of_check(files, frames)}
              ),
              1,
              []
            )
          }
        ),
        Tables.TLeaf{None{}},
        Tables.TLeaf{None{}},
        []
      )

# Failures
# ========

# Where a failure is: its span on disk, and the text of its file.
type Located is Data:
  Located{span: Lint.Span, text: String}

def Parsed.reads(parsed: List<&2, ParsedFile>, file: U32) -> Bool:
  match parsed:
    case Con{ParsedFile{path, text, namespace, aliases, Some{r}, p, loads, frames}, rest}:
      U32.is_eq(r, file)
    case _:
      False{}

# The file whose parser read the file numbered `file`; `hit` says whether it is the first of `parsed`.
def Parsed.find(parsed: List<&2, ParsedFile>, +file: U32, hit: Bool) -> Maybe<&2, ParsedFile>:
  match parsed hit:
    case Con{p, rest} True{}:
      Some{p}
    case Con{p, +rest} False{}:
      Parsed.find(rest, file, Parsed.reads(rest, file))
    case _ _:
      None{}

def Parsed.first(+parsed: List<&2, ParsedFile>, +file: U32) -> Maybe<&2, ParsedFile>:
  Parsed.find(parsed, file, Parsed.reads(parsed, file))

def Located.at(path: String, text: String, range: Maybe<&2, Range>) -> Maybe<&2, Located>:
  match range:
    case Some{Range{beg, end}}:
      Some{Located{Lint.Span{path, beg, end}, text}}
    case None{}:
      None{}

# Where the span is, in the file a load did not finish (`pending`, with its text on disk), if there is one.
def Located.pending(
  none: Bool,
  pending: String,
  +text: String,
  read: String,
  span: Span
) -> Maybe<&2, Located>:
  match none span:
    case False{} Span{+file, beg, end}:
      Located.at(
        pending,
        text,
        Placer.range(Placer.of(Some{file}, text, read), Some{Span{file, beg, end}})
      )
    case _ _:
      None{}

def Located.of(
  found: Maybe<&2, ParsedFile>,
  +span: Span,
  +pending: String,
  +text: String,
  files: Tables.Indexed<ReadFile>
) -> Maybe<&2, Located>:
  match found span:
    case Some{ParsedFile{path, +disk, namespace, aliases, read, parsed, loads, frames}} _:
      Located.at(path, disk, Placer.range(Placer.of(read, disk, parsed), Some{span}))
    case None{} Span{+file, beg, end}:
      Located.pending(
        String.is_empty(pending),
        pending,
        text,
        ReadFile.text(Tables.Indexed.get(ReadFile, files, file), text),
        span
      )

# Where a failed check's error is, if Bend's error says: in a file the check parsed, or else in the file a load did
# not finish (`pending`, with its text).
def located(checked: Checked, +span: Span, pending: String, text: String) -> Maybe<&2, Located>:
  match checked span:
    case Checked{base, frames, declared, scopes, entries, +files} Span{+file, beg, end}:
      Located.of(Parsed.first(Parsed.of_check(files, frames), file), span, pending, text, files)

# Judgments
# =========

# The checker's facts on the nodes of a check (Lint.Fact): from each declaration's type (its binders), then each def's
# checked body. A checked term is a node's if it was read at the node's span and has its kind and name, and, for a call
# or a constructor, its children's spans; a variable must also name the node's binder. So a term the checker made from
# another (a pattern put for a scrutinee, a partial call, a list's tail) is no node's. A fact has the demand and scope
# the checker judged its term with. A lambda's or let's binder declares the type and quantity its entry in the scope
# of its body has, unless it is a parameter its signature declared (a law's fill takes the law's); it is used as often
# as its judgment closed it.

# What a fact on a node says before it is one: what of the node, the type's handle, the scope, the quantity, and the
# file whose spelling shows the type.
type Noted is Data:
  Noted{role: Lint.Role, handle: U32, scope: U32, quantity: Lint.Quantity, file: U32}

# What reading a check's facts uses: the nodes a checked term can be and the binder nodes (Read's), and the
# check's scopes and entries.
type Lookup is Data:
  Lookup{
    origins: Tables.Table<List<&2, Spot<Origin>>>,
    binders: Tables.Table<Tables.Table<U32>>,
    scopes: Tables.Indexed<List<&2, Maybe<&2, U32>>>,
    entries: Tables.Indexed<Entry>
  }

# What the walk found so far: each node's judgments, by id, the last first; how often each binder node is used (the most of
# its checked copies); and the node of each entry the walk met, by number: the binder it is.
type Found is Data:
  Found{
    judged: Tables.Table<List<&2, Noted>>,
    used: Tables.Table<Lint.Quantity>,
    ids: Tables.Table<U32>
  }

# What the walk walks: a term, judged `up` above it; terms; a term without the checker's annotations, with the handle
# of its outermost one and its judgment (its own, else `up`); or a call (see `Call.of`).
type Walk is Data:
  One{term: Term, up: Maybe<&2, Judgment>}
  Many{terms: List<&2, Term>, up: Maybe<&2, Judgment>}
  Bare{term: Term, handle: Maybe<&2, U32>, judgment: Maybe<&2, Judgment>}
  Call{
    typed: Term,
    head: Term,
    args: List<&2, Term>,
    span: Maybe<&2, Span>,
    handle: Maybe<&2, U32>,
    judgment: Maybe<&2, Judgment>
  }

# Lookups
# =======
def Found.judged(found: Found, id: U32) -> List<&2, Noted>:
  match found:
    case Found{judged, used, ids}:
      List.reverse(
        &2,
        Noted,
        Maybe.default(&2, List<&2, Noted>, Tables.Table.read(List<&2, Noted>, judged, id), [])
      )

def Found.used(found: Found, id: U32) -> Maybe<&2, Lint.Quantity>:
  match found:
    case Found{judged, used, ids}:
      Tables.Table.read(Lint.Quantity, used, id)

def Found.node(found: Found, entry: U32) -> Maybe<&2, U32>:
  match found:
    case Found{judged, used, ids}:
      Tables.Table.read(U32, ids, entry)

def Found.judge(found: Found, +id: U32, j: Noted) -> Found:
  match found:
    case Found{+judged, used, ids}:
      Found{
        Tables.Table.set(
          List<&2, Noted>,
          judged,
          id,
          j
            <> Maybe.default(
              &2,
              List<&2, Noted>,
              Tables.Table.read(List<&2, Noted>, judged, id),
              []
            )
        ),
        used,
        ids
      }

def Found.bind(found: Found, entry: U32, id: U32) -> Found:
  match found:
    case Found{judged, used, ids}:
      Found{judged, used, Tables.Table.set(U32, ids, entry, id)}

# The most of two quantities, as the checker joins uses.
def Quantity.join(a: Lint.Quantity, b: Lint.Quantity) -> Lint.Quantity:
  match a b:
    case Lint.Many{} _:
      Lint.Many{}
    case _ Lint.Many{}:
      Lint.Many{}
    case Lint.Erased{} _:
      b
    case _ _:
      a

def Found.join(was: Maybe<&2, Lint.Quantity>, quantity: Lint.Quantity) -> Lint.Quantity:
  match was:
    case Some{w}:
      Quantity.join(w, quantity)
    case None{}:
      quantity

# `found` with the binder node `id` used `quantity` times more, as the most of its checked copies.
def Found.use(found: Found, +id: U32, quantity: Lint.Quantity) -> Found:
  match found:
    case Found{judged, +used, ids}:
      Found{
        judged,
        Tables.Table.set(
          Lint.Quantity,
          used,
          id,
          Found.join(Tables.Table.read(Lint.Quantity, used, id), quantity)
        ),
        ids
      }

def Lookup.origins(r: Lookup, span: Span) -> List<&2, Origin>:
  match r:
    case Lookup{origins, binders, scopes, entries}:
      Spots.get(Origin, origins, span)

def Lookup.level(levels: Maybe<&2, List<&2, Maybe<&2, U32>>>, level: Nat) -> Maybe<&2, U32>:
  match levels:
    case Some{ls}:
      Maybe.default(&2, Maybe<&2, U32>, List.get(&2, Maybe<&2, U32>, ls, level), None{})
    case None{}:
      None{}

# The entry at `level` of the scope numbered `scope`, if it has one.
def Lookup.entry(r: Lookup, scope: U32, level: U32) -> Maybe<&2, U32>:
  match r:
    case Lookup{origins, binders, scopes, entries}:
      Lookup.level(Tables.Indexed.get(List<&2, Maybe<&2, U32>>, scopes, scope), U32.to_nat(level))

def Lookup.binder(r: Lookup, bound: Bound) -> Maybe<&2, U32>:
  match r:
    case Lookup{origins, binders, scopes, entries}:
      Binders.get(binders, bound)

def Lookup.info(r: Lookup, entry: U32) -> Maybe<&2, Entry>:
  match r:
    case Lookup{origins, binders, scopes, entries}:
      Tables.Indexed.get(Entry, entries, entry)

# Binders
# =======
def Origin.binds(name: String, o: Origin) -> Bool:
  match o:
    case Origin{id, syntax, k, target, kids, binder}:
      binds(syntax) && String.eq(k, name)

def Origin.pick(hit: Bool, o: Origin, rest: Maybe<&2, Origin>) -> Maybe<&2, Origin>:
  match hit:
    case True{}:
      Some{o}
    case False{}:
      rest

# The first binder node named `name` of `origins`.
def Origin.find(origins: List<&2, Origin>, +name: String) -> Maybe<&2, Origin>:
  match origins:
    case Nil{}:
      None{}
    case Con{+o, rest}:
      Origin.pick(Origin.binds(name, o), o, Origin.find(rest, name))

# The binder node named `name` read at `span`, if any.
def binder.at(r: Lookup, span: Maybe<&2, Span>, name: String) -> Maybe<&2, Origin>:
  match span:
    case Some{s}:
      Origin.find(Lookup.origins(r, s), name)
    case None{}:
      None{}

def Origin.id(o: Origin) -> U32:
  match o:
    case Origin{id, syntax, name, target, kids, binder}:
      id

def Origin.syntax(o: Origin) -> Lint.Syntax:
  match o:
    case Origin{id, syntax, name, target, kids, binder}:
      syntax

def Span.file(span: Span) -> U32:
  match span:
    case Span{file, beg, end}:
      file

def domain.of(
  binder: Maybe<&2, Origin>,
  span: Maybe<&2, Span>,
  quantity: Lint.Quantity,
  handle: U32,
  scope: U32,
  entry: Maybe<&2, U32>,
  found: Found
) -> Found:
  match binder span entry:
    case Some{+o} Some{s} Some{e}:
      Found.bind(
        Found.judge(
          found,
          Origin.id(o),
          Noted{Lint.OfBinder{}, handle, scope, quantity, Span.file(s)}
        ),
        e,
        Origin.id(o)
      )
    case Some{+o} Some{s} None{}:
      Found.judge(
        found,
        Origin.id(o),
        Noted{Lint.OfBinder{}, handle, scope, quantity, Span.file(s)}
      )
    case Some{+o} None{} Some{e}:
      Found.bind(found, e, Origin.id(o))
    case _ _ _:
      found

# A declaration's binder, as its type opens it: the type it declares, with its quantity, and, as the node its entry is.
def domain(r: Lookup, d: Domain, found: Found) -> Found:
  match d:
    case Domain{name, quantity, +span, handle, scope, entry}:
      domain.of(binder.at(r, span, name), span, quantity, handle, scope, entry, found)

def domains(+r: Lookup, ds: List<&2, Domain>, found: Found) -> Found:
  match ds:
    case Nil{}:
      found
    case Con{d, rest}:
      domains(r, rest, domain(r, d, found))

def signatures(+r: Lookup, ts: List<&2, List<&2, Domain>>, found: Found) -> Found:
  match ts:
    case Nil{}:
      found
    case Con{ds, rest}:
      signatures(r, rest, domains(r, ds, found))

def named.one(binder: Maybe<&2, Origin>, entry: Maybe<&2, U32>, found: Found) -> Found:
  match binder entry:
    case Some{o} Some{e}:
      Found.bind(found, e, Origin.id(o))
    case _ _:
      found

def Judgment.entry(r: Lookup, inner: Maybe<&2, Judgment>, level: U32) -> Maybe<&2, U32>:
  match inner:
    case Some{Judgment{demand, scope, uses}}:
      Lookup.entry(r, scope, level)
    case None{}:
      None{}

# The binder node of each of the binders a lambda, let or forall read at `span` declares at `levels`, by its entry in
# the scope of its body, judged `inner`: each node is its entry's from now on.
def named(
  +r: Lookup,
  +span: Maybe<&2, Span>,
  names: List<&2, String>,
  levels: List<&2, U32>,
  +inner: Maybe<&2, Judgment>,
  found: Found
) -> Found:
  match names levels:
    case Con{k, ks} Con{level, ls}:
      named(
        r,
        span,
        ks,
        ls,
        inner,
        named.one(binder.at(r, span, k), Judgment.entry(r, inner, level), found)
      )
    case _ _:
      found

def Uses.first(uses: List<&2, Use>, level: U32) -> Bool:
  match uses:
    case Con{Use{l, q}, rest}:
      U32.is_eq(l, level)
    case Nil{}:
      False{}

# How often the binder at `level` was used, among `uses`: `hit` says whether the first is its.
def Uses.at(uses: List<&2, Use>, +level: U32, hit: Bool) -> Maybe<&2, Lint.Quantity>:
  match uses hit:
    case Con{Use{l, q}, rest} True{}:
      Some{q}
    case Con{u, +rest} False{}:
      Uses.at(rest, level, Uses.first(rest, level))
    case _ _:
      None{}

def is_parameter(syntax: Lint.Syntax) -> Bool:
  match syntax:
    case Lint.Parameter{}:
      True{}
    case _:
      False{}

def declare.use(used: Maybe<&2, Lint.Quantity>, id: U32, found: Found) -> Found:
  match used:
    case Some{q}:
      Found.use(found, id, q)
    case None{}:
      found

def declare.record(
  hit: Bool,
  id: U32,
  +entry: Maybe<&2, Entry>,
  scope: U32,
  file: U32,
  found: Found
) -> Found:
  match hit entry:
    case True{} Some{Entry{quantity, handle}}:
      Found.judge(found, id, Noted{Lint.OfBinder{}, handle, scope, quantity, file})
    case _ _:
      found

# A binder node a lambda or let at `span` declares, judged `j`: the type and quantity of its entry, unless a signature
# declared it (a parameter with a fact), and how often its judgment closed it.
def declare.one(
  r: Lookup,
  +o: Origin,
  entry: U32,
  +level: U32,
  +span: Maybe<&2, Span>,
  +j: Maybe<&2, Judgment>,
  +found: Found
) -> Found:
  match span j:
    case Some{s} Some{Judgment{demand, scope, uses}}:
      declare.use(
        Uses.at(uses, level, Uses.first(uses, level)),
        Origin.id(o),
        declare.record(
          Bool.not(
            is_parameter(Origin.syntax(o))
          )
            || List.is_empty(&2, Noted, Found.judged(found, Origin.id(o))),
          Origin.id(o),
          Lookup.info(r, entry),
          scope,
          Span.file(s),
          found
        )
      )
    case _ _:
      found

def declare.with(
  r: Lookup,
  binder: Maybe<&2, Origin>,
  entry: Maybe<&2, U32>,
  level: U32,
  span: Maybe<&2, Span>,
  j: Maybe<&2, Judgment>,
  found: Found
) -> Found:
  match binder entry:
    case Some{+o} Some{+e}:
      declare.one(r, o, e, level, span, j, Found.bind(found, e, Origin.id(o)))
    case _ _:
      found

# The binders a lambda or let read at `span`, judged `j`, declares at `levels` (see `named`), with their facts.
def declare(
  +r: Lookup,
  +span: Maybe<&2, Span>,
  names: List<&2, String>,
  levels: List<&2, U32>,
  +j: Maybe<&2, Judgment>,
  +inner: Maybe<&2, Judgment>,
  found: Found
) -> Found:
  match names levels:
    case Con{k, ks} Con{+level, ls}:
      declare(
        r,
        span,
        ks,
        ls,
        j,
        inner,
        declare.with(
          r,
          binder.at(r, span, k),
          Judgment.entry(r, inner, level),
          level,
          span,
          j,
          found
        )
      )
    case _ _:
      found

# Checked terms
# =============

# `u` without the checker's annotations, as Bare: with the handle of the first, and the first judgment, else `up`.
def peel(
  u: Term,
  handle: Maybe<&2, U32>,
  judgment: Maybe<&2, Judgment>,
  up: Maybe<&2, Judgment>
) -> Walk:
  match u:
    case Typed{t, h}:
      peel(t, Maybe.or(&2, U32, handle, Some{h}), judgment, up)
    case Judged{t, j}:
      peel(t, handle, Maybe.or(&2, Judgment, judgment, Some{j}), up)
    case _:
      Bare{u, handle, Maybe.or(&2, Judgment, judgment, up)}

# The judgment of a term: its outermost one.
def judgment(u: Term) -> Maybe<&2, Judgment>:
  match u:
    case Typed{t, h}:
      judgment(t)
    case Judged{t, j}:
      Some{j}
    case _:
      None{}

# The terms right under a checked term, in order: none under a variable (a value it has is a substitution's), and only
# the term an annotation annotates.
def kids(t: Term) -> List<&2, Term>:
  match t:
    case Substitution{i, p, b, s}:
      [b]
    case Let{ks, ls, qs, vs, b, s}:
      Lists.append(&2, Term, vs, [b])
    case Sort{g, s}:
      [g]
    case QuantityMinimum{a, b, s}:
      [a, b]
    case Forall{q, k, i, a, b, s}:
      [a, b]
    case Lambda{k, i, b, q, s}:
      [b]
    case Application{f, x, s}:
      [f, x]
    case TypeApplication{k, xs, s}:
      xs
    case Construction{k, xs, s}:
      xs
    case Elimination{k, h, m, s}:
      [h, m]
    case Equality{a, b, t, s}:
      [a, b, t]
    case Rewrite{e, p, b, s}:
      [e, p, b]
    case Annotation{x, t, s}:
      [x]
    case Typed{t, h}:
      [t]
    case Judged{t, j}:
      [t]
    case _:
      []

def Spans.first(terms: List<&2, Term>, spans: List<&2, Maybe<&2, Span>>) -> Bool:
  match terms spans:
    case Con{t, ts} Con{s, ss}:
      Span.is_eq(Term.span(Term.bare(t)), s)
    case _ _:
      True{}

# Whether each of `terms` was read at its place in `spans`: `ok` says whether the first was.
def Spans.of(terms: List<&2, Term>, spans: List<&2, Maybe<&2, Span>>, ok: Bool) -> Bool:
  match terms spans ok:
    case Nil{} Nil{} _:
      True{}
    case Con{t, +ts} Con{s, +ss} True{}:
      Spans.of(ts, ss, Spans.first(ts, ss))
    case _ _ _:
      False{}

def Spans.same(+terms: List<&2, Term>, +spans: List<&2, Maybe<&2, Span>>) -> Bool:
  Spans.of(terms, spans, Spans.first(terms, spans))

# Whether a construction is the node of `target` whose children were read at `spans` (`hit` says whether it names it).
def Spans.named(hit: Bool, terms: List<&2, Term>, spans: List<&2, Maybe<&2, Span>>) -> Bool:
  match hit:
    case True{}:
      Spans.same(terms, spans)
    case False{}:
      False{}

def Variable.node(n: U32, of: Maybe<&2, U32>) -> Bool:
  match of:
    case Some{m}:
      U32.is_eq(n, m)
    case None{}:
      False{}

def Variable.same(node: Maybe<&2, U32>, entry: Maybe<&2, U32>, found: Found) -> Bool:
  match node entry:
    case None{} None{}:
      True{}
    case Some{n} Some{e}:
      Variable.node(n, Found.node(found, e))
    case _ _:
      False{}

# Whether the variable `name` at `level`, judged in `scope`, is the node `o`, whose name is `k` and binder `binder`:
# the node's binder is the node of the variable's entry.
def Variable.is(
  +r: Lookup,
  found: Found,
  name: String,
  level: U32,
  scope: U32,
  k: String,
  binder: Maybe<&2, Bound>
) -> Bool:
  match binder:
    case Some{bound}:
      String.eq(
        k,
        name
      )
        && Variable.same(Lookup.binder(r, bound), Lookup.entry(r, scope, level), found)
    case None{}:
      False{}

# Whether a checked term, judged in `scope`, is the node `o`: of the kind of its syntax, and, for some kinds, with its
# name, target, children or binder.
def fits(r: Lookup, found: Found, t: Term, scope: U32, o: Origin) -> Bool:
  match t o:
    case Variable{k, i, v, s} Origin{id, Lint.Variable{}, name, target, kids, binder}:
      Variable.is(r, found, k, i, scope, name, binder)
    case Reference{k, s} Origin{id, Lint.Reference{}, name, target, kids, binder}:
      String.eq(target, k)
    case Literal{kind, v, s} Origin{id, Lint.Literal{}, name, target, kids, binder}:
      String.eq(name, v)
    case Lambda{k, i, b, q, s} Origin{id, Lint.Lambda{}, name, target, kids, binder}:
      String.eq(name, k)
    case Forall{q, k, i, a, b, s} Origin{id, Lint.Forall{}, name, target, kids, binder}:
      String.eq(name, k)
    case Construction{k, xs, s} Origin{id, Lint.Construction{}, name, target, kids, binder}:
      Spans.named(String.eq(target, k), xs, kids)
    case TypeApplication{k, xs, s} Origin{id, Lint.TypeApplication{}, name, target, kids, binder}:
      Spans.named(String.eq(target, k), xs, kids)
    case Substitution{i, p, b, s} Origin{id, Lint.Substitution{}, name, target, kids, binder}:
      True{}
    case Let{ks, ls, qs, vs, b, s} Origin{id, Lint.Let{}, name, target, kids, binder}:
      True{}
    case Sort{g, s} Origin{id, Lint.Sort{}, name, target, kids, binder}:
      True{}
    case QuantityType{s} Origin{id, Lint.QuantityType{}, name, target, kids, binder}:
      True{}
    case QuantityLiteral{q, s} Origin{id, Lint.QuantityLiteral{}, name, target, kids, binder}:
      True{}
    case QuantityMinimum{a, b, s} Origin{id, Lint.QuantityMinimum{}, name, target, kids, binder}:
      True{}
    case Elimination{k, h, m, s} Origin{id, Lint.Elimination{}, name, target, kids, binder}:
      True{}
    case Absurd{s} Origin{id, Lint.Absurd{}, name, target, kids, binder}:
      True{}
    case Equality{a, b, c, s} Origin{id, Lint.Equality{}, name, target, kids, binder}:
      True{}
    case Reflexivity{s} Origin{id, Lint.Reflexivity{}, name, target, kids, binder}:
      True{}
    case Rewrite{e, p, b, s} Origin{id, Lint.Rewrite{}, name, target, kids, binder}:
      True{}
    case Hole{k, s} Origin{id, Lint.Hole{}, name, target, kids, binder}:
      True{}
    case Annotation{x, a, s} Origin{id, Lint.Annotation{}, name, target, kids, binder}:
      True{}
    case _ _:
      False{}

def Ref.template(t: Term) -> Bool:
  match t:
    case Reference{k, s}:
      String.contains(k, "~")
    case _:
      False{}

# Whether the arguments are the last children: all of them (`order` compares how many there are), or, for a template's
# instance, those after its `~` arguments.
def calls.skip(
  order: Cmp,
  template: Bool,
  +terms: List<&2, Term>,
  +spans: List<&2, Maybe<&2, Span>>
) -> Bool:
  match order template:
    case EQ{} _:
      Spans.same(terms, spans)
    case GT{} True{}:
      Spans.same(
        terms,
        List.drop(
          &2,
          Maybe<&2, Span>,
          spans,
          Nat.sub(Lists.length(&2, Maybe<&2, Span>, spans), Lists.length(&2, Term, terms))
        )
      )
    case _ _:
      False{}

# Whether a call's head and arguments are the node `o`: they are its children, but the leading ones a template's
# instance took as `~` arguments.
def calls(+head: Term, +args: List<&2, Term>, o: Origin) -> Bool:
  match o:
    case Origin{id, Lint.Application{}, name, target, Con{k, +rest}, binder}:
      Span.is_eq(
        Term.span(head),
        k
      )
        && calls.skip(
          Nat.cmp(Lists.length(&2, Maybe<&2, Span>, rest), Lists.length(&2, Term, args)),
          Ref.template(head),
          args,
          rest
        )
    case _:
      False{}

def record.one(hit: Bool, id: U32, j: Noted, found: Found) -> Found:
  match hit:
    case True{}:
      Found.judge(found, id, j)
    case False{}:
      found

# The facts of the nodes in `here` that a checked term is, with handle `h`, judged `j`, read at `s`.
def record(
  +r: Lookup,
  +t: Term,
  here: List<&2, Origin>,
  +h: U32,
  +j: Judgment,
  +file: U32,
  +found: Found
) -> Found:
  match here j:
    case Nil{} _:
      found
    case Con{+o, rest} Judgment{+demand, +scope, uses}:
      record(
        r,
        t,
        rest,
        h,
        j,
        file,
        record.one(
          fits(r, found, t, scope, o),
          Origin.id(o),
          Noted{Lint.OfTerm{}, h, scope, demand, file},
          found
        )
      )

# The same, for a call: its head and arguments must be the node's children.
def record.call(
  +head: Term,
  +args: List<&2, Term>,
  here: List<&2, Origin>,
  +h: U32,
  +j: Judgment,
  +file: U32,
  found: Found
) -> Found:
  match here j:
    case Nil{} _:
      found
    case Con{+o, rest} Judgment{+demand, +scope, uses}:
      record.call(
        head,
        args,
        rest,
        h,
        j,
        file,
        record.one(
          calls(head, args, o),
          Origin.id(o),
          Noted{Lint.OfTerm{}, h, scope, demand, file},
          found
        )
      )

# The facts of the nodes a checked term at `span`, with handle `h`, judged `j`, is: `call` says how to tell.
def judge(
  +r: Lookup,
  t: Term,
  args: List<&2, Term>,
  call: Bool,
  span: Maybe<&2, Span>,
  h: Maybe<&2, U32>,
  j: Maybe<&2, Judgment>,
  found: Found
) -> Found:
  match call span h j:
    case False{} Some{+s} Some{h} Some{j}:
      record(r, t, Lookup.origins(r, s), h, j, Span.file(s), found)
    case True{} Some{+s} Some{h} Some{j}:
      record.call(t, args, Lookup.origins(r, s), h, j, Span.file(s), found)
    case _ _ _ _:
      found

# The binders a checked term declares (see `declare` and `named`).
def binders(r: Lookup, t: Term, j: Maybe<&2, Judgment>, found: Found) -> Found:
  match t:
    case Lambda{k, i, b, q, s}:
      declare(r, s, [k], [i], j, judgment(b), found)
    case Let{ks, ls, qs, vs, b, s}:
      declare(r, s, ks, ls, j, judgment(b), found)
    case Forall{q, k, i, a, b, s}:
      named(r, s, [k], [i], judgment(b), found)
    case _:
      found

# A call, from its spine (see Term.spine), at `span`, with handle `h`, judged `j`.
def Call.of(
  spine: Term & List<&2, Term>,
  span: Maybe<&2, Span>,
  h: Maybe<&2, U32>,
  j: Maybe<&2, Judgment>
) -> Walk:
  match spine:
    case Tuple{+typed, args}:
      Call{typed, Term.bare(typed), args, span, h, j}

# Walks a checked body: `fuel` bounds its depth.
def walk(fuel: Nat, w: Walk, +r: Lookup, found: Found) -> Found:
  match fuel w:
    case 0n _:
      found
    case 1n++f One{u, up}:
      walk(f, peel(u, None{}, None{}, up), r, found)
    case 1n++f Many{Nil{}, up}:
      found
    case 1n++f Many{Con{u, rest}, +up}:
      walk(f, Many{rest, up}, r, walk(f, One{u, up}, r, found))
    case 1n++f Bare{Application{+fn, +x, +s}, h, j}:
      walk(
        f,
        Call.of(
          Term.spine(4294967295n, Application{fn, x, s}, Application{fn, x, s}, s, [], True{}),
          s,
          h,
          j
        ),
        r,
        found
      )
    case 1n++f Call{typed, head, +args, span, h, +j}:
      walk(f, Many{typed <> args, j}, r, judge(r, head, args, True{}, span, h, j, found))
    case 1n++f Bare{+t, h, +j}:
      walk(
        f,
        Many{kids(t), j},
        r,
        binders(r, t, j, judge(r, t, [], False{}, Term.span(t), h, j, found))
      )

def Declared.body(r: Lookup, body: Maybe<&2, Term>, found: Found) -> Found:
  match body:
    case Some{b}:
      walk(4294967295n, One{b, None{}}, r, found)
    case None{}:
      found

# What the checker found of a declaration: each binder of its type and of its constructors' types, then its checked
# body. A declaration's walk reads only what it found itself: its parameters' facts, and its own entries.
def Declared.found(+r: Lookup, d: Declared) -> Found:
  match d:
    case Declared{name, datatype, bs, cs, body}:
      Declared.body(
        r,
        body,
        signatures(
          r,
          cs,
          domains(r, bs, Found{Tables.TLeaf{None{}}, Tables.TLeaf{None{}}, Tables.TLeaf{None{}}})
        )
      )

# The judgments of a node in two walks, the last first: the second walk's, then the first's.
def Noted.join(a: List<&2, Noted>, b: List<&2, Noted>) -> List<&2, Noted>:
  Lists.append(&2, Noted, b, a)

# The node of an entry: no two walks meet one entry.
def Entry.join(a: U32, b: U32) -> U32:
  a

# What two walks found, the first's first.
def Found.merge(a: Found, b: Found) -> Found:
  match a b:
    case Found{j, u, i} Found{k, v, e}:
      Found{
        Tables.Table.merge(~List<&2, Noted>, ~Noted.join, j, k),
        Tables.Table.merge(~Lint.Quantity, ~Quantity.join, u, v),
        Tables.Table.merge(~U32, ~Entry.join, i, e)
      }

def Found.all(founds: List<&2, Found>, out: Found) -> Found:
  match founds:
    case Nil{}:
      out
    case Con{x, rest}:
      Found.all(rest, Found.merge(out, x))

# What the checker found of a check's nodes: of each declaration, walked in parallel.
def found.of(r: Lookup, declared: List<&2, Declared>) -> Found:
  Found.all(
    Lists.fork(~Lookup, ~Declared, ~Found, ~Declared.found, 64n, r, Lists.Whole{declared}),
    Found{Tables.TLeaf{None{}}, Tables.TLeaf{None{}}, Tables.TLeaf{None{}}}
  )

# Facts
# =====

# A node's facts as their duplicates go: those kept (the last first; the newest is the one the next round tells the
# others from), and those not told yet, in order.
type Dedup is Data:
  Dedup{kept: List<&2, Lint.Fact>, pending: List<&2, Lint.Fact>}

# A source with its nodes' facts, node by node, as their duplicates go.
type Raw is Data:
  Raw{source: Lint.Source, nodes: List<&2, Dedup>}

# What a round leaves: the sources, and whether a node has facts not told yet.
type Round is Data:
  Round{raws: List<&2, Raw>, pending: Bool}

# What a round made of a node, or of a source, and the answers left for the rest.
type Carry<-A: Data> is Data:
  Carry{done: Maybe<&2, A>, answers: List<&2, Lint.Answer>}

def Binder.node(e: U32, node: Maybe<&2, U32>) -> Lint.Binder:
  match node:
    case Some{n}:
      Lint.NodeBinder{n}
    case None{}:
      Lint.EntryBinder{e}

def Binder.of(entry: Maybe<&2, U32>, found: Found) -> Lint.Binder:
  match entry:
    case Some{+e}:
      Binder.node(e, Found.node(found, e))
    case None{}:
      Lint.NoBinder{}

def Binder.all(
  levels: List<&2, Maybe<&2, U32>>,
  +found: Found,
  out: List<&2, Lint.Binder>
) -> List<&2, Lint.Binder>:
  match levels:
    case Nil{}:
      List.reverse(&2, Lint.Binder, out)
    case Con{e, rest}:
      Binder.all(rest, found, Binder.of(e, found) <> out)

def Binder.levels(+found: Found, levels: List<&2, Maybe<&2, U32>>) -> List<&2, Lint.Binder>:
  Binder.all(levels, found, [])

# The binders of each scope, by level: the node each entry is, if the walk met it. Facts of a scope share its list.
def Binder.scopes(r: Lookup, found: Found) -> Tables.Indexed<List<&2, Lint.Binder>>:
  match r:
    case Lookup{origins, binders, scopes, entries}:
      Tables.Indexed.map(
        ~Found,
        ~List<&2, Maybe<&2, U32>>,
        ~List<&2, Lint.Binder>,
        ~Binder.levels,
        found,
        scopes
      )

def Fact.used(role: Lint.Role, used: Maybe<&2, Lint.Quantity>) -> Maybe<&2, Lint.Quantity>:
  match role:
    case Lint.OfBinder{}:
      used
    case Lint.OfTerm{}:
      None{}

def Fact.of(
  scoped: Tables.Indexed<List<&2, Lint.Binder>>,
  check: U32,
  node: Lint.Node,
  used: Maybe<&2, Lint.Quantity>,
  j: Noted
) -> Lint.Fact:
  match j:
    case Noted{+role, handle, +scope, quantity, file}:
      Lint.Fact{
        node,
        role,
        quantity,
        Fact.used(role, used),
        Lint.TypeRef{
          check,
          handle,
          scope,
          file,
          Maybe.default(
            &2,
            List<&2, Lint.Binder>,
            Tables.Indexed.get(List<&2, Lint.Binder>, scoped, scope),
            []
          )
        }
      }

def Fact.all(
  +scoped: Tables.Indexed<List<&2, Lint.Binder>>,
  found: Found,
  +check: U32,
  +node: Lint.Node,
  +used: Maybe<&2, Lint.Quantity>,
  js: List<&2, Noted>,
  out: List<&2, Lint.Fact>
) -> List<&2, Lint.Fact>:
  match js:
    case Nil{}:
      List.reverse(&2, Lint.Fact, out)
    case Con{j, rest}:
      Fact.all(scoped, found, check, node, used, rest, Fact.of(scoped, check, node, used, j) <> out)

def Node.id(node: Lint.Node) -> U32:
  match node:
    case Lint.Node{id, parent, owner, syntax, name, binder, quantity, span, target}:
      id

def Fact.push(facts: List<&2, Lint.Fact>, out: List<&2, Dedup>) -> List<&2, Dedup>:
  match facts:
    case Nil{}:
      out
    case Con{f, rest}:
      Dedup{[f], rest} <> out

def Found.bounds.of(ids: List<&2, U32>, low: U32, high: U32) -> Range:
  match ids:
    case Nil{}:
      Range{low, high}
    case Con{+i, rest}:
      Found.bounds.of(rest, U32.min(low, i), U32.max(high, i))

# The ids the walk judged a node of, from the least to the most; none if it judged none.
def Found.bounds(found: Found) -> Range:
  match found:
    case Found{judged, used, ids}:
      Found.bounds.of(Tables.Table.numbers(List<&2, Noted>, judged, 0, 1, []), 4294967295, 0)

def Range.has(range: Range, +at: U32) -> Bool:
  match range:
    case Range{beg, end}:
      U32.is_le(beg, at) && U32.is_le(at, end)

# The facts of the node `n`, if `hit` (its id is one the walk judged a node of), onto `out`.
def Fact.node(
  hit: Bool,
  scoped: Tables.Indexed<List<&2, Lint.Binder>>,
  +found: Found,
  check: U32,
  +n: Lint.Node,
  out: List<&2, Dedup>
) -> List<&2, Dedup>:
  match hit:
    case True{}:
      Fact.push(
        Fact.all(
          scoped,
          found,
          check,
          n,
          Found.used(found, Node.id(n)),
          Found.judged(found, Node.id(n)),
          []
        ),
        out
      )
    case False{}:
      out

# The facts of each of `nodes` that has any, onto `out` (last first). Only a node whose id is in `bounds` can.
def Fact.nodes(
  +scoped: Tables.Indexed<List<&2, Lint.Binder>>,
  +found: Found,
  +check: U32,
  +bounds: Range,
  nodes: List<&2, Lint.Node>,
  out: List<&2, Dedup>
) -> List<&2, Dedup>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Dedup, out)
    case Con{+n, rest}:
      Fact.nodes(
        scoped,
        found,
        check,
        bounds,
        rest,
        Fact.node(Range.has(bounds, Node.id(n)), scoped, found, check, n, out)
      )

def Raw.all(
  +scoped: Tables.Indexed<List<&2, Lint.Binder>>,
  +found: Found,
  +check: U32,
  +bounds: Range,
  sources: List<&2, Lint.Source>,
  out: List<&2, Raw>
) -> List<&2, Raw>:
  match sources:
    case Nil{}:
      List.reverse(&2, Raw, out)
    case Con{Lint.Source{path, namespace, text, +nodes, facts}, rest}:
      Raw.all(
        scoped,
        found,
        check,
        bounds,
        rest,
        Raw{
          Lint.Source{path, namespace, text, nodes, facts},
          Fact.nodes(scoped, found, check, bounds, nodes, [])
        }
          <> out
      )

# The sources of a passed check, numbered `check`, with what the checker found of their nodes, before duplicates go.
def raw(checked: Checked, syntax: Read, check: U32) -> List<&2, Raw>:
  match checked syntax:
    case Checked{base, frames, declared, scopes, entries, files} Read{sources, origins, binders}:
      +r: Lookup = Lookup{origins, binders, scopes, entries}
      +found: Found = found.of(r, declared)
      Raw.all(Binder.scopes(r, found), found, check, Found.bounds(found), sources, [])

# Duplicates
# ==========

# A node's facts that the checker counts the same (same role and quantity, and the same type) are one: copies of one
# term, as pattern compilation makes them. Of each such set the first stays. A round tells each node's facts not told
# yet from its newest kept fact, all nodes at once; the first left of them is kept next. So a fact is told from each
# kept fact before it, as the server would one by one, in as many rounds as a node keeps facts.
def Role.is_eq(a: Lint.Role, b: Lint.Role) -> Bool:
  match a b:
    case Lint.OfTerm{} Lint.OfTerm{}:
      True{}
    case Lint.OfBinder{} Lint.OfBinder{}:
      True{}
    case _ _:
      False{}

def Quantity.is_eq(a: Lint.Quantity, b: Lint.Quantity) -> Bool:
  match a b:
    case Lint.Erased{} Lint.Erased{}:
      True{}
    case Lint.Once{} Lint.Once{}:
      True{}
    case Lint.Many{} Lint.Many{}:
      True{}
    case Lint.Template{} Lint.Template{}:
      True{}
    case _ _:
      False{}

# Whether two facts of a node could be one: the same role and quantity. Their types tell.
def Fact.alike(a: Lint.Fact, b: Lint.Fact) -> Bool:
  match a b:
    case Lint.Fact{n, r, q, u, t} Lint.Fact{m, s, p, v, w}:
      Role.is_eq(r, s) && Quantity.is_eq(q, p)

def Fact.type(f: Lint.Fact) -> Lint.TypeRef:
  match f:
    case Lint.Fact{node, role, quantity, used, checked}:
      checked

# Whether the first of `facts` could be one with `head`.
def Fact.alike.first(head: Lint.Fact, facts: List<&2, Lint.Fact>) -> Bool:
  match facts:
    case Con{f, rest}:
      Fact.alike(head, f)
    case Nil{}:
      False{}

def Question.push(
  alike: Bool,
  a: Lint.Fact,
  b: Lint.Fact,
  out: List<&2, Lint.Question>
) -> List<&2, Lint.Question>:
  match alike:
    case True{}:
      Lint.Same{Fact.type(a), Fact.type(b)} <> out
    case False{}:
      out

def Pending.questions(
  +head: Lint.Fact,
  pending: List<&2, Lint.Fact>,
  out: List<&2, Lint.Question>
) -> List<&2, Lint.Question>:
  match pending:
    case Nil{}:
      out
    case Con{+p, rest}:
      Pending.questions(head, rest, Question.push(Fact.alike(head, p), head, p, out))

def Dedup.questions(
  nodes: List<&2, Dedup>,
  out: List<&2, Lint.Question>
) -> List<&2, Lint.Question>:
  match nodes:
    case Nil{}:
      out
    case Con{Dedup{Con{head, kept}, pending}, rest}:
      Dedup.questions(rest, Pending.questions(head, pending, out))
    case Con{d, rest}:
      Dedup.questions(rest, out)

# The questions of a round, in order: each node's facts not told yet, from its newest kept one, if they could be one.
def questions(raws: List<&2, Raw>, out: List<&2, Lint.Question>) -> List<&2, Lint.Question>:
  match raws:
    case Nil{}:
      List.reverse(&2, Lint.Question, out)
    case Con{Raw{source, nodes}, rest}:
      questions(rest, Dedup.questions(nodes, out))

# The facts not told from `head` yet that its round told apart from it, onto `out` (last first): `alike` says whether
# the first could be one with it, so that its answer is the next.
def Pending.go(
  +head: Lint.Fact,
  pending: List<&2, Lint.Fact>,
  answers: List<&2, Lint.Answer>,
  out: List<&2, Lint.Fact>,
  alike: Bool
) -> Carry<List<&2, Lint.Fact>>:
  match pending answers alike:
    case Con{p, +rest} Con{Lint.Equal{True{}}, more} True{}:
      Pending.go(head, rest, more, out, Fact.alike.first(head, rest))
    case Con{p, +rest} Con{a, more} True{}:
      Pending.go(head, rest, more, p <> out, Fact.alike.first(head, rest))
    case Con{p, +rest} _ False{}:
      Pending.go(head, rest, answers, p <> out, Fact.alike.first(head, rest))
    case _ _ _:
      Carry{Some{List.reverse(&2, Lint.Fact, out)}, answers}

# A node after a round: the first of its facts left is kept.
def Dedup.promote(kept: List<&2, Lint.Fact>, left: Carry<List<&2, Lint.Fact>>) -> Carry<Dedup>:
  match left:
    case Carry{Some{Con{p, rest}}, answers}:
      Carry{Some{Dedup{p <> kept, rest}}, answers}
    case Carry{done, answers}:
      Carry{Some{Dedup{kept, []}}, answers}

def Dedup.advance(d: Dedup, answers: List<&2, Lint.Answer>) -> Carry<Dedup>:
  match d:
    case Dedup{Con{+head, kept}, +pending}:
      Dedup.promote(
        head <> kept,
        Pending.go(head, pending, answers, [], Fact.alike.first(head, pending))
      )
    case Dedup{kept, pending}:
      Carry{Some{Dedup{kept, pending}}, answers}

# A source's nodes after a round, onto `out` (last first): `carry` holds the last node done and the answers left.
def Dedup.all(
  nodes: List<&2, Dedup>,
  carry: Carry<Dedup>,
  out: List<&2, Dedup>
) -> Carry<List<&2, Dedup>>:
  match nodes carry:
    case Nil{} Carry{done, answers}:
      Carry{Some{List.reverse(&2, Dedup, Lists.push(Dedup, done, out))}, answers}
    case Con{d, rest} Carry{done, answers}:
      Dedup.all(rest, Dedup.advance(d, answers), Lists.push(Dedup, done, out))

def Raw.with(source: Lint.Source, nodes: Carry<List<&2, Dedup>>) -> Carry<Raw>:
  match nodes:
    case Carry{Some{n}, answers}:
      Carry{Some{Raw{source, n}}, answers}
    case Carry{None{}, answers}:
      Carry{Some{Raw{source, []}}, answers}

def Raw.advance(raw: Raw, answers: List<&2, Lint.Answer>) -> Carry<Raw>:
  match raw:
    case Raw{source, nodes}:
      Raw.with(source, Dedup.all(nodes, Carry{None{}, answers}, []))

def Dedup.pending(nodes: List<&2, Dedup>) -> Bool:
  match nodes:
    case Nil{}:
      False{}
    case Con{Dedup{kept, Con{p, ps}}, rest}:
      True{}
    case Con{d, rest}:
      Dedup.pending(rest)

def Raw.first(raws: List<&2, Raw>) -> Bool:
  match raws:
    case Con{Raw{source, nodes}, rest}:
      Dedup.pending(nodes)
    case Nil{}:
      False{}

# Whether a node of `raws` has facts not told yet: `hit` says whether one of the first does.
def Raw.pending(raws: List<&2, Raw>, hit: Bool) -> Bool:
  match raws hit:
    case _ True{}:
      True{}
    case Con{r, +rest} False{}:
      Raw.pending(rest, Raw.first(rest))
    case Nil{} False{}:
      False{}

def Round.of(+raws: List<&2, Raw>) -> Round:
  Round{raws, Raw.pending(raws, Raw.first(raws))}

def Round.go(raws: List<&2, Raw>, carry: Carry<Raw>, out: List<&2, Raw>) -> Round:
  match raws carry:
    case Nil{} Carry{done, answers}:
      Round.of(List.reverse(&2, Raw, Lists.push(Raw, done, out)))
    case Con{r, rest} Carry{done, answers}:
      Round.go(rest, Raw.advance(r, answers), Lists.push(Raw, done, out))

# The sources after a round, with `answers`, the answers to its questions, in order.
def advance(raws: List<&2, Raw>, answers: List<&2, Lint.Answer>) -> Round:
  Round.go(raws, Carry{None{}, answers}, [])

def Dedup.facts(nodes: List<&2, Dedup>, out: List<&2, Lint.Fact>) -> List<&2, Lint.Fact>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Fact, out)
    case Con{Dedup{kept, pending}, rest}:
      Dedup.facts(rest, Lists.onto(&2, Lint.Fact, pending, Lists.append(&2, Lint.Fact, kept, out)))

# The sources, each with its facts, node by node, once no node has facts not told.
def finish(raws: List<&2, Raw>, out: List<&2, Lint.Source>) -> List<&2, Lint.Source>:
  match raws:
    case Nil{}:
      List.reverse(&2, Lint.Source, out)
    case Con{Raw{Lint.Source{path, namespace, text, nodes, none}, ds}, rest}:
      finish(rest, Lint.Source{path, namespace, text, nodes, Dedup.facts(ds, [])} <> out)

# Checks
# ======
def Check.malformed(-A: Type) -> IO(A):
  IO.die(A, 1, "bend-lint: the checker's answer is malformed")

def Check.done(check: U32, raws: List<&2, Raw>) -> IO(Program.Check):
  IO.pure(Program.Check, Program.Passed{Lint.Program{finish(raws, [])}, check})

# A passed check's program with its facts, after the rounds of questions that drop a node's duplicates (see
# Duplicates); `fuel` bounds them.
def Check.rounds(fuel: Nat, check: U32, round: Round) -> IO(Program.Check):
  match fuel round:
    case 1n+f Round{+raws, True{}}:
      IO.bind(
        List<&2, Lint.Answer>,
        Program.Check,
        answers(questions(raws, [])),
        got => Check.rounds(f, check, advance(raws, got))
      )
    case _ Round{raws, pending}:
      Check.done(check, raws)

def Check.passed(facts: Bool, +check: U32, +checked: Checked) -> IO(Program.Check):
  match facts:
    case True{}:
      Check.rounds(4294967295n, check, Round.of(raw(checked, Read.of(checked), check)))
    case False{}:
      IO.pure(Program.Check, Program.Passed{Lint.Program{Read.sources(Read.of(checked))}, check})

def Failure.at(message: String, short: String, located: Maybe<&2, Located>) -> Program.Failure:
  match located:
    case Some{Located{span, text}}:
      Program.Failure{short, Some{span}, text}
    case None{}:
      Program.Failure{message, None{}, ""}

def Failure.span(file: String, beg: String, end: String) -> Maybe<&2, Span>:
  do Maybe<&2, Span>:
    f: U32 <- U32.read(file)
    b: U32 <- U32.read(beg)
    e: U32 <- U32.read(end)
    return Span{f, b, e}

def Failure.located(
  checked: Maybe<&2, Checked>,
  span: Maybe<&2, Span>,
  pending: String,
  text: String
) -> Maybe<&2, Located>:
  match checked span:
    case Some{c} Some{s}:
      located(c, s, pending, text)
    case _ _:
      None{}

# Why a check failed, from its `fail` record: Bend's message with and without where, and, if Bend's error says, the
# span, and the file a load did not finish, with its text.
def Failure.of(checked: Maybe<&2, Checked>, fields: List<&2, String>) -> Program.Failure:
  match fields:
    case Con{message, Con{short, Con{file, Con{beg, Con{end, Con{pending, Con{text, Nil{}}}}}}}}:
      Failure.at(
        message,
        short,
        Failure.located(checked, Failure.span(file, beg, end), pending, text)
      )
    case Con{message, rest}:
      Program.Failure{message, None{}, ""}
    case Nil{}:
      Program.Failure{"", None{}, ""}

def Check.parsed(loaded: Bool, checked: Maybe<&2, Checked>) -> Maybe<&2, Lint.Program>:
  match loaded checked:
    case True{} Some{c}:
      Some{Lint.Program{Read.sources(Read.of(c))}}
    case _ _:
      None{}

def Check.failed(
  loaded: Bool,
  read: List<&2, String>,
  fail: List<&2, String>,
  +checked: Maybe<&2, Checked>
) -> IO(Program.Check):
  IO.pure(
    Program.Check,
    Program.Failed{Failure.of(checked, fail), read, Check.parsed(loaded, checked)}
  )

def Check.ok(facts: Bool, check: U32, checked: Maybe<&2, Checked>) -> IO(Program.Check):
  match checked:
    case Some{c}:
      Check.passed(facts, check, c)
    case None{}:
      Check.malformed(Program.Check)

# What an answer says: the check's number and program; or why and where the check failed, the files it read, and, if it
# loaded them, the program of what it parsed, without facts.
def Check.of(facts: Bool, a: Dumped) -> IO(Program.Check):
  match a:
    case Dumped{Some{n}, base, loaded, read, None{}, stack}:
      Check.ok(facts, n, Checked.of(base, stack))
    case Dumped{None{}, base, +loaded, read, Some{fail}, stack}:
      Check.failed(loaded, List.reverse(&2, String, read), fail, Checked.of(base, stack))
    case _:
      Check.malformed(Program.Check)

def Check.request(path: String, facts: Bool, wanted: List<&2, String>) -> List<&2, String>:
  match facts:
    case True{}:
      "check" <> path <> "facts" <> wanted
    case False{}:
      ["check", path, "syntax"]

# Checks the file at `path`: with `facts`, the checker's facts on the files at `wanted` (on each file, if none).
def check(path: String, +facts: Bool, wanted: List<&2, String>) -> IO(Program.Check):
  IO.bind(
    List<&2, List<&2, String>>,
    Program.Check,
    ask(Check.request(path, facts, wanted)),
    records => Check.of(facts, Dumped.of(records))
  )

# Frees what the server holds for the passed check numbered `check`: no rule asks about its types again.
def forget(check: U32) -> IO(Unit):
  IO.bind(
    List<&2, List<&2, String>>,
    Unit,
    ask(["forget", U32.show(check)]),
    records => IO.pure(Unit, Unit{})
  )
