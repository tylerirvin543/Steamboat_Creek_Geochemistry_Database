# ============================================================
# ingest_earthquakes.R
#
# ingest_earthquakes(con, csv_dir = "data/raw/earthquakes")
#
# Ingests a real USGS earthquake catalog export (see
# data/raw/earthquakes/README.md for the exact FDSN query used) into
# Earthquake_Events, computing each event's distance to the Steamboat
# Hills field center at ingest time. Built to check whether nearby
# seismicity coincides with detectable water-level/temperature/
# barometric-response anomalies -- Sorey & Colvard (1992) name
# earthquakes as a real historical influence on this system's spring
# water levels, alongside barometric pressure and precipitation.
#
# Any CSV under csv_dir with the USGS FDSN CSV column signature
# (time, latitude, longitude, mag, place, ...) is auto-detected and
# ingested, mirroring this project's other "any file, format detected
# from content" ingest scripts. Idempotent on `id` (the USGS event id
# is globally unique and stable), so re-running after downloading a
# fresh/updated extract only inserts genuinely new events.
# ============================================================

library(DBI)
library(dplyr)

STEAMBOAT_LAT <- 39.385
STEAMBOAT_LON <- -119.755

.haversine_km <- function(lat1, lon1, lat2, lon2) {
  R <- 6371
  dlat <- (lat2 - lat1) * pi / 180
  dlon <- (lon2 - lon1) * pi / 180
  a <- sin(dlat / 2)^2 + cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dlon / 2)^2
  2 * R * asin(sqrt(a))
}

.find_usgs_earthquake_files <- function(csv_dir) {
  candidates <- list.files(csv_dir, pattern = "\\.csv$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
  keep <- vapply(candidates, function(f) {
    first_line <- tryCatch(readLines(f, n = 1, warn = FALSE), error = function(e) "")
    cols <- tolower(trimws(strsplit(first_line, ",")[[1]]))
    all(c("time", "latitude", "longitude", "mag", "place", "id") %in% cols)
  }, logical(1))
  candidates[keep]
}

ingest_earthquakes <- function(con, csv_dir = "data/raw/earthquakes") {
  if (!dir.exists(csv_dir)) {
    message("[eq] No directory at ", csv_dir, " -- nothing to ingest.")
    return(invisible(NULL))
  }

  files <- .find_usgs_earthquake_files(csv_dir)
  if (length(files) == 0) {
    message("[eq] No USGS earthquake CSVs found under ", csv_dir, ".")
    return(invisible(NULL))
  }

  raw <- dplyr::bind_rows(lapply(files, function(f) {
    d <- readr::read_csv(f, show_col_types = FALSE)
    names(d) <- tolower(names(d))
    d
  }))

  events <- raw |>
    dplyr::transmute(
      event_id = id,
      event_time = as.character(time),
      latitude = latitude,
      longitude = longitude,
      depth_km = depth,
      magnitude = mag,
      mag_type = magtype,
      place = place,
      event_type = type,
      dist_to_steamboat_km = .haversine_km(STEAMBOAT_LAT, STEAMBOAT_LON, latitude, longitude),
      source = "USGS FDSN Event Web Service",
      retrieved_at = as.character(Sys.time())
    ) |>
    dplyr::distinct(event_id, .keep_all = TRUE)

  existing <- tryCatch(dbGetQuery(con, "SELECT event_id FROM Earthquake_Events")$event_id, error = function(e) character(0))
  new_events <- events |> dplyr::filter(!event_id %in% existing)

  if (nrow(new_events) > 0) {
    dbWriteTable(con, "Earthquake_Events", new_events, append = TRUE, row.names = FALSE)
  }

  message("[eq] Ingested ", nrow(new_events), " new earthquake event(s) from ", length(files),
          " file(s) (", nrow(events) - nrow(new_events), " already present, skipped). ",
          "Within 15 km of the Steamboat field: ",
          sum(new_events$dist_to_steamboat_km <= 15), " new / ",
          sum(events$dist_to_steamboat_km <= 15), " total.")

  invisible(new_events)
}
