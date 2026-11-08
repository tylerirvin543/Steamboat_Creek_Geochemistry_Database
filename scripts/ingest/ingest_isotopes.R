library(DBI)
library(dplyr)
library(readxl)
library(tidyr)

ingest_isotopes <- function(con) {
  
  message("---- Starting Isotope Ingest ----")
  
  # Every .xlsx under data/raw/isotopes/ is read; header row is the one containing "Sample #"
  # (files differ in how many title rows precede it). Rows are combined.
  iso_files <- list.files("data/raw/isotopes", pattern = "\\.xlsx$", full.names = TRUE)
  read_iso_file <- function(file) {
    raw <- suppressMessages(read_excel(file, col_names = FALSE))
    hdr <- which(apply(raw, 1, function(r) any(trimws(as.character(r)) == "Sample #")))[1]
    if (is.na(hdr)) { warning("No 'Sample #' header in ", basename(file), "; skipped"); return(NULL) }
    d <- raw[(hdr + 1):nrow(raw), ]; names(d) <- trimws(as.character(unlist(raw[hdr, ])))
    d <- d[, !is.na(names(d)) & names(d) != "NA"]
    d$d18O_raw <- d[["d18OVSMOW (‰)"]]; d$dD_raw <- d[["dDVSMOW (‰)"]]
    d[["d18OVSMOW (‰)"]] <- suppressWarnings(as.numeric(d$d18O_raw)); d[["dDVSMOW (‰)"]] <- suppressWarnings(as.numeric(d$dD_raw))
    d$d18O_raw <- NULL; d$dD_raw <- NULL
    message("  ", basename(file), ": ", sum(!is.na(d[["Sample #"]])), " row(s)")
    d
  }
  iso <- dplyr::bind_rows(lapply(iso_files, read_iso_file))
  
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
      base_code = sub("^LINDSEY2026_([^_]+)_.*$", "\\1", base_code),
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
