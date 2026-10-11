# Fixing: the edits that the fixes of the findings that stay ask for, planned and written to the files. A fix runs
# whole or not at all: one whose operation the linter refuses, or whose edits overlap an earlier fix's, waits for the
# next run.
import Base
import ./lint.bend as Lint
import ./program.bend as Program
import ./shared.bend as Shared

# Types
# =====

# How a run fixes: not at all, with the fixes the linter proves safe, or with every fix.
type Fixing is Data:
  NoFixes{}
  SafeFixes{}
  DangerousFixes{}

# An edit to make: a span of a file, and its new text.
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

# The edits planned so far, last first, and how many fixes they make.
type Plan is Data:
  Plan{edits: List<&2, Edit>, fixes: U32}

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

def Part.when(hit: Bool, from: U32, until: U32) -> Maybe<&2, Part>:
  match hit:
    case True{}:
      Some{Part{from, until}}
    case False{}:
      None{}

# Where `old` is in `name`, a name a node writes: its first part, if `alias`; else its last.
def Part.of(alias: Bool, +name: String, +old: String) -> Maybe<&2, Part>:
  match alias:
    case True{}:
      Part.when(String.eq(name, old) || String.starts_with(name, old ++ "."), 0, U32.from_nat(String.length(old)))
    case False{}:
      Part.when(
        String.eq(last(name), old),
        U32.from_nat(Nat.sub(String.length(name), String.length(old))),
        U32.from_nat(String.length(name))
      )

# Renames
# -------

# Where a rename of `old` to `to` changes the name `node` writes; None if the node has no span, or its name has no
# such part.
def Spot.of(fix: U32, node: Lint.Node, alias: Bool, old: String, to: String) -> Maybe<&2, Change>:
  match node:
    case Lint.Node{id, p, o, s, +name, b, q, Some{Lint.Span{path, beg, end}}, t}:
      Maybe.map(&2, Part, Change, part => Sought{Spot{fix, path, beg, name, part, to}}, Part.of(alias, name, old))
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
          changes : List<&2, Change> <- out
          c : Change <- Spot.of(fix, n, alias, old, to)
          return c <> changes
      )

# Whether `node` takes the name `to`, as a rename would write it: an import's alias, if `alias`; else any name's last
# part.
def Rename.taken(alias: Bool, node: Lint.Node, to: String) -> Bool:
  match alias node:
    case True{} Lint.Node{i, p, o, Lint.Import{}, name, b, q, sp, t}:
      String.eq(name, to)
    case True{} _:
      False{}
    case False{} Lint.Node{i, p, o, s, name, b, q, sp, t}:
      String.eq(last(name), to)

# Whether no node of `nodes` takes the name `to`; `free` holds so far.
def Rename.free(nodes: List<&2, Lint.Node>, +alias: Bool, +to: String, free: Bool) -> Bool:
  match nodes free:
    case _ False{}:
      False{}
    case Nil{} True{}:
      True{}
    case Con{n, rest} True{}:
      Rename.free(rest, alias, to, Bool.not(Rename.taken(alias, n, to)))

# The nodes of the file at `path`; `found` holds them once found.
def Rename.file(sources: List<&2, Lint.Source>, +path: String, found: Maybe<&2, List<&2, Lint.Node>>) -> List<&2, Lint.Node>:
  match sources found:
    case _ Some{nodes}:
      nodes
    case Nil{} None{}:
      []
    case Con{Lint.Source{p, namespace, text, nodes, facts}, rest} None{}:
      Rename.file(rest, path, Shared.lookup.hit(List<&2, Lint.Node>, String.eq(p, path), nodes))

# Whether a rename may write `to`: a Rename (`whole`) if no node of the declaration's file takes it already. RenameUses
# points the uses at a name the program declares.
def Rename.allowed(whole: Bool, alias: Bool, to: String, span: Maybe<&2, Lint.Span>, sources: List<&2, Lint.Source>) -> Bool:
  match whole span:
    case False{} _:
      True{}
    case True{} Some{Lint.Span{path, beg, end}}:
      Rename.free(Rename.file(sources, path, None{}), alias, to, True{})
    case True{} None{}:
      False{}

def Rename.checked(allowed: Bool, changes: Maybe<&2, List<&2, Change>>) -> Maybe<&2, List<&2, Change>>:
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
  sources: List<&2, Lint.Source>
) -> Maybe<&2, List<&2, Change>>:
  match declaration:
    case Some{Lint.Declaration{Lint.Node{id, p, o, +s, +name, b, q, +span, t}, uses}}:
      +alias = Syntax.alias(s)
      Rename.checked(
        Rename.allowed(whole, alias, to, span, sources),
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

# The declaration of the node `id`, among `declarations`; `found` holds it once found.
def Declaration.find(declarations: List<&2, Lint.Declaration>, +id: U32, found: Maybe<&2, Lint.Declaration>) ->
  Maybe<&2, Lint.Declaration>:
  match declarations found:
    case _ Some{d}:
      Some{d}
    case Nil{} None{}:
      None{}
    case Con{Lint.Declaration{Lint.Node{+i, p, o, s, n, b, q, sp, t}, uses}, rest} None{}:
      Declaration.find(
        rest,
        id,
        Shared.lookup.hit(Lint.Declaration, U32.is_eq(i, id), Lint.Declaration{Lint.Node{i, p, o, s, n, b, q, sp, t}, uses})
      )

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

# Whether `s` starts with the whole name `name`.
def spells(+s: String, +name: String) -> Bool:
  String.starts_with(s, name) && Name.ends(String.drop(s, String.length(name)))

def Spot.edit(spelled: Bool, path: String, +at: U32, part: Part, text: String) -> Maybe<&2, Edit>:
  match spelled part:
    case True{} Part{from, until}:
      Some{Edit{path, (at + from : U32), (at + until : U32), text}}
    case False{} _:
      None{}

# A spot read in `rest`, the text from where its node starts.
def Spot.read(spot: Spot, +rest: String) -> Spotted:
  match spot:
    case Spot{fix, path, beg, name, part, text}:
      +skip = sigils(rest, 0n)
      Spotted{fix, Spot.edit(spells(String.drop(rest, skip), name), path, (beg + U32.from_nat(skip) : U32), part, text)}

# The spots of one file, in order of where they start, read in its text, onto `out`: `rest` is the text from `at` on.
def Spot.walk(spots: List<&2, Spot>, rest: String, at: U32, out: List<&2, Spotted>) -> List<&2, Spotted>:
  match spots:
    case Nil{}:
      out
    case Con{+spot, more}:
      +beg = Spot.beg(spot)
      +here = String.drop(rest, U32.to_nat((beg - at : U32)))
      Spot.walk(more, here, beg, Spot.read(spot, here) <> out)

# Spots in a file a fix may not edit: none is found.
def Spot.missed(spots: List<&2, Spot>, out: List<&2, Spotted>) -> List<&2, Spotted>:
  match spots:
    case Nil{}:
      out
    case Con{Spot{fix, path, beg, name, part, text}, rest}:
      Spot.missed(rest, Spotted{fix, None{}} <> out)

# The spots of one file read in its text, if a fix may edit it, onto `out`.
def Spot.file(text: Maybe<&2, String>, spots: List<&2, Spot>, out: List<&2, Spotted>) -> List<&2, Spotted>:
  match text:
    case Some{t}:
      Spot.walk(Shared.sort(~Spot, ~Spot.le, spots), t, 0, out)
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
        Spot.file(Spot.text(Map.has(&2, String, texts, path), path), Shared.Group.get(Spot, groups, path), out)
      )

# Plans
# -----

# The changes of one operation, if the linter can make them.
def Operation.changes(
  op: Lint.Operation,
  fix: U32,
  declarations: List<&2, Lint.Declaration>,
  sources: List<&2, Lint.Source>
) -> Maybe<&2, List<&2, Change>>:
  match op:
    case Lint.Replace{Lint.Span{path, beg, end}, text}:
      Some{[Given{Edit{path, beg, end, text}}]}
    case Lint.Rename{id, to}:
      Rename.plan(True{}, Declaration.find(declarations, id, None{}), to, fix, sources)
    case Lint.RenameUses{id, to}:
      Rename.plan(False{}, Declaration.find(declarations, id, None{}), to, fix, sources)

# The changes of a fix's operations, onto `out`; none if the linter cannot make one.
def Fix.changes(
  ops: List<&2, Lint.Operation>,
  +fix: U32,
  +declarations: List<&2, Lint.Declaration>,
  +sources: List<&2, Lint.Source>,
  out: Maybe<&2, List<&2, Change>>
) -> Maybe<&2, List<&2, Change>>:
  match ops:
    case Nil{}:
      out
    case Con{op, rest}:
      Fix.changes(
        rest,
        fix,
        declarations,
        sources,
        do Maybe<&2, List<&2, Change>>:
          changes : List<&2, Change> <- out
          more : List<&2, Change> <- Operation.changes(op, fix, declarations, sources)
          return Shared.onto(&2, Change, more, changes)
      )

# Whether the linter proves a fix keeps what the program does. Until Bend's checker is Bend it proves none.
def Fix.safe(fix: Lint.Fix) -> Bool:
  False{}

def Plan.allowed(fixing: Fixing, fix: Lint.Fix) -> Bool:
  match fixing:
    case NoFixes{}:
      False{}
    case SafeFixes{}:
      Fix.safe(fix)
    case DangerousFixes{}:
      True{}

def Plan.allow(allowed: Bool, fix: Lint.Fix) -> Maybe<&2, List<&2, Lint.Operation>>:
  match allowed fix:
    case True{} Lint.Fix{title, ops}:
      Some{ops}
    case False{} _:
      None{}

# The operations of the first of `fixes`, if `fixing` allows it.
def Plan.pick(fixing: Fixing, fixes: List<&2, Lint.Fix>) -> Maybe<&2, List<&2, Lint.Operation>>:
  match fixes:
    case Con{+fix, rest}:
      Plan.allow(Plan.allowed(fixing, fix), fix)
    case Nil{}:
      None{}

def Plan.work(
  ops: Maybe<&2, List<&2, Lint.Operation>>,
  fix: U32,
  declarations: List<&2, Lint.Declaration>,
  sources: List<&2, Lint.Source>
) -> Maybe<&2, List<&2, Change>>:
  match ops:
    case Some{os}:
      Fix.changes(os, fix, declarations, sources, Some{[]})
    case None{}:
      None{}

# What each finding's first fix that `fixing` allows asks for, in order, the fixes numbered from `fix`; None for a
# finding without one, or a fix with an operation the linter cannot make.
def Plan.works(
  founds: List<&2, Lint.Found>,
  +fixing: Fixing,
  +declarations: List<&2, Lint.Declaration>,
  +sources: List<&2, Lint.Source>,
  +fix: U32,
  out: List<&2, Maybe<&2, List<&2, Change>>>
) -> List<&2, Maybe<&2, List<&2, Change>>>:
  match founds:
    case Nil{}:
      List.reverse(&2, Maybe<&2, List<&2, Change>>, out)
    case Con{Lint.Found{rule, Lint.Finding{s, span, message, fixes}}, rest}:
      Plan.works(
        rest,
        fixing,
        declarations,
        sources,
        (fix + 1 : U32),
        Plan.work(Plan.pick(fixing, fixes), fix, declarations, sources) <> out
      )

def Change.spots(changes: List<&2, Change>, out: List<&2, Spot>) -> List<&2, Spot>:
  match changes:
    case Nil{}:
      out
    case Con{Sought{spot}, rest}:
      Change.spots(rest, spot <> out)
    case Con{Given{edit}, rest}:
      Change.spots(rest, out)

# The spots of every fix.
def Plan.spots(works: List<&2, Maybe<&2, List<&2, Change>>>, out: List<&2, Spot>) -> List<&2, Spot>:
  match works:
    case Nil{}:
      out
    case Con{Some{changes}, rest}:
      Plan.spots(rest, Change.spots(changes, out))
    case Con{None{}, rest}:
      Plan.spots(rest, out)

def Change.given(may: Bool, edit: Edit, out: Maybe<&2, List<&2, Edit>>) -> Maybe<&2, List<&2, Edit>>:
  match may out:
    case True{} Some{edits}:
      Some{edit <> edits}
    case _ _:
      None{}

# The edits of `changes` as given, onto `out`, the edits of their spots; none if one is in a file a fix may not edit
# (not among `texts`).
def Change.edits(changes: List<&2, Change>, +texts: Map<&2, String>, out: Maybe<&2, List<&2, Edit>>) ->
  Maybe<&2, List<&2, Edit>>:
  match changes:
    case Nil{}:
      out
    case Con{Given{+edit}, rest}:
      Change.edits(rest, texts, Change.given(Pair.snd(Map<&2, String>, Bool, Map.has(&2, String, texts, Edit.path(edit))), edit, out))
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
    edits : List<&2, Edit> <- out
    e : Edit <- edit
    return e <> edits

# The edits of fix `fix`'s spots, first in `spotted` (sorted by fix), onto `out`, with the spots after them. `mine` says
# whether the first spot is the fix's; none if the text does not write the name at one of them.
def Spotted.take(spotted: List<&2, Spotted>, +fix: U32, mine: Bool, out: Maybe<&2, List<&2, Edit>>) ->
  Maybe<&2, List<&2, Edit>> & List<&2, Spotted>:
  match spotted mine:
    case Con{Spotted{f, edit}, +rest} True{}:
      Spotted.take(rest, fix, Spotted.mine(rest, fix), Spotted.add(edit, out))
    case _ _:
      (out, spotted)

# Whether two edits touch: in one file, their spans share a character, or two insertions are at one place.
def Edit.overlap(a: Edit, b: Edit) -> Bool:
  match a b:
    case Edit{+p, +ab, +ae, t} Edit{+q, +bb, +be, u}:
      String.eq(p, q) && Bool.or(Bool.and(U32.is_lt(ab, be), U32.is_lt(bb, ae)), Bool.and(U32.is_eq(ab, bb), U32.is_eq(ae, be)))

# Whether `edit` touches one of `edits`; `found` holds so far.
def Edit.clashes(edits: List<&2, Edit>, +edit: Edit, found: Bool) -> Bool:
  match edits found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{e, rest} False{}:
      Edit.clashes(rest, edit, Edit.overlap(edit, e))

# Whether some edit of `edits` touches another, or one of `kept`; `kept` grows with the edits read.
def Edit.tangled(edits: List<&2, Edit>, +kept: List<&2, Edit>, found: Bool) -> Bool:
  match edits found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{+e, rest} False{}:
      Edit.tangled(rest, e <> kept, Edit.clashes(kept, e, False{}))

def Plan.add(tangled: Bool, edits: List<&2, Edit>, plan: Plan) -> Plan:
  match tangled plan:
    case True{} _:
      plan
    case False{} Plan{kept, n}:
      Plan{Shared.onto(&2, Edit, edits, kept), (n + 1 : U32)}

def Plan.fix(edits: Maybe<&2, List<&2, Edit>>, +plan: Plan) -> Plan:
  match edits plan:
    case Some{+es} Plan{+kept, n}:
      Plan.add(Edit.tangled(es, kept, False{}), es, plan)
    case None{} _:
      plan

def Plan.step(
  work: Maybe<&2, List<&2, Change>>,
  texts: Map<&2, String>,
  taken: Maybe<&2, List<&2, Edit>> & List<&2, Spotted>,
  plan: Plan
) -> List<&2, Spotted> & Plan:
  match work taken:
    case Some{changes} Tuple{found, rest}:
      (rest, Plan.fix(Change.edits(changes, texts, found), plan))
    case None{} Tuple{found, rest}:
      (rest, plan)

# The plan of `works`, the fixes numbered from `fix`, in order; `state` holds the spots read (sorted by fix) and the
# plan so far. A fix joins whole, if its edits are in files a fix may edit (`texts`), the text writes each name where
# its spots are, and its edits touch no earlier fix's.
def Plan.go(works: List<&2, Maybe<&2, List<&2, Change>>>, +fix: U32, +texts: Map<&2, String>, state: List<&2, Spotted> & Plan) ->
  Plan:
  match works state:
    case Nil{} Tuple{spotted, plan}:
      plan
    case Con{w, rest} Tuple{+spotted, plan}:
      Plan.go(
        rest,
        (fix + 1 : U32),
        texts,
        Plan.step(w, texts, Spotted.take(spotted, fix, Spotted.mine(spotted, fix), Some{[]}), plan)
      )

# The text of each file, by path, onto `out`.
def Plan.texts(sources: List<&2, Lint.Source>, out: Map<&2, String>) -> Map<&2, String>:
  match sources:
    case Nil{}:
      out
    case Con{Lint.Source{path, namespace, text, nodes, facts}, rest}:
      Plan.texts(rest, Map.set(&2, String, out, path, text))

# The edits of each finding's first fix that `fixing` allows, in order, but those the linter cannot make, and those that
# touch an earlier one's. Each file a rename changes is read once, for all the fixes.
def Plan.of(
  founds: List<&2, Lint.Found>,
  fixing: Fixing,
  declarations: List<&2, Lint.Declaration>,
  +sources: List<&2, Lint.Source>
) -> Plan:
  +works = Plan.works(founds, fixing, declarations, sources, 0, [])
  +texts = Plan.texts(Program.Program.own(sources), Map.new(&2, String))
  +groups = Shared.Group.of(~Spot, ~Spot.path, Plan.spots(works, []), Map.new(&2, List<&2, Spot>))
  Plan.go(
    works,
    0,
    texts,
    (Shared.sort(~Spotted, ~Spotted.le, Spot.read_all(Map.keys(&2, List<&2, Spot>, groups), groups, texts, [])), Plan{[], 0})
  )

# Writing
# -------

def Edit.le(a: Edit, b: Edit) -> Bool:
  match a b:
    case Edit{p, x, e, t} Edit{q, y, f, u}:
      U32.is_le(x, y)

# `rest`, the text from `at` on, with `edits` (in order) made, after `out`.
def Text.edited(edits: List<&2, Edit>, +rest: String, +at: U32, out: String) -> String:
  match edits:
    case Nil{}:
      out ++ rest
    case Con{Edit{p, beg, +end, text}, more}:
      Text.edited(
        more,
        String.drop(rest, U32.to_nat((end - at : U32))),
        end,
        out ++ Shared.take(rest, U32.to_nat((beg - at : U32))) ++ text
      )

def write.closed(+path: String, written: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match written:
    case Tuple{f, Done{u}}:
      File.close(f)
    case Tuple{f, Fail{e}}:
      do IO<Unit>:
        File.close(f)
        IO.die(Unit, 2, "bend-lint: could not write " ++ path)

def write.opened(+path: String, text: String, opened: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match opened:
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, Unit, File.write(f, text), w => write.closed(path, w))
    case Fail{e}:
      IO.die(Unit, 2, "bend-lint: could not write " ++ path)

def write(+path: String, text: String) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open(path, "w"), opened => write.opened(path, text, opened))

def write.edited(+path: String, text: String, edits: List<&2, Edit>) -> IO(Unit):
  match edits:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{e, rest}:
      write(path, Text.edited(Shared.sort(~Edit, ~Edit.le, Con{e, rest}), text, 0, ""))

# Writes each of `sources` that the edits of `groups` (by file) change.
def write.all(sources: List<&2, Lint.Source>, +groups: Map<&2, List<&2, Edit>>) -> IO(Unit):
  match sources:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{Lint.Source{+path, namespace, text, nodes, facts}, rest}:
      do IO<Unit>:
        write.edited(path, text, Shared.Group.get(Edit, groups, path))
        write.all(rest, groups)

# Fixes
# -----

def made(sources: List<&2, Lint.Source>, plan: Plan) -> IO(Maybe<&2, U32>):
  match plan:
    case Plan{edits, n}:
      do IO<Maybe<&2, U32>>:
        write.all(sources, Shared.Group.of(~Edit, ~Edit.path, edits, Map.new(&2, List<&2, Edit>)))
        return Some{n}

def apply.to(fixing: Fixing, founds: List<&2, Lint.Found>, program: Lint.Program) -> IO(Maybe<&2, U32>):
  match program:
    case Lint.Program{+sources}:
      made(
        sources,
        Plan.of(founds, fixing, Lint.Whole.declarations(Program.Whole.of(Lint.Program{sources})), sources)
      )

# Makes the fixes `fixing` allows, of `founds` (in order), in the files of `program`; how many, if it fixes.
def apply(+fixing: Fixing, founds: List<&2, Lint.Found>, program: Lint.Program) -> IO(Maybe<&2, U32>):
  match fixing:
    case NoFixes{}:
      IO.pure(Maybe<&2, U32>, None{})
    case _:
      apply.to(fixing, founds, program)
