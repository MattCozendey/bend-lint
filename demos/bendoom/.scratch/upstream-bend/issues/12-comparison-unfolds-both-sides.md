# The checker unfolds both sides before comparing them

**Status:** ready-for-human

On Bend 2.0.26, an equation's two sides are normalised in full before their
heads are compared, nothing is shared between them, and a stuck value is
walked once per read. A law naming one state six times, or a def reading a
table before the branch that needs it, cost seconds each (`docs/bend.md`,
"Normalization duplicates"; Bendoom's `exit_ends` went from 2.7 s to 0.2 s
once restated). Build a minimal reproduction on the current pin and ask
upstream to compare heads first or share subterms.
