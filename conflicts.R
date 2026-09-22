# Declared winners, sourced by the last line of packages.R.
#
# Every entry is a decision, so the reason goes next to it - "we picked one" is
# not a reason. When conflicted errors on an ambiguous call, come here and
# decide rather than reaching for pkg::fun() at the call site.
#
# An empty file is a normal result. It is kept, and kept sourced, so the first
# real conflict has a home that already works.

# check what is actually ambiguous rather than guessing:
#   conflicted::conflict_scout()

# dplyr and stats both export these. Nothing here does signal processing or
# time series, so the data-frame verbs are always the ones meant - and
# stats::filter() silently reading a column name as a filter coefficient is a
# genuinely hard bug to spot when it happens.
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag", "dplyr", quiet = TRUE)
