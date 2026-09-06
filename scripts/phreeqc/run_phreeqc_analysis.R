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

#' Run every self-test (mixing, inverse, gas phase) against synthetic
#' data -- confirms the whole PHREEQC modeling layer is wired up
#' correctly without touching the real database or requiring real
#' overlapping end-member chemistry to exist yet.
demo_phreeqc_analysis <- function() {
  message("\n======================================")
  message(" PHREEQC modeling self-tests (synthetic)")
  message("======================================")
  mix_result <- demo_mixing_model()
  inv_result <- demo_inverse_model()
  gas_result <- demo_gas_phase()
  invisible(list(mixing = mix_result, inverse = inv_result, gas_phase = gas_result))
}
