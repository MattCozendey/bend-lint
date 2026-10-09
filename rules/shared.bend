# Logic that more than one Bend rule uses. A rule imports it with
# import ../shared.bend as Shared
import Base

# The text of the line that holds offset `n` of `s`, up to `n`.
def line_before(s: String, n: Nat, line: String) -> String:
  match s n:
    case _ 0n:
      String.reverse(line)
    case SNil{} _:
      String.reverse(line)
    case SCon{'\n', rest} 1n+k:
      line_before(rest, k, "")
    case SCon{c, rest} 1n+k:
      line_before(rest, k, SCon{c, line})
