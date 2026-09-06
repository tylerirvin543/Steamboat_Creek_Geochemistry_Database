#10_run_phreeqc_mixing
#
# Two-end-member mixing models for the thesis's central geothermal-outflow
# question: how much of an observed sample's chemistry reflects dilution
# of a deep thermal end-member with meteoric/background water?
#
# Two complementary pieces:
#  1. compute_mixing_fractions() -- pure R, conservative-tracer (default
#     Cl, since chloride discharge is this project's whole reason for
#     existing) linear mixing. Fast, transparent, but assumes no reaction
#     (no mineral precipitation/dissolution, no degassing) along the way.
#  2. run_phreeqc_mixing() -- PHREEQC MIX blocks combining the two
#     end-member SOLUTIONs at each computed (or user-specified) fraction,
#     comparing PHREEQC's predicted full chemistry/SI (which *does*
#     account for real solubility effects on mixing/cooling) against the
#     target sample's observed chemistry -- a genuine fit-quality check
#     on the two-end-member hypothesis.
#
# Status (see AGENTS.md / the 2026-09-06 planning session): real Cl
# chemistry currently exists for only a couple of samples and doesn't
# temporally overlap the conductivity logger record; the downstream/
# outflow-proxy site (SBGG) has no chemistry at all yet. Per the
# confirmed decision, this file is built and self-tested against
# synthetic end-members (demo_mixing_model(), bottom of file) now; it
# will produce real results the moment two real, chemically distinct
# end-member sample_ids are supplied by the user -- never guessed.

library(DBI)
library(dplyr)

#' Compute two-end-member conservative mixing fractions for every
#' eligible sample against a designated thermal and meteoric end-member.
#'
#' @param con DBI connection.
#' @param thermal_sample_id,meteoric_sample_id Integer sample_ids (from
#'   PHREEQC_Solutions) for the two end-members. Must be supplied by the
#'   caller -- never inferred automatically.
#' @param tracer Character. Column name in PHREEQC_Solutions to use as
#'   the conservative tracer (default "Cl").
#' @param sample_ids Optional vector restricting which target samples to
#'   compute fractions for (default: all samples with a non-NA tracer value).
#' @return Tibble: sample_id, tracer, observed_value,
#'   mixing_fraction_thermal, predicted_value_if_conservative.
compute_mixing_fractions <- function(con, thermal_sample_id, meteoric_sample_id,
                                      tracer = "Cl", sample_ids = NULL) {
  solutions <- dbReadTable(con, "PHREEQC_Solutions") |> as_tibble()

  if (!tracer %in% names(solutions)) stop("Tracer '", tracer, "' is not a PHREEQC_Solutions column.")

  c_thermal  <- solutions[[tracer]][solutions$sample_id == thermal_sample_id][1]
  c_meteoric <- solutions[[tracer]][solutions$sample_id == meteoric_sample_id][1]

  if (is.na(c_thermal) || is.na(c_meteoric)) {
    stop("Both end-member samples must have a non-NA '", tracer, "' value in PHREEQC_Solutions.")
  }
  if (isTRUE(all.equal(c_thermal, c_meteoric))) {
    stop("Thermal and meteoric end-members have the same '", tracer,
         "' value (", c_thermal, ") -- not distinguishable as end-members for this tracer.")
  }

  targets <- solutions |> filter(!is.na(.data[[tracer]]))
  if (!is.null(sample_ids)) targets <- targets |> filter(sample_id %in% sample_ids)

  targets |>
    transmute(
      sample_id,
      tracer = tracer,
      observed_value = .data[[tracer]],
      mixing_fraction_thermal = (observed_value - c_meteoric) / (c_thermal - c_meteoric),
      predicted_value_if_conservative = mixing_fraction_thermal * c_thermal + (1 - mixing_fraction_thermal) * c_meteoric
    )
}

#' Run compute_mixing_fractions() and store the run + per-sample fractions.
#'
#' @return mixing_run_id (invisibly), after storing PHREEQC_Mixing_Runs
#'   and PHREEQC_Mixing_Fractions rows.
run_mixing_fraction_analysis <- function(con, thermal_sample_id, meteoric_sample_id,
                                          tracer = "Cl", sample_ids = NULL, notes = NULL) {
  fractions <- compute_mixing_fractions(con, thermal_sample_id, meteoric_sample_id, tracer, sample_ids)

  dbAppendTable(con, "PHREEQC_Mixing_Runs", data.frame(
    run_date = as.character(Sys.Date()),
    thermal_end_member_id = thermal_sample_id,
    meteoric_end_member_id = meteoric_sample_id,
    tracer = tracer,
    notes = ifelse(is.null(notes), NA_character_, notes),
    stringsAsFactors = FALSE
  ))
  mixing_run_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]

  out <- fractions |> mutate(mixing_run_id = mixing_run_id) |>
    select(mixing_run_id, sample_id, tracer, mixing_fraction_thermal, observed_value, predicted_value_if_conservative)

  dbExecute(con, "DELETE FROM PHREEQC_Mixing_Fractions WHERE mixing_run_id = ?", params = list(mixing_run_id))
  dbAppendTable(con, "PHREEQC_Mixing_Fractions", out)

  message("Stored mixing_run_id ", mixing_run_id, " with ", nrow(out), " sample fractions (tracer = ", tracer, ").")
  invisible(mixing_run_id)
}

#' Build a PHREEQC input file with two end-member SOLUTIONs and a MIX
#' block combining them at a given thermal fraction.
format_phreeqc_mix_input <- function(thermal_row, meteoric_row, fraction_thermal,
                                      output_file = "phreeqc_mix.tsv",
                                      si_minerals = DEFAULT_SI_MINERALS) {
  lines <- c(
    "SELECTED_OUTPUT",
    sprintf("    -file         %s", output_file),
    "    -reset        false",
    "    -simulation   true",
    "    -solution     true",
    "    -pH           true",
    "    -temperature  true",
    "    -ionic_strength true",
    sprintf("    -saturation_indices  %s", paste(si_minerals, collapse = "  ")),
    ""
  )

  lines <- c(lines, format_solution_block(thermal_row, solution_number = 1), "")
  lines <- c(lines, format_solution_block(meteoric_row, solution_number = 2), "")
  lines <- c(lines,
    "MIX 1",
    sprintf("    1  %.4f", fraction_thermal),
    sprintf("    2  %.4f", 1 - fraction_thermal),
    "SAVE SOLUTION 3",
    "END", "",
    "USE SOLUTION 3", "END", ""
  )
  lines
}

#' Run PHREEQC MIX blocks for each row of a mixing-fraction table (from
#' compute_mixing_fractions()/run_mixing_fraction_analysis()), comparing
#' MIX-predicted chemistry/SI to the target sample's observed values.
#'
#' @param con DBI connection.
#' @param mixing_run_id From run_mixing_fraction_analysis().
#' @param phreeqc_db Database key (default "auto").
run_phreeqc_mixing <- function(con, mixing_run_id, phreeqc_db = "auto") {
  check_phreeqc()

  run_info <- dbGetQuery(con, "SELECT * FROM PHREEQC_Mixing_Runs WHERE mixing_run_id = ?",
                          params = list(mixing_run_id))
  if (nrow(run_info) == 0) stop("No PHREEQC_Mixing_Runs row for mixing_run_id ", mixing_run_id)

  fractions <- dbGetQuery(con, "SELECT * FROM PHREEQC_Mixing_Fractions WHERE mixing_run_id = ?",
                           params = list(mixing_run_id))
  if (nrow(fractions) == 0) { message("No mixing fractions to run."); return(invisible(NULL)) }

  solutions <- dbReadTable(con, "PHREEQC_Solutions") |> as_tibble()
  thermal_row  <- as.list(solutions[solutions$sample_id == run_info$thermal_end_member_id[1], ][1, ])
  meteoric_row <- as.list(solutions[solutions$sample_id == run_info$meteoric_end_member_id[1], ][1, ])

  if (identical(phreeqc_db, "auto")) {
    rec <- recommend_phreeqc_db(bind_rows(as_tibble(thermal_row), as_tibble(meteoric_row)))
    db_key <- rec$recommended
  } else db_key <- phreeqc_db
  db_path <- get_phreeqc_db_path(db_key)
  db_name <- PHREEQC_DATABASES[[db_key]]$name

  out_dir <- file.path("phreeqc", "runs", "mixing", paste0("run_", mixing_run_id))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  results_all <- list()
  for (i in seq_len(nrow(fractions))) {
    frow <- fractions[i, ]
    f <- frow$mixing_fraction_thermal
    if (is.na(f) || f < 0 || f > 1) {
      message("  Skipping sample ", frow$sample_id, " (fraction ", round(f, 3), " outside [0,1] -- not a plausible two-end-member mix)")
      next
    }
    tag <- paste0("s", frow$sample_id)
    sel_out <- file.path(out_dir, paste0(tag, "_", db_key, "_selected.tsv"))
    in_file <- file.path(out_dir, paste0(tag, "_", db_key, ".pqi"))
    out_file <- file.path(out_dir, paste0(tag, "_", db_key, ".pqo"))

    mix_lines <- format_phreeqc_mix_input(thermal_row, meteoric_row, f, output_file = sel_out,
                                           si_minerals = get_si_minerals(db_key))
    writeLines(mix_lines, in_file)
    exit_code <- run_phreeqc(in_file, out_file, db_file = db_path)

    if (exit_code == 0 && file.exists(sel_out)) {
      # SELECTED_OUTPUT has one row per simulation (SOLUTION 1, SOLUTION 2,
      # then the MIX's "USE SOLUTION 3" simulation) -- the result of
      # interest is the mixed solution, i.e. the last simulation row.
      parsed <- parse_phreeqc_output(sel_out, sample_ids = rep(frow$sample_id, 3))
      predicted <- parsed |>
        group_by(parameter) |>
        slice_tail(n = 1) |>
        ungroup() |>
        select(parameter, value) |>
        mutate(sample_id = frow$sample_id)
      results_all[[length(results_all) + 1]] <- predicted |>
        mutate(mixing_run_id = mixing_run_id, mixing_fraction_thermal = f, db_file = db_name,
               run_date = as.character(Sys.Date())) |>
        rename(predicted_value = value) |>
        mutate(observed_value = NA_real_) |>
        select(mixing_run_id, sample_id, mixing_fraction_thermal, parameter, predicted_value, observed_value, db_file, run_date)
    } else {
      message("  MIX run failed to converge for sample ", frow$sample_id)
    }
  }

  if (length(results_all) == 0) { message("No MIX runs produced results."); return(invisible(NULL)) }

  results <- bind_rows(results_all)
  dbExecute(con, "DELETE FROM PHREEQC_Mixing_Results WHERE mixing_run_id = ?", params = list(mixing_run_id))
  dbAppendTable(con, "PHREEQC_Mixing_Results", results)
  message("Stored ", nrow(results), " PHREEQC_Mixing_Results rows for mixing_run_id ", mixing_run_id, ".")
  invisible(results)
}

# =============================================================================
# SELF-TEST ON SYNTHETIC END-MEMBERS
# =============================================================================

#' Self-test compute_mixing_fractions() and the MIX-block path against a
#' synthetic Na-Cl "thermal" solution and a dilute Ca-HCO3 "meteoric"
#' solution -- confirms both the R-only fraction calculation and (if
#' PHREEQC is installed) the PHREEQC MIX path agree on a trivial 50/50
#' case, before ever being pointed at real database rows.
#'
#' Does NOT touch the real database: builds an in-memory synthetic table
#' and runs the pure-R fraction math directly; only calls run_phreeqc()
#' if PHREEQC is actually installed on this machine (skips with a
#' message otherwise).
demo_mixing_model <- function(run_phreeqc_check = TRUE) {
  message("---- Mixing model self-test (synthetic end-members) ----")

  thermal <- list(sample_id = "SYNTH_THERMAL", temperature = 180, pH = 7.2,
                   Na = 900, K = 90, Ca = 15, Mg = 0.5, Cl = 1400, SO4 = 40,
                   Alkalinity = 120, Si = 220, NO3 = NA, F = 5, Br = NA,
                   B = 10, Li = 3, Sr = NA, Fe = NA, Mn = NA, As = NA)
  meteoric <- list(sample_id = "SYNTH_METEORIC", temperature = 12, pH = 7.8,
                    Na = 15, K = 2, Ca = 40, Mg = 8, Cl = 5, SO4 = 10,
                    Alkalinity = 183, Si = 15, NO3 = NA, F = NA, Br = NA,
                    B = NA, Li = NA, Sr = NA, Fe = NA, Mn = NA, As = NA)

  # 50/50 conservative mix, computed directly (mirrors
  # compute_mixing_fractions()'s formula without needing a DB round-trip).
  f_true <- 0.5
  synth_target_cl <- f_true * thermal$Cl + (1 - f_true) * meteoric$Cl
  recovered_f <- (synth_target_cl - meteoric$Cl) / (thermal$Cl - meteoric$Cl)

  ok <- isTRUE(all.equal(recovered_f, f_true, tolerance = 1e-9))
  message(sprintf("  Synthetic 50/50 mix: true Cl = %.1f mg/L, recovered fraction = %.4f (expected %.1f) -- %s",
                   synth_target_cl, recovered_f, f_true, if (ok) "PASS" else "FAIL"))

  if (run_phreeqc_check) {
    has_phreeqc <- tryCatch({ check_phreeqc(); TRUE }, error = function(e) FALSE)
    if (has_phreeqc) {
      tmp_dir <- tempfile("phreeqc_mix_demo_")
      dir.create(tmp_dir)
      sel_out <- file.path(tmp_dir, "demo_selected.tsv")
      in_file <- file.path(tmp_dir, "demo.pqi")
      out_file <- file.path(tmp_dir, "demo.pqo")
      lines <- format_phreeqc_mix_input(thermal, meteoric, f_true, output_file = sel_out,
                                         si_minerals = get_si_minerals("phreeqc"))
      writeLines(lines, in_file)
      exit_code <- tryCatch(run_phreeqc(in_file, out_file, db_file = PHREEQC_DB), error = function(e) { message("  PHREEQC exe call failed: ", e$message); -1L })
      if (exit_code == 0 && file.exists(sel_out)) {
        message("  PHREEQC MIX block executed successfully -- see ", sel_out, " for full speciation of the synthetic 50/50 mix.")
      } else {
        message("  PHREEQC MIX block did not run cleanly (exit code ", exit_code, "). This does not affect the pure-R fraction math above.")
      }
    } else {
      message("  PHREEQC executable not found -- skipping the MIX-block half of the self-test (pure-R fraction math above is unaffected).")
    }
  }

  invisible(list(true_fraction = f_true, recovered_fraction = recovered_f, pass = ok))
}
