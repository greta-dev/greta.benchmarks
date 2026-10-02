# Normal or t cut-off for batch-means scores


## The question

The bivariate normal test scores each posterior summary as
`|estimate - truth| / MCSE`, with the MCSE from batch means, and fails a
sampler when any of five scores passes `qnorm(1 - 0.01 / 10)`. A
standard error estimated from `a` batch means makes the score
t-distributed with `a - 1` degrees of freedom. Does the normal cut-off
reject more often than the 0.0020 per score it is set for, and does a t
cut-off fix it?

Chains are AR(1) with coefficient 0.5 and mean zero, 20000 replicates at
each length.

## Results

| n     | batches | target rate | normal cut-off | t cut-off      |
|-------|---------|-------------|----------------|----------------|
| 4000  | 63      | 0.0020      | 0.0031 (1.53x) | 0.0022 (1.12x) |
| 16000 | 126     | 0.0020      | 0.0026 (1.30x) | 0.0022 (1.12x) |

Each rate has a Monte Carlo standard error of about 0.0003. The normal
cut-off rejects 1.30-1.53 times as often as intended; the t cut-off is
within 0.8 standard errors of the target.

## Environment

`mcse()` from greta at 75decd9dda0e6c5054496884f8a9bc1bac8bfe0b.

|                |                                |
|----------------|--------------------------------|
| run at         | `2026-09-28 13:25:28 AEST`     |
| OS             | `macOS Tahoe 26.5.2`           |
| system         | `aarch64, darwin23`            |
| CPU            | `Apple M3`                     |
| cores detected | `8`                            |
| R              | `R version 4.6.1 (2026-06-24)` |
