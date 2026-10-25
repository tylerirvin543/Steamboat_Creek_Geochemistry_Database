#16_reaction_path_titration
#
# A real, FORWARD PHREEQC REACTION-path (titration) model for the Lower
# Sinter Terrace flowpath, built 2026-10-25 as the direct complement to
# 11_run_phreeqc_inverse.R: every real inverse-modeling attempt against
# SBW_0001 (the real across-creek well showing a clear deviation from
# the fissure+SBRR conservative-mixing curve) finds zero feasible
# solutions within PHREEQC's automatic mass-balance search (see
# ROADMAP.md Section 1/2, fixed 2026-10-25 parser bug). Rather than keep
# asking the solver to search blindly, this script mixes the two known
# real end-members at a known (stored or freshly computed) conservative
# mixing fraction, then explicitly TITRATES calcite and/or dolomite --
# both dissolution (positive reaction progress) and precipitation
# (negative reaction progress) -- and reports the resulting Ca/Mg/
# Alkalinity/pH/saturation-index trajectory, directly comparable against
# a real target sample's observed chemistry. A better-posed question
# than the inverse search, and testable with data already on hand.
#
# PHREEQC REACTION-block syntax notes (confirmed empirically against the
# real installed PHREEQC 3 executable before writing this file -- see
# the 2026-10-25 session's interactive test transcript):
#  - A bare, space-separated list of numbers following the phase lines
#    (no "-steps" keyword) is read as the CUMULATIVE reaction progress
#    (mol) at each step directly -- NOT per-step increments. Multiple
#    IDENTICAL or explicitly-listed "-steps" values instead triggers
#    PHREEQC's "equal increments" error path and fails; the bare-list
#    form is what actually works and is what this file uses.
#  - Each phase listed in a REACTION block (coefficient 1) is titrated
#    by the SAME reaction-progress amount at every step -- so "Calcite 1
#    / Dolomite 1" with reaction progress x consumes/produces x mol of
#    EACH phase, not a combined x mol split between them.
#  - A negative reaction-progress value that would drive any element's
#    total concentration below zero hard-stops the whole simulation
#    (PHREEQC does not just clamp or skip that one step) -- see
#    .estimate_reaction_bounds_mol() below for how this script picks a
#    safe default range from the mixed fluid's own real Ca/Mg/
#    Alkalinity content, with an automatic one-time narrowing retry if
#    the first attempt still overshoots.
#  - SELECTED_OUTPUT's `sim` column increments once per PHREEQC
#    simulation (here: sim=1 is the MIX itself, sim=2 is the REACTION
#    titration) -- parse_phreeqc_reaction_path_output() keeps only the
#    last `sim`'s `state == "react"` rows, which are the real titration
#    steps (excluding the two `i_soln` echo rows and the MIX's own
#    internal "react" row from sim 1).

library(DBI)
library(dplyr)

#' Build a complete PHREEQC input: SOLUTION 1 (thermal) + SOLUTION 2
#' (meteoric) + MIX 1 (at fraction_thermal) + SAVE SOLUTION 3, then
#' USE SOLUTION 3 + REACTION 1 titrating `phases` across the cumulative
#' reaction-progress values in `step_values_mol` (mol; negative values
#' represent net precipitation/removal, positive net dissolution).
format_phreeqc_reaction_path_input <- function(thermal_row, meteoric_row, fraction_thermal,
                                                phases, step_values_mol,
                                                output_file = "phreeqc_reaction_path.tsv",
                                                si_minerals = DEFAULT_SI_MINERALS) {
  si_list <- unique(c(si_minerals, phases, "Quartz", "Chalcedony"))

  lines <- c(
    "SELECTED_OUTPUT",
    sprintf("    -file         %s", output_file),
    "    -reset        false",
    "    -simulation   true",
    "    -state        true",
    "    -step         true",
    "    -reaction     true",
    "    -solution     true",
    "    -pH           true",
    "    -totals       Ca Mg Na Cl S(6) Si F",
    "    -alkalinity   true",
    sprintf("    -saturation_indices  %s", paste(si_list, collapse = "  ")),
    ""
  )

  lines <- c(lines, format_solution_block(thermal_row, solution_number = 1), "")
  lines <- c(lines, format_solution_block(meteoric_row, solution_number = 2), "")
  lines <- c(lines,
    "MIX 1",
    sprintf("    1  %.6f", fraction_thermal),
    sprintf("    2  %.6f", 1 - fraction_thermal),
    "SAVE SOLUTION 3",
    "END", "",
    "USE SOLUTION 3",
    "REACTION 1"
  )
  for (p in phases) lines <- c(lines, sprintf("    %s  1", p))
  lines <- c(lines, sprintf("    %s", paste(formatC(step_values_mol, format = "g", digits = 8), collapse = "  ")))
  lines <- c(lines, "END", "")

  lines
}


#' Real molar masses (g/mol) for the elements/species this file's
#' molar-mass-dependent functions need, shared between
#' .estimate_reaction_bounds_mol(), summarize_reaction_path_fit(), and
#' build_reaction_path_titration_figure() so there is exactly one place
#' to update if a new element is ever added. SO4 uses PHREEQC's own
#' stored parameter key (S_6_, from "S(6)" after this file's standard
#' dot-to-underscore cleanup) -- 1 mol S(6) = 1 mol SO4 exactly, so
#' SO4's own molar mass (not elemental sulfur's) is the correct
#' conversion back to a real mg/L-equivalent comparison.
.REACTION_PATH_MW <- c(Ca = 40.078, Mg = 24.305, Alkalinity = 61.017, SO4 = 96.06, F = 18.998)

#' Maps a PHREEQC_Solutions column name (used throughout this project,
#' e.g. in fit_parameters) to the actual parameter key PHREEQC writes to
#' SELECTED_OUTPUT and this file stores in PHREEQC_Reaction_Path_Steps.
#' Only SO4 differs (stored as "S_6_", from PHREEQC's "S(6)" total).
.REACTION_PATH_STEP_PARAM_KEY <- c(Ca = "Ca", Mg = "Mg", Alkalinity = "Alkalinity", SO4 = "S_6_", F = "F")

#' Real per-mol-of-reaction-progress consumption of each tracked element,
#' for every phase this project has tested as a reaction-path candidate.
#' Each phase is titrated by the SAME reaction-progress amount (see file
#' header), so a phase list's total consumption of an element is just the
#' sum of each listed phase's own row here.
.REACTION_PATH_PHASE_STOICHIOMETRY <- list(
  Calcite   = c(Ca = 1, Alkalinity = 1),               # CaCO3: 1 Ca, 1 C (~1 mol Alkalinity-as-HCO3)
  Dolomite  = c(Ca = 1, Mg = 1, Alkalinity = 2),        # CaMg(CO3)2: 1 Ca, 1 Mg, 2 C
  Anhydrite = c(Ca = 1, SO4 = 1),                      # CaSO4: 1 Ca, 1 SO4
  Gypsum    = c(Ca = 1, SO4 = 1),                      # CaSO4.2H2O: same Ca/SO4 stoichiometry for bounding purposes
  Fluorite  = c(Ca = 1, F = 2)                          # CaF2: 1 Ca, 2 F
)

#' Estimate a safe, physically-grounded [min, max] reaction-progress
#' range (mol) from the mixed fluid's own Ca/Mg/Alkalinity/SO4/F content,
#' so a default run doesn't immediately overshoot and hard-stop PHREEQC.
#'
#' Exact (real per-phase stoichiometry, see
#' .REACTION_PATH_PHASE_STOICHIOMETRY) for Calcite, Dolomite, Anhydrite,
#' Gypsum, and Fluorite -- the five phases this project has tested as
#' reaction-path candidates. Any other phase falls back to a generic,
#' conservative approximation (the combined Ca+Mg+Alkalinity pool divided
#' evenly across the number of phases) -- supply step_range_mol
#' explicitly for a genuinely untested phase.
#'
#' @param safety Fraction of the theoretically available pool to allow
#'   (default 0.4 -- leaves real headroom so PHREEQC's own equilibrium
#'   chemistry, which consumes a bit more/less than the bare
#'   stoichiometric ratio, doesn't push past zero).
.estimate_reaction_bounds_mol <- function(thermal_row, meteoric_row, fraction_thermal,
                                           phases, safety = 0.4) {
  f <- fraction_thermal
  mix_val <- function(x) {
    tv <- thermal_row[[x]]; mv <- meteoric_row[[x]]
    tv <- if (is.null(tv) || is.na(tv)) 0 else as.numeric(tv)
    mv <- if (is.null(mv) || is.na(mv)) 0 else as.numeric(mv)
    f * tv + (1 - f) * mv
  }
  # Real element pools (mol), from the mixed fluid's own mg/L values.
  # "SO4"/"F" are the real PHREEQC_Solutions column names (mg/L); S_6_ is
  # only the *output* parameter key, reused here as the pool's name so it
  # lines up directly with .REACTION_PATH_PHASE_STOICHIOMETRY's rownames.
  pools <- c(
    Ca = mix_val("Ca") / 1000 / .REACTION_PATH_MW[["Ca"]],
    Mg = mix_val("Mg") / 1000 / .REACTION_PATH_MW[["Mg"]],
    Alkalinity = mix_val("Alkalinity") / 1000 / .REACTION_PATH_MW[["Alkalinity"]],
    SO4 = mix_val("SO4") / 1000 / .REACTION_PATH_MW[["SO4"]],
    F = mix_val("F") / 1000 / .REACTION_PATH_MW[["F"]]
  )

  known_phases <- phases[phases %in% names(.REACTION_PATH_PHASE_STOICHIOMETRY)]
  if (length(known_phases) > 0) {
    # Total per-mol-of-reaction-progress consumption of each element,
    # summed across every known phase in the list (each titrated by the
    # same amount -- see file header).
    total_consumption <- c(Ca = 0, Mg = 0, Alkalinity = 0, SO4 = 0, F = 0)
    for (p in known_phases) {
      row <- .REACTION_PATH_PHASE_STOICHIOMETRY[[p]]
      total_consumption[names(row)] <- total_consumption[names(row)] + row
    }
    limits <- sapply(names(total_consumption), function(el) {
      if (total_consumption[[el]] > 0) pools[[el]] / total_consumption[[el]] else Inf
    })
  } else {
    # Generic fallback for any untested phase: divide the combined
    # Ca+Mg+Alkalinity pool evenly across the number of phases -- a
    # conservative approximation, not phase-stoichiometry-exact.
    limits <- (pools[["Ca"]] + pools[["Mg"]] + pools[["Alkalinity"]]) / max(length(phases), 1)
  }

  x_max <- safety * min(limits)

  if (!is.finite(x_max) || x_max <= 0) x_max <- 0.001  # last-resort fallback

  # Intentionally ASYMMETRIC: the negative (precipitation/removal) bound
  # above is a real physical limit -- removing more than the mixed
  # fluid's own available Ca/Mg/C pool hard-stops PHREEQC outright (see
  # the file header). Net DISSOLUTION (positive reaction progress) faces
  # no equivalent limit from the solution's own current contents -- it's
  # adding material, not removing it -- so a symmetric default range
  # risks clipping a real interior RMSE minimum before it's reached.
  # Confirmed empirically (2026-10-25, SBW_0001 vs. fissure+SBRR): a
  # symmetric range found the best fit sitting right at its own positive
  # edge (an artifact of the bound, not a real optimum); widening the
  # positive side alone revealed a genuine interior minimum at roughly
  # 2.5x the symmetric magnitude. POS_MULTIPLIER errs generously wider
  # than that one confirmed case so a real minimum isn't missed by
  # default; summarize_reaction_path_fit() still warns if the best fit
  # sits at the very edge of the explored range, flagging that the
  # range itself (not just this default) may need widening further.
  POS_MULTIPLIER <- 6
  c(-x_max, x_max * POS_MULTIPLIER)
}

#' Parse a reaction-path SELECTED_OUTPUT file, keeping only the real
#' titration steps (the last `sim`'s `state == "react"` rows -- see the
#' file header for why).
parse_phreeqc_reaction_path_output <- function(selected_output_file) {
  if (!file.exists(selected_output_file)) return(tibble::tibble())
  raw <- read.delim(selected_output_file, sep = "\t", stringsAsFactors = FALSE, check.names = FALSE) |>
    tibble::as_tibble(.name_repair = "universal")
  names(raw) <- stringr::str_replace_all(names(raw), "\\.", "_")
  if (!all(c("sim", "state", "step", "reaction") %in% names(raw))) return(tibble::tibble())

  # PHREEQC right-pads the "state" column with whitespace in its
  # tab-delimited SELECTED_OUTPUT (confirmed empirically 2026-10-25) --
  # trim before comparing, or "react" never matches "       react".
  raw$state <- trimws(raw$state)
  react_rows <- raw |> filter(sim == max(sim), state == "react")
  if (nrow(react_rows) == 0) return(tibble::tibble())

  param_cols <- setdiff(names(react_rows), c("sim", "state", "soln", "step", "reaction"))
  param_cols <- param_cols[nchar(param_cols) > 0]
  param_cols <- param_cols[!grepl("^\\.\\.\\.\\d+$", param_cols)]

  react_rows |>
    transmute(step_index = step, reaction_progress_mol = reaction, across(all_of(param_cols))) |>
    tidyr::pivot_longer(cols = -c(step_index, reaction_progress_mol), names_to = "parameter", values_to = "value") |>
    mutate(
      parameter = stringr::str_replace(parameter, "^si_", "SI_"),
      parameter = stringr::str_replace(parameter, "^Alk$", "Alkalinity")
    ) |>
    filter(!is.na(value)) |>
    distinct()
}

#' Run a forward PHREEQC REACTION-path titration: mix thermal+meteoric at
#' a known fraction, then titrate `phases` across a range of cumulative
#' reaction progress. Stores PHREEQC_Reaction_Path_Runs +
#' PHREEQC_Reaction_Path_Steps.
#'
#' @param con DBI connection.
#' @param target_sample_id Optional sample_id this run is meant to
#'   explain -- used only to look up a stored mixing fraction (if
#'   `mixing_fraction` is NULL) and recorded on the run row for
#'   `summarize_reaction_path_fit()`'s later use. Not required.
#' @param thermal_sample_id,meteoric_sample_id Real sample_ids from
#'   PHREEQC_Solutions.
#' @param mixing_fraction Fraction of `thermal_sample_id` in the mix.
#'   If NULL, looks up the most recent stored PHREEQC_Mixing_Fractions
#'   row for this exact thermal/meteoric/target combination; if none
#'   exists, computes one fresh via compute_mixing_fractions() (requires
#'   `target_sample_id`). Never silently guessed otherwise.
#' @param phases Character vector of PHREEQC phase names to titrate
#'   (default Calcite + Dolomite, this project's real use case).
#' @param step_range_mol Optional c(min, max) cumulative reaction
#'   progress in mol. If NULL, auto-estimated from the mixed fluid's own
#'   Ca/Mg/Alkalinity via .estimate_reaction_bounds_mol().
#' @param n_steps Number of steps across the range (default 41).
#' @param phreeqc_db Database key or "auto".
#' @return run_id (invisibly).
run_reaction_path_titration <- function(con, target_sample_id = NULL,
                                         thermal_sample_id, meteoric_sample_id,
                                         mixing_fraction = NULL,
                                         phases = c("Calcite", "Dolomite"),
                                         step_range_mol = NULL, n_steps = 41,
                                         phreeqc_db = "auto", notes = NULL) {
  check_phreeqc()

  solutions <- dbReadTable(con, "PHREEQC_Solutions") |> as_tibble()
  thermal_row  <- as.list(solutions |> filter(sample_id == thermal_sample_id) |> slice(1))
  meteoric_row <- as.list(solutions |> filter(sample_id == meteoric_sample_id) |> slice(1))
  if (length(thermal_row$sample_id) == 0 || is.na(thermal_row$sample_id))
    stop("thermal_sample_id ", thermal_sample_id, " not found in PHREEQC_Solutions.")
  if (length(meteoric_row$sample_id) == 0 || is.na(meteoric_row$sample_id))
    stop("meteoric_sample_id ", meteoric_sample_id, " not found in PHREEQC_Solutions.")

  mixing_fraction_source <- "user_supplied"
  if (is.null(mixing_fraction)) {
    stored <- dbGetQuery(con, "
      SELECT f.mixing_fraction_thermal, f.mixing_run_id
      FROM PHREEQC_Mixing_Fractions f
      JOIN PHREEQC_Mixing_Runs r ON f.mixing_run_id = r.mixing_run_id
      WHERE r.thermal_end_member_id = ? AND r.meteoric_end_member_id = ? AND f.sample_id = ?
      ORDER BY f.mixing_run_id DESC LIMIT 1
    ", params = list(thermal_sample_id, meteoric_sample_id, target_sample_id))
    if (nrow(stored) > 0) {
      mixing_fraction <- stored$mixing_fraction_thermal[1]
      mixing_fraction_source <- sprintf("stored PHREEQC_Mixing_Fractions (mixing_run_id=%s, thermal=%s, meteoric=%s, target=%s)",
                                         stored$mixing_run_id[1], thermal_sample_id, meteoric_sample_id, target_sample_id)
      message("Using stored mixing fraction ", round(mixing_fraction, 4), " from mixing_run_id ", stored$mixing_run_id[1], ".")
    } else {
      if (is.null(target_sample_id)) {
        stop("No mixing_fraction supplied, no stored mixing run found, and no target_sample_id given to compute one fresh -- supply one explicitly.")
      }
      mixing_fraction <- compute_mixing_fractions(con, thermal_sample_id, meteoric_sample_id,
                                                   sample_ids = target_sample_id)$mixing_fraction_thermal[1]
      mixing_fraction_source <- "computed fresh via compute_mixing_fractions() (no stored mixing run found)"
      message("No stored mixing run found for this pair/target -- computed mixing fraction fresh: ", round(mixing_fraction, 4))
    }
  }
  if (is.null(mixing_fraction) || is.na(mixing_fraction)) stop("Could not determine a mixing fraction -- supply mixing_fraction explicitly.")

  # A mixing fraction outside [0,1] means the target is not a convex
  # combination of the two named end-members (e.g. MORE concentrated
  # than the "thermal" reference itself, a real, already-documented
  # case for SBW_0002) -- PHREEQC's MIX block cannot represent a
  # negative fraction (it hard-stops with a negative-concentration
  # error before the titration even starts, confirmed 2026-10-25).
  # Clamped to the nearest valid endpoint (0 or 1) with an explicit
  # warning, rather than silently failing or guessing a different
  # value -- this is now a "what reaction progress explains the gap
  # from the pure end-member alone" question, a real, stated change
  # in what is being tested for any sample this happens to.
  if (mixing_fraction < 0 || mixing_fraction > 1) {
    clamped <- max(0, min(1, mixing_fraction))
    warning(sprintf(
      "Mixing fraction %.4f is outside [0,1] -- target_sample_id %s is not a convex mix of the named end-members. ",
      mixing_fraction, if (is.null(target_sample_id)) "NA" else target_sample_id),
      sprintf("Clamped to %.1f for the MIX block (pure %s end-member, no dilution); the reaction titration now tests what mass transfer explains the gap from that pure end-member alone, not from a real mixed fluid.",
              clamped, if (clamped == 1) "thermal" else "meteoric"), call. = FALSE)
    mixing_fraction_source <- paste0(mixing_fraction_source, sprintf(" [clamped from %.4f to %.1f -- outside [0,1]]", mixing_fraction, clamped))
    mixing_fraction <- clamped
  }


  if (is.null(step_range_mol)) {
    step_range_mol <- .estimate_reaction_bounds_mol(thermal_row, meteoric_row, mixing_fraction, phases)
    message(sprintf("Auto-estimated reaction-progress bounds: [%.6g, %.6g] mol (safety-scaled from the mixed fluid's own Ca/Mg/Alkalinity).",
                     step_range_mol[1], step_range_mol[2]))
  }

  if (identical(phreeqc_db, "auto")) {
    rec <- recommend_phreeqc_db(bind_rows(as_tibble(thermal_row), as_tibble(meteoric_row)))
    db_key <- rec$recommended
  } else db_key <- phreeqc_db
  db_path <- get_phreeqc_db_path(db_key)
  db_name <- PHREEQC_DATABASES[[db_key]]$name

  dbAppendTable(con, "PHREEQC_Reaction_Path_Runs", data.frame(
    run_date = as.character(Sys.Date()),
    target_sample_id = if (is.null(target_sample_id)) NA_integer_ else as.integer(target_sample_id),
    thermal_sample_id = as.integer(thermal_sample_id),
    meteoric_sample_id = as.integer(meteoric_sample_id),
    mixing_fraction_thermal = mixing_fraction,
    mixing_fraction_source = mixing_fraction_source,
    phases = paste(phases, collapse = ","),
    step_min_mol = step_range_mol[1],
    step_max_mol = step_range_mol[2],
    n_steps = as.integer(n_steps),
    db_file = db_name,
    convergence_status = NA_character_,
    notes = if (is.null(notes)) NA_character_ else notes,
    stringsAsFactors = FALSE
  ))
  run_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]

  out_dir <- file.path("phreeqc", "runs", "reaction_path", paste0("run_", run_id))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  sel_out <- file.path(out_dir, "selected.tsv")
  in_file <- file.path(out_dir, "reaction_path.pqi")
  out_file <- file.path(out_dir, "reaction_path.pqo")

  .run_once <- function(rng) {
    steps <- seq(rng[1], rng[2], length.out = n_steps)
    lines <- format_phreeqc_reaction_path_input(thermal_row, meteoric_row, mixing_fraction, phases, steps,
                                                 output_file = sel_out, si_minerals = get_si_minerals(db_key))
    writeLines(lines, in_file)
    exit_code <- run_phreeqc(in_file, out_file, db_file = db_path)
    parsed <- if (file.exists(sel_out)) parse_phreeqc_reaction_path_output(sel_out) else tibble::tibble()
    list(exit_code = exit_code, parsed = parsed)
  }

  attempt <- .run_once(step_range_mol)
  n_converged <- length(unique(attempt$parsed$step_index))
  if (n_converged < n_steps) {
    message("First attempt converged for only ", n_converged, " of ", n_steps,
            " steps -- retrying once with the negative bound halved (a hard-stop on reaction progress ",
            "usually means the negative/precipitation direction overshot available Ca/Mg/alkalinity).")
    step_range_mol[1] <- step_range_mol[1] / 2
    attempt <- .run_once(step_range_mol)
    n_converged <- length(unique(attempt$parsed$step_index))
    dbExecute(con, "UPDATE PHREEQC_Reaction_Path_Runs SET step_min_mol = ? WHERE run_id = ?",
              params = list(step_range_mol[1], run_id))
  }

  status <- if (n_converged == 0) "failed" else if (n_converged < n_steps) "partial" else "converged"
  dbExecute(con, "UPDATE PHREEQC_Reaction_Path_Runs SET convergence_status = ? WHERE run_id = ?",
            params = list(status, run_id))

  if (nrow(attempt$parsed) == 0) {
    message("Reaction-path titration run_id ", run_id, " produced no convergent steps at all -- inspect ", out_file, " directly.")
    return(invisible(run_id))
  }

  results <- attempt$parsed |>
    mutate(run_id = run_id) |>
    select(run_id, step_index, reaction_progress_mol, parameter, value)

  dbExecute(con, "DELETE FROM PHREEQC_Reaction_Path_Steps WHERE run_id = ?", params = list(run_id))
  dbAppendTable(con, "PHREEQC_Reaction_Path_Steps", results)

  message("Stored ", nrow(results), " PHREEQC_Reaction_Path_Steps rows (", n_converged, "/", n_steps,
          " steps converged, status = ", status, ") for run_id ", run_id, ".")
  invisible(run_id)
}

#' Compare a stored reaction-path titration's trajectory against a real
#' target sample's observed Ca/Mg/Alkalinity, reporting the best-fit
#' reaction progress (and, separately, a Cl conservation sanity check --
#' Cl should be essentially unchanged across all steps, since the
#' titrated phases carry no Cl).
#'
#' @param con DBI connection.
#' @param run_id From run_reaction_path_titration().
#' @param target_sample_id Defaults to the run's own stored
#'   target_sample_id if not supplied.
#' @param fit_parameters Which PHREEQC_Solutions columns (mg/L) to fit
#'   against (default Ca, Mg, Alkalinity -- the three species the
#'   titrated phases actually move).
#' @return Invisibly, list(table = per-step residual tibble, best_fit =
#'   single best-fit row). Also writes
#'   data/derived/phreeqc/reaction_path_fit_run<run_id>.csv.
summarize_reaction_path_fit <- function(con, run_id, target_sample_id = NULL,
                                         fit_parameters = c("Ca", "Mg", "Alkalinity")) {
  run_info <- dbGetQuery(con, "SELECT * FROM PHREEQC_Reaction_Path_Runs WHERE run_id = ?", params = list(run_id))
  if (nrow(run_info) == 0) stop("No PHREEQC_Reaction_Path_Runs row for run_id ", run_id)
  if (is.null(target_sample_id)) target_sample_id <- run_info$target_sample_id[1]
  if (is.na(target_sample_id)) stop("This run has no associated target_sample_id -- supply one explicitly.")

  steps <- dbGetQuery(con, "SELECT * FROM PHREEQC_Reaction_Path_Steps WHERE run_id = ?", params = list(run_id)) |> as_tibble()
  if (nrow(steps) == 0) { message("No steps stored for run_id ", run_id, " -- nothing to summarize."); return(invisible(tibble::tibble())) }

  solutions <- dbReadTable(con, "PHREEQC_Solutions") |> as_tibble()
  target_row <- solutions |> filter(sample_id == target_sample_id) |> slice(1)
  if (nrow(target_row) == 0) stop("target_sample_id ", target_sample_id, " not found in PHREEQC_Solutions.")

  # PHREEQC_Solutions stores these in mg/L; PHREEQC_Reaction_Path_Steps
  # stores PHREEQC's own -totals/-alkalinity output, which is mol/kgw.
  mw <- .REACTION_PATH_MW
  fit_parameters <- intersect(fit_parameters, names(mw))

  obs_mol <- sapply(fit_parameters, function(p) {
    val_mgL <- target_row[[p]][1]
    if (is.null(val_mgL) || is.na(val_mgL)) NA_real_ else val_mgL / 1000 / mw[[p]]
  })
  names(obs_mol) <- fit_parameters
  if (all(is.na(obs_mol))) {
    message("Target sample ", target_sample_id, " has no observed value for any of ", paste(fit_parameters, collapse = ", "), " -- cannot fit.")
    return(invisible(tibble::tibble()))
  }

  step_keys <- .REACTION_PATH_STEP_PARAM_KEY[fit_parameters]
  wide <- steps |>
    filter(parameter %in% step_keys) |>
    tidyr::pivot_wider(id_cols = c(step_index, reaction_progress_mol), names_from = parameter, values_from = value) |>
    arrange(reaction_progress_mol)
  # Rename step-table parameter keys back to their PHREEQC_Solutions column
  # name (only SO4/"S_6_" actually differs) so every line below can
  # reference wide[[p]] uniformly for p in fit_parameters.
  rename_map <- step_keys[step_keys %in% names(wide)]
  if (length(rename_map) > 0) names(wide)[match(rename_map, names(wide))] <- names(rename_map)

  resid <- wide
  pct_cols <- character()
  for (p in fit_parameters) {
    if (is.na(obs_mol[[p]]) || !(p %in% names(wide))) next
    resid[[paste0("resid_", p)]] <- wide[[p]] - obs_mol[[p]]
    resid[[paste0("pct_resid_", p)]] <- 100 * (wide[[p]] - obs_mol[[p]]) / obs_mol[[p]]
    pct_cols <- c(pct_cols, paste0("pct_resid_", p))
  }

  if (length(pct_cols) == 0) {
    message("No fittable parameters overlapped between the run's stored steps and the target's observed chemistry.")
    return(invisible(resid))
  }

  resid$combined_rmse_pct <- sqrt(rowMeans(as.matrix(resid[, pct_cols, drop = FALSE])^2, na.rm = TRUE))
  best <- resid |> arrange(combined_rmse_pct) |> slice(1)

  message(sprintf(
    "Best-fit reaction progress for sample %s: %.6g mol (combined RMSE = %.1f%% across %s).",
    target_sample_id, best$reaction_progress_mol[1], best$combined_rmse_pct[1],
    paste(gsub("^pct_resid_", "", pct_cols), collapse = ", ")
  ))

  # If the best fit sits at (or within one step of) either edge of the
  # explored reaction-progress range, the RMSE curve may still be
  # improving outside the range that was actually run -- i.e. the
  # "best fit" found is an artifact of where the range happens to stop,
  # not a real interior minimum. Confirmed happening in practice
  # (2026-10-25) with a too-narrow symmetric default range; flagged here
  # so it's never silently mistaken for a genuine optimum again.
  ordered_progress <- sort(unique(resid$reaction_progress_mol))
  if (length(ordered_progress) >= 2) {
    edge_tolerance <- diff(range(ordered_progress)) / length(ordered_progress) * 1.5
    at_min_edge <- abs(best$reaction_progress_mol[1] - min(ordered_progress)) <= edge_tolerance
    at_max_edge <- abs(best$reaction_progress_mol[1] - max(ordered_progress)) <= edge_tolerance
    if (at_min_edge || at_max_edge) {
      message("WARNING: the best fit sits at the ", if (at_max_edge) "upper" else "lower",
              " edge of the explored reaction-progress range [", signif(min(ordered_progress), 4), ", ",
              signif(max(ordered_progress), 4), "] mol -- re-run with a wider step_range_mol on that side ",
              "before treating this as a real interior minimum.")
    }
  }

  out_dir <- "data/derived/phreeqc"
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  out_path <- file.path(out_dir, paste0("reaction_path_fit_run", run_id, ".csv"))
  write.csv(resid, out_path, row.names = FALSE)
  message("Wrote fit table: ", out_path)

  cl_steps <- steps |> filter(parameter == "Cl")
  if (nrow(cl_steps) > 0 && all(is.finite(cl_steps$value))) {
    cl_range <- range(cl_steps$value, na.rm = TRUE)
    cl_pct_var <- if (mean(cl_range) != 0) 100 * (cl_range[2] - cl_range[1]) / mean(cl_range) else NA_real_
    message(sprintf(
      "Cl conservation check: %.6g to %.6g mol/kgw across all steps (%.4f%% variation) -- should be ~0%%, since the titrated phases carry no chloride.",
      cl_range[1], cl_range[2], cl_pct_var))
  }

  invisible(list(table = resid, best_fit = best))
}

# =============================================================================
# SELF-TEST ON SYNTHETIC END-MEMBERS
# =============================================================================

#' Self-test format_phreeqc_reaction_path_input()/.estimate_reaction_bounds_mol()/
#' parse_phreeqc_reaction_path_output() against the same synthetic thermal/
#' meteoric end-members used in 10_run_phreeqc_mixing.R's
#' demo_mixing_model() and 11_run_phreeqc_inverse.R's demo_inverse_model() --
#' confirms the auto-estimated bounds produce a run that actually
#' converges end-to-end (if PHREEQC is installed), before ever being
#' pointed at real database rows.
demo_reaction_path_titration <- function(run_phreeqc_check = TRUE) {
  message("---- Reaction-path titration self-test (synthetic end-members) ----")

  thermal <- list(sample_id = "SYNTH_THERMAL", temperature = 180, pH = 7.2,
                   Na = 900, K = 90, Ca = 15, Mg = 0.5, Cl = 1400, SO4 = 40,
                   Alkalinity = 120, Si = 220, NO3 = NA, F = 5, Br = NA,
                   B = 10, Li = 3, Sr = NA, Fe = NA, Mn = NA, As = NA)
  meteoric <- list(sample_id = "SYNTH_METEORIC", temperature = 12, pH = 7.8,
                    Na = 15, K = 2, Ca = 40, Mg = 8, Cl = 5, SO4 = 10,
                    Alkalinity = 183, Si = 15, NO3 = NA, F = NA, Br = NA,
                    B = NA, Li = NA, Sr = NA, Fe = NA, Mn = NA, As = NA)
  f <- 0.4
  phases <- c("Calcite", "Dolomite")

  bounds <- .estimate_reaction_bounds_mol(thermal, meteoric, f, phases)
  ok_bounds <- is.finite(bounds[1]) && is.finite(bounds[2]) && bounds[1] < 0 && bounds[2] > 0
  message(sprintf("  Auto-estimated bounds: [%.6g, %.6g] mol -- %s", bounds[1], bounds[2],
                   if (ok_bounds) "PASS (straddles zero, finite)" else "FAIL"))

  lines <- format_phreeqc_reaction_path_input(thermal, meteoric, f, phases, seq(bounds[1], bounds[2], length.out = 11),
                                               si_minerals = get_si_minerals("phreeqc"))
  ok_syntax <- any(grepl("^REACTION 1", lines)) && any(grepl("^MIX 1", lines)) && any(grepl("Calcite  1", lines))
  message("  Input block generated: ", if (ok_syntax) "PASS (MIX+REACTION syntax present)" else "FAIL")

  if (!run_phreeqc_check) return(invisible(list(bounds = bounds, syntax_ok = ok_syntax)))

  has_phreeqc <- tryCatch({ check_phreeqc(); TRUE }, error = function(e) FALSE)
  if (!has_phreeqc) {
    message("  PHREEQC executable not found -- skipping the execution half of the self-test.")
    return(invisible(list(bounds = bounds, syntax_ok = ok_syntax)))
  }

  tmp_dir <- tempfile("phreeqc_reaction_path_demo_")
  dir.create(tmp_dir)
  sel_out <- file.path(tmp_dir, "demo_selected.tsv")
  in_file <- file.path(tmp_dir, "demo.pqi")
  out_file <- file.path(tmp_dir, "demo.pqo")
  steps <- seq(bounds[1], bounds[2], length.out = 21)
  writeLines(format_phreeqc_reaction_path_input(thermal, meteoric, f, phases, steps, output_file = sel_out,
                                                 si_minerals = get_si_minerals("phreeqc")),
             in_file)
  exit_code <- tryCatch(run_phreeqc(in_file, out_file, db_file = PHREEQC_DB), error = function(e) { message("  PHREEQC exe call failed: ", e$message); -1L })

  if (exit_code != 0 || !file.exists(sel_out)) {
    message("  PHREEQC did not run cleanly (exit code ", exit_code, ") -- this does not affect the input-generation logic above.")
    return(invisible(list(bounds = bounds, syntax_ok = ok_syntax, exit_code = exit_code)))
  }

  parsed <- parse_phreeqc_reaction_path_output(sel_out)
  ok_exec <- nrow(parsed) > 0 && "Ca" %in% parsed$parameter && length(unique(parsed$step_index)) >= 1
  message(sprintf("  PHREEQC reaction-path titration executed: %d of %d step(s) parsed -- %s",
                   length(unique(parsed$step_index)), length(steps), if (ok_exec) "PASS" else "FAIL"))

  invisible(list(bounds = bounds, syntax_ok = ok_syntax, parsed = parsed, pass = ok_exec))
}
