# The fixes a run makes with `--fix-dangerously`: no fix is proven to keep the program until Bend's checker is Bend.
import Base
import ../files/main.bend as Files
import ../shared/lists.bend as Lists
import ../shared/names.bend as Names
import ../shared/strings.bend as Strings
import ../text/main.bend as Text
import ./lint.bend as Lint

# Types
# =====
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
  Given{edit: Text.Edit}
  Sought{spot: Spot}

# A spot, after the text is read: its fix's number, and its edit, if the text writes the name there.
type Spotted is Data:
  Spotted{fix: U32, edit: Maybe<&2, Text.Edit>}

# What resolving renames reads, built once per run: each declaration, by where its node is written (`Lookup.key`); and
# the names each own file takes, as keys (`Taken.key`).
type Lookup is Data:
  Lookup{declarations: Map<&2, Maybe<&2, Lint.Declaration>>, taken: Set()}

# The edits planned so far, last first; how many fixes they make; and their spans, by file.
type Plan is Data:
  Plan{edits: List<&2, Text.Edit>, fixes: U32, spans: Map<&2, Text.Spans>}

# Functions
# =========

# Names
# -----
# Whether a node of this syntax is an import, whose name is its alias.
def Syntax.is_alias(syntax: Lint.Syntax) -> Bool:
  match syntax:
    case Lint.Import{t}:
      True{}
    case _:
      False{}

# Where `old` is in `name`, a name a node writes: its first part, if `alias`; else its last.
def Part.of(alias: Bool, +name: String, +old: String) -> Maybe<&2, Part>:
  match alias:
    case True{}:
      Lists.when(
        Part,
        String.eq(name, old) || String.starts_with(name, old ++ "."),
        Part{0, U32.from_nat(String.length(old))}
      )
    case False{}:
      Lists.when(
        Part,
        String.eq(Strings.after_last(name, '.'), old),
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
    case Lint.Node{s, +name, Some{Lint.Span{path, beg, end}}, k, f}:
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

def Taken.node(+path: String, +node: Lint.Node, out: Set()) -> Set():
  match node:
    case Lint.Node{Lint.Import{t}, name, sp, k, f}:
      Set.add(
        Set.add(out, Taken.key(path, True{}, name)),
        Taken.key(path, False{}, Strings.after_last(name, '.'))
      )
    case Lint.Node{s, name, sp, k, f}:
      Set.add(out, Taken.key(path, False{}, Strings.after_last(name, '.')))

def Taken.files(sources: List<&2, Lint.Source>, out: Set()) -> Set():
  match sources:
    case Nil{}:
      out
    case Con{Lint.Source{path, namespace, text, nodes}, rest}:
      Taken.files(rest, Lint.fold(~String, ~Set(), ~Taken.node, path, nodes, out))

# Whether a rename may write `to`. A Rename (`whole`) may, of a name no file but its own can use (not a `global` one),
# if its file does not take `to` already (`taken`). RenameUses points the uses at a name the program declares, and
# leaves the declaration as it is.
def Rename.is_allowed(
  whole: Bool,
  global: Bool,
  alias: Bool,
  to: String,
  span: Maybe<&2, Lint.Span>,
  taken: Set()
) -> Bool:
  match whole global span:
    case False{} _ _:
      True{}
    case True{} True{} _:
      False{}
    case True{} False{} Some{Lint.Span{path, beg, end}}:
      Bool.not(Pair.snd(Set(), Bool, Set.has(taken, Taken.key(path, alias, to))))
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
  taken: Set()
) -> Maybe<&2, List<&2, Change>>:
  match declaration:
    case Some{Lint.Declaration{Lint.Node{+s, +name, +span, k, f}, uses}}:
      +alias = Syntax.is_alias(s)
      Rename.checked(
        Rename.is_allowed(
          whole,
          Maybe.default(&2, Bool, Lint.Syntax.declares(s), False{}),
          alias,
          to,
          span,
          taken
        ),
        Rename.spots(
          Rename.nodes(whole, Lint.Node{s, name, span, k, f}, uses),
          fix,
          alias,
          Bool.pick(String, alias, name, Strings.after_last(name, '.')),
          to,
          Some{[]}
        )
      )
    case None{}:
      None{}

# A declaration's key in a lookup: where it is written.
def Lookup.key(span: Lint.Span) -> String:
  match span:
    case Lint.Span{path, beg, end}:
      path ++ "\t" ++ U32.show(beg) ++ "\t" ++ U32.show(end)

def Lookup.declarations(
  declarations: List<&2, Lint.Declaration>,
  out: Map<&2, Maybe<&2, Lint.Declaration>>
) -> Map<&2, Maybe<&2, Lint.Declaration>>:
  match declarations:
    case Nil{}:
      out
    case Con{Lint.Declaration{Lint.Node{s, n, Some{+sp}, k, f}, uses}, rest}:
      Lookup.declarations(
        rest,
        Map.set(
          &2,
          Maybe<&2, Lint.Declaration>,
          out,
          Lookup.key(sp),
          Some{Lint.Declaration{Lint.Node{s, n, Some{sp}, k, f}, uses}}
        )
      )
    case Con{d, rest}:
      Lookup.declarations(rest, out)

def Lookup.find(lookup: Lookup, at: Lint.Span) -> Maybe<&2, Lint.Declaration>:
  match lookup:
    case Lookup{declarations, taken}:
      Pair.snd(
        Map<&2, Maybe<&2, Lint.Declaration>>,
        Maybe<&2, Lint.Declaration>,
        Map.get(Maybe<&2, Lint.Declaration>, None{}, declarations, Lookup.key(at))
      )

def Lookup.taken(lookup: Lookup) -> Set():
  match lookup:
    case Lookup{declarations, taken}:
      taken

# Finding names in the text
# -------------------------
def Spot.path(spot: Spot) -> String:
  match spot:
    case Spot{fix, path, beg, name, part, text}:
      path

def Spot.beg(spot: Spot) -> U32:
  match spot:
    case Spot{fix, path, beg, name, part, text}:
      beg

def Spot.is_le(a: Spot, b: Spot) -> Bool:
  U32.is_le(Spot.beg(a), Spot.beg(b))

def Spotted.is_le(a: Spotted, b: Spotted) -> Bool:
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

def Spot.edit(
  spelled: Bool,
  path: String,
  +at: U32,
  part: Part,
  text: String
) -> Maybe<&2, Text.Edit>:
  match spelled part:
    case True{} Part{from, until}:
      Some{Text.Edit{path, (at + from: U32), (at + until: U32), text}}
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
      Spot.walk(Lists.sort(~Spot, ~Spot.is_le, spots), t, 0, out)
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
          Names.Group.get(Spot, groups, path),
          out
        )
      )

# Plans
# -----
def Operation.changes(op: Lint.Operation, fix: U32, +lookup: Lookup) -> Maybe<&2, List<&2, Change>>:
  match op:
    case Lint.Replace{Lint.Span{path, beg, end}, text}:
      Some{[Given{Text.Edit{path, beg, end, text}}]}
    case Lint.Rename{at, to}:
      Rename.plan(True{}, Lookup.find(lookup, at), to, fix, Lookup.taken(lookup))
    case Lint.RenameUses{at, to}:
      Rename.plan(False{}, Lookup.find(lookup, at), to, fix, Lookup.taken(lookup))

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
          return Lists.onto(&2, Change, more, changes))

def Plan.firsts(founds: List<&2, Lint.Found>, out: List<&2, Lint.Fix>) -> List<&2, Lint.Fix>:
  match founds:
    case Nil{}:
      List.reverse(&2, Lint.Fix, out)
    case Con{Lint.Found{rule, Lint.Finding{s, span, message, Con{fix, more}}}, rest}:
      Plan.firsts(rest, fix <> out)
    case Con{found, rest}:
      Plan.firsts(rest, out)

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
      Fix.any(~f, rest, Lists.any(~Lint.Operation, ~f, ops))

def Lookup.index(
  need: Bool,
  declarations: List<&2, Lint.Declaration>
) -> Map<&2, Maybe<&2, Lint.Declaration>>:
  match need:
    case True{}:
      Lookup.declarations(declarations, Map.new(&2, Maybe<&2, Lint.Declaration>))
    case False{}:
      Map.new(&2, Maybe<&2, Lint.Declaration>)

def Lookup.names(need: Bool, sources: List<&2, Lint.Source>) -> Set():
  match need:
    case True{}:
      Taken.files(Lint.Program.own(sources), Set.new())
    case False{}:
      Set.new()

# What resolving the renames of `fixes` reads, built once: the declarations by where they are written, if one renames
# anything; the names each own file takes, if one renames a declaration.
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
  edit: Text.Edit,
  out: Maybe<&2, List<&2, Text.Edit>>
) -> Maybe<&2, List<&2, Text.Edit>>:
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
  out: Maybe<&2, List<&2, Text.Edit>>
) -> Maybe<&2, List<&2, Text.Edit>>:
  match changes:
    case Nil{}:
      out
    case Con{Given{+edit}, rest}:
      Change.edits(
        rest,
        texts,
        Change.given(
          Pair.snd(Map<&2, String>, Bool, Map.has(&2, String, texts, Text.Edit.path(edit))),
          edit,
          out
        )
      )
    case Con{Sought{spot}, rest}:
      Change.edits(rest, texts, out)

def Spotted.is_mine(spotted: List<&2, Spotted>, fix: U32) -> Bool:
  match spotted:
    case Con{Spotted{f, edit}, rest}:
      U32.is_eq(f, fix)
    case Nil{}:
      False{}

def Spotted.add(
  edit: Maybe<&2, Text.Edit>,
  out: Maybe<&2, List<&2, Text.Edit>>
) -> Maybe<&2, List<&2, Text.Edit>>:
  do Maybe<&2, List<&2, Text.Edit>>:
    edits: List<&2, Text.Edit> <- out
    e: Text.Edit <- edit
    return e <> edits

# The edits of fix `fix`'s spots, first in `spotted` (sorted by fix), onto `out`, with the spots after them. `mine` says
# whether the first spot is the fix's; none if the text does not write the name at one of them.
def Spotted.take(
  spotted: List<&2, Spotted>,
  +fix: U32,
  mine: Bool,
  out: Maybe<&2, List<&2, Text.Edit>>
) -> Maybe<&2, List<&2, Text.Edit>>
  & List<&2, Spotted>:
  match spotted mine:
    case Con{Spotted{f, edit}, +rest} True{}:
      Spotted.take(rest, fix, Spotted.is_mine(rest, fix), Spotted.add(edit, out))
    case _ _:
      (out, spotted)

# Spans
# -----
def Spans.of(spans: Map<&2, Text.Spans>, path: String) -> Text.Spans:
  Pair.snd(Map<&2, Text.Spans>, Text.Spans, Map.get(Text.Spans, Text.SLeaf{}, spans, path))

def Spans.clashes(edits: List<&2, Text.Edit>, spans: Map<&2, Text.Spans>) -> Bool:
  match edits:
    case Con{Text.Edit{path, beg, end, text}, rest}:
      Text.Spans.touches(Spans.of(spans, path), beg, end)
    case Nil{}:
      False{}

# The planned spans with each of `edits`, if none touches a planned one or another: `clash` says whether the first
# does.
def Spans.with(
  edits: List<&2, Text.Edit>,
  +spans: Map<&2, Text.Spans>,
  clash: Bool
) -> Maybe<&2, Map<&2, Text.Spans>>:
  match edits clash:
    case Nil{} _:
      Some{spans}
    case _ True{}:
      None{}
    case Con{Text.Edit{+path, +beg, +end, text}, +rest} False{}:
      +next = Map.set(
        &2,
        Text.Spans,
        spans,
        path,
        Text.Spans.add(
          Spans.of(spans, path),
          beg,
          end,
          Text.Spans.cmp(Spans.of(spans, path), beg, end)
        )
      )
      Spans.with(rest, next, Spans.clashes(rest, next))

def Plan.add(spans: Maybe<&2, Map<&2, Text.Spans>>, edits: List<&2, Text.Edit>, plan: Plan) -> Plan:
  match spans plan:
    case None{} _:
      plan
    case Some{taken} Plan{kept, n, old}:
      Plan{Lists.onto(&2, Text.Edit, edits, kept), (n + 1: U32), taken}

# The plan with a fix's edits, if the linter can make it, and none of its edits touches a planned one or another.
def Plan.fix(edits: Maybe<&2, List<&2, Text.Edit>>, +plan: Plan) -> Plan:
  match edits plan:
    case Some{+es} Plan{kept, n, +spans}:
      Plan.add(Spans.with(es, spans, Spans.clashes(es, spans)), es, plan)
    case None{} _:
      plan

def Works.step(
  work: Maybe<&2, List<&2, Change>>,
  texts: Map<&2, String>,
  taken: Maybe<&2, List<&2, Text.Edit>> & List<&2, Spotted>,
  out: List<&2, Maybe<&2, List<&2, Text.Edit>>>
) -> List<&2, Spotted>
  & List<&2, Maybe<&2, List<&2, Text.Edit>>>:
  match work taken:
    case Some{changes} Tuple{found, rest}:
      (rest, Change.edits(changes, texts, found) <> out)
    case None{} Tuple{found, rest}:
      (rest, None{} <> out)

# The edits of `works`, the fixes numbered from `fix`, in order; `state` holds the spots read (sorted by fix) and the
# edits so far (last first).
def Works.go(
  works: List<&2, Maybe<&2, List<&2, Change>>>,
  +fix: U32,
  +texts: Map<&2, String>,
  state: List<&2, Spotted> & List<&2, Maybe<&2, List<&2, Text.Edit>>>
) -> List<&2, Maybe<&2, List<&2, Text.Edit>>>:
  match works state:
    case Nil{} Tuple{spotted, out}:
      List.reverse(&2, Maybe<&2, List<&2, Text.Edit>>, out)
    case Con{w, rest} Tuple{+spotted, out}:
      Works.go(
        rest,
        (fix + 1: U32),
        texts,
        Works.step(
          w,
          texts,
          Spotted.take(spotted, fix, Spotted.is_mine(spotted, fix), Some{[]}),
          out
        )
      )

def texts(sources: List<&2, Lint.Source>, out: Map<&2, String>) -> Map<&2, String>:
  match sources:
    case Nil{}:
      out
    case Con{Lint.Source{path, namespace, text, nodes}, rest}:
      texts(rest, Map.set(&2, String, out, path, text))

# The edits of each of `fixes`, in order; None for a fix the linter cannot make: an operation it refuses, an edit in a
# file a fix may not edit, or a rename of a name the text does not write where a use is. Each file a rename changes is
# read once, for all the fixes.
def edits(
  +fixes: List<&2, Lint.Fix>,
  declarations: List<&2, Lint.Declaration>,
  +sources: List<&2, Lint.Source>
) -> List<&2, Maybe<&2, List<&2, Text.Edit>>>:
  +works = Fix.works(fixes, Lookup.of(fixes, declarations, sources), 0, [])
  +own = texts(Lint.Program.own(sources), Map.new(&2, String))
  +groups = Names.Group.of(~Spot, ~Spot.path, Fix.spots(works, []), Map.new(&2, List<&2, Spot>))
  Works.go(
    works,
    0,
    own,
    (
      Lists.sort(
        ~Spotted,
        ~Spotted.is_le,
        Spot.read_all(Map.keys(&2, List<&2, Spot>, groups), groups, own, [])
      ),
      []
    )
  )

# The plan of `edits`, in order: each fix the linter can make, whose edits touch no earlier fix's.
def Plan.fold(edits: List<&2, Maybe<&2, List<&2, Text.Edit>>>, plan: Plan) -> Plan:
  match edits:
    case Nil{}:
      plan
    case Con{e, rest}:
      Plan.fold(rest, Plan.fix(e, plan))

# The edits of each finding's first fix, in order, but those the linter cannot make, and those that touch an earlier
# one's.
def Plan.of(
  founds: List<&2, Lint.Found>,
  declarations: List<&2, Lint.Declaration>,
  sources: List<&2, Lint.Source>
) -> Plan:
  Plan.fold(
    edits(Plan.firsts(founds, []), declarations, sources),
    Plan{[], 0, Map.new(&2, Text.Spans)}
  )

# Writing
# -------
def write.done(path: String, written: Bool) -> IO(Unit):
  match written:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 2, "bend-lint: could not write " ++ path)

def write.edited(+path: String, text: String, edits: List<&2, Text.Edit>) -> IO(Unit):
  match edits:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{e, rest}:
      IO.bind(
        Bool,
        Unit,
        Files.write(path, Text.apply(Con{e, rest}, text)),
        w => write.done(path, w)
      )

def write.all(sources: List<&2, Lint.Source>, +groups: Map<&2, List<&2, Text.Edit>>) -> IO(Unit):
  match sources:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{Lint.Source{+path, namespace, text, nodes}, rest}:
      do IO<Unit>:
        write.edited(path, text, Names.Group.get(Text.Edit, groups, path))
        write.all(rest, groups)

# Fixes
# -----
def made(sources: List<&2, Lint.Source>, plan: Plan) -> IO(U32):
  match plan:
    case Plan{edits, n, spans}:
      do IO<U32>:
        write.all(
          sources,
          Names.Group.of(~Text.Edit, ~Text.Edit.path, edits, Map.new(&2, List<&2, Text.Edit>))
        )
        return n

# Makes the fixes of `founds` (in order), if `fixing`, in the program's files (`sources`, whose declarations are
# `declarations`); how many.
def apply(
  fixing: Bool,
  founds: List<&2, Lint.Found>,
  declarations: List<&2, Lint.Declaration>,
  +sources: List<&2, Lint.Source>
) -> IO(U32):
  match fixing:
    case False{}:
      IO.pure(U32, 0)
    case True{}:
      made(sources, Plan.of(founds, declarations, sources))
