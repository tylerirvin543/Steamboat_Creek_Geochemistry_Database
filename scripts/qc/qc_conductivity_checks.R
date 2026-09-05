# ------------------------------------------------------------
# qc_conductivity_checks.R
#
# Purpose:
# Non-destructive QC checks specific to the stream conductivity
# loggers, appended to the shared QC_Issues table (does not drop
# or reset it — call this AFTER run_qc_checks(con) in the pipeline).
#
# Checks performed:
#   1. Timestamp gaps (missed logging intervals)
#   2. Duplicate / out-of-order timestamps
#   3. Spike / outlier detection (rolling-median + MAD, i.e. a
#      Hampel-style filter), tuned against concretely observed
#      excursions in the raw HOBO exports
#   4. Cross-reference spikes against Sampling_Events dates to
#      distinguish likely field-visit sensor disturbance from
#      unexplained excursions
#   5. Range/plausibility checks on EC and temperature
#   6. Logger deployment-event integrity (missing start/stop markers)
#
# Side effects:
#   - Appends rows to QC_Issues
#   - Writes qc_flag back onto Conductivity_Observations for rows
#     identified as spikes / disturbance, so downstream analysis can
#     filter them out
#   - Writes qc_reports/conductivity_gaps.csv and
#     qc_reports/conductivity_spikes.csv
# ------------------------------------------------------------

run_conductivity_qc_checks <- function(con,
                                        expected_interval_min = 5,
                                        gap_multiplier = 3,
                                        spike_window = 7,
                                        spike_k = 4,
                                        field_visit_window_days = 1) {

  library(DBI)
  library(dplyr)

  message("---- Running conductivity QC checks ----")

  qc_run_time <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  if (!dbExistsTable(con, "Conductivity_Observations")) {
    message("Conductivity_Observations not found — skipping conductivity QC.")
    return(invisible(NULL))
  }

  obs <- dbGetQuery(con, "
    SELECT observation_id, logger_id, timestamp, ec_raw, temperature_c, sc_25c, logger_event
    FROM Conductivity_Observations
  ") |>
    mutate(timestamp = as.POSIXct(timestamp, tz = "UTC"))

  if (nrow(obs) == 0) {
    message("No conductivity observations yet — skipping conductivity QC.")
    return(invisible(NULL))
  }

  # -----------------------------
  # Local logging helper (mirrors log_qc_issue() in qc_data_integrity_checks.R)
  # -----------------------------
  log_qc_issue <- function(df, table_name, issue_type, severity, message_text) {
    n_rows <- nrow(df)
    if (n_rows == 0) return(invisible(NULL))

    created_at <- if ("timestamp" %in% names(df)) {
      format(df$timestamp, "%Y-%m-%d %H:%M:%S")
    } else {
      rep(qc_run_time, n_rows)
    }

    record_id <- if ("observation_id" %in% names(df)) {
      as.character(df$observation_id)
    } else if ("logger_id" %in% names(df)) {
      as.character(df$logger_id)
    } else {
      as.character(seq_len(n_rows))
    }

    location_id <- if ("location_id" %in% names(df)) df$location_id else rep(NA_integer_, n_rows)

    out <- data.frame(
      table_name  = table_name,
      qc_source   = "qc_conductivity_checks",
      record_id   = record_id,
      location_id = location_id,
      issue_type  = issue_type,
      severity    = severity,
      message     = message_text,
      created_at  = ifelse(is.na(created_at), qc_run_time, created_at),
      qc_run_time = qc_run_time,
      stringsAsFactors = FALSE
    )

    dbWriteTable(con, "QC_Issues", out, append = TRUE)
  }

  write_qc <- function(df, path) {
    if (nrow(df) > 0) write.csv(df, path, row.names = FALSE)
  }

  # ==================================================
  # 1 & 2. TIMESTAMP GAPS + ORDERING
  # ==================================================

  gap_flags <- obs |>
    arrange(logger_id, timestamp) |>
    group_by(logger_id) |>
    mutate(
      prev_time = lag(timestamp),
      gap_min = as.numeric(difftime(timestamp, prev_time, units = "mins"))
    ) |>
    filter(!is.na(gap_min)) |>
    ungroup()

  dup_flags <- gap_flags |>
    filter(gap_min <= 0)

  log_qc_issue(
    dup_flags,
    "Conductivity_Observations",
    "duplicate_or_out_of_order_timestamp",
    "ERROR",
    "Non-increasing timestamp within a single logger's record"
  )

  large_gaps <- gap_flags |>
    filter(gap_min > gap_multiplier * expected_interval_min)

  log_qc_issue(
    large_gaps,
    "Conductivity_Observations",
    "time_gap",
    "WARN",
    paste0("Gap exceeds ", gap_multiplier, "x expected ", expected_interval_min, "-min interval")
  )

  write_qc(
    large_gaps |> select(logger_id, timestamp, prev_time, gap_min),
    "qc_reports/conductivity_gaps.csv"
  )

  # ==================================================
  # 3. SPIKE / OUTLIER DETECTION (rolling median + MAD)
  # ==================================================

  hampel_flag <- function(x, window = spike_window, k = spike_k) {
    n <- length(x)
    flagged <- logical(n)
    half <- window %/% 2
    for (i in seq_len(n)) {
      lo <- max(1, i - half)
      hi <- min(n, i + half)
      window_vals <- x[lo:hi]
      med <- median(window_vals, na.rm = TRUE)
      mad_val <- mad(window_vals, constant = 1.4826, na.rm = TRUE)
      if (is.na(mad_val) || mad_val == 0) next
      if (!is.na(x[i]) && abs(x[i] - med) > k * mad_val) {
        flagged[i] <- TRUE
      }
    }
    flagged
  }

  spike_flags <- obs |>
    arrange(logger_id, timestamp) |>
    group_by(logger_id) |>
    mutate(is_spike = hampel_flag(ec_raw)) |>
    ungroup() |>
    filter(is_spike)

  # ---- Cross-reference against known field visits ----
  # Sampling_Events.date is stored as text but may be either an ISO date
  # string or an Excel serial day count (observed in this database for
  # older/historical events) — handle both.
  parse_event_date <- function(x) {
    numeric_x <- suppressWarnings(as.numeric(x))
    is_serial <- !is.na(numeric_x) & !grepl("-", x, fixed = TRUE)
    out <- as.Date(rep(NA_character_, length(x)))
    out[is_serial] <- as.Date(numeric_x[is_serial], origin = "1899-12-30")
    out[!is_serial] <- suppressWarnings(as.Date(x[!is_serial]))
    out
  }

  events <- dbGetQuery(con, "SELECT date FROM Sampling_Events") |>
    mutate(date = parse_event_date(date)) |>
    filter(!is.na(date))

  spike_flags <- spike_flags |>
    mutate(
      obs_date = as.Date(timestamp),
      near_field_visit = if (nrow(events) == 0) {
        FALSE
      } else {
        vapply(obs_date, function(d) {
          any(abs(as.numeric(d - events$date)) <= field_visit_window_days)
        }, logical(1))
      },
      qc_flag = ifelse(near_field_visit, "field_visit_disturbance", "spike")
    )

  log_qc_issue(
    spike_flags |> filter(qc_flag == "field_visit_disturbance"),
    "Conductivity_Observations",
    "field_visit_disturbance",
    "INFO",
    paste0("EC excursion coincides with a Sampling_Events date (+/-", field_visit_window_days, " day)")
  )

  log_qc_issue(
    spike_flags |> filter(qc_flag == "spike"),
    "Conductivity_Observations",
    "unexplained_spike",
    "WARN",
    paste0("EC excursion > ", spike_k, "x MAD from local rolling median, no nearby field visit")
  )

  write_qc(
    spike_flags |> select(logger_id, timestamp, ec_raw, qc_flag),
    "qc_reports/conductivity_spikes.csv"
  )

  # Persist qc_flag back onto the observations for downstream filtering
  if (nrow(spike_flags) > 0) {
    for (i in seq_len(nrow(spike_flags))) {
      dbExecute(con, "
        UPDATE Conductivity_Observations
        SET qc_flag = ?
        WHERE logger_id = ? AND timestamp = ?
      ", params = list(
        spike_flags$qc_flag[i],
        spike_flags$logger_id[i],
        format(spike_flags$timestamp[i], "%Y-%m-%d %H:%M:%S")
      ))
    }
  }

  # ==================================================
  # 5. RANGE / PLAUSIBILITY CHECKS
  # ==================================================
  # Bounds are generous for a spring-fed creek that receives
  # geothermal outflow; tighten once a longer record establishes
  # site-specific norms.

  qc_impossible <- dbGetQuery(con, "
    SELECT * FROM Conductivity_Observations
    WHERE ec_raw < 0 OR ec_raw > 3000
       OR temperature_c < -5 OR temperature_c > 40
  ")
  log_qc_issue(
    qc_impossible,
    "Conductivity_Observations",
    "impossible_value",
    "ERROR",
    "EC or temperature outside plausible range for Steamboat Creek"
  )

  # ==================================================
  # 6. LOGGER DEPLOYMENT-EVENT INTEGRITY
  # ==================================================

  loggers <- dbGetQuery(con, "SELECT logger_id, serial_number, status FROM Conductivity_Loggers")

  missing_start <- obs |>
    filter(!grepl("Logged", logger_event, fixed = TRUE)) |>
    group_by(logger_id) |>
    slice_min(timestamp, n = 1) |>
    ungroup()

  has_start_marker <- obs |>
    filter(grepl("Logged", logger_event, fixed = TRUE)) |>
    distinct(logger_id) |>
    pull(logger_id)

  loggers_missing_start <- loggers |>
    filter(!(logger_id %in% has_start_marker))

  log_qc_issue(
    loggers_missing_start,
    "Conductivity_Loggers",
    "missing_start_marker",
    "WARN",
    "No 'Logged' start-of-deployment marker found in observations"
  )

  closed_loggers <- loggers |> filter(status %in% c("retrieved", "destroyed"))
  has_stop_marker <- obs |>
    filter(grepl("Stopped|End Of File", logger_event)) |>
    distinct(logger_id) |>
    pull(logger_id)

  loggers_missing_stop <- closed_loggers |>
    filter(!(logger_id %in% has_stop_marker))

  log_qc_issue(
    loggers_missing_stop,
    "Conductivity_Loggers",
    "missing_stop_marker",
    "WARN",
    "Logger marked retrieved/destroyed but no 'Stopped'/'End Of File' marker found"
  )

  # ==================================================
  # SUMMARY
  # ==================================================

  message(
    "Conductivity QC: ", nrow(large_gaps), " gap(s), ",
    nrow(spike_flags |> filter(qc_flag == "spike")), " unexplained spike(s), ",
    nrow(spike_flags |> filter(qc_flag == "field_visit_disturbance")), " field-visit disturbance flag(s), ",
    nrow(qc_impossible), " impossible value(s)."
  )

  message("Conductivity QC checks complete.")
}
