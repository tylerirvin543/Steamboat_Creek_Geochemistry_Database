# ============================================================
# data_availability.R
#
# Purpose:
# Answer "what data do we have, and for what time period?" across every
# major table in the database with a real timestamp/date column, as a
# single tidy table + a horizontal ("sideways") bar / Gantt-style chart.
# Requested 2026-09-05 (session 3, revisited session 11) -- previously
# scoped but never built (see AGENTS.md).
#
# Each table's date column has its own storage quirk (Excel serial
# numbers, Unix epoch seconds, ISO strings, mixed formats within one
# column) discovered and fixed piecemeal in other scripts over the
# course of this project (e.g. qc_conductivity_checks.R's
# parse_event_date() for Sampling_Events.date) -- this script
# consolidates a read-only version of that same date handling so the
# availability table can be computed from any point in the pipeline
# without re-deriving it. Well_Log_Documents.completion_date_raw is
# OCR/handwritten text and is NOT included here -- it's too irregular
# to parse reliably as a MIN/MAX range (see parse_well_log_pdf.R's own
# caveats); only the well logs' *processed_at* (ingestion date) would
# be defensible, and that's a data-pipeline artifact, not a real-world
# observation date, so it's deliberately left out of this chart.
#
# Usage:
#   source("scripts/analysis/data_availability.R")
#   avail <- compute_data_availability(con)
#   plot_data_availability(avail)  # returns a ggplot object
# ============================================================

library(DBI)
library(dplyr)
library(ggplot2)

#' Parse a Sampling_Events.date-style mixed column (Excel serial OR
#' "MM/DD/YYYY H:MM" OR "MM/DD/YYYY" OR ISO "YYYY-MM-DD"), one value at
#' a time, tolerantly. Mirrors qc_conductivity_checks.R's
#' parse_event_date() (kept as a separate copy there since that script
#' predates this one and is not touched here to avoid destabilizing a
#' working QC check).
#'
#' 2026-09-05 (session 11): discovered that ~723 of 759 Sampling_Events
#' rows store `date` as days-since-1970-01-01 (Unix epoch days), NOT
#' days-since-1899-12-30 (Excel serial) like the rest -- e.g. raw value
#' 6502 parses to a nonsensical 1917-10-19 under the Excel-serial
#' assumption, but the *same* row's `external_event_id` is literally
#' "SB10_1987-10-21", and 6502 IS exactly the correct Unix-epoch-day
#' count for 1987-10-21. This is a real, unresolved upstream ingest bug
#' (root cause -- which ingest script wrote these rows with the wrong
#' epoch -- not yet identified; see AGENTS.md), NOT something fixed
#' here. This function works around it in a read-only way, for chart
#' purposes only: whenever `external_event_id` ends in a YYYY-MM-DD, that
#' is trusted as ground truth over the numeric `date` value. The ~10
#' rows without such a suffix still rely on the numeric value.
.parse_mixed_event_date <- function(x, external_event_id = NA_character_) {
  n <- length(x)
  if (length(external_event_id) == 1) external_event_id <- rep(external_event_id, n)

  parse_one <- function(v, eid) {
    # Prefer a YYYY-MM-DD suffix on the external event id, when present --
    # ground truth, unaffected by the numeric-date epoch ambiguity below.
    if (!is.na(eid)) {
      m <- regmatches(eid, regexpr("\\d{4}-\\d{2}-\\d{2}$", eid))
      if (length(m) == 1 && nzchar(m)) {
        d <- tryCatch(as.Date(m, format = "%Y-%m-%d"), error = function(e) NA)
        if (!is.na(d)) return(as.character(d))
      }
    }
    if (is.na(v) || trimws(v) == "") return(NA_character_)
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
  as.Date(vapply(seq_len(n), function(i) parse_one(as.character(x[i]), external_event_id[i]), character(1)))
}

#' Compute a tidy source x date-range x record-count table across every
#' major time-stamped source in the database. Read-only -- never writes
#' anything back to the database.
#'
#' @return tibble with columns: source, category, start_date, end_date, n_records
compute_data_availability <- function(con) {

  add_row <- function(source, category, dates, n = length(dates)) {
    dates <- dates[!is.na(dates)]
    if (length(dates) == 0) {
      return(tibble(source = source, category = category,
                     start_date = as.Date(NA), end_date = as.Date(NA), n_records = 0L))
    }
    tibble(source = source, category = category,
           start_date = min(dates), end_date = max(dates), n_records = as.integer(n))
  }

  rows <- list()

  # --- Chemistry sampling events (field + lab + NDEP + NDEP PRR) ---
  se <- dbGetQuery(con, "SELECT date, external_event_id FROM Sampling_Events")
  se_dates <- .parse_mixed_event_date(se$date, se$external_event_id)
  rows$sampling_events <- add_row("Chemistry Sampling Events", "Discrete / Event", se_dates)

  # --- Water level observations (NDWR + driller reports) ---
  wl <- dbGetQuery(con, "SELECT timestamp FROM Water_Level_Observations")
  wl_dates <- suppressWarnings(as.Date(wl$timestamp))
  rows$water_level <- add_row("Water Level Observations", "Discrete / Event", wl_dates)

  # --- Temperature logger observations (Elitech loggers; epoch seconds) ---
  to <- dbGetQuery(con, "SELECT timestamp FROM Temperature_Observations")
  to_ts <- suppressWarnings(as.numeric(to$timestamp))
  to_dates <- as.Date(as.POSIXct(to_ts, origin = "1970-01-01", tz = "UTC"))
  rows$temperature_logger <- add_row("Temperature Logger Observations", "Continuous Logger", to_dates)

  # --- Conductivity logger observations (HOBO/Onset; ISO timestamps) ---
  co <- dbGetQuery(con, "SELECT timestamp FROM Conductivity_Observations")
  co_dates <- suppressWarnings(as.Date(co$timestamp))
  rows$conductivity_logger <- add_row("Conductivity Logger Observations", "Continuous Logger", co_dates)

  # --- USGS discharge (param 60) ---
  usgs_q <- dbGetQuery(con, "SELECT datetime FROM USGS_Timeseries WHERE parameter_code = '60'")
  usgs_q_dates <- suppressWarnings(as.Date(usgs_q$datetime))
  rows$usgs_discharge <- add_row("USGS Discharge (live, param 60)", "Continuous Logger", usgs_q_dates)

  # --- USGS historic specific conductance (param 00095) ---
  usgs_sc <- dbGetQuery(con, "SELECT datetime FROM USGS_Timeseries WHERE parameter_code = '00095'")
  usgs_sc_dates <- suppressWarnings(as.Date(usgs_sc$datetime))
  rows$usgs_historic_sc <- add_row("USGS Historic Specific Conductance (grab samples)", "Discrete / Event", usgs_sc_dates)

  # --- NOAA weather ---
  wx <- tryCatch(dbGetQuery(con, "SELECT date FROM Weather_Observations"), error = function(e) NULL)
  if (!is.null(wx)) {
    wx_dates <- suppressWarnings(as.Date(wx$date))
    rows$weather <- add_row("NOAA Weather Observations", "External Time Series", wx_dates)
  }

  # --- Field photo-derived observations (EXIF timestamp, if present) ---
  fo <- tryCatch(dbGetQuery(con, "SELECT observed_at FROM Field_Observations"), error = function(e) NULL)
  if (!is.null(fo) && nrow(fo) > 0) {
    fo_dates <- suppressWarnings(as.Date(fo$observed_at))
    rows$field_observations <- add_row("Field Observations (photo-linked)", "Discrete / Event", fo_dates)
  }

  bind_rows(rows) |>
    filter(n_records > 0) |>
    arrange(start_date)
}

#' Sideways (horizontal) bar / Gantt-style chart of data availability
#' through time. One bar per source, ordered by start date, colored by
#' category (continuous logger vs. discrete/event vs. external time
#' series), spanning start_date to end_date.
plot_data_availability <- function(avail) {
  avail <- avail |>
    mutate(source = factor(source, levels = rev(source[order(start_date)])))

  ggplot(avail, aes(y = source, x = start_date, xend = end_date, yend = source, color = category)) +
    geom_segment(linewidth = 6, lineend = "round") +
    labs(
      x = "Date", y = NULL, color = "Data type",
      title = "Data availability by source, Steamboat Geochemistry Database",
      subtitle = "Bar spans first to last dated record currently in the database"
    ) +
    theme_minimal(base_size = 12) +
    theme(panel.grid.minor = element_blank())
}

#' Convenience wrapper: compute + write CSV + write plot. Called from
#' run_pipeline.R's export stage (always -- this is read-only reporting,
#' not gated by a RUN_INGEST flag).
build_data_availability_outputs <- function(
    con,
    csv_path = "data/derived/data_availability/data_availability.csv",
    plot_path = "output/figures/data_availability_timeline.png") {

  message("---- Computing data availability across all sources ----")
  avail <- compute_data_availability(con)

  dir.create(dirname(csv_path), recursive = TRUE, showWarnings = FALSE)
  write.csv(avail, csv_path, row.names = FALSE)

  dir.create(dirname(plot_path), recursive = TRUE, showWarnings = FALSE)
  p <- plot_data_availability(avail)
  ggsave(plot_path, p, width = 10, height = 5.5, dpi = 150)

  message("  -> ", nrow(avail), " source(s) with dated records; wrote ", csv_path, " and ", plot_path)
  invisible(avail)
}
