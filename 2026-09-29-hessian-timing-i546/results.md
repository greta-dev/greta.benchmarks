# opt(hessian = TRUE) on main and greta#843


## The question

greta#843 changes how `opt(hessian = TRUE)` takes hessians: one graph
build for all targets rather than one per target, and TensorFlow’s
`pfor` jacobian only for targets of at least 100 elements, with a while
loop below that. How long does `opt(hessian = TRUE)` take on `main` and
on the branch, and does the threshold of 100 sit where the two jacobian
routes cross?

Each replicate is a fresh R process that builds the model and times
`opt(hessian = TRUE)` twice: the first call, which includes TensorFlow
tracing and is what a user waits for, and a second, once traced. 5
replicates per cell.

## main against the branch

| shape | main | faster-hessians-i546 | resolved | speedup |
|:---|:---|:---|:---|:---|
| 5 scalar targets | 1.26 (1.25-1.40) | 0.51 (0.47-0.71) | TRUE | 2.5x |
| 20 scalar targets | 12.46 (12.09-13.75) | 1.95 (1.90-2.03) | TRUE | 6.4x |
| one target of 100 | 0.19 (0.18-0.21) | 0.20 (0.20-0.21) | FALSE | not resolved |
| one target of 400 | 0.19 (0.19-0.25) | 0.21 (0.20-0.23) | FALSE | not resolved |

First call to opt(hessian = TRUE), seconds: median (range)

With 20 scalar targets, the case \#546 reported, the first call takes
12.46 s on main and 1.95 s on the branch (medians, 5 replicates each;
ranges 12.09-13.75 and 1.90-2.03).

## pfor against the while loop, on the branch

| shape             | pfor             | while loop       | faster     | resolved |
|:------------------|:-----------------|:-----------------|:-----------|:---------|
| 5 scalar targets  | 1.12 (1.11-1.16) | 0.47 (0.47-0.47) | while loop | TRUE     |
| 20 scalar targets | 8.11 (8.01-9.14) | 1.97 (1.87-2.67) | while loop | TRUE     |
| one target of 100 | 0.20 (0.20-0.23) | 0.23 (0.23-0.24) | pfor       | FALSE    |
| one target of 400 | 0.21 (0.20-0.29) | 0.44 (0.42-0.53) | pfor       | TRUE     |

First call, seconds: median (range), each route forced

greta uses `pfor` for targets of at least 100 elements. The table shows
which route is faster at each shape measured; the threshold is right if
the while loop wins below 100 and `pfor` at or above it.

## Environment

- `main` at
  [282944f5](https://github.com/greta-dev/greta/commit/282944f572bb386ebf9b6bc21749336cbbea42b8)
- `faster-hessians-i546` at
  [e57e4c98](https://github.com/greta-dev/greta/commit/e57e4c981195da732a7f9156ce99463fc55c4b54)

|  |  |
|----|----|
| run at | `2026-09-29 17:28:55 AEST` |
| OS | `macOS Tahoe 26.5.2` |
| system | `aarch64, darwin23` |
| CPU | `Apple M3` |
| cores detected | `8` |
| R | `R version 4.6.1 (2026-06-24)` |
| R package: cross | `0.0.0.9000 (Github (DavisVaughan/cross@1a0db276e1f14b404efa6305b7890ffe24690f1d))` |
| R package: reticulate | `1.47.0 (CRAN (R 4.6.1))` |
| R package: tensorflow | `2.20.0 (CRAN (R 4.6.0))` |
