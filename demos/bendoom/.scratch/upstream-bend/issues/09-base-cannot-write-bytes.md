# Read bytes directly into an array

**Status:** ready-for-human

In Bend 2.0.22, `File.read_bytes` and `File.read_at` return a list, allocating
one cell per byte. Bendoom folds those lists into an array. Request an
array-returning read upstream to avoid the intermediate allocations.

Bend already provides `File.write_bytes` and `File.size`. Bendoom can adopt
those separately to remove hexadecimal output conversion and the reader's
array growth.
