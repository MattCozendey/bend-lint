# AGENTS: Bend code

## 2. Code

- Run `bend guide` once per session before you write Bend code. Use the `bend` on PATH, even if it
  is a fork or a different version. Also run `bend guide shaders` before parallel or performance
  work, and `bend guide effects` before a custom effect.
- Before you write a new def, look for it with `bend base <Name>`.
- Trust the checker. Bend is sound, so a proof that checks is correct. Do not look for
  counterexamples, before or after you write a law.
- Do not run `--verdict` unless I ask.
- Do not use `@unsafe`. Do not use foreign code unless I approve it.
- Hard rule: Windows runs Bend natively only with the fork in the sibling folder `../bend` (branch
  `feature/cuda-and-windows`, NVIDIA included). Outside that fork, run Bend only on WSL.

- Prefer laws, not tests. Use a test only for behavior that a law cannot state (for example, IO
  output) - NEVER WRITE LAWS WITHOUT RUNNING BY ME FIRST.
- Write a law only for a property that matters. For example, a hardcoded list does not need a law
  that it has no duplicates.
- If a proven law covers a def, use that def. Do not write or use an unproven def that does the same
  thing.
- When a law replaces another law or a test, delete the old one in the same change.
- Ask me before you review proof bodies, or code that a proven law covers. Good laws and an
  ergonomic API are the priority.

- Put code that two or more namespaces of one package use in that package's `shared.bend`.
- Write small capabilities yourself. Do not import a package for a few lines of code. If you need a
  large capability that Base and this repo do not have, and that we cannot or should not write
  ourselves, import it from BendHub (`import 0x<hash>/...` or `<name>@<version>/...`). Do not copy
  hub code into this repo. If the hub does not have it, tell me.

- Do not keep an old form for compatibility.
- Choose the representation for its access pattern first. The laws and the code follow from it.
- Keep the public API ergonomic. Put performance details behind named defs. Name defs `Type.verb`,
  as Base does.

### 2.1 Common pitfalls

These repeat `bend guide`. If they disagree, `bend guide` is correct.

- Variables are affine. To use a `Data` value again, mark it `+` (`+x`, `+x = v`, `case K{+f}`). A
  `Type` value (array, closure, handle) cannot be copied.
- Call a closure at most once. To call a function many times, pass it as a `~` template.
- Put the shrinking parameter first in a recursive call. Mutual recursion is not allowed.
- `match` only on a parameter or a pattern variable. Pass a computed value to a helper. There is no
  `if`: match on `True{}` and `False{}`.
- Write operators as `(a + b : T)`, with spaces on both sides. Compare values with `T.is_eq(a, b)`,
  not `==`.

## 3. Performance

Bend runs pure, affine code in parallel on CPU threads and on the GPU. Design for this from the
start.

For each function that processes a collection or a large amount of work, answer these questions:

1. Can the work split into independent parts of approximately equal size?
2. Is each part large enough to pay for a fork? (A job of approximately 0.3 ms loses to the pool
   wake-up.)

If both answers are yes, use a balanced fork tree (binary or 4-way). If not, use a flat loop. Write
the reason in one line in the commit message. A balanced tree or a range split is parallel. A cons
list walked from the head is sequential.

These cost rules apply to all code, not only to parallel code. Most of them repeat
`bend guide shaders`. If they disagree, the guide is correct.

- Use `+` only where the checker requires a second use.
- Do not let two consumers own one structure. Borrow it, and give the last use to one owner.
- Pass constants as `~` template arguments, not as runtime parameters.
- Bind a repeated value once. Bend does no common-subexpression elimination.
- Prefer tail recursion. A non-tail self call allocates a frame per call.
- Do not `match` on U32 literals in hot code. Use `word` or `pick` chains.
- Do not claim a speedup without a measurement. Measure as `bend guide shaders` describes.

## 4. After you write code

Ask me before the review skills review proof bodies, or code that a proven law covers.

Then run `bend <namespace>/PROOF.bend` for each changed namespace, and report the result.
