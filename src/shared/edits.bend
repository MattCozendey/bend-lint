import Base
import ./lists.bend as Lists
import ./strings.bend as Strings

# The text from `beg` to `end` in the file at `path`, replaced by `text`.
type Edit is Data:
  Edit{path: String, beg: U32, end: U32, text: String}

def Edit.path(edit: Edit) -> String:
  match edit:
    case Edit{path, beg, end, text}:
      path

def Edit.le(a: Edit, b: Edit) -> Bool:
  match a b:
    case Edit{p, x, e, t} Edit{q, y, f, u}:
      U32.is_le(x, y)

# `rest`, the text from `at` on, with `edits` (in order) made, after the pieces of `out` (last first). The pieces join
# once, at the end, so the text is copied once, whatever the number of edits.
def apply.go(edits: List<&2, Edit>, +rest: String, +at: U32, out: List<&2, String>) -> String:
  match edits:
    case Nil{}:
      Strings.joined(rest <> out, "")
    case Con{Edit{p, beg, +end, text}, more}:
      apply.go(
        more,
        String.drop(rest, U32.to_nat((end - at: U32))),
        end,
        text <> Strings.take(rest, U32.to_nat((beg - at: U32))) <> out
      )

# `text` with `edits` made. Edits must not overlap.
def apply(edits: List<&2, Edit>, text: String) -> String:
  apply.go(Lists.sort(~Edit, ~Edit.le, edits), text, 0, [])
