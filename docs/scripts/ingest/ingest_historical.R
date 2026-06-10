#-------------------------------------------------------------
#Ingest Historical Data
#-------------------------------------------------------------

# Load Libraries

library(DBI)
library(readxl)
library(dplyr)
library(lubridate)
library(purrr)

# Function wrapper for ingest call

ingest_historical <- function(con) {
  
  message("---- Starting historical ingest ----")
  
  if (missing(con)) stop("Database connection required.")

# ------------------------------------------------------------
# CONFIG
# ------------------------------------------------------------
file <- "data/raw/historical/historical_data.xlsx"

if (!file.exists(file)) {
  message("No historical file found — skipping.")
  return(invisible(NULL))
}

if (!exists("con")) {
  stop("Database connection `con` not found.")
}

dbExecute(con, "PRAGMA foreign_keys = ON;")

# ------------------------------------------------------------
# DATA SOURCE REGISTRATION
# ------------------------------------------------------------
dbExecute(con, "
INSERT OR IGNORE INTO Data_Sources (name, notes)
VALUES ('SB Historical', 'Historical NDEP and archival data');
")

source_id <- dbGetQuery(
  con,
  "SELECT source_id FROM Data_Sources WHERE name = 'SB Historical'"
)$source_id[1]

# ------------------------------------------------------------
# READ SHEETS
# ------------------------------------------------------------
locations <- read_excel(file, sheet = "locations")
samples   <- read_excel(file, sheet = "samples")
field     <- read_excel(file, sheet = "field_measurements")
lab       <- read_excel(file, sheet = "lab_analyses")

# ------------------------------------------------------------
# TYPE CLEANING
# ------------------------------------------------------------
samples <- samples %>%
  mutate(datetime = ymd_hms(datetime, quiet = TRUE))

field <- field %>%
  mutate(datetime = ymd_hms(datetime, quiet = TRUE))

lab <- lab %>%
  mutate(datetime = ymd_hms(datetime, quiet = TRUE))

# ------------------------------------------------------------
# INSERT LOCATIONS
# ------------------------------------------------------------
dbAppendTable(con, "Locations", locations)

# ------------------------------------------------------------
# RESOLVE LOCATION IDS
# ------------------------------------------------------------
loc_db <- dbReadTable(con, "Locations") %>%
  select(location_id, external_station_code)

samples <- samples %>%
  left_join(loc_db, by = "external_station_code")

field <- field %>%
  left_join(loc_db, by = "external_station_code")

lab <- lab %>%
  left_join(loc_db, by = "external_station_code")

if (any(is.na(samples$location_id))) {
  stop("Some historical samples have unknown locations.")
}

# ------------------------------------------------------------
# CREATE EVENT
# ------------------------------------------------------------
dbExecute(con, "
INSERT OR IGNORE INTO Sampling_Events (external_event_id, date, purpose)
VALUES ('SBH_BATCH', DATE('now'), 'historical')
")

event_id <- dbGetQuery(
  con,
  "SELECT event_id FROM Sampling_Events WHERE external_event_id = 'SBH_BATCH'"
)$event_id[1]

# ------------------------------------------------------------
# CREATE SAMPLES
# ------------------------------------------------------------
samples_clean <- samples %>%
  distinct(location_id, datetime) %>%
  mutate(
    sample_type = "historical",
    collection_time = datetime,
    event_id = event_id
  ) %>%
  select(location_id, event_id, sample_type, collection_time)

# insert safely
existing <- dbGetQuery(con, "
SELECT location_id, collection_time, sample_type FROM Samples
")

samples_clean <- samples_clean %>%
  anti_join(existing,
            by = c("location_id", "collection_time", "sample_type"))

dbAppendTable(con, "Samples", samples_clean)

# reload samples with IDs
samples_db <- dbReadTable(con, "Samples")

# ------------------------------------------------------------
# JOIN SAMPLE IDS
# ------------------------------------------------------------
join_keys <- samples_db %>%
  select(sample_id, location_id, collection_time, sample_type)

field <- field %>%
  left_join(join_keys,
            by = c("location_id",
                   "datetime" = "collection_time"))

lab <- lab %>%
  left_join(join_keys,
            by = c("location_id",
                   "datetime" = "collection_time"))

# ------------------------------------------------------------
# FIELD MEASUREMENTS
# ------------------------------------------------------------
field_meas <- field %>%
  transmute(
    sample_id,
    parameter,
    value,
    units,
    source_id
  )

existing_field <- dbGetQuery(con, "
SELECT sample_id, parameter FROM Field_Measurements
")

field_meas <- field_meas %>%
  anti_join(existing_field, by = c("sample_id", "parameter"))

dbWriteTable(con, "Field_Measurements", field_meas, append = TRUE)

# ------------------------------------------------------------
# LAB ANALYSES
# ------------------------------------------------------------
lab_meas <- lab %>%
  transmute(
    sample_id,
    analyte,
    value,
    units,
    fraction,
    method,
    detection_limit,
    source_id
  )

existing_lab <- dbGetQuery(con, "
SELECT sample_id, analyte FROM Lab_Analyses
")

lab_meas <- lab_meas %>%
  anti_join(existing_lab, by = c("sample_id", "analyte"))

dbAppendTable(con, "Lab_Analyses", lab_meas)

# ------------------------------------------------------------
# GEOMETRY UPDATE (already in system)
# ------------------------------------------------------------
update_location_geometry(con)

# ------------------------------------------------------------
# LOG
# ------------------------------------------------------------
dbAppendTable(
  con,
  "Ingest_Run_Log",
  data.frame(
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    data_source = "SBH",
    script_name = "ingest_sbh.R",
    samples_inserted = nrow(samples_clean),
    measurements_inserted = nrow(field_meas) + nrow(lab_meas),
    notes = "Historical ingest",
    stringsAsFactors = FALSE
  ),
)

message("Historical ingest complete.")
}