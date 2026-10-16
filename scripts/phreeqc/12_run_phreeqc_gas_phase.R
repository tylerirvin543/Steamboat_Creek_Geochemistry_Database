#12_run_phreeqc_gas_phase
#
# PHREEQC GAS_PHASE equilibria: models degassing/gas equilibration (CO2,
# H2S by default) along a sample's ascent-to-outflow path. Relevant here
# because boiling/degassing measurably shifts pH and carbonate speciation
# between deep upflow and surface outflow -- a real confound for this
# project's conductivity-as-Cl-proxy work, since specific conductance
# responds to total ionic strength, not just Cl.
#
# Supports both PHREEQC gas-phase modes:
#  - "fixed_pressure" (open system, gas escapes to maintain total pressure)
#  - "fixed_volume" (closed system, pressure varies with dissolution/exsolution)

library(DBI)
library(dplyr)

#' Build a PHREEQC input file with a SOLUTION + GAS_PHASE block.
#'
#' @param row Sample row (as used by format_solution_block()).
#' @param gas_components Character vector of gas components, e.g.
#'   c("CO2(g)", "H2S(g)").
#' @param gas_phase_type "fixed_pressure" or "fixed_volume".
#' @param total_pressure_atm Used when gas_phase_type == "fixed_pressure".
#' @param volume_liters Used when gas_phase_type == "fixed_volume".
format_phreeqc_gas_phase_input <- function(row, gas_components = c("CO2(g)", "H2S(g)"),
                                            gas_phase_type = c("fixed_pressure", "fixed_volume"),
                                            total_pressure_atm = 1.0, volume_liters = 1.0,
                                            output_file = "phreeqc_gas.tsv",
                                            si_minerals = DEFAULT_SI_MINERALS,
                                            initial_moles = NULL) {
  # initial_moles: optional named numeric vector (names matching
  # gas_components exactly, e.g. c("CO2(g)" = 0.9, "H2S(g)" = 0.03)) --
  # seeds the GAS_PHASE with a real, non-zero starting composition
  # instead of the default all-zero start. Added 2026-10 to let a real
  # measured free-gas analysis (not just the water sample's own
  # internal degassing) be imposed on the equilibration -- see
  # run_phreeqc_gas_phase_fischer_pairing() below.
  gas_phase_type <- match.arg(gas_phase_type)

  lines <- c(
    "SELECTED_OUTPUT",
    sprintf("    -file         %s", output_file),
    "    -reset        false",
    "    -simulation   true",
    "    -solution     true",
    "    -pH           true",
    "    -temperature  true",
    sprintf("    -saturation_indices  %s", paste(si_minerals, collapse = "  ")),
    # 2026-09-06: "-gas true" is not a real SELECTED_OUTPUT keyword --
    # PHREEQC prefix-matched it against "-gases" (which takes gas
    # component *names*, not a boolean) and warned "Did not find phase,
    # true", silently punching zero gas columns. The aggregate
    # -pressure/"total mol" columns parse_phreeqc_gas_output() already
    # falls back to happened to still work for a single-gas-component
    # phase, which is why this went unnoticed until rendering
    # notebooks/06_phreeqc_geochemical_modeling.qmd surfaced the raw
    # PHREEQC warning text. Fixed to the real keyword + real gas names,
    # which additionally gives real per-component m_<gas>/pressure_<gas>
    # columns for a genuinely multi-gas mixture.
    sprintf("    -gases        %s", paste(gas_components, collapse = " ")),
    ""
  )

  lines <- c(lines, format_solution_block(row, solution_number = 1), "")

  gas_lines <- c("GAS_PHASE 1")
  if (gas_phase_type == "fixed_pressure") {
    gas_lines <- c(gas_lines,
      "    -fixed_pressure",
      sprintf("    -pressure   %.6g", total_pressure_atm),
      "    -volume     1")
  } else {
    gas_lines <- c(gas_lines,
      "    -fixed_volume",
      sprintf("    -volume     %.3f", volume_liters))
  }
  for (g in gas_components) {
    start_moles <- if (!is.null(initial_moles) && g %in% names(initial_moles)) initial_moles[[g]] else 0
    gas_lines <- c(gas_lines, sprintf("    %-10s %.6g", g, start_moles))
  }
  lines <- c(lines, gas_lines, "END", "")

  lines
}

#' Parse `-gases <names>` SELECTED_OUTPUT columns (fixed 2026-09-06: the
#' prior "-gas true" directive was not a real PHREEQC keyword and
#' silently punched zero real gas-component columns -- see
#' format_phreeqc_gas_phase_input()). PHREEQC's real "-gases" selector
#' punches one moles-of-gas column per named component ("g_<name>"),
#' plus the aggregate total pressure/total moles/volume columns this
#' function used as its only source before. Real per-component moles let
#' this compute a genuine per-component partial pressure
#' (partial_pressure_i = total_pressure * moles_i / total_moles) for a
#' true multi-gas mixture; falls back to the aggregate columns alone if
#' a component's own "g_<name>" column isn't found for any reason.
parse_phreeqc_gas_output <- function(selected_output_file, sample_id, gas_components) {
  if (!file.exists(selected_output_file)) stop("SELECTED_OUTPUT file not found: ", selected_output_file)

  raw <- read.delim(selected_output_file, sep = "\t", stringsAsFactors = FALSE, check.names = FALSE) |>
    tibble::as_tibble(.name_repair = "universal")
  names(raw) <- stringr::str_replace_all(names(raw), "\\.", "_")
  names(raw) <- trimws(names(raw))

  last_row <- raw[nrow(raw), ]
  ph_col <- grep("^pH$", names(raw), value = TRUE)
  press_col <- grep("^pressure$", names(raw), value = TRUE, ignore.case = TRUE)
  moles_col <- grep("^total_mol$", names(raw), value = TRUE, ignore.case = TRUE)

  total_pressure <- if (length(press_col) > 0) suppressWarnings(as.numeric(last_row[[press_col[1]]])) else NA_real_
  total_moles <- if (length(moles_col) > 0) suppressWarnings(as.numeric(last_row[[moles_col[1]]])) else NA_real_
  resulting_pH <- if (length(ph_col) > 0) suppressWarnings(as.numeric(last_row[[ph_col[1]]])) else NA_real_

  result <- list()
  for (g in gas_components) {
    g_clean <- gsub("[^A-Za-z0-9]", "_", g)
    g_col <- grep(paste0("^g_", g_clean, "_?$"), names(raw), value = TRUE, ignore.case = TRUE)
    moles_i <- if (length(g_col) > 0) suppressWarnings(as.numeric(last_row[[g_col[1]]])) else NA_real_
    partial_pressure_i <- if (!is.na(moles_i) && !is.na(total_moles) && total_moles > 0 && !is.na(total_pressure)) {
      total_pressure * moles_i / total_moles
    } else {
      total_pressure  # fallback: aggregate total, only exact for a single gas component
    }
    result[[length(result) + 1]] <- data.frame(
      sample_id = sample_id,
      gas_component = g,
      moles_gas = if (!is.na(moles_i)) moles_i else total_moles,
      partial_pressure_atm = partial_pressure_i,
      resulting_pH = resulting_pH,
      stringsAsFactors = FALSE
    )
  }
  bind_rows(result)
}

#' Run a GAS_PHASE equilibration for one or more eligible samples.
#'
#' @param con DBI connection.
#' @param sample_ids Integer vector of sample_ids (from PHREEQC_Solutions).
#' @param gas_components Default c("CO2(g)", "H2S(g)").
#' @param gas_phase_type "fixed_pressure" (default) or "fixed_volume".
#' @param phreeqc_db Database key or "auto".
run_phreeqc_gas_phase <- function(con, sample_ids, gas_components = c("CO2(g)", "H2S(g)"),
                                   gas_phase_type = c("fixed_pressure", "fixed_volume"),
                                   total_pressure_atm = 1.0, volume_liters = 1.0,
                                   phreeqc_db = "auto", initial_moles = NULL, notes = NA_character_) {
  check_phreeqc()
  gas_phase_type <- match.arg(gas_phase_type)

  solutions <- dbReadTable(con, "PHREEQC_Solutions") |> as_tibble()
  rows <- solutions[solutions$sample_id %in% sample_ids, ]
  if (nrow(rows) == 0) { message("No matching PHREEQC_Solutions rows for the given sample_ids."); return(invisible(NULL)) }

  if (identical(phreeqc_db, "auto")) {
    rec <- recommend_phreeqc_db(rows)
    db_key <- rec$recommended
  } else db_key <- phreeqc_db
  db_path <- get_phreeqc_db_path(db_key)
  db_name <- PHREEQC_DATABASES[[db_key]]$name

  dbAppendTable(con, "PHREEQC_Gas_Phase_Runs", data.frame(
    run_date = as.character(Sys.Date()),
    gas_components = paste(gas_components, collapse = ","),
    gas_phase_type = gas_phase_type,
    total_pressure_atm = if (gas_phase_type == "fixed_pressure") total_pressure_atm else NA_real_,
    volume_liters = if (gas_phase_type == "fixed_volume") volume_liters else NA_real_,
    db_file = db_name,
    notes = notes,
    stringsAsFactors = FALSE
  ))
  gas_run_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]

  out_dir <- file.path("phreeqc", "runs", "gas_phase", paste0("run_", gas_run_id))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  all_results <- list()
  for (i in seq_len(nrow(rows))) {
    row <- as.list(rows[i, ])
    tag <- paste0("s", row$sample_id)
    sel_out <- file.path(out_dir, paste0(tag, "_selected.tsv"))
    in_file <- file.path(out_dir, paste0(tag, ".pqi"))
    out_file <- file.path(out_dir, paste0(tag, ".pqo"))

    lines <- format_phreeqc_gas_phase_input(row, gas_components, gas_phase_type,
                                             total_pressure_atm, volume_liters,
                                             output_file = sel_out, si_minerals = get_si_minerals(db_key),
                                             initial_moles = initial_moles)
    writeLines(lines, in_file)
    exit_code <- run_phreeqc(in_file, out_file, db_file = db_path)

    if (exit_code == 0 && file.exists(sel_out)) {
      parsed <- parse_phreeqc_gas_output(sel_out, row$sample_id, gas_components)
      all_results[[length(all_results) + 1]] <- parsed |>
        mutate(gas_run_id = gas_run_id, db_file = db_name, run_date = as.character(Sys.Date()))
    } else {
      message("  Gas-phase run failed to converge for sample ", row$sample_id)
    }
  }

  if (length(all_results) == 0) { message("No gas-phase runs produced results."); return(invisible(gas_run_id)) }

  results <- bind_rows(all_results) |>
    select(gas_run_id, sample_id, gas_component, moles_gas, partial_pressure_atm, resulting_pH, db_file, run_date)
  dbAppendTable(con, "PHREEQC_Gas_Phase_Results", results)
  message("Stored ", nrow(results), " gas-phase result rows for gas_run_id ", gas_run_id, ".")
  invisible(gas_run_id)
}

# =============================================================================
# SELF-TEST ON SYNTHETIC CO2-CHARGED SOLUTION
# =============================================================================

#' Self-test: confirm a synthetic CO2-charged solution degasses (and pH
#' rises) when equilibrated with an open, atmosphere-like fixed-pressure
#' gas phase -- a sanity check on block syntax and parsing, not a
#' validated real-world number. Note: total_pressure_atm here is
#' deliberately set near atmospheric CO2 partial pressure (~10^-3.5 atm),
#' not 1 atm -- a fixed-pressure gas phase starting from zero gas moles
#' only exchanges gas once the solution's own fugacity reaches the
#' target pressure, so setting total_pressure_atm above the solution's
#' actual CO2 fugacity (as an earlier version of this self-test did)
#' correctly produces *no* change, which looked like a bug but wasn't.
demo_gas_phase <- function() {
  message("---- Gas phase self-test (synthetic CO2-charged solution) ----")

  synth <- list(sample_id = "SYNTH_CO2", temperature = 25, pH = 6.0,
                 Na = 50, K = 5, Ca = 60, Mg = 10, Cl = 20, SO4 = 15,
                 Alkalinity = 400, Si = 30, NO3 = NA, F = NA, Br = NA,
                 B = NA, Li = NA, Sr = NA, Fe = NA, Mn = NA, As = NA)

  atm_co2 <- 10^-3.5
  lines <- format_phreeqc_gas_phase_input(synth, gas_components = "CO2(g)",
                                           gas_phase_type = "fixed_pressure",
                                           total_pressure_atm = atm_co2,
                                           output_file = "demo_gas.tsv")
  ok_syntax <- any(grepl("^GAS_PHASE", lines)) && any(grepl("CO2\\(g\\)", lines))
  message("  GAS_PHASE input block generated: ", if (ok_syntax) "PASS (syntax present)" else "FAIL")

  has_phreeqc <- tryCatch({ check_phreeqc(); TRUE }, error = function(e) FALSE)
  if (has_phreeqc) {
    tmp_dir <- tempfile("phreeqc_gas_demo_")
    dir.create(tmp_dir)
    sel_out <- file.path(tmp_dir, "demo_selected.tsv")
    in_file <- file.path(tmp_dir, "demo.pqi")
    out_file <- file.path(tmp_dir, "demo.pqo")
    lines <- format_phreeqc_gas_phase_input(synth, gas_components = "CO2(g)",
                                             gas_phase_type = "fixed_pressure",
                                             total_pressure_atm = atm_co2, output_file = sel_out)
    writeLines(lines, in_file)
    exit_code <- tryCatch(run_phreeqc(in_file, out_file, db_file = PHREEQC_DB), error = function(e) { message("  PHREEQC exe call failed: ", e$message); -1L })
    if (exit_code == 0 && file.exists(sel_out)) {
      parsed <- parse_phreeqc_gas_output(sel_out, synth$sample_id, "CO2(g)")
      message("  PHREEQC GAS_PHASE run executed. Resulting pH after equilibration: ",
              round(parsed$resulting_pH[1], 2), " (started at pH ", synth$pH, ").")
    } else {
      message("  PHREEQC GAS_PHASE run did not run cleanly (exit code ", exit_code, "). Syntax check above is unaffected.")
    }
  } else {
    message("  PHREEQC executable not found -- skipping the execution half of the self-test.")
  }

  invisible(list(input_lines = lines, syntax_ok = ok_syntax))
}
# =============================================================================
# REAL GAS-PHASE EQUILIBRATION: SBF_0001 WATER AGAINST NV26-1's REAL
# MEASURED GAS COMPOSITION
# =============================================================================
#
# Every GAS_PHASE run before this one (the self-test above, and any
# config-driven run from data/raw/phreeqc/gas_phase_config.csv) either
# used a synthetic solution or let the water degas against an assumed
# atmospheric CO2 partial pressure -- a real measured gas composition at
# the same point was never available to impose instead. NV26-1 (the
# April 2026 fissure gas sample co-located with the real water sample
# SBF_0001) is the first case where this project can equilibrate a real
# water analysis against a real, independently-measured gas phase
# instead of an assumption.
#
# Honest simplifications, stated once here rather than buried:
#  - Only CO2(g) and H2S(g) are modeled (the two species already in
#    this pipeline's DEFAULT gas-phase list and the only ones with a
#    meaningful aqueous/mineral tie-in via SI_Calcite etc.) -- N2, Ar,
#    He, CH4 are real components of NV26-1 but are not reactive with
#    this water's major-ion chemistry in a way PHREEQC's standard
#    databases model, so leaving them out does not materially change
#    the carbonate/sulfide equilibrium question being asked here.
#  - The relative CO2:H2S proportion is taken from NV26-1's
#    AIR-CORRECTED composition (correct_gas_for_air()), since the raw
#    composition is >50% diluted by atmospheric entrainment at this
#    shallow vent -- using the raw ratio would understate the real
#    reservoir gas's CO2 dominance.
#  - A large total gas-phase size (10 mol) is used so the imposed real
#    composition acts as an effectively infinite external buffer (an
#    open system continuously supplied by the fissure), rather than a
#    small, easily-exhausted finite gas pocket -- this is a modeling
#    choice representing "the fissure keeps supplying this gas," not a
#    measured gas-phase volume (none was measured in the field).

#' Equilibrate a real water sample against a real GAS_PHASE seeded with
#' another real sample's (air-corrected) CO2/H2S proportions.
#'
#' @param con DBI connection.
#' @param water_sample_id Integer sample_id of the water sample (must
#'   already have a PHREEQC_Solutions row -- see build_phreeqc_solutions()).
#' @param gas_sample_label Gas_Analyses.sample_label to source the
#'   CO2/H2S proportions from (default "NV26-1").
#' @param total_gas_moles Total size of the imposed gas phase (mol);
#'   large relative to the water's own dissolved-gas content so it acts
#'   as an external buffer. Default 10.
run_phreeqc_gas_phase_fischer_pairing <- function(
    con, water_sample_id = 816, gas_sample_label = "NV26-1",
    total_pressure_atm = 1.0, total_gas_moles = 10, phreeqc_db = "auto") {

  gas_row <- DBI::dbGetQuery(con, "
    SELECT sample_label, co2_mol_pct AS CO2, he_mol_pct AS He, h2_mol_pct AS H2, ar_mol_pct AS Ar,
           o2_mol_pct AS O2, n2_mol_pct AS N2, ch4_mol_pct AS CH4, co_mol_pct AS CO,
           h2s_mol_pct AS H2S
    FROM Gas_Analyses WHERE sample_label = ?
  ", params = list(gas_sample_label))
  if (nrow(gas_row) == 0) {
    message("[gas_phase_fischer] No Gas_Analyses row for ", gas_sample_label, ".")
    return(invisible(NULL))
  }

  corrected <- correct_gas_for_air(gas_row)
  co2_frac <- corrected$CO2_corrected[1] / (corrected$CO2_corrected[1] + corrected$H2S_corrected[1])
  h2s_frac <- 1 - co2_frac

  initial_moles <- c(
    `CO2(g)` = total_gas_moles * co2_frac,
    `H2S(g)` = total_gas_moles * h2s_frac
  )

  note_text <- sprintf(
    "Real pairing: water sample_id %d equilibrated against a GAS_PHASE seeded with %s's air-corrected CO2:H2S proportions (%.1f%%:%.1f%%), total %.1f mol as an open-system buffer.",
    water_sample_id, gas_sample_label, co2_frac * 100, h2s_frac * 100, total_gas_moles
  )
  message("[gas_phase_fischer] ", note_text)

  gas_run_id <- run_phreeqc_gas_phase(con, sample_ids = water_sample_id,
                         gas_components = c("CO2(g)", "H2S(g)"),
                         gas_phase_type = "fixed_pressure",
                         total_pressure_atm = total_pressure_atm,
                         phreeqc_db = phreeqc_db,
                         initial_moles = initial_moles,
                         notes = note_text)

  summarize_gas_phase_fischer_pairing(gas_run_id, water_sample_id, gas_sample_label)
}

#' Read the raw before/after SELECTED_OUTPUT from a
#' run_phreeqc_gas_phase_fischer_pairing() run and return a tidy
#' long-format comparison (pH + mineral saturation indices, before vs.
#' after equilibration with the real imposed gas phase), writing a CSV
#' for direct use in documents/figures.
summarize_gas_phase_fischer_pairing <- function(
    gas_run_id, water_sample_id, gas_sample_label,
    out_csv = "data/derived/gas_analysis/gas_phase_fischer_pairing_before_after.csv") {

  if (is.null(gas_run_id)) return(invisible(NULL))
  tsv_path <- file.path("phreeqc", "runs", "gas_phase", paste0("run_", gas_run_id),
                         paste0("s", water_sample_id, "_selected.tsv"))
  if (!file.exists(tsv_path)) {
    message("[gas_phase_fischer] Selected-output file not found: ", tsv_path)
    return(invisible(NULL))
  }

  raw <- read.delim(tsv_path, sep = "\t", stringsAsFactors = FALSE, check.names = FALSE)
  names(raw) <- trimws(names(raw))
  raw <- raw[, !grepl("^\\.\\.\\.", names(raw)) & !grepl("^$", names(raw))]

  keep_cols <- c("pH", grep("^si_", names(raw), value = TRUE))
  before <- raw[1, keep_cols]
  after  <- raw[nrow(raw), keep_cols]

  comparison <- data.frame(
    parameter = keep_cols,
    before_no_gas_phase = as.numeric(before),
    after_real_gas_phase = as.numeric(after)
  )
  comparison$delta <- comparison$after_real_gas_phase - comparison$before_no_gas_phase
  # -999.999 is PHREEQC's own "undefined" sentinel (mineral absent from
  # the database's SI list for this solution) -- flag, don't compute a
  # delta against it.
  comparison$delta[comparison$before_no_gas_phase <= -999 | comparison$after_real_gas_phase <= -999] <- NA_real_
  comparison$water_sample_id <- water_sample_id
  comparison$gas_sample_label <- gas_sample_label

  dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(comparison, out_csv)
  message("[gas_phase_fischer] Wrote before/after comparison to ", out_csv)

  for (i in seq_len(nrow(comparison))) {
    r <- comparison[i, ]
    if (!is.na(r$delta)) {
      message(sprintf("  %-14s %8.3f -> %8.3f (delta %+.3f)", r$parameter, r$before_no_gas_phase, r$after_real_gas_phase, r$delta))
    }
  }

  invisible(comparison)
}