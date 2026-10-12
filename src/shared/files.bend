import Base

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

# The folders a path's folder parts make, nearest first; `at` is the folder so far, `out` the folders so far
# (nearest first).
def folders.go(parts: List<&2, String>, +at: String, out: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}:
      out
    case Con{+p, rest}:
      folders.go(rest, at ++ "/" ++ p, (at ++ "/" ++ p) <> out)

def folders.from(parts: List<&2, String>) -> List<&2, String>:
  match parts:
    case Con{+first, rest}:
      folders.go(rest, first, [first])
    case Nil{}:
      []

# A path's folder parts: its parts, less the last (the file's name).
def folders.parts(reversed: List<&2, String>) -> List<&2, String>:
  match reversed:
    case Con{name, rest}:
      List.reverse(&2, String, rest)
    case Nil{}:
      []

# The folders a path is in, nearest first: "C:/a/b/c.bend" gives "C:/a/b", "C:/a", "C:"; "/a/b.bend" gives "/a", "".
def folders(path: String) -> List<&2, String>:
  folders.from(folders.parts(List.reverse(&2, String, String.split(path, '/'))))

# The file named `name` in the nearest folder of `folders` that has one, from the last attempt to open one (in
# `folder`).
def nearest.go(
  folders: List<&2, String>,
  +name: String,
  opened: Result<&1, &1, U32 & String, File>,
  folder: String
) -> IO(Maybe<&1, String & File>):
  match folders opened:
    case _ Done{file}:
      IO.pure(Maybe<&1, String & File>, Some{(folder, file)})
    case Con{+next, rest} Fail{why}:
      IO.bind(
        Result<&1, &1, U32 & String, File>,
        Maybe<&1, String & File>,
        File.open(next ++ "/" ++ name, "r"),
        r => nearest.go(rest, name, r, next)
      )
    case Nil{} Fail{why}:
      IO.pure(Maybe<&1, String & File>, None{})

# The file named `name` in the nearest folder that holds the file at `path`, opened to read, and that folder.
def nearest(path: String, name: String) -> IO(Maybe<&1, String & File>):
  nearest.go(folders(path), name, Fail{(0, "")}, "")
