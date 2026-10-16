# ============================================================
# gas_air_correction.R
#
# Purpose:
# A purpose-built atmospheric-contamination (air) correction for free-
# gas compositions, plus a wrapper that runs the existing D'Amore-
# Panichi (1980) gas geothermometer (scripts/phreeqc/
# 13_gas_geothermometry.R) on the corrected values. Built for the
# April 2026 Fischer/Ruprecht fissure gas samples (NV26-1/2/3), the
# first real gas data this project has -- no air-correction capability
# existed before this (the closest prior thing,
# scripts/phreeqc/14_gas_mixing.R, is a generic two-end-member mixing-
# fraction solver, not a purpose-built O2-based air correction).
#
# Method (standard Giggenbach-style air correction, matching the
# source spreadsheet's own analyst note that "O2 = air component to be
# subtracted; N2/Ar/CH4/CO/H2 assumed unaffected"):
#   - Dry air is ~20.95 mol% O2, ~78.08 mol% N2 (N2/O2 = 3.773).
#   - Every mole of measured O2 is assumed atmospheric (geothermal
#     gases are essentially O2-free at depth); air-derived N2 is
#     therefore 3.773 * O2_measured.
#   - "Excess" (non-air) N2 = N2_measured - air_derived_N2. Negative
#     values (more measured O2 than the air N2/O2 ratio could explain
#     given the measured N2) are clamped to 0 and flagged -- a real
#     possibility for a sample close to 100% air-contaminated.
#   - air_fraction (0-1) estimates the share of the whole sample that
#     is atmospheric, via O2_measured / 20.95 (dry-air O2 mol%) --
#     capped at 1.
#   - CO2/He/H2/CH4/CO/H2S are left as measured (per the spreadsheet's
#     own stated assumption) and the whole corrected composition
#     (CO2, He, H2, Ar [unchanged -- Ar is present in both the
#     reservoir gas and air and this correction does not attempt to
#     split it], excess_N2, CH4, CO, H2S) is renormalized to 100%.
#
# This is a screening-level correction, not a rigorous Ar-isotope-based
# air correction (which would need measured 40Ar/36Ar against the air
# value of 295.5 -- already on file for these 3 samples as a noble-gas
# ratio, see .estimate_air_fraction_from_argon() below for a second,
# independent diagnostic using that ratio instead of O2).
# ============================================================

library(dplyr)

AIR_N2_O2_RATIO <- 3.773      # Giggenbach-standard dry-air N2/O2 mole ratio
AIR_O2_MOL_PCT  <- 20.95      # dry-air O2 mole percent
AIR_AR40_AR36   <- 295.5      # atmospheric 40Ar/36Ar ratio

#' Apply the O2-based air correction to one or more gas analyses.
#'
#' @param df Data frame/tibble with columns sample_label, CO2, He, H2,
#'   Ar, O2, N2, CH4, CO, H2S (mole %), and optionally Ar40_Ar36.
#' @return The input df with new columns: air_fraction_o2 (O2-based
#'   diagnostic), air_fraction_ar40_ar36 (independent Ar-isotope-based
#'   diagnostic, NA if Ar40_Ar36 not supplied), n2_excess (air-corrected
#'   N2), n2_excess_clamped (TRUE if the raw subtraction went negative
#'   and was clamped to 0), and *_corrected columns renormalized to
#'   100% over (CO2, He, H2, Ar, n2_excess, CH4, CO, H2S).
correct_gas_for_air <- function(df) {
  required <- c("sample_label", "CO2", "He", "H2", "Ar", "O2", "N2", "CH4", "CO", "H2S")
  missing_cols <- setdiff(required, names(df))
  if (length(missing_cols) > 0) stop("Missing required column(s): ", paste(missing_cols, collapse = ", "))

  df |>
    mutate(
      air_fraction_o2 = pmin(O2 / AIR_O2_MOL_PCT, 1),
      air_fraction_ar40_ar36 = if ("Ar40_Ar36" %in% names(df)) {
        # Simple two-end-member (air vs. a 40Ar/36Ar >= air end-member,
        # radiogenic/mantle-enriched) mixing read: how much of the
        # sample's own Ar is explained by an air signature alone. Not
        # used for the renormalization below -- a second, independent
        # check only.
        pmin(AIR_AR40_AR36 / Ar40_Ar36, 1)
      } else {
        NA_real_
      },
      n2_air_derived = AIR_N2_O2_RATIO * O2,
      n2_excess_raw = N2 - n2_air_derived,
      n2_excess_clamped = n2_excess_raw < 0,
      n2_excess = pmax(n2_excess_raw, 0),
      corrected_sum = CO2 + He + H2 + Ar + n2_excess + CH4 + CO + H2S,
      CO2_corrected = CO2 / corrected_sum * 100,
      He_corrected = He / corrected_sum * 100,
      H2_corrected = H2 / corrected_sum * 100,
      Ar_corrected = Ar / corrected_sum * 100,
      N2_corrected = n2_excess / corrected_sum * 100,
      CH4_corrected = CH4 / corrected_sum * 100,
      CO_corrected = CO / corrected_sum * 100,
      H2S_corrected = H2S / corrected_sum * 100
    ) |>
    select(-corrected_sum)
}

#' Run the air correction + D'Amore-Panichi geothermometer on real
#' Gas_Analyses rows, writing a derived CSV for downstream use (the
#' historical-comparison figure, the manuscript figure, the Ruprecht
#' outreach document).
#'
#' @param con DBI connection.
#' @return Invisibly, the combined tibble written to disk.
analyze_fischer_gas_samples <- function(
    con,
    out_csv = "data/derived/gas_analysis/fischer_gas_air_corrected_geothermometry.csv") {

  source("scripts/phreeqc/13_gas_geothermometry.R", local = TRUE)

  raw <- DBI::dbGetQuery(con, "
    SELECT sample_label, collection_date, field_temp_c,
           co2_mol_pct AS CO2, he_mol_pct AS He, h2_mol_pct AS H2,
           ar_mol_pct AS Ar, o2_mol_pct AS O2, n2_mol_pct AS N2,
           ch4_mol_pct AS CH4, co_mol_pct AS CO, h2s_mol_pct AS H2S,
           ar40_ar36 AS Ar40_Ar36, he3_he4_r_ra AS R_Ra,
           data_quality_flag, notes
    FROM Gas_Analyses
  ")

  if (nrow(raw) == 0) {
    message("[gas_air_correction] No Gas_Analyses rows found -- nothing to analyze.")
    return(invisible(NULL))
  }

  corrected <- correct_gas_for_air(raw)

  geotherm_input <- corrected |>
    transmute(sample_id = sample_label, CO2 = CO2_corrected, H2S = H2S_corrected,
              H2 = H2_corrected, CH4 = CH4_corrected)
  geotherm <- compute_dap_geothermometry(geotherm_input) |>
    rename(sample_label = sample_id, dap_temperature_C = temperature_C)

  result <- corrected |>
    left_join(geotherm |> select(sample_label, dap_temperature_C, pCO2_atm, pCO2_rule),
               by = "sample_label")

  dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(result, out_csv)
  message("[gas_air_correction] Wrote ", nrow(result), " row(s) to ", out_csv)

  for (i in seq_len(nrow(result))) {
    r <- result[i, ]
    message(sprintf(
      "  %s (%s): field T=%.1fC, air fraction (O2-based) = %.0f%%, D'Amore-Panichi T = %.1fC%s",
      r$sample_label, r$data_quality_flag, r$field_temp_c, r$air_fraction_o2 * 100,
      r$dap_temperature_C,
      if (isTRUE(r$n2_excess_clamped)) " [N2 excess clamped to 0 -- fully air-explicable]" else ""
    ))
  }

  invisible(result)
}
