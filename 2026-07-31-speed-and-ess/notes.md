# Benchmarking greta across branches: speed and effective samples per second

## Where the existing code was

The code Nick remembered does exist, in three places, none of them committed as
a runnable benchmark:

| what | where | state |
|---|---|---|
| **speed** workloads | `touchstone/script.R` in greta | four `benchmark_run()` tasks: `create_normal`, `create_model`, `run_mcmc`, `basic_example`. Touchstone itself is **retired**, but the tasks are good |
| **effective samples per second** | **greta issue #790**, "code for comparing HMC to Adaptive HMC" | Golding's script. Lives only in the issue body — not in the repo at all |
| ESS convergence helpers | `tests/testthat/helpers.R:787-860` | `need_more_samples()`, `new_samples()`, `get_enough_draws()`, and an `mcse()` batch-means helper. Used by the posterior tests, not for benchmarking |

Issue #790's metric is the important one:

```r
worst_efficiency <- function(draws, time) {
  neffs <- coda::effectiveSize(draws)
  min(neffs) / time["elapsed"]
}
```

Effective samples per second of wall clock, for the **worst-sampled** variable.
Higher is better. It is the right metric for sampler work because raw speed is
actively misleading — the smoke test below shows `hmc(Lmin = 1, Lmax = 3)`
finishing in 0.79s against plain `hmc()`'s 1.16s, while delivering *less than
half* the effective samples per second. A faster sampler that mixes worse is a
worse sampler.

The design book already refers to this at
`milestone-06-faster-sampling.qmd:367` ("the efficiency case — `adaptive_hmc()`
far outperforms `hmc()` on effective sample size") but the evidence was never
turned into runnable code.

## What is here

Two scripts that consolidate the above into a branch-comparison harness.

- **`bench-worker.R`** — benchmarks ONE (branch, python stack) combination in
  the current session and writes a tidy `.rds`. Runs the four touchstone speed
  tasks, then the #790 efficiency comparison over a correlated multivariate
  normal in `easy` and `hard` configurations, reporting `ess_per_sec`,
  `min_ess`, `elapsed` and `worst_rhat` per sampler.
- **`bench-compare.R`** — the orchestrator. Creates a `git worktree` per
  branch, runs the worker once per combination, collects everything and prints
  a comparison table with ratios against the first branch named.

Samplers are discovered per branch with `exists("adaptive_hmc")`, so a branch
that has `adaptive_hmc()` is compared against one that does not without the
harness needing to know which is which.

## Two rules the harness enforces

**Separate R sessions.** reticulate initialises Python once per process, so one
session cannot switch TF stacks, and a warm TF times differently from a cold
one. Each combination gets a fresh `Rscript`.

**Strictly in series.** These are wall-clock measurements. Two R sessions
running concurrently contend for the same cores and both numbers become
meaningless. `bench-compare.R` uses a blocking `system2()` and never
parallelises. Don't "speed it up" — and don't use the machine for anything else
while it runs.

Worktrees mean the working tree and any uncommitted changes are never touched,
which matters here because the greta checkout usually has work in progress.

## Usage

```bash
cd notes/benchmarks

# quick smoke test, one branch, greta's default python
GRETA_QUICK=true Rscript bench-compare.R main

# compare two branches
Rscript bench-compare.R main add-snaper-hmc

# compare branches AND python stacks (every branch against every stack)
GRETA_PYTHONS="tf215=/tmp/tf215/bin/python,tf221=/tmp/tf221/bin/python" \
  Rscript bench-compare.R main keras3-optimisers
```

Knobs: `GRETA_QUICK=true` (shrinks everything for a smoke test),
`GRETA_REPS`, `GRETA_CHAINS`, `GRETA_WARMUP`, `GRETA_REPO`, `GRETA_BENCH_DIR`.

The first branch named is the reference; ratios are reported against it.

## The convergence gate, and why it is there

The harness refuses to compare efficiency for runs whose chains did not
converge (`worst_rhat >= 1.1`). This is not defensive decoration — it came out
of the first two-branch run I did.

Comparing `main` against `keras3-optimisers`, whose sampling code is
**byte-identical** (the branch only changes optimisers), the harness reported:

```
mvn_easy/hmc   main 16.57 ess/s   keras3 390.2 ess/s   -> "23.55x faster"
```

`main`'s run had `worst_rhat = 3.0`. The chains had not converged, so its ESS
was meaningless and the 23x was pure artefact. Without the gate, that number
goes in a report.

Two lessons worth carrying into milestone 6:

- **ESS is only interpretable after convergence.** Always report rhat beside
  it.
- **`GRETA_QUICK=true` is for checking the plumbing, never for conclusions.**
  Short warmup is exactly when this happens.

## Replication, and the noise floor

The convergence gate alone was **not enough**. With it in place and proper
settings (4 chains, 1000 warmup), the same identical-sampling-code comparison
still reported:

```
mvn_easy/hmc   main 193.1 ess/s   keras3 1190 ess/s   -> "6.16x"
               rhat 1.025          rhat 1.003          both converged
```

A converged run's ESS still varies by several-fold between runs, because the
sampler is not seeded. One run per cell cannot support any claim.

So the worker now runs **`GRETA_ESS_REPS` replicate MCMC runs per cell**
(default 5, 2 in quick mode), reports the median, and reports
`ess_per_sec_spread` = max/min across replicates. The comparison prints a
**noise floor** at the end:

> Noise floor: within-branch `ess_per_sec` varied by up to N× across
> replicates. Treat any branch-to-branch ratio below that as noise.

That is the number to check before believing any efficiency claim — including
the ones in `milestone-06-faster-sampling.qmd`. It also strengthens the case
for pulling the seed issues (#285/#427) forward: until `set.seed()` controls
the sampler, every sampler comparison costs 5× the runs to say anything.

### The measured noise floor

Two independent runs of the identical configuration (5 replicates, 4 chains,
1000 warmup, TF 2.21, `main` vs `keras3-optimisers` — branches whose sampling
code is byte-identical).

`ess_per_sec_spread`, max/min across the 5 replicates within one branch:

| task | run A: main / keras3 | run B: main / keras3 |
|---|---|---|
| `mvn_easy/hmc` | 7.87× / 2.61× | **55.7× / 233.1×** |
| `mvn_easy/hmc_short_leapfrog` | 1.51× / 1.20× | 1.30× / 1.19× |
| `mvn_hard/hmc` | 1.51× / 1.59× | 1.62× / 1.53× |
| `mvn_hard/hmc_short_leapfrog` | 2.04× / 1.60× | 1.35× / 1.24× |

**The noise floor is not a stable quantity.** For `mvn_easy/hmc` it was 7.9× in
one run and 233× in the next. Do not quote a single figure for it; measure it
inside every comparison, which is what the harness now does.

Wall clock, by contrast, is trustworthy: `elapsed` ratios between the two
branches stayed within 0.98–1.02× on every task in both runs. **It is ESS
specifically that is unstable, not timing.**

The practical consequences:

- **Efficiency comparisons on `hmc()` need replication and a reported spread**,
  every time. No single-run efficiency claim on this workload is supportable.
- The variance is strongly sampler- and configuration-dependent:
  `hmc_short_leapfrog` sits at a well-behaved 1.2–1.5× throughout.
- `mvn_hard` never converges under any `hmc()` variant (rhat 22–34 across both
  runs). That failure *is* the argument for adaptive HMC, and the comparison
  #790 was written to make.

### Flagged: `mvn_easy/hmc` sometimes fails to converge

`mvn_easy` is a 4-dimensional **standard** multivariate normal — `correlation =
0`, all marginal SDs 1, so `Sigma` is the identity. It should be trivial to
sample. Yet across the two runs, plain `hmc()` on it produced:

| | main | keras3-optimisers |
|---|---|---|
| run A | rhat 1.06 (converged) | rhat 1.00 (converged) |
| run B | rhat 1.04 (converged) | **rhat 16.56 (failed)** |

with 4 chains and 1000 warmup. A worst-case rhat of 16.6 on an identity-covariance
Gaussian is not obviously "just noise", and it is the same cell that produces
the extreme efficiency spreads above. Worth isolating: run `mvn_easy/hmc` alone
30–50 times and look at the distribution of rhat and min ESS. If a meaningful
fraction fail, that is a sampler or initialisation defect, not benchmark
variance — and it belongs in milestone 6 as a bug rather than a tuning note.

## Smoke test output

`main`, quick mode, TF 2.15:

```
-- ess_per_sec --
                        task main@tf215
                mvn_easy/hmc      569.3
 mvn_easy/hmc_short_leapfrog      281.5

-- elapsed --
                mvn_easy/hmc      1.161
 mvn_easy/hmc_short_leapfrog      0.789
```

## Worth doing next

1. **Promote this into greta** as `benchmarks/`, replacing the retired
   `touchstone/` directory. It is more useful living next to the code it
   measures.
2. **Run it against the adaptive-HMC branches** — `adaptive-hmc-v3-i765`,
   `add-snaper-hmc`, `new-adaptive-smoothing`. That is the comparison #790 was
   written for and the evidence milestone 6 claims but does not hold.
3. **Close #790 by committing the code**, rather than leaving the only copy in
   an issue body.
4. **Seeding.** greta's sampler is not controlled by `set.seed()` (#285/#427),
   so ESS numbers vary run to run. Treat single runs as indicative; for a real
   claim, repeat and report spread. This is a live argument for fixing the seed
   issues earlier than milestone 6.
