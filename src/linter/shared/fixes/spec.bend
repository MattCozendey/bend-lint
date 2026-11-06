# The fixes a run makes with `--fix-dangerously`: no fix is proven to keep the program until Bend's checker is Bend.
import Base
import ../../api/spec.bend as Lint
import ../text/spec.bend as Text

# The text of each of `sources`, by its path, onto `out`.
law texts:
  for sources: List<&2, Lint.Source>
  for out: Map<&2, String>
  Map<&2, String>

# The edits of each of `fixes`, in order; None for a fix the linter cannot make: an operation it refuses, an edit in a
# file a fix may not edit, or a rename of a name the text does not write where a use is. Each file a rename changes is
# read once, for all the fixes.
law edits:
  for +fixes: List<&2, Lint.Fix>
  for declarations: List<&2, Lint.Declaration>
  for +sources: List<&2, Lint.Source>
  List<&2, Maybe<&2, List<&2, Text.Edit>>>

# Makes the fixes of `founds` (in order), if `fixing`, in the program's files (`sources`, whose declarations are
# `declarations`); how many.
law apply:
  for fixing: Bool
  for founds: List<&2, Lint.Found>
  for declarations: List<&2, Lint.Declaration>
  for +sources: List<&2, Lint.Source>
  IO(U32)
