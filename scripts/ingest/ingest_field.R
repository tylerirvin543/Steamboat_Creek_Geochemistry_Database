# --------------------------------------------------
# Field data ingestion (REPRODUCIBLE & SAFE)
# --------------------------------------------------
# Purpose:
#   Ingest field data from controlled Excel templates
#   into a normalized relational database.
#
# Design principles:
#   • Humans provide only EXTERNAL identifiers
#   • Database generates all INTERNAL identifiers
#   • All ingests are idempotent (safe to re-run)
#   • Raw inputs are archived before ingestion
#   • Templates are wiped only after success
# --------------------------------------------------

library(DBI)
library(dplyr)
library(readxl)
library(openxlsx)
library(lubridate)
library(stringr)

# ==================================================
# CONFIGURATION
# ==================================================
# Directory containing raw, human-edited field templates
FIELD_DIR <- "data/raw/field"

# Directory where immutable archival snapshots are stored
ARCHIVE_DIR <- "data/processed/field_archive"

# ==================================================
# ARCHIVING & TEMPLATE MANAGEMENT
# ==================================================

# Archive raw Excel inputs prior to ingestion.
# This preserves original human-entered data and
# provides a permanent provenance record.
archive_field_excels <- function() {
  
  archive_path <- file.path(
    ARCHIVE_DIR,
    format(Sys.time(), "%Y%m%d_%H%M%S")
  )
  dir.create(archive_path, recursive = TRUE, showWarnings = FALSE)
  
  files <- c(
    "locations.xlsx",
    "sampling_events.xlsx",
    "samples.xlsx",
    "field_measurements.xlsx"
  )
  
  paths <- file.path(FIELD_DIR, files)
  existing_paths <- paths[file.exists(paths)]
  
  if (length(existing_paths) > 0) {
    file.copy(existing_paths, archive_path)
    message("Archived raw field input files.")
  } else {
    message("No field input files found to archive.")
  }
}

# Remove only data rows (not headers, formatting, or validation)
# from Excel templates after a successful ingest.
wipe_excel_data <- function(path) {
  
  wb <- loadWorkbook(path)
  sheets <- getSheetNames(path)
  
  for (s in sheets) {
    writeData(
      wb,
      sheet = s,
      x = data.frame(),
      startRow = 2,
      colNames = FALSE
    )
  }
  
  saveWorkbook(wb, path, overwrite = TRUE)
}

wipe_field_templates <- function() {
  wipe_excel_data(file.path(FIELD_DIR, "sampling_events.xlsx"))
  wipe_excel_data(file.path(FIELD_DIR, "samples.xlsx"))
  wipe_excel_data(file.path(FIELD_DIR, "field_measurements.xlsx"))
}

# ==================================================
# VALIDATION HELPERS
# ==================================================

# Prevent humans from entering database-managed IDs.
# This enforces separation of responsibility.
forbid_db_ids <- function(df, df_name) {
  
  forbidden <- c("location_id", "event_id", "measurement_id")
  
  bad <- intersect(forbidden, names(df))
  if (length(bad) > 0) {
    stop(
      df_name, " contains database-managed ID columns: ",
      paste(bad, collapse = ", ")
    )
  }
}

# ==================================================
# MAIN INGESTION FUNCTION
# ==================================================

ingest_field <- function(con) {
  
  message("Starting field data ingestion…")
  
  # Run counters
  
  locations_inserted     <- 0L
  events_inserted        <- 0L
  samples_inserted       <- 0L
  measurements_inserted  <- 0L
  
  
  # Archive raw inputs before any transformation
  archive_field_excels()
  
  # --------------------------------------------------
  # READ EXCEL INPUTS
  # --------------------------------------------------
  locations_xl <- read_excel(file.path(FIELD_DIR, "locations.xlsx"))
  events_xl    <- read_excel(file.path(FIELD_DIR, "sampling_events.xlsx"))
  samples_xl   <- read_excel(file.path(FIELD_DIR, "samples.xlsx"))
  meas_xl      <- read_excel(file.path(FIELD_DIR, "field_measurements.xlsx"))
  
  # Enforce correct usage of identifiers
  forbid_db_ids(samples_xl, "samples.xlsx")
  forbid_db_ids(meas_xl, "field_measurements.xlsx")
  
  # quick sample_id clean
  samples_xl <- samples_xl |>
    mutate(sample_id = str_to_upper(str_trim(sample_id)))
  
  meas_xl <- meas_xl |>
    mutate(sample_id = str_to_upper(str_trim(sample_id)))
# --------------------------------------------------
# CRS NORMALIZATION & VALIDATION
# --------------------------------------------------
  # Goal:
  #   Ensure all spatial data entering the system uses a 
  #   consistent, machine-readable CRS (EPSG format).
  #
  # Why:
  #   • Users may input human-readable CRS (e.g., "WGS 84")
  #   • ArcGIS and spatial operations require standardized CRS
  #   • Mixing CRS values leads to misaligned spatial layers
  #
  # Design:
  #   • Accept flexible user input
  #   • Normalize to canonical EPSG codes
  #   • Fail loudly if CRS is unknown
# --------------------------------------------------
  # Standardize external_station_code
  locations_xl <- locations_xl |>
    mutate(
      external_station_code = str_trim(external_station_code),
      external_station_code = str_to_upper(external_station_code),
      site_type = str_trim(site_type),
      site_type = str_to_lower(site_type)
    ) |>
    distinct(external_station_code, .keep_all = TRUE)
    
  # Standardize CRS from locations excel
  locations_xl <- locations_xl |>
    mutate(
      crs = case_when(
        crs %in% c("WGS 84", "WGS84") ~ "EPSG:4326",
        str_detect(crs, "4326") ~ "EPSG:4326",
        TRUE ~ crs
      )
    )

  locations_xl <- locations_xl |>
    mutate(
      latitude = as.numeric(trimws(latitude)),
      longitude = as.numeric(trimws(longitude))
    ) |>
    mutate(
      latitude = round(latitude, 6),
      longitude = round(longitude, 6),
      coord_key = paste0(latitude, "_", longitude)
    )
  
  # validate coordinates
  bad_coords <- locations_xl |>
    filter(is.na(latitude) | is.na(longitude))
  
  if (nrow(bad_coords) > 0) {
    stop(
      "Invalid latitude/longitude detected in locations.xlsx:\n",
      paste(head(bad_coords$external_station_code, 5), collapse = "\n")
    )
  }
  
  # validate coordinate ranges ( longitude < -180 | longitude > 180)
  # validate coordinate ranges ( latitude < -90 | latitude > 90)
  bad_ranges <- locations_xl |>
    filter(
      latitude < -90 | latitude > 90 |
        longitude < -180 | longitude > 180
    )
  
  if (nrow(bad_ranges) > 0) {
    stop(
      "Out-of-range coordinates detected in locations.xlsx:\n",
      paste(head(bad_ranges$external_station_code, 5), collapse = "\n"),
      "\n\nLatitude must be [-90, 90], Longitude [-180, 180]."
    )
  }
  
  # detect possible lat/lon swap
  swapped <- locations_xl |>
    filter(
      latitude > 90 & abs(longitude) <= 90
    )
  
  if (nrow(swapped) > 0) {
    warning(
      "Possible lat/lon swapped values detected:\n",
      paste(head(swapped$external_station_code, 5), collapse = "\n")
    )
  }
      
  # Validate CRS against allowed set
  # (prevents silent projection errors downstream)
  valid_crs <- c("EPSG:4326")
  
  invalid <- setdiff(unique(locations_xl$crs), valid_crs)
  
  if (length(invalid) > 0) {
    stop(
      "Invalid CRS values detected: ",
      paste(invalid, collapse = ", "),
      ". Use EPSG codes (e.g., EPSG:4326)."
    )
  }
  
  if (nrow(bad_ranges) > 0) {
    message("Bad coordinate rows detected: ", nrow(bad_ranges))
  }
  
  
# ==================================================
# LOCATIONS
# ==================================================
  # Role:
  #   Locations are the canonical spatial entities in the system.
  #
  # Key properties:
  #   • external_station_code = human-facing identifier
  #   • location_id = database primary key (internal)
  #   • CRS is REQUIRED for spatial consistency
  # Idempotency:
  #   • We only insert locations that do not already exist
  #   • Matching is done on external_station_code
# -------------------------------------------------
  
  # Locations are persistent spatial entities
  required_loc <- c(
    "external_station_code",
    "latitude",
    "longitude",
    "elevation_m",
    "crs",
    "site_type"
  )
  if (!all(required_loc %in% names(locations_xl))) {
    stop("locations.xlsx missing required columns.")
  }
  
  existing_locations <- dbReadTable(con, "Locations") %>%
    select(external_station_code, coord_key)
  
  
  locations_inserted <- 0L
  
  locations_xl <- locations_xl |>
    mutate(notes = if ("notes" %in% names(locations_xl)) notes else NA_character_)
  
  
  # Guard against duplicate external_station_code rows *within* the
  # incoming locations sheet itself (e.g. a station re-entered with a
  # slightly corrected lat/lon, which would give it a different
  # coord_key and so slip past the coord_key-based anti_join below,
  # then violate Locations.external_station_code's UNIQUE constraint
  # on insert). Keeps the first occurrence, matching the
  # distinct(..., .keep_all = TRUE) idiom already used above for
  # measurement rows.
  n_before_dedup <- nrow(locations_xl)
  locations_xl <- locations_xl %>%
    distinct(external_station_code, .keep_all = TRUE)
  if (nrow(locations_xl) < n_before_dedup) {
    message("[ingest_field] Dropped ", n_before_dedup - nrow(locations_xl),
            " duplicate external_station_code row(s) from the incoming locations sheet.")
  }

  new_locations <- locations_xl %>%
    anti_join(existing_locations, by = "external_station_code") |>
    transmute(
      external_station_code,
      name = external_station_code,
      latitude,
      longitude,
      coord_key,
      elevation_m,
      crs,
      site_type,
      notes = notes
    )
  
  if (nrow(new_locations) > 0) {
    dbAppendTable(
      con,
      "Locations",
      new_locations |> select(all_of(c(
        "external_station_code",
        "name",
        "latitude",
        "longitude",
        "coord_key",
        "elevation_m",
        "crs",
        "site_type",
        "notes"
      )))
    )
    locations_inserted <- nrow(new_locations)
    message(locations_inserted, " new field locations inserted.")
  } else {
    message("No new field locations to insert.")
  }
  
# ==================================================
# SAMPLING EVENTS
# ==================================================
  # Role:
  #   Events represent temporal groupings (field campaigns).
  # Why separate from Samples:
  #   • Multiple samples can belong to one event
  #   • Prevents duplication of metadata (observer, weather)
  #   • Enables time-based grouping and analysis
# --------------------------------------------------
  
  # Events define temporal grouping (field campaigns)
  required_evt <- c("campaign_id", "date", "observer")
  if (!all(required_evt %in% names(events_xl))) {
    stop("sampling_events.xlsx missing required columns.")
  }
  
  existing_events <- dbReadTable(con, "Sampling_Events") |>
    select(external_event_id)
  
  events_xl <- events_xl |>
    mutate(
      purpose = str_trim(purpose),
      purpose = str_to_lower(purpose)
    )
  
  valid_purpose <- c(
    "baseline",
    "post-eruption",
    "reconnaissance",
    "historical"
  )
  
  invalid_purpose <- setdiff(unique(events_xl$purpose), valid_purpose)
  
  if (length(invalid_purpose) > 0) {
    stop(
      "Invalid purpose values detected: ",
      paste(invalid_purpose, collapse = ", "),
      ". Allowed values are: ",
      paste(valid_purpose, collapse = ", ")
    )
  }
  
  new_events <- events_xl |>
    anti_join(existing_events,
              by = c("campaign_id" = "external_event_id")) |>
    transmute(
      external_event_id = campaign_id,
      date = as.Date(date),
      purpose,
      weather_conditions,
      observer,
      notes
    )
  
  if (nrow(new_events) > 0) {
    dbAppendTable(
      con,
      "Sampling_Events",
      new_events |> select(all_of(c(
        "external_event_id",
        "date",
        "purpose",
        "weather_conditions",
        "observer",
        "notes"
      )))
    )
    
    events_inserted <- nrow(new_events)
    message(events_inserted, " new sampling events inserted.")
  } else {
    message("No new sampling events to insert.")
  }
  
# ==================================================
# SAMPLES
# ==================================================
  
  # Goal:
  #   Convert user-provided external identifiers into 
  #   internal database keys required by the schema.
  #
  # Process:
  #   1. Match external_station_code → location_id
  #   2. Match campaign_id → event_id
  #
  # Why:
  #   The database does NOT store external identifiers
  #   as foreign keys — only internal IDs are persisted.
  #
  # Failure mode:
  #   If either join fails → stop ingestion immediately
# --------------------------------------------------
  
  # Samples represent physical bottles or grabs
  required_smp <- c(
    "sample_id", "campaign_id",
    "external_station_code", "sample_time"
  )
  if (!all(required_smp %in% names(samples_xl))) {
    stop("samples.xlsx missing required columns.")
  }
  
  locations_db <- dbReadTable(con, "Locations") |>
    select(location_id, external_station_code)
  
  events_db <- dbReadTable(con, "Sampling_Events") |>
    select(event_id, external_event_id)
  
  samples_db <- samples_xl |>
    mutate(
      collection_time = parse_datetime_safe(sample_time)
    ) |>
    left_join(locations_db, by = "external_station_code") |>
    left_join(events_db, by = c("campaign_id" = "external_event_id"))
  
  bad_times <- samples_db |> filter(is.na(collection_time))
  
  if (nrow(bad_times) > 0) {
    stop(
      "Unparseable timestamps detected:\n - ",
      paste(head(bad_times$sample_time, 5), collapse = "\n - ")
    )
  }
  
  
  if (any(is.na(samples_db$location_id)) ||
      any(is.na(samples_db$event_id))) {
    stop("Samples could not be matched to locations or events.")
  }
  
# --------------------------------------------------
# SAMPLE DEDUPLICATION (CRITICAL)
# --------------------------------------------------
  # Database constraint:
  #   UNIQUE(location_id, collection_time, sample_type)
  # Implication:
  #   • Two samples cannot exist at the same location,
  #     timestamp, and type
  # Strategy:
  #   • Remove rows already present in DB
  #   • Remove duplicates within current batch
  # Why:
  #   Prevents:
  #     • duplicate field entries
  #     • accidental re-ingest duplication
  #     • constraint violations during insert
# --------------------------------------------------
  dup_check <- samples_db |>
    count(location_id, collection_time, sample_type) |>
    filter(n > 1)
  
  if (nrow(dup_check) > 0) {
    message("Duplicate samples detected in incoming batch")
    print(dup_check)
  }
  # --------------------------
  # SAFE DEDUP AGAINST DATABASE
  # --------------------------
  
  # Remove duplicates within batch
  samples_db <- samples_db |>
    distinct(location_id, collection_time, sample_type, .keep_all = TRUE)
  
  # Remove rows already in DB (robust check)
  new_samples <- samples_db |>
    rowwise() |>
    filter(
      DBI::dbGetQuery(
        con,
        "
      SELECT COUNT(*) AS n
      FROM Samples
      WHERE location_id = ?
        AND collection_time = ?
        AND sample_type = ?
      ",
        params = list(location_id, collection_time, sample_type)
      )$n == 0
    ) |>
    ungroup() |>
    transmute(
      location_id,
      event_id,
      sample_type,
      collection_time,
      filtered = NA_integer_,
      preservation_method = NA_character_,
      notes,
      external_sample_id = sample_id,
      external_event_id = campaign_id,
      data_source = "FIELD"
    )
  
  new_samples <- new_samples |>
    distinct(location_id, collection_time, sample_type, .keep_all = TRUE)
  
# --------------------------------------------------
# SAMPLE INSERT
# --------------------------------------------------
  # Important:
  #   • external_station_code is NOT stored here
  #   • It has already been resolved → location_id
  #
  # Design principle:
  #   External identifiers are ONLY used for joins,
  #   never stored as relational keys.
# --------------------------------------------------
  
  if (nrow(new_samples) > 0) {
    dbAppendTable(
      con,
      "Samples",
      new_samples |> select(all_of(c(
        "location_id",
        "event_id",
        "sample_type",
        "collection_time",
        "filtered",
        "preservation_method",
        "notes",
        "external_event_id",
        "external_sample_id",
        "data_source"
      )))
    )
    samples_inserted <- nrow(new_samples)
    message(samples_inserted, " new samples inserted.")
  } else {
    message("No new field samples to insert.")
  }
  
# ==================================================
# FIELD MEASUREMENTS
# ==================================================
  # Role:
  #   Field measurements are analytical observations 
  #   attached to a specific sample.
  # Key constraint:
  #   • sample_id must exist in Samples table
  # Deduplication:
  #   • Prevent duplicate parameter entries per sample
  #     using (sample_id, parameter)
# --------------------------------------------------
  
  # Lookup table: external_sample_id → sample_id (DB key)
  sample_lookup <- dbReadTable(con, "Samples") |>
    select(sample_id, external_sample_id)
  
  # Diagnostic sample id mismatch between tables
  missing_ids <- meas_xl |>
    rename(external_sample_id = sample_id) |>
    anti_join(sample_lookup, by = "external_sample_id")
  
  if (nrow(missing_ids) > 0) {
    message("Missing sample_id values:")
    print(unique(missing_ids$external_sample_id))
  }
  
  # Rename Excel ID to avoid collision
  meas_db <- meas_xl |>
    rename(external_sample_id = sample_id) |>
    left_join(
      sample_lookup,
      by = "external_sample_id"
    ) |>
    transmute(
      sample_id = sample_id,
      parameter,
      value,
      units,
      instrument,
      source_id = NA_integer_
    )
  
  # Validate join success with explicit failure reporting
  if (any(is.na(meas_db$sample_id))) {
    
    bad_ids <- meas_xl |>
      rename(external_sample_id = sample_id) |>
      anti_join(sample_lookup, by = "external_sample_id") |>
      distinct(external_sample_id) |>
      pull(external_sample_id)
    
    stop(
      "Field measurements reference unknown sample_id values:\n",
      paste(bad_ids, collapse = "\n")
    )
  }
  
  # Existing measurements (for deduplication)
  existing_meas <- dbReadTable(con, "Field_Measurements") |>
    select(sample_id, parameter)
  
  # Remove duplicates
  meas_to_insert <- meas_db |>
    anti_join(existing_meas,
              by = c("sample_id", "parameter"))
  
  # Insert
  if (nrow(meas_to_insert) > 0) {
    dbAppendTable(
      con,
      "Field_Measurements",
      meas_to_insert |> select(all_of(c(
        "sample_id",
        "parameter",
        "value",
        "units",
        "instrument",
        "source_id"
      )))
    )
    
    measurements_inserted <- nrow(meas_to_insert)
    message(measurements_inserted,
            " new field measurements inserted.")
  } else {
    message("No new field measurements to insert.")
  }
# --------------------------------------------------
# INGEST RUN LOGGING
# --------------------------------------------------
  # Purpose:
  #   Record metadata about this ingest run for auditing,
  #   reproducibility, and debugging.
  # Captures:
  #   • timestamps
  #   • row counts by table
  #   • data source label
  # Why:
  #   Essential for:
  #     • tracking pipeline behavior over time
  #     • diagnosing ingestion issues
# --------------------------------------------------
  
  # Map to database metadata
  dbAppendTable(
    con,
    "Ingest_Run_Log",
    data.frame(
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
      data_source = "FIELD",
      script_name = "ingest_field.R",
      locations_inserted    = locations_inserted,
      events_inserted       = events_inserted,
      samples_inserted      = samples_inserted,
      measurements_inserted = measurements_inserted,
      notes = "Field ingest run",
      stringsAsFactors = FALSE
    )
  )
# ==================================================
# CLEANUP
# ==================================================
  # IMPORTANT:
  #   Templates are wiped ONLY after successful ingest.
  # Why:
  #   • Prevent accidental re-ingestion of old data
  #   • Preserve original inputs via archive step
  # Risk if removed:
  #   Duplicate data ingestion across runs
# --------------------------------------------------
  wipe_field_templates()
  message("⚠️ Field templates wiped after successful ingest.")
  message("Field data ingestion completed successfully.")
}