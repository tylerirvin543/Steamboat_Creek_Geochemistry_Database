# --------------------------------------------------
# ingest_lab.R
# Unified Lab Ingest (RAW + NORMALIZED)
#
# Handles:
# - raw ALS-style wide files (auto-normalized)
# - pre-normalized long CSVs
#
# --------------------------------------------------
# --------------------------------------------------
# ingest_lab.R (REFactored FINAL)
# --------------------------------------------------

library(DBI)
library(RSQLite)
library(dplyr)
library(readr)
library(readxl)
library(tidyr)

ingest_lab <- function(con) {
  
  message("---- Starting Lab Ingest ----")
  
  if (missing(con)) stop("Database connection required.")
  dbExecute(con, "PRAGMA foreign_keys = ON;")
  
  # --------------------------------------------------
  # CONFIG
  # --------------------------------------------------
  raw_dir <- "data/raw/lab"
  
  # --------------------------------------------------
  # LOAD MAPPINGS
  # --------------------------------------------------
  source("database/schema/lab_analyte_map.R")
  
  # --------------------------------------------------
  # REGISTER SOURCE
  # --------------------------------------------------
  dbExecute(con, "
    INSERT OR IGNORE INTO Data_Sources (name)
    VALUES ('Analytical Laboratory');
  ")
  
  source_id <- dbGetQuery(
    con,
    "SELECT source_id FROM Data_Sources WHERE name='Analytical Laboratory'"
  )$source_id[1]
  
  # --------------------------------------------------
  # SAMPLE LOOKUP (WITH DATE EXTRACTION)
  # --------------------------------------------------
  sample_lookup <- dbGetQuery(con, "
  SELECT
    sample_id,
    external_sample_id,
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
    
    # ✅ CRITICAL: resolve duplicates HERE
    filter(!is.na(sample_date)) %>%
    group_by(base_code) %>%
    slice_max(sample_date, n = 1, with_ties = FALSE) %>%
    ungroup()
  
  # --------------------------------------------------
  # EXISTING RECORDS (for idempotency)
  # --------------------------------------------------
  existing_field <- dbReadTable(con, "Field_Measurements") %>%
    select(sample_id, parameter, source_id)
  
  existing_lab <- dbReadTable(con, "Lab_Analyses") %>%
    select(sample_id, analyte, source_id)
  
  # --------------------------------------------------
  # NORMALIZATION FUNCTION
  # --------------------------------------------------
  normalize_lab_wide <- function(df) {
    
    header_row <- which(trimws(df[[1]]) == "SAMPLE")[1]
    if (is.na(header_row)) stop("No SAMPLE row found")
    
    units_row <- header_row + 1
    
    analyte_names <- as.character(unlist(df[header_row, ]))
    unit_values <- as.character(unlist(df[units_row, ]))
    
    bad <- is.na(analyte_names) | analyte_names == ""
    analyte_names[bad] <- paste0("X", which(bad))
    analyte_names <- make.names(analyte_names, unique = TRUE)
    
    names(df) <- analyte_names
    df <- df[-c(1:units_row), ]
    
    colnames(df)[1] <- "sample_code"
    
    df <- df %>%
      mutate(sample_code = trimws(sample_code))
    
    unit_lookup <- unit_values
    names(unit_lookup) <- analyte_names
    
    df %>%
      pivot_longer(
        cols = -sample_code,
        names_to = "analyte",
        values_to = "raw_value"
      ) %>%
      mutate(
        raw_value_chr = as.character(raw_value),
        qualifier = ifelse(grepl("^[<>]", raw_value_chr),
                           substr(raw_value_chr, 1, 1),
                           NA_character_),
        value = suppressWarnings(
          as.numeric(gsub("[<>]", "", raw_value_chr))
        ),
        units = dplyr::case_when(
          analyte %in% names(unit_lookup) ~ as.character(unit_lookup[analyte]),
          TRUE ~ NA_character_
        )
      ) %>%
      filter(!is.na(value))
  }
  
  # --------------------------------------------------
  # FIND FILES
  # --------------------------------------------------
  files <- list.files(raw_dir, pattern = "\\.(csv|xlsx)$", full.names = TRUE)
  files <- files[!grepl("^~\\$", basename(files))]
  
  if (length(files) == 0) stop("No lab files found.")
  
  print(files)
  
  # --------------------------------------------------
  # PROCESS FILES
  # --------------------------------------------------
  for (file in files) {
    
    message("Processing: ", basename(file))
    
    # Load data
    if (grepl("\\.xlsx$", file)) {
      raw <- read_excel(file, col_names = FALSE)
    } else {
      raw <- read_csv(file, col_names = FALSE, show_col_types = FALSE)
      colnames(raw) <- make.names(seq_len(ncol(raw)), unique = TRUE)
    }
    
    # Normalize
    lab_long <- normalize_lab_wide(raw)
    
    # --------------------------------------------------
    # JOIN TO SAMPLES (DATE RESOLUTION)
    # --------------------------------------------------
    lab_long <- lab_long %>%
      left_join(sample_lookup, by = c("sample_code" = "base_code"))
    
    # Validate match
    if (any(is.na(lab_long$sample_id))) {
      print(lab_long %>% filter(is.na(sample_id)) %>% distinct(sample_code))
      stop("Sample mismatch detected.")
    }
    
    # --------------------------------------------------
    # SPLIT DATA
    # --------------------------------------------------
    lab_physical <- lab_long %>%
      filter(analyte %in% c("TDS", "Conductivity", "EC", "pH"))
    
    lab_chem <- lab_long %>%
      filter(!(analyte %in% c("TDS", "Conductivity", "EC", "pH")))
    
    # --------------------------------------------------
    # FIELD MEASUREMENTS
    # --------------------------------------------------
    if (nrow(lab_physical) > 0) {
      
      lab_physical <- lab_physical %>%
        mutate(
          parameter = case_when(
            analyte %in% c("Conductivity", "EC") ~ "conductivity",
            analyte == "TDS" ~ "TDS",
            analyte == "pH" ~ "pH",
            TRUE ~ analyte
          )
        )
      
      new_field <- lab_physical %>%
        transmute(
          sample_id,
          parameter,
          value,
          units,
          instrument = "lab",
          source_id
        ) %>%
        anti_join(existing_field,
                  by = c("sample_id", "parameter", "source_id"))
      
      if (nrow(new_field) > 0) {
        dbAppendTable(con, "Field_Measurements", new_field)
      }
    }
    
    # --------------------------------------------------
    # LAB CHEMISTRY
    # --------------------------------------------------
    if (nrow(lab_chem) > 0) {
      
      lab_chem <- lab_chem %>%
        left_join(lab_analyte_map,
                  by = c("analyte" = "raw_name")) %>%
        
        transmute(
          sample_id,
          analyte = analyte.y,
          value,
          units = as.character(units.x),
          qualifier
        ) %>%
        
        filter(!is.na(analyte)) %>%
        
        mutate(
          value = ifelse(!is.na(units) & units == "ug/L",
                         value / 1000,
                         value),
          units = "mg/L",
          source_id = source_id,
          fraction = "dissolved"
        )
      
      # ✅ CREATE new_lab properly
      new_lab <- lab_chem %>%
        anti_join(existing_lab,
                  by = c("sample_id", "analyte", "source_id"))
      
      # ✅ INSERT the correct object
      if (nrow(new_lab) > 0) {
        dbAppendTable(con, "Lab_Analyses", new_lab)
      }
    }
  }
  
  
  # --------------------------------------------------
  # LOG INGEST RUN
  # --------------------------------------------------
  dbAppendTable(
    con,
    "Ingest_Run_Log",
    data.frame(
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
      data_source = "LAB",
      script_name = "ingest_lab.R",
      locations_inserted     = locations_inserted,
      events_inserted        = events_inserted,
      samples_inserted       = samples_inserted,
      measurements_inserted  = measurements_inserted,
      notes = "Lab chemistry + physical parameters ingested",
      stringsAsFactors = FALSE
    )
  )
  
  message("Lab ingestion complete.")
}