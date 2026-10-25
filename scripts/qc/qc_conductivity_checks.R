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
#   7. End-of-record / start-of-record ambient-air exposure (logger
#      retrieval/relaunch boundary detector)
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
                                        field_visit_window_days = 1,
                                        ambient_tail_check_n = 20,
                                        ambient_head_check_n = 10,
                                        ambient_baseline_window = 20,
                                        ambient_baseline_gap = 5,
                                        ambient_drop_fraction = 0.85,
                                        ambient_min_baseline_us_cm = 15) {

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
      prev_time = dplyr::lag(timestamp),
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
  # ---- Cross-reference against known field visits ----
  # Sampling_Events.date is stored as text but has been observed in at
  # least three different formats depending on where the event came
  # from: an Excel serial day count (older/historical events), an ISO
  # date string, and "MM/DD/YYYY H:MM" US-style timestamps (added
  # 2026-09-05 by promote_staged_ndep.R, which stores NDEP PRR
  # chemistry's collection_time verbatim). as.Date() on a character
  # vector requires ONE format to work for every element at once, so a
  # vectorized call errors outright the moment the vector mixes
  # formats -- each value is parsed individually instead, trying each
  # known format in turn.
  parse_event_date <- function(x) {
    parse_one <- function(v) {
      if (is.na(v)) return(NA_character_)
      numeric_v <- suppressWarnings(as.numeric(v))
      if (!is.na(numeric_v) && !grepl("-", v, fixed = TRUE) && !grepl("/", v, fixed = TRUE)) {
        return(as.character(as.Date(numeric_v, origin = "1899-12-30")))
      }
      for (fmt in c("%Y-%m-%d", "%m/%d/%Y %H:%M", "%m/%d/%Y")) {
        d <- tryCatch(as.Date(v, format = fmt), error = function(e) NA)
        if (!is.na(d)) return(as.character(d))
      }
      NA_character_
    }
    as.Date(vapply(x, parse_one, character(1)))
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
  # 7. END-OF-RECORD / START-OF-RECORD AMBIENT-AIR EXPOSURE
  # ==================================================
  # HOBO "Full Range" loggers here are shuttle-downloaded by physically
  # uncoupling the logger from its stream mount (or lifting it clear of
  # the water) to connect the shuttle, then relaunching it the same way.
  # Every segment boundary -- a 'Logged' start-of-deployment marker, or a
  # large time gap -- is therefore a real opportunity for the sensor to
  # briefly read ambient air instead of stream water, not a real
  # stream-chemistry change. Confirmed concretely twice now (2026-08-22
  # and 2026-10-10 downloads; 2026-08-22 is also a mid-record relaunch),
  # this generalizes the manual, Sampling_Events-proximity-based check
  # used previously so future downloads get this flagged automatically.
  #
  # Logic per logger, per segment boundary:
  #   - END of a segment: scan the last `ambient_tail_check_n` readings
  #     before the boundary; if any reading drops below
  #     `ambient_drop_fraction` x a baseline computed from the stable
  #     window just before that tail, flag it AND every reading after it
  #     through the segment's end (an air-exposed sensor stays erratic
  #     until it's back in the water, not just the single lowest point).
  #   - START of a segment: the mirror image, using the following stable
  #     window as the baseline and scanning the first
  #     `ambient_head_check_n` readings after the boundary.
  # A candidate baseline below `ambient_min_baseline_us_cm` is skipped
  # (too close to the noise floor for a relative-fraction comparison to
  # mean anything).
  ambient_flag_segment <- function(ec, logger_event,
                                    tail_check_n, head_check_n,
                                    baseline_window, baseline_gap,
                                    drop_fraction, min_baseline,
                                    gap_min, gap_threshold) {
    n <- length(ec)
    flagged <- logical(n)
    if (n < (baseline_window + baseline_gap + 5)) return(flagged)

    logged_idx <- which(!is.na(logger_event) & grepl("Logged", logger_event, fixed = TRUE))
    boundary_after_gap <- which(gap_min > gap_threshold)

    start_idx <- sort(unique(c(1, logged_idx, boundary_after_gap)))
    start_idx <- start_idx[start_idx <= n]
    end_idx   <- sort(unique(c(n, logged_idx - 1, boundary_after_gap - 1)))
    end_idx   <- end_idx[end_idx >= 1]

    for (e in end_idx) {
      tail_lo <- max(1, e - tail_check_n + 1)
      base_hi <- tail_lo - baseline_gap - 1
      base_lo <- base_hi - baseline_window + 1
      if (base_hi < 1 || base_lo < 1) next
      baseline <- median(ec[base_lo:base_hi], na.rm = TRUE)
      if (is.na(baseline) || baseline < min_baseline) next
      window_vals <- ec[tail_lo:e]
      breach <- which(!is.na(window_vals) & window_vals < drop_fraction * baseline)
      if (length(breach) > 0) {
        first_breach <- tail_lo + min(breach) - 1
        flagged[first_breach:e] <- TRUE
      }
    }

    for (s in start_idx) {
      head_hi <- min(n, s + head_check_n - 1)
      base_lo <- head_hi + baseline_gap + 1
      base_hi <- base_lo + baseline_window - 1
      if (base_hi > n || base_lo > n) next
      baseline <- median(ec[base_lo:base_hi], na.rm = TRUE)
      if (is.na(baseline) || baseline < min_baseline) next
      window_vals <- ec[s:head_hi]
      breach <- which(!is.na(window_vals) & window_vals < drop_fraction * baseline)
      if (length(breach) > 0) {
        last_breach <- s + max(breach) - 1
        flagged[s:last_breach] <- TRUE
      }
    }

    flagged
  }

  ambient_flags <- obs |>
    arrange(logger_id, timestamp) |>
    group_by(logger_id) |>
    group_modify(function(df, key) {
      n <- nrow(df)
      gap_min_vec <- c(NA, as.numeric(difftime(df$timestamp[-1], df$timestamp[-n], units = "mins")))
      df$is_ambient <- ambient_flag_segment(
        ec = df$ec_raw, logger_event = df$logger_event,
        tail_check_n = ambient_tail_check_n, head_check_n = ambient_head_check_n,
        baseline_window = ambient_baseline_window, baseline_gap = ambient_baseline_gap,
        drop_fraction = ambient_drop_fraction, min_baseline = ambient_min_baseline_us_cm,
        gap_min = gap_min_vec, gap_threshold = gap_multiplier * expected_interval_min
      )
      df
    }) |>
    ungroup() |>
    filter(is_ambient) |>
    mutate(qc_flag = "field_visit_disturbance")

  log_qc_issue(
    ambient_flags,
    "Conductivity_Observations",
    "ambient_air_exposure",
    "INFO",
    paste0("EC drop below ", round(100 * ambient_drop_fraction), "% of local baseline adjacent to a logger",
           " retrieval/relaunch boundary -- likely an out-of-water reading, not a real stream signal")
  )

  write_qc(
    ambient_flags |> select(logger_id, timestamp, ec_raw, qc_flag),
    "qc_reports/conductivity_ambient_air_exposure.csv"
  )

  if (nrow(ambient_flags) > 0) {
    for (i in seq_len(nrow(ambient_flags))) {
      dbExecute(con, "
        UPDATE Conductivity_Observations
        SET qc_flag = 'field_visit_disturbance'
        WHERE logger_id = ? AND timestamp = ?
      ", params = list(
        ambient_flags$logger_id[i],
        format(ambient_flags$timestamp[i], "%Y-%m-%d %H:%M:%S")
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
    nrow(spike_flags |> filter(qc_flag == "field_visit_disturbance")), " field-visit disturbance flag(s) (Sampling_Events-proximity), ",
    nrow(ambient_flags), " ambient-air-exposure flag(s) (retrieval/relaunch boundary detector), ",
    nrow(qc_impossible), " impossible value(s)."
  )

  message("Conductivity QC checks complete.")
}
