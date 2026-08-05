# greta.benchmarks

Benchmarks for [greta](https://github.com/greta-dev/greta), kept so that a speed
claim in `NEWS.md` or in a code comment can point at the code that produced it
rather than at a number somebody typed out.

## Layout

```
provenance.R                     environment capture, shared
2026-08-05-keras3-vs-main/
  run.R                          the exact script that produced these results
  results.md                     the question, the numbers, the environment
  results.rds                    raw output, so a summary can be recomputed
```

One directory per run, named for its date and its question. A run directory is
a lab notebook entry: once written it is never edited, and a later run of the
same comparison gets a new directory rather than overwriting an old one. A
`NEWS.md` entry linking here has to keep pointing at the numbers it was written
about.

## Running one

```bash
cd 2026-08-05-keras3-vs-main
Rscript --quiet --vanilla run.R
```

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
