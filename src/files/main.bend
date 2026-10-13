import Base
import ../shared/lists.bend as Lists
import ../shared/strings.bend as Strings

# Types
# =====

# What a character is to a glob.
type Glyph is Data:
  GStar{}
  GQuestion{}
  GOpen{}
  GClose{}
  GBrace{}
  GUnbrace{}
  GComma{}
  GNot{}
  GDash{}
  GOther{}

# A class's scan (`[...]`, after its `[`) for one character: whether the class is negated, whether no member is read
# yet, whether a member is the character, the last member read (a range may start at it), and whether a `-` follows
# it; or its end: whether the class holds the character, and the text after its `]`.
type Scan is Data:
  Scan{negated: Bool, first: Bool, hit: Bool, last: Maybe<&2, Char>, dash: Bool}
  Ended{hit: Bool, rest: String}

# Where a match tries again after a mismatch: the name and the pattern after the last `*`.
type Back is Data:
  Back{name: String, pattern: String}

# A name's match against a glob segment: the name and the pattern left, and where to try again after a mismatch; or its
# end.
type Matching is Data:
  Matching{name: String, pattern: String, back: Maybe<&2, Back>}
  Hit{}
  Miss{}

# A glob's scan for its first brace group: the text before it (last first); then, inside it, how deep in nested groups,
# the alternative so far (last first), and those before it (last first); or the group: the text before it, its
# alternatives, and the text after it.
type Braces is Data:
  Seek{before: String}
  Inside{before: String, depth: Nat, current: String, alternatives: List<&2, String>}
  Group{before: String, alternatives: List<&2, String>, after: String}

# The brace expansion of globs: those left, and those done (last first).
type Expanding is Data:
  Expanding{globs: List<&2, String>, done: List<&2, String>}

# A glob's segment: `**` (any folders), a pattern of names, or a name.
type Segment is Data:
  Deep{}
  Pattern{pattern: String}
  Plain{name: String}

# A glob walk's work: a path and the segments after it, or a file it found.
type Walk is Data:
  Walk{path: String, segments: List<&2, String>}
  Found{path: String}

# The files an input names.
type Named is Data:
  Named{input: String, files: List<&2, String>}

# The real paths found so far, once each: as a set, and in order (last first).
type Seen is Data:
  Seen{set: Set(), paths: List<&2, String>}

# Effects
# =======

# The names in the folder at `path`, but "." and "..", each ended by a NUL, in the order the OS gives them.
def list.raw(path: String) -> IO(Result<&1, &1, U32 & String, String>):
  import "./effs/files.c"
  import "./effs/files.js"

# What is at `path`, links followed: 0 nothing, 1 a file, 2 a folder, 3 something else.
def kind(path: String) -> IO(U32):
  import "./effs/files.c"
  import "./effs/files.js"

# The real path of `path`: absolute, links resolved, "/" between its parts.
def real(path: String) -> IO(Result<&1, &1, U32 & String, String>):
  import "./effs/files.c"
  import "./effs/files.js"

def list.names(listed: Result<&1, &1, U32 & String, String>) -> List<&2, String>:
  match listed:
    case Done{names}:
      List.filter(~String, ~(n => Bool.not(String.is_empty(n))), String.split(names, Chr{0}))
    case Fail{why}:
      []

# The names in the folder at `path` ("" for the current one), but "." and ".."; none if it is not a folder.
def list(+path: String) -> IO(List<&2, String>):
  IO.bind(
    Result<&1, &1, U32 & String, String>,
    List<&2, String>,
    list.raw(Bool.pick(String, String.is_empty(path), ".", path)),
    listed => IO.pure(List<&2, String>, list.names(listed))
  )

# Text
# ====

# The text read so far (`got`, last first) and the last read `step`. `fuel` bounds the reads.
def read.go(
  fuel: Nat,
  step: File & Result<&1, &1, U32 & String, String>,
  got: List<&2, String>
) -> IO(Result<&2, &2, String, String>):
  match fuel step:
    case 1n+k Tuple{f, Done{SCon{h, t}}}:
      IO.bind(
        File & Result<&1, &1, U32 & String, String>,
        Result<&2, &2, String, String>,
        File.read(f, 65536),
        r => read.go(k, r, SCon{h, t} <> got)
      )
    case _ Tuple{f, Done{SNil{}}}:
      do IO<Result<&2, &2, String, String>>:
        File.close(f)
        return Done{String.concat(List.reverse(&2, String, got))}
    case _ Tuple{f, Fail{Tuple{code, why}}}:
      do IO<Result<&2, &2, String, String>>:
        File.close(f)
        return Fail{why}
    case 0n Tuple{f, Done{text}}:
      do IO<Result<&2, &2, String, String>>:
        File.close(f)
        return Fail{"too long"}

# The whole text of `file`, which it closes; or why it could not be read.
def read(file: File) -> IO(Result<&2, &2, String, String>):
  IO.bind(
    File & Result<&1, &1, U32 & String, String>,
    Result<&2, &2, String, String>,
    File.read(file, 65536),
    r => read.go(4294967295n, r, [])
  )

def write.closed(written: File & Result<&1, &1, U32 & String, Unit>) -> IO(Bool):
  match written:
    case Tuple{f, Done{u}}:
      do IO<Bool>:
        File.close(f)
        return True{}
    case Tuple{f, Fail{e}}:
      do IO<Bool>:
        File.close(f)
        return False{}

def write.opened(text: String, opened: Result<&1, &1, U32 & String, File>) -> IO(Bool):
  match opened:
    case Done{f}:
      IO.bind(
        File & Result<&1, &1, U32 & String, Unit>,
        Bool,
        File.write(f, text),
        w => write.closed(w)
      )
    case Fail{e}:
      IO.pure(Bool, False{})

# Whether `text` was written to the file at `path`, in place of its text.
def write(path: String, text: String) -> IO(Bool):
  IO.bind(
    Result<&1, &1, U32 & String, File>,
    Bool,
    File.open(path, "w"),
    opened => write.opened(text, opened)
  )

# Globs
# =====
def Glyph.of(+c: Char) -> Glyph:
  Bool.pick(
    Glyph,
    Char.is_eq(c, '*'),
    GStar{},
    Bool.pick(
      Glyph,
      Char.is_eq(c, '?'),
      GQuestion{},
      Bool.pick(
        Glyph,
        Char.is_eq(c, '['),
        GOpen{},
        Bool.pick(
          Glyph,
          Char.is_eq(c, ']'),
          GClose{},
          Bool.pick(
            Glyph,
            Char.is_eq(c, '{'),
            GBrace{},
            Bool.pick(
              Glyph,
              Char.is_eq(c, '}'),
              GUnbrace{},
              Bool.pick(
                Glyph,
                Char.is_eq(c, ','),
                GComma{},
                Bool.pick(
                  Glyph,
                  Char.is_eq(c, '!') || Char.is_eq(c, '^'),
                  GNot{},
                  Bool.pick(Glyph, Char.is_eq(c, '-'), GDash{}, GOther{})
                )
              )
            )
          )
        )
      )
    )
  )

# Whether a glyph makes a segment a pattern.
def Glyph.wild(glyph: Glyph) -> Bool:
  match glyph:
    case GStar{}:
      True{}
    case GQuestion{}:
      True{}
    case GOpen{}:
      True{}
    case _:
      False{}

# Whether `s` has a glyph that makes a segment a pattern, or `found` says one came before it.
def wild(s: String, found: Bool) -> Bool:
  match s found:
    case _ True{}:
      True{}
    case SCon{c, t} False{}:
      wild(t, Glyph.wild(Glyph.of(c)))
    case SNil{} False{}:
      False{}

def Range.has(lo: Char, hi: Char, x: Char) -> Bool:
  +at = Char.to_u32(x)
  U32.is_le(Char.to_u32(lo), at) && U32.is_le(at, Char.to_u32(hi))

# The scan after a class's character `c` (a `glyph`), with `t` after it, for the character `x`. A `]` first, or a `-`
# first or last, is a member; a `!` or `^` first negates the class.
def Scan.step(
  glyph: Glyph,
  first: Bool,
  negated: Bool,
  last: Maybe<&2, Char>,
  dash: Bool,
  hit: Bool,
  +c: Char,
  t: String,
  x: Char
) -> Scan:
  match glyph first negated last dash:
    case GClose{} False{} _ _ _:
      Ended{Bool.xor(negated, hit || (dash && Char.is_eq(x, '-'))), t}
    case GNot{} True{} False{} _ _:
      Scan{True{}, True{}, hit, last, dash}
    case GDash{} False{} _ Some{lo} False{}:
      Scan{negated, False{}, hit, Some{lo}, True{}}
    case _ _ _ Some{lo} True{}:
      Scan{negated, False{}, hit || Range.has(lo, c, x), None{}, False{}}
    case _ _ _ _ _:
      Scan{negated, False{}, hit || Char.is_eq(c, x), Some{c}, False{}}

# The scan of the class that `s` continues, for `x`: Ended, unless no `]` ends it.
def class.go(s: String, +x: Char, scan: Scan) -> Scan:
  match s scan:
    case SCon{+c, +t} Scan{negated, first, hit, last, dash}:
      class.go(t, x, Scan.step(Glyph.of(c), first, negated, last, dash, hit, c, t, x))
    case _ done:
      done

# The match after a mismatch: one more character for the last `*`, if any.
def retry(back: Maybe<&2, Back>) -> Matching:
  match back:
    case Some{Back{SCon{c, +name}, +pattern}}:
      Matching{name, pattern, Some{Back{name, pattern}}}
    case _:
      Miss{}

# The match after a class's scan from a `[` (`found`), with `t` after the `[`, for the name's character `x` and
# the name after it. A `[` that no `]` ends is a character.
def Matching.class(
  found: Scan,
  x: Char,
  t: String,
  name: String,
  +back: Maybe<&2, Back>
) -> Matching:
  match found:
    case Ended{True{}, rest}:
      Matching{name, rest, back}
    case Ended{False{}, rest}:
      retry(back)
    case Scan{negated, first, hit, last, dash}:
      Bool.pick(Matching, Char.is_eq(x, '['), Matching{name, t, back}, retry(back))

# The match of the name's next character against the pattern's character `c` (a `glyph`), with `t` after it.
def Matching.char(
  glyph: Glyph,
  c: Char,
  +t: String,
  name: String,
  +back: Maybe<&2, Back>
) -> Matching:
  match glyph name:
    case GQuestion{} SCon{x, n}:
      Matching{n, t, back}
    case GOpen{} SCon{+x, n}:
      Matching.class(class.go(t, x, Scan{False{}, True{}, False{}, None{}, False{}}), x, t, n, back)
    case _ SCon{x, n}:
      Bool.pick(Matching, Char.is_eq(c, x), Matching{n, t, back}, retry(back))
    case _ SNil{}:
      retry(back)

def Matching.glyph(
  glyph: Glyph,
  c: Char,
  +t: String,
  +name: String,
  back: Maybe<&2, Back>
) -> Matching:
  match glyph:
    case GStar{}:
      Matching{name, t, Some{Back{name, t}}}
    case other:
      Matching.char(other, c, t, name, back)

def Matching.end(name: String, back: Maybe<&2, Back>) -> Matching:
  match name:
    case SNil{}:
      Hit{}
    case SCon{c, n}:
      retry(back)

def Matching.step(name: String, pattern: String, back: Maybe<&2, Back>) -> Matching:
  match pattern:
    case SNil{}:
      Matching.end(name, back)
    case SCon{+c, t}:
      Matching.glyph(Glyph.of(c), c, t, name, back)

def matches.go(fuel: Nat, matching: Matching) -> Bool:
  match fuel matching:
    case 1n+k Matching{name, pattern, back}:
      matches.go(k, Matching.step(name, pattern, back))
    case _ Hit{}:
      True{}
    case _ _:
      False{}

def matches.shown(shown: Bool, name: String, pattern: String) -> Bool:
  match shown:
    case True{}:
      matches.go(4294967295n, Matching{name, pattern, None{}})
    case False{}:
      False{}

# Whether `name` matches the glob segment `pattern`: `*` matches any characters, `?` one, and `[...]` one of a class
# (`[!...]` or `[^...]`, one outside it). A name that starts with "." matches only a pattern that does.
def matches(+name: String, +pattern: String) -> Bool:
  matches.shown(Bool.not(Strings.starts(name, '.')) || Strings.starts(pattern, '.'), name, pattern)

# The scan after the glob's character `c` (a `glyph`), with `t` after it.
def Braces.step(scan: Braces, glyph: Glyph, c: Char, t: String) -> Braces:
  match scan glyph:
    case Seek{before} GBrace{}:
      Inside{before, 0n, "", []}
    case Seek{before} _:
      Seek{SCon{c, before}}
    case Inside{before, 0n, current, alternatives} GUnbrace{}:
      Group{
        String.reverse(before),
        List.reverse(&2, String, String.reverse(current) <> alternatives),
        t
      }
    case Inside{before, 1n+d, current, alternatives} GUnbrace{}:
      Inside{before, d, SCon{c, current}, alternatives}
    case Inside{before, 0n, current, alternatives} GComma{}:
      Inside{before, 0n, "", String.reverse(current) <> alternatives}
    case Inside{before, d, current, alternatives} GBrace{}:
      Inside{before, 1n+d, SCon{c, current}, alternatives}
    case Inside{before, d, current, alternatives} _:
      Inside{before, d, SCon{c, current}, alternatives}
    case Group{before, alternatives, after} _:
      Group{before, alternatives, after}

# The first brace group of the glob that `s` continues; not a Group if it has none.
def braces.go(s: String, scan: Braces) -> Braces:
  match s scan:
    case _ Group{before, alternatives, after}:
      Group{before, alternatives, after}
    case SCon{+c, +t} other:
      braces.go(t, Braces.step(other, Glyph.of(c), c, t))
    case SNil{} other:
      other

# Each of `alternatives` between `before` and `after`, onto `out`.
def expand.each(
  alternatives: List<&2, String>,
  +before: String,
  +after: String,
  out: List<&2, String>
) -> List<&2, String>:
  match alternatives:
    case Nil{}:
      out
    case Con{a, rest}:
      expand.each(rest, before, after, (before ++ a ++ after) <> out)

# The expansion after the glob `glob` and its first brace group (`found`), with `rest` left and `done` done.
def expand.next(
  found: Braces,
  glob: String,
  rest: List<&2, String>,
  done: List<&2, String>
) -> Expanding:
  match found:
    case Group{before, alternatives, after}:
      Expanding{expand.each(alternatives, before, after, rest), done}
    case _:
      Expanding{rest, glob <> done}

# The globs an expansion makes with their brace groups expanded (`a{b,c}d` is `abd` and `acd`), last first.
def expand(fuel: Nat, expanding: Expanding) -> List<&2, String>:
  match fuel expanding:
    case 1n+k Expanding{Con{+glob, rest}, done}:
      expand(k, expand.next(braces.go(glob, Seek{""}), glob, rest, done))
    case _ Expanding{globs, done}:
      done

def Segment.wild(wild: Bool, segment: String) -> Segment:
  match wild:
    case True{}:
      Pattern{segment}
    case False{}:
      Plain{segment}

def Segment.deep(deep: Bool, +segment: String) -> Segment:
  match deep:
    case True{}:
      Deep{}
    case False{}:
      Segment.wild(wild(segment, False{}), segment)

# The path of `name` in the folder at `path`: "" is the current folder, so a name after it is relative, and an empty
# name after it is the root.
def join(+path: String, +name: String) -> String:
  Bool.pick(
    String,
    String.is_empty(path),
    Bool.pick(String, String.is_empty(name), "/", name),
    Bool.pick(String, String.ends_with(path, "/"), path ++ name, path ++ "/" ++ name)
  )

# The walks into each name of `names` in the folder at `path` that does not start with ".", with `**` and `more`
# after it, onto `out`.
def Walk.deep(
  names: List<&2, String>,
  +path: String,
  +more: List<&2, String>,
  out: List<&2, Walk>
) -> List<&2, Walk>:
  match names:
    case Nil{}:
      out
    case Con{+name, rest}:
      Walk.deep(
        rest,
        path,
        more,
        Lists.push(
          Walk,
          Lists.when(
            Walk,
            Bool.not(Strings.starts(name, '.')),
            Walk{join(path, name), "**" <> more}
          ),
          out
        )
      )

# The walks into each name of `names` in the folder at `path` that matches `pattern`, with `more` after it, onto `out`.
def Walk.matching(
  names: List<&2, String>,
  +pattern: String,
  +path: String,
  +more: List<&2, String>,
  out: List<&2, Walk>
) -> List<&2, Walk>:
  match names:
    case Nil{}:
      out
    case Con{+name, rest}:
      Walk.matching(
        rest,
        pattern,
        path,
        more,
        Lists.push(
          Walk,
          Lists.when(Walk, matches(name, pattern), Walk{join(path, name), more}),
          out
        )
      )

def Walk.found(kind: U32, path: String) -> List<&2, Walk>:
  Bool.pick(List<&2, Walk>, U32.is_eq(kind, 1), [Found{path}], [])

# The walks after `segment`, at `path` with `more` after it. `**` is no folder, or a folder and `**` again.
def Walk.segment(segment: Segment, +path: String, +more: List<&2, String>) -> IO(List<&2, Walk>):
  match segment:
    case Deep{}:
      IO.bind(
        List<&2, String>,
        List<&2, Walk>,
        list(path),
        names => IO.pure(List<&2, Walk>, Walk.deep(names, path, more, [Walk{path, more}]))
      )
    case Pattern{pattern}:
      IO.bind(
        List<&2, String>,
        List<&2, Walk>,
        list(path),
        names => IO.pure(List<&2, Walk>, Walk.matching(names, pattern, path, more, []))
      )
    case Plain{name}:
      IO.pure(List<&2, Walk>, [Walk{join(path, name), more}])

# The walks after the first of `segments`, at `path`; with none, the file at `path`, if it is one.
def Walk.step(+path: String, segments: List<&2, String>) -> IO(List<&2, Walk>):
  match segments:
    case Nil{}:
      IO.bind(U32, List<&2, Walk>, kind(path), k => IO.pure(List<&2, Walk>, Walk.found(k, path)))
    case Con{+segment, more}:
      Walk.segment(Segment.deep(String.eq(segment, "**"), segment), path, more)

# The files the walks of `todo` find, onto `out`.
def Walk.loop(fuel: Nat, todo: List<&2, Walk>, out: List<&2, String>) -> IO(List<&2, String>):
  match fuel todo:
    case 1n+k Con{Found{path}, rest}:
      Walk.loop(k, rest, path <> out)
    case 1n+k Con{Walk{path, segments}, rest}:
      IO.bind(
        List<&2, Walk>,
        List<&2, String>,
        Walk.step(path, segments),
        more => Walk.loop(k, Lists.onto(&2, Walk, more, rest), out)
      )
    case _ _:
      IO.pure(List<&2, String>, out)

# The walks that start each of `globs`, onto `out`.
def Walk.starts(globs: List<&2, String>, out: List<&2, Walk>) -> List<&2, Walk>:
  match globs:
    case Nil{}:
      out
    case Con{glob, rest}:
      Walk.starts(rest, Walk{"", String.split(glob, '/')} <> out)

# The files `glob` names, sorted, as it spells them.
def glob(glob: String) -> IO(List<&2, String>):
  IO.bind(
    List<&2, String>,
    List<&2, String>,
    Walk.loop(4294967295n, Walk.starts(expand(4294967295n, Expanding{[glob], []}), []), []),
    found => IO.pure(List<&2, String>, Lists.sort(~String, ~String.is_le, found))
  )

# Inputs
# ======

# The files each of `inputs` names, onto `groups` (last first), each with its input.
def named.go(inputs: List<&2, String>, groups: List<&2, Named>) -> IO(List<&2, Named>):
  match inputs:
    case Nil{}:
      IO.pure(List<&2, Named>, List.reverse(&2, Named, groups))
    case Con{+input, rest}:
      IO.bind(
        List<&2, String>,
        List<&2, Named>,
        glob(input),
        found => named.go(rest, Named{input, found} <> groups)
      )

# The files of `groups`, in order, onto `out` (last first); or the first input that names none.
def named.check(
  groups: List<&2, Named>,
  out: List<&2, String>
) -> Result<&2, &2, String, List<&2, String>>:
  match groups:
    case Nil{}:
      Done{List.reverse(&2, String, out)}
    case Con{Named{input, Nil{}}, rest}:
      Fail{input ++ " matches no file"}
    case Con{Named{input, found}, rest}:
      named.check(rest, Lists.onto(&2, String, found, out))

# The paths seen, with `path` after `paths` unless `found` (the set of those seen, and whether it holds `path`) says it
# is seen.
def Seen.put(found: Set() & Bool, +path: String, paths: List<&2, String>) -> Seen:
  match found:
    case Tuple{set, True{}}:
      Seen{set, paths}
    case Tuple{set, False{}}:
      Seen{Set.add(set, path), path <> paths}

def Seen.add(seen: Seen, +path: String) -> Seen:
  match seen:
    case Seen{set, paths}:
      Seen.put(Set.has(set, path), path, paths)

def Seen.paths(seen: Seen) -> List<&2, String>:
  match seen:
    case Seen{set, paths}:
      List.reverse(&2, String, paths)

# The real path of each of `paths`, once each, after those `seen`.
def reals(paths: List<&2, String>, seen: Seen) -> IO(List<&2, String>):
  match paths:
    case Nil{}:
      IO.pure(List<&2, String>, Seen.paths(seen))
    case Con{path, rest}:
      IO.bind(
        String,
        List<&2, String>,
        IO.try(String, real(path)),
        r => reals(rest, Seen.add(seen, r))
      )

def named.real(
  found: Result<&2, &2, String, List<&2, String>>
) -> IO(Result<&2, &2, String, List<&2, String>>):
  match found:
    case Done{paths}:
      IO.bind(
        List<&2, String>,
        Result<&2, &2, String, List<&2, String>>,
        reals(paths, Seen{Set.new(), []}),
        r => IO.pure(Result<&2, &2, String, List<&2, String>>, Done{r})
      )
    case Fail{why}:
      IO.pure(Result<&2, &2, String, List<&2, String>>, Fail{why})

# The files `inputs` name, each once, in order, as real paths; or why an input names none. An input is a path, or a
# glob with "/" between its parts, whose files come sorted: in a segment, `*` matches any characters, `?` one, and
# `[...]` one of a class; `**` is any folders; `{a,b}` is either.
def named(inputs: List<&2, String>) -> IO(Result<&2, &2, String, List<&2, String>>):
  IO.bind(
    List<&2, Named>,
    Result<&2, &2, String, List<&2, String>>,
    named.go(inputs, []),
    groups => named.real(named.check(groups, []))
  )
