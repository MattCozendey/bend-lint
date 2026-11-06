# Files: their text, folders and globs.
import Base

# The whole text of `file`, which it closes; or why it could not be read.
law read:
  for file: File
  IO(Result<&2, &2, String, String>)

# The real path of `path`: absolute, links resolved, "/" between its parts.
law real:
  for path: String
  IO(Result<&1, &1, U32 & String, String>)

# Whether `text` was written to the file at `path`, in place of its text.
law write:
  for path: String
  for text: String
  IO(Bool)

# The paths of `paths` that name no file, onto `out`.
law missing:
  for paths: List<&2, String>
  for out: List<&2, String>
  IO(List<&2, String>)

# The files `inputs` name, each once, in order, as real paths; or why an input names none. An input is a path, or a
# glob with "/" between its parts, whose files come sorted: in a segment, `*` matches any characters, `?` one, and
# `[...]` one of a class; `**` is any folders; `{a,b}` is either.
law named:
  for inputs: List<&2, String>
  IO(Result<&2, &2, String, List<&2, String>>)

# The files under the current folder whose names match the glob segment `pattern`, sorted, each once, as real paths:
# those git lists (tracked, or untracked and not ignored, by .gitignore files and git's other ignore files; at most 64
# MiB of paths, in a minute), or all if git does not list them (outside a repository, for one); but none with a part
# that is node_modules or starts with ".".
law listed:
  for +pattern: String
  IO(List<&2, String>)
