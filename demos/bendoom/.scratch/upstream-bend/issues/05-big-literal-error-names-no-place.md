# Large list errors need a source location

**Status:** ready-for-human

On Bend 2.0.26, a 4096-element list literal still overflows the checker:

```
Error: the machine stack overflowed (a deep recursion, or a literal too large to expand)
```

The error names no file, line or definition. Report a minimal reproduction and
request a source location. Large Nat literals now check directly; the remaining
workaround for list literals is documented in `docs/bend.md`.
