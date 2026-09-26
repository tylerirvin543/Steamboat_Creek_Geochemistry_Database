# ============================================================
# barometric_efficiency.R
#
# Real (non-synthetic) barometric-efficiency calculation, per Sorey &
# Colvard (1992, p. 85-88, Figs. 39-40): the response of a well/spring's
# water level to atmospheric loading, expressed as a fraction (0-1)
# of the applied pressure change. Documented as a ready-to-run-but-
# unblocked stub in notebooks/07_historical_context_sorey1992.qmd
# starting 2026-09-12 ("no barometric/station pressure parameter
# currently exists anywhere in this database"); unblocked 2026-09-25
# by ingesting real hourly Reno-Airport MSLP data
# (scripts/ingest/ingest_barometric_pressure.R,
# data/raw/airpressure/README.md).
#
# Honest methodological note, stated up front rather than buried:
# Sorey & Colvard's own barometric-efficiency estimates were fit
# against short, intensive synoptic field campaigns (water level read
# 3-4x/day over a few days), where a naive water-level-vs-pressure
# regression is dominated by the short-term barometric response because
# there's no time for a competing seasonal/pumping trend to matter.
# This project's real overlapping data is different: full-year DAILY
# transducer records against hourly MSLP -- long enough for a real
# secular trend (seasonal recharge/pumping, not barometric loading at
# all) to dominate a naive level-vs-pressure regression and inflate or
# mask the true short-term signal. Both approaches are computed here,
# not just one:
#   - `method = "level"`   -- Sorey's original regression form
#     (water_level_elevation ~ pressure), reported for direct
#     comparability to the 1992 report's own numbers, but flagged
#     whenever the residual autocorrelation/trend is large.
#   - `method = "diff"`    -- day-over-day CHANGES in water level
#     regressed against day-over-day CHANGES in pressure. This removes
#     any slow secular trend and isolates the short-term loading
#     response -- the more defensible estimate for a full-year daily
#     series, even though it is not literally Sorey's own regression
#     form.
# Neither is presented as more "correct" than the other without
# comparing them -- both are returned, side by side, for every
# eligible well.
#
# Usage:
#   source("scripts/analysis/barometric_efficiency.R")
#   result <- run_barometric_efficiency(con)
#   result$table          # one row per eligible well x method
#   result$plot_overlay    # stacked water-level / pressure time series
#                           # for the best-overlapping real well
# ============================================================

library(DBI)
library(dplyr)
library(ggplot2)
library(tidyr)

HPA_TO_FT_WATER <- 0.03345  # 1 hPa = 100 Pa; head (ft) = P / (rho * g), fresh water, 20C

#' Daily-mean barometric pressure (hPa) from the ingested hourly MSLP series.
get_daily_pressure <- function(con, station_id = "USW00023185") {
  raw <- dbGetQuery(con, sprintf("
    SELECT date, value FROM Weather_Observations
    WHERE station_id = '%s' AND parameter = 'MSLP'
  ", station_id))
  raw$day <- substr(raw$date, 1, 10)
  raw |>
    dplyr::group_by(day) |>
    dplyr::summarise(pressure_hpa = mean(value, na.rm = TRUE), n_hourly = dplyr::n(), .groups = "drop")
}

#' Wells with continuous (transducer/automated) water-level records that
#' overlap the pressure record by at least `min_days` days. Returns one
#' row per well_id (the best-covered method_type kept, if a well has
#' more than one) -- deliberately deduplicated on well_id so downstream
#' joins never fan out into duplicate rows.
find_eligible_wells <- function(con, min_days = 60) {
  pressure_range <- dbGetQuery(con, "SELECT MIN(date) mn, MAX(date) mx FROM Weather_Observations WHERE parameter = 'MSLP'")
  wl <- dbGetQuery(con, sprintf("
    SELECT wl.well_id, w.well_name, w.latitude, w.longitude, wl.method_type,
           substr(wl.timestamp, 1, 10) AS day, wl.water_level_elevation
    FROM Water_Level_Observations wl
    JOIN Wells w ON w.well_id = wl.well_id
    WHERE wl.timestamp >= '%s' AND wl.timestamp <= '%s'
      AND wl.water_level_elevation IS NOT NULL
  ", pressure_range$mn, pressure_range$mx))

  wl |>
    dplyr::group_by(well_id, well_name, latitude, longitude, method_type) |>
    dplyr::summarise(n_days = dplyr::n_distinct(day), .groups = "drop") |>
    dplyr::filter(n_days >= min_days) |>
    dplyr::arrange(dplyr::desc(n_days)) |>
    dplyr::distinct(well_id, .keep_all = TRUE)
}

#' Is (lat, lon) inside the Steamboat Hills field bounding box already
#' used by scripts/analysis/facies_depth_map.R? Kept as its own helper
#' so the same box is reused, not silently redefined.
.in_steamboat_bbox <- function(lat, lon,
                                bbox = c(lon_min = -119.80, lon_max = -119.71,
                                         lat_min = 39.355, lat_max = 39.415)) {
  !is.na(lat) & !is.na(lon) &
    lon >= bbox["lon_min"] & lon <= bbox["lon_max"] &
    lat >= bbox["lat_min"] & lat <= bbox["lat_max"]
}

#' Fit both barometric-efficiency regression forms for one well.
fit_barometric_efficiency_one <- function(con, well_id) {
  daily_p <- get_daily_pressure(con)
  wl <- dbGetQuery(con, sprintf("
    SELECT substr(timestamp, 1, 10) AS day, water_level_elevation
    FROM Water_Level_Observations
    WHERE well_id = %d AND water_level_elevation IS NOT NULL
  ", well_id))

  paired <- wl |>
    dplyr::inner_join(daily_p, by = "day") |>
    dplyr::arrange(day) |>
    dplyr::mutate(pressure_ft_water = pressure_hpa * HPA_TO_FT_WATER)

  if (nrow(paired) < 10) {
    return(NULL)
  }

  # ---- Method 1: Sorey's original form (level ~ pressure) ----
  fit_level <- lm(water_level_elevation ~ pressure_ft_water, data = paired)
  s_level <- summary(fit_level)
  be_level <- -coef(fit_level)[["pressure_ft_water"]]

  # ---- Method 2: first-differences (change ~ change) ----
  paired_diff <- paired |>
    dplyr::mutate(
      d_level = water_level_elevation - dplyr::lag(water_level_elevation),
      d_pressure = pressure_ft_water - dplyr::lag(pressure_ft_water)
    ) |>
    dplyr::filter(!is.na(d_level), !is.na(d_pressure))

  fit_diff <- lm(d_level ~ d_pressure, data = paired_diff)
  s_diff <- summary(fit_diff)
  be_diff <- -coef(fit_diff)[["d_pressure"]]

  tibble::tibble(
    well_id = well_id,
    method = c("level", "diff"),
    barometric_efficiency = c(be_level, be_diff),
    r_squared = c(s_level$r.squared, s_diff$r.squared),
    p_value = c(
      coef(s_level)["pressure_ft_water", "Pr(>|t|)"],
      coef(s_diff)["d_pressure", "Pr(>|t|)"]
    ),
    n = c(nrow(paired), nrow(paired_diff)),
    date_min = min(paired$day), date_max = max(paired$day)
  )
}

#' Run the real barometric-efficiency analysis across every eligible
#' well, plus a stacked water-level/pressure overlay plot. The overlay
#' well is chosen from wells actually inside the Steamboat Hills field
#' (this thesis's study area) when any qualify, falling back to the
#' globally best-overlap well otherwise -- most of this database's
#' Water_Level_Observations network is a much wider South Truckee
#' Meadows/Reno monitoring network, not Steamboat-specific, and a
#' "most overlapping days wins" rule alone would otherwise pick an
#' unrelated Reno-basin well.
run_barometric_efficiency <- function(con, min_days = 60, prefer_steamboat = TRUE) {
  eligible <- find_eligible_wells(con, min_days = min_days)

  if (nrow(eligible) == 0) {
    message("[baro_eff] No well has >= ", min_days,
            " days of continuous water-level data overlapping the barometric-pressure record.")
    return(list(table = eligible, plot_overlay = NULL))
  }

  message("[baro_eff] ", nrow(eligible), " well(s) have >= ", min_days,
          " overlapping days: ", paste(eligible$well_name, collapse = ", "))

  results <- lapply(eligible$well_id, function(id) fit_barometric_efficiency_one(con, id))
  results <- dplyr::bind_rows(results)
  results <- results |> dplyr::left_join(eligible[, c("well_id", "well_name", "latitude", "longitude")], by = "well_id")

  # ---- Choose the overlay well ----
  eligible$in_steamboat <- .in_steamboat_bbox(eligible$latitude, eligible$longitude)
  steamboat_candidates <- eligible[eligible$in_steamboat, ]

  if (prefer_steamboat && nrow(steamboat_candidates) > 0) {
    best_well <- steamboat_candidates$well_id[1]
    best_name <- steamboat_candidates$well_name[1]
    message("[baro_eff] Overlay plot uses ", best_name,
            " -- inside the Steamboat Hills field bounding box (", steamboat_candidates$n_days[1],
            " overlapping days); not the global maximum, which sits in the wider Reno/",
            "South Truckee Meadows monitoring network this thesis is not about.")
  } else {
    best_well <- eligible$well_id[1]
    best_name <- eligible$well_name[1]
    if (prefer_steamboat) {
      message("[baro_eff] No Steamboat-area well meets min_days -- falling back to the ",
              "globally best-overlapping well (", best_name, ", outside the Steamboat field).")
    }
  }

  # ---- Overlay plot: restrict BOTH series to the real overlap window ----
  daily_p <- get_daily_pressure(con)
  wl_best_full <- dbGetQuery(con, sprintf("
    SELECT substr(timestamp, 1, 10) AS day, water_level_elevation
    FROM Water_Level_Observations WHERE well_id = %d AND water_level_elevation IS NOT NULL
  ", best_well))

  overlap_days <- intersect(wl_best_full$day, daily_p$day)
  wl_best <- wl_best_full |> dplyr::filter(day %in% overlap_days)
  daily_p_overlap <- daily_p |> dplyr::filter(day %in% overlap_days)

  overlay_long <- dplyr::bind_rows(
    wl_best |> dplyr::transmute(day, series = "Water level (ft elevation)", value = water_level_elevation),
    daily_p_overlap |> dplyr::transmute(day, series = "Barometric pressure (hPa, daily mean)", value = pressure_hpa)
  ) |>
    dplyr::mutate(day = as.Date(day))

  p_overlay <- ggplot(overlay_long, aes(x = day, y = value)) +
    geom_line() +
    facet_wrap(~series, ncol = 1, scales = "free_y") +
    labs(x = NULL, y = NULL,
         title = paste0("Water level vs. barometric pressure -- ", best_name),
         subtitle = paste0(length(overlap_days), " overlapping days -- see barometric_efficiency.R for BE calculation"),
         caption = "Barometric pressure: Reno Airport ASOS (IEM), daily mean. A real, time-paired composite check, not a spatial overlay.") +
    theme_minimal()

  list(table = results, plot_overlay = p_overlay, eligible_wells = eligible)
}

#' Synthetic self-test, kept alongside the real function for anyone
#' debugging without a real database connection -- NOT used for any
#' real reported number.
demo_barometric_efficiency <- function(seed = 6193) {
  set.seed(seed)
  n <- 200
  baro <- 30 + cumsum(rnorm(n, 0, 0.02))          # synthetic barometric pressure, inHg
  wl <- 100 - 0.7 * baro + rnorm(n, 0, 0.05)       # synthetic water level, BE ~ 0.7
  fit <- lm(wl ~ baro)
  -coef(fit)[["baro"]]
}
