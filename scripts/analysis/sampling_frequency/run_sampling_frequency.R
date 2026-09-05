# ------------------------------------------------------------
# run_sampling_frequency.R
#
# Purpose:
# Single entry point for the chloride sampling-frequency workflow
# (scripts 02-05 in this folder). Mirrors the style of
# scripts/run_pipeline.R: sourced, not executed top-to-bottom on
# source(), and driven by one function you call explicitly.
#
# Design goals:
#   - Idempotent: re-running with unchanged inputs produces the same
#     decisions and does not silently duplicate or corrupt state.
#     Concretely: model artifacts are only (re-)saved when there is
#     a real, sufficient paired dataset AND the caller opts in via
#     `refit_models = TRUE`; each stage is read-only otherwise and
#     safe to re-run at any time to check status.
#   - No silent defaults for scientific decisions: RMSE / flux-error
#     thresholds must be supplied explicitly to reach a
#     recommendation (matching 05_recommendation_report.R's design),
#     and synthetic self-test data is never used to produce a "real"
#     recommendation -- it must be requested explicitly.
#   - Never stops the whole workflow because a later stage's
#     prerequisite (real paired data) isn't met yet; it reports
#     status per stage and skips forward, since each stage is
#     genuinely independent until a real dataset exists.
#
# Usage:
#   source("scripts/analysis/sampling_frequency/run_sampling_frequency.R")
#   con <- DBI::dbConnect(RSQLite::SQLite(), "database/geochem_operational.sqlite")
#   status <- run_sampling_frequency_pipeline(con)
#   # ... once the PI has agreed on thresholds:
#   status <- run_sampling_frequency_pipeline(
#     con,
#     rmse_threshold_mgL = 1,
#     refit_models = TRUE
#   )
#   DBI::dbDisconnect(con)
# ------------------------------------------------------------

library(DBI)

source(file.path("scripts", "analysis", "sampling_frequency", "02_specific_conductance.R"))
source(file.path("scripts", "analysis", "sampling_frequency", "03_chloride_models.R"))
source(file.path("scripts", "analysis", "sampling_frequency", "04_monte_carlo_subsampling.R"))
source(file.path("scripts", "analysis", "sampling_frequency", "05_recommendation_report.R"))

#' Time and message-wrap one pipeline stage (mirrors run_pipeline.R's run_step())
run_sf_stage <- function(label, expr) {
  message("\n--- ", label, " ---")
  t0 <- Sys.time()
  result <- tryCatch(expr, error = function(e) {
    message("  FAILED: ", conditionMessage(e))
    NULL
  })
  message("  (", round(difftime(Sys.time(), t0, units = "secs"), 2), " sec)")
  result
}

#' Run the full sampling-frequency workflow against a live database
#'
#' @param con open DBI connection to geochem_operational.sqlite (or demo)
#' @param calibration_tolerance_min time tolerance (minutes) for matching a
#'   field conductivity check to a logger observation (passed to 02)
#' @param chloride_tolerance_min time tolerance (minutes) for matching a
#'   chloride sample to a logger observation (passed to 03)
#' @param refit_models if TRUE and enough real chloride/SC pairs exist,
#'   fit and save lm/gam/rf models via save_final_chloride_models(). Never
#'   fits/saves on synthetic data, and never refits automatically just
#'   because the function was called again -- this is the one
#'   disk-writing step, so it is opt-in.
#' @param rmse_threshold_mgL,flux_pct_threshold explicit error thresholds
#'   (see 05_recommendation_report.R); if both NULL, no recommendation is
#'   attempted, by design.
#' @param min_pairs_for_cv minimum real chloride/SC pairs required before
#'   attempting cross-validated model fitting (default 25; blocked CV with
#'   the default initial/assess/skip needs at least this many to form a
#'   fold).
#' @return an invisible list with one element per stage, each recording
#'   status ("skipped_insufficient_data" | "ok" | "not_attempted") and any
#'   data produced, so calling code (or a future console UI) can inspect
#'   what happened without re-parsing messages.
run_sampling_frequency_pipeline <- function(con,
                                             calibration_tolerance_min = 15,
                                             chloride_tolerance_min = 60,
                                             refit_models = FALSE,
                                             rmse_threshold_mgL = NULL,
                                             flux_pct_threshold = NULL,
                                             min_pairs_for_cv = 25) {

  status <- list()

  # ---- Stage 1: SC temperature-compensation recalibration ----
  status$calibration <- run_sf_stage("1/4 Specific-conductance calibration", {
    calib <- recalibrate_sc_coefficient(con, tolerance_min = calibration_tolerance_min)
    message(
      "  coefficient = ", round(calib$coefficient, 5),
      " (n_pairs = ", calib$n_pairs, "; USGS default = 0.0191)"
    )
    if (calib$n_pairs < 5) {
      message("  -> Using USGS default; collect >=5 field conductivity checks ",
              "at active logger locations to enable recalibration.")
    }
    calib
  })

  # ---- Stage 2: real chloride/SC pairs, and (optionally) model fitting ----
  status$chloride_models <- run_sf_stage("2/4 Chloride prediction models", {
    pairs <- get_chloride_conductance_pairs(con, tolerance_min = chloride_tolerance_min)

    # NOTE: deliberately if/else, not an early return() -- a `return()`
    # written inside this block would unwind run_sampling_frequency_pipeline()
    # itself (the block is evaluated as a promise in that function's frame),
    # not just this stage, silently skipping stages 3-4.
    if (nrow(pairs) < min_pairs_for_cv) {
      message(
        "  Only ", nrow(pairs), " real chloride/SC pair(s) available (need >= ",
        min_pairs_for_cv, " for cross-validated fitting) -- skipping model fit. ",
        "This is expected until chloride samples are collected during an active ",
        "logger deployment window; see notebooks/01_conductivity_temporal_structure.qmd."
      )
      list(status = "skipped_insufficient_data", n_pairs = nrow(pairs), pairs = pairs)
    } else {
      cv <- evaluate_chloride_models(pairs)
      message("  Cross-validated on ", nrow(pairs), " real pairs:")
      print(aggregate(cbind(rmse, mae) ~ model, data = cv, FUN = mean))

      fitted <- NULL
      if (refit_models) {
        fitted <- save_final_chloride_models(pairs)
        message("  Models refit and saved (refit_models = TRUE).")
      } else {
        message("  refit_models = FALSE -- CV metrics reported above but no model ",
                "artifacts written. Call with refit_models = TRUE once satisfied.")
      }

      list(status = "ok", n_pairs = nrow(pairs), pairs = pairs, cv = cv, fitted = fitted)
    }
  })

  # ---- Stage 3: Monte Carlo sampling-frequency simulation ----
  # Requires a dense reference series. Until a fitted model (stage 2) exists
  # on real data, there is nothing honest to feed this stage, so it is only
  # attempted when stage 2 actually fit models on real pairs.
  status$monte_carlo <- run_sf_stage("3/4 Monte Carlo sampling-frequency design", {
    if (is.null(status$chloride_models) || status$chloride_models$status != "ok" ||
        is.null(status$chloride_models$fitted)) {
      message("  No real fitted chloride model available yet (see stage 2) -- ",
              "skipping. This stage needs a dense reference series, which can ",
              "only honestly come from a model fit to real paired data.")
      list(status = "skipped_insufficient_data")
    } else {
      message("  Real fitted model available; building a reference series from it ",
              "is a modeling decision (which conductivity window, which model) left ",
              "for the analyst -- run monte_carlo_sampling_frequency() directly with ",
              "that reference series once ready.")
      list(status = "not_attempted", reason = "reference series construction is analyst-driven")
    }
  })

  # ---- Stage 4: recommendation ----
  status$recommendation <- run_sf_stage("4/4 Sampling-frequency recommendation", {
    if (is.null(rmse_threshold_mgL) && is.null(flux_pct_threshold)) {
      message("  No rmse_threshold_mgL / flux_pct_threshold supplied -- no ",
              "recommendation attempted (this must be an explicit, PI-agreed ",
              "decision; see 05_recommendation_report.R).")
      list(status = "not_attempted", reason = "no threshold supplied")
    } else if (is.null(status$monte_carlo) || is.null(status$monte_carlo$summary)) {
      message("  No Monte Carlo summary available yet (see stage 3) -- ",
              "cannot make a recommendation.")
      list(status = "skipped_insufficient_data")
    } else {
      rec <- recommend_sampling_frequency(
        status$monte_carlo$summary,
        rmse_threshold_mgL = rmse_threshold_mgL,
        flux_pct_threshold = flux_pct_threshold
      )
      list(status = "ok", recommendation = rec)
    }
  })

  message("\n=== Sampling-frequency pipeline complete ===")
  invisible(status)
}
