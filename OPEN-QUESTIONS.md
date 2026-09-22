# Open questions

Decisions the suite is waiting on. Each one has been measured or diagnosed, not
guessed — the evidence is recorded so the discussion can start from it rather
than re-deriving it.

Raised 2026-09-22, after the first `quick` runs.

## 1. Every branch is installed twice per run — DONE 2026-09-22

**What happens.** `cross::bench_branches()` is a thin wrapper over
`run_branches()`, and `run_branches()` unconditionally does, per branch: a
`gert` worktree checkout of greta, then `pak::pkg_install()` into a temporary
library that is deleted when the call returns. Nothing is cached between calls.

The pipeline calls into `{cross}` twice — once for `timings`, once for
`sampling` — so each branch is installed **twice per `tar_make()`**. Four
installs where two would do.

This is the only cost in the suite that grows with the number of measurement
targets rather than with the tier, so it gets proportionally worse for `quick`,
whose measurement is only ~60 s per branch.

**Resolved: merged into one `cross` call.** `measure_branches()` now runs both
tiers inside a single `run_branches()` and returns
`list(timings, sampling, rss_mb)`, unpacked by three cheap targets. Two
installs per run rather than four.

`bench_branches()` turned out to be exactly `run_branches()` plus a
recombination step, so `branch_timings()` does that recombination with the
exported `bench::as_bench_mark()` — verified that `summary(relative = TRUE)`
and `autoplot()` still work on the result.

**Accepted cost:** invalidation is now coupled. Changing `bench_iterations`
re-runs the sampling tier too. The unpacking targets keep everything
downstream separate, so only the measurement itself is shared.

**Still unmeasured:** how long an install actually takes.

## 2. The Rhat stopping rule is hardcoded below where it hurts

**What happens.** `target_progress()` in `R/sample-to-target.R` decides
`reached` with `max(rhat) < 1.01`. That is a fixed scalar compared against the
maximum of `n_variables` estimates, so the rule **tightens as a model gains
variables** — the maximum of many Rhat estimates clears 1.01 by chance.

**What it has already cost.** `wide_linear` was removed from the example set
for this and nothing else: minimum bulk-ESS 1842, comfortably past target, Rhat
1.028 across 202 variables. It sampled perfectly well and capped every run. A
model was dropped from the suite to work around a constant one file over.
`cjs` sits at Rhat 1.010 across 40 variables — one unlucky run from the same
fate, which also makes tier run times unpredictable.

`R/compare.R` already solves the identical statistical problem correctly and
explicitly: `posterior_agreement(threshold = 4)`, a named parameter with the
multiplicity reasoning written next to it. The suite knows how to handle this;
the knowledge just has not reached `sample_to_target()`.

**What the literature says.** Checked 2026-09-22.

- **Vehtari et al. (2021)** set R̂ < 1.01 *per parameter*, alongside bulk- and
  tail-ESS above 100 per chain. They do not prescribe how to aggregate across
  many parameters, which is exactly the gap we are falling into.
- **Stan practice acknowledges the problem and has no principled fix.** The
  Stan forums thread on summarising R̂ over many variables states it plainly:
  with many variables and many fits "there will almost always be some Rhats
  that are a bit larger", and the usual response is to relax to **R̂ < 1.05
  when estimating a large number of parameters**. That is convention, not
  theory.
- **Vats & Knudson (2021)** is the most directly useful. They establish a
  one-to-one relationship between the Gelman-Rubin statistic and effective
  sample size, approximately

      R̂ ≈ sqrt(1 + 1/ESS)

  and argue the conventional fixed thresholds are arbitrary — a termination
  threshold should be *derived from the ESS you want*, not picked by custom.

**What that implies for us.** Inverting the relationship, R̂ < 1.01
corresponds to ESS ≈ 50. Our `target_ess` is 200 to 1000, so the ESS condition
is four to twenty times stricter, and on that relationship the R̂ condition
should already be implied and therefore redundant.

| ESS  | implied R̂ |
|-----:|-----------:|
| 50   | 1.0100     |
| 200  | 1.0025     |
| 1000 | 1.0005     |

Empirically it is not redundant — `wide_linear` reached min bulk-ESS 1842 and
still showed max R̂ 1.028. The gap is informative: our R̂ is the
rank-normalised **folded** statistic, which is the maximum of bulk and tail
behaviour, while our stopping rule tests **bulk**-ESS only. So R̂ is failing on
something bulk-ESS cannot see — the tails — compounded by taking a maximum over
202 noisy estimates.

**Options, in the order the literature supports them.**

- **Replace the R̂ stopping condition with a tail-ESS condition.**
  `min(ess_tail) >= target` catches what folded R̂ was catching, and being a
  *minimum* it does not suffer the "maximum of many estimates" inflation that
  is the whole problem. This looks like the right answer.
- **Derive the R̂ threshold from `target_ess`** as `sqrt(1 + 1/target_ess)`,
  per Vats & Knudson. Principled, but *stricter* than 1.01, so it makes the
  capping worse rather than better.
- **Relax to 1.05 when variables are many**, following Stan convention.
  Pragmatic, unprincipled, and the number is arbitrary.
- **Make convergence a predicate argument** so any of the above is a swap
  rather than an edit, living in `tier_settings()` next to `target_ess`.

Either way R̂ should stay *reported* — it is the diagnostic that noticed
something. The question is only whether it should *stop the loop*.

If this is fixed, `wide_linear` can come back and the size axis returns with
it.

## 3. Memory is not measured, and `bench`'s memory column is the wrong tool

**What happens.** `bench::mark(memory = TRUE)` was turned off in
`measure_deterministic()`. The stated reason was size — it was 8.4 MB of an
8.5 MB object, 99.5%, and nothing read it. The better reason is that it
measures the wrong thing.

`mem_alloc` comes from `Rprofmem`, which sees the **R heap only**. greta's
memory is in the TensorFlow graph, on the Python side, where Rprofmem cannot
look. Measured on 2026-09-22:

| example  | `mem_alloc` (R heap) | process RSS growth |
|----------|---------------------:|-------------------:|
| `linear` | 4.21 MB              | 356 MB             |
| `cjs`    | 37.3 MB              | 113 MB             |

They do not merely differ in magnitude — they **rank the two models in opposite
order**. `mem_alloc` says `cjs` is 9x heavier; RSS says `linear` is 3x heavier.
(`linear` ran first and so paid TensorFlow initialisation, which inflates its
RSS. The ordering point stands regardless: one instrument cannot see the
allocation the other is dominated by.)

**What the right instrument is.** `AGENTS.md` already prescribes it: *measure
peak RSS of a short-lived process, not a delta inside a long one*, because a
delta straddling a garbage collection produces negative numbers — this repo has
recorded RSS deltas of -900 MB for that reason.

**Partly resolved 2026-09-22: RSS is now recorded per branch.** `rss_mb()` in
`R/sample-to-target.R` reports it, `measure_branches()` collects it at the end
of each branch's subprocess, and the report has an RSS table.

**RSS means resident set size** — the physical RAM a process currently holds.
Not residual sum of squares. Worth saying in the report too, which it now does,
because this is a statistics repository and the acronym is taken.

**What is still not right.** This is **end-of-run RSS, not a true peak.** A
peak needs `getrusage()`'s `ru_maxrss`, which R does not expose, and macOS has
no `/proc/self/status` to read `VmHWM` from — `ps::ps_memory_info()` returns
`rss`, `vms`, `pfaults`, `pageins` and no high-water mark. For a short-lived
process doing monotonically growing work, where TensorFlow does not release
memory back to the OS, the two should be close, but that is an assumption and
not a measurement.

It is also **one number per branch, not per example**, because both tiers now
share one subprocess (item 1). Attributing memory to a particular example would
need one process per measurement, which is the option below.

**Remaining options.**

- **One process per measurement.** Gives per-example attribution and a
  meaningful high-water mark per cell. Costs a process launch and a TensorFlow
  initialisation per cell — roughly 3 s each, measured — and cuts against
  building all examples in one process, which is what makes the warm-up
  affordable.
- **Sample RSS on a timer during the run and keep the maximum.** Gets closer to
  a real peak without extra processes.
- **Accept end-of-run RSS per branch**, which is the current state, now
  documented.

Whichever is chosen, `mem_alloc` stays off: a number that ranks models
backwards is worse than no number.
