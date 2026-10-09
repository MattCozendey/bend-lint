# Performance rules

The `performance/` rules find Bend code that runs slower than it must. They
target the habits of code that LLMs write: linked lists everywhere, needless
clones, and parallelism done wrong.

A finding is the main result. A fix is a bonus: an agent can apply the
recommendation, or the user can suppress the finding.

## Samples

Each case is a folder in `samples/`:

| File          | Holds                                                |
| ------------- | ---------------------------------------------------- |
| `before.bend` | the slow code, as an LLM writes it                   |
| `after.bend`  | what an agent made of it, with the linter's findings |

An agent writes `after.bend`, not a human:

1. It gets a copy of `before.bend`, under a neutral name, in an empty folder.
   It is not told about `before.bend`.
2. It runs the linter, and follows each finding's recommendation strictly. It
   may apply the linter's own fixes (`--fix`).
3. After each change by hand, it adds a line `# agent: <what, and which
   finding asked for it>`.
4. Its output goes to `after.bend` unchanged, failed or not. It is the proof.

Before `after.bend` is kept, check that the agent changed only what the
findings asked for. Whether `after.bend` is valid, and does what
`before.bend` did, is the user's call.

## Measuring

The linter runs on Bend's JavaScript lane, which runs one thread. Speed is
measured on the native lane, which needs clang. On Windows, use WSL:

```sh
bend before.bend -o /tmp/before
time /tmp/before --threads 1
time /tmp/before --threads 16
```

- Run `bend` from a login shell (`bash -l`). Else WSL's `PATH` can find the
  Windows `bun.exe`, the build fails, and an old binary runs.
- The GPU (`!`) is not measured. Without a GPU, it falls back to the CPU
  threads.

## Rules

### `performance/missed-fork`

Bend forks only the values of a parallel let (`a b = f(x) f(y)`). The rule
reports two calls of a def to itself that run one after another:

- in one expression: `U32.add(f(x), f(y))`, `Node{f(x), f(y)}`,
  `f(x) + f(y)`;
- in lets that follow each other: `l = f(x)`, then `r = f(y)`.

The fix moves the calls into a parallel let. Bend is pure, so it is `safe`.
There is no fix when the text cannot be rewritten reliably: a typed let, a
call over several lines, or an expression inside a lambda.

Sample `samples/missed-fork/`: a 2000-round xorshift hash of 2^18 seeds,
summed over a range split in halves.

| File          | 1 thread | 16 threads |
| ------------- | -------- | ---------- |
| `before.bend` | 0.82 s   | 0.81 s     |
| `after.bend`  | 0.83 s   | 0.08 s     |

Agent result:

- 1 finding, with a `safe` fix. The agent applied it with `--fix`, and made
  no change by hand.
- Its change is exactly the merge the finding asked for. It touched no other
  file.
- 3 tool calls, 13 s.

### `performance/list-index-loop`

A def passes a list parameter unchanged to its own call, and gives it to
`List.get`, `List.drop`, `List.take`, `List.last` or `List.length`. Each of
those walks the list from its head, so the loop is O(n²). The finding says
what to do instead: walk the list, or, for `List.length`, compute it once
before the loop.

There is no fix: the rewrite changes the loop's parameters.

A lookup one call deep counts too: a def of the file that gives the list to
one of those (`at(xs, i)`).

Sample `samples/list-index-loop/`: the dot product of two lists of 16000
values, by index.

| File          | 1 thread     | 16 threads   |
| ------------- | ------------ | ------------ |
| `before.bend` | 3.07 s       | 3.13 s       |
| `after.bend`  | under 0.01 s | under 0.01 s |

Agent result:

- 2 findings (`xs` and `ys`), without a fix. The agent rewrote the loop by
  hand, with a comment after each changed line.
- It changed only the loop step the findings point at, and touched no other
  file. The result is the same.
- It left `i` and `or_zero` unused, rather than clean up what no finding
  asked for, and said so.
- 4 tool calls, 28 s.
- Its comment lines break `layout/format`. It ran only the performance rules.

### `performance/append-in-loop`

A def passes `List.append(acc, ..)` or `acc ++ ..` to its own call, for its
parameter `acc`. Each append copies `acc`, so building it is O(n²). The
finding says to build at the head and reverse once, or, for a string, to
collect the pieces and join them once. Its advice spells the call's
quantity and type, so that it compiles as written.

There is no fix: the rewrite changes the loop's end.

Sample `samples/append-in-loop/`: the squares of 0 .. 29999, collected in a
list.

| File          | 1 thread     | 16 threads   |
| ------------- | ------------ | ------------ |
| `before.bend` | 1.68 s       | 1.69 s       |
| `after.bend`  | under 0.01 s | under 0.01 s |

Agent result:

- 1 finding, without a fix. The agent made the two changes it asked for by
  hand, with a comment after each: cons at the head, and reverse when the
  loop ends. The result is the same.
- The finding then suggested `List.reverse(acc)`, which does not compile.
  The agent found the right call, `List.reverse(&2, U32, acc)`, and
  reported the mistake. The advice now spells it.
- 4 tool calls, 23 s.
- Its comment lines break `layout/format`. It ran only the performance rules.

### `performance/deep-call-in-fork`

A def has a parallel let, and its values, or the lets just before it, call
a def of the file that recurses without a tail call. In our tests, such a
call at each fork cut the 16-thread speedup from 10x to 1.9x. The same call
in a leaf, a helper that does not recurse, or the same def with a tail
call, kept the 10x. Why the runtime does this is not known.

The finding says to make the callee tail-recursive with an accumulator, to
compute the value with native operations (`U32.shln(1, p)`), or to pass it
down as a parameter. There is no fix.

Sample `samples/deep-call-in-fork/`: the `missed-fork` sample, but each
fork computes the half's size with a `pow2` on `Nat`.

| File          | 1 thread | 16 threads |
| ------------- | -------- | ---------- |
| `before.bend` | 0.86 s   | 0.42 s     |
| `after.bend`  | 0.83 s   | 0.10 s     |

Agent result:

- 1 finding, without a fix. The agent took the first option: it made `pow2`
  tail-recursive with an accumulator, and passed the start value at the
  call. Each change has a comment. The result is the same.
- 3 tool calls, 22 s.
- Its comment lines break `layout/format`. It ran only the performance rules.

## Candidates

Measured on an x86 CPU with 20 threads, Bend 2.0.36.

| Pattern                                                          | Detect | Fix             | Gain measured                                                                                             |
| ---------------------------------------------------------------- | ------ | --------------- | --------------------------------------------------------------------------------------------------------- |
| index-split fork: the whole collection shared, split by an index | medium | split the data  | 1.4x (`samples/matrix-vector/`); list-index-loop and deep-call-in-fork report it; neither advises a split |
| a `+` value that every leaf reads                                | easy   | none in general | about 2x, also on one thread                                                                              |
| loops that are not tail calls                                    | easy   | accumulator     | almost none in native code                                                                                |

On the GPU, not measured:

- A missed fork costs more: a `!` call spreads forks over thousands of lanes.
- A shared `+` value costs more: each lane reads it with an atomic.
- The list and append patterns cost the same: their gain is O(n²) to O(n).
