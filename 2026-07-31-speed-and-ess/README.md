# 2026-07-31 — speed and effective samples per second across branches

Imported from the design repo's working notes, where it was written before this
repository existed. It predates the one-script-one-question convention: it is a
harness (`bench-compare.R`, `bench-worker.R`) plus three numbered experiments,
rather than a single `run.R` with one question at the top.

Kept as-is rather than reshaped, because rewriting it would break the link
between the code and the numbers it produced. `notes.md` is the original
write-up, including where greta's earlier benchmark code lived and why
effective samples per second is the right metric for sampler work.

Later runs should follow the convention in the top-level README.
