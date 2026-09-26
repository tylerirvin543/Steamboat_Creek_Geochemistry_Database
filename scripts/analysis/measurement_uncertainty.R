# ============================================================
# measurement_uncertainty.R
#
# Purpose: combine (1) a logger's manufacturer-published accuracy
# spec (Logger_Specifications) with (2) any real, empirical field
# calibration-check bias for that specific logger
# (Logger_Calibration_Checks) into one documented combined
# measurement-uncertainty estimate.
#
# Method (deliberately simple and stated explicitly, not hidden in
# code): when both a manufacturer spec and at least one real
# calibration check exist for a logger/parameter, the combined
# uncertainty is the root-sum-square (RSS) of the manufacturer's own
# accuracy value and the empirical |difference| from the calibration
# check(s) (mean absolute difference if more than one exists). RSS
# assumes the two error sources are independent, which is a standard,
# reasonable but not certain assumption -- stated here rather than
# silently applied. When only a manufacturer spec exists (no field
# check yet for that logger), the combined uncertainty IS the
# manufacturer spec, unmodified -- reported as such, not inflated.
# ============================================================

#' Resolve a logger's own manufacturer/model from Temperature_Loggers
#' or Conductivity_Loggers, then look up its Logger_Specifications row.
.mu_get_spec <- function(con, logger_id, logger_type) {
  tbl <- if (logger_type == "temperature") "Temperature_Loggers" else "Conductivity_Loggers"
  info <- DBI::dbGetQuery(con, sprintf("SELECT manufacturer, model FROM %s WHERE logger_id = ?", tbl),
                           params = list(logger_id))
  if (nrow(info) == 0) return(NULL)
  # Exact manufacturer+model+parameter match first (real, on-file
  # identity) -- only fall back to "any spec for this parameter" if no
  # exact match exists, and flag that fallback explicitly rather than
  # silently returning an unrelated logger's spec (a real bug found
  # 2026-09-26: an earlier version of this match fell back to an
  # arbitrary row whenever the model string didn't match exactly,
  # which meant every temperature logger silently got the HOBO
  # conductivity-logger's temperature spec regardless of its own real
  # manufacturer/model).
  spec <- DBI::dbGetQuery(con, "
    SELECT * FROM Logger_Specifications WHERE parameter = ? AND manufacturer = ? AND model = ?
  ", params = list(logger_type, info$manufacturer[1], info$model[1]))
  if (nrow(spec) > 0) return(spec[1, ])

  message("[.mu_get_spec] No exact Logger_Specifications match for ", info$manufacturer[1], " ",
          info$model[1], " (", logger_type, ") -- no manufacturer spec applied for this logger.")
  NULL
}

#' Manufacturer accuracy at a given reading value (handles the
#' "X% of reading or Y absolute, whichever is greater" spec type).
.mu_manufacturer_accuracy_at <- function(spec, reading_value) {
  if (is.null(spec) || nrow(spec) == 0) return(NA_real_)
  switch(spec$accuracy_type[1],
    "absolute" = spec$accuracy_value[1],
    "percent_of_reading" = abs(reading_value) * spec$accuracy_value[1] / 100,
    "greater_of_percent_or_absolute" = max(abs(reading_value) * spec$accuracy_value[1] / 100, spec$accuracy_value2[1], na.rm = TRUE),
    NA_real_
  )
}

#' Combined uncertainty for one logger at one reading value.
#' Returns a one-row data.frame: manufacturer_uncertainty,
#' empirical_bias, n_checks, combined_uncertainty, method.
get_combined_uncertainty <- function(con, logger_id, logger_type, reading_value = NA_real_) {
  spec <- .mu_get_spec(con, logger_id, logger_type)
  manu_unc <- if (!is.null(spec)) .mu_manufacturer_accuracy_at(spec, reading_value) else NA_real_

  checks <- DBI::dbGetQuery(con, "
    SELECT difference FROM Logger_Calibration_Checks
    WHERE logger_type = ? AND logger_id = ?
  ", params = list(logger_type, logger_id))

  if (nrow(checks) > 0) {
    empirical_bias <- mean(abs(checks$difference), na.rm = TRUE)
    if (!is.na(manu_unc)) {
      combined <- sqrt(manu_unc^2 + empirical_bias^2)
      method <- "root_sum_square(manufacturer_spec, empirical_calibration_check)"
    } else {
      combined <- empirical_bias
      method <- "empirical_calibration_check_only (no manufacturer spec on file)"
    }
  } else {
    empirical_bias <- NA_real_
    combined <- manu_unc
    method <- "manufacturer_spec_only (no field calibration check yet for this logger)"
  }

  data.frame(
    logger_id = logger_id, logger_type = logger_type,
    manufacturer_uncertainty = manu_unc, empirical_bias = empirical_bias,
    n_checks = nrow(checks), combined_uncertainty = combined, method = method
  )
}

#' Worked example: apply get_combined_uncertainty() to every logger
#' that has at least one real calibration check, for direct use in a
#' notebook table/plot.
summarize_logger_uncertainty <- function(con) {
  temp_loggers <- DBI::dbGetQuery(con, "SELECT DISTINCT logger_id FROM Logger_Calibration_Checks WHERE logger_type = 'temperature'")
  cond_loggers <- DBI::dbGetQuery(con, "SELECT DISTINCT logger_id FROM Logger_Calibration_Checks WHERE logger_type = 'conductivity'")

  rows <- list()
  for (lid in temp_loggers$logger_id) {
    latest_val <- DBI::dbGetQuery(con, "SELECT temperature FROM Temperature_Observations WHERE logger_id = ? ORDER BY timestamp DESC LIMIT 1", params = list(lid))
    v <- if (nrow(latest_val) > 0) latest_val$temperature[1] else NA_real_
    rows[[length(rows) + 1]] <- get_combined_uncertainty(con, lid, "temperature", v)
  }
  for (lid in cond_loggers$logger_id) {
    latest_val <- DBI::dbGetQuery(con, "SELECT ec_raw FROM Conductivity_Observations WHERE logger_id = ? ORDER BY timestamp DESC LIMIT 1", params = list(lid))
    v <- if (nrow(latest_val) > 0) latest_val$ec_raw[1] else NA_real_
    rows[[length(rows) + 1]] <- get_combined_uncertainty(con, lid, "conductivity", v)
  }
  if (length(rows) == 0) return(data.frame())
  do.call(rbind, rows)
}
