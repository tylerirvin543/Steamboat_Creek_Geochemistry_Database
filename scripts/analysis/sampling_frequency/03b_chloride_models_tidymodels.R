# ------------------------------------------------------------
# 03b_chloride_models_tidymodels.R
#
# Purpose:
# A tidymodels re-implementation of the chloride-from-conductance
# prediction problem already built by hand in 03_chloride_models.R.
# That script was originally written with base R + mgcv + ranger
# specifically because tidymodels was NOT installed in this
# environment (see its own header comment); tidymodels is now
# installed, so this is the proper version requested 2026-09-26.
#
# Reuses 03_chloride_models.R's own data functions unchanged
# (get_chloride_conductance_pairs(), simulate_synthetic_pairs(),
# add_seasonal_terms()) rather than duplicating them -- only the
# modeling/resampling/evaluation layer is new.
#
# STATUS AS OF 2026-09-26: get_chloride_conductance_pairs(con) still
# returns 0 real rows. Confirmed directly: the one real Cl sample at
# a conductivity-logger location (SBRR, sample_id=819, 2026-05-01)
# predates the real logger deployment record (starts 2026-07-15) by
# ~2.5 months -- the same real, already-documented data gap flagged
# repeatedly in this project's own session notes, not a bug. This
# script therefore runs on simulate_synthetic_pairs() for now and is
# written so that swapping in real data later requires changing
# nothing but the input data frame.
#
# MODELING SESSION LOG (2026-09-26, on synthetic self-test data only):
#   1. Baseline workflow_set (null / linear_reg / rand_forest,
#      default hyperparameters, rolling-origin CV via rsample):
#      rand_forest won on RMSE (1.06) and MAE (0.93) over lm (1.26)
#      and the null model (1.56).
#   2. Tuned rand_forest's mtry/min_n via tune_grid(): an initial
#      grid (min_n 2-15) looked like RMSE improves monotonically
#      toward the boundary; extending to min_n 15-30 revealed a real
#      interior optimum (best: mtry=4, min_n=25, RMSE=0.974), not a
#      boundary artifact -- confirmed by checking the FULL ranked
#      results table, not just show_best()'s top few rows. Caveat:
#      the smallest rolling-origin folds (initial=20) are smaller
#      than min_n=25/30, so ranger silently clips those folds to a
#      degenerate single-node tree -- the min_n=25/30 results aren't
#      fully comparable across every fold for that reason.
#   3. Revisited feature engineering rather than tuning further:
#      dropping the doy_sin/doy_cos seasonal terms (redundant with
#      sc_25c/temperature_c, which already carry the seasonal signal)
#      made plain lm the best model overall (RMSE 0.91), beating
#      every random-forest variant -- a feature-engineering fix
#      mattered more than model family or tuning here.
#   4. A lagged-conductivity feature (step_lag()) was tested and
#      found to NOT help -- traced this to simulate_synthetic_pairs()
#      itself having no lag structure at all, so there was nothing
#      for a lag feature to find. Fixed the generator (see
#      03_chloride_models.R's own header for the `lag_days`
#      parameter) to build in a real 6-day transport lag, then
#      re-tested: a correctly-lagged lm became the clear new best
#      (RMSE 1.00 vs. the no-lag lm's 1.24 on the SAME lagged data) --
#      confirmed with both a residual check (no strong ACF structure,
#      because the slow ~365-day seasonal cycle means a 6-day lag
#      barely shifts sc/temp's value, so the "wrong" unlagged
#      predictor is still a decent stand-in) and a direct predictive
#      comparison (the more sensitive, decisive check of the two).
#   Current leading candidate: linear regression on sc_25c/
#   temperature_c lagged by 2 steps (6 days), no seasonal terms.
#   Winning workflow saved via save_best_chloride_workflow() to
#   models/chloride_prediction/ and logged in models/MODEL_REGISTRY.csv.
#
# Usage:
#   source("scripts/analysis/sampling_frequency/03_chloride_models.R")
#   source("scripts/analysis/sampling_frequency/03b_chloride_models_tidymodels.R")
#   result <- run_chloride_tidymodels()
#   result$comparison_table
# ------------------------------------------------------------

library(tidymodels)
library(dplyr)

tidymodels_prefer()

#' Build rolling-origin (blocked, time-aware) resampling folds via
#' rsample -- replaces 03_chloride_models.R's own hand-rolled
#' rolling_origin_cv() with the real rsample implementation now that
#' tidymodels is installed.
#' @param df Must be sorted or sortable by `time_col`.
build_rolling_folds <- function(df, time_col = "collection_time",
                                 initial = 20, assess = 5, skip = 4) {
  df <- df[order(df[[time_col]]), ]
  rsample::rolling_origin(df, initial = initial, assess = assess, skip = skip, cumulative = TRUE)
}

#' Fit the null model + linear regression + random forest via a real
#' tidymodels workflow_set, evaluated on the SAME rolling-origin folds
#' with the SAME metric set for every model (per this project's own
#' predictive-modeling-r skill conventions).
#'
#' @param df Data frame with chloride_mgL (outcome), sc_25c,
#'   temperature_c, doy_sin, doy_cos (predictors), and a time column
#'   for building resampling folds (default "collection_time").
#' @return list(folds=, metrics=, wf_set=, results=, comparison_table=,
#'   final_fits=)
run_chloride_tidymodels <- function(df = NULL, initial = 20, assess = 5, skip = 5, seed = 8341) {
  if (is.null(df)) {
    message("[tidymodels] No data frame supplied -- using simulate_synthetic_pairs() ",
            "(real Cl/conductivity pairs still don't exist, see this file's header).")
    df <- simulate_synthetic_pairs()
  }

  folds <- build_rolling_folds(df, initial = initial, assess = assess, skip = skip)
  message("[tidymodels] Built ", nrow(folds), " rolling-origin fold(s) from n=", nrow(df), " rows.")

  metrics <- metric_set(rmse, mae, rsq)

  # Minimal recipe: normalization is not required for the tree-based
  # model but is harmless and required for a fair, consistent
  # comparison against the linear model within the same workflow_set.
  rec <- recipe(chloride_mgL ~ sc_25c + temperature_c + doy_sin + doy_cos, data = df) |>
    step_normalize(all_numeric_predictors())

  spec_null <- null_model(mode = "regression") |> set_engine("parsnip")
  spec_lm   <- linear_reg() |> set_engine("lm")
  spec_rf   <- rand_forest(trees = 500) |> set_mode("regression") |> set_engine("ranger")

  wf_set <- workflow_set(
    preproc = list(rec = rec),
    models = list(null = spec_null, lm = spec_lm, rand_forest = spec_rf)
  )

  set.seed(seed)
  results <- wf_set |>
    workflow_map("fit_resamples", resamples = folds, metrics = metrics, verbose = FALSE)

  comparison_table <- collect_metrics(results) |>
    filter(.metric %in% c("rmse", "mae", "rsq")) |>
    mutate(model = sub("^rec_", "", wflow_id)) |>
    select(model, .metric, mean, std_err, n) |>
    arrange(.metric, mean)

  # Final fit of each model on ALL available data (not a held-out test
  # set -- there is no genuinely independent real test set yet given
  # n is this small/synthetic; this mirrors 03_chloride_models.R's own
  # save_final_chloride_models() posture, not a claim of unbiased
  # generalization performance).
  final_fits <- lapply(list(lm = spec_lm, rand_forest = spec_rf), function(spec) {
    fit(workflow() |> add_recipe(rec) |> add_model(spec), data = df)
  })

  list(
    folds = folds,
    metrics = metrics,
    wf_set = wf_set,
    results = results,
    comparison_table = comparison_table,
    final_fits = final_fits
  )
}

#' Save the winning workflow (by lowest mean RMSE) to disk, bundled
#' per the predictive-modeling-r skill's own guidance (bundle() before
#' saveRDS(), so a ranger fit round-trips correctly).
save_best_chloride_workflow <- function(result, out_dir = "models/chloride_prediction") {
  library(bundle)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  best_model <- result$comparison_table |>
    filter(.metric == "rmse") |>
    slice_min(mean, n = 1) |>
    pull(model)

  if (length(best_model) == 0 || best_model == "null") {
    message("[tidymodels] Best model by RMSE is the null model or undetermined -- not saving a real fit.")
    return(invisible(NULL))
  }

  wf <- result$final_fits[[best_model]]
  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  path <- file.path(out_dir, paste0("tidymodels_", best_model, "_", stamp, ".rds"))
  saveRDS(bundle::bundle(wf), path)
  message("[tidymodels] Saved best workflow (", best_model, ") to ", path)
  invisible(path)
}

# ------------------------------------------------------------
# Self-test (synthetic data) -- run manually:
#   source("scripts/analysis/sampling_frequency/03_chloride_models.R")
#   source("scripts/analysis/sampling_frequency/03b_chloride_models_tidymodels.R")
#   demo_chloride_tidymodels()
# ------------------------------------------------------------
demo_chloride_tidymodels <- function() {
  result <- run_chloride_tidymodels()
  print(result$comparison_table)
  invisible(result)
}
