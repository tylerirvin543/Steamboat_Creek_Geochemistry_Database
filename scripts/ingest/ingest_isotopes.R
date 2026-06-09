library(DBI)
library(dplyr)
library(readxl)
library(tidyr)

ingest_isotopes <- function(con) {
  
  message("---- Starting Isotope Ingest ----")
  
  file <- "data/raw/isotopes/Isotope_Data_Steamboat_05_26.xlsx"
  
  iso <- read_excel(file, skip = 2)
  
  # --------------------------------------------------
  # CLEAN COLUMNS (ASSUMES ALREADY MATCHED SCHEMA)
  # --------------------------------------------------
  iso <- iso %>%
    rename(
      sample_code = `Sample #`,
      d18O = `d18OVSMOW (‰)`,
      dD   = `dDVSMOW (‰)`
    ) %>%
    mutate(
      sample_code = trimws(sample_code)
    )
  
  iso <- iso %>%
    filter(!is.na(sample_code))
  
  # --------------------------------------------------
  # REGISTER SOURCE
  # --------------------------------------------------
  dbExecute(con, "
    INSERT OR IGNORE INTO Data_Sources (name)
    VALUES ('Stable Isotope Analysis')
  ")
  
  source_id <- dbGetQuery(con,
                          "SELECT source_id FROM Data_Sources WHERE name='Stable Isotope Analysis'"
  )$source_id[1]
  
  # --------------------------------------------------
  # SAMPLE LOOKUP (DIRECT MATCH NOW)
  # --------------------------------------------------
  sample_lookup <- dbGetQuery(con, "
  SELECT
    sample_id,
    substr(external_sample_id, 1,
           instr(external_sample_id, '-') - 1) AS base_code,
    substr(external_sample_id,
           instr(external_sample_id, '-') + 1) AS sample_date
  FROM Samples
") %>%
    mutate(
      sample_date = ifelse(
        grepl("^\\d{4}-\\d{2}-\\d{2}$", sample_date),
        sample_date,
        NA_character_
      ),
      sample_date = as.Date(sample_date)
    ) %>%
    group_by(base_code) %>%
    slice_max(sample_date, n = 1, with_ties = FALSE) %>%
    ungroup()
  
  iso <- iso %>%
    left_join(sample_lookup,
              by = c("sample_code" = "base_code"))
  
  
  # --------------------------------------------------
  # VALIDATION
  # --------------------------------------------------
  if (any(is.na(iso$sample_id))) {
    print(iso %>% filter(is.na(sample_id)))
    stop("Isotope samples did not match Samples table")
  }
  
  # --------------------------------------------------
  # PIVOT TO LONG FORMAT
  # --------------------------------------------------
  iso_long <- iso %>%
    select(sample_id, d18O, dD) %>%
    pivot_longer(
      cols = c(d18O, dD),
      names_to = "analyte",
      values_to = "value"
    ) %>%
    mutate(
      analyte = ifelse(analyte == "dD", "d2H", analyte)
    )
  
  # --------------------------------------------------
  # EXISTING RECORD CHECK (IDEMPOTENCY)
  # --------------------------------------------------
  existing_iso <- dbReadTable(con, "Isotope_Analyses") %>%
    select(sample_id, analyte, source_id)
  
  new_iso <- iso_long %>%
    mutate(
      units = "permil",
      standard = "VSMOW",
      source_id = source_id
    ) %>%
    anti_join(existing_iso,
              by = c("sample_id", "analyte", "source_id"))
  
  # --------------------------------------------------
  # INSERT
  # --------------------------------------------------
  if (nrow(new_iso) > 0) {
    dbAppendTable(con, "Isotope_Analyses", new_iso)
  }
  
  message("✅ Isotope ingest complete.")
}