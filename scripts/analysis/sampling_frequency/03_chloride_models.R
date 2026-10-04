# ------------------------------------------------------------
# 03_chloride_models.R
#
# Purpose:
# Fit and compare chloride-prediction models (linear regression, GAM,
# Random Forest) using specific conductance, temperature, and seasonal
# terms, evaluated with BLOCKED (time-aware) cross-validation — never
# naive random k-fold on an autocorrelated series.
#
# Originally implemented with base R + mgcv + ranger (all installed)
# rather than the tidymodels metapackage, because tidymodels was not
# installed in this environment. tidymodels IS now installed
# (2026-09-26) -- prefer 03b_chloride_models_tidymodels.R for any new
# work; this file is kept for its data-generating functions
# (get_chloride_conductance_pairs(), simulate_synthetic_pairs(),
# add_seasonal_terms()), which 03b sources and reuses unchanged, and
# for the original hand-rolled lm/GAM/Random-Forest comparison, still
# valid as a lighter-weight alternative with no tidymodels dependency.
#
# simulate_synthetic_pairs()'s `lag_days` parameter (2026-09-26):
# the original synthetic data-generating process had chloride_mgL
# depend on the SAME-timestep sc_25c/temperature_c, with no lag at
# all -- discovered this made a lagged-conductivity feature
# meaningless to test (nothing to find). `lag_days` (default 6, i.e.
# 2 sampling steps at the 3-day spacing) now builds a real,
# physically-motivated transport lag into the synthetic chloride
# response, so a lagged-predictor recipe has genuine signal to
# recover. Confirmed this matters: on lag-free data, a plain linear
# model with same-timestep sc_25c/temperature_c (no seasonal terms)
# was the best model found (RMSE ~0.91); once lag_days=6 is built
# in, the SAME unlagged model degrades (RMSE ~1.24) and a correctly-
# lagged linear model becomes the clear winner (RMSE ~1.00) -- a real
# ~24% improvement recovered purely by matching the model's features
# to the (synthetic) truth, not by switching model family. Pass
# `lag_days = 0` to reproduce the original no-lag behavior if needed.
#
# Also discovered while revisiting feature engineering: the doy_sin/
# doy_cos seasonal terms were NEVER part of the true chloride
# relationship (only sc_25c/temperature_c are, and they already carry
# the seasonal signal via their own sinusoidal construction) --
# including them as extra predictors was collinear noise that hurt
# the linear model specifically (RMSE 1.26 -> 0.91 after removing
# them on the original lag-free data). Worth remembering before
# assuming more features/complexity helps: here, removing two
# redundant ones was the single biggest improvement found.
#
# get_chloride_conductance_pairs()'s `include_historical` (2026-09-29):
# real chemistry at a conductivity-logger location still returns 0
# logger-based rows (Cl samples predate the logger deployment -- see
# notebooks/09_sampling_campaign_design.qmd Section 1.1). A real,
# much larger historical dataset exists at NDEP stations that are the
# same real-world point (or a close, documented neighbor) as a
# logger site, via `Location_Aliases` -- e.g. SB5 for SBRR, 142 real
# Cl+conductivity pairs. `get_historical_ndep_chloride_conductance_pairs()`
# pulls these; `get_chloride_conductance_pairs()` now appends them by
# default, tagged `pairing_type = "historical_ndep"` vs `"logger"` so
# callers never silently blend two different instruments/eras as
# equivalent. See notebooks/09_sampling_campaign_design.qmd Section 1.4.
#
# Model artifacts are saved to models/chloride_prediction/*.rds and
# logged in models/MODEL_REGISTRY.csv.
# ------------------------------------------------------------

library(DBI)
library(dplyr)
library(mgcv)
library(ranger)

source("scripts/ingest/helpers/parse_datetime.R")

#' Real historical (non-logger) Cl-EC pairs at NDEP stations that are,
#' per `Location_Aliases`, the same real-world point (or a close,
#' documented neighbor) as a conductivity-logger location -- e.g. SB5
#' for SBRR. NDEP stores chloride and specific conductance together as
#' plain `Lab_Analyses` rows (analytes `'Cl'` and `'conductivity'`), a
#' different table/pathway than the FIELD-source `Field_Measurements`
#' pairing used elsewhere in this project. Kept deliberately distinct
#' from the logger-based pairs (different instrumentation/era spanning
#' decades of NDEP grab samples, not silently blended as equivalent) --
#' see `get_chloride_conductance_pairs()`'s `pairing_type` column, and
#' `notebooks/09_sampling_campaign_design.qmd` Section 1.4 for the full
#' write-up (currently: 142 real SB5 pairs for SBRR, mean ratio ~0.051,
#' close to SBRR's own single 2026 point of 0.071).
get_historical_ndep_chloride_conductance_pairs <- function(con) {
  logger_locations <- dbGetQuery(con, "SELECT DISTINCT location_id FROM Conductivity_Loggers")
  if (nrow(logger_locations) == 0) return(data.frame())

  alias_locations <- dbGetQuery(con, sprintf(
    "SELECT location_id AS canonical_location_id, alias FROM Location_Aliases WHERE location_id IN (%s)",
    paste(logger_locations$location_id, collapse = ",")
  ))
  if (nrow(alias_locations) == 0) {
    message("No Location_Aliases entries for any conductivity-logger location -- no historical NDEP pairs to pull.")
    return(data.frame())
  }

  alias_codes <- paste(sprintf("'%s'", alias_locations$alias), collapse = ",")
  result <- dbGetQuery(con, sprintf("
    SELECT cl_a.sample_id, l.external_station_code, l.location_id,
           s.collection_time, cl_a.value AS chloride_mgL, ec_a.value AS sc_25c
    FROM Lab_Analyses cl_a
    JOIN Lab_Analyses ec_a ON cl_a.sample_id = ec_a.sample_id AND ec_a.analyte = 'conductivity'
    JOIN Samples s ON cl_a.sample_id = s.sample_id
    JOIN Locations l ON s.location_id = l.location_id
    WHERE cl_a.analyte = 'Cl' AND cl_a.value > 0 AND l.external_station_code IN (%s)
  ", alias_codes)) |>
    mutate(collection_time = parse_datetime_safe(collection_time)) |>
    left_join(alias_locations, by = c("external_station_code" = "alias"))

  message("Pulled ", nrow(result), " real historical NDEP Cl+EC pair(s) from station(s): ",
          paste(unique(result$external_station_code), collapse = ", "))
  result
}

#' Pull paired chloride + specific-conductance observations
#'
#' Joins Lab_Analyses (analyte = 'Cl') to the nearest-in-time
#' Conductivity_Observations row for a logger at the same location,
#' within `tolerance_min` minutes ("logger" pairs). Real chemistry at a
#' conductivity-logger location still returns 0 logger-based rows (see
#' this file's own header) -- but when `include_historical = TRUE`
#' (default), real historical NDEP Cl+EC pairs at aliased stations
#' (e.g. SB5 for SBRR, via `get_historical_ndep_chloride_conductance_pairs()`)
#' are appended too, each tagged via `pairing_type` ("logger" vs.
#' "historical_ndep") so callers never silently blend the two eras/
#' instruments as equivalent.
get_chloride_conductance_pairs <- function(con, tolerance_min = 60, include_historical = TRUE) {

  cl <- dbGetQuery(con, "
    SELECT la.sample_id, s.location_id, s.collection_time, la.value AS chloride_mgL
    FROM Lab_Analyses la
    JOIN Samples s ON la.sample_id = s.sample_id
    WHERE la.analyte = 'Cl'
  ") |>
    mutate(collection_time = parse_datetime_safe(collection_time))

  loggers <- dbGetQuery(con, "SELECT logger_id, location_id FROM Conductivity_Loggers")

  cl <- cl |> inner_join(loggers, by = "location_id")

  logger_result <- data.frame()
  if (nrow(cl) == 0) {
    message("No chloride samples yet at a conductivity-logger location.")
  } else {
    obs <- dbGetQuery(con, "
      SELECT logger_id, timestamp, ec_raw, temperature_c, sc_25c, qc_flag
      FROM Conductivity_Observations
      WHERE qc_flag IS NULL OR qc_flag NOT IN ('spike', 'field_visit_disturbance')
    ") |>
      mutate(timestamp = as.POSIXct(timestamp, tz = "UTC"))

    out <- vector("list", nrow(cl))
    for (i in seq_len(nrow(cl))) {
      cand <- obs |> filter(logger_id == cl$logger_id[i])
      if (nrow(cand) == 0) next
      diffs <- abs(as.numeric(difftime(cand$timestamp, cl$collection_time[i], units = "mins")))
      j <- which.min(diffs)
      if (diffs[j] <= tolerance_min) {
        out[[i]] <- cbind(cl[i, c("sample_id", "chloride_mgL", "collection_time")], cand[j, ])
      }
    }

    logger_result <- bind_rows(out)
    if (nrow(logger_result) > 0) logger_result$pairing_type <- "logger"
    message("Matched ", nrow(logger_result), " chloride sample(s) to a conductivity observation ",
            "within ", tolerance_min, " minutes.")
  }

  if (!include_historical) return(logger_result)

  hist_result <- get_historical_ndep_chloride_conductance_pairs(con)
  if (nrow(hist_result) > 0) hist_result$pairing_type <- "historical_ndep"

  combined <- bind_rows(logger_result, hist_result)
  message("Total: ", nrow(logger_result), " logger-based + ", nrow(hist_result),
          " historical NDEP pair(s) = ", nrow(combined), " row(s).")
  combined
}

#' Compare a historical (NDEP-derived) Cl-EC relationship -- used as an
#' informed prior -- against the real logger-era relationship, once
#' real Tier 1 SBRR/SBGG pairs exist
#' (`get_chloride_conductance_pairs()`'s `pairing_type == "logger"`
#' subset). Until then, this reports the historical prior alone and
#' states plainly that no comparison is possible yet -- it never
#' fabricates a comparison from too few (or zero) real logger pairs.
#' See `notebooks/09_sampling_campaign_design.qmd` Section 1.6.
#' @param min_logger_n Minimum real logger pairs required before a
#'   formal slope-comparison (interaction) test is attempted (default
#'   10 -- fewer points make an interaction test unreliable).
#' @param historical_era Restrict the historical prior to samples at
#'   or after this year (default 2000). Session 2026-09-29's real
#'   finding: the SBRR-group historical Cl-EC slope roughly doubled
#'   between 1987-1999 (0.039) and 2000-2025 (0.073) -- a real,
#'   significant secular shift (interaction p < 1e-8), not sampling
#'   noise -- so the post-2000 subset is the more relevant prior for
#'   comparing against a 2026-era logger relationship. Pass
#'   `historical_era = NULL` to use the full historical record instead.
compare_historical_vs_logger_fit <- function(con, min_logger_n = 10, historical_era = 2000) {
  pairs <- get_chloride_conductance_pairs(con)

  hist_df <- pairs |> filter(pairing_type == "historical_ndep")
  if (!is.null(historical_era)) {
    hist_df <- hist_df |> filter(as.numeric(format(collection_time, "%Y")) >= historical_era)
  }
  logger_df <- pairs |> filter(pairing_type == "logger")

  if (nrow(hist_df) < 5) {
    message("Not enough historical pairs to fit a prior relationship (n=", nrow(hist_df), ").")
    return(invisible(NULL))
  }

  m_hist <- lm(chloride_mgL ~ sc_25c, data = hist_df)
  hist_summary <- list(n = nrow(hist_df), slope = unname(coef(m_hist)[2]),
                        intercept = unname(coef(m_hist)[1]), r_squared = summary(m_hist)$r.squared)
  message(sprintf("Historical prior (n=%d%s): slope=%.4f, intercept=%.2f, R2=%.3f",
                   hist_summary$n, if (is.null(historical_era)) "" else paste0(", >=", historical_era),
                   hist_summary$slope, hist_summary$intercept, hist_summary$r_squared))

  if (nrow(logger_df) < min_logger_n) {
    message(sprintf(
      "Only %d real logger-based Cl-EC pair(s) exist (need >= %d) -- reporting the historical prior only, no comparison yet.",
      nrow(logger_df), min_logger_n
    ))
    return(list(historical = hist_summary, logger = NULL, comparison = NULL))
  }

  m_logger <- lm(chloride_mgL ~ sc_25c, data = logger_df)
  logger_summary <- list(n = nrow(logger_df), slope = unname(coef(m_logger)[2]),
                          intercept = unname(coef(m_logger)[1]), r_squared = summary(m_logger)$r.squared)

  combined <- bind_rows(
    hist_df |> mutate(group = "historical") |> select(chloride_mgL, sc_25c, group),
    logger_df |> mutate(group = "logger") |> select(chloride_mgL, sc_25c, group)
  )
  m_interaction <- lm(chloride_mgL ~ sc_25c * group, data = combined)
  interaction_p <- anova(m_interaction)["sc_25c:group", "Pr(>F)"]
  consistent <- interaction_p >= 0.05

  message(sprintf(
    "Logger-era fit (n=%d): slope=%.4f, intercept=%.2f, R2=%.3f -- interaction p=%.3g (%s the historical prior)",
    logger_summary$n, logger_summary$slope, logger_summary$intercept, logger_summary$r_squared,
    interaction_p, if (consistent) "CONSISTENT with" else "SIGNIFICANTLY DIFFERENT from"
  ))

  list(historical = hist_summary, logger = logger_summary,
       interaction_p = interaction_p, consistent = consistent)
}

#' Self-test `compare_historical_vs_logger_fit()` end-to-end using a
#' synthetic stand-in for real logger pairs (since real Tier 1 data
#' doesn't exist yet) -- demonstrates the mechanism and its two
#' possible outcomes, not a real result. Temporarily monkeypatches
#' `get_chloride_conductance_pairs()` for the duration of the call so
#' no synthetic rows are ever written to the real database.
#' @param slope_multiplier Synthetic logger slope, as a multiple of the
#'   real historical prior's own slope. 1.0 simulates a logger-era
#'   relationship that matches the historical prior (expect
#'   `consistent = TRUE`); a value far from 1.0 (e.g. 2.0) simulates a
#'   real drift (expect `consistent = FALSE`).
demo_compare_historical_vs_logger_fit <- function(con, slope_multiplier = 1.0, n_synthetic = 25, seed = 9142) {
  set.seed(seed)
  real_pairs <- get_chloride_conductance_pairs(con)
  hist_prior <- real_pairs |> filter(pairing_type == "historical_ndep",
                                      as.numeric(format(collection_time, "%Y")) >= 2000)
  if (nrow(hist_prior) < 5) {
    message("No real historical prior available -- cannot run this self-test meaningfully.")
    return(invisible(NULL))
  }
  m_prior <- lm(chloride_mgL ~ sc_25c, data = hist_prior)

  sc_synth <- runif(n_synthetic, min(hist_prior$sc_25c), max(hist_prior$sc_25c))
  cl_synth <- coef(m_prior)[1] + slope_multiplier * coef(m_prior)[2] * sc_synth + rnorm(n_synthetic, 0, 2)
  synthetic_logger <- data.frame(sample_id = -seq_len(n_synthetic), chloride_mgL = pmax(cl_synth, 0.1),
                                  sc_25c = sc_synth, pairing_type = "logger",
                                  collection_time = as.POSIXct("2026-08-01", tz = "UTC"))

  # Monkeypatch just for this call, restored via on.exit() even on error
  real_fn <- get_chloride_conductance_pairs
  get_chloride_conductance_pairs <<- function(con, ...) bind_rows(real_pairs, synthetic_logger)
  on.exit(get_chloride_conductance_pairs <<- real_fn, add = TRUE)

  message(sprintf("[SELF-TEST, synthetic logger data, slope_multiplier=%.2f] ", slope_multiplier))
  compare_historical_vs_logger_fit(con, min_logger_n = 10)
}

#' Simulate a synthetic paired dataset for self-testing the pipeline
#' before real chloride/conductivity pairs exist.
#' @param lag_days Real hydrologic transport lag built into the
#'   synthetic chloride response, in days, rounded to the nearest
#'   sampling step (3-day spacing) -- 0 reproduces the original,
#'   no-lag data-generating process. 2026-09-26: added because
#'   testing a lagged-conductivity FEATURE is meaningless against
#'   data with no lag structure at all (confirmed the original DGP
#'   had none) -- a real transport lag between a logger reading and
#'   the geothermal source's Cl response is physically plausible,
#'   so this gives that feature genuine signal to detect, without
#'   pretending this is anything more than a synthetic self-test
#'   until real paired Cl/conductivity data exists.
#' Real, single-point Cl:EC ratio observed at SBRR (sample 819,
#' 2026-05-01: Cl = 17.1 mg/L at lab specific conductance = 241 uS/cm;
#' see `notebooks/09_sampling_campaign_design.qmd` Section 1.1). Used
#' below only as a rough seed for the synthetic slope's magnitude --
#' one real point, not a fitted regression -- so the self-test's
#' synthetic chloride range stays in a physically plausible ballpark
#' instead of an arbitrary made-up slope. A second real point at SBBV
#' (Section 1.2 of the same notebook) gives a ratio roughly double
#' this (0.144), confirming the ratio is site-specific and should not
#' be read as a universal calibration constant.
CL_EC_RATIO_SEED <- 0.071

simulate_synthetic_pairs <- function(n = 60, seed = 4218, lag_days = 6) {
  set.seed(seed)
  t <- seq(as.POSIXct("2026-05-01", tz = "UTC"), by = "3 days", length.out = n)
  doy <- as.numeric(format(t, "%j"))
  sc <- 300 + 40 * sin(2 * pi * doy / 365) + rnorm(n, 0, 15)
  temp <- 15 + 8 * sin(2 * pi * (doy - 60) / 365) + rnorm(n, 0, 1.5)

  # Real chloride response depends on sc/temp from `lag_steps` samples
  # ago, not the same-timestep reading -- the first `lag_steps` rows
  # have no real antecedent within this series, so they reuse the
  # first real observation rather than fabricating an earlier one.
  lag_steps <- max(0, round(lag_days / 3))
  if (lag_steps > 0) {
    sc_lag <- c(rep(sc[1], lag_steps), sc[seq_len(n - lag_steps)])
    temp_lag <- c(rep(temp[1], lag_steps), temp[seq_len(n - lag_steps)])
  } else {
    sc_lag <- sc
    temp_lag <- temp
  }

  # Slope seeded from the real SBRR Cl:EC ratio (CL_EC_RATIO_SEED, see
  # above); intercept/noise kept modest so the resulting synthetic
  # chloride values land near the real observed SBRR/SBBV range
  # (roughly 15-25 mg/L) rather than an arbitrary earlier value.
  cl_true <- 1 + CL_EC_RATIO_SEED * sc_lag + 0.1 * temp_lag + rnorm(n, 0, 1.5)

  tibble::tibble(
    collection_time = t,
    sc_25c = sc,
    temperature_c = temp,
    doy_sin = sin(2 * pi * doy / 365),
    doy_cos = cos(2 * pi * doy / 365),
    chloride_mgL = pmax(cl_true, 0.1)
  )
}

#' Add seasonal harmonic terms used by all model families below
add_seasonal_terms <- function(df, time_col = "collection_time") {
  doy <- as.numeric(format(df[[time_col]], "%j"))
  df$doy_sin <- sin(2 * pi * doy / 365)
  df$doy_cos <- cos(2 * pi * doy / 365)
  df
}

#' Rolling-origin (blocked, time-aware) cross-validation
#'
#' Mirrors rsample::rolling_origin(): each fold trains on all data up
#' to a point in time and tests on the next `assess` observations,
#' never on data from the past relative to training.
rolling_origin_cv <- function(df, time_col = "collection_time",
                               initial = 20, assess = 5, skip = 4) {
  df <- df[order(df[[time_col]]), ]
  n <- nrow(df)
  folds <- list()
  start <- initial
  while (start + assess <= n) {
    folds[[length(folds) + 1]] <- list(
      train = seq_len(start),
      test = seq(start + 1, start + assess)
    )
    start <- start + skip
  }
  folds
}

#' Fit lm / GAM / Random Forest on one train fold, predict on test fold
fit_and_predict <- function(train_df, test_df, formula_vars = c("sc_25c", "temperature_c", "doy_sin", "doy_cos")) {

  form_lm  <- as.formula(paste("chloride_mgL ~", paste(formula_vars, collapse = " + ")))
  form_gam <- as.formula(paste(
    "chloride_mgL ~ s(sc_25c, k = 4) + s(temperature_c, k = 4) + doy_sin + doy_cos"
  ))

  preds <- list()

  m_lm <- lm(form_lm, data = train_df)
  preds$lm <- predict(m_lm, newdata = test_df)

  m_gam <- tryCatch(gam(form_gam, data = train_df), error = function(e) NULL)
  preds$gam <- if (!is.null(m_gam)) predict(m_gam, newdata = test_df) else rep(NA_real_, nrow(test_df))

  m_rf <- ranger(form_lm, data = train_df, num.trees = 300)
  preds$rf <- predict(m_rf, data = test_df)$predictions

  preds
}

#' Run blocked CV across all three model families, return per-fold errors
evaluate_chloride_models <- function(df, ...) {

  folds <- rolling_origin_cv(df, ...)

  if (length(folds) == 0) {
    stop(
      "Not enough paired samples for even one CV fold (n = ", nrow(df),
      "). Collect more paired Cl/SC samples, or lower `initial`/`assess`."
    )
  }

  results <- purrr_map_dfr(seq_along(folds), function(i) {
    train_df <- df[folds[[i]]$train, ]
    test_df  <- df[folds[[i]]$test, ]

    preds <- fit_and_predict(train_df, test_df)

    do.call(rbind, lapply(names(preds), function(model_name) {
      err <- test_df$chloride_mgL - preds[[model_name]]
      data.frame(
        fold = i,
        model = model_name,
        rmse = sqrt(mean(err^2, na.rm = TRUE)),
        mae = mean(abs(err), na.rm = TRUE),
        n_test = nrow(test_df)
      )
    }))
  })

  results
}

# Minimal dplyr-free rbind helper (avoid a hard purrr dependency here)
purrr_map_dfr <- function(x, f) do.call(rbind, lapply(x, f))

#' Fit final models on ALL available paired data and save artifacts
save_final_chloride_models <- function(df, out_dir = "models/chloride_prediction") {

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")

  form_lm  <- chloride_mgL ~ sc_25c + temperature_c + doy_sin + doy_cos
  form_gam <- chloride_mgL ~ s(sc_25c, k = 4) + s(temperature_c, k = 4) + doy_sin + doy_cos

  m_lm  <- lm(form_lm, data = df)
  m_gam <- gam(form_gam, data = df)
  m_rf  <- ranger(form_lm, data = df, num.trees = 500)

  saveRDS(m_lm,  file.path(out_dir, paste0("lm_",  stamp, ".rds")))
  saveRDS(m_gam, file.path(out_dir, paste0("gam_", stamp, ".rds")))
  saveRDS(m_rf,  file.path(out_dir, paste0("rf_",  stamp, ".rds")))

  registry_path <- "models/MODEL_REGISTRY.csv"
  entry <- data.frame(
    date = stamp,
    model_file = c(paste0("lm_", stamp, ".rds"), paste0("gam_", stamp, ".rds"), paste0("rf_", stamp, ".rds")),
    family = c("lm", "gam", "ranger_rf"),
    response = "chloride_mgL",
    predictors = "sc_25c + temperature_c + doy_sin + doy_cos",
    training_window = paste(range(df$collection_time), collapse = " to "),
    resampling = "rolling_origin (manual)",
    cv_metric = NA,
    notes = ifelse(nrow(df) <= 60 && "sample_id" %in% names(df) == FALSE, "synthetic self-test run", "")
  )
  write.table(entry, registry_path, sep = ",", append = TRUE, row.names = FALSE,
              col.names = !file.exists(registry_path) || file.size(registry_path) == 0)

  message("Saved lm/gam/rf models to ", out_dir, " and logged to ", registry_path)

  invisible(list(lm = m_lm, gam = m_gam, rf = m_rf))
}

# ------------------------------------------------------------
# Self-test (synthetic data) — run manually:
#   source("scripts/analysis/sampling_frequency/03_chloride_models.R")
#   demo_chloride_models()
# ------------------------------------------------------------
demo_chloride_models <- function() {
  df <- simulate_synthetic_pairs()
  cv <- evaluate_chloride_models(df, initial = 20, assess = 5, skip = 5)
  print(aggregate(cbind(rmse, mae) ~ model, data = cv, FUN = mean))
  save_final_chloride_models(df)
  invisible(cv)
}
