# Native segment overflow needs a source location

**Status:** ready-for-human

The native backend rejects segments with more than 255 live words:

```
an arity over 255
```

The error names neither the definition nor the segment. Record fields count
as separate words, so source functions with few arguments can still reach
the cap. `compile_tables` in `bend2/comp.ts` emits byte-sized arity tables.

Request a diagnostic naming the segment and its live values, and consider
wider tables or spilled parameters upstream. Current coding workarounds are
in `docs/bend.md`; reproduce against the current pin before reporting.
