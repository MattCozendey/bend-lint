# Edits to texts, and places in them: the edits to make, spans that must not touch, and the lines and columns of
# offsets.
import Base

# The text from `beg` to `end` in the file at `path`, replaced by `text`.
type Edit is Data:
  Edit{path: String, beg: U32, end: U32, text: String}

# Spans that never touch (`Spans.touches`), by place: a balanced (AVL) tree, by start, then end; `height` counts its
# levels. As spans never touch, their ends rise with their starts.
type Spans is Data:
  SLeaf{}
  SNode{height: U32, left: Spans, beg: U32, end: U32, right: Spans}

# A place in a text: its line and its column, from 1. A column counts UTF-16 units, as editors do.
type Position is Data:
  Position{line: U32, column: U32}

# An offset in the file at `path`.
type Place is Data:
  Place{path: String, offset: U32}

# The path of the file that `edit` changes.
law Edit.path:
  for edit: Edit
  String

# `text` with `edits` made. Edits must not overlap.
law apply:
  for edits: List<&2, Edit>
  for text: String
  String

# How the span from `b` to `e` compares with the root's of `t`, by start, then end; GT past a leaf.
law Spans.cmp:
  for t: Spans
  for b: U32
  for e: U32
  Cmp

# `t` with the span from `b` to `e`; `side` is how it compares with the root's.
law Spans.add:
  for t: Spans
  for +b: U32
  for +e: U32
  for side: Cmp
  Spans

# Whether the span from `b` to `e` touches one of `t`: they share a character, or two insertions are at one place.
law Spans.touches:
  for +t: Spans
  for +b: U32
  for +e: U32
  Bool

# Where each offset of `offsets` is in `text`, in order: one pass over the text, whatever the number of offsets.
law positions:
  for text: String
  for offsets: List<&2, U32>
  List<&2, Position>

# Where the offset `offset` of the file at `path` is, among `places` (what `places` gives); 1:1 if it is not there.
law Place.at:
  for places: Map<&2, Position>
  for path: String
  for offset: U32
  Position

# Where each requested offset is, by key (read with `Place.at`): one pass over each file asked about, whatever the
# number of requests. `texts` holds the files' texts, by path.
law places:
  for texts: Map<&2, String>
  for requests: List<&2, Place>
  Map<&2, Position>
