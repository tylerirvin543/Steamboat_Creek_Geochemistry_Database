# ============================================================
# ingest_usgs_historic_chemistry.R
#
# Purpose:
# Ingest historic USGS Water Quality Portal (WQP) grab-sample chemistry
# exports -- e.g. the "full physical/chemical" station download at
# data/raw/usgs/fullphyschem_station_download/ -- into the SAME
# USGS_Timeseries / USGS_Stations tables that ingest_usgs.R already
# populates with live discharge (parameter_code '00060'). This is a
# deliberate design choice: WQP rows already carry a USGS parameter
# code (`USGSpcode`) per row, so a historic specific-conductance grab
# sample and a continuous discharge reading are just two different
# parameter_code values for the same station -- storing them in one
# table is what makes a joined SC-vs-discharge view (see
# scripts/analysis/create_analysis_views.R) a one-line join instead of
# a cross-schema join.
#
# Scope (2026-09-05): filters to Result_Characteristic == "Specific
# conductance" (USGSpcode 00095) only, per current request, but keys
# off USGSpcode generically so widening later is a one-line change to
# `target_characteristics` below, not a rewrite.
#
# Folder:
#   data/raw/usgs/fullphyschem_station_download/*.csv
#
# Behavior:
# - Does NOT overwrite existing data.
# - Only inserts new (station_id, datetime, parameter_code) rows --
#   the exact same primary key ingest_usgs.R's discharge rows use, so
#   the two ingests can never collide or double-count.
# ============================================================

library(DBI)
library(dplyr)
library(readr)
library(stringr)
library(fs)

#' Characteristic -> USGS parameter code fallback, used only when a row's
#' own `USGSpcode` column is blank (some historical WQP exports omit it).
#' Extend this map, not the row-filtering logic, to widen scope later.
usgs_characteristic_map <- c(
  "Specific conductance" = "00095"
)

target_characteristics <- names(usgs_characteristic_map)

#' Convert a WQP activity date/time/timezone triple to a UTC POSIXct.
#' WQP exports the zone abbreviation actually in force for that
#' historical date (PDT vs PST), so a fixed offset per abbreviation is
#' correct and avoids relying on the OS timezone database for dates
#' that may predate some tzdata entries.
parse_wqp_datetime_utc <- function(date, time, tz_abbrev) {
  offset_hours <- case_when(
    tz_abbrev == "PDT" ~ 7,
    tz_abbrev == "PST" ~ 8,
    TRUE ~ NA_real_
  )
  local_dt <- suppressWarnings(as.POSIXct(paste(date, time), format = "%Y-%m-%d %H:%M:%S", tz = "UTC"))
  local_dt + offset_hours * 3600
}

ingest_usgs_historic_chemistry <- function(con) {

  message("---- Starting USGS historic chemistry ingest ----")

  base_dir <- "data/raw/usgs/fullphyschem_station_download"

  if (!dir_exists(base_dir)) {
    message("[USGS historic chem] Directory not found — skipping.")
    return(invisible(NULL))
  }

  csv_files <- dir_ls(base_dir, regexp = "\\.csv$", type = "file")

  if (length(csv_files) == 0) {
    message("[USGS historic chem] No CSV files found — skipping.")
    return(invisible(NULL))
  }

  total_inserted <- 0L

  for (f in csv_files) {

    message("\n[USGS historic chem] Processing: ", basename(f))

    raw <- read_csv(f, show_col_types = FALSE, guess_max = 5000)

    if (!("Result_Characteristic" %in% names(raw))) {
      message("  → Not a WQP physchem export (missing Result_Characteristic) — skipping file")
      next
    }

    df <- raw |>
      filter(Result_Characteristic %in% target_characteristics) |>
      transmute(
        station_id     = Location_Identifier,
        latitude       = suppressWarnings(as.numeric(Location_Latitude)),
        longitude      = suppressWarnings(as.numeric(Location_Longitude)),
        parameter_code = if_else(
          !is.na(USGSpcode) & USGSpcode != "",
          as.character(USGSpcode),
          usgs_characteristic_map[Result_Characteristic]
        ),
        datetime  = parse_wqp_datetime_utc(Activity_StartDate, Activity_StartTime, Activity_StartTimeZone),
        value     = suppressWarnings(as.numeric(Result_Measure)),
        unit      = Result_MeasureUnit,
        status    = Result_MeasureStatusIdentifier,
        last_modified = as.character(LastChangeDate),
        source_file   = basename(f)
      )

    n_before <- nrow(df)
    df <- df |> filter(!is.na(datetime), !is.na(value), !is.na(parameter_code))
    if (n_before - nrow(df) > 0) {
      message("  → Dropped ", n_before - nrow(df), " row(s) with unparseable datetime/value/parameter_code")
    }

    if (nrow(df) == 0) {
      message("  → No usable rows in this file — skipping")
      next
    }

    # ------------------------------------------------------------
    # STATION METADATA (same USGS_Stations table ingest_usgs.R uses)
    # ------------------------------------------------------------
    stations_new <- df |>
      distinct(station_id, latitude, longitude)

    existing_stations <- dbGetQuery(con, "SELECT station_id FROM USGS_Stations")

    stations_new <- stations_new |>
      anti_join(existing_stations, by = "station_id")

    if (nrow(stations_new) > 0) {
      dbAppendTable(con, "USGS_Stations", stations_new)
      message("  → Inserted metadata for ", nrow(stations_new), " station(s)")
    }

    # ------------------------------------------------------------
    # TIMESERIES ROWS (same USGS_Timeseries table, different parameter_code)
    # ------------------------------------------------------------
    df <- df |>
      select(station_id, datetime, parameter_code, value, unit, status, last_modified, source_file) |>
      distinct(station_id, datetime, parameter_code, .keep_all = TRUE)

    existing <- dbGetQuery(con, "SELECT station_id, datetime, parameter_code FROM USGS_Timeseries") |>
      mutate(datetime = as.POSIXct(datetime, tz = "UTC"), parameter_code = as.character(parameter_code))

    pre_filter <- nrow(df)

    df <- df |>
      anti_join(existing, by = c("station_id", "datetime", "parameter_code"))

    message("  → New rows after deduplication: ", nrow(df),
            " (removed ", pre_filter - nrow(df), " already-ingested)")

    if (nrow(df) > 0) {
      df <- df |> mutate(datetime = format(datetime, "%Y-%m-%d %H:%M:%S"))
      dbAppendTable(con, "USGS_Timeseries", df)
    }

    total_inserted <- total_inserted + nrow(df)
  }

  dbAppendTable(
    con,
    "Ingest_Run_Log",
    data.frame(
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
      data_source = "USGS_historic_chemistry",
      script_name = "ingest_usgs_historic_chemistry.R",
      samples_inserted = 0,
      measurements_inserted = total_inserted,
      notes = paste("USGS historic chemistry ingest total rows:", total_inserted),
      stringsAsFactors = FALSE
    )
  )

  message("\n✅ USGS historic chemistry ingest complete")
  message("Total rows inserted: ", total_inserted)
  invisible(total_inserted)
}
