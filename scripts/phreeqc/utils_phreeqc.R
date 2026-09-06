# --------------------------------------------------------------------------
# utils_phreeqc.R
#
# Shared PHREEQC utilities for the Steamboat geochemistry database: SOLUTION
# block generation from Samples/Lab_Analyses/Field_Measurements rows,
# external execution of the standalone PHREEQC 3 executable via system2(),
# SELECTED_OUTPUT parsing, a multi-thermodynamic-database registry with
# automatic recommendation, fluid-type classification, and automated
# human-readable interpretation text.
#
# Ported from the IGNIS project's utils_phreeqc.R (same author, same
# analytical needs), adapted to this project's schema (Samples/Locations/
# Lab_Analyses/Field_Measurements instead of samples/locations with a
# `prospect` column) and house style (functions take `con` as their first
# argument; no bare top-level dbConnect() calls; PascalCase table names).
#
# Every downstream PHREEQC script (08_build_phreeqc_tables.R,
# 09_run_phreeqc.R, 10_run_phreeqc_mixing.R, 11_run_phreeqc_inverse.R,
# 12_run_phreeqc_gas_phase.R) sources this file first.
# --------------------------------------------------------------------------

library(DBI)
library(RSQLite)
library(dplyr)
library(tidyr)
library(stringr)

# --- Configuration ----------------------------------------------------------

# Override via environment variables PHREEQC_EXE / PHREEQC_DB, or by setting
# these directly before sourcing this file.
PHREEQC_EXE <- Sys.getenv("PHREEQC_EXE",
  unset = "C:/Program Files/USGS/phreeqc/bin/Release/phreeqc.exe")
PHREEQC_DB  <- Sys.getenv("PHREEQC_DB",
  unset = "C:/Program Files/USGS/phreeqc/database/phreeqc.dat")

#' Check that PHREEQC is installed and accessible.
#' @return TRUE invisibly if OK, stops with install instructions if not.
check_phreeqc <- function(exe = PHREEQC_EXE, db_file = PHREEQC_DB) {
  if (file.exists(exe) && file.exists(db_file)) {
    message("PHREEQC found: ", exe)
    message("Database:      ", db_file)
    return(invisible(TRUE))
  }

  found <- Sys.which("phreeqc")
  if (nchar(found) > 0) {
    message("PHREEQC found on PATH: ", found)
    PHREEQC_EXE <<- found
    db_dir <- file.path(dirname(dirname(found)), "database", "phreeqc.dat")
    if (file.exists(db_dir)) {
      PHREEQC_DB <<- db_dir
      message("Database:      ", db_dir)
    }
    return(invisible(TRUE))
  }

  search_paths <- c(
    "C:/Program Files/USGS/phreeqc/bin/Release/phreeqc.exe",
    "C:/Program Files/USGS/Phreeqc/bin/Release/phreeqc.exe",
    "C:/Program Files/USGS/phreeqc/bin/phreeqc.bat",
    "C:/Program Files/USGS/Phreeqc/bin/phreeqc.bat",
    "C:/Program Files (x86)/USGS/phreeqc/bin/Release/phreeqc.exe"
  )
  for (sp in search_paths) {
    if (file.exists(sp)) {
      message("PHREEQC found at: ", sp)
      PHREEQC_EXE <<- sp
      base <- gsub("/bin/.*$", "", sp)
      db_path <- file.path(base, "database", "phreeqc.dat")
      if (file.exists(db_path)) {
        PHREEQC_DB <<- db_path
        message("Database:      ", db_path)
      }
      return(invisible(TRUE))
    }
  }

  stop(
    "PHREEQC not found at: ", exe,
    "\n\nTo install PHREEQC:",
    "\n  1. Download from https://www.usgs.gov/software/phreeqc-version-3",
    "\n  2. Install to C:/Program Files/USGS/phreeqc/",
    "\n  3. Or set environment variable PHREEQC_EXE to the executable path"
  )
}

# Default minerals for saturation index output
DEFAULT_SI_MINERALS <- c(
  "Calcite", "Aragonite", "Dolomite",
  "Quartz", "Chalcedony", "SiO2(a)",
  "Gypsum", "Anhydrite",
  "Fluorite", "Barite",
  "Halite"
)

get_si_minerals <- function(db_key = "phreeqc") {
  if (db_key == "llnl") {
    setdiff(DEFAULT_SI_MINERALS, "SiO2(a)")
  } else {
    DEFAULT_SI_MINERALS
  }
}

# --- PHREEQC Thermodynamic Database Registry --------------------------------

PHREEQC_DATABASES <- list(
  phreeqc = list(
    name     = "phreeqc.dat",
    label    = "PHREEQC Default",
    activity = "Extended Debye-Huckel (WATEQ)",
    temp_range = c(0, 100),
    mu_limit   = 0.7,
    strengths  = "General-purpose. Well-validated for fresh to moderately saline waters at ambient to 100C.",
    best_for   = "Standard geochemical screening, dilute natural waters, environmental applications.",
    reference  = "Parkhurst & Appelo (2013)"
  ),
  llnl = list(
    name     = "llnl.dat",
    label    = "LLNL (thermo.com.V8.R6.230)",
    activity = "Extended Debye-Huckel (B-dot)",
    temp_range = c(0, 300),
    mu_limit   = 0.7,
    strengths  = "Extended mineral set and high-temperature thermodynamic data. Preferred for geothermal systems.",
    best_for   = "Geothermal exploration, hydrothermal systems, high-temperature equilibria (up to 300C).",
    reference  = "Johnson et al. (2000), LLNL"
  ),
  wateq4f = list(
    name     = "wateq4f.dat",
    label    = "WATEQ4F",
    activity = "Extended Debye-Huckel (WATEQ)",
    temp_range = c(0, 100),
    mu_limit   = 0.7,
    strengths  = "Comprehensive trace metal speciation. Good for environmental and low-temperature systems.",
    best_for   = "Trace metal speciation, environmental geochemistry, mine drainage.",
    reference  = "Ball & Nordstrom (1991)"
  ),
  pitzer = list(
    name     = "pitzer.dat",
    label    = "Pitzer",
    activity = "Pitzer specific-interaction",
    temp_range = c(0, 200),
    mu_limit   = 6.0,
    strengths  = "Accurate for high ionic strength solutions (brines, evaporites). Limited mineral set.",
    best_for   = "Brines, saline lakes, evaporite systems, high-TDS geothermal fluids.",
    reference  = "Pitzer (1991); Plummer et al. (1988)"
  ),
  sit = list(
    name     = "sit.dat",
    label    = "SIT (Specific Ion Interaction Theory)",
    activity = "SIT",
    temp_range = c(0, 100),
    mu_limit   = 4.0,
    strengths  = "Alternative to Pitzer for moderately high ionic strength. Better mineral coverage than Pitzer.",
    best_for   = "Moderately saline waters, nuclear waste applications, high-TDS waters.",
    reference  = "Grenthe et al. (1997)"
  ),
  minteq = list(
    name     = "minteq.v4.dat",
    label    = "MINTEQA2 v4",
    activity = "Davies / Extended Debye-Huckel",
    temp_range = c(0, 100),
    mu_limit   = 0.5,
    strengths  = "Environmental focus. Good organic complexation data.",
    best_for   = "Environmental risk assessment, metal mobility, surface water chemistry.",
    reference  = "Allison et al. (1991)"
  )
)

get_phreeqc_db_path <- function(db_key) {
  if (!db_key %in% names(PHREEQC_DATABASES)) {
    stop("Unknown PHREEQC database: ", db_key,
         ". Available: ", paste(names(PHREEQC_DATABASES), collapse = ", "))
  }
  db_name <- PHREEQC_DATABASES[[db_key]]$name
  base_dir <- dirname(PHREEQC_DB)
  path <- file.path(base_dir, db_name)
  if (!file.exists(path)) {
    stop("Database file not found: ", path)
  }
  path
}

#' Recommend the most appropriate PHREEQC database based on sample
#' characteristics. Steamboat is a genuine high-temperature geothermal
#' system, so the >50C branch below (routing to LLNL) fires for most
#' real samples -- this differs from a typical ambient-temperature
#' environmental dataset where "phreeqc" default would dominate.
recommend_phreeqc_db <- function(df) {
  max_temp <- suppressWarnings(max(df$temperature, na.rm = TRUE))
  if (!is.finite(max_temp)) max_temp <- NA_real_

  ion_cols <- intersect(c("Na", "K", "Ca", "Mg", "Cl", "SO4", "Alkalinity", "Si"), names(df))
  max_tds <- if (length(ion_cols) > 0) {
    tds_est <- rowSums(df[, ion_cols, drop = FALSE], na.rm = TRUE)
    suppressWarnings(max(tds_est, na.rm = TRUE))
  } else NA_real_
  if (!is.finite(max_tds)) max_tds <- NA_real_

  has_metals <- any(!is.na(df$Fe) | !is.na(df$Mn) | !is.na(df$As))

  if (!is.na(max_temp) && max_temp > 100) {
    return(list(
      recommended = "llnl",
      reason = sprintf("Maximum temperature %.0fC exceeds 100C. LLNL database has validated high-T thermodynamic data up to 300C.", max_temp),
      alternatives = c("phreeqc")
    ))
  }
  if (!is.na(max_tds) && max_tds > 35000) {
    return(list(
      recommended = "pitzer",
      reason = sprintf("Maximum TDS %.0f mg/L indicates high ionic strength. Pitzer model provides accurate activity coefficients for brines.", max_tds),
      alternatives = c("sit", "llnl")
    ))
  }
  if (!is.na(max_tds) && max_tds > 10000) {
    return(list(
      recommended = "sit",
      reason = sprintf("Maximum TDS %.0f mg/L. SIT model handles moderately high ionic strength better than Debye-Huckel.", max_tds),
      alternatives = c("pitzer", "llnl")
    ))
  }
  if (!is.na(max_temp) && max_temp > 50) {
    return(list(
      recommended = "llnl",
      reason = sprintf("Geothermal temperatures detected (max %.0fC). LLNL database has better high-T mineral data and is standard for geothermal applications.", max_temp),
      alternatives = c("phreeqc")
    ))
  }
  if (has_metals && !is.na(max_temp) && max_temp < 50) {
    return(list(
      recommended = "wateq4f",
      reason = "Trace metals detected (Fe, Mn, or As) at ambient temperatures. WATEQ4F has comprehensive trace metal speciation data.",
      alternatives = c("phreeqc", "minteq")
    ))
  }
  list(
    recommended = "phreeqc",
    reason = "Standard conditions (T < 50C, moderate TDS). Default PHREEQC database is well-validated for these conditions.",
    alternatives = c("llnl", "wateq4f")
  )
}

list_phreeqc_databases <- function() {
  tibble::tibble(
    key = names(PHREEQC_DATABASES),
    name = sapply(PHREEQC_DATABASES, "[[", "name"),
    label = sapply(PHREEQC_DATABASES, "[[", "label"),
    activity_model = sapply(PHREEQC_DATABASES, "[[", "activity"),
    temp_max = sapply(PHREEQC_DATABASES, function(x) x$temp_range[2]),
    mu_limit = sapply(PHREEQC_DATABASES, "[[", "mu_limit"),
    best_for = sapply(PHREEQC_DATABASES, "[[", "best_for")
  )
}

# --- Fluid Type Classification ----------------------------------------------

FLUID_TYPE_MINERALS <- list(
  "Na-Cl" = list(
    label = "Sodium-Chloride (mature geothermal)",
    minerals = c("Quartz", "Chalcedony", "Calcite", "Fluorite",
                 "Halite", "Anhydrite", "Barite", "Dolomite"),
    description = "Mature geothermal brine. Focus on silica geothermometry and scaling minerals."
  ),
  "Na-HCO3" = list(
    label = "Sodium-Bicarbonate (CO2-rich / peripheral)",
    minerals = c("Calcite", "Aragonite", "Dolomite", "Quartz",
                 "Chalcedony", "Fluorite", "SiO2(a)"),
    description = "CO2-charged or peripheral geothermal water. Carbonate equilibria dominant."
  ),
  "Ca-HCO3" = list(
    label = "Calcium-Bicarbonate (immature / meteoric)",
    minerals = c("Calcite", "Aragonite", "Dolomite", "Gypsum",
                 "Quartz", "Chalcedony", "SiO2(a)"),
    description = "Shallow groundwater or immature geothermal fluid. Carbonate and silica equilibria."
  ),
  "Ca-SO4" = list(
    label = "Calcium-Sulfate (steam-heated / acid)",
    minerals = c("Gypsum", "Anhydrite", "Calcite", "Quartz",
                 "SiO2(a)", "Barite", "Chalcedony"),
    description = "Steam-heated or acid-sulfate water. Sulfate mineral equilibria important."
  ),
  "Mixed" = list(
    label = "Mixed / Transitional",
    minerals = DEFAULT_SI_MINERALS,
    description = "No dominant ion type. Using complete mineral suite."
  )
)

#' Classify water samples by fluid type from major-ion dominance
#' (Piper-diagram logic on meq/L ratios).
#'
#' @param df Data frame with sample_id, Na, K, Ca, Mg, Cl, SO4, Alkalinity
#'   (this project stores bicarbonate as "Alkalinity", not "HCO3" -- see
#'   lab_analyte_map.R). Alkalinity (mg/L as CaCO3-equivalent-free
#'   reported units passed straight through, per this project's ingest
#'   convention) is treated as an HCO3 proxy for classification purposes.
classify_fluid_type <- function(df) {
  meq <- list(Na = 22.990, K = 39.098, Ca = 20.039, Mg = 12.153,
              Cl = 35.453, SO4 = 48.030, HCO3 = 61.017)

  hco3_col <- if ("Alkalinity" %in% names(df)) df$Alkalinity else df$HCO3

  df |>
    mutate(
      Na_meq  = coalesce(Na, 0) / meq$Na,
      K_meq   = coalesce(K, 0)  / meq$K,
      Ca_meq  = coalesce(Ca, 0) / meq$Ca,
      Mg_meq  = coalesce(Mg, 0) / meq$Mg,
      Cl_meq  = coalesce(Cl, 0) / meq$Cl,
      SO4_meq = coalesce(SO4, 0) / meq$SO4,
      HCO3_meq = coalesce(hco3_col, 0) / meq$HCO3,

      sum_cat = Na_meq + K_meq + Ca_meq + Mg_meq,
      sum_an  = Cl_meq + SO4_meq + HCO3_meq,
      pct_NaK   = ifelse(sum_cat > 0, (Na_meq + K_meq) / sum_cat * 100, NA),
      pct_Ca    = ifelse(sum_cat > 0, Ca_meq / sum_cat * 100, NA),
      pct_Cl    = ifelse(sum_an > 0, Cl_meq / sum_an * 100, NA),
      pct_SO4   = ifelse(sum_an > 0, SO4_meq / sum_an * 100, NA),
      pct_HCO3  = ifelse(sum_an > 0, HCO3_meq / sum_an * 100, NA),

      cation_facies = case_when(
        pct_NaK > 60 ~ "Na-K",
        pct_Ca > 60  ~ "Ca",
        TRUE         ~ "Mixed-cation"
      ),
      anion_facies = case_when(
        pct_Cl > 60   ~ "Cl",
        pct_HCO3 > 60 ~ "HCO3",
        pct_SO4 > 40  ~ "SO4",
        TRUE          ~ "Mixed-anion"
      ),
      fluid_type = case_when(
        cation_facies == "Na-K" & anion_facies == "Cl"    ~ "Na-Cl",
        cation_facies == "Na-K" & anion_facies == "HCO3"  ~ "Na-HCO3",
        cation_facies == "Ca"   & anion_facies == "HCO3"  ~ "Ca-HCO3",
        cation_facies == "Ca"   & anion_facies == "SO4"   ~ "Ca-SO4",
        TRUE                                               ~ "Mixed"
      )
    ) |>
    select(sample_id, fluid_type, cation_facies, anion_facies,
           any_of("location_name"), any_of("site_type"))
}

get_minerals_for_fluid <- function(fluid_types, db_key = "phreeqc") {
  types <- unique(fluid_types)
  minerals <- character()
  for (ft in types) {
    if (ft %in% names(FLUID_TYPE_MINERALS)) {
      minerals <- union(minerals, FLUID_TYPE_MINERALS[[ft]]$minerals)
    } else {
      minerals <- union(minerals, DEFAULT_SI_MINERALS)
    }
  }
  if (db_key == "llnl") {
    minerals <- setdiff(minerals, "SiO2(a)")
  }
  minerals
}

# --- SOLUTION Block Generation ----------------------------------------------

#' Analyte -> PHREEQC element/species mapping, driven by
#' database/schema/lab_analyte_map.R (loaded by the caller before this file
#' is sourced, or sourced here if not already present) so that adding a new
#' analyte to that one table is enough to flow into PHREEQC input
#' generation without touching this file.
.phreeqc_analyte_map <- function() {
  if (!exists("lab_analyte_map", envir = .GlobalEnv)) {
    source("database/schema/lab_analyte_map.R")
  }
  get("lab_analyte_map", envir = .GlobalEnv)
}

#' Create a PHREEQC SOLUTION block for a single sample.
#'
#' @param row A single-row data frame or named list with columns:
#'   sample_id, temperature, pH, and ion columns named after this
#'   project's clean `analyte` values (Ca, Mg, Na, K, Cl, SO4, Alkalinity,
#'   Si, B, Li, Fe, Mn, F, As, ...). Units are mg/L (this project's
#'   Lab_Analyses.value is already normalized to mg/L on ingest -- see
#'   ingest_lab.R).
format_solution_block <- function(row, solution_number = 1) {
  lines <- character()
  lines <- c(lines, sprintf("SOLUTION %d  %s", solution_number, row$sample_id))

  temp <- if (!is.null(row$temperature) && !is.na(row$temperature)) row$temperature else 25.0
  lines <- c(lines, sprintf("    temp      %.1f", temp))

  if (!is.null(row$pH) && !is.na(row$pH)) {
    lines <- c(lines, sprintf("    pH        %.2f", row$pH))
  }

  lines <- c(lines, "    units     mg/L")

  amap <- .phreeqc_analyte_map()

  # Build a per-analyte PHREEQC directive. Alkalinity and Si (-> SiO2)
  # need an "as X" suffix; everything else is a bare element/species name.
  as_unit_lookup <- c(Alkalinity = "HCO3", Si = "SiO2", NO3 = "NO3", SO4 = "SO4")

  # Skip boron if B >> Alkalinity (mirrors IGNIS's guard against PHREEQC's
  # "non-carbonate alkalinity > total" error).
  b_val <- row[["B"]]
  alk_val <- row[["Alkalinity"]]
  skip_boron <- FALSE
  if (!is.null(b_val) && !is.na(b_val) && !is.null(alk_val) && !is.na(alk_val)) {
    if (b_val > alk_val * 0.5) {
      skip_boron <- TRUE
      lines <- c(lines, sprintf(
        "    # NOTE: B (%.1f mg/L) excluded -- exceeds alkalinity constraint (Alkalinity=%.1f)",
        b_val, alk_val))
    }
  }

  for (i in seq_len(nrow(amap))) {
    analyte <- amap$analyte[i]
    if (analyte == "B" && skip_boron) next
    val <- row[[analyte]]
    if (is.null(val) || is.na(val) || !is.numeric(val) || val <= 0) next
    phreeqc_name <- amap$phreeqc_name[i]
    as_unit <- if (analyte %in% names(as_unit_lookup)) as_unit_lookup[[analyte]] else NULL
    if (!is.null(as_unit)) {
      lines <- c(lines, sprintf("    %-12s %.4g  as %s", phreeqc_name, val, as_unit))
    } else {
      lines <- c(lines, sprintf("    %-12s %.4g", phreeqc_name, val))
    }
  }

  lines
}

#' Generate a complete PHREEQC input file for multiple samples.
format_phreeqc_input <- function(df, output_file = "phreeqc_output.tsv",
                                  si_minerals = DEFAULT_SI_MINERALS) {
  lines <- character()

  lines <- c(lines,
    "SELECTED_OUTPUT",
    sprintf("    -file         %s", output_file),
    "    -reset        false",
    "    -simulation   true",
    "    -solution     true",
    "    -pH           true",
    "    -temperature  true",
    "    -ionic_strength true",
    "    -pe           true",
    sprintf("    -saturation_indices  %s", paste(si_minerals, collapse = "  ")),
    "    -activities   Na+ K+ Ca+2 Mg+2 H+ OH- HCO3- CO3-2 SO4-2 Cl- SiO2 F-",
    ""
  )

  for (i in seq_len(nrow(df))) {
    row <- as.list(df[i, ])
    sol_lines <- format_solution_block(row, solution_number = i)
    lines <- c(lines, sol_lines, "END", "")
  }

  lines
}

write_phreeqc_input <- function(df, input_file, output_file,
                                 si_minerals = DEFAULT_SI_MINERALS) {
  lines <- format_phreeqc_input(df, output_file = output_file, si_minerals = si_minerals)
  writeLines(lines, input_file)
  message("Wrote PHREEQC input: ", input_file, " (", nrow(df), " solutions)")
  invisible(input_file)
}

# --- PHREEQC Execution -------------------------------------------------------

#' Run PHREEQC externally via system2(). Windows short paths are used to
#' avoid the "Program Files" space breaking PHREEQC's argument parser.
run_phreeqc <- function(input_file, output_file,
                         phreeqc_exe = PHREEQC_EXE,
                         db_file = PHREEQC_DB) {
  if (!file.exists(phreeqc_exe)) stop("PHREEQC executable not found: ", phreeqc_exe)
  if (!file.exists(db_file)) stop("PHREEQC database not found: ", db_file)

  phreeqc_exe <- normalizePath(phreeqc_exe, mustWork = TRUE)
  db_file     <- normalizePath(db_file, mustWork = TRUE)
  input_file  <- normalizePath(input_file, mustWork = TRUE)
  if (.Platform$OS.type == "windows") {
    phreeqc_exe <- shortPathName(phreeqc_exe)
    db_file     <- shortPathName(db_file)
    input_file  <- shortPathName(input_file)
    output_file <- file.path(
      shortPathName(normalizePath(dirname(output_file), mustWork = TRUE)),
      basename(output_file)
    )
  }

  message("Running PHREEQC...")
  message("  Input:    ", input_file)
  message("  Output:   ", output_file)
  message("  Database: ", db_file)

  exit_code <- system2(phreeqc_exe, args = c(input_file, output_file, db_file),
                        stdout = "", stderr = "")

  if (exit_code == 0) {
    message("PHREEQC completed successfully.")
  } else {
    warning("PHREEQC exited with code ", exit_code, ". Check output file for errors.")
  }

  invisible(exit_code)
}

# --- Output Parsing ----------------------------------------------------------

parse_phreeqc_output <- function(selected_output_file, sample_ids) {
  if (!file.exists(selected_output_file)) {
    stop("SELECTED_OUTPUT file not found: ", selected_output_file)
  }

  raw <- read.delim(selected_output_file, sep = "\t",
                     stringsAsFactors = FALSE, check.names = FALSE) |>
    as_tibble(.name_repair = "universal")

  names(raw) <- str_replace_all(names(raw), "\\.", "_")

  if ("sim" %in% names(raw)) {
    raw <- raw |> mutate(sample_id = sample_ids[sim])
  } else if ("soln" %in% names(raw)) {
    raw <- raw |> mutate(sample_id = sample_ids[soln])
  } else {
    raw$sample_id <- sample_ids[seq_len(nrow(raw))]
  }

  param_cols <- names(raw)[!names(raw) %in% c("sim", "soln", "sample_id", "state", "dist_x")]
  param_cols <- param_cols[!grepl("^\\.\\.\\.\\d+$", param_cols)]
  param_cols <- param_cols[nchar(param_cols) > 0]

  raw |>
    select(sample_id, all_of(param_cols)) |>
    pivot_longer(cols = -sample_id, names_to = "parameter", values_to = "value") |>
    mutate(
      parameter = str_replace(parameter, "^si_", "SI_"),
      parameter = str_replace(parameter, "^temp_C_$", "temperature"),
      parameter = str_replace(parameter, "^mu$", "ionic_strength"),
      parameter = str_replace(parameter, "^la_", "log_activity_"),
      parameter = str_replace(parameter, "^pe$", "pe")
    ) |>
    filter(!is.na(value))
}

#' Parse PHREEQC output and insert into PHREEQC_Results (idempotent:
#' deletes any prior results for the same sample_id + db_file first).
store_phreeqc_results <- function(con, selected_output_file, sample_ids,
                                   db_file = PHREEQC_DB) {
  results <- parse_phreeqc_output(selected_output_file, sample_ids)

  results <- results |>
    mutate(run_date = as.character(Sys.Date()), db_file = basename(db_file)) |>
    select(sample_id, run_date, parameter, value, db_file)

  for (sid in unique(results$sample_id)) {
    dbExecute(con, "DELETE FROM PHREEQC_Results WHERE sample_id = ? AND db_file = ?",
              params = list(sid, basename(db_file)))
  }

  dbWriteTable(con, "PHREEQC_Results", results, append = TRUE)
  message("Stored ", nrow(results), " PHREEQC result rows for ",
          length(unique(results$sample_id)), " samples.")
}

#' Record (or clear) a sample-level PHREEQC convergence failure so it's
#' visible in QC instead of silently vanishing from downstream SI results.
record_phreeqc_run_failure <- function(con, sample_id, location_name, site_type, reason) {
  dbExecute(con, "DELETE FROM PHREEQC_Run_Failures WHERE sample_id = ?", params = list(sample_id))
  dbAppendTable(con, "PHREEQC_Run_Failures", data.frame(
    sample_id = sample_id,
    location_name = ifelse(is.null(location_name) || is.na(location_name), NA_character_, location_name),
    site_type = ifelse(is.null(site_type) || is.na(site_type), NA_character_, site_type),
    reason = reason,
    logged_at = as.character(Sys.time()),
    stringsAsFactors = FALSE
  ))
}

clear_phreeqc_run_failure <- function(con, sample_id) {
  dbExecute(con, "DELETE FROM PHREEQC_Run_Failures WHERE sample_id = ?", params = list(sample_id))
}

get_phreeqc_run_failures <- function(con) {
  dbGetQuery(con, "SELECT * FROM PHREEQC_Run_Failures ORDER BY logged_at DESC") |> tibble::as_tibble()
}

# --- Automated Interpretation -----------------------------------------------

#' Generate automated, human-readable interpretation of PHREEQC SI results.
#' @param site_type Character. Filter by Locations.site_type (NULL for all).
interpret_phreeqc_results <- function(con, db_file = NULL, site_type = NULL) {
  conditions <- character()
  params <- list()
  if (!is.null(db_file)) {
    conditions <- c(conditions, "pr.db_file = ?")
    params <- c(params, db_file)
  }
  if (!is.null(site_type)) {
    conditions <- c(conditions, "l.site_type = ?")
    params <- c(params, site_type)
  }
  where <- if (length(conditions) > 0) paste("WHERE", paste(conditions, collapse = " AND ")) else ""

  sql <- sprintf("
    SELECT pr.sample_id, l.name AS location_name, l.site_type, pr.parameter, pr.value,
           pr.db_file, fm.value AS temperature
    FROM PHREEQC_Results pr
    JOIN Samples s ON pr.sample_id = s.sample_id
    JOIN Locations l ON s.location_id = l.location_id
    LEFT JOIN Field_Measurements fm ON pr.sample_id = fm.sample_id AND fm.parameter = 'temperature'
    %s
  ", where)

  data <- if (length(params) > 0) dbGetQuery(con, sql, params = params) else dbGetQuery(con, sql)
  if (nrow(data) == 0) return("")

  si_data <- data |> filter(grepl("^SI_", parameter), value > -100) |>
    mutate(mineral = gsub("^SI_", "", parameter))

  ionic <- data |> filter(parameter == "ionic_strength")
  n_samples <- length(unique(si_data$sample_id))
  db_used <- unique(data$db_file)

  sections <- character()

  carb <- si_data |> filter(mineral %in% c("Calcite", "Aragonite", "Dolomite"))
  if (nrow(carb) > 0) {
    calc_near_eq <- carb |> filter(mineral == "Calcite", abs(value) < 0.5)
    calc_super <- carb |> filter(mineral == "Calcite", value > 0.5)
    calc_under <- carb |> filter(mineral == "Calcite", value < -0.5)
    txt <- "<strong>Carbonate Minerals:</strong> "
    if (nrow(calc_near_eq) > 0) {
      txt <- paste0(txt, sprintf("%d of %d samples are near calcite equilibrium (SI within &plusmn;0.5), ", nrow(calc_near_eq), n_samples))
      txt <- paste0(txt, "suggesting calcium carbonate buffering of the water chemistry. ")
    }
    if (nrow(calc_super) > 0) {
      txt <- paste0(txt, sprintf("%d sample(s) are calcite-supersaturated (SI up to %.1f), ", nrow(calc_super), max(calc_super$value)))
      txt <- paste0(txt, "indicating potential for carbonate scaling or active precipitation. ")
    }
    if (nrow(calc_under) > 0) {
      txt <- paste0(txt, sprintf("%d sample(s) are calcite-undersaturated, ", nrow(calc_under)))
      txt <- paste0(txt, "consistent with dilute meteoric waters or CO<sub>2</sub>-charged fluids. ")
    }
    sections <- c(sections, txt)
  }

  silica <- si_data |> filter(mineral %in% c("Quartz", "Chalcedony", "SiO2_a_"))
  if (nrow(silica) > 0) {
    qtz_eq <- silica |> filter(mineral == "Quartz", abs(value) < 0.5)
    chal_eq <- silica |> filter(mineral == "Chalcedony", abs(value) < 0.5)
    txt <- "<strong>Silica Phases:</strong> "
    if (nrow(qtz_eq) > 0) {
      txt <- paste0(txt, sprintf("%d sample(s) approach quartz equilibrium, ", nrow(qtz_eq)))
      txt <- paste0(txt, "supporting the quartz geothermometer as a reliable reservoir temperature estimate. ")
    }
    if (nrow(chal_eq) > 0 && nrow(qtz_eq) == 0) {
      txt <- paste0(txt, sprintf("%d sample(s) are near chalcedony equilibrium (not quartz), ", nrow(chal_eq)))
      txt <- paste0(txt, "suggesting lower reservoir temperatures (typically &lt;120&deg;C). ")
    }
    sections <- c(sections, txt)
  }

  if (nrow(ionic) > 0) {
    mu_range <- range(ionic$value, na.rm = TRUE)
    db_info <- PHREEQC_DATABASES[[gsub("\\.dat$", "", db_used[1])]]
    mu_limit <- if (!is.null(db_info)) db_info$mu_limit else 0.7
    txt <- sprintf("<strong>Ionic Strength:</strong> Calculated &mu; ranges from %.4f to %.4f mol/kgw. ", mu_range[1], mu_range[2])
    if (mu_range[2] > mu_limit) {
      txt <- paste0(txt, sprintf("<span class='qc-review'>Some samples exceed the recommended limit (&mu; > %.1f) for the %s activity model.</span>",
                                  mu_limit, if (!is.null(db_info)) db_info$activity else "current"))
    } else if (mu_range[2] > 0.1) {
      txt <- paste0(txt, "Moderate ionic strength; activity corrections are significant but within the valid range of the selected database.")
    } else {
      txt <- paste0(txt, "Low ionic strength; activity coefficients are near unity and mineral solubility calculations are well-constrained.")
    }
    sections <- c(sections, txt)
  }

  if (length(sections) == 0) return("")

  paste0(
    "<div class='interpretation'>",
    "<strong>Automated Geochemical Interpretation</strong> (", paste(db_used, collapse = ", "), ")<br><br>",
    paste(sections, collapse = "<br><br>"),
    "</div>"
  )
}

#' Compare SI results across multiple PHREEQC databases (side-by-side).
compare_phreeqc_databases <- function(con, site_type = NULL) {
  conditions <- "pr.parameter LIKE 'SI_%' AND pr.value > -100"
  params <- list()
  if (!is.null(site_type)) {
    conditions <- paste(conditions, "AND l.site_type = ?")
    params <- c(params, site_type)
  }

  data <- dbGetQuery(con, sprintf("
    SELECT pr.sample_id, l.name AS location_name, l.site_type, pr.parameter, pr.value, pr.db_file
    FROM PHREEQC_Results pr
    JOIN Samples s ON pr.sample_id = s.sample_id
    JOIN Locations l ON s.location_id = l.location_id
    WHERE %s
  ", conditions), params = if (length(params) > 0) params else NULL)

  if (nrow(data) == 0 || length(unique(data$db_file)) < 2) return(NULL)

  data |>
    mutate(mineral = gsub("^SI_", "", parameter)) |>
    select(sample_id, location_name, site_type, mineral, value, db_file) |>
    tidyr::pivot_wider(
      id_cols = c(sample_id, location_name, site_type, mineral),
      names_from = db_file, values_from = value, names_prefix = "SI_",
      values_fn = list(value = ~ mean(., na.rm = TRUE))
    ) |>
    mutate(across(where(is.numeric) & starts_with("SI_"), ~ round(., 2))) |>
    arrange(sample_id, mineral)
}
