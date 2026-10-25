# ============================================================
# 15_gas_informed_parent_fluid.R
#
# Purpose:
# A first-pass "gas-informed parent-fluid" reconstruction for the
# Lower Sinter Terrace (LST): use the real NV26-1 free-gas composition
# (Fischer/Ruprecht UCSB, April 2026, paired with the fissure water
# sample 816/SBF_0001) to estimate what the thermal fluid looked like
# BEFORE boiling/steam loss stripped gas out of it and concentrated
# the residual liquid -- then use that reconstructed "parent" fluid,
# alongside the as-measured (degassed) fluid, as two alternative
# thermal end-members in this project's existing conservative-Cl
# mixing framework (10_run_phreeqc_mixing.R) and inverse-modeling
# framework (11_run_phreeqc_inverse.R), to see whether the choice of
# end-member meaningfully changes inferred mixing fractions/flow-path
# groupings across real LST samples.
#
# METHOD (explicitly a simplified, first-pass model -- not a finished
# geothermometric method; built per an explicit user decision
# [2026-10-24 session] to iterate on assumptions together):
#
# 1. STEAM-LOSS FRACTION (y): a standard single-step adiabatic
#    enthalpy-balance ("maximum steam loss") calculation --
#      y = (hf(T_reservoir) - hf(T_discharge)) / (hg(T_discharge) - hf(T_discharge))
#    where hf/hg are saturated-liquid/-vapor enthalpy (kJ/kg) from a
#    small, hardcoded steam-table lookup (see .STEAM_TABLE below).
#    T_reservoir is NOT taken from the quartz/chalcedony geothermometer
#    -- this project's own established finding (Session 16, AGENTS.md)
#    is that quartz/chalcedony come out BELOW measured discharge
#    temperature at Steamboat (silica re-equilibrates/dilutes on the
#    way up), which would give a physically invalid negative y. The
#    Giggenbach Na/K geothermometer, which DOES come out above measured
#    temperature here (also an established finding), is used instead.
#
# 2. CONSERVATIVE-SPECIES CONCENTRATION CORRECTION: boiling off a
#    vapor mass fraction y concentrates everything dissolved in the
#    residual liquid by a factor of 1/(1-y) -- so the PARENT (pre-
#    boiling) concentration of a conservative species is the measured
#    (post-boiling) concentration times (1-y), not divided by it:
#      C_parent = C_measured * (1 - y)
#    Applied to Cl, Na, K, SO4, B, Li, Br, F, Sr (the usual
#    conservative/near-conservative majors+traces already in
#    PHREEQC_Solutions). Alkalinity is also scaled this way as a
#    first-pass starting value, even though it is not strictly
#    conservative once gas is added back in step 3 -- PHREEQC's own
#    GAS_PHASE equilibration re-sets pH/carbonate speciation from
#    there, so this is only an initial condition, not the final
#    answer.
#
# 3. GAS ADD-BACK: a PHREEQC GAS_PHASE equilibration (fixed-pressure,
#    open system, mirroring run_phreeqc_gas_phase_fischer_pairing()'s
#    existing 10-mol convention) is run against the parent-fluid
#    SOLUTION, seeded with NV26-1's AIR-CORRECTED CO2:H2S molar
#    proportions (correct_gas_for_air()), at a total pressure equal to
#    the water's own saturation pressure AT the reservoir temperature
#    (from the same steam table) -- representing the elevated
#    confining pressure the parent fluid would experience at depth,
#    which lets far more CO2 stay dissolved than at 1 atm surface
#    conditions. This re-equilibrates pH and carbonate/sulfide
#    speciation; the resulting post-equilibration pH and saturation
#    indices are the reconstructed parent fluid's characterization.
#
# Known, stated simplifications (not resolved here): single-step
# (not multi-step/continuous) boiling; CO2/H2S assumed to partition
# essentially entirely into the escaping vapor during boiling (no
# vapor-liquid partition-coefficient treatment); the gas sample itself
# (NV26-1, collected ~2.5 months before the water sample at a point
# ~64 m away, per the existing SBF_0001 Location_Aliases note) is
# treated as representative of the SAME parent fluid as sample 816,
# not a simultaneous, co-located measurement.
# ============================================================

library(DBI)
library(dplyr)

# --- Small saturated-steam-table lookup (standard reference values) ---
# T (deg C), hf = saturated liquid enthalpy (kJ/kg),
# hg = saturated vapor enthalpy (kJ/kg), Psat = saturation pressure (atm).
.STEAM_TABLE <- data.frame(
  T    = c(25,    50,     75,     100,    125,    150,    175,    200,    225,    250),
  hf   = c(104.89,209.33, 313.93, 419.04, 524.99, 632.20, 741.17, 852.45, 966.78, 1085.36),
  hg   = c(2546.5,2592.1, 2635.3, 2676.1, 2713.5, 2746.4, 2773.6, 2793.7, 2803.8, 2800.4),
  Psat = c(0.0313,0.1217, 0.3855, 1.0,    2.321,  4.760,  8.924,  15.54,  25.50,  39.78)
)

#' Estimate the single-step ("maximum steam loss") vapor mass fraction
#' separated between a reservoir temperature and a lower discharge
#' temperature, from saturated-steam-table enthalpies.
#'
#' @return Named list: y (steam-loss fraction, 0-1), hf_reservoir,
#'   hf_discharge, hg_discharge (kJ/kg), and a `valid` flag (FALSE if
#'   T_reservoir_C <= T_discharge_C, which would imply no boiling).
estimate_steam_loss_fraction <- function(T_reservoir_C, T_discharge_C) {
  if (T_reservoir_C <= T_discharge_C) {
    warning("T_reservoir (", round(T_reservoir_C, 1), " C) is not above T_discharge (",
            round(T_discharge_C, 1), " C) -- no boiling implied; y set to 0.")
    return(list(y = 0, hf_reservoir = NA_real_, hf_discharge = NA_real_,
                hg_discharge = NA_real_, valid = FALSE))
  }
  hf_res  <- approx(.STEAM_TABLE$T, .STEAM_TABLE$hf, xout = T_reservoir_C, rule = 2)$y
  hf_dis  <- approx(.STEAM_TABLE$T, .STEAM_TABLE$hf, xout = T_discharge_C, rule = 2)$y
  hg_dis  <- approx(.STEAM_TABLE$T, .STEAM_TABLE$hg, xout = T_discharge_C, rule = 2)$y
  y <- (hf_res - hf_dis) / (hg_dis - hf_dis)
  y <- max(0, min(y, 0.9))  # clamp to a physically plausible range
  list(y = y, hf_reservoir = hf_res, hf_discharge = hf_dis, hg_discharge = hg_dis, valid = TRUE)
}

#' Interpolate saturation pressure (atm) at a given temperature from
#' the same steam table, for use as the GAS_PHASE's total pressure
#' (a stand-in for the elevated confining pressure at reservoir depth).
.saturation_pressure_atm <- function(T_C) {
  approx(.STEAM_TABLE$T, .STEAM_TABLE$Psat, xout = T_C, rule = 2)$y
}

#' Reconstruct a gas-informed "parent fluid" for a water sample paired
#' with a real free-gas analysis.
#'
#' @param con DBI connection.
#' @param water_sample_id sample_id already present in PHREEQC_Solutions
#'   (e.g. 816 = SBF_0001).
#' @param gas_sample_label Gas_Analyses.sample_label (e.g. "NV26-1").
#' @param reservoir_temp_source Data frame with columns sample_id,
#'   measured_temp_c, T_NaK_gigg_activity -- defaults to reading
#'   docs/data/geothermometer_by_site.csv if not supplied.
#' @param total_gas_moles Total GAS_PHASE moles (open-system buffer).
#'   Default NULL: scaled to each sample's own alkalinity (buffering
#'   capacity) via GAS_MOLES_PER_MOL_ALKALINITY, rather than a fixed
#'   value applied regardless of how much carbonate buffering a given
#'   fluid actually has -- calibrated so sample 816 (SBF_0001, this
#'   method's original/validated case) still gets ~10 mol, matching
#'   run_phreeqc_gas_phase_fischer_pairing()'s original convention.
#'   Pass a number directly to override this scaling.
#'   existing convention.
#' @param phreeqc_db "auto" or a specific database key.
#' @return A list with the parent-fluid row (named list, same shape as
#'   a PHREEQC_Solutions row), y, T_reservoir, T_discharge,
#'   reservoir_pressure_atm, post-equilibration pH/SI, and the raw
#'   comparison table (measured vs. parent for each conservative
#'   species).
reconstruct_parent_fluid <- function(con, water_sample_id = 816, gas_sample_label = "NV26-1",
                                      reservoir_temp_source = NULL, total_gas_moles = NULL,
                                      phreeqc_db = "auto") {
  check_phreeqc()

  solutions <- dbReadTable(con, "PHREEQC_Solutions") |> as_tibble()
  measured_row_df <- solutions |> filter(sample_id == water_sample_id)
  if (nrow(measured_row_df) == 0) stop("water_sample_id ", water_sample_id, " not found in PHREEQC_Solutions.")
  measured_row <- as.list(measured_row_df[1, ])

  if (is.null(reservoir_temp_source)) {
    geo_path <- "docs/data/geothermometer_by_site.csv"
    if (!file.exists(geo_path)) stop("No geothermometer_by_site.csv found at ", geo_path,
                                      " -- supply reservoir_temp_source directly.")
    reservoir_temp_source <- read.csv(geo_path, stringsAsFactors = FALSE)
  }
  geo_row <- reservoir_temp_source |> filter(sample_id == water_sample_id)
  if (nrow(geo_row) == 0) stop("sample_id ", water_sample_id, " has no geothermometer row -- cannot estimate T_reservoir.")
  T_discharge <- geo_row$measured_temp_c[1]
  T_reservoir <- geo_row$T_NaK_gigg_activity[1]

  steam <- estimate_steam_loss_fraction(T_reservoir, T_discharge)
  y <- steam$y

  gas_row <- dbGetQuery(con, "SELECT * FROM Gas_Analyses WHERE sample_label = ?", params = list(gas_sample_label))
  if (nrow(gas_row) == 0) stop("gas_sample_label '", gas_sample_label, "' not found in Gas_Analyses.")
  gas_df <- gas_row |>
    transmute(sample_label, CO2 = co2_mol_pct, He = he_mol_pct, H2 = h2_mol_pct,
              Ar = ar_mol_pct, O2 = o2_mol_pct, N2 = n2_mol_pct,
              CH4 = ch4_mol_pct, CO = co_mol_pct, H2S = h2s_mol_pct)
  source("scripts/analysis/gas_air_correction.R", local = TRUE)
  gas_corrected <- correct_gas_for_air(gas_df)
  co2_h2s_ratio <- gas_corrected$CO2_corrected[1] / gas_corrected$H2S_corrected[1]

  conservative_species <- c("Cl", "Na", "K", "SO4", "B", "Li", "Br", "F", "Sr", "Alkalinity")
  comparison <- lapply(conservative_species, function(s) {
    measured_val <- measured_row[[s]]
    parent_val <- if (!is.null(measured_val) && !is.na(measured_val)) measured_val * (1 - y) else NA_real_
    data.frame(species = s, measured = measured_val, parent = parent_val)
  }) |> bind_rows()

  parent_row <- measured_row
  for (s in conservative_species) {
    if (!is.null(parent_row[[s]]) && !is.na(parent_row[[s]])) parent_row[[s]] <- parent_row[[s]] * (1 - y)
  }
  parent_row$temperature <- T_reservoir
  parent_row$sample_id <- paste0("PARENT_", water_sample_id)

  # Scale the imposed gas load to this sample's own buffering
  # capacity (alkalinity), rather than applying the same fixed total
  # regardless of fluid -- a real limitation flagged after finding
  # (2026-10-24) that the resort-tank sample's divergent/non-
  # convergent gas-equilibration result traced to its own higher
  # starting pH, not database choice or a fixed-gas-moles artifact;
  # scaling here is a genuine methodological improvement regardless.
  GAS_MOLES_PER_MOL_ALKALINITY <- 2131.97  # calibrated so sample 816's own real alkalinity (post-steam-loss) gives ~10 mol, this method's original/validated case
  parent_alkalinity_mol <- if (!is.null(parent_row$Alkalinity) && !is.na(parent_row$Alkalinity)) parent_row$Alkalinity / 61017 else NA_real_
  if (is.null(total_gas_moles)) {
    if (is.na(parent_alkalinity_mol)) {
      warning("No parent-fluid Alkalinity available to scale the gas load -- falling back to the fixed 10 mol default.")
      total_gas_moles <- 10
    } else {
      total_gas_moles <- GAS_MOLES_PER_MOL_ALKALINITY * parent_alkalinity_mol
    }
  }
  h2s_moles <- total_gas_moles / (co2_h2s_ratio + 1)
  co2_moles <- total_gas_moles - h2s_moles

  reservoir_pressure_atm <- .saturation_pressure_atm(T_reservoir)

  if (identical(phreeqc_db, "auto")) {
    rec <- recommend_phreeqc_db(as_tibble(parent_row))
    db_key <- rec$recommended
  } else db_key <- phreeqc_db
  db_path <- get_phreeqc_db_path(db_key)

  out_dir <- file.path("phreeqc", "runs", "parent_fluid", paste0("water_", water_sample_id, "_", db_key))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  in_file <- file.path(out_dir, "parent_fluid.pqi")
  out_file <- file.path(out_dir, "parent_fluid.pqo")
  selected_file <- file.path(out_dir, "parent_fluid_selected.tsv")

  lines <- format_phreeqc_gas_phase_input(
    parent_row, gas_components = c("CO2(g)", "H2S(g)"),
    gas_phase_type = "fixed_pressure", total_pressure_atm = reservoir_pressure_atm,
    output_file = selected_file, si_minerals = get_si_minerals(db_key),
    initial_moles = c("CO2(g)" = co2_moles, "H2S(g)" = h2s_moles)
  )
  writeLines(lines, in_file)
  exit_code <- run_phreeqc(in_file, out_file, db_file = db_path)
  convergence_status <- if (exit_code == 0) "converged" else "failed_to_converge"
  if (exit_code != 0) {
    err_lines <- tryCatch(tail(readLines(out_file, warn = FALSE), 5), error = function(e) character())
    message("[parent fluid] PHREEQC gas-phase equilibration FAILED for water_sample_id=", water_sample_id,
            " (db=", db_key, "). Last lines of .pqo:\n  ", paste(err_lines, collapse = "\n  "))
  }

  result_row <- list(pH_final = NA_real_, SI = tibble::tibble())
  if (exit_code == 0 && file.exists(selected_file)) {
    sel <- tryCatch(read.delim(selected_file, sep = "\t", stringsAsFactors = FALSE, check.names = FALSE),
                     error = function(e) NULL)
    if (!is.null(sel) && nrow(sel) > 0) {
      last_row <- sel[nrow(sel), ]
      ph_col <- grep("^pH$", names(last_row), value = TRUE)
      if (length(ph_col) > 0) result_row$pH_final <- as.numeric(last_row[[ph_col[1]]])
      si_cols <- grep("^si_", names(last_row), ignore.case = TRUE, value = TRUE)
      if (length(si_cols) > 0) {
        result_row$SI <- tibble::tibble(
          mineral = sub("^si_", "", si_cols, ignore.case = TRUE),
          SI = as.numeric(unlist(last_row[si_cols]))
        )
      }
    }
  } else {
    message("[parent fluid] PHREEQC gas-phase equilibration did not produce usable SELECTED_OUTPUT -- pH/SI left NA; conservative-species reconstruction is still valid.")
  }

  list(
    water_sample_id = water_sample_id,
    gas_sample_label = gas_sample_label,
    T_discharge_C = T_discharge,
    T_reservoir_C = T_reservoir,
    steam_loss_fraction = y,
    reservoir_pressure_atm = reservoir_pressure_atm,
    co2_h2s_ratio_air_corrected = co2_h2s_ratio,
    parent_row = parent_row,
    measured_row = measured_row,
    comparison = comparison,
    pH_measured = measured_row$pH,
    pH_parent = result_row$pH_final,
    SI_parent = result_row$SI,
    db_key = db_key,
    charge_balance_pct_measured = measured_row$charge_balance,
    convergence_status = convergence_status,
    exit_code = exit_code
  )
}


#' Reconstruct parent fluids for BOTH real LST water samples that have
#' complete major-ion chemistry (fissure=816, resort=815), using the
#' SAME gas composition (NV26-1, the only real gas sample on file) for
#' both -- an explicit, stated assumption that both discharge points
#' draw on gas from the same deep source, since no gas sample exists
#' at the resort tank itself. Returns both reconstructions plus a
#' direct side-by-side comparison, to test whether the two
#' independently measured, nearby LST discharges converge toward a
#' common parent fluid once each is corrected back toward its own
#' reservoir temperature.
compare_fissure_and_resort_parents <- function(con, gas_sample_label = "NV26-1") {
  pf_fissure <- reconstruct_parent_fluid(con, water_sample_id = 816, gas_sample_label = gas_sample_label)
  pf_resort  <- reconstruct_parent_fluid(con, water_sample_id = 815, gas_sample_label = gas_sample_label)

  conservative_species <- c("Cl", "Na", "K", "SO4", "B", "Li", "Br", "F", "Sr", "Alkalinity")
  side_by_side <- lapply(conservative_species, function(s) {
    data.frame(
      species = s,
      fissure_measured = pf_fissure$measured_row[[s]],
      fissure_parent = pf_fissure$parent_row[[s]],
      resort_measured = pf_resort$measured_row[[s]],
      resort_parent = pf_resort$parent_row[[s]]
    )
  }) |> dplyr::bind_rows()
  side_by_side$pct_diff_parent <- 100 * (side_by_side$fissure_parent - side_by_side$resort_parent) /
    pmax(side_by_side$fissure_parent, side_by_side$resort_parent)

  diagnostics <- data.frame(
    water_sample_id = c(816, 815),
    location = c("SBF_0001 (fissure)", "SBW_0002 (resort tank)"),
    T_discharge_C = c(pf_fissure$T_discharge_C, pf_resort$T_discharge_C),
    T_reservoir_C = c(pf_fissure$T_reservoir_C, pf_resort$T_reservoir_C),
    steam_loss_fraction = c(pf_fissure$steam_loss_fraction, pf_resort$steam_loss_fraction),
    reservoir_pressure_atm = c(pf_fissure$reservoir_pressure_atm, pf_resort$reservoir_pressure_atm),
    phreeqc_database = c(pf_fissure$db_key, pf_resort$db_key),
    charge_balance_pct = c(pf_fissure$charge_balance_pct_measured, pf_resort$charge_balance_pct_measured),
    gas_equilibration_convergence = c(pf_fissure$convergence_status, pf_resort$convergence_status),
    pH_measured = c(pf_fissure$pH_measured, pf_resort$pH_measured),
    pH_parent_reequilibrated = c(pf_fissure$pH_parent, pf_resort$pH_parent)
  )

  list(pf_fissure = pf_fissure, pf_resort = pf_resort, side_by_side = side_by_side, diagnostics = diagnostics)
}
#' Compare conservative-Cl mixing fractions for a set of real target
#' samples using the as-measured thermal end-member vs. the
#' reconstructed parent-fluid end-member, against a fixed meteoric
#' end-member.
#'
#' @param con DBI connection.
#' @param parent_result Output of reconstruct_parent_fluid().
#' @param meteoric_sample_id sample_id for the meteoric end-member
#'   (default 829, Boyd Domestic Well).
#' @param target_sample_ids Integer vector of real target sample_ids.
#' @return Tibble: one row per target, with Cl_target, Cl_meteoric,
#'   Cl_measured_thermal, Cl_parent_thermal, f_measured, f_parent,
#'   delta_f (parent minus measured).
compare_parent_vs_measured_mixing <- function(con, parent_result, meteoric_sample_id = 829,
                                               target_sample_ids) {
  solutions <- dbReadTable(con, "PHREEQC_Solutions") |> as_tibble()
  cl_meteoric <- solutions$Cl[solutions$sample_id == meteoric_sample_id][1]
  cl_measured_thermal <- parent_result$measured_row$Cl
  cl_parent_thermal <- parent_result$parent_row$Cl

  names_lookup <- dbGetQuery(con, "
    SELECT s.sample_id, l.name FROM Samples s JOIN Locations l ON s.location_id = l.location_id
  ")

  rows <- lapply(target_sample_ids, function(sid) {
    cl_target <- solutions$Cl[solutions$sample_id == sid][1]
    if (length(cl_target) == 0 || is.na(cl_target)) {
      cl_target_raw <- dbGetQuery(con, "SELECT value FROM Lab_Analyses WHERE sample_id = ? AND analyte = 'Cl'", params = list(sid))
      cl_target <- if (nrow(cl_target_raw) > 0) cl_target_raw$value[1] else NA_real_
    }
    nm <- names_lookup$name[names_lookup$sample_id == sid][1]
    f_measured <- (cl_target - cl_meteoric) / (cl_measured_thermal - cl_meteoric)
    f_parent <- (cl_target - cl_meteoric) / (cl_parent_thermal - cl_meteoric)
    data.frame(
      sample_id = sid, location_name = nm, Cl_target = cl_target,
      Cl_meteoric = cl_meteoric, Cl_measured_thermal = cl_measured_thermal,
      Cl_parent_thermal = cl_parent_thermal,
      f_thermal_measured = f_measured, f_thermal_parent = f_parent,
      delta_f = f_parent - f_measured
    )
  })
  bind_rows(rows)
}

#' Run PHREEQC inverse modeling with the reconstructed parent fluid as
#' an end-member (alongside the meteoric end-member) against a real
#' target sample -- a lighter-weight variant of run_phreeqc_inverse()
#' that doesn't require the synthetic parent fluid to have its own
#' sample_id/PHREEQC_Solutions row (it has neither).
run_inverse_with_parent_fluid <- function(con, parent_result, target_sample_id,
                                           meteoric_sample_id = 829,
                                           phases = c("Calcite", "Quartz", "Chalcedony"),
                                           uncertainty_pct = 10) {
  check_phreeqc()
  solutions <- dbReadTable(con, "PHREEQC_Solutions") |> as_tibble()
  target_row <- as.list(solutions |> filter(sample_id == target_sample_id) |> slice(1))
  meteoric_row <- as.list(solutions |> filter(sample_id == meteoric_sample_id) |> slice(1))
  end_member_rows <- list(parent_result$parent_row, meteoric_row)

  all_rows <- c(list(target_row), end_member_rows)
  all_rows <- lapply(all_rows, function(r) { r$sample_id <- as.character(r$sample_id); r })
  rec <- recommend_phreeqc_db(bind_rows(lapply(all_rows, as_tibble)))
  db_path <- get_phreeqc_db_path(rec$recommended)

  out_dir <- file.path("phreeqc", "runs", "parent_fluid_inverse", paste0("target_", target_sample_id))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  in_file <- file.path(out_dir, "inverse.pqi")
  out_file <- file.path(out_dir, "inverse.pqo")

  lines <- format_phreeqc_inverse_input(target_row, end_member_rows, phases, uncertainty_pct)
  writeLines(lines, in_file)
  exit_code <- run_phreeqc(in_file, out_file, db_file = db_path)
  if (exit_code != 0) {
    warning("PHREEQC inverse model (parent-fluid end-member) did not converge for target ", target_sample_id, ".")
    return(invisible(tibble::tibble()))
  }
  parsed <- parse_phreeqc_inverse_output(out_file)
  parsed
}

#' End-to-end driver: reconstruct the parent fluid for sample 816 +
#' NV26-1, compare mixing fractions for the real LST target samples
#' currently on file, write derived CSV outputs + a comparison figure.
run_parent_fluid_analysis <- function(con,
    water_sample_id = 816, gas_sample_label = "NV26-1",
    meteoric_sample_id = 829,
    target_sample_ids = c(815, 821, 1603),   # SBW_0002, SBW_0001, GS-1 (2026-10-24 ingest)
    out_dir = "data/derived/phreeqc") {

  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  pf <- reconstruct_parent_fluid(con, water_sample_id, gas_sample_label)
  message(sprintf(
    "[parent fluid] T_discharge=%.1f C, T_reservoir(Na/K Giggenbach)=%.1f C, steam-loss fraction y=%.3f, reservoir pressure=%.2f atm",
    pf$T_discharge_C, pf$T_reservoir_C, pf$steam_loss_fraction, pf$reservoir_pressure_atm))

  comparison_path <- file.path(out_dir, "parent_fluid_reconstruction.csv")
  write.csv(pf$comparison, comparison_path, row.names = FALSE)

  mixing_comparison <- compare_parent_vs_measured_mixing(con, pf, meteoric_sample_id, target_sample_ids)
  mixing_path <- file.path(out_dir, "parent_fluid_mixing_comparison.csv")
  write.csv(mixing_comparison, mixing_path, row.names = FALSE)

  si_path <- file.path(out_dir, "parent_fluid_saturation_indices.csv")
  if (nrow(pf$SI_parent) > 0) write.csv(pf$SI_parent, si_path, row.names = FALSE)

  message("[parent fluid] Wrote: ", comparison_path, ", ", mixing_path,
          if (nrow(pf$SI_parent) > 0) paste0(", ", si_path) else "")
  message("[parent fluid] pH: measured=", round(pf$pH_measured, 2),
          ", parent (re-gassed, reservoir T/P)=", if (!is.na(pf$pH_parent)) round(pf$pH_parent, 2) else "NA")

  both <- compare_fissure_and_resort_parents(con, gas_sample_label)
  diag_path <- file.path(out_dir, "parent_fluid_diagnostics.csv")
  write.csv(both$diagnostics, diag_path, row.names = FALSE)
  side_by_side_path <- file.path(out_dir, "parent_fluid_fissure_vs_resort.csv")
  write.csv(both$side_by_side, side_by_side_path, row.names = FALSE)
  message("[parent fluid] Fissure-vs-resort parent comparison written to: ", side_by_side_path)
  message("[parent fluid] Run diagnostics (PHREEQC database, charge balance, convergence) written to: ", diag_path)

  invisible(list(parent_fluid = pf, mixing_comparison = mixing_comparison, fissure_vs_resort = both))
}
