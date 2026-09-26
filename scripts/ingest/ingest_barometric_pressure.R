# ============================================================
# ingest_barometric_pressure.R
#
# ingest_barometric_pressure(con, base_dir = "data/raw/airpressure")
#
# Ingests hourly barometric pressure (mean sea-level pressure, MSLP)
# for Reno-Tahoe International Airport (ICAO/ASOS "RNO"), downloaded
# from the Iowa Environmental Mesonet's public ASOS archive
# (mesonet.agron.iastate.edu -- see data/raw/airpressure/README.md for
# the exact download process). This is the real barometric-pressure
# source the Session 27/29 notebook work flagged as missing ("no
# barometric/station pressure parameter currently exists anywhere in
# this database") -- it unblocks a real (non-synthetic) barometric-
# efficiency calculation (see scripts/analysis/barometric_efficiency.R).
#
# Deliberately reuses the existing generic Weather_Stations /
# Weather_Observations long-format tables (03_weather_schema.R) rather
# than adding a new table -- same design principle already used for
# ingest_usgs_historic_chemistry.R ("same tables ... so [two related
# series] are a one-line join away"). The one wrinkle: this table's
# `date` column is really a date+time key for this source (hourly, not
# daily) -- that's fine, the column is TEXT and the primary key is
# (station_id, date, parameter), so a full "YYYY-MM-DD HH:MM:SS"
# timestamp is a perfectly valid, unique value per row.
#
# Station identity: the IEM ASOS coordinate for "RNO"
# (39.4839, -119.7711) sits ~2.6 km from the coordinate already stored
# for Weather_Stations "USW00023185" ("RENO AIRPORT, NV US",
# 39.50769, -119.7683, the NOAA GHCN Daily station used by
# ingest_noaa_weather.R) -- both are real reference points on/near the
# same large airport (GHCN's coordinate is the official station
# location; ASOS instrumentation sits elsewhere on the field), not two
# different airports. This script deliberately reuses the SAME
# station_id ("USW00023185") so barometric pressure joins to the
# existing temperature/precipitation record by station_id with no
# extra mapping step -- consistent with the project's standing
# "reuse the same station identity when it's genuinely the same
# station" rule. It does NOT overwrite the existing Weather_Stations
# coordinate (never overwrite an existing field, per project
# convention); the ASOS coordinate is recorded in this script's own
# console message only, for anyone who later wants the more precise
# instrument location.
#
# Any file anywhere under base_dir whose header matches the IEM
# export's column signature (station,valid,lon,lat,elevation,mslp,
# case-insensitive, any column order) is auto-detected and ingested --
# consistent with this project's "new file just works" convention for
# NOAA/weather-style sources (see ingest_noaa_weather.R). Idempotent via
# an anti_join against existing Weather_Observations rows and a
# Weather_Files_Processed(file_name) log (same table
# ingest_noaa_weather.R already writes to).
# ============================================================

library(DBI)
library(dplyr)
library(readr)
library(stringr)
library(lubridate)

RNO_STATION_ID <- "USW00023185"   # same physical airport as the existing GHCN station
RNO_ASOS_COORD <- c(lat = 39.4839, lon = -119.7711)  # IEM's own reported ASOS coordinate, reference only

#' Find every CSV under base_dir whose header matches the IEM ASOS
#' MSLP export signature.
.find_iem_pressure_files <- function(base_dir) {
  candidates <- list.files(base_dir, pattern = "\\.csv$", recursive = TRUE,
                            full.names = TRUE, ignore.case = TRUE)
  keep <- vapply(candidates, function(f) {
    first_line <- tryCatch(readLines(f, n = 1, warn = FALSE), error = function(e) "")
    cols <- tolower(trimws(strsplit(first_line, ",")[[1]]))
    all(c("station", "valid", "mslp") %in% cols)
  }, logical(1))
  candidates[keep]
}

#' Parse one IEM ASOS pressure export file.
#' Expected columns (any order): station, valid, lon, lat, elevation, mslp
#' `valid` is a local-time string like "1/1/2025 0:55" (M/D/YYYY H:MM).
#' `mslp` is mean sea-level pressure in hectopascals (hPa).
.parse_iem_pressure_file <- function(path) {
  raw <- readr::read_csv(path, col_types = readr::cols(.default = "c"), show_col_types = FALSE)
  names(raw) <- tolower(trimws(names(raw)))

  if (!all(c("station", "valid", "mslp") %in% names(raw))) {
    warning("[baro] Skipping ", path, " -- missing required column(s).")
    return(NULL)
  }

  parsed_ts <- suppressWarnings(lubridate::mdy_hm(raw$valid))
  n_bad_ts <- sum(is.na(parsed_ts) & !is.na(raw$valid) & nzchar(raw$valid))
  if (n_bad_ts > 0) {
    message("[baro] ", basename(path), ": ", n_bad_ts,
            " row(s) had an unparseable `valid` timestamp -- dropped, not guessed.")
  }

  out <- tibble::tibble(
    station_id = RNO_STATION_ID,
    date = format(parsed_ts, "%Y-%m-%d %H:%M:%S"),
    parameter = "MSLP",
    value = suppressWarnings(as.numeric(raw$mslp)),
    unit = "hPa",
    quality_flag = NA_character_,
    source_file = basename(path)
  ) |>
    dplyr::filter(!is.na(date), !is.na(value))

  out
}

#' Ingest all IEM ASOS barometric-pressure files under base_dir.
ingest_barometric_pressure <- function(con, base_dir = "data/raw/airpressure") {
  if (!dir.exists(base_dir)) {
    message("[baro] No directory at ", base_dir, " -- nothing to ingest.")
    return(invisible(NULL))
  }

  files <- .find_iem_pressure_files(base_dir)
  if (length(files) == 0) {
    message("[baro] No IEM ASOS pressure CSVs found under ", base_dir, ".")
    return(invisible(NULL))
  }

  already_processed <- tryCatch(
    dbGetQuery(con, "SELECT file_name FROM Weather_Files_Processed")$file_name,
    error = function(e) character(0)
  )
  new_files <- files[!basename(files) %in% already_processed]

  if (length(new_files) == 0) {
    message("[baro] All ", length(files), " IEM pressure file(s) already ingested -- nothing new.")
    return(invisible(NULL))
  }

  # ---- Register the station (never overwrite an existing row) ----
  existing_station <- dbGetQuery(con, sprintf(
    "SELECT * FROM Weather_Stations WHERE station_id = '%s'", RNO_STATION_ID
  ))
  if (nrow(existing_station) == 0) {
    dbExecute(con, sprintf("
      INSERT INTO Weather_Stations (station_id, name, latitude, longitude, elevation_m, source)
      VALUES ('%s', 'RENO AIRPORT, NV US', %f, %f, %f, 'NOAA/IEM ASOS (mesonet.agron.iastate.edu)')
    ", RNO_STATION_ID, RNO_ASOS_COORD["lat"], RNO_ASOS_COORD["lon"], 1345 * 0.3048))
    message("[baro] Registered new Weather_Stations row for ", RNO_STATION_ID, ".")
  } else {
    dist_deg <- sqrt((existing_station$latitude - RNO_ASOS_COORD["lat"])^2 +
                      (existing_station$longitude - RNO_ASOS_COORD["lon"])^2)
    message("[baro] Reusing existing Weather_Stations row for ", RNO_STATION_ID,
            " (GHCN coordinate; IEM's own ASOS coordinate differs by ~",
            round(dist_deg * 111, 1), " km -- both are real points on/near the",
            " same airport, not two different stations; existing coordinate left untouched).")
  }

  parsed <- lapply(new_files, .parse_iem_pressure_file)
  parsed <- parsed[!vapply(parsed, is.null, logical(1))]
  if (length(parsed) == 0) {
    message("[baro] No parseable rows in any new file.")
    return(invisible(NULL))
  }
  obs <- dplyr::bind_rows(parsed) |>
    dplyr::distinct(station_id, date, parameter, .keep_all = TRUE)

  existing_obs <- dbGetQuery(con, "SELECT station_id, date, parameter FROM Weather_Observations WHERE parameter = 'MSLP'")
  new_obs <- obs |> dplyr::anti_join(existing_obs, by = c("station_id", "date", "parameter"))

  if (nrow(new_obs) > 0) {
    dbWriteTable(con, "Weather_Observations", new_obs, append = TRUE, row.names = FALSE)
  }

  dbExecute(con, "CREATE TABLE IF NOT EXISTS Weather_Files_Processed (file_name TEXT PRIMARY KEY, format TEXT, processed_at TEXT)")
  for (f in new_files) {
    dbExecute(con, "INSERT OR IGNORE INTO Weather_Files_Processed (file_name, format, processed_at) VALUES (?, 'iem_asos_mslp', ?)",
              params = list(basename(f), as.character(Sys.time())))
  }

  message("[baro] Ingested ", nrow(new_obs), " new hourly MSLP observation(s) from ",
          length(new_files), " new file(s) (", nrow(obs) - nrow(new_obs),
          " already present, skipped). Range: ",
          if (nrow(new_obs) > 0) paste(range(new_obs$date), collapse = " to ") else "n/a", ".")

  invisible(new_obs)
}
