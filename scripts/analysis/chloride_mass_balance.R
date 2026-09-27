# ============================================================
# chloride_mass_balance.R
#
# Purpose (added 2026-09-27):
# Folds the GRC 2026 poster's (Irvin & Lindsey, "Renewed Measurements
# of Thermal Water Discharge at the Steamboat Hills Geothermal System
# Following Recent Fumarolic Activity") own chloride mass-balance
# calculation into a real, reproducible script -- per website/
# results.Rmd's own explicit note that this "has not yet been re-run
# as a reproducible script against the live database ... so treat the
# specific numbers as a snapshot ... Folding that calculation into the
# pipeline itself ... is a natural near-term follow-up."
#
# The poster's own stated formula (read directly from
# docs/literature/GRC_2026_Steamboat.pdf via pdftotext, not guessed):
#
#   Chloride mass balance: Q_TW = (Cl-flux at SBBV - Cl-flux at SBRR) / 820 mg/L Cl
#   where Q_TW is Thermal Water Inflow, and 820 mg/L is the typical
#   Steamboat brine chloride concentration.
#
# "Cl-flux" at a station is discharge x concentration (a mass flux),
# NOT the concentration alone -- confirmed this is the poster's real
# method, not the simpler single-station Q*(C-C_meteoric)/(C_thermal-
# C_meteoric) formula used elsewhere in this project (e.g. notebook
# 07's live-qtw-chunk, which -- flagged here -- had actually
# implemented a DIFFERENT, single-station formula than the poster's
# own two-station flux-difference method; see notebooks/
# 07_historical_context_sorey1992.qmd's changelog for the correction
# made alongside this script).
#
# Data source: the real, corrected `sample_flow` table (see Session
# 2026-09-27's align_timeseries.R join-correctness fix -- this table
# returned 0 usable rows for most of this project's history before
# that fix) joined to Lab_Analyses for Cl, paired by SAME CALENDAR
# DATE at the two named stations (never guessed/interpolated across
# dates). Reports one row per date both stations have a real paired
# Cl+discharge measurement, plus a simple mean across dates -- the
# poster's own "27 L/s" figure is explicitly described (see the
# discharge-timeline table elsewhere in this project) as "averaged
# over the sampling period," so a mean-across-real-dates is the
# faithful reproduction target, not a single day.
# ============================================================

library(DBI)
library(dplyr)

#' Reproduce the poster's own two-station chloride mass-balance
#' calculation from the real, corrected sample_flow join.
#'
#' @param con DBI connection.
#' @param upstream_site,downstream_site Locations.name values for the
#'   two paired stream stations (default SBRR/SBBV, the poster's own
#'   sites).
#' @param C_thermal Typical deep thermal-water Cl concentration
#'   (mg/L), the poster's own stated 820 mg/L default -- never
#'   silently changed without a caller override.
#' @return A list: `by_date` (one row per real paired date, with every
#'   intermediate quantity so the calculation is fully auditable) and
#'   `mean_Q_TW_Ls` (simple mean across those dates, NA if none exist).
compute_chloride_mass_balance <- function(con, upstream_site = "SBRR",
                                           downstream_site = "SBBV",
                                           C_thermal = 820) {

  message("---- Chloride mass balance (poster formula): ", downstream_site,
          " minus ", upstream_site, ", C_thermal = ", C_thermal, " mg/L ----")

  pull_site <- function(site_name) {
    dbGetQuery(con, "
      SELECT sf.sample_id, sf.sample_time, sf.discharge_m3_s, sf.time_diff_min,
             la.value AS cl_mgL
      FROM sample_flow sf
      JOIN Locations l ON l.location_id = sf.location_id
      JOIN Lab_Analyses la ON la.sample_id = sf.sample_id AND la.analyte = 'Cl'
      WHERE l.name = ?
    ", params = list(site_name))
  }

  up <- pull_site(upstream_site)
  down <- pull_site(downstream_site)

  if (nrow(up) == 0 || nrow(down) == 0) {
    message("  -> No real paired Cl+discharge data for one or both sites yet.")
    return(list(by_date = data.frame(), mean_Q_TW_Ls = NA_real_))
  }

  up$date <- as.Date(as.POSIXct(up$sample_time, origin = "1970-01-01", tz = "UTC"))
  down$date <- as.Date(as.POSIXct(down$sample_time, origin = "1970-01-01", tz = "UTC"))

  # Pair strictly by same calendar date -- never interpolate/guess
  # across dates the two sites weren't both sampled.
  paired <- inner_join(
    up %>% rename(sample_id_up = sample_id, discharge_up = discharge_m3_s,
                  time_diff_up = time_diff_min, cl_up = cl_mgL),
    down %>% rename(sample_id_down = sample_id, discharge_down = discharge_m3_s,
                    time_diff_down = time_diff_min, cl_down = cl_mgL),
    by = "date"
  )

  if (nrow(paired) == 0) {
    message("  -> ", upstream_site, " and ", downstream_site,
            " have real Cl+discharge data, but never on the same date.")
    return(list(by_date = data.frame(), mean_Q_TW_Ls = NA_real_))
  }

  paired <- paired %>%
    mutate(
      cl_flux_up_gs   = discharge_up   * cl_up,    # m3/s * mg/L = g/s
      cl_flux_down_gs = discharge_down * cl_down,
      # g/s / (mg/L = g/m3) = m3/s; x1000 for L/s
      Q_TW_Ls = (cl_flux_down_gs - cl_flux_up_gs) / C_thermal * 1000
    ) %>%
    select(date, sample_id_up, sample_id_down,
           discharge_up, cl_up, time_diff_up,
           discharge_down, cl_down, time_diff_down,
           cl_flux_up_gs, cl_flux_down_gs, Q_TW_Ls)

  mean_Q_TW <- mean(paired$Q_TW_Ls, na.rm = TRUE)

  message("  -> ", nrow(paired), " real paired date(s); mean Q_TW = ",
          round(mean_Q_TW, 1), " L/s (range ", round(min(paired$Q_TW_Ls), 1),
          "-", round(max(paired$Q_TW_Ls), 1), " L/s).")

  list(by_date = paired, mean_Q_TW_Ls = mean_Q_TW)
}

#' Run compute_chloride_mass_balance() and write its result to a
#' stable, regenerable CSV -- mirrors data_availability.csv's own
#' "read-only reporting, no RUN_ANALYSIS flag" pattern, so this stays
#' in sync automatically on every pipeline run rather than needing a
#' manual console step. export_website_data_files() (run_pipeline.R)
#' copies this into docs/data/ the same way it does every other
#' website CSV.
build_chloride_mass_balance_report <- function(con, out_csv = "data/derived/chloride_mass_balance/chloride_mass_balance.csv") {
  result <- compute_chloride_mass_balance(con)
  dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)
  write.csv(result$by_date, out_csv, row.names = FALSE, na = "")
  message("  -> Wrote ", nrow(result$by_date), " row(s) to ", out_csv, ".")
  invisible(result)
}
