# ------------------------------------------------------------
# 02_specific_conductance.R
#
# Purpose:
# Recalibrate the EC -> specific-conductance (25 C) temperature
# compensation coefficient used at ingest time
# (scripts/ingest/helpers/compute_specific_conductance.R), using any
# co-located field conductivity + temperature checks that exist in
# Field_Measurements. Falls back to the USGS default (0.0191) with a
# clear message when no calibration pairs exist yet.
#
# This does NOT rewrite Conductivity_Observations.sc_25c automatically
# — it reports a recommended coefficient so you can decide whether to
# adopt it (and re-run ingest_conductivity.R after updating the
# default in compute_specific_conductance.R) or keep the USGS default.
# ------------------------------------------------------------

library(DBI)
library(dplyr)

source("scripts/ingest/helpers/compute_specific_conductance.R")

#' Pull field conductivity checks paired with logger EC/temperature
#'
#' Looks for Field_Measurements rows with parameter %in% c('conductivity',
#' 'specific_conductance') collected at/near a Conductivity_Loggers
#' location, and joins each to the nearest-in-time Conductivity_Observations
#' row (within `tolerance_min` minutes) for the same logger.
get_calibration_pairs <- function(con, tolerance_min = 15) {

  source("scripts/ingest/helpers/parse_datetime.R")

  field <- dbGetQuery(con, "
    SELECT fm.sample_id, s.location_id, s.collection_time, fm.value AS field_ec, fm.parameter
    FROM Field_Measurements fm
    JOIN Samples s ON fm.sample_id = s.sample_id
    WHERE fm.parameter IN ('conductivity', 'specific_conductance')
  ")

  if (nrow(field) == 0) return(field)

  loggers <- dbGetQuery(con, "SELECT logger_id, location_id FROM Conductivity_Loggers")

  field <- field |> inner_join(loggers, by = "location_id")

  if (nrow(field) == 0) return(field)

  obs <- dbGetQuery(con, "
    SELECT logger_id, timestamp, ec_raw, temperature_c FROM Conductivity_Observations
  ") |>
    mutate(timestamp = as.POSIXct(timestamp, tz = "UTC"))

  field$collection_time <- parse_datetime_safe(field$collection_time)

  # Nearest-in-time join per row (small data volume expected; simple loop is fine)
  out <- vector("list", nrow(field))
  for (i in seq_len(nrow(field))) {
    cand <- obs |> filter(logger_id == field$logger_id[i])
    if (nrow(cand) == 0) next
    diffs <- abs(as.numeric(difftime(cand$timestamp, field$collection_time[i], units = "mins")))
    j <- which.min(diffs)
    if (diffs[j] <= tolerance_min) {
      out[[i]] <- cbind(field[i, c("sample_id", "field_ec", "collection_time")], cand[j, ])
    }
  }

  bind_rows(out)
}

#' Recalibrate the compensation coefficient via non-linear least squares
recalibrate_sc_coefficient <- function(con, tolerance_min = 15, theta = 25) {

  pairs <- get_calibration_pairs(con, tolerance_min)

  if (nrow(pairs) < 5) {
    message(
      "Only ", nrow(pairs), " field-vs-logger calibration pair(s) found ",
      "(need >= 5) — keeping USGS default coefficient (0.0191). ",
      "Add paired field conductivity checks to Field_Measurements to enable recalibration."
    )
    return(list(coefficient = 0.0191, n_pairs = nrow(pairs), model = NULL))
  }

  fit <- tryCatch(
    nls(
      field_ec ~ ec_raw / (1 + b * (temperature_c - theta)),
      data = pairs,
      start = list(b = 0.0191)
    ),
    error = function(e) {
      message("nls() failed to converge (", e$message, ") — keeping default coefficient.")
      NULL
    }
  )

  if (is.null(fit)) {
    return(list(coefficient = 0.0191, n_pairs = nrow(pairs), model = NULL))
  }

  coef_est <- coef(fit)[["b"]]
  message("Recalibrated compensation coefficient: ", round(coef_est, 4),
          " (default 0.0191), from ", nrow(pairs), " pairs.")

  list(coefficient = coef_est, n_pairs = nrow(pairs), model = fit)
}
