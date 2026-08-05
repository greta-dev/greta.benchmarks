# Keras 3 optimiser port versus main

## The question

Does porting greta's Keras optimisers to the Keras 3 API, and raising the pinned dependencies to TensorFlow 2.21, make greta slower? A ratio below 1 means the branch is faster.

## Results

|task       | use-keras3-i633 (ms)| main (ms)| median ratio| min ratio|
|:----------|--------------------:|---------:|------------:|---------:|
|build      |                13.42|     13.81|        0.971|     0.993|
|calculate  |                 7.36|      8.19|        0.899|     0.998|
|opt_adam   |                53.15|    107.24|        0.496|     0.506|
|opt_bfgs   |                12.57|     12.81|        0.981|     0.993|
|mcmc_short |               378.58|    360.26|        1.051|     1.059|

`bench::mark()`, 5 to 10 iterations per cell. `min` is the statistic least contaminated by garbage collection and scheduling; where the two branches share byte-identical code, it is the one to read.

## Environment

| | |
|---|---|
| run at | `2026-08-05 13:50:35 AEST` |
| OS | `Darwin 25.5.0` |
| architecture | `aarch64` |
| CPU | `Apple M3` |
| cores detected | `8` |
| R | `R version 4.6.1 (2026-06-24)` |
| R package: cross | `0.0.0.9000` |
| R package: bench | `1.1.4` |
| R package: reticulate | `1.46.0` |
| R package: tensorflow | `2.20.0` |
| stack, use-keras3-i633 | `python 3.12, tensorflow 2.21.0, tfp 0.25.0` |
| stack, main | `python 3.11, tensorflow 2.15.1, tfp 0.23.0` |
| greta, current | `769a9039d6c816779fa791b1922dda55f370e699` |
| greta, reference | `9687542c361899b066ecd792557802e25343a59d` |

Timings are bound to this machine. Ratios within this run are meaningful; the absolute numbers are not comparable with a run on different hardware.
