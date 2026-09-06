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
      ),
      # 2026-09-06: applies ndep_analyte_map.R's per-raw_name
      # conversion_factor (e.g. mg/L as CaCO3 -> mg/L as HCO3 for "Total
      # Alkalinity as CaCO3", factor 1.2189) so a clean analyte code
      # stays in one consistent unit convention regardless of which raw
      # NDEP characteristic supplied it. Defaults to 1 (no-op) for every
      # analyte that does not need conversion.
      value = value * dplyr::coalesce(conversion_factor, 1),
      detection_limit = detection_limit * dplyr::coalesce(conversion_factor, 1)
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
