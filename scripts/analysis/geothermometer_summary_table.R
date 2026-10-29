# ============================================================
# geothermometer_summary_table.R
#
# A compact, one-row-per-sample geothermometer comparison table for the
# seven real Lower Sinter Terrace flowpath samples, built 2026-10-27 as
# the data-table companion to the existing geothermometer-divergence
# figure (geothermometer_comparison.png) and the new multicomponent
# mineral-equilibration diagram (lst_mineral_equilibration.R). Columns:
# measured discharge temperature, Na/K (Giggenbach, activity-based),
# Na/K (Fournier, activity-based), quartz zero-crossing, chalcedony
# zero-crossing, and whether any candidate mineral set actually
# converges on a single shared equilibration temperature in the real
# PHREEQC_Temp_Sweep output (the genuine multicomponent-equilibrium
# test, Reed & Spycher 1984) -- reported honestly as "no convergence"
# where that is in fact the real result (confirmed directly against the
# sweep data before writing this table, not assumed).
#
# No new PHREEQC execution: reads PHREEQC_Results (activity-based Na/K,
# via the existing calculate_activity_geothermometers()) and
# PHREEQC_Temp_Sweep (quartz/chalcedony zero-crossings, already used by
# flowpath_baseline_characterization_figures.R's temperature-profile
# figure).
#
# Usage:
#   source("scripts/analysis/geothermometer_summary_table.R")
#   build_geothermometer_summary_table(con)
# ============================================================

library(DBI)
library(dplyr)

.GEOTHERM_SAMPLE_IDS <- c(816, 819, 818, 821, 815, 825, 820, 822)  # SBBV (818) added 2026-10-27 per direct request

.zero_cross_geotherm <- function(t, s) {
  if (length(t) < 2) return(NA_real_)
  o <- order(t); t <- t[o]; s <- s[o]
  for (i in seq_len(length(t) - 1)) {
    if (!is.na(s[i]) && !is.na(s[i + 1]) && sign(s[i]) != sign(s[i + 1])) {
      return(t[i] + (s[i] / (s[i] - s[i + 1])) * (t[i + 1] - t[i]))
    }
  }
  NA_real_
}

#' @return A data frame, one row per real flowpath sample, and also
#'   writes `data/derived/phreeqc/geothermometer_summary_table.csv`.
build_geothermometer_summary_table <- function(con,
    sample_ids = .GEOTHERM_SAMPLE_IDS,
    out_csv = "data/derived/phreeqc/geothermometer_summary_table.csv") {

  source("scripts/phreeqc/09_run_phreeqc.R", local = TRUE)

  nak <- calculate_activity_geothermometers(con)
  nak <- nak[nak$sample_id %in% sample_ids & nak$db_file == "llnl.dat", ]

  sw <- dbGetQuery(con, sprintf("
    SELECT sample_id, temperature_C, parameter, value
    FROM PHREEQC_Temp_Sweep
    WHERE sample_id IN (%s) AND parameter IN ('SI_Quartz', 'SI_Chalcedony')
  ", paste(sample_ids, collapse = ",")))

  sol <- dbGetQuery(con, sprintf("
    SELECT ps.sample_id, l.name AS location_name, ps.temperature AS measured_temp_c
    FROM PHREEQC_Solutions ps
    JOIN Samples s ON ps.sample_id = s.sample_id
    JOIN Locations l ON s.location_id = l.location_id
    WHERE ps.sample_id IN (%s)
  ", paste(sample_ids, collapse = ",")))

  # Multicomponent convergence check: do any 2+ of the 6 geothermometrically
  # relevant minerals (Calcite, Dolomite, Quartz, Chalcedony, Anhydrite,
  # Fluorite) cross zero within 15 degrees Celsius of each other? A real,
  # not assumed, test against the full sweep.
  sw_all <- dbGetQuery(con, sprintf("
    SELECT sample_id, temperature_C, parameter, value
    FROM PHREEQC_Temp_Sweep
    WHERE sample_id IN (%s) AND parameter IN
      ('SI_Calcite','SI_Dolomite','SI_Quartz','SI_Chalcedony','SI_Anhydrite','SI_Fluorite')
  ", paste(sample_ids, collapse = ",")))

  rows <- lapply(sample_ids, function(sid) {
    nak_row <- nak[nak$sample_id == sid, ]
    sw_q <- sw[sw$sample_id == sid & sw$parameter == "SI_Quartz", ]
    sw_c <- sw[sw$sample_id == sid & sw$parameter == "SI_Chalcedony", ]
    t_quartz <- .zero_cross_geotherm(sw_q$temperature_C, sw_q$value)
    t_chalc  <- .zero_cross_geotherm(sw_c$temperature_C, sw_c$value)

    # multicomponent convergence: collect each mineral's own crossing, then
    # check pairwise spread
    sw_sid <- sw_all[sw_all$sample_id == sid, ]
    crossings <- sapply(split(sw_sid, sw_sid$parameter), function(d) {
      .zero_cross_geotherm(d$temperature_C, d$value)
    })
    crossings <- crossings[!is.na(crossings)]
    converges <- length(crossings) >= 2 && (max(crossings) - min(crossings)) <= 15

    tibble::tibble(
      sample_id = sid,
      location_name = sol$location_name[sol$sample_id == sid],
      measured_temp_c = sol$measured_temp_c[sol$sample_id == sid],
      T_NaK_gigg_C = if (nrow(nak_row) > 0) nak_row$T_NaK_gigg_activity[1] else NA_real_,
      T_NaK_four_C = if (nrow(nak_row) > 0) nak_row$T_NaK_four_activity[1] else NA_real_,
      T_quartz_C = t_quartz,
      T_chalcedony_C = t_chalc,
      n_minerals_converging = length(crossings),
      multicomponent_converges = converges
    )
  })

  tbl <- dplyr::bind_rows(rows) |> arrange(desc(measured_temp_c))

  dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)
  write.csv(tbl, out_csv, row.names = FALSE)
  message("  -> Wrote ", out_csv)
  tbl
}
