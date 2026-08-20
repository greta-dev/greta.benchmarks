# greta.benchmarks

Benchmarks for [greta](https://github.com/greta-dev/greta), kept so that a speed
claim in `NEWS.md` or in a code comment can point at the code that produced it
rather than at a number somebody typed out.

## Layout

```
provenance.R                     environment capture, shared
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
