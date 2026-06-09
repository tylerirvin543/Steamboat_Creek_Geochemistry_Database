
# ============================================================
# ingest_flux.R
#
# Purpose:
# Ingest field-measured streamflow from transect velocity
# measurements and compute discharge.
#
# Design:
# - Accepts flexible field input (depth, width, velocity)
# - Calculates discharge at point level
# - Aggregates to transect-level discharge estimates
# - Stores results in:
#     - Samples (one per transect)
#     - Field_Measurements (discharge + statistics)
#
# Data Model:
# RAW (Excel transects)
#   → point-level velocity
#   → cross-section slices
#   → aggregated transect discharge
#   → Sample + Field_Measurement entries
#
# Supports:
# - Multiple transects per station
# - Multiple velocity measurements per slice
# - Optional area input (otherwise computed)
#
# Future Extensions:
# - Weighted velocity profiles
# - Method comparison (mean vs depth-weighted)
# - Integration with USGS discharge time series
# - Flux coupling with chemistry
#
# ============================================================

library(DBI)
library(readxl)
library(dplyr)
library(purrr)
library(lubridate)
library(stringr)
library(fs)

ingest_flux <- function(con) {
  
  message("---- Starting flux ingest ----")
  
  if (missing(con)) stop("Database connection required.")
  
  # ------------------------------------------------------------
  # CONFIG
  # ------------------------------------------------------------
  flux_file <- "data/raw/discharge/stream_discharge.xlsx"
  
  if (!file.exists(flux_file)) {
    message("No flux file found — skipping.")
    return(invisible(NULL))
  }
  
  dbExecute(con, "PRAGMA foreign_keys = ON;")
  
  archive_dir <- file.path("data/processed/flux_archive",
                           format(Sys.time(), "%Y%m%d_%H%M"))
  dir_create(archive_dir)
  
  # ------------------------------------------------------------
  # COUNTERS
  # ------------------------------------------------------------
  samples_inserted      <- 0L
  measurements_inserted <- 0L
  
  # ------------------------------------------------------------
  # DATA SOURCE
  # ------------------------------------------------------------
  dbExecute(con, "
    INSERT OR IGNORE INTO Data_Sources (name, notes)
    VALUES ('Flux Transects', 'Field-measured streamflow transects');
  ")
  
  source_id <- dbGetQuery(con, "
    SELECT source_id FROM Data_Sources
    WHERE name = 'Flux Transects'
  ")$source_id[1]
  
  # ------------------------------------------------------------
  # METADATA (OPTIONAL)
  # ------------------------------------------------------------
  meta <- tryCatch(
    read_excel(flux_file, sheet = "metadata", col_names = FALSE),
    error = function(e) NULL
  )
  
  meta_list <- if (!is.null(meta)) setNames(meta$X2, meta$X1) else list()
  
  # ------------------------------------------------------------
  # READ TRANSECT SHEETS
  # ------------------------------------------------------------
  sheets <- excel_sheets(flux_file)
  data_sheets <- sheets[sheets != "metadata"]
  
  if (length(data_sheets) == 0) {
    stop("No transect sheets found.")
  }
  
  raw_data <- map_dfr(data_sheets, function(sheet) {
    df <- read_excel(flux_file, sheet = sheet)
    
    df %>%
      mutate(sheet_name = sheet)
  })
  
  # ------------------------------------------------------------
  # STANDARDIZE COLUMN NAMES
  # ------------------------------------------------------------
  raw_data <- raw_data %>%
    rename_with(tolower) %>%
    rename(
      depth_total_m = depth_m,
      velocity_m_s  = velocity
    )
  
  # ------------------------------------------------------------
  # REQUIRED COLUMN CHECK
  # ------------------------------------------------------------
  required_cols <- c(
    "external_station_code",
    "datetime",
    "transect_id",
    "point_id",
    "depth_total_m",
    "width_m",
    "velocity_m_s"
  )
  
  if (!all(required_cols %in% names(raw_data))) {
    stop("Missing required columns in flux file.")
  }
  
  # ------------------------------------------------------------
  # TYPE STANDARDIZATION
  # ------------------------------------------------------------
  raw_data <- raw_data %>%
    mutate(
      datetime       = ymd_hms(datetime, quiet = TRUE),
      depth_total_m  = as.numeric(depth_total_m),
      width_m        = as.numeric(width_m),
      velocity_m_s   = as.numeric(velocity_m_s)
    )
  
  if (any(is.na(raw_data$datetime))) {
    stop("Invalid datetime values.")
  }
  
  # ------------------------------------------------------------
  # BASIC VALIDATION
  # ------------------------------------------------------------
  if (any(raw_data$depth_total_m <= 0, na.rm = TRUE)) {
    stop("depth must be > 0")
  }
  
  if (any(raw_data$width_m <= 0, na.rm = TRUE)) {
    stop("width must be > 0")
  }
  
  if (any(raw_data$velocity_m_s < 0, na.rm = TRUE)) {
    stop("Negative velocities detected.")
  }
  
  # ------------------------------------------------------------
  # AREA + DISCHARGE (POINT LEVEL)
  # ------------------------------------------------------------
  raw_data <- raw_data %>%
    mutate(
      area_m2 = if ("area" %in% names(.)) {
        ifelse(!is.na(area), area, depth_total_m * width_m)
      } else {
        depth_total_m * width_m
      },
      discharge_point_m3_s = velocity_m_s * area_m2
    )
  
  # ------------------------------------------------------------
  # RESOLVE LOCATIONS
  # ------------------------------------------------------------
  locations <- dbReadTable(con, "Locations") %>%
    select(location_id, external_station_code)
  
  raw_data <- raw_data %>%
    left_join(locations, by = "external_station_code")
  
  if (any(is.na(raw_data$location_id))) {
    stop("Unknown external_station_code detected.")
  }
  
  # ------------------------------------------------------------
  # AGGREGATE TO TRANSECT
  # ------------------------------------------------------------
  transect_data <- raw_data %>%
    group_by(location_id, external_station_code, datetime, transect_id) %>%
    summarise(
      discharge_total_m3_s = sum(discharge_point_m3_s, na.rm = TRUE),
      discharge_mean_m3_s  = mean(discharge_point_m3_s, na.rm = TRUE),
      velocity_mean        = mean(velocity_m_s, na.rm = TRUE),
      velocity_sd          = sd(velocity_m_s, na.rm = TRUE),
      n_points             = n(),
      .groups = "drop"
    )
  
  # ------------------------------------------------------------
  # SAMPLE IDS (TRANSECT LEVEL)
  # ------------------------------------------------------------
  transect_data <- transect_data %>%
    mutate(
      sample_id = paste0(
        "FLUX_",
        external_station_code, "_",
        format(datetime, "%Y%m%d%H%M"),
        "_", transect_id
      )
    )
  
  if (any(duplicated(transect_data$sample_id))) {
    stop("Duplicate sample_id generated.")
  }
  
  # ------------------------------------------------------------
  # INSERT INTO SAMPLES
  # ------------------------------------------------------------
  samples <- transect_data %>%
    select(sample_id, location_id, collection_time = datetime)
  
  existing_samples <- dbGetQuery(con, "SELECT sample_id FROM Samples")
  
  samples <- samples %>%
    anti_join(existing_samples, by = "sample_id")
  
  dbWriteTable(con, "Samples", samples, append = TRUE)
  
  samples_inserted <- nrow(samples)
  
  # ------------------------------------------------------------
  # FIELD MEASUREMENTS
  # ------------------------------------------------------------
  measurements <- bind_rows(
    
    transect_data %>%
      transmute(sample_id, parameter = "discharge_total", value = discharge_total_m3_s, units = "m3/s"),
    
    transect_data %>%
      transmute(sample_id, parameter = "discharge_mean_point", value = discharge_mean_m3_s, units = "m3/s"),
    
    transect_data %>%
      transmute(sample_id, parameter = "velocity_mean", value = velocity_mean, units = "m/s"),
    
    transect_data %>%
      transmute(sample_id, parameter = "velocity_sd", value = velocity_sd, units = "m/s"),
    
    transect_data %>%
      transmute(sample_id, parameter = "n_points", value = n_points, units = "count")
    
  ) %>%
    mutate(
      source_id = source_id,
      status = NA_character_
    )
  
  # ------------------------------------------------------------
  # DEDUPLICATION
  # ------------------------------------------------------------
  existing_meas <- dbGetQuery(con,
                              "SELECT sample_id, parameter FROM Field_Measurements"
  )
  
  measurements <- measurements %>%
    anti_join(existing_meas, by = c("sample_id", "parameter"))
  
  dbAppendTable(con, "Field_Measurements", measurements)
  
  measurements_inserted <- nrow(measurements)
  
  # ------------------------------------------------------------
  # LOGGING
  # ------------------------------------------------------------
  dbAppendTable(
    con,
    "Ingest_Run_Log",
    data.frame(
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
      data_source = "FLUX",
      script_name = "ingest_flux.R",
      samples_inserted = samples_inserted,
      measurements_inserted = measurements_inserted,
      notes = paste("Flux ingest", meta_list[["campaign_name"]] %||% ""),
      stringsAsFactors = FALSE
    )
  )
  
  # ------------------------------------------------------------
  # ARCHIVE RAW FILE
  # ------------------------------------------------------------
  file_copy(
    flux_file,
    file.path(archive_dir,
              paste0("flux_transects_", Sys.Date(), ".xlsx")),
    overwrite = TRUE
  )
  
  message("✅ Flux ingest complete.")
  message("Samples inserted: ", samples_inserted)
  message("Measurements inserted: ", measurements_inserted)
}