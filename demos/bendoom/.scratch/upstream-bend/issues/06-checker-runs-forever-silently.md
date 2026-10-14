# Slow normalization needs diagnostics

**Status:** needs-info

Nested calls to a function that uses its argument multiple times can make
normalization grow exponentially. The checker gives no progress or location
while evaluating the term. The coding constraint is in `docs/bend.md`.

Build a minimal reproduction on the current Bend pin, measure growth with
nesting depth, and request a step limit or a diagnostic naming the definition.
