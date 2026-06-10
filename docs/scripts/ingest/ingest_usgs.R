# ============================================================
# ingest_usgs.R
#
# USGS continuous discharge time series from download:
# https://waterdata.usgs.gov/monitoring-location/USGS-10349300/
# https://waterdata.usgs.gov/monitoring-location/USGS-10349849/
#
#
# Purpose:
# data folders and append only new data to database.
#
# Design:
# - Reads folders containing USGS exports
# - Automatically detects station IDs
# - Handles overlapping date pulls safely
# - Deduplicates using database keys
#
# Folder structure:
# data/raw/usgs/input/
#   ├── mlp_continuous_USGS-10349849_01012026T06062026/
#   │     ├── primary-time-series.csv
#   │     ├── time-series-metadata.csv
#
# Behavior:
# - Does NOT overwrite existing data
# - Only inserts new timestamps
#
# ============================================================

library(DBI)
library(dplyr)
library(lubridate)
library(stringr)
library(readr)
library(fs)
library(purrr)

ingest_usgs <- function(con) {
  
  message("---- Starting USGS ingest ----")
  
  base_dir <- "data/raw/usgs/input"
  
  message("[USGS] Looking in: ", normalizePath(base_dir, mustWork = FALSE))
  
  if (!dir_exists(base_dir)) {
    message("[USGS] Directory not found — skipping.")
    return(invisible(NULL))
  }
  
  folders <- dir_ls(base_dir, type = "directory")
  
  if (length(folders) == 0) {
    message("[USGS] No folders found.")
    return(invisible(NULL))
  }
  
  
  total_inserted <- 0
  
  # ------------------------------------------------------------
  # LOOP THROUGH FOLDERS
  # ------------------------------------------------------------
  
  for (folder in folders) {
    
    folder_name <- basename(folder)
    
    message("\n[USGS] Processing: ", folder_name)
    
    primary_file <- file.path(folder, "primary-time-series.csv")
    
    if (!file.exists(primary_file)) {
      message("  → Missing primary file, skipping")
      next
    }
    
    # ------------------------------------------------------------
    # READ METADATA (CRITICAL FIX)
    # ------------------------------------------------------------
    metadata_file <- file.path(folder, "time-series-metadata.csv")
    
    if (file.exists(metadata_file)) {
      
      message("  → Reading metadata")
      
      meta <- read_csv(metadata_file, show_col_types = FALSE)
      
      meta_clean <- meta %>%
        transmute(
          station_id = monitoring_location_id,
          latitude   = y,
          longitude  = x
        ) %>%
        distinct()
      
      # ✅ normalize IDs (important)
      meta_clean <- meta_clean %>%
        mutate(station_id = trimws(station_id))
      
      # ✅ avoid duplicates
      existing_stations <- dbGetQuery(con, "SELECT station_id FROM USGS_Stations")
      
      new_meta <- meta_clean %>%
        anti_join(existing_stations, by = "station_id")
      
      if (nrow(new_meta) > 0) {
        dbAppendTable(con, "USGS_Stations", new_meta)
        message("  → Inserted metadata for ", nrow(new_meta), " station(s)")
      } else {
        message("  → Metadata already exists, skipping")
      }
      
    } else {
      message("  → No metadata file found in folder")
    }
    
    # ------------------------------------------------------------
    # PARSE STATION
    # ------------------------------------------------------------
    
    station_id <- str_extract(folder_name, "USGS-\\d+")
    
    if (is.na(station_id)) {
      message("  → Could not parse station ID, skipping")
      next
    }
    
    message("  → Station: ", station_id)
    
    # ------------------------------------------------------------
    # READ DATA
    # ------------------------------------------------------------
    
    df <- read_csv(primary_file, show_col_types = FALSE)
    
    # ------------------------------------------------------------
    # CLEAN COLUMN NAMES
    # ------------------------------------------------------------
    
    names(df) <- tolower(names(df))
    
    # ✅ Handle possible alternate time column names
    time_col <- names(df)[str_detect(names(df), "^time$|date|datetime")][1]
    
    if (is.na(time_col)) {
      message("  → Could not detect time column, skipping file")
      next
    }
    
    value_col <- names(df)[names(df) == "value"]
    
    if (length(value_col) == 0) {
      message("  → No value column found, skipping file")
      next
    }
    
    # ------------------------------------------------------------
    # TRANSFORM
    # ------------------------------------------------------------
    
    df <- df %>%
      mutate(
        datetime = suppressWarnings(
          lubridate::parse_date_time(
            !!sym(time_col),
            orders = c(
              "Y-m-d H:M:S",
              "Y-m-d H:M:S z",
              "Y-m-d H:M:SOS",
              "Y-m-d H:M:OS z"
            ),
            tz = "UTC"
          )
        ),
        value        = as.numeric(.data[[value_col]]),
        station_id   = monitoring_location_id %||% station_id,
        source_file  = folder_name,
        parameter_code = as.character(parameter_code)
      )
    
    # ------------------------------------------------------------
    # DROP BAD ROWS (KEY FIX)
    # ------------------------------------------------------------
    
    bad_rows <- sum(is.na(df$datetime))
    
    if (bad_rows > 0) {
      message("  → Dropping ", bad_rows, " bad rows (invalid datetime)")
    }
    
    df <- df %>%
      filter(!is.na(datetime))
    
    if (nrow(df) == 0) {
      message("  → No valid data remaining after cleaning")
      next
    }
    
    # ------------------------------------------------------------
    # SELECT FINAL COLUMNS
    # ------------------------------------------------------------
    
    df <- df %>%
      select(
        station_id,
        datetime,
        parameter_code,
        value,
        unit = unit_of_measure,
        status = approval_status,
        last_modified,
        source_file
      )
    
    # NA check
    na_count <- sum(is.na(df$datetime))
    
    if (na_count > 0) {
      message("  → Datetime failures: ", na_count, "/", nrow(df))
      
      print(
        df %>%
          filter(is.na(datetime)) %>%
          select(time) %>%
          head(5)
      )
      
      next
    }
    
    # ------------------------------------------------------------
    # REMOVE DUPLICATES WITHIN FILE
    # ------------------------------------------------------------
    
    df <- df %>%
      distinct(station_id, datetime, parameter_code, .keep_all = TRUE)
    
    message("  → Rows in file: ", nrow(df))
    
    # ------------------------------------------------------------
    # REMOVE EXISTING DB ROWS (incremental ingest)
    # ------------------------------------------------------------
    
    existing <- dbGetQuery(con, "
  SELECT station_id, datetime, parameter_code
  FROM USGS_Timeseries
")
    
    # ✅ Fix type mismatch
    existing <- existing %>%
      mutate(datetime = as.POSIXct(datetime, tz = "UTC"),
             parameter_code = as.character(parameter_code)
             )
    
    pre_filter <- nrow(df)
    
    df <- df %>%
      anti_join(existing,
                by = c("station_id", "datetime", "parameter_code")
      )
    
    message("  → New rows after deduplication: ", nrow(df),
            " (removed ", pre_filter - nrow(df), ")")
    # ------------------------------------------------------------
    # INSERT
    # ------------------------------------------------------------
    
    df <- df %>%
      mutate(
        datetime = format(datetime, "%Y-%m-%d %H:%M:%S")
      )
    
    if (nrow(df) > 0) {
      dbAppendTable(con, "USGS_Timeseries", df)
    }
    
    total_inserted <- total_inserted + nrow(df)
  }
  
  # ------------------------------------------------------------
  # LOGGING
  # ------------------------------------------------------------
  
  dbAppendTable(
    con,
    "Ingest_Run_Log",
    data.frame(
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
      data_source = "USGS",
      script_name = "ingest_usgs.R",
      samples_inserted = 0,
      measurements_inserted = total_inserted,
      notes = paste("USGS ingest total rows:", total_inserted),
      stringsAsFactors = FALSE
    )
  )
  
  message("\n✅ USGS ingest complete")
  message("Total rows inserted: ", total_inserted)
}
