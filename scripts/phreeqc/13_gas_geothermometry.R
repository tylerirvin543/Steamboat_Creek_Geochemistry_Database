#13_gas_geothermometry
#
# Free-gas (fumarole/bubbling-spring) geothermometry -- forward-looking
# capability built ahead of real data. Motivated directly by the planned
# UCSB (Tobias Fischer) gas sampling at the Lower Sinter Terrace geysering
# fissure and nearby fumaroles (CO2/H2S major-gas composition, plus He
# isotopes and other tracers still to be scoped once real analyses are in
# hand -- see AGENTS.md's 2026-09-06 notes). No Fischer data exists yet;
# per explicit instruction this file does NOT create any database table
# or wire into run_pipeline.R. It is a standalone, self-tested module
# (data-frame in, data-frame out) that will be pointed at real gas-sample
# rows once their actual reporting format is known.
#
# Literature grounding (docs/literature/"Geochem Data and concept model
# Mariner & Janik 1995.pdf" -- GRC Transactions v.19, the only
# Steamboat-specific gas-geochemistry study found in this project's
# literature folder): Table 2 reports free-gas mole-percent compositions
# (CO2, H2S, H2, CH4, NH3, N2, O2, Ar, He) and three gas-geothermometer
# temperature columns (T-DP, T-HA, T-CO2) for Caithness/Far West wells and
# one fumarole (at PW3-4). D'Amore & Panichi's (1980) reservoir
# temperature is at least 230-235C (sulfate-water isotope /
# enthalpy-chloride) and possibly as high as 243C from Na-K and gas
# geothermometry, with well 23-5 the hottest and gas-geothermometer
# T-CO2 values as high as 243C.
#
# Only the D'Amore-Panichi (1980) multicomponent CO2-H2-H2S-CH4
# geothermometer is implemented here, and only because it could be
# independently cross-validated against Mariner & Janik's own published
# T-DP numbers (see demo_gas_geothermometry() below) -- this project's
# standing rule is to never publish a formula it can't verify. The other
# two columns in their Table 2 (T-HA, attributed to Giggenbach & Goguel
# 1989; T-CO2, attributed to Arnorsson & Gunnlaugsson 1985) were
# deliberately NOT implemented: web search found qualitative descriptions
# of both (T-CO2 in particular requires the fumarole steam fraction from
# an assumed adiabatic-boiling path, not just gas mole percent) but not
# a citable, exact calibration equation this session could verify against
# real numbers the way the D'Amore-Panichi coefficients were. Flagged
# here as a known gap, not silently skipped.

library(dplyr)

#' D'Amore & Panichi (1980) multicomponent gas geothermometer.
#'
#' t(C) = 24775 / (alpha + beta + 36.05) - 273.15
#' alpha = 2*log10(CH4/CO2) - 6*log10(H2/CO2) - 3*log10(H2S/CO2)   (mole %)
#' beta  = -7*log10(pCO2)   (pCO2 in atm, estimated per D'Amore & Panichi's
#'         own rule-of-thumb: 0.1 atm if CO2 < 75 mol%; 1 atm if CO2 >= 75
#'         mol%; 10 atm if additionally CH4 > 2*H2 AND H2S > 2*H2)
#'
#' NOTE on the H2 coefficient: several secondary sources (abstracts,
#' review articles) transcribe alpha's H2 term as bare "-log10(H2/CO2)"
#' (coefficient 1), but Powell (2000, Stanford GRC short course review)
#' gives coefficient 6, and only coefficient 6 reproduces Mariner &
#' Janik's own published T-DP values for real Steamboat samples (see
#' demo_gas_geothermometry()) -- coefficient 1 overshoots by >150C.
#' Coefficient 6 is used here; this is exactly the kind of formula-
#' transcription risk this project has hit before (see the SO4/S(6)
#' PHREEQC element-name bug), which is why the self-test below checks
#' against real, cited, published temperatures rather than trusting the
#' formula on its own.
#'
#' @param co2, h2s, h2, ch4 Mole percent (0-100) of each gas in the dry
#'   gas fraction. NA/non-positive values for h2s/h2/ch4 are treated as
#'   the paper's own convention for below-detection ("<=0.001 mol%"),
#'   per the French-language secondary source (aquamania.net technical
#'   note) describing the original paper's NB1 footnote.
#' @return A list: temperature_C, alpha, beta, pCO2_atm, pCO2_rule.
dap_gas_geothermometer <- function(co2, h2s, h2, ch4) {
  if (is.na(co2) || co2 <= 0) stop("CO2 mole percent must be a positive number.")

  # NB1 (D'Amore & Panichi 1980): treat below-detection/missing minor
  # gases as 0.001 mol% rather than 0 (log of 0 is undefined).
  floor_val <- function(x) if (is.na(x) || x <= 0) 0.001 else x
  h2s_v <- floor_val(h2s); h2_v <- floor_val(h2); ch4_v <- floor_val(ch4)

  alpha <- 2 * log10(ch4_v / co2) - 6 * log10(h2_v / co2) - 3 * log10(h2s_v / co2)

  # NB2 pCO2 estimation rule (reservoir CO2 partial pressure is rarely
  # measured directly, so the original authors proposed this three-way
  # rule from the gas composition itself).
  if (co2 < 75) {
    pCO2 <- 0.1; rule <- "CO2 < 75 mol%: pCO2 = 0.1 atm"
  } else if (ch4_v > 2 * h2_v && h2s_v > 2 * h2_v) {
    pCO2 <- 10; rule <- "CO2 >= 75 mol% and CH4 > 2*H2 and H2S > 2*H2: pCO2 = 10 atm"
  } else {
    pCO2 <- 1; rule <- "CO2 >= 75 mol%: pCO2 = 1 atm"
  }
  beta <- -7 * log10(pCO2)

  t_C <- 24775 / (alpha + beta + 36.05) - 273.15

  list(temperature_C = t_C, alpha = alpha, beta = beta, pCO2_atm = pCO2, pCO2_rule = rule)
}

#' Vectorized wrapper: apply dap_gas_geothermometer() row-wise to a data
#' frame of gas analyses.
#'
#' @param df Data frame with columns sample_id, CO2, H2S, H2, CH4 (mole %).
#' @return Tibble: sample_id, temperature_C, alpha, beta, pCO2_atm, pCO2_rule.
compute_dap_geothermometry <- function(df) {
  required <- c("sample_id", "CO2", "H2S", "H2", "CH4")
  missing_cols <- setdiff(required, names(df))
  if (length(missing_cols) > 0) stop("Missing required column(s): ", paste(missing_cols, collapse = ", "))

  results <- lapply(seq_len(nrow(df)), function(i) {
    row <- df[i, ]
    res <- tryCatch(
      dap_gas_geothermometer(row$CO2, row$H2S, row$H2, row$CH4),
      error = function(e) list(temperature_C = NA_real_, alpha = NA_real_, beta = NA_real_,
                                pCO2_atm = NA_real_, pCO2_rule = paste("error:", e$message))
    )
    tibble::tibble(sample_id = row$sample_id, temperature_C = res$temperature_C,
                   alpha = res$alpha, beta = res$beta, pCO2_atm = res$pCO2_atm,
                   pCO2_rule = res$pCO2_rule)
  })
  dplyr::bind_rows(results)
}

# =============================================================================
# SELF-TEST / LITERATURE VALIDATION
# =============================================================================

#' Validate dap_gas_geothermometer() against Mariner & Janik (1995) Table 2's
#' own published gas compositions and T-DP values for well 23-5 (the
#' hottest well in the field, sampled on four dates) -- real, cited,
#' published numbers transcribed directly from
#' docs/literature/"Geochem Data and concept model Mariner & Janik
#' 1995.pdf", not synthetic data. This is a genuine literature
#' cross-check, not just a syntax self-test: it is what confirmed the
#' alpha H2-term coefficient of 6 (not 1) above.
demo_gas_geothermometry <- function() {
  message("---- D'Amore-Panichi gas geothermometer: literature validation (Mariner & Janik 1995, Table 2, well 23-5) ----")

  # Columns: date, CO2, H2S, H2, CH4 (mole %), published T-DP (C).
  lit <- tibble::tribble(
    ~date,       ~CO2,  ~H2S,  ~H2,    ~CH4,    ~published_T_DP,
    "1991-11-05", 97.7, 1.04,  0.021,  0.0051,  174,
    "1993-01-27", 97.7, 1.02,  0.024,  0.0081,  173,
    "1993-08-02", 97.8, 1.00,  0.023,  0.0052,  175,
    "1994-07-25", 97.7, 1.01,  0.024,  0.0064,  175
  )

  lit <- lit |>
    mutate(sample_id = date) |>
    select(sample_id, date, CO2, H2S, H2, CH4, published_T_DP)

  computed <- compute_dap_geothermometry(lit)
  check <- lit |>
    left_join(computed |> select(sample_id, temperature_C), by = "sample_id") |>
    mutate(diff_C = temperature_C - published_T_DP)

  for (i in seq_len(nrow(check))) {
    r <- check[i, ]
    message(sprintf("  %s: computed T-DP = %.1fC, published T-DP = %dC (diff %.1fC)",
                     r$date, r$temperature_C, r$published_T_DP, r$diff_C))
  }

  ok <- all(abs(check$diff_C) < 2)
  message(sprintf("  Overall: %s (all differences < 2C)", if (ok) "PASS" else "FAIL"))

  invisible(check)
}
