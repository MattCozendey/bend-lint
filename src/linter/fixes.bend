# A run's `fixing`: None (no fixes), Some{False{}} (`--fix`) or Some{True{}} (`--fix-dangerously`).
import Base
import ../shared/utils.bend as Utils
import ./directives.bend as Directives
import ./lint.bend as Lint
import ./program.bend as Program

# Types
# =====
type Edit is Data:
  Edit{path: String, beg: U32, end: U32, text: String}

# The part of a name a rename changes: from `from` to `until`, offsets in the name.
type Part is Data:
  Part{from: U32, until: U32}

# Where a rename changes a name: its fix's number; the file and offset where the node that writes the name starts; the
# name, which the text writes there after any sigils and blanks (`+x`, `@-x`); and the part of the name to change, with
# its new text.
type Spot is Data:
  Spot{fix: U32, path: String, beg: U32, name: String, part: Part, text: String}

# What a fix asks for: an edit as given (a Replace's), or a spot to find in the text (a rename's).
type Change is Data:
  Given{edit: Edit}
  Sought{spot: Spot}

# A spot, after the text is read: its fix's number, and its edit, if the text writes the name there.
type Spotted is Data:
  Spotted{fix: U32, edit: Maybe<&2, Edit>}

# What resolving renames reads, built once per run: each declaration, by its node's id; and the names each own file
# takes, as keys (`Taken.key`).
type Lookup is Data:
  Lookup{declarations: Map<&2, Maybe<&2, Lint.Declaration>>, taken: Map<&2, Unit>}

# The edits planned in one file, by place: a balanced (AVL) tree of spans, by start, then end; `height` counts its
# levels. Planned edits never touch, so their ends rise with their starts.
type Spans is Data:
  SLeaf{}
  SNode{height: U32, left: Spans, beg: U32, end: U32, right: Spans}

# The edits planned so far, last first; how many fixes they make; and their spans, by file.
type Plan is Data:
  Plan{edits: List<&2, Edit>, fixes: U32, spans: Map<&2, Spans>}

# Functions
# =========

# Names
# -----
def last.go(s: String, seg: String) -> String:
  match s:
    case SNil{}:
      String.reverse(seg)
    case SCon{'.', rest}:
      last.go(rest, "")
    case SCon{c, rest}:
      last.go(rest, SCon{c, seg})

# The last part of a name, as a rename changes it: `f` of `U.f`.
def last(name: String) -> String:
  last.go(name, "")

# Whether a node of this syntax is an import, whose name is its alias.
def Syntax.alias(syntax: Lint.Syntax) -> Bool:
  match syntax:
    case Lint.Import{}:
      True{}
    case _:
      False{}

# Where `old` is in `name`, a name a node writes: its first part, if `alias`; else its last.
def Part.of(alias: Bool, +name: String, +old: String) -> Maybe<&2, Part>:
  match alias:
    case True{}:
      Utils.when(
        Part,
        String.eq(name, old) || String.starts_with(name, old ++ "."),
        Part{0, U32.from_nat(String.length(old))}
      )
    case False{}:
      Utils.when(
        Part,
        String.eq(last(name), old),
        Part{
          U32.from_nat(Nat.sub(String.length(name), String.length(old))),
          U32.from_nat(String.length(name))
        }
      )

# Renames
# -------

# Where a rename of `old` to `to` changes the name `node` writes; None if the node has no span, or its name has no
# such part.
def Spot.of(fix: U32, node: Lint.Node, alias: Bool, old: String, to: String) -> Maybe<&2, Change>:
  match node:
    case Lint.Node{id, p, o, s, +name, b, q, Some{Lint.Span{path, beg, end}}, t}:
      Maybe.map(
        &2,
        Part,
        Change,
        part => Sought{Spot{fix, path, beg, name, part, to}},
        Part.of(alias, name, old)
      )
    case _:
      None{}

# The changes of a rename of `old` to `to` in each of `nodes`, onto `out`; none if one cannot change.
def Rename.spots(
  nodes: List<&2, Lint.Node>,
  +fix: U32,
  +alias: Bool,
  +old: String,
  +to: String,
  out: Maybe<&2, List<&2, Change>>
) -> Maybe<&2, List<&2, Change>>:
  match nodes:
    case Nil{}:
      out
    case Con{n, rest}:
      Rename.spots(
        rest,
        fix,
        alias,
        old,
        to,
        do Maybe<&2, List<&2, Change>>:
          changes: List<&2, Change> <- out
          c: Change <- Spot.of(fix, n, alias, old, to)
          return c <> changes)

# A name the file at `path` takes, as a key: an import's alias (`alias`), or any name's last part.
def Taken.key(path: String, alias: Bool, name: String) -> String:
  path ++ Bool.pick(String, alias, "\ta\t", "\tn\t") ++ name

def Taken.node(+path: String, node: Lint.Node, out: Map<&2, Unit>) -> Map<&2, Unit>:
  match node:
    case Lint.Node{i, p, o, Lint.Import{}, +name, b, q, sp, t}:
      Map.set(
        &2,
        Unit,
        Map.set(&2, Unit, out, Taken.key(path, True{}, name), Unit{}),
        Taken.key(path, False{}, last(name)),
        Unit{}
      )
    case Lint.Node{i, p, o, s, name, b, q, sp, t}:
      Map.set(&2, Unit, out, Taken.key(path, False{}, last(name)), Unit{})

def Taken.nodes(nodes: List<&2, Lint.Node>, +path: String, out: Map<&2, Unit>) -> Map<&2, Unit>:
  match nodes:
    case Nil{}:
      out
    case Con{n, rest}:
      Taken.nodes(rest, path, Taken.node(path, n, out))

def Taken.files(sources: List<&2, Lint.Source>, out: Map<&2, Unit>) -> Map<&2, Unit>:
  match sources:
    case Nil{}:
      out
    case Con{Lint.Source{path, namespace, text, nodes, facts}, rest}:
      Taken.files(rest, Taken.nodes(nodes, path, out))

# Whether a rename may write `to`. A Rename (`whole`) may, of a name no file but its own can use (not a `global` one),
# if its file does not take `to` already (`taken`). RenameUses points the uses at a name the program declares, and
# leaves the declaration as it is.
def Rename.allowed(
  whole: Bool,
  global: Bool,
  alias: Bool,
  to: String,
  span: Maybe<&2, Lint.Span>,
  taken: Map<&2, Unit>
) -> Bool:
  match whole global span:
    case False{} _ _:
      True{}
    case True{} True{} _:
      False{}
    case True{} False{} Some{Lint.Span{path, beg, end}}:
      Bool.not(Pair.snd(Map<&2, Unit>, Bool, Map.has(&2, Unit, taken, Taken.key(path, alias, to))))
    case True{} False{} None{}:
      False{}

def Rename.checked(
  allowed: Bool,
  changes: Maybe<&2, List<&2, Change>>
) -> Maybe<&2, List<&2, Change>>:
  match allowed:
    case True{}:
      changes
    case False{}:
      None{}

# The nodes a rename changes: the declaration's and its uses' (`whole`), or its uses' alone.
def Rename.nodes(whole: Bool, node: Lint.Node, uses: List<&2, Lint.Node>) -> List<&2, Lint.Node>:
  match whole:
    case True{}:
      node <> uses
    case False{}:
      uses

# The changes of a rename of what `declaration` declares to `to`: of its name, if `whole`, and of each use.
def Rename.plan(
  +whole: Bool,
  declaration: Maybe<&2, Lint.Declaration>,
  +to: String,
  fix: U32,
  taken: Map<&2, Unit>
) -> Maybe<&2, List<&2, Change>>:
  match declaration:
    case Some{Lint.Declaration{Lint.Node{id, p, o, +s, +name, b, q, +span, t}, uses}}:
      +alias = Syntax.alias(s)
      Rename.checked(
        Rename.allowed(
          whole,
          Maybe.default(&2, Bool, Program.Syntax.declares(s), False{}),
          alias,
          to,
          span,
          taken
        ),
        Rename.spots(
          Rename.nodes(whole, Lint.Node{id, p, o, s, name, b, q, span, t}, uses),
          fix,
          alias,
          Bool.pick(String, alias, name, last(name)),
          to,
          Some{[]}
        )
      )
    case None{}:
      None{}

def Lookup.declarations(
  declarations: List<&2, Lint.Declaration>,
  out: Map<&2, Maybe<&2, Lint.Declaration>>
) -> Map<&2, Maybe<&2, Lint.Declaration>>:
  match declarations:
    case Nil{}:
      out
    case Con{Lint.Declaration{Lint.Node{+id, p, o, s, n, b, q, sp, t}, uses}, rest}:
      Lookup.declarations(
        rest,
        Map.set(
          &2,
          Maybe<&2, Lint.Declaration>,
          out,
          U32.show(id),
          Some{Lint.Declaration{Lint.Node{id, p, o, s, n, b, q, sp, t}, uses}}
        )
      )

def Lookup.find(lookup: Lookup, id: U32) -> Maybe<&2, Lint.Declaration>:
  match lookup:
    case Lookup{declarations, taken}:
      Pair.snd(
        Map<&2, Maybe<&2, Lint.Declaration>>,
        Maybe<&2, Lint.Declaration>,
        Map.get(Maybe<&2, Lint.Declaration>, None{}, declarations, U32.show(id))
      )

def Lookup.taken(lookup: Lookup) -> Map<&2, Unit>:
  match lookup:
    case Lookup{declarations, taken}:
      taken

# Finding names in the text
# -------------------------
def Edit.path(edit: Edit) -> String:
  match edit:
    case Edit{path, beg, end, text}:
      path

def Spot.path(spot: Spot) -> String:
  match spot:
    case Spot{fix, path, beg, name, part, text}:
      path

def Spot.beg(spot: Spot) -> U32:
  match spot:
    case Spot{fix, path, beg, name, part, text}:
      beg

def Spot.le(a: Spot, b: Spot) -> Bool:
  U32.is_le(Spot.beg(a), Spot.beg(b))

def Spotted.le(a: Spotted, b: Spotted) -> Bool:
  match a b:
    case Spotted{f, e} Spotted{g, d}:
      U32.is_le(f, g)

# How many sigils and blanks start `s`, onto `n`: what the text may write before a node's name (`+x`, `@-x`).
def sigils(s: String, n: Nat) -> Nat:
  match s:
    case SCon{'@', rest}:
      sigils(rest, 1n+n)
    case SCon{'+', rest}:
      sigils(rest, 1n+n)
    case SCon{'-', rest}:
      sigils(rest, 1n+n)
    case SCon{'~', rest}:
      sigils(rest, 1n+n)
    case SCon{' ', rest}:
      sigils(rest, 1n+n)
    case SCon{'\t', rest}:
      sigils(rest, 1n+n)
    case _:
      n

# Whether no character of a name starts `s`, so a name before it ends there.
def Name.ends(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{+c, rest}:
      Bool.not(Char.is_alpha(c) || Char.is_digit(c) || Char.is_eq(c, '_') || Char.is_eq(c, '.'))

def spells(+s: String, +name: String) -> Bool:
  String.starts_with(s, name) && Name.ends(String.drop(s, String.length(name)))

def Spot.edit(spelled: Bool, path: String, +at: U32, part: Part, text: String) -> Maybe<&2, Edit>:
  match spelled part:
    case True{} Part{from, until}:
      Some{Edit{path, (at + from: U32), (at + until: U32), text}}
    case False{} _:
      None{}

# A spot read in `rest`, the text from where its node starts.
def Spot.read(spot: Spot, +rest: String) -> Spotted:
  match spot:
    case Spot{fix, path, beg, name, part, text}:
      +skip = sigils(rest, 0n)
      Spotted{
        fix,
        Spot.edit(
          spells(String.drop(rest, skip), name),
          path,
          (beg + U32.from_nat(skip): U32),
          part,
          text
        )
      }

# The spots of one file, in order of where they start, read in its text, onto `out`: `rest` is the text from `at` on.
def Spot.walk(
  spots: List<&2, Spot>,
  rest: String,
  at: U32,
  out: List<&2, Spotted>
) -> List<&2, Spotted>:
  match spots:
    case Nil{}:
      out
    case Con{+spot, more}:
      +beg = Spot.beg(spot)
      +here = String.drop(rest, U32.to_nat((beg - at: U32)))
      Spot.walk(more, here, beg, Spot.read(spot, here) <> out)

# Spots in a file a fix may not edit: none is found.
def Spot.missed(spots: List<&2, Spot>, out: List<&2, Spotted>) -> List<&2, Spotted>:
  match spots:
    case Nil{}:
      out
    case Con{Spot{fix, path, beg, name, part, text}, rest}:
      Spot.missed(rest, Spotted{fix, None{}} <> out)

# The spots of one file read in its text, if a fix may edit it, onto `out`.
def Spot.file(
  text: Maybe<&2, String>,
  spots: List<&2, Spot>,
  out: List<&2, Spotted>
) -> List<&2, Spotted>:
  match text:
    case Some{t}:
      Spot.walk(Utils.sort(~Spot, ~Spot.le, spots), t, 0, out)
    case None{}:
      Spot.missed(spots, out)

# The text of the file at `path`, if a fix may edit it (`has`).
def Spot.text(has: Map<&2, String> & Bool, path: String) -> Maybe<&2, String>:
  match has:
    case Tuple{texts, True{}}:
      Some{Pair.snd(Map<&2, String>, String, Map.get(String, "", texts, path))}
    case Tuple{texts, False{}}:
      None{}

# The spots of `groups`, by file (at `paths`), read in their files' texts, one pass over each file, onto `out`.
def Spot.read_all(
  paths: List<&2, String>,
  +groups: Map<&2, List<&2, Spot>>,
  +texts: Map<&2, String>,
  out: List<&2, Spotted>
) -> List<&2, Spotted>:
  match paths:
    case Nil{}:
      out
    case Con{+path, rest}:
      Spot.read_all(
        rest,
        groups,
        texts,
        Spot.file(
          Spot.text(Map.has(&2, String, texts, path), path),
          Utils.Group.get(Spot, groups, path),
          out
        )
      )

# Plans
# -----
def Operation.changes(op: Lint.Operation, fix: U32, +lookup: Lookup) -> Maybe<&2, List<&2, Change>>:
  match op:
    case Lint.Replace{Lint.Span{path, beg, end}, text}:
      Some{[Given{Edit{path, beg, end, text}}]}
    case Lint.Rename{id, to}:
      Rename.plan(True{}, Lookup.find(lookup, id), to, fix, Lookup.taken(lookup))
    case Lint.RenameUses{id, to}:
      Rename.plan(False{}, Lookup.find(lookup, id), to, fix, Lookup.taken(lookup))

def Fix.changes(
  ops: List<&2, Lint.Operation>,
  +fix: U32,
  +lookup: Lookup,
  out: Maybe<&2, List<&2, Change>>
) -> Maybe<&2, List<&2, Change>>:
  match ops:
    case Nil{}:
      out
    case Con{op, rest}:
      Fix.changes(
        rest,
        fix,
        lookup,
        do Maybe<&2, List<&2, Change>>:
          changes: List<&2, Change> <- out
          more: List<&2, Change> <- Operation.changes(op, fix, lookup)
          return Utils.onto(&2, Change, more, changes))

# Safety
# ------
def Comment.key(path: String, beg: U32, end: U32) -> String:
  path ++ "\t" ++ U32.show(beg) ++ "\t" ++ U32.show(end)

# Whether `text` is one comment: a # first, and no line end.
def Comment.is(+text: String) -> Bool:
  String.starts_with(
    text,
    "#"
  )
    && Bool.not(String.contains(text, "\n") || String.contains(text, "\r"))

# Whether an operation writes a comment over a comment: one of `comments`.
def Operation.safe(op: Lint.Operation, comments: Map<&2, Unit>) -> Bool:
  match op:
    case Lint.Replace{Lint.Span{path, beg, end}, text}:
      Comment.is(
        text
      )
        && Pair.snd(Map<&2, Unit>, Bool, Map.has(&2, Unit, comments, Comment.key(path, beg, end)))
    case _:
      False{}

def Fix.safe.go(ops: List<&2, Lint.Operation>, +comments: Map<&2, Unit>, safe: Bool) -> Bool:
  match ops safe:
    case _ False{}:
      False{}
    case Nil{} True{}:
      True{}
    case Con{op, rest} True{}:
      Fix.safe.go(rest, comments, Operation.safe(op, comments))

# Each edit writes a comment over a comment (`comments`, from `safety`).
def Fix.safe(fix: Lint.Fix, comments: Map<&2, Unit>) -> Bool:
  match fix:
    case Lint.Fix{title, Nil{}}:
      False{}
    case Lint.Fix{title, ops}:
      Fix.safe.go(ops, comments, True{})

def Plan.allowed(fixing: Maybe<&2, Bool>, fix: Lint.Fix, comments: Map<&2, Unit>) -> Bool:
  match fixing:
    case None{}:
      False{}
    case Some{False{}}:
      Fix.safe(fix, comments)
    case Some{True{}}:
      True{}

def Plan.firsts(founds: List<&2, Lint.Found>, out: List<&2, Lint.Fix>) -> List<&2, Lint.Fix>:
  match founds:
    case Nil{}:
      List.reverse(&2, Lint.Fix, out)
    case Con{Lint.Found{rule, Lint.Finding{s, span, message, Con{fix, more}}}, rest}:
      Plan.firsts(rest, fix <> out)
    case Con{found, rest}:
      Plan.firsts(rest, out)

# The fixes of `fixes` that `fixing` allows, in order, onto `out`; `comments` says where a safe fix may write.
def Plan.picked(
  fixes: List<&2, Lint.Fix>,
  +fixing: Maybe<&2, Bool>,
  +comments: Map<&2, Unit>,
  out: List<&2, Lint.Fix>
) -> List<&2, Lint.Fix>:
  match fixes:
    case Nil{}:
      List.reverse(&2, Lint.Fix, out)
    case Con{+fix, rest}:
      Plan.picked(
        rest,
        fixing,
        comments,
        Utils.push(Lint.Fix, Utils.when(Lint.Fix, Plan.allowed(fixing, fix, comments), fix), out)
      )

# What each of `fixes` asks for, in order, numbered from `fix`; None for a fix with an operation the linter cannot
# make.
def Fix.works(
  fixes: List<&2, Lint.Fix>,
  +lookup: Lookup,
  +fix: U32,
  out: List<&2, Maybe<&2, List<&2, Change>>>
) -> List<&2, Maybe<&2, List<&2, Change>>>:
  match fixes:
    case Nil{}:
      List.reverse(&2, Maybe<&2, List<&2, Change>>, out)
    case Con{Lint.Fix{title, ops}, rest}:
      Fix.works(rest, lookup, (fix + 1: U32), Fix.changes(ops, fix, lookup, Some{[]}) <> out)

def Operation.renames(op: Lint.Operation) -> Bool:
  match op:
    case Lint.Replace{span, text}:
      False{}
    case _:
      True{}

def Operation.renames_whole(op: Lint.Operation) -> Bool:
  match op:
    case Lint.Rename{node, to}:
      True{}
    case _:
      False{}

def Fix.any(~f: Lint.Operation -> Bool, fixes: List<&2, Lint.Fix>, found: Bool) -> Bool:
  match fixes found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{Lint.Fix{title, ops}, rest} False{}:
      Fix.any(~f, rest, Utils.any(~Lint.Operation, ~f, ops))

def Lookup.index(
  need: Bool,
  declarations: List<&2, Lint.Declaration>
) -> Map<&2, Maybe<&2, Lint.Declaration>>:
  match need:
    case True{}:
      Lookup.declarations(declarations, Map.new(&2, Maybe<&2, Lint.Declaration>))
    case False{}:
      Map.new(&2, Maybe<&2, Lint.Declaration>)

def Lookup.names(need: Bool, sources: List<&2, Lint.Source>) -> Map<&2, Unit>:
  match need:
    case True{}:
      Taken.files(Program.Program.own(sources), Map.new(&2, Unit))
    case False{}:
      Map.new(&2, Unit)

# What resolving the renames of `fixes` reads, built once: the declarations by id, if one renames anything; the names
# each own file takes, if one renames a declaration.
def Lookup.of(
  +fixes: List<&2, Lint.Fix>,
  declarations: List<&2, Lint.Declaration>,
  sources: List<&2, Lint.Source>
) -> Lookup:
  Lookup{
    Lookup.index(Fix.any(~Operation.renames, fixes, False{}), declarations),
    Lookup.names(Fix.any(~Operation.renames_whole, fixes, False{}), sources)
  }

def Change.spots(changes: List<&2, Change>, out: List<&2, Spot>) -> List<&2, Spot>:
  match changes:
    case Nil{}:
      out
    case Con{Sought{spot}, rest}:
      Change.spots(rest, spot <> out)
    case Con{Given{edit}, rest}:
      Change.spots(rest, out)

def Fix.spots(works: List<&2, Maybe<&2, List<&2, Change>>>, out: List<&2, Spot>) -> List<&2, Spot>:
  match works:
    case Nil{}:
      out
    case Con{Some{changes}, rest}:
      Fix.spots(rest, Change.spots(changes, out))
    case Con{None{}, rest}:
      Fix.spots(rest, out)

def Change.given(
  may: Bool,
  edit: Edit,
  out: Maybe<&2, List<&2, Edit>>
) -> Maybe<&2, List<&2, Edit>>:
  match may out:
    case True{} Some{edits}:
      Some{edit <> edits}
    case _ _:
      None{}

# The edits of `changes` as given, onto `out`, the edits of their spots; none if one is in a file a fix may not edit
# (not among `texts`).
def Change.edits(
  changes: List<&2, Change>,
  +texts: Map<&2, String>,
  out: Maybe<&2, List<&2, Edit>>
) -> Maybe<&2, List<&2, Edit>>:
  match changes:
    case Nil{}:
      out
    case Con{Given{+edit}, rest}:
      Change.edits(
        rest,
        texts,
        Change.given(
          Pair.snd(Map<&2, String>, Bool, Map.has(&2, String, texts, Edit.path(edit))),
          edit,
          out
        )
      )
    case Con{Sought{spot}, rest}:
      Change.edits(rest, texts, out)

def Spotted.mine(spotted: List<&2, Spotted>, fix: U32) -> Bool:
  match spotted:
    case Con{Spotted{f, edit}, rest}:
      U32.is_eq(f, fix)
    case Nil{}:
      False{}

def Spotted.add(edit: Maybe<&2, Edit>, out: Maybe<&2, List<&2, Edit>>) -> Maybe<&2, List<&2, Edit>>:
  do Maybe<&2, List<&2, Edit>>:
    edits: List<&2, Edit> <- out
    e: Edit <- edit
    return e <> edits

# The edits of fix `fix`'s spots, first in `spotted` (sorted by fix), onto `out`, with the spots after them. `mine` says
# whether the first spot is the fix's; none if the text does not write the name at one of them.
def Spotted.take(
  spotted: List<&2, Spotted>,
  +fix: U32,
  mine: Bool,
  out: Maybe<&2, List<&2, Edit>>
) -> Maybe<&2, List<&2, Edit>>
  & List<&2, Spotted>:
  match spotted mine:
    case Con{Spotted{f, edit}, +rest} True{}:
      Spotted.take(rest, fix, Spotted.mine(rest, fix), Spotted.add(edit, out))
    case _ _:
      (out, spotted)

# Spans
# -----
def Spans.height(t: Spans) -> U32:
  match t:
    case SLeaf{}:
      0
    case SNode{h, l, b, e, r}:
      h

# The node over `l` and `r`, whose heights differ by one at most.
def Spans.node(+l: Spans, b: U32, e: U32, +r: Spans) -> Spans:
  +hl = Spans.height(l)
  +hr = Spans.height(r)
  SNode{(Bool.pick(U32, U32.is_ge(hl, hr), hl, hr) + 1: U32), l, b, e, r}

def Spans.lean_left.by(
  outer: Bool,
  ll: Spans,
  lb: U32,
  le: U32,
  lr: Spans,
  b: U32,
  e: U32,
  r: Spans
) -> Spans:
  match outer lr:
    case False{} SNode{h, lrl, lrb, lre, lrr}:
      Spans.node(Spans.node(ll, lb, le, lrl), lrb, lre, Spans.node(lrr, b, e, r))
    case _ _:
      Spans.node(ll, lb, le, Spans.node(lr, b, e, r))

# The node over `l` and `r`, where `l` is two levels higher: turned right, after its left turns left if its inner side
# is the higher.
def Spans.lean_left(l: Spans, b: U32, e: U32, r: Spans) -> Spans:
  match l:
    case SNode{h, +ll, lb, le, +lr}:
      Spans.lean_left.by(U32.is_ge(Spans.height(ll), Spans.height(lr)), ll, lb, le, lr, b, e, r)
    case SLeaf{}:
      Spans.node(SLeaf{}, b, e, r)

def Spans.lean_right.by(
  outer: Bool,
  l: Spans,
  b: U32,
  e: U32,
  rl: Spans,
  rb: U32,
  re: U32,
  rr: Spans
) -> Spans:
  match outer rl:
    case False{} SNode{h, rll, rlb, rle, rlr}:
      Spans.node(Spans.node(l, b, e, rll), rlb, rle, Spans.node(rlr, rb, re, rr))
    case _ _:
      Spans.node(Spans.node(l, b, e, rl), rb, re, rr)

# The node over `l` and `r`, where `r` is two levels higher: the mirror of `lean_left`.
def Spans.lean_right(l: Spans, b: U32, e: U32, r: Spans) -> Spans:
  match r:
    case SNode{h, +rl, rb, re, +rr}:
      Spans.lean_right.by(U32.is_ge(Spans.height(rr), Spans.height(rl)), l, b, e, rl, rb, re, rr)
    case SLeaf{}:
      Spans.node(l, b, e, SLeaf{})

def Spans.balance.by(left: Bool, right: Bool, l: Spans, b: U32, e: U32, r: Spans) -> Spans:
  match left right:
    case True{} _:
      Spans.lean_left(l, b, e, r)
    case _ True{}:
      Spans.lean_right(l, b, e, r)
    case _ _:
      Spans.node(l, b, e, r)

# The node over `l` and `r`, balanced: their heights may differ by two.
def Spans.balance(+l: Spans, b: U32, e: U32, +r: Spans) -> Spans:
  +hl = Spans.height(l)
  +hr = Spans.height(r)
  Spans.balance.by(U32.is_gt(hl, (hr + 1: U32)), U32.is_gt(hr, (hl + 1: U32)), l, b, e, r)

def Spans.cmp.of(starts: Cmp, e: U32, y: U32) -> Cmp:
  match starts:
    case EQ{}:
      U32.cmp(e, y)
    case LT{}:
      LT{}
    case GT{}:
      GT{}

# How the span from `b` to `e` compares with the root's of `t`, by start, then end; GT past a leaf.
def Spans.cmp(t: Spans, b: U32, e: U32) -> Cmp:
  match t:
    case SNode{h, l, x, y, r}:
      Spans.cmp.of(U32.cmp(b, x), e, y)
    case SLeaf{}:
      GT{}

# `t` with the span from `b` to `e`; `side` is how it compares with the root's.
def Spans.add(t: Spans, +b: U32, +e: U32, side: Cmp) -> Spans:
  match t side:
    case SLeaf{} _:
      SNode{1, SLeaf{}, b, e, SLeaf{}}
    case SNode{h, +l, x, y, r} LT{}:
      Spans.balance(Spans.add(l, b, e, Spans.cmp(l, b, e)), x, y, r)
    case SNode{h, l, x, y, +r} _:
      Spans.balance(l, x, y, Spans.add(r, b, e, Spans.cmp(r, b, e)))

# Whether `t` holds the span from `b` to `e`; `side` is how it compares with the root's.
def Spans.has(t: Spans, +b: U32, +e: U32, side: Cmp) -> Bool:
  match t side:
    case SLeaf{} _:
      False{}
    case SNode{h, l, x, y, r} EQ{}:
      True{}
    case SNode{h, +l, x, y, r} LT{}:
      Spans.has(l, b, e, Spans.cmp(l, b, e))
    case SNode{h, l, x, y, +r} GT{}:
      Spans.has(r, b, e, Spans.cmp(r, b, e))

def Spans.starts_before(t: Spans, e: U32) -> Bool:
  match t:
    case SNode{h, l, x, y, r}:
      U32.is_lt(x, e)
    case SLeaf{}:
      False{}

# The end of the last span of `t` (by start, then end) that starts before `e`, or `found`. `before` says whether the
# root's does. Its end is the furthest of theirs, as ends rise with starts.
def Spans.last(t: Spans, +e: U32, found: Maybe<&2, U32>, before: Bool) -> Maybe<&2, U32>:
  match t before:
    case SLeaf{} _:
      found
    case SNode{h, l, x, y, +r} True{}:
      Spans.last(r, e, Some{y}, Spans.starts_before(r, e))
    case SNode{h, +l, x, y, r} False{}:
      Spans.last(l, e, found, Spans.starts_before(l, e))

def Spans.ends_after(last: Maybe<&2, U32>, b: U32) -> Bool:
  match last:
    case Some{y}:
      U32.is_lt(b, y)
    case None{}:
      False{}

# Whether the span from `b` to `e` touches one of `t`: they share a character, or two insertions are at one place.
def Spans.touch.insertion(insertion: Bool, +t: Spans, +b: U32, +e: U32) -> Bool:
  match insertion:
    case True{}:
      Spans.has(t, b, e, Spans.cmp(t, b, e))
    case False{}:
      False{}

def Spans.touch.of(shares: Bool, t: Spans, +b: U32, +e: U32) -> Bool:
  match shares:
    case True{}:
      True{}
    case False{}:
      Spans.touch.insertion(U32.is_eq(b, e), t, b, e)

def Spans.touch(+t: Spans, +b: U32, +e: U32) -> Bool:
  Spans.touch.of(Spans.ends_after(Spans.last(t, e, None{}, Spans.starts_before(t, e)), b), t, b, e)

def Spans.of(spans: Map<&2, Spans>, path: String) -> Spans:
  Pair.snd(Map<&2, Spans>, Spans, Map.get(Spans, SLeaf{}, spans, path))

def Spans.clash(edits: List<&2, Edit>, spans: Map<&2, Spans>) -> Bool:
  match edits:
    case Con{Edit{path, beg, end, text}, rest}:
      Spans.touch(Spans.of(spans, path), beg, end)
    case Nil{}:
      False{}

# The planned spans with each of `edits`, if none touches a planned one or another: `clash` says whether the first
# does.
def Spans.with(
  edits: List<&2, Edit>,
  +spans: Map<&2, Spans>,
  clash: Bool
) -> Maybe<&2, Map<&2, Spans>>:
  match edits clash:
    case Nil{} _:
      Some{spans}
    case _ True{}:
      None{}
    case Con{Edit{+path, +beg, +end, text}, +rest} False{}:
      +next = Map.set(
        &2,
        Spans,
        spans,
        path,
        Spans.add(Spans.of(spans, path), beg, end, Spans.cmp(Spans.of(spans, path), beg, end))
      )
      Spans.with(rest, next, Spans.clash(rest, next))

def Plan.add(spans: Maybe<&2, Map<&2, Spans>>, edits: List<&2, Edit>, plan: Plan) -> Plan:
  match spans plan:
    case None{} _:
      plan
    case Some{taken} Plan{kept, n, old}:
      Plan{Utils.onto(&2, Edit, edits, kept), (n + 1: U32), taken}

# The plan with a fix's edits, if the linter can make it, and none of its edits touches a planned one or another.
def Plan.fix(edits: Maybe<&2, List<&2, Edit>>, +plan: Plan) -> Plan:
  match edits plan:
    case Some{+es} Plan{kept, n, +spans}:
      Plan.add(Spans.with(es, spans, Spans.clash(es, spans)), es, plan)
    case None{} _:
      plan

def Edits.step(
  work: Maybe<&2, List<&2, Change>>,
  texts: Map<&2, String>,
  taken: Maybe<&2, List<&2, Edit>> & List<&2, Spotted>,
  out: List<&2, Maybe<&2, List<&2, Edit>>>
) -> List<&2, Spotted>
  & List<&2, Maybe<&2, List<&2, Edit>>>:
  match work taken:
    case Some{changes} Tuple{found, rest}:
      (rest, Change.edits(changes, texts, found) <> out)
    case None{} Tuple{found, rest}:
      (rest, None{} <> out)

# The edits of `works`, the fixes numbered from `fix`, in order; `state` holds the spots read (sorted by fix) and the
# edits so far (last first).
def Edits.go(
  works: List<&2, Maybe<&2, List<&2, Change>>>,
  +fix: U32,
  +texts: Map<&2, String>,
  state: List<&2, Spotted> & List<&2, Maybe<&2, List<&2, Edit>>>
) -> List<&2, Maybe<&2, List<&2, Edit>>>:
  match works state:
    case Nil{} Tuple{spotted, out}:
      List.reverse(&2, Maybe<&2, List<&2, Edit>>, out)
    case Con{w, rest} Tuple{+spotted, out}:
      Edits.go(
        rest,
        (fix + 1: U32),
        texts,
        Edits.step(w, texts, Spotted.take(spotted, fix, Spotted.mine(spotted, fix), Some{[]}), out)
      )

def texts(sources: List<&2, Lint.Source>, out: Map<&2, String>) -> Map<&2, String>:
  match sources:
    case Nil{}:
      out
    case Con{Lint.Source{path, namespace, text, nodes, facts}, rest}:
      texts(rest, Map.set(&2, String, out, path, text))

# The edits of each of `fixes`, in order; None for a fix the linter cannot make: an operation it refuses, an edit in a
# file a fix may not edit, or a rename of a name the text does not write where a use is. Each file a rename changes is
# read once, for all the fixes.
def edits(
  +fixes: List<&2, Lint.Fix>,
  declarations: List<&2, Lint.Declaration>,
  +sources: List<&2, Lint.Source>
) -> List<&2, Maybe<&2, List<&2, Edit>>>:
  +works = Fix.works(fixes, Lookup.of(fixes, declarations, sources), 0, [])
  +own = texts(Program.Program.own(sources), Map.new(&2, String))
  +groups = Utils.Group.of(~Spot, ~Spot.path, Fix.spots(works, []), Map.new(&2, List<&2, Spot>))
  Edits.go(
    works,
    0,
    own,
    (
      Utils.sort(
        ~Spotted,
        ~Spotted.le,
        Spot.read_all(Map.keys(&2, List<&2, Spot>, groups), groups, own, [])
      ),
      []
    )
  )

def Safety.ops(ops: List<&2, Lint.Operation>, out: Map<&2, Unit>) -> Map<&2, Unit>:
  match ops:
    case Nil{}:
      out
    case Con{Lint.Replace{Lint.Span{path, beg, end}, text}, rest}:
      Safety.ops(
        rest,
        Map.set(&2, Unit, out, Bool.pick(String, Comment.is(text), path, ""), Unit{})
      )
    case Con{op, rest}:
      Safety.ops(rest, out)

# The files where `fixes` write comments, as keys (and "" for any other), onto `out`.
def Safety.paths(fixes: List<&2, Lint.Fix>, out: Map<&2, Unit>) -> Map<&2, Unit>:
  match fixes:
    case Nil{}:
      out
    case Con{Lint.Fix{title, ops}, rest}:
      Safety.paths(rest, Safety.ops(ops, out))

def Safety.keys(
  comments: List<&2, Directives.Comment>,
  +path: String,
  out: Map<&2, Unit>
) -> Map<&2, Unit>:
  match comments:
    case Nil{}:
      out
    case Con{Directives.Comment{beg, end, line, trailing, body}, rest}:
      Safety.keys(rest, path, Map.set(&2, Unit, out, Comment.key(path, beg, end), Unit{}))

def Safety.scanned(scanned: Directives.Scanned, path: String, out: Map<&2, Unit>) -> Map<&2, Unit>:
  match scanned:
    case Directives.Scanned{comments, lines}:
      Safety.keys(comments, path, out)

# The comments of each own file at `paths`, as keys, onto `out`: one pass over each file.
def Safety.files(
  paths: List<&2, String>,
  +texts: Map<&2, String>,
  out: Map<&2, Unit>
) -> Map<&2, Unit>:
  match paths:
    case Nil{}:
      out
    case Con{+path, rest}:
      Safety.files(
        rest,
        texts,
        Safety.scanned(
          Directives.Scan.of(Pair.snd(Map<&2, String>, String, Map.get(String, "", texts, path))),
          path,
          out
        )
      )

# Where the comments are that `fixes` may write over, as keys, for `Fix.safe`: the comments of each of the program's own
# files where one of them writes a comment. Only those files are read.
def safety(fixes: List<&2, Lint.Fix>, sources: List<&2, Lint.Source>) -> Map<&2, Unit>:
  Safety.files(
    Map.keys(&2, Unit, Safety.paths(fixes, Map.new(&2, Unit))),
    texts(Program.Program.own(sources), Map.new(&2, String)),
    Map.new(&2, Unit)
  )

# Where a safe fix may write, if the run makes the safe fixes alone.
def Plan.safety(
  fixing: Maybe<&2, Bool>,
  fixes: List<&2, Lint.Fix>,
  sources: List<&2, Lint.Source>
) -> Map<&2, Unit>:
  match fixing:
    case Some{False{}}:
      safety(fixes, sources)
    case _:
      Map.new(&2, Unit)

# The plan of `edits`, in order: each fix the linter can make, whose edits touch no earlier fix's.
def Plan.fold(edits: List<&2, Maybe<&2, List<&2, Edit>>>, plan: Plan) -> Plan:
  match edits:
    case Nil{}:
      plan
    case Con{e, rest}:
      Plan.fold(rest, Plan.fix(e, plan))

# The edits of each finding's first fix that `fixing` allows, in order, but those the linter cannot make, and those that
# touch an earlier one's.
def Plan.of(
  founds: List<&2, Lint.Found>,
  +fixing: Maybe<&2, Bool>,
  declarations: List<&2, Lint.Declaration>,
  +sources: List<&2, Lint.Source>
) -> Plan:
  +firsts = Plan.firsts(founds, [])
  Plan.fold(
    edits(
      Plan.picked(firsts, fixing, Plan.safety(fixing, firsts, sources), []),
      declarations,
      sources
    ),
    Plan{[], 0, Map.new(&2, Spans)}
  )

# Writing
# -------
def Edit.le(a: Edit, b: Edit) -> Bool:
  match a b:
    case Edit{p, x, e, t} Edit{q, y, f, u}:
      U32.is_le(x, y)

# `rest`, the text from `at` on, with `edits` (in order) made, after the pieces of `out` (last first). The pieces join
# once, at the end, so the text is copied once, whatever the number of edits.
def Text.edited(edits: List<&2, Edit>, +rest: String, +at: U32, out: List<&2, String>) -> String:
  match edits:
    case Nil{}:
      Utils.joined(rest <> out, "")
    case Con{Edit{p, beg, +end, text}, more}:
      Text.edited(
        more,
        String.drop(rest, U32.to_nat((end - at: U32))),
        end,
        text <> Utils.take(rest, U32.to_nat((beg - at: U32))) <> out
      )

def write.closed(path: String, written: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match written:
    case Tuple{f, Done{u}}:
      File.close(f)
    case Tuple{f, Fail{e}}:
      do IO<Unit>:
        File.close(f)
        IO.die(Unit, 2, "bend-lint: could not write " ++ path)

def write.opened(
  path: String,
  text: String,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Unit):
  match opened:
    case Done{f}:
      IO.bind(
        File & Result<&1, &1, U32 & String, Unit>,
        Unit,
        File.write(f, text),
        w => write.closed(path, w)
      )
    case Fail{e}:
      IO.die(Unit, 2, "bend-lint: could not write " ++ path)

def write(+path: String, text: String) -> IO(Unit):
  IO.bind(
    Result<&1, &1, U32 & String, File>,
    Unit,
    File.open(path, "w"),
    opened => write.opened(path, text, opened)
  )

def write.edited(path: String, text: String, edits: List<&2, Edit>) -> IO(Unit):
  match edits:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{e, rest}:
      write(path, Text.edited(Utils.sort(~Edit, ~Edit.le, Con{e, rest}), text, 0, []))

def write.all(sources: List<&2, Lint.Source>, +groups: Map<&2, List<&2, Edit>>) -> IO(Unit):
  match sources:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{Lint.Source{+path, namespace, text, nodes, facts}, rest}:
      do IO<Unit>:
        write.edited(path, text, Utils.Group.get(Edit, groups, path))
        write.all(rest, groups)

# Fixes
# -----
def made(sources: List<&2, Lint.Source>, plan: Plan) -> IO(U32):
  match plan:
    case Plan{edits, n, spans}:
      do IO<U32>:
        write.all(sources, Utils.Group.of(~Edit, ~Edit.path, edits, Map.new(&2, List<&2, Edit>)))
        return n

# Makes the fixes `fixing` allows, of `founds` (in order), in the program's files (`sources`, whose declarations are
# `declarations`); how many.
def apply(
  +fixing: Maybe<&2, Bool>,
  founds: List<&2, Lint.Found>,
  declarations: List<&2, Lint.Declaration>,
  +sources: List<&2, Lint.Source>
) -> IO(U32):
  match fixing:
    case None{}:
      IO.pure(U32, 0)
    case _:
      made(sources, Plan.of(founds, fixing, declarations, sources))
