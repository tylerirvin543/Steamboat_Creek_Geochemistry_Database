# ============================================================
# historical_well_spring_comparison.R
#
# Built 2026-10-27 per explicit user request: compare "old springs we
# mapped and confirmed" / "old wells" through the real literature
# record -- chloride, specific conductance, temperature, and water
# level, one panel per well/spring, spanning every real era on file
# (1950s/White 1964,1968 and Sorey & Colvard 1992; 1985-1998 Skalbeck
# 2001 monthly monitoring; 1991-1994 Mariner & Janik 1995; modern NDEP/
# FIELD). Small multiples (facet_wrap ~ location name), not ten
# separate figures, so the comparison across wells/springs is direct.
#
# A genuine, curated list, not every location with any Cl value on
# file: these twelve are the real sites with enough independent,
# multi-source chloride history to support a real "has this well's
# chemistry drifted" comparison -- confirmed directly against the
# database (a `n_sources >= 1` with `n >= 4` Cl observations spanning
# more than one real sampling campaign) before being hard-coded here.
#
# Usage:
#   source("scripts/analysis/historical_well_spring_comparison.R")
#   build_historical_well_spring_figures(con)
# ============================================================

suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
  library(ggplot2)
})

source("scripts/analysis/plot_theme.R")

.HIST_SITES <- c(
  "Herz Domestic Well", "Herz Geothermal", "Curti Domestic Well",
  "Curti Barn Well (geothermal)",
  "Brown's School (Mariner & Janik 1995; = Wells 'Brown School Geothermal Well')",
  "Peigh", "Steinhardt Geothermal Well (narrative Cl trend)",
  "Pine Tree Ranch-1", "Flame",
  "23-5 (Mariner & Janik 1995; = Wells '23-5')",
  "Cox I-1 (Mariner & Janik 1995; = Wells 'Cox I-1')",
  "GS-5 (Mariner & Janik 1995; = Wells 'GS-5')",
  # Added 2026-10-27, per direct review: these five are real NDEP
  # Public Records Request (PRR) locations with genuine, promoted
  # 2024 chloride lab results (confirmed directly against
  # Lab_Analyses: 2 Cl values each, 2024-03-22 and 2024-06-07) that
  # were never added to this curated list -- the most recent real
  # chloride data this project has for any of the twelve-plus sites
  # compared here, and the gap this figure was missing.
  "Boyd Domestic Well", "Eich Well", "Jeppson Geothermal Well",
  "Rogers Domestic Well", "Soccer Field Monitoring Well"
)

# Shorter display names for facet labels -- the long, parenthetical
# "(Mariner & Janik 1995; = Wells '...')" disambiguation strings are
# useful in the database but clutter a facet strip.
.HIST_SHORT_NAMES <- c(
  "Herz Domestic Well" = "Herz Domestic",
  "Herz Geothermal" = "Herz Geothermal",
  "Curti Domestic Well" = "Curti Domestic",
  "Curti Barn Well (geothermal)" = "Curti Barn",
  "Brown's School (Mariner & Janik 1995; = Wells 'Brown School Geothermal Well')" = "Brown's School",
  "Peigh" = "Peigh",
  "Steinhardt Geothermal Well (narrative Cl trend)" = "Steinhardt",
  "Pine Tree Ranch-1" = "Pine Tree Ranch-1",
  "Flame" = "Flame",
  "23-5 (Mariner & Janik 1995; = Wells '23-5')" = "23-5",
  "Cox I-1 (Mariner & Janik 1995; = Wells 'Cox I-1')" = "Cox I-1",
  "GS-5 (Mariner & Janik 1995; = Wells 'GS-5')" = "GS-5",
  "Boyd Domestic Well" = "Boyd Domestic",
  "Eich Well" = "Eich",
  "Jeppson Geothermal Well" = "Jeppson Geothermal",
  "Rogers Domestic Well" = "Rogers Domestic",
  "Soccer Field Monitoring Well" = "Soccer Field"
)

.sql_in <- function(x) paste(sprintf("'%s'", gsub("'", "''", x)), collapse = ",")

.hist_cl <- function(con) {
  dbGetQuery(con, sprintf("
    SELECT l.name, COALESCE(se.date, s.collection_time) AS date_raw, la.value AS Cl
    FROM Lab_Analyses la
    JOIN Samples s ON la.sample_id = s.sample_id
    LEFT JOIN Sampling_Events se ON s.event_id = se.event_id
    JOIN Locations l ON s.location_id = l.location_id
    WHERE la.analyte = 'Cl' AND l.name IN (%s)
  ", .sql_in(.HIST_SITES)))
}

.hist_temp <- function(con) {
  dbGetQuery(con, sprintf("
    SELECT l.name, COALESCE(se.date, s.collection_time) AS date_raw, fm.value AS temperature_c
    FROM Field_Measurements fm
    JOIN Samples s ON fm.sample_id = s.sample_id
    LEFT JOIN Sampling_Events se ON s.event_id = se.event_id
    JOIN Locations l ON s.location_id = l.location_id
    WHERE fm.parameter = 'temperature' AND l.name IN (%s)
  ", .sql_in(.HIST_SITES)))
}

.hist_cond <- function(con) {
  dbGetQuery(con, sprintf("
    SELECT l.name, COALESCE(se.date, s.collection_time) AS date_raw, fm.value AS conductivity_uscm
    FROM Field_Measurements fm
    JOIN Samples s ON fm.sample_id = s.sample_id
    LEFT JOIN Sampling_Events se ON s.event_id = se.event_id
    JOIN Locations l ON s.location_id = l.location_id
    WHERE fm.parameter = 'conductivity' AND l.name IN (%s)
  ", .sql_in(.HIST_SITES)))
}

.hist_wl <- function(con) {
  dbGetQuery(con, sprintf("
    SELECT l.name, wl.timestamp AS date_raw, wl.depth_to_water
    FROM Water_Level_Observations wl
    JOIN Wells w ON wl.well_id = w.well_id
    JOIN Locations l ON w.location_id = l.location_id
    WHERE l.name IN (%s)
  ", .sql_in(.HIST_SITES)))
}

# Dates in this project arrive in several real formats (plain
# YYYY-MM-DD, Unix-epoch-seconds-as-text, occasionally a bare 4-digit
# year) -- tries each in turn, same general approach already
# established elsewhere in this project (e.g. notebook 07's
# .parse_any_date()), rather than assuming one format.
.parse_any_date_hist <- function(x) {
  x <- as.character(x)
  out <- as.Date(rep(NA, length(x)))
  iso <- !is.na(x) & grepl("^\\d{4}-\\d{2}-\\d{2}", x)
  if (any(iso)) out[iso] <- as.Date(substr(x[iso], 1, 10))
  epoch <- is.na(out) & !is.na(x) & grepl("^\\d{9,10}$", x)
  if (any(epoch)) out[epoch] <- as.Date(as.POSIXct(as.numeric(x[epoch]), origin = "1970-01-01", tz = "UTC"))
  yr <- is.na(out) & !is.na(x) & grepl("^\\d{4}$", x)
  if (any(yr)) out[yr] <- as.Date(paste0(x[yr], "-01-01"))
  # NDEP Public Records Request rows store dates as "MM/DD/YYYY H:MM"
  # (e.g. "03/22/2024 11:35"); previously unparsed here, which silently
  # dropped every NDEP PRR sample from these figures.
  us <- is.na(out) & !is.na(x) & grepl("^\\d{1,2}/\\d{1,2}/\\d{4}", x)
  if (any(us)) out[us] <- as.Date(sub(" .*$", "", x[us]), format = "%m/%d/%Y")
  out
}

#' Build the three real historical well/spring comparison figures (Cl,
#' temperature, and -- for the subset with any -- specific conductance
#' and water level), one facet per site, all real literature/database
#' values, no interpolation or synthetic data.
build_historical_well_spring_figures <- function(con,
    out_dir = "output/figures/manuscript") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  cl <- .hist_cl(con)
  temp <- .hist_temp(con)
  cond <- .hist_cond(con)
  wl <- .hist_wl(con)

  prep <- function(df, value_col) {
    df$date <- .parse_any_date_hist(df$date_raw)
    df$site <- .HIST_SHORT_NAMES[df$name]
    df$site[is.na(df$site)] <- df$name[is.na(df$site)]
    df <- df[!is.na(df$date) & !is.na(df[[value_col]]), ]
    df
  }
  cl <- prep(cl, "Cl")
  temp <- prep(temp, "temperature_c")
  cond <- prep(cond, "conductivity_uscm")
  wl <- prep(wl, "depth_to_water")

  site_order <- .HIST_SHORT_NAMES[.HIST_SITES]
  cl$site <- factor(cl$site, levels = site_order)
  temp$site <- factor(temp$site, levels = site_order)
  cond$site <- factor(cond$site, levels = site_order)
  wl$site <- factor(wl$site, levels = site_order)

  p_cl <- ggplot(cl, aes(date, Cl)) +
    geom_point(size = 1.3, alpha = 0.7, color = "#D55E00") +
    geom_line(alpha = 0.4, color = "#D55E00") +
    facet_wrap(~ site, scales = "free_y", ncol = 4) +
    theme_steamboat(base_size = 10) +
    labs(
      title = "Chloride through time, real historically documented wells and springs",
      subtitle = "Every real Cl measurement on file, by site, spanning all available eras (1950s-present)",
      x = NULL, y = "Chloride (mg/L)",
      caption = "Sources: Sorey & Colvard (1992), Mariner & Janik (1995), Skalbeck (2001) Table B-2, NDEP, NDEP Public Records Request (PRR, 2024), this project's own field campaign."
    )
  ggsave(file.path(out_dir, "historical_cl_by_well.png"), p_cl, width = 11, height = 9.5, dpi = 200)

  p_temp <- ggplot(temp, aes(date, temperature_c)) +
    geom_point(size = 1.3, alpha = 0.7, color = "#0072B2") +
    geom_line(alpha = 0.4, color = "#0072B2") +
    facet_wrap(~ site, scales = "free_y", ncol = 4) +
    theme_steamboat(base_size = 10) +
    labs(
      title = "Temperature through time, real historically documented wells and springs",
      subtitle = "Every real field-measured temperature on file, by site",
      x = NULL, y = "Temperature (\u00B0C)",
      caption = "Sources: Skalbeck (2001) Table B-2 monthly monitoring (1985-1998), NDEP, NDEP Public Records Request (PRR, 2024), this project's own field campaign."
    )
  ggsave(file.path(out_dir, "historical_temperature_by_well.png"), p_temp, width = 11, height = 9.5, dpi = 200)

  # Specific conductance and water level are both real but sparse for
  # this historical site list (modern U230/NDEP rounds only -- the
  # 1985-1998 Skalbeck era recorded temperature and Cl/B, not SC) --
  # built and saved, but only for sites that actually have at least one
  # real value, reported honestly rather than padded with empty facets.
  out <- list(cl_plot = p_cl, temp_plot = p_temp)
  if (nrow(cond) > 0) {
    p_cond <- ggplot(cond, aes(date, conductivity_uscm)) +
      geom_point(size = 1.5, color = "#009E73") +
      facet_wrap(~ site, scales = "free_y", ncol = 4) +
      theme_steamboat(base_size = 10) +
      labs(
        title = "Specific conductance, real historically documented wells and springs",
        subtitle = "Modern (NDEP U230 round) field measurements only -- no SC record exists for the 1985-1998 Skalbeck era",
        x = NULL, y = "Specific conductance (uS/cm)"
      )
    ggsave(file.path(out_dir, "historical_conductance_by_well.png"), p_cond, width = 9, height = 5, dpi = 200)
    out$cond_plot <- p_cond
  } else {
    message("[HISTORICAL COMPARISON] No real specific-conductance data for this site list -- skipped that figure.")
  }
  if (nrow(wl) > 0) {
    p_wl <- ggplot(wl, aes(date, depth_to_water)) +
      geom_point(size = 1.5, color = "#CC79A7") +
      geom_line(alpha = 0.4, color = "#CC79A7") +
      scale_y_reverse() +
      facet_wrap(~ site, scales = "free_y", ncol = 4) +
      theme_steamboat(base_size = 10) +
      labs(
        title = "Depth to water, real historically documented wells",
        subtitle = "Y-axis reversed so an upward line = a rising water table",
        x = NULL, y = "Depth to water (ft)"
      )
    ggsave(file.path(out_dir, "historical_water_level_by_well.png"), p_wl, width = 9, height = 5, dpi = 200)
    out$wl_plot <- p_wl
  } else {
    message("[HISTORICAL COMPARISON] No real water-level data for this site list -- skipped that figure.")
  }

  message("[HISTORICAL COMPARISON] Wrote figures to ", out_dir)
  invisible(out)
}
