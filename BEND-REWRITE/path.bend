import Base

def get_real_path(path: String) -> IO(Result<&1, &1, U32 & String, String>):
  import "./effs/get_real_path.c"
  import "./effs/get_real_path.js"

def get_normalized_path.pop.up(up: Bool, h: String, t: List<&2, String>) -> List<&2, String>:
  match up:
    case True{}:
      ".." <> (h <> t)
    case False{}:
      t

def get_normalized_path.pop.root(abs: Bool) -> List<&2, String>:
  match abs:
    case True{}:
      Nil{}
    case False{}:
      [".."]

def get_normalized_path.pop(stack: List<&2, String>, abs: Bool) -> List<&2, String>:
  match stack:
    case Nil{}:
      get_normalized_path.pop.root(abs)
    case Con{+h, t}:
      get_normalized_path.pop.up(String.eq(h, ".."), h, t)

def get_normalized_path.step(
  skip: Bool,
  up: Bool,
  s: String,
  stack: List<&2, String>,
  abs: Bool
) -> List<&2, String>:
  match skip:
    case True{}:
      stack
    case False{}:
      match up:
        case True{}:
          get_normalized_path.pop(stack, abs)
        case False{}:
          s <> stack

def get_normalized_path.go(
  segs: List<&2, String>,
  stack: List<&2, String>,
  +abs: Bool
) -> List<&2, String>:
  match segs:
    case Nil{}:
      stack
    case Con{+s, t}:
      get_normalized_path.go(
        t,
        get_normalized_path.step(
          String.eq(s, "") || String.eq(s, "."),
          String.eq(s, ".."),
          s,
          stack,
          abs
        ),
        abs
      )

def get_normalized_path.dotted(up: Bool, body: String) -> String:
  match up:
    case True{}:
      body
    case False{}:
      "./" ++ body

def get_normalized_path.relative(kept: List<&2, String>) -> String:
  match kept:
    case Nil{}:
      "."
    case Con{+h, t}:
      get_normalized_path.dotted(String.eq(h, ".."), String.join(h <> t, "/"))

def get_normalized_path.finish(unc: Bool, abs: Bool, kept: List<&2, String>) -> String:
  match unc:
    case True{}:
      "//" ++ String.join(kept, "/")
    case False{}:
      match abs:
        case True{}:
          "/" ++ String.join(kept, "/")
        case False{}:
          get_normalized_path.relative(kept)

def get_normalized_path.kept(path: String, +abs: Bool) -> List<&2, String>:
  List.reverse(&2, String, get_normalized_path.go(String.split(path, '/'), Nil{}, abs))

def get_normalized_path.plain(+p: String) -> String:
  +abs = String.starts_with(p, "/")
  get_normalized_path.finish(
    String.starts_with(p, "//") && Bool.not(String.starts_with(p, "///")),
    abs,
    get_normalized_path.kept(p, abs)
  )

def get_normalized_path.ends(t: String) -> Bool:
  match t:
    case SNil{}:
      True{}
    case SCon{h, rest}:
      Char.is_eq(h, '/')

def get_normalized_path.is_drive.pair(+c: Char, rest: String) -> Bool:
  match rest:
    case SNil{}:
      False{}
    case SCon{d, t}:
      Char.is_alpha(c) && Char.is_eq(d, ':') && get_normalized_path.ends(t)

def get_normalized_path.is_drive(p: String) -> Bool:
  match p:
    case SNil{}:
      False{}
    case SCon{+c, rest}:
      get_normalized_path.is_drive.pair(c, rest)

def get_normalized_path.drive(p: String) -> String:
  match p:
    case SNil{}:
      SNil{}
    case SCon{c, rest}:
      match rest:
        case SNil{}:
          SCon{c, SNil{}}
        case SCon{d, t}:
          SCon{
            Char.to_lower(c),
            SCon{':', "/" ++ String.join(get_normalized_path.kept(t, True{}), "/")}
          }

def get_normalized_path.rooted(drive: Bool, p: String) -> String:
  match drive:
    case True{}:
      get_normalized_path.drive(p)
    case False{}:
      get_normalized_path.plain(p)

def get_normalized_path(+p: String) -> String:
  get_normalized_path.rooted(get_normalized_path.is_drive(p), p)

def get_posix_path.slash(backslash: Bool, c: Char) -> Char:
  match backslash:
    case True{}:
      '/'
    case False{}:
      c

def get_posix_path.slashes(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, t}:
      SCon{get_posix_path.slash(Char.is_eq(h, '\\'), h), get_posix_path.slashes(t)}

def get_posix_path.shape(drive: Bool, unc: Bool, c: Char, d: Char, t: String) -> String:
  match drive:
    case True{}:
      SCon{Char.to_lower(c), SCon{':', get_posix_path.slashes(t)}}
    case False{}:
      match unc:
        case True{}:
          get_posix_path.slashes(SCon{c, SCon{d, t}})
        case False{}:
          SCon{c, SCon{d, t}}

def get_posix_path.pair(+c: Char, rest: String) -> String:
  match rest:
    case SNil{}:
      SCon{c, SNil{}}
    case SCon{+d, t}:
      get_posix_path.shape(
        Char.is_alpha(c) && Char.is_eq(d, ':'),
        Char.is_eq(c, '\\') && Char.is_eq(d, '\\'),
        c,
        d,
        t
      )

def get_posix_path.shaped(native: String) -> String:
  match native:
    case SNil{}:
      SNil{}
    case SCon{+c, rest}:
      get_posix_path.pair(c, rest)

def get_posix_path(native: String) -> String:
  get_normalized_path(get_posix_path.shaped(native))

def get_is_windows_path.pair(+c: Char, rest: String) -> Bool:
  match rest:
    case SNil{}:
      False{}
    case SCon{+d, t}:
      (Char.is_alpha(c) && Char.is_eq(d, ':')) || (Char.is_eq(c, '\\') && Char.is_eq(d, '\\'))

def get_is_windows_path(native: String) -> Bool:
  match native:
    case SNil{}:
      False{}
    case SCon{+c, rest}:
      get_is_windows_path.pair(c, rest)

def get_linter_path.separators(windows: Bool, path: String) -> String:
  match windows:
    case True{}:
      get_posix_path.slashes(path)
    case False{}:
      path

def get_linter_path.root(empty: Bool, drive: Bool, joined: String) -> String:
  match empty:
    case True{}:
      "/"
    case False{}:
      match drive:
        case True{}:
          joined ++ "/"
        case False{}:
          joined

def get_linter_path.folder(rev: List<&2, String>) -> String:
  +joined = String.join(List.reverse(&2, String, rev), "/")
  get_linter_path.root(String.is_empty(joined), String.ends_with(joined, ":"), joined)

def get_linter_path.rest(empty: Bool, name: String, rest: String) -> String:
  match empty:
    case True{}:
      name
    case False{}:
      name ++ "/" ++ rest

def get_linter_path.candidates(rev: List<&2, String>, +rest: String) -> List<&1, String & String>:
  match rev:
    case Nil{}:
      [(".", rest)]
    case Con{+h, +t}:
      (
        get_linter_path.folder(h <> t),
        rest
      )
        <> get_linter_path.candidates(t, get_linter_path.rest(String.is_empty(rest), h, rest))

def get_linter_path.found(
  missing: Bool,
  retry: IO(Result<&1, &1, U32 & String, String>),
  code: U32,
  text: String
) -> IO(Result<&1, &1, U32 & String, String>):
  match missing:
    case True{}:
      retry
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{(code, text)})

def get_linter_path.tried(
  r: Result<&1, &1, U32 & String, String>,
  rest: String,
  retry: IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Done{value}:
      IO.pure(
        Result<&1, &1, U32 & String, String>,
        Done{get_normalized_path(get_posix_path(value) ++ "/" ++ rest)}
      )
    case Fail{error}:
      match error:
        case (+code, text):
          get_linter_path.found(U32.is_eq(code, 2), retry, code, text)

def get_linter_path.try(
  cands: List<&1, String & String>
) -> IO(Result<&1, &1, U32 & String, String>):
  match cands:
    case Nil{}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{(2, "No such file or directory")})
    case Con{head, tail}:
      match head:
        case (folder, rest):
          IO.bind(
            Result<&1, &1, U32 & String, String>,
            Result<&1, &1, U32 & String, String>,
            get_real_path(folder),
            r => get_linter_path.tried(r, rest, get_linter_path.try(tail))
          )

def get_is_windows.of(here: Result<&1, &1, U32 & String, String>) -> Bool:
  match here:
    case Done{value}:
      get_is_windows_path(value)
    case Fail{error}:
      False{}

def get_is_windows() -> IO(Bool):
  IO.bind(
    Result<&1, &1, U32 & String, String>,
    Bool,
    get_real_path("."),
    here => IO.pure(Bool, get_is_windows.of(here))
  )

def get_linter_path.from(windows: Bool, path: String) -> IO(Result<&1, &1, U32 & String, String>):
  get_linter_path.try(
    get_linter_path.candidates(
      List.reverse(&2, String, String.split(get_linter_path.separators(windows, path), '/')),
      ""
    )
  )

def get_linter_path(path: String) -> IO(Result<&1, &1, U32 & String, String>):
  IO.bind(
    Bool,
    Result<&1, &1, U32 & String, String>,
    get_is_windows(),
    windows => get_linter_path.from(windows, path)
  )
