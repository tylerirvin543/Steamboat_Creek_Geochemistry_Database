# --------------------------------------------------
# prepare_lab_data.R
# Convert raw lab outputs to standardized long CSVs
# --------------------------------------------------
# NOTE:
# This script is run manually to standardize lab outputs
# before ingestion. It is NOT called by update_all_data.R.

library(readxl)
library(readr)
library(dplyr)

source("scripts/ingest/helpers/normalize_lab_wide.R")

raw_lab_file <- "data/raw/lab/ALS_ICPMS_2026.xlsx"
out_file <- "data/processed/lab_normalized/ALS_ICPMS_2026_long.csv"

raw_lab <- read_excel(raw_lab_file)

lab_long <- normalize_lab_wide(raw_lab)

write_csv(lab_long, out_file)

message("Normalized lab file written to: ", out_file)