# ------------------------------------------------------------
# ingest_temperature_loggers.R
# 
# Purpose:
# Ingest temperature logger deployments and time-series observations
# into the relational database.
#
# Design:
# - Deployments provide mapping: logger -> location
# - Observations are append-only time series
# - Duplicate rows are prevented via (logger_id + timestamp)
#
# Data model:
# Temperature_Loggers       → metadata
# Temperature_Observations  → time-series data
#
# Safety:
# - Validates timestamps and temperature values
# - Prevents duplicate ingestion
# - Fails loudly on mismatch (serial, location, schema issues)
#
# Assumptions:
# - Logger files follow Elitech export format
# - Sheet 1 = metadata, Sheet 2 = time series
# ------------------------------------------------------------

#Load required Libraries

library(DBI)
library(RSQLite)
library(readxl)
library(readr)
library(dplyr)
library(lubridate)
library(stringr)
library(fs)


#Function wrapper for index call

ingest_temperature_loggers <- function(con) {

message("---- Starting temperature logger ingest ----")

deploy_csv <- "data/raw/loggers/temperature_logger_deployments.csv"
obs_dir    <- "data/raw/loggers/observations"
archive_dir <- file.path("data/processed/logger_archive", format(Sys.time(), "%Y%m%d_%H%M"))
dir_create(archive_dir)

if (!file.exists(deploy_csv)) {
  message("No logger deployment CSV found — skipping.")
  return(invisible(NULL))
}
if (missing(con)) {
  stop("Database connection `con` not provided.")
}

dbExecute(con, "PRAGMA foreign_keys = ON;")

# -----------------------------
# INGEST RUN COUNTERS
# -----------------------------
#The ingest run counters track how many records are inserted during a single run, 
# and that information is saved in a log table. This provides an audit trail of 
# how the database grows over time and ensures reproducibility
measurements_inserted  <- 0L
loggers_processed <- 0L


# Register data source
dbExecute(con, "
INSERT OR IGNORE INTO Data_Sources (name, notes)
VALUES ('Elitech LogEt 8', 'Temperature logger metadata and observations');
")
source_id <- dbGetQuery(
  con,
  "SELECT source_id FROM Data_Sources WHERE name = 'Elitech LogEt 8'"
)$source_id[1]


# ==================================================
# SECTION 1 — READ & BASIC SETUP
# ==================================================
# Purpose:
#   Load deployment CSV and prepare raw inputs

deploy <- read_csv(deploy_csv, show_col_types = FALSE)
message("Read ", nrow(deploy), " logger deployment records.")


# ==================================================
# SECTION 2 — NORMALIZATION
# ==================================================
# Purpose:
#   Standardize text fields to ensure reliable joins
# Why:
#   Prevents mismatches due to case or whitespace

deploy <- deploy |>
  mutate(
    status = str_to_lower(str_trim(status)),
    external_station_code = str_to_upper(str_trim(external_station_code))
  )


# ==================================================
# SECTION 3 — DATE PARSING & VALIDATION
# ==================================================
# Purpose:
#   Convert flexible Excel inputs → strict datetime
# Why:
#   Ensures database consistency and avoids type errors

deploy <- deploy |>
  mutate(
    deployment_start = parse_date_time(
      deployment_start,
      orders = c("ymd", "mdy", "dmy"),
      tz = "UTC"
    ),
    deployment_end = parse_date_time(
      deployment_end,
      orders = c("ymd", "mdy", "dmy"),
      tz = "UTC"
    )
  )

message("Deployment dates parsed.")

# ==================================================
# SECTION 4 — STATUS + RULE VALIDATION
# ==================================================
# Purpose:
#   Enforce lifecycle rules for deployments
# Rules:
#   • active / standby → NO end date
#   • retrieved / destroyed → MUST have end date

valid_status <- c("active", "retrieved", "destroyed", "lost", "standby")

bad_status <- setdiff(unique(deploy$status), valid_status)

if (length(bad_status) > 0) {
  stop(
    "Invalid status values:\n  - ",
    paste(bad_status, collapse = "\n  - ")
  )
}

message("Status values validated.")

# Rule enforcement
bad_active <- deploy |>
  filter(status %in% c("active", "standby"), !is.na(deployment_end))

if (nrow(bad_active) > 0) {
  stop(
    "Active/standby loggers cannot have deployment_end:\n  - ",
    paste(bad_active$serial_number, collapse = "\n  - ")
  )
}

bad_closed <- deploy |>
  filter(status %in% c("retrieved", "destroyed"), is.na(deployment_end))

if (nrow(bad_closed) > 0) {
  stop(
    "Closed loggers must have deployment_end:\n  - ",
    paste(bad_closed$serial_number, collapse = "\n  - ")
  )
}

# Normalize lifecycle state
deploy <- deploy |>
  mutate(
    deployment_start = if_else(status == "standby", NA, deployment_start),
    deployment_end   = if_else(status %in% c("active", "standby"), NA, deployment_end)
  )


# ==================================================
# SECTION 5 — COLUMN VALIDATION
# ==================================================
required <- c(
  "logger_name", "serial_number", "manufacturer",
  "model", "external_station_code", "notes"
)

missing_cols <- setdiff(required, names(deploy))

if (length(missing_cols) > 0) {
  stop(
    "Missing required columns:\n  - ",
    paste(missing_cols, collapse = "\n  - ")
  )
}

message("Deployment structure validated.")


# ==================================================
# SECTION 6 — LOCATION LOOKUP
# ==================================================
# Purpose:
#   Resolve external_station_code → location_id

locations <- dbReadTable(con, "Locations") |>
  select(location_id, external_station_code)

deploy <- deploy |>
  left_join(locations, by = "external_station_code")

bad_sites <- deploy |>
  filter(
    is.na(location_id) &
      status != "standby"
  ) |>
  distinct(external_station_code) |>
  pull()

if (length(bad_sites) > 0) {
  stop(
    "Unknown external_station_code:\n  - ",
    paste(bad_sites, collapse = "\n  - ")
  )
}
bad_missing_location <- deploy |>
  filter(
    is.na(external_station_code) &
      status != "standby"
  )

if (nrow(bad_missing_location) > 0) {
  stop(
    "Non-standby loggers must have external_station_code:\n  - ",
    paste(bad_missing_location$serial_number, collapse = "\n  - ")
  )
}

message("Resolved location IDs.")


# ==================================================
# SECTION 7 — LOGGER UPSERT (VECTORIZED)
# ==================================================
# Purpose:
#   Insert/update ALL logger metadata at once

dbWriteTable(con, "tmp_deploy", deploy, overwrite = TRUE)

# Step 1: UPDATE existing records
dbExecute(con, "
UPDATE Temperature_Loggers
SET
  logger_name = (
    SELECT tmp.logger_name FROM tmp_deploy tmp
    WHERE tmp.serial_number = Temperature_Loggers.serial_number
  ),
  location_id = (
    SELECT tmp.location_id FROM tmp_deploy tmp
    WHERE tmp.serial_number = Temperature_Loggers.serial_number
  ),
  deployment_start = (
    SELECT tmp.deployment_start FROM tmp_deploy tmp
    WHERE tmp.serial_number = Temperature_Loggers.serial_number
  ),
  deployment_end = (
    SELECT tmp.deployment_end FROM tmp_deploy tmp
    WHERE tmp.serial_number = Temperature_Loggers.serial_number
  ),
  status = (
    SELECT tmp.status FROM tmp_deploy tmp
    WHERE tmp.serial_number = Temperature_Loggers.serial_number
  ),
  notes = (
    SELECT tmp.notes FROM tmp_deploy tmp
    WHERE tmp.serial_number = Temperature_Loggers.serial_number
  )
WHERE serial_number IN (
  SELECT serial_number FROM tmp_deploy
);
")

# Step 2: INSERT new records
dbExecute(con, "
INSERT INTO Temperature_Loggers
(logger_name, manufacturer, model, serial_number,
 location_id, deployment_start, deployment_end, status, notes)
SELECT
  logger_name, manufacturer, model, serial_number,
  location_id, deployment_start, deployment_end, status, notes
FROM tmp_deploy
WHERE NOT EXISTS (
  SELECT 1 FROM Temperature_Loggers t
  WHERE t.serial_number = tmp_deploy.serial_number
);
")

dbExecute(con, "DROP TABLE tmp_deploy")

message("Logger metadata upsert complete.")


# ==================================================
# SECTION 8 — OBSERVATION INGEST (VECTORIZED)
# ==================================================
# Purpose:
#   Append all time-series data efficiently

xlsx_files <- dir_ls(obs_dir, regexp = "\\.xlsx?$", type = "file")

if (length(xlsx_files) == 0) {
  message("No observation files found — skipping.")
  return(invisible(NULL))
}

processed_files <- dbGetQuery(con, "
  SELECT file_name FROM Logger_Files_Processed
")$file_name

for (f in xlsx_files) {
  
  if (basename(f) %in% processed_files) {
    message("Skipping already processed file: ", basename(f))
    next
  }
  
  
  message("Processing: ", basename(f))
  
  # Extract serial
  serial <- str_extract(basename(f), "(CMN|EMO)[0-9]+")
  
  if (is.na(serial)) {
    stop("Could not extract serial from filename: ", basename(f))
  }
  
  # Validate serial
  dep <- deploy |> filter(serial_number == serial)
  
  if (nrow(dep) != 1) {
    stop("Serial number not found or duplicated: ", serial)
  }
  
  # Resolve logger_id
  logger_id <- dbGetQuery(
    con,
    "SELECT logger_id FROM Temperature_Loggers WHERE serial_number = ?",
    params = list(serial)
  )$logger_id
  
  if (length(logger_id) != 1) {
    stop("Logger not found or duplicated: ", serial)
  }
  
    
    # ---------------------------------
    # TRY EXCEL FIRST (ALWAYS)
    # ---------------------------------
  sheets <- excel_sheets(f)
  message("Sheets found: ", paste(sheets, collapse = ", "))
  
  # ✅ Force "List" sheet if it exists
  if ("List" %in% sheets) {
    sheet_name <- "List"
  } else {
    sheet_name <- sheets[1]
  }
  
  data <- read_excel(f, sheet = sheet_name)
  
  message("Reading sheet: ", sheet_name)
  
    
    # ---------------------------------
    # IF EXCEL FAILED → FALLBACK
    # ---------------------------------
  # Debug: show columns if Excel worked
  # Debug info (optional)
  if (!is.null(data)) {
    message("Columns detected: ", paste(names(data), collapse = ", "))
  }
  
  # ✅ ONLY fallback if Excel truly failed
  if (is.null(data) || nrow(data) == 0) {
    
    message("Excel failed — using fallback parser")
    
    raw <- read_lines(f, locale = locale(encoding = "latin1"))
    raw <- raw[raw != ""]
    
    records <- list()
    
    for (i in seq_len(length(raw))) {
      if (str_detect(raw[i], "^\\d{4}-\\d{2}-\\d{2}")) {
        
        if (i + 1 <= length(raw) &&
            str_detect(raw[i + 1], "^-?\\d+\\.?\\d*$")) {
          
          records[[length(records) + 1]] <- c(raw[i], raw[i + 1])
          
        } else if (i + 2 <= length(raw) &&
                   str_detect(raw[i + 2], "^-?\\d+\\.?\\d*$")) {
          
          records[[length(records) + 1]] <- c(raw[i], raw[i + 2])
        }
      }
    }
    
    if (length(records) == 0) {
      stop("Fallback parser failed: ", f)
    }
    
    data <- as_tibble(do.call(rbind, records))
    names(data) <- c("Time", "Temperature")
  }
  
    
  
  # ---------------------------------
  # ENSURE DATA EXISTS
  # ---------------------------------
  if (is.null(data)) {
    stop("Failed to read file: ", f)
  }
  
  # ---------------------------------
  # CLEAN COLUMN NAMES ONCE
  # ---------------------------------
      names(data) <- names(data) |>
        str_replace_all("\\s+", "") |>
        str_replace_all("°C", "C") |>
        str_replace_all("[^A-Za-z0-9]", "")
  
  message("Cleaned column names: ", paste(names(data), collapse = ", "))
  
  time_col <- names(data)[
    str_detect(names(data), regex("time", ignore_case = TRUE))
  ]
  
  temp_col <- names(data)[
    str_detect(names(data), regex("temp|temperature", ignore_case = TRUE))
  ]
  
  if (length(time_col) == 0 | length(temp_col) == 0) {
    stop(
      "Could not identify time/temperature columns in: ", f,
      "\nColumns found: ", paste(names(data), collapse = ", ")
    )
  }
  
  time_col <- time_col[1]
  temp_col <- temp_col[1]
  
  
  # Transform
  data <- data |>
    transmute(
      logger_id = logger_id,
      timestamp = parse_datetime_safe(.data[[time_col]]),
      temperature = suppressWarnings(as.numeric(.data[[temp_col]])),
      units = "deg C",
      status = NA_character_,
      source_id = source_id
    ) |>
    filter(!is.na(timestamp) & !is.na(temperature))
  
  if (nrow(data) == 0) {
    stop("No valid observations after cleaning: ", f)
  }
  
  if (any(is.na(data$temperature))) {
    stop("Non-numeric temperature detected in: ", f)
  }
  

  
  # VECTOR INSERT
  before <- dbGetQuery(con,
                       "SELECT COUNT(*) n FROM Temperature_Observations"
  )$n
  
  dbWriteTable(con, "tmp_obs", data, overwrite = TRUE)
  
  dbExecute(con, "
INSERT OR IGNORE INTO Temperature_Observations
(logger_id, timestamp, temperature, units, status, source_id)
SELECT
  logger_id, timestamp, temperature, units, status, source_id
FROM tmp_obs
")
  
  dbExecute(con, "DROP TABLE tmp_obs")
  
  after <- dbGetQuery(con,
                      "SELECT COUNT(*) n FROM Temperature_Observations"
  )$n
  
  inserted <- after - before
  measurements_inserted <- measurements_inserted + inserted
  
  loggers_processed <- loggers_processed + 1
  
  message("Inserted ", inserted, " new observations (", nrow(data), " processed)")
  
  dbExecute(con, "
INSERT OR REPLACE INTO Logger_Files_Processed
(file_name, processed_time)
VALUES (?, ?)
", params = list(
  basename(f),
  format(Sys.time(), "%Y-%m-%d %H:%M:%S")
))
  
  processed_files <- c(processed_files, basename(f))

}

  # ==================================================
  # INGEST RUN LOGGING
  # ==================================================
  
  dbAppendTable(
    con,
    "Ingest_Run_Log",
    data.frame(
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
      data_source = "LOGGER",
      script_name = "ingest_temperature_loggers.R",
      measurements_inserted = measurements_inserted,
      notes = paste("Processed", loggers_processed, "files"),
      stringsAsFactors = FALSE
    )
  )

  file_copy(
    deploy_csv,
    file.path(archive_dir,
              paste0("temperature_logger_deployments_", Sys.Date(), ".csv")),
    overwrite = TRUE
  )

  message("Total observations inserted: ", measurements_inserted)
  message("Loggers processed: ", loggers_processed)
  message("Temperature logger ingest complete.")
}