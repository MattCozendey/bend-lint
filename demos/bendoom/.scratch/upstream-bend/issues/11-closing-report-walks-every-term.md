# The closing report walks every checked term

**Status:** ready-for-human

On Bend 2.0.26, `bend PROOF.bend` spends about 1.5 s of its 5.6 s after the
last law checks, in `cli_report` in `bend2/main.ts`. Base declares foreign
defs (`Array.fork`, `Array.join`), so the report walks every reachable
checked term to find who relies on them, and Bendoom's generated tables make
that walk long. Measure it on the current pin with a patched `main.ts` timing
`cli_report`, then ask upstream to skip Base's own foreign defs or memoise
the walk.
