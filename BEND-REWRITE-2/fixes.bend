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

# The last segment of a name, as a rename changes it: `f` of `U.f`.
def last(name: String) -> String:
  last.go(name, "")

# Renames
# -------

def Edit.named(written: Bool, +path: String, +end: U32, +old: String, +to: String) -> Maybe<&2, Edit>:
  match written:
    case True{}:
      Some{Edit{path, (end - U32.from_nat(String.length(old)) : U32), end, to}}
    case False{}:
      None{}

# The edit that renames `node` from `old` to `to`, if it is written as the name: its last segment is `old`.
def Edit.renaming(node: Lint.Node, +old: String, +to: String) -> Maybe<&2, Edit>:
  match node:
    case Lint.Node{id, p, o, s, name, b, q, Some{Lint.Span{path, beg, end}}, t}:
      Edit.named(String.eq(last(name), old), path, end, old, to)
    case _:
      None{}

# The edits that rename each of `uses`, onto `out`; none if one is not written as the name.
def Rename.uses(uses: List<&2, Lint.Node>, +old: String, +to: String, out: Maybe<&2, List<&2, Edit>>) ->
  Maybe<&2, List<&2, Edit>>:
  match uses:
    case Nil{}:
      out
    case Con{u, rest}:
      Rename.uses(
        rest,
        old,
        to,
        do Maybe<&2, List<&2, Edit>>:
          edits : List<&2, Edit> <- out
          e : Edit <- Edit.renaming(u, old, to)
          return e <> edits
      )

# Whether no node of `nodes` is named `to`: a rename to it could take the place of another name.
def Rename.free(nodes: List<&2, Lint.Node>, +to: String) -> Bool:
  match nodes:
    case Nil{}:
      True{}
    case Con{Lint.Node{id, p, o, s, name, b, q, sp, t}, rest}:
      Bool.and(Bool.not(String.eq(last(name), to)), Rename.free(rest, to))

def Rename.checked(free: Bool, edits: Maybe<&2, List<&2, Edit>>) -> Maybe<&2, List<&2, Edit>>:
  match free:
    case True{}:
      edits
    case False{}:
      None{}

# The nodes of the file at `path`.
def Rename.nodes(sources: List<&2, Lint.Source>, +path: String) -> List<&2, Lint.Node>:
  match sources:
    case Nil{}:
      []
    case Con{Lint.Source{+p, namespace, text, nodes, facts}, rest}:
      Bool.pick(List<&2, Lint.Node>, String.eq(p, path), nodes, Rename.nodes(rest, path))

# The edits of a rename of `declaration`: its name and each use, if each is written as the name and no node of its
# file is named `to` already.
def Rename.plan(declaration: Maybe<&2, Lint.Declaration>, +to: String, +sources: List<&2, Lint.Source>) ->
  Maybe<&2, List<&2, Edit>>:
  match declaration:
    case Some{Lint.Declaration{Lint.Node{id, p, o, s, +name, b, q, Some{Lint.Span{+path, beg, end}}, t}, uses}}:
      Rename.checked(
        Rename.free(Rename.nodes(sources, path), to),
        Rename.uses(
          Lint.Node{id, p, o, s, name, b, q, Some{Lint.Span{path, beg, end}}, t} <> uses,
          last(name),
          to,
          Some{[]}
        )
      )
    case _:
      None{}

# The declaration of the node `id`, among `declarations`.
def Declaration.find(declarations: List<&2, Lint.Declaration>, +id: U32) -> Maybe<&2, Lint.Declaration>:
  match declarations:
    case Nil{}:
      None{}
    case Con{Lint.Declaration{Lint.Node{+i, p, o, s, n, b, q, sp, t}, uses}, rest}:
      Bool.pick(
        Maybe<&2, Lint.Declaration>,
        U32.is_eq(i, id),
        Some{Lint.Declaration{Lint.Node{i, p, o, s, n, b, q, sp, t}, uses}},
        Declaration.find(rest, id)
      )

# Plans
# -----

# The edits of one operation, if the linter can make them.
def Operation.edits(op: Lint.Operation, +declarations: List<&2, Lint.Declaration>, +sources: List<&2, Lint.Source>) ->
  Maybe<&2, List<&2, Edit>>:
  match op:
    case Lint.Replace{Lint.Span{path, beg, end}, text}:
      Some{[Edit{path, beg, end, text}]}
    case Lint.Rename{id, to}:
      Rename.plan(Declaration.find(declarations, id), to, sources)

# The edits of a fix's operations, onto `out`; none if the linter cannot make one.
def Fix.edits(
  ops: List<&2, Lint.Operation>,
  +declarations: List<&2, Lint.Declaration>,
  +sources: List<&2, Lint.Source>,
  out: Maybe<&2, List<&2, Edit>>
) -> Maybe<&2, List<&2, Edit>>:
  match ops:
    case Nil{}:
      out
    case Con{op, rest}:
      Fix.edits(
        rest,
        declarations,
        sources,
        do Maybe<&2, List<&2, Edit>>:
          edits : List<&2, Edit> <- out
          more : List<&2, Edit> <- Operation.edits(op, declarations, sources)
          return Shared.onto(&2, Edit, more, edits)
      )

# Whether two edits touch: in one file, their spans share a character, or two insertions are at one place.
def Edit.overlap(a: Edit, b: Edit) -> Bool:
  match a b:
    case Edit{+p, +ab, +ae, t} Edit{+q, +bb, +be, u}:
      String.eq(p, q) && Bool.or(Bool.and(U32.is_lt(ab, be), U32.is_lt(bb, ae)), Bool.and(U32.is_eq(ab, bb), U32.is_eq(ae, be)))

# Whether `edit` touches one of `edits`.
def Edit.clashes(+edit: Edit, edits: List<&2, Edit>) -> Bool:
  match edits:
    case Nil{}:
      False{}
    case Con{e, rest}:
      Bool.or(Edit.overlap(edit, e), Edit.clashes(edit, rest))

# Whether some edit of `edits` touches another, or one of `kept`; `kept` grows with the edits read.
def Edit.tangled(edits: List<&2, Edit>, +kept: List<&2, Edit>) -> Bool:
  match edits:
    case Nil{}:
      False{}
    case Con{+e, rest}:
      Bool.or(Edit.clashes(e, kept), Edit.tangled(rest, e <> kept))

# Whether the linter proves a fix keeps what the program does. Until Bend's checker is Bend it proves none.
def Fix.safe(fix: Lint.Fix) -> Bool:
  False{}

def Plan.add(tangled: Bool, edits: List<&2, Edit>, plan: Plan) -> Plan:
  match tangled plan:
    case True{} _:
      plan
    case False{} Plan{kept, n}:
      Plan{Shared.onto(&2, Edit, edits, kept), (n + 1 : U32)}

def Plan.fix(edits: Maybe<&2, List<&2, Edit>>, +plan: Plan) -> Plan:
  match edits plan:
    case Some{+es} Plan{+kept, n}:
      Plan.add(Edit.tangled(es, kept), es, plan)
    case None{} _:
      plan

def Plan.allowed(+fixing: Fixing, fix: Lint.Fix) -> Bool:
  match fixing:
    case NoFixes{}:
      False{}
    case SafeFixes{}:
      Fix.safe(fix)
    case DangerousFixes{}:
      True{}

def Plan.take(allowed: Bool, fix: Lint.Fix, +declarations: List<&2, Lint.Declaration>, +sources: List<&2, Lint.Source>, +plan: Plan) ->
  Plan:
  match allowed fix:
    case True{} Lint.Fix{title, ops}:
      Plan.fix(Fix.edits(ops, declarations, sources, Some{[]}), plan)
    case False{} _:
      plan

def Plan.first(
  +fixing: Fixing,
  fixes: List<&2, Lint.Fix>,
  +declarations: List<&2, Lint.Declaration>,
  +sources: List<&2, Lint.Source>,
  +plan: Plan
) -> Plan:
  match fixes:
    case Con{+fix, rest}:
      Plan.take(Plan.allowed(fixing, fix), fix, declarations, sources, plan)
    case Nil{}:
      plan

# The edits of each finding's first fix that `fixing` allows, in order, but those that overlap an earlier one's.
def Plan.of(
  founds: List<&2, Lint.Found>,
  +fixing: Fixing,
  +declarations: List<&2, Lint.Declaration>,
  +sources: List<&2, Lint.Source>,
  plan: Plan
) -> Plan:
  match founds:
    case Nil{}:
      plan
    case Con{Lint.Found{rule, Lint.Finding{s, span, message, fixes}}, rest}:
      Plan.of(rest, fixing, declarations, sources, Plan.first(fixing, fixes, declarations, sources, plan))

# Writing
# -------

def Edit.le(a: Edit, b: Edit) -> Bool:
  match a b:
    case Edit{p, x, e, t} Edit{q, y, f, u}:
      U32.is_le(x, y)

def Edit.at(+path: String, edits: List<&2, Edit>, +out: List<&2, Edit>) -> List<&2, Edit>:
  match edits:
    case Nil{}:
      out
    case Con{Edit{+p, b, e, t}, rest}:
      Edit.at(path, rest, Bool.pick(List<&2, Edit>, String.eq(p, path), Edit{p, b, e, t} <> out, out))

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

# Writes each of `sources` that `edits` change.
def write.all(sources: List<&2, Lint.Source>, +edits: List<&2, Edit>) -> IO(Unit):
  match sources:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{Lint.Source{+path, namespace, text, nodes, facts}, rest}:
      do IO<Unit>:
        write.edited(path, text, Edit.at(path, edits, []))
        write.all(rest, edits)

# Fixes
# -----

def made(+sources: List<&2, Lint.Source>, plan: Plan) -> IO(Maybe<&2, U32>):
  match plan:
    case Plan{+edits, n}:
      do IO<Maybe<&2, U32>>:
        write.all(sources, edits)
        return Some{n}

def apply.to(+fixing: Fixing, founds: List<&2, Lint.Found>, program: Lint.Program) -> IO(Maybe<&2, U32>):
  match program:
    case Lint.Program{+sources}:
      made(
        sources,
        Plan.of(founds, fixing, Lint.Whole.declarations(Program.Whole.of(Lint.Program{sources})), sources, Plan{[], 0})
      )

# Makes the fixes `fixing` allows, of `founds` (in order), in the files of `program`; how many, if it fixes.
def apply(+fixing: Fixing, founds: List<&2, Lint.Found>, program: Lint.Program) -> IO(Maybe<&2, U32>):
  match fixing:
    case NoFixes{}:
      IO.pure(Maybe<&2, U32>, None{})
    case _:
      apply.to(fixing, founds, program)
