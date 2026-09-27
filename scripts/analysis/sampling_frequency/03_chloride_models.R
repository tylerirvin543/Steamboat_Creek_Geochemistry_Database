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
# Model artifacts are saved to models/chloride_prediction/*.rds and
# logged in models/MODEL_REGISTRY.csv.
# ------------------------------------------------------------

library(DBI)
library(dplyr)
library(mgcv)
library(ranger)

source("scripts/ingest/helpers/parse_datetime.R")

#' Pull paired chloride + specific-conductance observations
#'
#' Joins Lab_Analyses (analyte = 'Cl') to the nearest-in-time
#' Conductivity_Observations row for a logger at the same location,
#' within `tolerance_min` minutes. Returns 0 rows (with a message)
#' until paired field chemistry exists for SBRR/SBGG.
get_chloride_conductance_pairs <- function(con, tolerance_min = 60) {

  cl <- dbGetQuery(con, "
    SELECT la.sample_id, s.location_id, s.collection_time, la.value AS chloride_mgL
    FROM Lab_Analyses la
    JOIN Samples s ON la.sample_id = s.sample_id
    WHERE la.analyte = 'Cl'
  ") |>
    mutate(collection_time = parse_datetime_safe(collection_time))

  loggers <- dbGetQuery(con, "SELECT logger_id, location_id FROM Conductivity_Loggers")

  cl <- cl |> inner_join(loggers, by = "location_id")

  if (nrow(cl) == 0) {
    message("No chloride samples yet at a conductivity-logger location — returning 0 rows.")
    return(cl)
  }

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

  result <- bind_rows(out)
  message("Matched ", nrow(result), " chloride sample(s) to a conductivity observation ",
          "within ", tolerance_min, " minutes.")
  result
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

  cl_true <- 5 + 0.03 * sc_lag + 0.1 * temp_lag + rnorm(n, 0, 1.2)

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
