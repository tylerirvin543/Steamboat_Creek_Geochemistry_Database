# --------------------------------------------------
# ingest_ndep.R
# Master NDEP ingestion script
# --------------------------------------------------
# Purpose:
#   Ingest regulatory water quality data from the
#   Nevada Division of Environmental Protection (NDEP)
#   into the normalized database schema.
#
# Design principles:
#   • External data is normalized into internal schema
#   • CRS is assumed and enforced (EPSG:4326)
#   • External identifiers are resolved to internal IDs
#   • Ingest is idempotent and safe to re-run
#   • Data source attribution is preserved
# --------------------------------------------------


library(DBI)
library(RSQLite)
library(dplyr)

# --------------------------------------------------
# CONFIG
# --------------------------------------------------
# Expected inputs:
#   • StationData.csv → spatial metadata (locations)
#   • NormalizedData.csv → samples + chemistry
# Assumption:
#   These files follow NDEP export structure and
#   contain consistent identifiers across tables.
# --------------------------------------------------


ndep_dir <- "data/raw/ndep"

station_file <- file.path(ndep_dir, "StationData.csv")
normalized_file <- file.path(ndep_dir, "NormalizedData.csv")

# --------------------------------------------------
# LOAD SCHEMA & HELPERS
# --------------------------------------------------
# Helpers encapsulate parsing and transformation logic:
#   • parse_ndep_locations → builds spatial entities
#   • extract_ndep_samples → reconstructs sample records
#   • parse_ndep_chemistry → maps analytes to schema
#   • build_sample_lookup → resolves sample IDs
# Design:
#   Separation of concerns keeps ingest script clean
#   and allows independent testing of components.
# --------------------------------------------------


source("database/schema/ndep_analyte_map.R")
source("database/schema/02_define_validators.R")

source("scripts/ingest/helpers/ndep_locations.R")
source("scripts/ingest/helpers/extract_ndep_samples.R")
source("scripts/ingest/helpers/parse_ndep_chemistry.R")
source("scripts/ingest/helpers/build_sample_lookup.R")

# --------------------------------------------------
# CONNECT
# --------------------------------------------------

dbExecute(con, "PRAGMA foreign_keys = ON;")

#set run counters
locations_inserted     <- 0L
events_inserted        <- 0L
samples_inserted       <- 0L
measurements_inserted  <- 0L
# --------------------------------------------------
# REGISTER DATA SOURCE
# --------------------------------------------------
# Purpose:
#   Track provenance of all analytical data.
# Why:
#   • Enables traceability of regulatory datasets
#   • Supports multi-source integration (NDEP, field, lab)
#   • Required for reproducibility and auditing
# Pattern:
#   INSERT OR IGNORE ensures idempotent registration
# --------------------------------------------------

dbExecute(con, "
INSERT OR IGNORE INTO Data_Sources (name, citation, url)
VALUES (
  'Nevada DEP Water Quality Portal',
  'Nevada Division of Environmental Protection',
  'https://nevadawaterquality.ndep.nv.gov'
);
")

source_id <- dbGetQuery(
  con,
  "SELECT source_id FROM Data_Sources WHERE name = 'Nevada DEP Water Quality Portal'"
)$source_id[1]

# --------------------------------------------------
# READ RAW DATA
# --------------------------------------------------

stations_raw <- read.csv(station_file, stringsAsFactors = FALSE)
norm_raw <- read.csv(normalized_file, stringsAsFactors = FALSE)

#standardize and normalize
names(norm_raw) <- trimws(names(norm_raw))
names(norm_raw) <- gsub("^X\\.\\.\\.", "", names(norm_raw))
names(norm_raw) <- gsub("\ufeff", "", names(norm_raw))
names(norm_raw) <- toupper(names(norm_raw))

print(names(norm_raw))

# --------------------------------------------------
# LOCATIONS
# --------------------------------------------------
# Role:
#   Convert NDEP station metadata into canonical Locations.
# Key differences from field ingest:
#   • CRS is assigned automatically (EPSG:4326)
#   • elevation_m may be missing → set to NA
# Validation:
#   validate_locations() ensures required fields exist
# Idempotency:
#   insert_ndep_locations() prevents duplicate site creation
# --------------------------------------------------


ndep_locations <- parse_ndep_locations(station_file)
validate_locations(ndep_locations)
insert_ndep_locations(con, ndep_locations)

station_lookup <- build_station_location_lookup(con)

# --------------------------------------------------
# SAMPLING EVENTS
# --------------------------------------------------
# Role:
#   Reconstruct sampling events from NDEP records.
# Why reconstruction is needed:
#   NDEP data does not explicitly define "events"
#   → events are inferred from identifiers in normalized data
# Idempotency:
#   • Avoid inserting events already in database
#   • Remove duplicates within incoming batch
# --------------------------------------------------

events <- extract_ndep_events(norm_raw)

# Read existing events from DB
existing_events <- DBI::dbReadTable(con, "Sampling_Events")

# Identify events not yet in DB
if (nrow(existing_events) == 0) {
  new_events <- events
} else {
  new_events <- events[
    !events$external_event_id %in%
      existing_events$external_event_id,
    ,
    drop = FALSE
  ]
}

# **Critical**: enforce uniqueness within the batch itself
new_events <- new_events[!duplicated(new_events$external_event_id), , drop = FALSE]

if (nrow(new_events) == 0) {
  message("No new NDEP events to insert.")
} else {
  DBI::dbAppendTable(
    con,
    "Sampling_Events",
    new_events[, c(
      "external_event_id",
      "date",
      "purpose",
      "weather_conditions",
      "observer",
      "notes"
    )]
  )
  events_inserted <- nrow(new_events)
  message(events_inserted, " NDEP sampling events inserted.")
}

# --------------------------------------------------
# SAMPLES
# --------------------------------------------------
# Role:
#   Construct sample records from NDEP normalized dataset.
# Key challenge:
#   NDEP data is not normalized → samples must be derived
#   from repeated measurement records.
# Process:
#   • Extract unique sample identifiers
#   • Resolve:
#       external_station_code → location_id
#       external_event_id → event_id
# Integrity checks:
#   • All samples MUST resolve to valid location_id
#   • All samples MUST resolve to valid event_id
# Failure mode:
#   stopifnot() ensures ingest halts on broken joins
# --------------------------------------------------
samples <- extract_ndep_samples(norm_raw)

locations_db <- dbReadTable(con, "Locations")
events_db <- dbReadTable(con, "Sampling_Events")

samples_db <- samples |>
  left_join(
    locations_db[, c("location_id", "external_station_code")],
    by = "external_station_code"
  ) |>
  left_join(
    events_db[, c("event_id", "external_event_id")],
    by = "external_event_id",
    relationship = "many-to-one"
  )


samples_db <- samples_db |>
  mutate(collection_time = parse_datetime_safe(collection_time))

stopifnot(all(!is.na(samples_db$location_id)))
stopifnot(all(!is.na(samples_db$event_id)))

# --------------------------------------------------
# SAMPLE DEDUPLICATION (NDEP)
# --------------------------------------------------
# Same uniqueness constraint as field ingest:
#   UNIQUE(location_id, collection_time, sample_type)
# --------------------------------------------------

# --------------------------
# SAFE DEDUP AGAINST DATABASE
# --------------------------

# Remove duplicates within batch
samples_db <- samples_db |>
  distinct(external_sample_id, .keep_all = TRUE)

# Remove rows already in DB (robust check)
existing_samples <- dbGetQuery(con, "
  SELECT external_sample_id FROM Samples
")$external_sample_id

new_samples <- samples_db |>
  filter(!external_sample_id %in% existing_samples)


new_samples <- new_samples |>
  transmute(
    location_id,
    event_id,
    sample_type,
    collection_time,
    filtered,
    preservation_method,
    notes,
    external_event_id,
    external_sample_id,
    data_source = "NDEP"
  )

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
  message(samples_inserted, " NDEP samples inserted.")
} else {
  message("No new NDEP samples to insert.")
}
# --------------------------------------------------
# LAB ANALYSES (CHEMISTRY)
# --------------------------------------------------
# Role:
#   Normalize analytical chemistry data into Lab_Analyses table.
# Process:
#   • Map NDEP analyte names → standardized parameter names
#   • Convert units (if needed)
#   • Attach each result to sample_id
#   • Record data source via source_id
# Importance:
#   This step standardizes heterogeneous regulatory data
#   into a consistent analytical framework.
# --------------------------------------------------
sample_lookup <- build_sample_lookup(con)

lab_df <- parse_ndep_chemistry(
  norm_raw,
  ndep_analyte_map,
  sample_lookup,
  source_id
)


# --------------------------------------------------
# DEDUPLICATE AGAINST EXISTING Lab_Analyses ROWS
# --------------------------------------------------
# Unlike Locations/Sampling_Events/Samples above, this insert had no
# guard at all before 2026-09-05 -- every pipeline run re-appended the
# full lab_df, which is how the operational database ended up with
# NDEP chemistry duplicated many times over. Matches the
# anti_join(..., by = c("sample_id", "analyte", "source_id")) pattern
# already used in ingest_lab.R / ingest_isotopes.R.
existing_lab <- dbGetQuery(con, "
  SELECT sample_id, analyte, source_id FROM Lab_Analyses WHERE source_id = ?
", params = list(source_id))

lab_df <- lab_df |>
  distinct(sample_id, analyte, source_id, .keep_all = TRUE) |>
  anti_join(existing_lab, by = c("sample_id", "analyte", "source_id"))

dbAppendTable(
  con,
  "Lab_Analyses",
  lab_df,
)

measurements_inserted <- nrow(lab_df)
message(measurements_inserted, " NDEP chemistry records inserted.")

# --------------------------------------------------
# INGEST RUN LOGGING
# --------------------------------------------------
# Purpose:
#   Record metadata for this ingest run.
# Additional note:
#   Distinguishes NDEP ingest from Field ingest
#   for downstream auditing and debugging.
# --------------------------------------------------
dbAppendTable(
  con,
  "Ingest_Run_Log",
  data.frame(
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    data_source = "NDEP",
    script_name = "ingest_ndep.R",
    locations_inserted    = locations_inserted,
    events_inserted       = events_inserted,
    samples_inserted      = samples_inserted,
    measurements_inserted = measurements_inserted,
    notes = "NDEP normalized chemistry ingest",
    stringsAsFactors = FALSE
  )
)

message("NDEP ingestion complete.")
