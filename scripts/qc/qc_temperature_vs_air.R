# ============================================================
# qc_temperature_vs_air.R
#
# Purpose:
# Cross-checks every Temperature_Loggers time series against the new
# SBRR air-temperature record (USGS-10349300, parameter code 00020,
# ingested 2026-09-26 via ingest_usgs(con, base_dir =
# "data/raw/usgs/air_temperature_data")) as a QC signal, NOT a literal
# temperature calibration/offset correction -- there is no physical
# basis for "correcting" a spring/well/creek temperature reading using
# air temperature (they are different, legitimately different
# quantities). What air temperature CAN do is flag periods where a
# logger is behaving suspiciously air-like -- e.g. exposed above the
# water surface, in a dry channel, or otherwise not measuring what it's
# supposed to -- which is a real, useful QC application.
#
# Method: for each logger, resample both series to daily min/max/mean,
# then compute:
#   - diurnal_range_ratio = logger's daily (max-min) / air's daily
#     (max-min), on days where both exist. Real submerged water bodies
#     (springs, wells, most of a creek) damp diurnal swings far more
#     than open air; a ratio approaching or exceeding 1 is a real red
#     flag, not a subtle one.
#   - corr = same-day correlation between logger and air daily mean,
#     across the full overlap period -- a secondary, softer signal
#     (real water temperature legitimately correlates somewhat with
#     air temperature seasonally, so this is not on its own
#     disqualifying).
#
# Output: data/derived/qc/temperature_vs_air_qc.csv (one row per
# logger-day in the overlap window, with both metrics and a flag
# column), plus a summary printed per logger. Read-only / reporting
# only -- does not modify Temperature_Observations.
# ============================================================

library(DBI)
library(dplyr)

compare_temperature_to_air <- function(con,
    air_station_id = "USGS-10349300",
    ratio_flag_threshold = 0.6,
    out_csv = "data/derived/qc/temperature_vs_air_qc.csv") {

  message("---- Temperature logger vs. air temperature QC ----")

  air <- dbGetQuery(con, "
    SELECT datetime, value FROM USGS_Timeseries
    WHERE station_id = ? AND parameter_code = '00020'
  ", params = list(air_station_id))

  if (nrow(air) == 0) {
    message("[qc_temp_vs_air] No air-temperature data found for station ", air_station_id, " -- skipping.")
    return(invisible(NULL))
  }

  air$date <- as.Date(air$datetime)
  air_daily <- air %>%
    group_by(date) %>%
    summarise(air_min = min(value, na.rm = TRUE),
              air_max = max(value, na.rm = TRUE),
              air_mean = mean(value, na.rm = TRUE),
              .groups = "drop") %>%
    mutate(air_range = air_max - air_min)

  loggers <- dbGetQuery(con, "SELECT logger_id, logger_name FROM Temperature_Loggers")

  results <- list()
  for (i in seq_len(nrow(loggers))) {
    lg <- loggers[i, ]
    obs <- dbGetQuery(con, "
      SELECT timestamp, temperature FROM Temperature_Observations WHERE logger_id = ?
    ", params = list(lg$logger_id))
    if (nrow(obs) == 0) next

    # timestamps stored as Unix-epoch-seconds text, project-wide convention
    obs$ts_num <- suppressWarnings(as.numeric(obs$timestamp))
    obs <- obs[!is.na(obs$ts_num), ]
    if (nrow(obs) == 0) next
    obs$date <- as.Date(as.POSIXct(obs$ts_num, origin = "1970-01-01", tz = "UTC"))

    logger_daily <- obs %>%
      group_by(date) %>%
      summarise(logger_min = min(temperature, na.rm = TRUE),
                logger_max = max(temperature, na.rm = TRUE),
                logger_mean = mean(temperature, na.rm = TRUE),
                .groups = "drop") %>%
      mutate(logger_range = logger_max - logger_min)

    merged <- inner_join(logger_daily, air_daily, by = "date")
    if (nrow(merged) < 3) next

    merged$diurnal_range_ratio <- merged$logger_range / merged$air_range
    merged$logger_id <- lg$logger_id
    merged$logger_name <- lg$logger_name
    merged$flag_air_like <- merged$diurnal_range_ratio >= ratio_flag_threshold & merged$air_range > 0.5

    corr <- suppressWarnings(cor(merged$logger_mean, merged$air_mean, use = "complete.obs"))
    pct_flagged <- round(100 * mean(merged$flag_air_like, na.rm = TRUE), 1)

    message("  Logger ", lg$logger_name, " (id=", lg$logger_id, "): ",
            nrow(merged), " overlapping days, corr with air = ",
            round(corr, 2), ", ", pct_flagged, "% of days flagged as air-like (ratio >= ",
            ratio_flag_threshold, ")")

    results[[lg$logger_id]] <- merged
  }

  if (length(results) == 0) {
    message("[qc_temp_vs_air] No logger had overlapping days with the air-temperature record -- skipping output.")
    return(invisible(NULL))
  }

  out <- bind_rows(results)
  fs::dir_create(dirname(out_csv))
  readr::write_csv(out, out_csv)
  message("[qc_temp_vs_air] Wrote ", nrow(out), " logger-day rows to ", out_csv)

  invisible(out)
}
