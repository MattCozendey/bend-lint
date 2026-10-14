# Results

Each row applies what a rule asked to one project in this folder, as the rule asks, without tuning.
Its commit shows the code before and after, and times both on the same machine and build. Rule
headers hold the other measurements: small programs written to time one pattern.

| Commit | Project | Rule | Change | Lane | Result |
| --- | --- | --- | --- | --- | --- |
| [`4b8c2bd`](https://github.com/MattCozendey/bend-lint/commit/4b8c2bd) | slash_boss_3d, three-bodies, raytracing-bend2 | language/unneeded-plus | removed 1,049 `+` | all | the same C: no change |
| [`007f41a`](https://github.com/MattCozendey/bend-lint/commit/007f41a) | BendSR | performance/gpu-fit | removed each `!` | GPU | compute_mae 6.5 s → 0.08 s (80x faster); `--gpu off`: 0.11 → 0.07 s |
| [`44947f4`](https://github.com/MattCozendey/bend-lint/commit/44947f4) | BendSR | performance/missed-fork | forked `eval`'s calls, on top of the row above | CPU | 230x slower |
| [`b19bb51`](https://github.com/MattCozendey/bend-lint/commit/b19bb51) | bend-bench (6 benchmarks) | performance/gpu-fit (its hint to add a `!`) | added 7 `!` | GPU | never faster; tree-matmul 4.6x slower |
| [`e29ce75`](https://github.com/MattCozendey/bend-lint/commit/e29ce75) | raytracing-bend2 | performance/deep-call-in-fork | made `evens` and `odds` tail-recursive | CPU | 4% to 8% faster |
| [`faf7a11`](https://github.com/MattCozendey/bend-lint/commit/faf7a11) | llama.bend | performance/append-in-loop, performance/deep-call-in-fork | applied their 4 findings | CPU | no change |
| [`eb21979`](https://github.com/MattCozendey/bend-lint/commit/eb21979) | llama.bend | performance/unused-result | built `Act` empty | CPU | 19% to 25% faster per token |
| [`71a6d36`](https://github.com/MattCozendey/bend-lint/commit/71a6d36) | bend-ml (tensor-array, as llama.bend uses it) | performance/missed-fork | forked 4 pairs of calls | CPU | no change |
| [`be56d3e`](https://github.com/MattCozendey/bend-lint/commit/be56d3e) | bend-ml (bpe, as llama.bend uses it) | performance/dead-accumulator | erased `done` (`-done`) | CPU | 26.1 s → 11.5 s to tokenize 19 KB (2.3x faster) |
| [`2440ca2`](https://github.com/MattCozendey/bend-lint/commit/2440ca2) | llama.bend (tokenizer) | performance/repeated-call | computed `lcl(run, 0n)` once | CPU | no change |
| [`1c9480a`](https://github.com/MattCozendey/bend-lint/commit/1c9480a) | eldergrove-faire | performance/repeated-call | computed 3 list lengths once | CPU | no change |

The commits that restore a file as pinned, and the last one, `aeff4bd`, put the authors' code back.
