# greta.benchmarks

Benchmarks for [greta](https://github.com/greta-dev/greta), kept so that a speed
claim in `NEWS.md` or in a code comment can point at the code that produced it
rather than at a number somebody typed out.

**Posts** are the current way to benchmark, and are published as a website at
<https://greta-dev.github.io/greta.benchmarks/>. Before them there were two
halves, still described below: **the standing suite is a `targets` pipeline**
at the repository root, and **dated run directories** answer one-off questions
and are kept as lab notebook entries. They stay until the posts cover what they
did.

## Posts

```
_quarto.yml                      the website; renders index.qmd and posts/ only
index.qmd                        the list of posts
posts/2026-10-05-retracing-i546/
  run.R                          every measurement, in one cross::run_versions()
                                 expression; run it to make results/
  results/session-<n>.rds        raw output, one file per session, committed
  index.qmd                      reads results/, shows run.R in full
_template/                       a post to copy
.github/workflows/publish.yml    renders the site and deploys it to GitHub Pages
```

A post's `run.R` holds all of the code that is measured: the models, the
settings and the timed calls, inside one expression that
`cross::run_versions()` evaluates in a fresh R session for each version. The
page reads `results/` and never runs greta, and the code it shows, including
each model's, is read out of `run.R`, so it is the code that ran.

To make a post:

1. Copy `_template/` to `posts/YYYY-MM-DD-short-name-iNNN/`.
2. In `run.R`, pin the versions to commits and set `results_dir` to the new
   directory. Change the models or settings if the question needs it.
3. Run it: `Rscript --quiet --vanilla posts/<post>/run.R`. Sessions already in
   `results/` are skipped, so a rerun after a crash carries on.
4. Edit `index.qmd`'s title, description and opening sentence, and look at it
   with `quarto preview`.
5. Commit `run.R`, `results/` and `index.qmd`. HTML is not tracked: pushing to
   main renders the site and deploys it.

## Layout

```
_targets.R                       the pipeline: what is measured, and with what
packages.R                       every library(), sourcing conflicts.R last
conflicts.R                      declared winners, with the reason for each
R/                               every function in the project
  examples.R                     bench_examples(), the posteriors
  measure.R                      the two measurements
  sample-to-target.R             sample until the chains are good enough
  compare.R                      do the branches estimate the same posterior?
  tiers.R                        quick / standard / thorough, and what they cost
  provenance.R                   environment capture, shared with run dirs
report.qmd                       reads the targets, renders to self-contained HTML
references.bib                   citations for the methods section
OPEN-QUESTIONS.md                decisions the suite is waiting on

2026-08-20-warmup-trace/
  01-measure.R                   the exact script that produced these numbers
  02-report.R                    renders results.qmd
  results.qmd                    the write-up; reads results.rds, computes
                                 every number it quotes
  results.md                     rendered output, the thing you link to
  results.rds                    raw output, so a summary can be recomputed
  issue.md                       where a run is written up as a greta issue
```

Two scripts, numbered, and neither calls the other. Measuring is expensive and
sometimes installs package branches, so it is not something to trigger by
accident when fixing a typo. Report second, as often as you like.

**Prose that mentions a number computes it.** Use inline R rather than typing
the figure into the text: a re-run changes the numbers, and hand-written ones
silently stop matching the table above them.

**Anything mutable gets captured at measure time**, not at report time. Git
SHAs are the trap: branches move, so resolving one while rendering records a
different commit than the one measured.

**Link every SHA you record**, to
`https://github.com/greta-dev/<repo>/commit/<sha>`, so a reader can click
through to the commit rather than copy it into a terminal. Check the repo is
public first — a link into a private repo is a dead end for everyone but you.

One directory per run, named for its date and its question. A run directory is
a lab notebook entry: once written it is never edited, and a later run of the
same comparison gets a new directory rather than overwriting an old one. A
`NEWS.md` entry linking here has to keep pointing at the numbers it was written
about.

## The standing suite

A `targets` pipeline comparing two branches of greta on a fixed set of
posteriors. Use it to check a change before opening a pull request; use a dated
run directory to answer a one-off question.

```r
targets::tar_make(callr_function = NULL)  # build what is out of date
targets::tar_visnetwork()                 # the graph
targets::tar_read(sampling)               # any target's value
```

**`callr_function = NULL` is required**, and it is not the usual advice.
`tar_make()` normally runs the pipeline inside its own `callr` process, and
{cross} spawns further `callr` subprocesses and pak installs inside that. The
nesting segfaults with `segfault from C stack overflow` as soon as the first
measurement starts. Everything else works - the measurement functions called
directly, `cross` with a trivial expression, the same benchmark body against an
installed greta - so it is the nesting specifically. The cost is that the
pipeline runs in your session rather than a clean one, so start from a fresh R
session for a run you intend to quote.

Edit `branches` in `_targets.R` to choose what is compared. The branch under
test goes second, both must be committed, and {cross} installs each one.

Decisions the suite is waiting on are in `OPEN-QUESTIONS.md`.

### Tiers

The tier sets how hard the suite pushes. It is read from the environment
variable `GRETA_BENCH_TIER`, and is `quick` when that is unset:

```sh
GRETA_BENCH_TIER=flash Rscript -e 'targets::tar_make(callr_function = NULL)'
```

Every tier runs all three tasks - a tier that skipped `mcmc()` could not catch
a sampling regression, and that is what the suite is for.

| tier | examples | `target_ess` | `reps` | `mcmc_repeats` | `bench_repeats` | when |
|---|---|---|---|---|---|---|
| `flash` | 1, `linear` | 200 | 5 | 10 | 10 | a first look |
| `quick` | 4 | 200 | 3 | 5 | 10 | before a commit |
| `standard` | 5 | 500 | 5 | 10 | 30 | before a pull request |
| `thorough` | 5 | 1000 | 5 | 20 | 50 | before a CRAN release |

Measured cost, in seconds, at the settings of 2026-09-21, which ran 1, 1 and 3
sampling runs; sampling now costs about `reps` times as much:

| tier | deterministic | sampling | per branch | two-branch comparison |
|---|---|---|---|---|
| `quick` | 18 | 42 | 60 | **120** (2.0 min) |
| `standard` | 66 | 122 | 188 | **376** (6.3 min) |
| `thorough` | 92 | 705 | 797 | **1594** (26.6 min) |

From `2026-09-21-tier-costs/`. Add however long {cross} takes to install each
branch, which has not been timed.

The three settings are different things and the names are worth keeping
straight:

- **`target_ess`** is a *quality* target, not a number of draws - sampling
  continues until the worst-mixing variable reaches this bulk-ESS. It does not
  map to a fixed time: `cjs` reaches 4,700 on its first pass so raising its
  target is free, while `eight_schools` needs 2,400 draws for 500 and 64,180
  for 1,000.
- **`reps`** is how many times each branch runs each example's sampling
  measurements: `mcmc()` to the ESS target, and the seeded fit.
- **`mcmc_repeats`** is how many fixed-length `mcmc()` runs are timed per
  example per branch; each run's ESS is kept too.
- **`bench_repeats`** is the fewest times `bench::mark()` repeats building the
  model and `opt()`; it stops at twice that. Nothing to do with MCMC
  iterations.

`quick` excludes `cjs`, which costs 38 s in the deterministic tier and 73-93 s
in the sampling tier - more than half a full pass on its own. It is in
`standard` and `thorough`, so anything touching graph construction is covered
before a PR.

**Before quoting a ratio, rebuild both branches together.** Two branches
measured on different days are not a comparison - the machine's thermal state
and whatever else was running are part of the number:

```r
targets::tar_invalidate(c(timings, sampling))
targets::tar_make()
```

That is also why no measurement is cached across a question. Everything else in
the pipeline is, so a wording change in `report.qmd` costs a render and not an
hour.

### The tasks

Each is named for the greta function it calls, so a result says which entry
point regressed. The engine is a column rather than part of the name, so adding
`opt(bfgs())` or `mcmc(nuts())` is another row and not another name to learn.

| task | call | metric |
|---|---|---|
| `model` | `model()` | wall time. Constructing the DAG and the TensorFlow graph, which both inference paths pay |
| `opt` | `opt(optimiser = adam())` | wall time. 100 optimiser iterations |
| `mcmc` | `mcmc()` | seconds to reach a target minimum bulk-ESS |

`mcmc` fixes the quality and measures the cost, rather than fixing the
iterations and gating on quality. A gate discards every run that misses it - at
greta's defaults that was 47 runs in 50, which left nothing to compare. Here a
branch that cannot reach the target is reported with `hit_cap = TRUE` instead
of vanishing.

`opt` runs `adam()` rather than `opt()`'s default `bfgs()`, because `adam()` is
a `tf_optimiser` driven from an R loop and so does exactly 100 identical round
trips, which is what `bench::mark()` needs. `bfgs()` runs its loop inside the
TensorFlow graph and stops at a tolerance, so its iteration count depends on
the data. **A change touching only `tfp_optimiser` is invisible here.**

### The examples

In `R/examples.R`, taken from greta's own `inst/examples/` so the suite
measures models people actually write. They are the `example` column in the
results - `example` rather than `model`, because `model` is a task.

| example | variables | why it is here | sec per 1000 ESS |
|---|---|---|---|
| `linear` | 3 | the cheapest real model - a floor for per-iteration overhead | 6.5 |
| `multiple_linear` | 8 | matrix multiply in the gradient | 16.0 |
| `hierarchical_linear` | 6 | `rbind` and integer indexing | 23.1 |
| `eight_schools` | 11 | **the funnel** - `eta ~ normal(0, sigma_eta)` with the scale estimated | 17.9 |
| `cjs` | 40 | **the deep graph** - a 19-step recursion, so node count is the cost | 12.5 |

All five reach a 500 minimum bulk-ESS target without capping, and one pass over
the set costs about 135 seconds. Measured in
`2026-09-21-example-baseline/`.

`eight_schools` is Neal's funnel in applied form: the scale of `eta` is itself
a parameter, so the posterior narrows to a point and a fixed step size either
cannot enter the neck or gets stuck in it. It is here for geometry rather than
size - eleven parameters, nine seconds.

Three examples were removed on 2026-09-21, after being measured rather than on
suspicion: `factor_analysis` (identified only up to an orthogonal rotation, so
Rhat is bad however well the sampler works), `wide_linear` (sampled fine but
capped on `max(rhat)` across 202 variables), and `hierarchical_slopes_corr`
(542 seconds per 1000 ESS, 20-80x everything else). The reasoning and the
numbers are in `R/examples.R`.

**That leaves cholesky performance uncovered.** `lkj_correlation()` and
`chol()` go through `CorrelationCholesky`, whose gradients XLA cannot compile,
and no remaining example touches that path. Correctness is still covered by
greta's own tests; a speed regression there would not show up here.

**Check the posterior geometry before adding an example.** `linear` regresses
on `attitude$complaints` uncentred, so its intercept and slope correlate at
-0.97 and both mix far more slowly than `sd` does. At 4 chains x 1000 that read
as "greta does not converge" when it only meant the chain was too short; at
4 x (2000 warmup + 4000) all three clear comfortably. An example like that
measures the shape of its own posterior rather than greta.

### Reading the result

**Check the resolution table before the ratios.** A ratio is only meaningful
when the difference between branches is larger than the spread within one. This
is not a theoretical worry: comparing `wire-jit-compile` against `main` at 10
iterations gave 27 ms and 62 ms on separate runs, and only at 50 iterations did
it resolve to 42 ms with a 95% interval of 9 to 55 ms. A small run of a real
effect looks exactly like no effect.

A worked check that the guard works: running at 3 iterations on a branch whose
only changes were code comments gave ratios of 0.964, 1.007 and 0.964 - which
reads as "3.6% faster" and is entirely noise. Every cell of the resolution
table said unresolved. That is the table doing its job; trust it over the
ratios.

If a cell is unresolved, raise `iterations` in `_targets.R` rather than
reporting the median.

## The runs so far

```
2026-07-31-speed-and-ess/        speed and effective samples per second across
                                 branches; predates the one-script-one-question
                                 convention, so it is a harness plus numbered
                                 experiments rather than a single run.R
2026-08-05-keras3-vs-main/       does porting the optimisers to Keras 3 make
                                 greta slower?
```

## Running one

```bash
Rscript --quiet --vanilla 2026-08-20-warmup-trace/01-measure.R
Rscript --quiet --vanilla 2026-08-20-warmup-trace/02-report.R
```

Run from the repository root: the scripts use `here()`, so they do not depend on
the working directory.

The two runs before `2026-08-19` predate this layout and keep a single `run.R`
that both measures and writes its own `results.md`. They are left alone rather
than converted, for the same reason a run directory is never edited: their git
SHAs and Python stacks were resolved when the write-up was generated and are not
stored in `results.rds`, so regenerating those files would record commits that
were never measured.

`GRETA_REPO` sets where the greta checkout lives, defaulting to
`~/github/greta-dev/greta`. Runs that compare branches need those branches
pushed, so the comparison is reproducible by someone who is not you.

## Two rules

**Run these by hand, on a machine you know.** Not in CI. Wall-clock timings from
a shared runner are too noisy to quote, and effective-sample-size measurements
are worse: within-branch ESS on one greta task has varied by 233x between
replicates of the same configuration. Correctness tests belong in greta's own
suite, where CI runs them.

**One script, one question.** The question goes at the top of `run.R` and again
in `results.md`. A script that answers three questions cannot be linked to from
a claim about one of them.

## What "reproducible" means here

Not "the same numbers". Timings are bound to the CPU, its thermal state, and
whatever else the machine is doing, so nobody else will reproduce them, and a
future run on this machine will not either.

It means the *procedure* is reproducible and the *environment* is recorded.
Every `results.md` carries the OS, architecture, CPU, R version, package
versions, the resolved Python, TensorFlow and TensorFlow Probability versions,
and the greta commit SHAs being compared. Read ratios within a run; ignore
absolute numbers across runs.

Two things are deliberately not done. There is no container, because it would
change CPU scheduling and add overhead, distorting the thing being measured in
exchange for a reproducibility that is not available anyway. And branch *names*
are not the record: `main` moves, so each run stores the SHAs it actually
compared.

## Why shared helpers are kept to a minimum

`provenance.R` is shared because what it returns is written into `results.md`
when a run happens, so editing it cannot change what a past run recorded.
Analysis code has no such protection: refactor a shared benchmark helper and
every earlier run's numbers were produced by code that no longer exists. So each
`run.R` is self-contained and duplication between runs is expected.
