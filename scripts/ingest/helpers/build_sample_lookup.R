# --------------------------------------------------
# Build sample lookup: external IDs -> sample_id
# --------------------------------------------------

library(DBI)
library(dplyr)

build_sample_lookup <- function(con) {
  
  samples <- dbReadTable(con, "Samples")
  
  # One row per external_sample_id (deterministic)
  lookup <- samples |>
    arrange(sample_id) |>               # ensure deterministic choice
    group_by(external_sample_id) |>
    slice(1) |>                         # keep the first occurrence
    ungroup() |>
    transmute(
      sample_id,
      external_sample_id = as.character(external_sample_id)
    )
  
  lookup
}