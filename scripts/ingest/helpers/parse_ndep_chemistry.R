# --------------------------------------------------
# Parse NDEP chemistry from NormalizedData.csv
# Produces SQL-ready Lab_Analyses records
# --------------------------------------------------

library(dplyr)
library(lubridate)

# --------------------------------------------------
# Parse result values and qualifiers
# --------------------------------------------------

parse_ndep_results <- function(df) {
  
  df |>
    mutate(
      qualifier = ifelse(grepl("^<", RESULTMEASURE), "<", NA_character_),
      value = as.numeric(gsub("<", "", RESULTMEASURE)),
      detection_limit = case_when(
        qualifier == "<" ~ as.numeric(gsub("<", "", RESULTMEASURE)),
        !is.na(REPORTINGLIMIT) ~ REPORTINGLIMIT,
        TRUE ~ NA_real_
      )
    )
}

# --------------------------------------------------
# Main chemistry parsing function
# --------------------------------------------------

parse_ndep_chemistry <- function(norm_df, analyte_map, sample_lookup, source_id) {
  
  chem <- norm_df |>
    # --- normalize identifier type ---
    mutate(
      SOURCESAMPLEID = as.character(SOURCESAMPLEID)
    ) |>
    # --- map analytes ---
    left_join(
      analyte_map,
      by = c("CHARACTERISTICNAME" = "raw_name_norm")
    ) |>
    filter(!is.na(analyte)) |>
    # --- parse reported values ---
    mutate(
      qualifier = ifelse(grepl("^<", RESULTMEASURE), "<", NA_character_),
      value = as.numeric(gsub("<", "", RESULTMEASURE)),
      detection_limit = case_when(
        qualifier == "<" & !is.na(REPORTINGLIMIT) ~ REPORTINGLIMIT,
        qualifier == "<"                          ~ value,
        TRUE                                     ~ REPORTINGLIMIT
      )
    ) |>
    # --- link to samples ONCE ---
    left_join(
      sample_lookup,
      by = c("SOURCESAMPLEID" = "external_sample_id")
    )
  
  # --- hard integrity check ---
  if (any(is.na(chem$sample_id))) {
    bad <- unique(chem$SOURCESAMPLEID[is.na(chem$sample_id)])
    stop(
      "Some NDEP chemistry records could not be matched to samples.\n",
      "Unmatched SOURCESAMPLEID(s): ",
      paste(bad, collapse = ", ")
    )
  }
  
  # --- final SQL‑ready table ---
  chem |>
    transmute(
      sample_id,
      analyte,
      value,
      units,
      fraction = NA_character_,
      detection_limit,
      method = ANALYTICALMETHOD,
      source_id
    )
}
