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
                                            si_minerals = DEFAULT_SI_MINERALS) {
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
    "    -gas          true",
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
  for (g in gas_components) gas_lines <- c(gas_lines, sprintf("    %-10s 0", g))
  lines <- c(lines, gas_lines, "END", "")

  lines
}

#' Parse `-gas true` SELECTED_OUTPUT columns. PHREEQC's `-gas` selector
#' reports aggregate gas-phase properties (total pressure, total moles,
#' volume), not one column per component -- fine for the single-gas-
#' component case used here (moles_gas/partial_pressure_atm are exact
#' when gas_components has length 1, since "total" and "partial" then
#' coincide; for a genuinely multi-component gas phase, treat the
#' resulting values as gas-phase totals, not true per-component
#' partial pressures/moles, without further PHREEQC punch options).
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

  result <- list()
  for (g in gas_components) {
    result[[length(result) + 1]] <- data.frame(
      sample_id = sample_id,
      gas_component = g,
      moles_gas = if (length(moles_col) > 0) suppressWarnings(as.numeric(last_row[[moles_col[1]]])) else NA_real_,
      partial_pressure_atm = if (length(press_col) > 0) suppressWarnings(as.numeric(last_row[[press_col[1]]])) else NA_real_,
      resulting_pH = if (length(ph_col) > 0) suppressWarnings(as.numeric(last_row[[ph_col[1]]])) else NA_real_,
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
                                   phreeqc_db = "auto") {
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
    notes = NA_character_,
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
                                             output_file = sel_out, si_minerals = get_si_minerals(db_key))
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
