# --------------------------------------------------
# ingest_photos.R
# Ingest photographic metadata linked to sites,
# samples, and/or sampling events
# --------------------------------------------------

library(DBI)
library(dplyr)
library(readxl)
library(lubridate)
library(stringr)

# Function Wrapper for Ingest Source Call

ingest_photos <- function(con) {
  
  message("---- Starting photo ingest ----")
  
  if (missing(con)) stop("Database connection required.")
  

PHOTO_FILE <- "data/raw/field/photos.xlsx"

if (!file.exists(PHOTO_FILE)) {
  message("No photos.xlsx found — skipping photo ingest.")
  return(invisible(NULL))
}

photos_xl <- read_excel(PHOTO_FILE)

# -----------------------------
# Validate required columns
# -----------------------------
required_cols <- c(
  "photo_filename",
  "relative_path",
  "external_station_code",
  "crs"
)

missing <- setdiff(required_cols, names(photos_xl))
if (length(missing) > 0) {
  stop("photos.xlsx missing required columns: ",
       paste(missing, collapse = ", "))
}

# Normalize crs
photos_xl <- photos_xl |>
  mutate(
    crs = case_when(
      crs %in% c("WGS 84", "WGS84") ~ "EPSG:4326",
      str_detect(crs, "4326") ~ "EPSG:4326",
      TRUE ~ crs
    )
  )
# Validate crs
valid_crs <- c("EPSG:4326")

invalid <- setdiff(unique(photos_xl$crs), valid_crs)

if (length(invalid) > 0) {
  stop(
    "Invalid CRS values in photos.xlsx: ",
    paste(invalid, collapse = ", ")
  )
}
# -----------------------------
# Resolve event_id from campaign_id
# -----------------------------
event_lookup <- dbReadTable(con, "Sampling_Events") |>
  select(event_id, external_event_id)

photos_db <- photos_xl |>
  left_join(
    event_lookup,
    by = c("campaign_id" = "external_event_id")
  )

if (any(!is.na(photos_db$campaign_id) & is.na(photos_db$event_id))) {
  stop("Some photos reference unknown campaign_id values.")
}

# -----------------------------
# Optional validation: locations
# -----------------------------
location_lookup <- dbReadTable(con, "Locations") |>
  select(external_station_code)

bad_sites <- photos_db |>
  anti_join(location_lookup, by = "external_station_code")

if (nrow(bad_sites) > 0) {
  stop("Some photos reference unknown external_station_code values.")
}

# -----------------------------
# Insert photos
# -----------------------------
existing_photos <- dbReadTable(con, "Photos") |>
  select(photo_filename, relative_path)

photos_to_insert <- photos_db |>
  anti_join(existing_photos,
            by = c("photo_filename", "relative_path")) |>
  transmute(
    photo_filename,
    relative_path,
    external_station_code,
    sample_id = ifelse(sample_id == "", NA, sample_id),
    event_id,
    taken_time = ymd_hms(photo_time, quiet = TRUE),
    latitude,
    longitude,
    elevation_m,
    device,
    crs,
    notes
  )

photos_inserted <- 0L

if (nrow(photos_to_insert) > 0) {
  dbWriteTable(con, "Photos", photos_to_insert, append = TRUE)
  photos_inserted <- nrow(photos_to_insert)
  message(photos_inserted, " photos ingested.")
} else {
  message("No new photos to ingest.")
}

# -----------------------------
# Log ingest run
# -----------------------------
dbAppendTable(
  con,
  "Ingest_Run_Log",
  data.frame(
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    data_source = "PHOTO",
    script_name = "ingest_photos.R",
    locations_inserted    = 0,
    events_inserted       = 0,
    samples_inserted      = 0,
    measurements_inserted = photos_inserted,
    notes = "Photographic metadata ingest",
    stringsAsFactors = FALSE
  ),
)

message("---- Photo ingest COMPLETE ----")

}
