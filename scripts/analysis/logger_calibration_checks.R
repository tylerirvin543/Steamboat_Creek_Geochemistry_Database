# ============================================================
# logger_calibration_checks.R
#
# Purpose: automatically detect real field calibration/reference
# checks for the conductivity and temperature loggers -- a co-located
# reference reading (e.g. a handheld/lab thermometer or conductivity
# measurement) taken during an ordinary field visit, at a site that
# also hosts one of this project's own loggers, close in time to a
# real logger observation. This requires NO new manual data-entry
# form: it is derived entirely from data this project already
# collects via the standard Field_Measurements pipeline
# (ingest_field.R).
#
# Confirmed real example driving this design (2026-09-26): a 2026
# field visit to SBRR recorded a `temperature` Field_Measurements row
# via instrument "FLUKE Thermometer" (a real reference thermometer,
# not a logger) and a `conductivity` row via instrument "lab" -- both
# co-located with SBRR's real conductivity logger (and, per prior
# session notes, a temperature logger too). This function is what
# turns that into a real, queryable Logger_Calibration_Checks row.
#
# Deliberately conservative: only matches a Field_Measurements
# reading to a logger observation within a documented time tolerance
# (default 4 hours); anything further apart is skipped, not force-
# matched. Idempotent (skips a check that already exists for the same
# logger + reference sample + parameter).
# ============================================================

#' Parse a timestamp that might be epoch-seconds text, an ISO-ish
#' string, or "MM/DD/YYYY H:MM" / "MM/DD/YYYY HH:MM" (the format
#' actually seen in Samples.collection_time) -- tries each in turn,
#' returns NA (not an error) if none match.
.calchk_parse_datetime <- function(x) {
  x <- trimws(as.character(x))
  if (is.na(x) || x == "") return(as.POSIXct(NA))

  if (grepl("^-?[0-9]+(\\.[0-9]+)?$", x)) {
    return(as.POSIXct(as.numeric(x), origin = "1970-01-01", tz = "UTC"))
  }
  # MM/DD/YYYY H:MM or MM/DD/YYYY HH:MM
  if (grepl("^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} [0-9]{1,2}:[0-9]{2}$", x)) {
    return(as.POSIXct(strptime(x, format = "%m/%d/%Y %H:%M", tz = "UTC")))
  }
  suppressWarnings(as.POSIXct(x, tz = "UTC"))
}

#' Scan Field_Measurements for temperature/conductivity readings taken
#' at a location that also hosts a Temperature_Logger/
#' Conductivity_Logger, and record each as a real calibration check
#' against the nearest-in-time real logger observation.
build_logger_calibration_checks <- function(con, max_time_offset_hours = 4) {
  message("---- Detecting real logger calibration/reference checks ----")

  # Temperature: Field_Measurements.parameter %in% c('temperature') at a
  # location with an active Temperature_Loggers row.
  temp_candidates <- DBI::dbGetQuery(con, "
    SELECT fm.sample_id, fm.value AS reference_value, fm.units AS reference_units,
           fm.instrument AS reference_instrument, s.collection_time,
           s.location_id, tl.logger_id
    FROM Field_Measurements fm
    JOIN Samples s ON fm.sample_id = s.sample_id
    JOIN Temperature_Loggers tl ON tl.location_id = s.location_id
    WHERE fm.parameter IN ('temperature', 'temperature_field')
      AND fm.value IS NOT NULL
  ")

  cond_candidates <- DBI::dbGetQuery(con, "
    SELECT fm.sample_id, fm.value AS reference_value, fm.units AS reference_units,
           fm.instrument AS reference_instrument, s.collection_time,
           s.location_id, cl.logger_id
    FROM Field_Measurements fm
    JOIN Samples s ON fm.sample_id = s.sample_id
    JOIN Conductivity_Loggers cl ON cl.location_id = s.location_id
    WHERE fm.parameter IN ('conductivity', 'conductivity_field')
      AND fm.value IS NOT NULL
  ")

  n_new <- 0L
  n_skipped <- 0L
  n_too_far <- 0L

  process <- function(candidates, logger_type, obs_table, obs_value_col, obs_units) {
    n_new_l <- 0L; n_skipped_l <- 0L; n_too_far_l <- 0L
    for (i in seq_len(nrow(candidates))) {
      r <- candidates[i, ]
      ref_time <- .calchk_parse_datetime(r$collection_time)
      if (is.na(ref_time)) next

      already <- DBI::dbGetQuery(con, "
        SELECT check_id FROM Logger_Calibration_Checks
        WHERE logger_type = ? AND logger_id = ? AND reference_source_sample_id = ?
      ", params = list(logger_type, r$logger_id, r$sample_id))
      if (nrow(already) > 0) { n_skipped_l <- n_skipped_l + 1L; next }

      obs <- DBI::dbGetQuery(con, sprintf("
        SELECT timestamp, %s AS obs_value FROM %s WHERE logger_id = ?
      ", obs_value_col, obs_table), params = list(r$logger_id))
      if (nrow(obs) == 0) next
      obs_time <- vapply(obs$timestamp, function(t) as.numeric(.calchk_parse_datetime(t)), numeric(1))
      diffs <- abs(obs_time - as.numeric(ref_time))
      best <- which.min(diffs)
      offset_sec <- diffs[best]

      if (offset_sec > max_time_offset_hours * 3600) { n_too_far_l <- n_too_far_l + 1L; next }

      # Convert reference value to the same units as the logger observation
      # where the units obviously differ (temperature F->C is the only
      # real case seen so far; conductivity units already match).
      ref_val <- r$reference_value
      ref_units <- r$reference_units
      if (logger_type == "temperature" && !is.na(ref_units) &&
          grepl("^f$|fahrenheit", tolower(ref_units))) {
        ref_val <- (ref_val - 32) * 5 / 9
        ref_units <- "deg C"
      }

      DBI::dbExecute(con, "
        INSERT INTO Logger_Calibration_Checks
          (logger_type, logger_id, check_timestamp, reference_source_sample_id,
           reference_instrument, reference_parameter, reference_value, reference_units,
           matched_observation_timestamp, matched_observation_value, matched_observation_units,
           time_offset_seconds, difference, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ", params = list(
        logger_type, r$logger_id, format(ref_time, "%Y-%m-%d %H:%M:%S"), r$sample_id,
        r$reference_instrument, ifelse(logger_type == "temperature", "temperature", "conductivity"),
        ref_val, ref_units,
        format(as.POSIXct(obs_time[best], origin = "1970-01-01", tz = "UTC"), "%Y-%m-%d %H:%M:%S"),
        obs$obs_value[best], obs_units, offset_sec, ref_val - obs$obs_value[best],
        "Auto-detected from a real Field_Measurements reading co-located with this logger (see build_logger_calibration_checks())."
      ))
      n_new_l <- n_new_l + 1L
    }
    c(new = n_new_l, skipped = n_skipped_l, too_far = n_too_far_l)
  }

  r1 <- process(temp_candidates, "temperature", "Temperature_Observations", "temperature", "deg C")
  r2 <- process(cond_candidates, "conductivity", "Conductivity_Observations", "ec_raw", "uS/cm")

  message("  -> Temperature checks: ", r1["new"], " new, ", r1["skipped"], " already present, ", r1["too_far"], " too far in time to match.")
  message("  -> Conductivity checks: ", r2["new"], " new, ", r2["skipped"], " already present, ", r2["too_far"], " too far in time to match.")
  invisible(list(temperature = r1, conductivity = r2))
}
