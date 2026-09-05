# ------------------------------------------------------------
# ingest_conductivity.R
#
# Purpose:
# Ingest stream conductivity logger deployments and time-series
# observations (HOBO/Onset "Full Range" EC loggers) into the
# relational database.
#
# Design (mirrors ingest_temperature_loggers.R):
# - Deployment manifest provides mapping: logger -> location -> role
# - Observations are append-only time series
# - Duplicate rows are prevented via (logger_id + timestamp)
# - Raw "Full Range" EC is converted to specific conductance at 25 C
#   (see scripts/ingest/helpers/compute_specific_conductance.R)
#
# Data model:
# Conductivity_Loggers       -> metadata
# Conductivity_Observations  -> time-series data (ec_raw, temperature_c, sc_25c)
#
# Safety:
# - Fails loudly on unknown serials / unknown locations / bad columns
# - Safe to re-run: already-processed files and rows are skipped
#
# Assumptions:
# - Raw files follow the HOBOware "Plot Title" export format:
#     line 1: "Plot Title: ..."
#     line 2: header row with embedded LGR/SEN serial numbers
#     data rows: index, "Date Time, GMT-07:00", EC, Temp, 4 event columns
# - Header timestamps carry a fixed GMT-07:00 offset (no DST ambiguity)
# ------------------------------------------------------------

library(DBI)
library(RSQLite)
library(readr)
library(dplyr)
library(lubridate)
library(stringr)
library(fs)
library(tibble)

source("scripts/ingest/helpers/compute_specific_conductance.R")

ingest_conductivity <- function(con) {

  message("---- Starting conductivity logger ingest ----")

  deploy_csv  <- "data/raw/conductivity/conductivity_logger_deployments.csv"
  raw_dir     <- "data/raw/conductivity/raw"
  archive_dir <- file.path("data/processed/conductivity_archive", format(Sys.time(), "%Y%m%d_%H%M"))
  dir_create(archive_dir)

  if (!file.exists(deploy_csv)) {
    message("No conductivity deployment manifest found — skipping.")
    return(invisible(NULL))
  }
  if (missing(con)) {
    stop("Database connection `con` not provided.")
  }

  dbExecute(con, "PRAGMA foreign_keys = ON;")

  observations_inserted <- 0L
  files_processed <- 0L

  # -----------------------------
  # Register data source
  # -----------------------------
  dbExecute(con, "
    INSERT OR IGNORE INTO Data_Sources (name, notes)
    VALUES ('Onset HOBO Conductivity Logger', 'Stream specific-conductance logger, ~5-min interval');
  ")
  source_id <- dbGetQuery(
    con,
    "SELECT source_id FROM Data_Sources WHERE name = 'Onset HOBO Conductivity Logger'"
  )$source_id[1]

  # ==================================================
  # SECTION 1 — READ + NORMALIZE DEPLOYMENT MANIFEST
  # ==================================================

  deploy <- read_csv(deploy_csv, show_col_types = FALSE,
                      col_types = cols(serial_number = col_character())) |>
    mutate(
      status = str_to_lower(str_trim(status)),
      role = str_to_lower(str_trim(role)),
      serial_number = str_trim(serial_number),
      external_station_code = str_to_upper(str_trim(external_station_code)),
      deployment_start = parse_date_time(deployment_start, orders = c("ymd", "mdy", "dmy"), tz = "UTC"),
      deployment_end   = parse_date_time(deployment_end,   orders = c("ymd", "mdy", "dmy"), tz = "UTC")
    )

  message("Read ", nrow(deploy), " conductivity logger deployment records.")

  valid_status <- c("active", "retrieved", "destroyed", "lost", "standby")
  bad_status <- setdiff(unique(deploy$status), valid_status)
  if (length(bad_status) > 0) {
    stop("Invalid status values:\n  - ", paste(bad_status, collapse = "\n  - "))
  }

  valid_role <- c("upstream_control", "downstream")
  bad_role <- setdiff(unique(deploy$role), valid_role)
  if (length(bad_role) > 0) {
    stop("Invalid role values:\n  - ", paste(bad_role, collapse = "\n  - "))
  }

  # ==================================================
  # SECTION 2 — LOCATION LOOKUP
  # ==================================================
  # Note: unlike ingest_temperature_loggers.R, this script does NOT
  # silently create missing locations. SBGG is seeded once in
  # database/schema/02_conductivity_schema.R; any other unknown code
  # here should be added to Locations (ideally via ingest_field.R's
  # locations.xlsx template) before re-running.

  locations <- dbReadTable(con, "Locations") |>
    select(location_id, external_station_code)

  deploy <- deploy |>
    left_join(locations, by = "external_station_code")

  bad_sites <- deploy |>
    filter(is.na(location_id) & status != "standby") |>
    distinct(external_station_code) |>
    pull()

  if (length(bad_sites) > 0) {
    stop(
      "Unknown external_station_code (add to Locations first):\n  - ",
      paste(bad_sites, collapse = "\n  - ")
    )
  }

  message("Resolved location IDs for conductivity loggers.")

  # ==================================================
  # SECTION 3 — LOGGER METADATA UPSERT
  # ==================================================

  dbWriteTable(con, "tmp_cond_deploy", deploy, overwrite = TRUE)

  dbExecute(con, "
    UPDATE Conductivity_Loggers
    SET
      logger_name = (SELECT tmp.logger_name FROM tmp_cond_deploy tmp WHERE tmp.serial_number = Conductivity_Loggers.serial_number),
      location_id = (SELECT tmp.location_id FROM tmp_cond_deploy tmp WHERE tmp.serial_number = Conductivity_Loggers.serial_number),
      role = (SELECT tmp.role FROM tmp_cond_deploy tmp WHERE tmp.serial_number = Conductivity_Loggers.serial_number),
      deployment_start = (SELECT tmp.deployment_start FROM tmp_cond_deploy tmp WHERE tmp.serial_number = Conductivity_Loggers.serial_number),
      deployment_end = (SELECT tmp.deployment_end FROM tmp_cond_deploy tmp WHERE tmp.serial_number = Conductivity_Loggers.serial_number),
      status = (SELECT tmp.status FROM tmp_cond_deploy tmp WHERE tmp.serial_number = Conductivity_Loggers.serial_number),
      notes = (SELECT tmp.notes FROM tmp_cond_deploy tmp WHERE tmp.serial_number = Conductivity_Loggers.serial_number)
    WHERE serial_number IN (SELECT serial_number FROM tmp_cond_deploy);
  ")

  dbExecute(con, "
    INSERT INTO Conductivity_Loggers
      (logger_name, manufacturer, model, serial_number, location_id, role,
       deployment_start, deployment_end, status, notes)
    SELECT
      logger_name, manufacturer, model, serial_number, location_id, role,
      deployment_start, deployment_end, status, notes
    FROM tmp_cond_deploy
    WHERE NOT EXISTS (
      SELECT 1 FROM Conductivity_Loggers c WHERE c.serial_number = tmp_cond_deploy.serial_number
    );
  ")

  dbExecute(con, "DROP TABLE tmp_cond_deploy")

  message("Conductivity logger metadata upsert complete.")

  # ==================================================
  # SECTION 4 — OBSERVATION INGEST
  # ==================================================

  csv_files <- dir_ls(raw_dir, regexp = "\\.csv$", type = "file")

  if (length(csv_files) == 0) {
    message("No conductivity observation files found — skipping.")
    return(invisible(NULL))
  }

  processed_files <- dbGetQuery(con, "SELECT file_name FROM Logger_Files_Processed")$file_name

  for (f in csv_files) {

    if (basename(f) %in% processed_files) {
      message("Skipping already processed file: ", basename(f))
      next
    }

    message("Processing: ", basename(f))

    # ---- Extract serial number from the header (line 2) ----
    header_line <- read_lines(f, n_max = 2)[2]
    serial <- str_extract(header_line, "(?<=LGR S/N: )[0-9]+")

    if (is.na(serial)) {
      stop("Could not extract logger serial number from header: ", basename(f))
    }

    logger_row <- dbGetQuery(
      con,
      "SELECT logger_id FROM Conductivity_Loggers WHERE serial_number = ?",
      params = list(serial)
    )

    if (nrow(logger_row) != 1) {
      stop("Conductivity logger serial not found in manifest: ", serial,
           " (add it to ", deploy_csv, ")")
    }
    logger_id <- logger_row$logger_id[1]

    # ---- Read data (skip the "Plot Title" line; row 2 becomes header) ----
    raw <- suppressWarnings(read_csv(f, skip = 1, show_col_types = FALSE, na = character()))

    names(raw) <- names(raw) |>
      str_replace_all("\\s+", " ") |>
      str_trim()

    time_col <- names(raw)[str_detect(names(raw), regex("Date Time", ignore_case = TRUE))][1]
    ec_col   <- names(raw)[str_detect(names(raw), regex("Full Range", ignore_case = TRUE))][1]
    temp_col <- names(raw)[str_detect(names(raw), regex("^Temp", ignore_case = TRUE))][1]
    event_cols <- names(raw)[str_detect(
      names(raw),
      regex("Coupler Detached|Coupler Attached|Stopped|End Of File", ignore_case = TRUE)
    )]

    if (is.na(time_col) || is.na(ec_col) || is.na(temp_col)) {
      stop(
        "Could not identify required columns in: ", basename(f),
        "\nColumns found: ", paste(names(raw), collapse = ", ")
      )
    }

    # ---- Collapse the 4 event columns into a single logger_event field ----
    if (length(event_cols) > 0) {
      event_matrix <- as.matrix(raw[event_cols])
      logger_event_vec <- apply(event_matrix, 1, function(row) {
        hit <- row[!is.na(row) & row != ""]
        if (length(hit) == 0) NA_character_ else paste(hit, collapse = "; ")
      })
    } else {
      logger_event_vec <- rep(NA_character_, nrow(raw))
    }

    # ---- Parse fixed-offset GMT-07:00 timestamps, standardize to UTC ----
    data <- tibble(
      logger_id = logger_id,
      timestamp_local = as.POSIXct(raw[[time_col]], format = "%m/%d/%y %I:%M:%S %p", tz = "Etc/GMT+7"),
      ec_raw = suppressWarnings(as.numeric(raw[[ec_col]])),
      temperature_c = suppressWarnings(as.numeric(raw[[temp_col]])),
      logger_event = logger_event_vec,
      source_id = source_id
    ) |>
      mutate(timestamp = format(with_tz(timestamp_local, "UTC"), "%Y-%m-%d %H:%M:%S")) |>
      filter(!is.na(timestamp) & !is.na(ec_raw)) |>
      mutate(
        sc_25c = compute_specific_conductance(ec_raw, temperature_c),
        units = "uS/cm",
        qc_flag = NA_character_
      ) |>
      select(logger_id, timestamp, ec_raw, temperature_c, sc_25c, units, logger_event, qc_flag, source_id)

    if (nrow(data) == 0) {
      stop("No valid observations after cleaning: ", basename(f))
    }

    # ---- Vector insert (append-only, deduplicated) ----
    before <- dbGetQuery(con, "SELECT COUNT(*) n FROM Conductivity_Observations")$n

    dbWriteTable(con, "tmp_cond_obs", data, overwrite = TRUE)

    dbExecute(con, "
      INSERT OR IGNORE INTO Conductivity_Observations
      (logger_id, timestamp, ec_raw, temperature_c, sc_25c, units, logger_event, qc_flag, source_id)
      SELECT logger_id, timestamp, ec_raw, temperature_c, sc_25c, units, logger_event, qc_flag, source_id
      FROM tmp_cond_obs
    ")

    dbExecute(con, "DROP TABLE tmp_cond_obs")

    after <- dbGetQuery(con, "SELECT COUNT(*) n FROM Conductivity_Observations")$n
    inserted <- after - before
    observations_inserted <- observations_inserted + inserted
    files_processed <- files_processed + 1

    message("Inserted ", inserted, " new observations (", nrow(data), " parsed) for logger_id ", logger_id)

    # ---- Archive raw file (never modify data/raw/) ----
    file_copy(f, file.path(archive_dir, basename(f)), overwrite = TRUE)

    dbExecute(con, "
      INSERT OR REPLACE INTO Logger_Files_Processed (file_name, processed_time)
      VALUES (?, ?)
    ", params = list(basename(f), format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

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
      data_source = "CONDUCTIVITY",
      script_name = "ingest_conductivity.R",
      measurements_inserted = observations_inserted,
      notes = paste("Processed", files_processed, "conductivity logger files"),
      stringsAsFactors = FALSE
    )
  )

  file_copy(
    deploy_csv,
    file.path(archive_dir, paste0("conductivity_logger_deployments_", Sys.Date(), ".csv")),
    overwrite = TRUE
  )

  message("Total conductivity observations inserted: ", observations_inserted)
  message("Conductivity logger files processed: ", files_processed)
  message("Conductivity logger ingest complete.")
}
