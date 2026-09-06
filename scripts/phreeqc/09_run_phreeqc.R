#09_run_phreeqc
#
# Core PHREEQC speciation/saturation-index/geothermometry pipeline.
# Ported from the IGNIS project's 07_run_phreeqc.R (same author, same
# analytical needs) with the following changes:
#  - takes `con` (never opens its own connection)
#  - batches/organizes output by `site_type` (Locations.site_type),
#    not `prospect` (this project has no prospect concept -- see the
#    2026-09-06 planning session's confirmed decision)
#  - writes under phreeqc/runs/<site_type>/ (this project's existing,
#    previously-empty reserved directory), not output/<prospect>/
#  - table/column names updated throughout to this project's schema
#
# Usage:
#   build_phreeqc_solutions(con)     # from 08_build_phreeqc_tables.R
#   run_phreeqc_pipeline(con)                      # auto-selects database
#   run_phreeqc_pipeline(con, phreeqc_db = "llnl")  # force LLNL
#   run_phreeqc_pipeline(con, dry_run = TRUE)       # preview only, no exe call
#   run_phreeqc_multi(con)                          # compare multiple databases
#   view_phreeqc_results(con)

library(DBI)
library(dplyr)

#' Run the PHREEQC pipeline for eligible samples.
#'
#' Queries eligible samples, generates input files, executes PHREEQC,
#' parses results, and stores them in the database. If an entire batch
#' fails to converge, falls back to a different thermodynamic database
#' for the whole batch, then to retrying each sample individually (across
#' the main database and fallbacks) -- so one non-convergent sample can't
#' silently drop every other sample in its site_type group. Any sample
#' that still fails with everything tried is logged to
#' PHREEQC_Run_Failures (see get_phreeqc_run_failures()) instead of just
#' vanishing from downstream SI results.
#'
#' @param con DBI connection.
#' @param site_type Character. Filter by Locations.site_type (NULL for all).
#' @param sample_ids Character/integer vector of specific sample_ids.
#' @param phreeqc_db Character. Database key, or "auto" (default) to
#'   recommend based on sample characteristics.
#' @param si_minerals Character vector of minerals for SI output (NULL = default set).
#' @param dry_run Logical. If TRUE, report eligibility/database choice without executing PHREEQC.
#' @return Invisible list summarizing what was processed.
run_phreeqc_pipeline <- function(con, site_type = NULL, sample_ids = NULL,
                                  phreeqc_db = "auto", si_minerals = NULL,
                                  dry_run = FALSE) {
  if (!dry_run) check_phreeqc()

  eligibility <- get_phreeqc_eligible(con, site_type = site_type, sample_ids = sample_ids)
  eligible <- eligibility$eligible
  rejected <- eligibility$rejected

  scope <- if (!is.null(site_type)) site_type else "all site types"
  message("\n--- PHREEQC Eligibility (", scope, ") ---")
  message("  Eligible:  ", nrow(eligible), " samples")
  message("  Rejected:  ", nrow(rejected), " samples")

  if (nrow(rejected) > 0) {
    message("\n  Rejection details:")
    for (i in seq_len(min(nrow(rejected), 20))) {
      r <- rejected[i, ]
      message(sprintf("    %s (%s): %s", r$sample_id, r$location_name, r$reason))
    }
    if (nrow(rejected) > 20) message("    ... and ", nrow(rejected) - 20, " more")
  }

  if (nrow(eligible) == 0) {
    message("\n  No eligible samples for PHREEQC modeling.")
    return(invisible(list(eligible = 0, rejected = nrow(rejected), results = 0)))
  }

  if (identical(phreeqc_db, "auto")) {
    recommendation <- recommend_phreeqc_db(eligible)
    db_key <- recommendation$recommended
    message("\n  Database recommendation: ", PHREEQC_DATABASES[[db_key]]$label)
    message("  Reason: ", recommendation$reason)
    message("  Alternatives: ", paste(recommendation$alternatives, collapse = ", "))
  } else {
    db_key <- phreeqc_db
    if (!db_key %in% names(PHREEQC_DATABASES)) {
      stop("Unknown database: ", db_key, ". Available: ", paste(names(PHREEQC_DATABASES), collapse = ", "))
    }
    message("\n  Database: ", PHREEQC_DATABASES[[db_key]]$label, " (user-specified)")
  }

  db_path <- get_phreeqc_db_path(db_key)
  db_info <- PHREEQC_DATABASES[[db_key]]
  db_filename <- db_info$name

  if (dry_run) {
    message("\n  [DRY RUN] Would process ", nrow(eligible), " samples with ", db_info$label)
    eligible_summary <- eligible |> group_by(site_type) |> summarise(n = n(), .groups = "drop")
    for (i in seq_len(nrow(eligible_summary))) {
      message(sprintf("    %s: %d samples", eligible_summary$site_type[i], eligible_summary$n[i]))
    }
    return(invisible(list(eligible = nrow(eligible), rejected = nrow(rejected), results = 0,
                           eligible_data = eligible, db_key = db_key, db_info = db_info)))
  }

  group_key <- eligible |> mutate(site_type = ifelse(is.na(site_type), "unknown", site_type)) |> pull(site_type)
  eligible$.group <- group_key
  groups <- split(eligible, eligible$.group)

  total_results <- 0
  failed_sample_ids <- character(0)
  fallbacks <- c("sit", "pitzer")

  try_one_sample <- function(one, ak, group_dir) {
    if (!ak %in% names(PHREEQC_DATABASES)) return(FALSE)
    ak_info <- PHREEQC_DATABASES[[ak]]
    ak_path <- tryCatch(get_phreeqc_db_path(ak), error = function(e) NULL)
    if (is.null(ak_path)) return(FALSE)
    ak_minerals <- if (!is.null(si_minerals)) si_minerals else get_si_minerals(ak)
    one_clean <- gsub("[^A-Za-z0-9_-]", "_", as.character(one$sample_id))
    ak_input <- file.path(group_dir, "phreeqc_inputs", paste0(one_clean, "_", ak, ".pqi"))
    ak_sel   <- file.path(group_dir, "phreeqc_outputs", paste0(one_clean, "_", ak, "_selected.tsv"))
    ak_main  <- file.path(group_dir, "phreeqc_outputs", paste0(one_clean, "_", ak, ".pqo"))
    write_phreeqc_input(one, input_file = ak_input, output_file = ak_sel, si_minerals = ak_minerals)
    ak_exit <- run_phreeqc(ak_input, output_file = ak_main, db_file = ak_path)
    if (ak_exit == 0 && file.exists(ak_sel)) {
      store_phreeqc_results(con, ak_sel, sample_ids = one$sample_id, db_file = ak_info$name)
      message("  \u2713 ", one$sample_id, " succeeded individually with ", ak_info$label)
      total_results <<- total_results + length(ak_minerals)
      TRUE
    } else FALSE
  }

  for (grp in groups) {
    g <- unique(grp$.group)
    message("\n=== Processing site_type: ", g, " (", nrow(grp), " samples) [", db_info$label, "] ===")

    group_clean <- gsub("[^A-Za-z0-9_-]", "_", g)
    group_dir <- file.path("phreeqc", "runs", group_clean)
    dir.create(file.path(group_dir, "phreeqc_inputs"), recursive = TRUE, showWarnings = FALSE)
    dir.create(file.path(group_dir, "phreeqc_outputs"), recursive = TRUE, showWarnings = FALSE)

    file_suffix <- paste0(group_clean, "_", db_key)
    input_file  <- file.path(group_dir, "phreeqc_inputs", paste0(file_suffix, ".pqi"))
    sel_output  <- file.path(group_dir, "phreeqc_outputs", paste0(file_suffix, "_selected.tsv"))
    main_output <- file.path(group_dir, "phreeqc_outputs", paste0(file_suffix, ".pqo"))

    si_minerals_run <- if (!is.null(si_minerals)) si_minerals else get_si_minerals(db_key)
    write_phreeqc_input(grp, input_file = input_file, output_file = sel_output, si_minerals = si_minerals_run)

    exit_code <- run_phreeqc(input_file, output_file = main_output, db_file = db_path)

    if (exit_code != 0) {
      retry_ok <- FALSE
      for (fb_key in fallbacks) {
        if (fb_key == db_key || !fb_key %in% names(PHREEQC_DATABASES)) next
        fb_info <- PHREEQC_DATABASES[[fb_key]]
        message("  Retrying ", g, " with fallback: ", fb_info$label)
        fb_path <- tryCatch(get_phreeqc_db_path(fb_key), error = function(e) NULL)
        if (is.null(fb_path)) next
        fb_minerals <- if (!is.null(si_minerals)) si_minerals else get_si_minerals(fb_key)
        fb_input <- file.path(group_dir, "phreeqc_inputs", paste0(group_clean, "_", fb_key, ".pqi"))
        fb_sel   <- file.path(group_dir, "phreeqc_outputs", paste0(group_clean, "_", fb_key, "_selected.tsv"))
        fb_main  <- file.path(group_dir, "phreeqc_outputs", paste0(group_clean, "_", fb_key, ".pqo"))
        write_phreeqc_input(grp, input_file = fb_input, output_file = fb_sel, si_minerals = fb_minerals)
        fb_exit <- run_phreeqc(fb_input, output_file = fb_main, db_file = fb_path)
        if (fb_exit == 0 && file.exists(fb_sel)) {
          store_phreeqc_results(con, fb_sel, sample_ids = grp$sample_id, db_file = fb_info$name)
          message("  \u2713 Fallback successful: ", fb_info$label)
          total_results <- total_results + nrow(grp) * length(fb_minerals)
          retry_ok <- TRUE
          break
        }
      }

      if (!retry_ok) {
        if (nrow(grp) > 1) {
          message("  Batch failed for ", g, " -- retrying sample-by-sample")
          attempt_dbs <- unique(c(db_key, fallbacks))
          for (j in seq_len(nrow(grp))) {
            one <- grp[j, ]
            sample_ok <- FALSE
            for (ak in attempt_dbs) {
              if (try_one_sample(one, ak, group_dir)) { sample_ok <- TRUE; break }
            }
            if (sample_ok) {
              clear_phreeqc_run_failure(con, one$sample_id)
            } else {
              failed_sample_ids <- c(failed_sample_ids, as.character(one$sample_id))
              tried_labels <- paste(sapply(attempt_dbs, function(k)
                if (k %in% names(PHREEQC_DATABASES)) PHREEQC_DATABASES[[k]]$label else k), collapse = ", ")
              warning("PHREEQC did not converge for ", one$sample_id, " with any database (", tried_labels, "). Skipping this sample.")
              record_phreeqc_run_failure(con, sample_id = one$sample_id, location_name = one$location_name,
                                          site_type = one$site_type,
                                          reason = sprintf("Did not converge with any thermodynamic database tried (%s)", tried_labels))
            }
          }
        } else {
          one <- grp[1, ]
          failed_sample_ids <- c(failed_sample_ids, as.character(one$sample_id))
          warning("PHREEQC failed for ", g, " with all databases. Skipping.")
          record_phreeqc_run_failure(con, sample_id = one$sample_id, location_name = one$location_name,
                                      site_type = one$site_type,
                                      reason = "Did not converge with any thermodynamic database tried")
        }
      } else {
        for (sid in grp$sample_id) clear_phreeqc_run_failure(con, sid)
      }
      next
    }

    if (file.exists(sel_output)) {
      store_phreeqc_results(con, sel_output, sample_ids = grp$sample_id, db_file = db_filename)
      n_res <- dbGetQuery(con, sprintf(
        "SELECT COUNT(*) AS n FROM PHREEQC_Results WHERE sample_id IN (%s) AND run_date = '%s' AND db_file = '%s'",
        paste(grp$sample_id, collapse = ","), Sys.Date(), db_filename))$n
      total_results <- total_results + n_res
      for (sid in grp$sample_id) clear_phreeqc_run_failure(con, sid)
    } else {
      warning("SELECTED_OUTPUT file not found: ", sel_output)
    }
  }

  message("\n--- PHREEQC Pipeline Complete ---")
  message("  Samples processed: ", nrow(eligible))
  message("  Result rows stored: ", total_results)
  if (length(failed_sample_ids) > 0) {
    message("  Convergence failures: ", length(failed_sample_ids), " (",
            paste(failed_sample_ids, collapse = ", "), ") -- see PHREEQC_Run_Failures / get_phreeqc_run_failures()")
  }
  message("  Run date:  ", Sys.Date())
  message("  Database:  ", db_info$label, " (", db_filename, ")")
  message("  Activity:  ", db_info$activity)
  message("  Temp range: ", db_info$temp_range[1], "-", db_info$temp_range[2], "C")

  invisible(list(eligible = nrow(eligible), rejected = nrow(rejected), results = total_results,
                 failed = failed_sample_ids, db_key = db_key, db_file = db_filename))
}

#' Run PHREEQC with multiple thermodynamic databases for comparison.
run_phreeqc_multi <- function(con, databases = c("phreeqc", "llnl"), site_type = NULL, ...) {
  message("\n========================================")
  message("  Multi-Database PHREEQC Comparison")
  message("  Databases: ", paste(databases, collapse = ", "))
  message("========================================")

  results <- list()
  for (db_key in databases) {
    message("\n>>> Running with: ", PHREEQC_DATABASES[[db_key]]$label, " <<<")
    results[[db_key]] <- run_phreeqc_pipeline(con, site_type = site_type, phreeqc_db = db_key, ...)
  }

  message("\n========================================")
  message("  Multi-Database Comparison Complete")
  message("========================================")
  for (db_key in databases) {
    r <- results[[db_key]]
    message(sprintf("  %-12s: %d samples, %d result rows", db_key, r$eligible, r$results))
  }
  invisible(results)
}

#' View existing PHREEQC results from the database.
view_phreeqc_results <- function(con, site_type = NULL, db_file = NULL) {
  sql <- "
    SELECT pr.sample_id, l.name AS location_name, l.site_type,
           pr.run_date, pr.parameter, pr.value, pr.db_file
    FROM PHREEQC_Results pr
    JOIN Samples s ON pr.sample_id = s.sample_id
    JOIN Locations l ON s.location_id = l.location_id
  "
  conditions <- character()
  params <- list()
  if (!is.null(site_type)) { conditions <- c(conditions, "l.site_type = ?"); params <- c(params, site_type) }
  if (!is.null(db_file)) { conditions <- c(conditions, "pr.db_file = ?"); params <- c(params, db_file) }
  if (length(conditions) > 0) sql <- paste(sql, "WHERE", paste(conditions, collapse = " AND "))

  result <- if (length(params) > 0) dbGetQuery(con, sql, params = params) else dbGetQuery(con, sql)
  result |> tibble::as_tibble() |> arrange(site_type, sample_id, db_file, parameter)
}

# =============================================================================
# TEMPERATURE SWEEP FOR MINERAL EQUILIBRATION GEOTHERMOMETRY
# =============================================================================

format_phreeqc_temp_sweep <- function(df, output_file = "phreeqc_sweep.tsv",
                                       temp_range = c(25, 300), temp_step = 25,
                                       si_minerals = DEFAULT_SI_MINERALS) {
  temps <- seq(temp_range[1], temp_range[2], by = temp_step)
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
    lines <- c(lines, sol_lines, "")
    lines <- c(lines, sprintf("REACTION_TEMPERATURE %d", i), paste("   ", paste(temps, collapse = "  ")), "END", "")
  }

  lines
}

parse_phreeqc_sweep_output <- function(selected_output_file, sample_ids) {
  if (!file.exists(selected_output_file)) stop("SELECTED_OUTPUT file not found: ", selected_output_file)

  raw <- read.delim(selected_output_file, sep = "\t", stringsAsFactors = FALSE, check.names = FALSE) |>
    tibble::as_tibble(.name_repair = "universal")
  names(raw) <- stringr::str_replace_all(names(raw), "\\.", "_")

  if ("sim" %in% names(raw)) raw <- raw |> mutate(sample_id = sample_ids[sim])
  else if ("soln" %in% names(raw)) raw <- raw |> mutate(sample_id = sample_ids[soln])

  temp_col <- grep("^temp", names(raw), value = TRUE, ignore.case = TRUE)
  if (length(temp_col) > 0) raw <- raw |> rename(temperature_C = !!temp_col[1])

  si_cols <- grep("^si_", names(raw), value = TRUE, ignore.case = TRUE)
  act_cols <- grep("^la_|^a_", names(raw), value = TRUE, ignore.case = TRUE)
  other_cols <- intersect(names(raw), c("pH", "pe", "mu"))
  param_cols <- c(si_cols, act_cols, other_cols)

  if (length(param_cols) == 0) { warning("No parameter columns found in sweep output."); return(tibble::tibble()) }

  raw |>
    select(sample_id, temperature_C, all_of(param_cols)) |>
    tidyr::pivot_longer(cols = -c(sample_id, temperature_C), names_to = "parameter", values_to = "value") |>
    mutate(
      parameter = stringr::str_replace(parameter, "^si_", "SI_"),
      parameter = stringr::str_replace(parameter, "^la_", "log_activity_"),
      parameter = stringr::str_replace(parameter, "^mu$", "ionic_strength")
    ) |>
    filter(!is.na(value))
}

store_phreeqc_sweep <- function(con, sweep_results, db_file = "phreeqc.dat") {
  results <- sweep_results |>
    mutate(run_date = as.character(Sys.Date()), db_file = basename(db_file)) |>
    select(sample_id, temperature_C, parameter, value, db_file, run_date)

  for (sid in unique(results$sample_id)) {
    dbExecute(con, "DELETE FROM PHREEQC_Temp_Sweep WHERE sample_id = ? AND db_file = ?",
              params = list(sid, basename(db_file)))
  }
  dbWriteTable(con, "PHREEQC_Temp_Sweep", results, append = TRUE)
  message("Stored ", nrow(results), " temperature sweep rows for ", length(unique(results$sample_id)), " samples.")
}

#' Run PHREEQC temperature sweep for mineral equilibration geothermometry.
run_phreeqc_temp_sweep <- function(con, site_type = NULL, phreeqc_db = "auto",
                                    temp_range = c(25, 300), temp_step = 25,
                                    sample_ids = NULL) {
  check_phreeqc()

  eligibility <- get_phreeqc_eligible(con, site_type = site_type, sample_ids = sample_ids)
  eligible <- eligibility$eligible

  if (nrow(eligible) == 0) { message("No eligible samples for temperature sweep."); return(invisible(list(n_samples = 0))) }

  scope <- if (!is.null(site_type)) site_type else "all site types"
  message("\n--- Temperature Sweep (", scope, ") ---")
  message("  Eligible samples: ", nrow(eligible))
  message("  Temperature range: ", temp_range[1], "-", temp_range[2], "\u00B0C")
  message("  Step size: ", temp_step, "\u00B0C")

  if (identical(phreeqc_db, "auto")) {
    recommendation <- recommend_phreeqc_db(eligible)
    db_key <- recommendation$recommended
    message("  Database: ", PHREEQC_DATABASES[[db_key]]$label)
  } else db_key <- phreeqc_db

  db_path <- get_phreeqc_db_path(db_key)
  db_name <- PHREEQC_DATABASES[[db_key]]$name

  max_db_temp <- PHREEQC_DATABASES[[db_key]]$temp_range[2]
  if (temp_range[2] > max_db_temp) {
    message(sprintf("  WARNING: Sweep max (%d\u00B0C) exceeds database limit (%d\u00B0C) for %s.", temp_range[2], max_db_temp, db_name))
  }

  out_dir <- file.path("phreeqc", "runs", "temp_sweep")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  input_file  <- file.path(out_dir, sprintf("sweep_%s_%s.pqi", db_key, timestamp))
  output_file <- file.path(out_dir, sprintf("sweep_%s_%s.pqo", db_key, timestamp))
  sel_out     <- file.path(out_dir, sprintf("sweep_%s_%s.tsv", db_key, timestamp))

  sweep_lines <- format_phreeqc_temp_sweep(eligible, output_file = sel_out, temp_range = temp_range, temp_step = temp_step)
  writeLines(sweep_lines, input_file)
  message("  Wrote sweep input: ", input_file, " (", nrow(eligible), " samples)")

  exit_code <- run_phreeqc(input_file, output_file, db_file = db_path)

  all_sweep_results <- tibble::tibble()
  if (exit_code == 0 && file.exists(sel_out)) {
    all_sweep_results <- parse_phreeqc_sweep_output(sel_out, eligible$sample_id)
    store_phreeqc_sweep(con, all_sweep_results, db_file = db_name)
  } else {
    message("  Sweep failed to converge as a batch.")
  }

  eq_temps <- tibble::tibble()
  if (nrow(all_sweep_results) > 0) {
    eq_temps <- estimate_equilibration_temperatures(all_sweep_results)
    if (nrow(eq_temps) > 0) {
      message("\n  Estimated equilibration temperatures:")
      for (i in seq_len(min(nrow(eq_temps), 20))) {
        r <- eq_temps[i, ]
        message(sprintf("    %s (%s): %.0f\u00B0C", r$sample_id, r$mineral, r$eq_temperature_C))
      }
    }
  }

  invisible(list(n_samples = nrow(eligible), exit_code = exit_code, n_results = nrow(all_sweep_results), eq_temps = eq_temps))
}

#' Estimate equilibration temperatures from temperature sweep SI data
#' (zero-crossing linear interpolation).
estimate_equilibration_temperatures <- function(sweep_data) {
  si_data <- sweep_data |>
    filter(grepl("^SI_", parameter)) |>
    mutate(mineral = gsub("^SI_", "", parameter)) |>
    filter(is.finite(value), abs(value) < 100)

  si_data |>
    arrange(sample_id, mineral, temperature_C) |>
    group_by(sample_id, mineral) |>
    filter(n() >= 2) |>
    reframe({
      vals <- value; temps <- temperature_C; n <- length(vals)
      eq_temps <- numeric()
      for (j in 2:n) {
        if (!is.na(vals[j-1]) && !is.na(vals[j]) && vals[j-1] * vals[j] < 0) {
          t_eq <- temps[j-1] + (0 - vals[j-1]) * (temps[j] - temps[j-1]) / (vals[j] - vals[j-1])
          eq_temps <- c(eq_temps, t_eq)
        }
      }
      if (length(eq_temps) > 0) tibble::tibble(eq_temperature_C = eq_temps) else tibble::tibble(eq_temperature_C = numeric())
    }) |>
    filter(eq_temperature_C > 0, eq_temperature_C < 400)
}

# =============================================================================
# ACTIVITY-BASED GEOTHERMOMETERS
# =============================================================================

#' Calculate activity-based Na/K geothermometer temperatures from PHREEQC
#' speciation (Giggenbach 1988; Fournier 1979).
calculate_activity_geothermometers <- function(con, site_type = NULL, db_file = NULL) {
  conditions <- character()
  params <- list()
  if (!is.null(site_type)) { conditions <- c(conditions, "l.site_type = ?"); params <- c(params, site_type) }
  if (!is.null(db_file)) { conditions <- c(conditions, "pr.db_file = ?"); params <- c(params, db_file) }
  conditions <- c(conditions, "(pr.parameter LIKE 'log_activity_%' OR pr.parameter IN ('pH', 'temperature', 'ionic_strength'))")
  where <- paste("WHERE", paste(conditions, collapse = " AND "))

  sql <- sprintf("
    SELECT pr.sample_id, l.name AS location_name, l.site_type, pr.parameter, pr.value, pr.db_file
    FROM PHREEQC_Results pr
    JOIN Samples s ON pr.sample_id = s.sample_id
    JOIN Locations l ON s.location_id = l.location_id
    %s
  ", where)

  data <- if (length(params) > 0) dbGetQuery(con, sql, params = params) else dbGetQuery(con, sql)

  if (nrow(data) == 0 || !any(grepl("log_activity", data$parameter))) {
    message("No activity data available. Run the pipeline with expanded SELECTED_OUTPUT first.")
    return(tibble::tibble())
  }

  act_wide <- data |> tidyr::pivot_wider(id_cols = c(sample_id, location_name, site_type, db_file),
                                          names_from = parameter, values_from = value)

  col_names <- names(act_wide)
  na_col <- col_names[grepl("log_activity_Na", col_names)][1]
  k_col  <- col_names[grepl("log_activity_K[^a-z]", col_names, ignore.case = FALSE)][1]
  has_activities <- !is.na(na_col) && !is.na(k_col)

  results <- act_wide |>
    mutate(
      log_aNa_aK = if (has_activities) .data[[na_col]] - .data[[k_col]] else NA_real_,
      T_NaK_gigg_activity = if (has_activities) 1390 / (log_aNa_aK + 1.75) - 273.15 else NA_real_,
      T_NaK_four_activity = if (has_activities) 1217 / (log_aNa_aK + 1.483) - 273.15 else NA_real_
    )

  results |> select(sample_id, location_name, site_type, db_file,
                     any_of(c("log_aNa_aK", "T_NaK_gigg_activity", "T_NaK_four_activity", "ionic_strength")))
}
