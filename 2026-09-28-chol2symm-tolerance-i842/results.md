# Rounding error in chol2symm(chol(x))


## The question

greta’s “chol2symm inverts chol” test rebuilt a 9 x 9 Wishart matrix
from its Cholesky factor and compared at
`tolerance = .Machine$double.eps` (2.2e-16). It failed on Windows CI for
greta \#842 with differences in the last digit. Is that tolerance
tighter than the rounding error of the rebuild itself, and what
tolerance is safe?

## Results

`all.equal()` compares the mean relative difference over the elements
that differ against its tolerance, leaving out elements that match
exactly. That is the error below, taken from
`all.equal(giveErr = TRUE)`.

|  | draws | largest error | fails at `double.eps` | fails at `1e-12` |
|----|----|----|----|----|
| `chol2symm()` in R | 2000 | 3.8e-16 | 3.0% | 0.0% |
| greta `calculate()` | 200 | 2.9e-16 | 2.5% | 0.0% |

The largest rounding error across all draws is 3.8e-16, so
`.Machine$double.eps` fails on ordinary rounding alone. A tolerance of
`1e-12` leaves a margin of 2,619 times over the largest error seen,
while a real bug in `chol2symm()` - a transpose, a wrong triangle -
gives errors of order 1.

## Environment

greta at e611c46286f14d6b3795ff6f8f4edfaf455c03be.

|                       |                                |
|-----------------------|--------------------------------|
| run at                | `2026-09-28 13:23:40 AEST`     |
| OS                    | `macOS Tahoe 26.5.2`           |
| system                | `aarch64, darwin23`            |
| CPU                   | `Apple M3`                     |
| cores detected        | `8`                            |
| R                     | `R version 4.6.1 (2026-06-24)` |
| R package: reticulate | `1.47.0 (CRAN (R 4.6.1))`      |
| R package: tensorflow | `2.20.0 (CRAN (R 4.6.0))`      |
