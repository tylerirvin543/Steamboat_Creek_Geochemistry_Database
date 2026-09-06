#run_phreeqc_analysis
#
# Single entry point sequencing the PHREEQC modeling stages, mirroring
# run_sampling_frequency.R's idempotent, explicit-argument philosophy:
# never silently fabricates end-member choices, phase lists, or
# thresholds, and never guesses which samples are "the" thermal or
# meteoric end-member.
#
# `speciation` and `temp_sweep` are cheap enough (no required extra
# arguments beyond an optional site_type filter) that run_pipeline.R
# calls them automatically when RUN_ANALYSIS$phreeqc is TRUE. `mixing`,
# `inverse`, and `gas_phase` require the caller to name real sample_ids
# and stay manual-invocation-only, matching how promote_staged_ndep.R
# and similar human-in-the-loop steps in this project work.
#
# Usage:
#   run_phreeqc_analysis_pipeline(con, mode = "speciation")
#   run_phreeqc_analysis_pipeline(con, mode = "temp_sweep", temp_range = c(25, 300))
#   run_phreeqc_analysis_pipeline(con, mode = "mixing",
#     thermal_sample_id = 12, meteoric_sample_id = 45, tracer = "Cl")
#   run_phreeqc_analysis_pipeline(con, mode = "inverse",
#     target_sample_id = 88, end_member_sample_ids = c(12, 45),
#     phases = c("Calcite", "Quartz"))
#   run_phreeqc_analysis_pipeline(con, mode = "gas_phase",
#     sample_ids = c(12, 45), gas_components = c("CO2(g)", "H2S(g)"))

library(DBI)

library(dplyr)

# =============================================================================
# USER-FRIENDLY AUTOMATION LAYER (2026-09-06)
# =============================================================================
# Two pieces make the PHREEQC stage practical to leave switched on in
# run_pipeline.R rather than something that has to be manually invoked
# and manually decided every time:
#
#  1. should_rerun_phreeqc() -- speciation/SI is cheap to check but
#     re-running it on literally every pipeline execution wastes time
#     once real chemistry stops changing run-to-run. This compares the
#     current PHREEQC-eligible sample set (get_phreeqc_eligible()) to
#     what PHREEQC_Pipeline_State recorded last time and reports
#     whether anything changed -- never guesses; a genuinely unchanged
#     eligible set is skipped, and run_pipeline.R prints exactly why.
#  2. run_phreeqc_mixing_from_config() / run_phreeqc_inverse_from_config()
#     / run_phreeqc_gas_phase_from_config() -- mixing/inverse/gas-phase
#     modeling still require a human to name real end-member sample_ids
#     (never inferred automatically -- see each mode's own docstring
#     above), but previously the *only* way to run them was editing R
#     code directly. These three functions instead read a plain CSV
#     (data/raw/phreeqc/{mixing,inverse,gas_phase}_config.csv) with an
#     `enabled` column, so a user can add/toggle a row without touching
#     any script, and run_pipeline.R can safely call all three every
#     run (rows with enabled != TRUE are just skipped).

#' Compare the current PHREEQC-eligible sample set to what
#' PHREEQC_Pipeline_State recorded on the last automatic run.
#'
#' @return list(should_rerun = logical, reason = character,
#'   current_count, current_max_id, last_count, last_max_id).
should_rerun_phreeqc <- function(con, site_type = NULL) {
  eligible <- get_phreeqc_eligible(con, site_type = site_type)$eligible
  current_count <- nrow(eligible)
  current_max_id <- if (current_count > 0) max(eligible$sample_id) else 0L

  state <- dbGetQuery(con, "SELECT * FROM PHREEQC_Pipeline_State WHERE state_id = 1")

  if (nrow(state) == 0) {
    return(list(should_rerun = TRUE, reason = "No prior run recorded.",
                current_count = current_count, current_max_id = current_max_id,
                last_count = NA_integer_, last_max_id = NA_integer_))
  }

  changed <- !identical(current_count, state$last_eligible_count[1]) ||
             !identical(current_max_id, state$last_max_sample_id[1])

  reason <- if (changed) {
    sprintf("Eligible sample set changed since last run (was %s samples / max sample_id %s, now %d / %d).",
            state$last_eligible_count[1], state$last_max_sample_id[1], current_count, current_max_id)
  } else {
    sprintf("No change since last run (%d eligible samples, last run %s).",
            current_count, state$last_run_at[1])
  }

  list(should_rerun = changed, reason = reason,
       current_count = current_count, current_max_id = current_max_id,
       last_count = state$last_eligible_count[1], last_max_id = state$last_max_sample_id[1])
}

#' Record the state should_rerun_phreeqc() will compare against next time.
record_phreeqc_run_state <- function(con, current_count, current_max_id) {
  dbExecute(con, "DELETE FROM PHREEQC_Pipeline_State WHERE state_id = 1")
  dbExecute(con, "
    INSERT INTO PHREEQC_Pipeline_State (state_id, last_run_at, last_eligible_count, last_max_sample_id)
    VALUES (1, ?, ?, ?)
  ", params = list(as.character(Sys.time()), current_count, current_max_id))
}

#' Ensure a config CSV exists with a documented header-only template,
#' mirroring this project's other data/raw/*.csv config-file convention
#' (e.g. dhakal_well_network.csv) -- never fabricates a data row, only
#' the column headers + an explanatory comment line.
.ensure_phreeqc_config_csv <- function(path, header_line, comment_line) {
  if (!file.exists(path)) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeLines(c(comment_line, header_line), path)
    message("  Created empty config template: ", path)
  }
}

#' Read a PHREEQC config CSV, tolerating a leading '#'-commented line
#' (readr::read_csv's `comment` argument) and filtering to enabled rows.
.read_phreeqc_config <- function(path) {
  if (!file.exists(path)) return(NULL)
  df <- tryCatch(readr::read_csv(path, comment = "#", show_col_types = FALSE), error = function(e) NULL)
  if (is.null(df) || nrow(df) == 0) return(NULL)
  if (!"enabled" %in% names(df)) { warning("  Config CSV ", path, " has no 'enabled' column -- skipping."); return(NULL) }
  df |> mutate(enabled = toupper(trimws(as.character(enabled))) %in% c("TRUE", "T", "1", "YES")) |> filter(enabled)
}

#' Run every enabled row of data/raw/phreeqc/mixing_config.csv
#' (columns: label, thermal_sample_id, meteoric_sample_id, tracer,
#' enabled, notes). Creates a header-only template on first use.
run_phreeqc_mixing_from_config <- function(con, csv = "data/raw/phreeqc/mixing_config.csv", phreeqc_db = "auto") {
  .ensure_phreeqc_config_csv(csv,
    "label,thermal_sample_id,meteoric_sample_id,tracer,enabled,notes",
    "# One row per mixing run you want run_pipeline.R (RUN_ANALYSIS$phreeqc_mixing = TRUE) to execute automatically. sample_ids are real Samples.sample_id values -- never guessed. Set enabled=TRUE to activate a row; leave FALSE/blank to keep it defined but skipped.")
  rows <- .read_phreeqc_config(csv)
  if (is.null(rows)) { message("[PHREEQC mixing] No enabled rows in ", csv, " -- nothing to run."); return(invisible(NULL)) }
  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    message("[PHREEQC mixing] Running config row '", r$label, "' (thermal=", r$thermal_sample_id, ", meteoric=", r$meteoric_sample_id, ", tracer=", r$tracer, ")")
    tryCatch({
      mixing_run_id <- run_mixing_fraction_analysis(con, r$thermal_sample_id, r$meteoric_sample_id, tracer = r$tracer)
      run_phreeqc_mixing(con, mixing_run_id, phreeqc_db = phreeqc_db)
    }, error = function(e) message("  [ERROR] config row '", r$label, "' failed: ", conditionMessage(e)))
  }
}

#' Run every enabled row of data/raw/phreeqc/inverse_config.csv
#' (columns: label, target_sample_id, end_member_sample_ids [semicolon-
#' separated], phases [semicolon-separated], uncertainty_pct, enabled, notes).
run_phreeqc_inverse_from_config <- function(con, csv = "data/raw/phreeqc/inverse_config.csv", phreeqc_db = "auto") {
  .ensure_phreeqc_config_csv(csv,
    "label,target_sample_id,end_member_sample_ids,phases,uncertainty_pct,enabled,notes",
    "# One row per inverse model you want run_pipeline.R (RUN_ANALYSIS$phreeqc_inverse = TRUE) to execute automatically. end_member_sample_ids and phases are semicolon-separated (e.g. \"12;45\" and \"Calcite;Quartz\"). sample_ids are real Samples.sample_id values -- never guessed.")
  rows <- .read_phreeqc_config(csv)
  if (is.null(rows)) { message("[PHREEQC inverse] No enabled rows in ", csv, " -- nothing to run."); return(invisible(NULL)) }
  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    end_members <- as.integer(strsplit(as.character(r$end_member_sample_ids), ";")[[1]])
    phases <- trimws(strsplit(as.character(r$phases), ";")[[1]])
    message("[PHREEQC inverse] Running config row '", r$label, "' (target=", r$target_sample_id, ", end members=", paste(end_members, collapse = ","), ")")
    tryCatch({
      run_phreeqc_inverse(con, r$target_sample_id, end_members, phases = phases,
                          uncertainty_pct = if (!is.na(r$uncertainty_pct)) r$uncertainty_pct else 5, phreeqc_db = phreeqc_db)
    }, error = function(e) message("  [ERROR] config row '", r$label, "' failed: ", conditionMessage(e)))
  }
}

#' Run every enabled row of data/raw/phreeqc/gas_phase_config.csv
#' (columns: label, sample_ids [semicolon-separated], gas_components
#' [semicolon-separated], gas_phase_type, total_pressure_atm,
#' volume_liters, enabled, notes).
run_phreeqc_gas_phase_from_config <- function(con, csv = "data/raw/phreeqc/gas_phase_config.csv", phreeqc_db = "auto") {
  .ensure_phreeqc_config_csv(csv,
    "label,sample_ids,gas_components,gas_phase_type,total_pressure_atm,volume_liters,enabled,notes",
    "# One row per gas-phase run you want run_pipeline.R (RUN_ANALYSIS$phreeqc_gas_phase = TRUE) to execute automatically. sample_ids and gas_components are semicolon-separated (e.g. \"12;45\" and \"CO2(g);H2S(g)\"). gas_phase_type is fixed_pressure or fixed_volume.")
  rows <- .read_phreeqc_config(csv)
  if (is.null(rows)) { message("[PHREEQC gas phase] No enabled rows in ", csv, " -- nothing to run."); return(invisible(NULL)) }
  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    sample_ids <- as.integer(strsplit(as.character(r$sample_ids), ";")[[1]])
    gas_components <- trimws(strsplit(as.character(r$gas_components), ";")[[1]])
    message("[PHREEQC gas phase] Running config row '", r$label, "' (samples=", paste(sample_ids, collapse = ","), ", gases=", paste(gas_components, collapse = ","), ")")
    tryCatch({
      run_phreeqc_gas_phase(con, sample_ids, gas_components = gas_components,
                            gas_phase_type = if (!is.na(r$gas_phase_type)) r$gas_phase_type else "fixed_pressure",
                            total_pressure_atm = if (!is.na(r$total_pressure_atm)) r$total_pressure_atm else 1.0,
                            volume_liters = if (!is.na(r$volume_liters)) r$volume_liters else 1.0,
                            phreeqc_db = phreeqc_db)
    }, error = function(e) message("  [ERROR] config row '", r$label, "' failed: ", conditionMessage(e)))
  }
}

run_phreeqc_analysis_pipeline <- function(con, mode = c("speciation", "temp_sweep", "mixing", "inverse", "gas_phase"),
                                           site_type = NULL, sample_ids = NULL, phreeqc_db = "auto",
                                           # mixing
                                           thermal_sample_id = NULL, meteoric_sample_id = NULL, tracer = "Cl",
                                           # inverse
                                           target_sample_id = NULL, end_member_sample_ids = NULL,
                                           phases = c("Calcite", "Quartz", "Chalcedony"), uncertainty_pct = 5,
                                           # gas phase
                                           gas_components = c("CO2(g)", "H2S(g)"),
                                           gas_phase_type = c("fixed_pressure", "fixed_volume"),
                                           total_pressure_atm = 1.0, volume_liters = 1.0,
                                           # temp sweep
                                           temp_range = c(25, 300), temp_step = 25) {
  mode <- match.arg(mode)
  gas_phase_type <- match.arg(gas_phase_type)

  # Always (re)build PHREEQC_Solutions first so every mode operates on
  # current chemistry, regardless of what else has been ingested since
  # the last run.
  build_phreeqc_solutions(con)

  switch(mode,
    speciation = {
      run_phreeqc_pipeline(con, site_type = site_type, sample_ids = sample_ids, phreeqc_db = phreeqc_db)
    },
    temp_sweep = {
      run_phreeqc_temp_sweep(con, site_type = site_type, phreeqc_db = phreeqc_db,
                              temp_range = temp_range, temp_step = temp_step, sample_ids = sample_ids)
    },
    mixing = {
      if (is.null(thermal_sample_id) || is.null(meteoric_sample_id)) {
        stop("mode = 'mixing' requires thermal_sample_id and meteoric_sample_id ",
             "(real Samples.sample_id values) -- these are never inferred automatically. ",
             "See AGENTS.md for current chemistry-coverage status before choosing end-members.")
      }
      mixing_run_id <- run_mixing_fraction_analysis(con, thermal_sample_id, meteoric_sample_id,
                                                     tracer = tracer, sample_ids = sample_ids)
      run_phreeqc_mixing(con, mixing_run_id, phreeqc_db = phreeqc_db)
    },
    inverse = {
      if (is.null(target_sample_id) || is.null(end_member_sample_ids)) {
        stop("mode = 'inverse' requires target_sample_id and end_member_sample_ids ",
             "(real Samples.sample_id values) -- these are never inferred automatically.")
      }
      run_phreeqc_inverse(con, target_sample_id, end_member_sample_ids, phases = phases,
                          uncertainty_pct = uncertainty_pct, phreeqc_db = phreeqc_db)
    },
    gas_phase = {
      if (is.null(sample_ids)) {
        stop("mode = 'gas_phase' requires sample_ids -- these are never inferred automatically.")
      }
      run_phreeqc_gas_phase(con, sample_ids, gas_components = gas_components, gas_phase_type = gas_phase_type,
                            total_pressure_atm = total_pressure_atm, volume_liters = volume_liters,
                            phreeqc_db = phreeqc_db)
    }
  )
}

#' Run every self-test (mixing, inverse, gas phase, gas geothermometry,
#' gas mixing) against synthetic/literature data -- confirms the whole
#' PHREEQC modeling layer is wired up correctly without touching the
#' real database or requiring real overlapping end-member chemistry to
#' exist yet. The gas geothermometry/mixing checks (added 2026-09-06,
#' ahead of the planned UCSB/Fischer gas-sampling data) validate against
#' real, cited Mariner & Janik (1995) numbers rather than synthetic data
#' -- see scripts/phreeqc/13_gas_geothermometry.R and 14_gas_mixing.R.
demo_phreeqc_analysis <- function() {
  message("\n======================================")
  message(" PHREEQC modeling self-tests (synthetic)")
  message("======================================")
  mix_result <- demo_mixing_model()
  inv_result <- demo_inverse_model()
  gas_result <- demo_gas_phase()
  geotherm_result <- demo_gas_geothermometry()
  gas_mix_result <- demo_gas_mixing()
  invisible(list(mixing = mix_result, inverse = inv_result, gas_phase = gas_result,
                  gas_geothermometry = geotherm_result, gas_mixing = gas_mix_result))
}
