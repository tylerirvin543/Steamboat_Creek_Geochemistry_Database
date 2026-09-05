# ============================================================
# ingest_noaa_weather.R
#
# Purpose:
# Ingest NOAA weather (precipitation + temperature) station exports
# from data/raw/noaa/ into Weather_Stations / Weather_Observations.
#
# Two distinct NOAA export formats have been observed so far, and
# more are expected (arbitrary filenames, no guaranteed naming
# convention) -- so files are dispatched by DETECTED FORMAT (first
# line of the file), not by filename pattern:
#
#   "search_tool"        -- NCEI Search Tool order export. Normal CSV
#     header: STATION,NAME,LATITUDE,LONGITUDE,ELEVATION,DATE,PRCP,
#     PRCP_ATTRIBUTES,TMAX,TMAX_ATTRIBUTES,TMIN,TMIN_ATTRIBUTES.
#     Values in metric (mm / degrees C); each measurement has a
#     paired *_ATTRIBUTES quality-flag column.
#
#   "ghcn_daily_summary"  -- NOAA "Daily Summaries" web-export. Line 1
#     is a single quoted "NAME, ST US (STATION_ID)" string; line 2 is
#     the real header Date,TAVG (Degrees Fahrenheit),TMAX (...),
#     TMIN (...),PRCP (Inches),SNOW (Inches),SNWD (Inches). Values in
#     °F / inches, unit embedded in the column name, no quality flag.
#
# Adding a third/fourth format later means adding one more
# parse_*() function and a branch in detect_noaa_format() -- the two
# existing parsers are untouched, and both already converge on the
# same Weather_Observations insert path.
#
# Folder: data/raw/noaa/*.csv (any filename)
#
# Behavior:
# - Does NOT overwrite existing data.
# - Whole-file skip once fully processed (Weather_Files_Processed),
#   plus a row-level anti-join on (station_id, date, parameter) as a
#   second safety net.
# ============================================================

library(DBI)
library(dplyr)
library(tidyr)
library(readr)
library(stringr)
library(fs)

#' Detect which NOAA export format a file is, from its first line.
detect_noaa_format <- function(path) {
  first_line <- readLines(path, n = 1, warn = FALSE)
  if (str_detect(first_line, '^"STATION"')) "search_tool" else "ghcn_daily_summary"
}

#' Parse an NCEI Search Tool order export (metric units, per-value
#' quality flags). Returns list(stations = ..., obs = ...).
parse_noaa_search_tool <- function(path) {
  df <- read_csv(path, show_col_types = FALSE)
  names(df) <- toupper(names(df))

  stations <- df |>
    distinct(STATION, NAME, LATITUDE, LONGITUDE, ELEVATION) |>
    transmute(
      station_id = STATION,
      name = NAME,
      latitude = suppressWarnings(as.numeric(LATITUDE)),
      longitude = suppressWarnings(as.numeric(LONGITUDE)),
      elevation_m = suppressWarnings(as.numeric(ELEVATION)),
      source = "NOAA Search Tool (metric)"
    )

  make_param <- function(value_col, attr_col, param_name, unit) {
    if (!(value_col %in% names(df))) return(NULL)
    df |>
      transmute(
        station_id = STATION,
        date = as.character(DATE),
        parameter = param_name,
        value = suppressWarnings(as.numeric(.data[[value_col]])),
        unit = unit,
        quality_flag = if (attr_col %in% names(df)) as.character(.data[[attr_col]]) else NA_character_
      ) |>
      filter(!is.na(value))
  }

  obs <- bind_rows(
    make_param("PRCP", "PRCP_ATTRIBUTES", "PRCP", "mm"),
    make_param("TMAX", "TMAX_ATTRIBUTES", "TMAX", "degC"),
    make_param("TMIN", "TMIN_ATTRIBUTES", "TMIN", "degC")
  )

  list(stations = stations, obs = obs)
}

#' Parse a NOAA "Daily Summaries" web export (°F/inches, station
#' identity in a quoted header line rather than a column).
parse_noaa_ghcn_daily_summary <- function(path) {
  header_line <- readLines(path, n = 1, warn = FALSE)
  m <- str_match(header_line, '^"?(.*)\\(([A-Za-z0-9]+)\\)"?\\s*$')
  station_name <- str_trim(str_remove(m[1, 2], ",\\s*$"))
  station_id <- m[1, 3]

  df <- read_csv(path, skip = 1, show_col_types = FALSE)

  long <- df |>
    pivot_longer(-Date, names_to = "raw_col", values_to = "value") |>
    mutate(
      parameter = str_extract(raw_col, "^[A-Za-z]+"),
      unit = case_when(
        str_detect(raw_col, "Fahrenheit") ~ "degF",
        str_detect(raw_col, "Inches") ~ "in",
        TRUE ~ NA_character_
      ),
      value = suppressWarnings(as.numeric(value))
    ) |>
    filter(!is.na(value)) |>
    transmute(
      station_id = station_id,
      date = as.character(Date),
      parameter = toupper(parameter),
      value,
      unit,
      quality_flag = NA_character_
    )

  stations <- tibble::tibble(
    station_id = station_id,
    name = station_name,
    latitude = NA_real_,
    longitude = NA_real_,
    elevation_m = NA_real_,
    source = "NOAA Daily Summaries (web export)"
  )

  list(stations = stations, obs = long)
}

ingest_noaa_weather <- function(con, base_dir = "data/raw/noaa") {

  message("---- Starting NOAA weather ingest ----")

  if (!dir_exists(base_dir)) {
    message("[NOAA weather] Directory not found — skipping.")
    return(invisible(NULL))
  }

  csv_files <- dir_ls(base_dir, regexp = "\\.csv$", type = "file")

  if (length(csv_files) == 0) {
    message("[NOAA weather] No CSV files found — skipping.")
    return(invisible(NULL))
  }

  processed_files <- dbGetQuery(con, "SELECT file_name FROM Weather_Files_Processed")$file_name

  total_inserted <- 0L

  for (f in csv_files) {

    if (basename(f) %in% processed_files) {
      message("[NOAA weather] Skipping already processed file: ", basename(f))
      next
    }

    fmt <- detect_noaa_format(f)
    message("\n[NOAA weather] Processing: ", basename(f), " (format: ", fmt, ")")

    parsed <- switch(
      fmt,
      search_tool = parse_noaa_search_tool(f),
      ghcn_daily_summary = parse_noaa_ghcn_daily_summary(f),
      { message("  → Unrecognized format — skipping"); NULL }
    )

    if (is.null(parsed) || nrow(parsed$obs) == 0) {
      message("  → No usable rows — skipping")
      next
    }

    # ---- Stations: insert only truly new station_ids ----
    existing_stations <- dbGetQuery(con, "SELECT station_id FROM Weather_Stations")
    new_stations <- parsed$stations |> anti_join(existing_stations, by = "station_id")
    if (nrow(new_stations) > 0) {
      dbAppendTable(con, "Weather_Stations", new_stations)
      message("  → Registered ", nrow(new_stations), " new weather station(s): ",
              paste(new_stations$station_id, collapse = ", "))
    }

    # ---- Observations: dedupe on (station_id, date, parameter) ----
    obs <- parsed$obs |>
      mutate(source_file = basename(f)) |>
      distinct(station_id, date, parameter, .keep_all = TRUE)

    existing_obs <- dbGetQuery(con, "SELECT station_id, date, parameter FROM Weather_Observations")
    pre_filter <- nrow(obs)
    obs <- obs |> anti_join(existing_obs, by = c("station_id", "date", "parameter"))

    message("  → New rows after deduplication: ", nrow(obs),
            " (removed ", pre_filter - nrow(obs), " already-ingested)")

    if (nrow(obs) > 0) {
      dbAppendTable(con, "Weather_Observations", obs)
    }

    dbAppendTable(
      con, "Weather_Files_Processed",
      data.frame(
        file_name = basename(f), format = fmt,
        processed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC")
      )
    )

    total_inserted <- total_inserted + nrow(obs)
  }

  dbAppendTable(
    con,
    "Ingest_Run_Log",
    data.frame(
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
      data_source = "NOAA_weather",
      script_name = "ingest_noaa_weather.R",
      samples_inserted = 0,
      measurements_inserted = total_inserted,
      notes = paste("NOAA weather ingest total rows:", total_inserted),
      stringsAsFactors = FALSE
    )
  )

  message("\n✅ NOAA weather ingest complete")
  message("Total rows inserted: ", total_inserted)
  invisible(total_inserted)
}
