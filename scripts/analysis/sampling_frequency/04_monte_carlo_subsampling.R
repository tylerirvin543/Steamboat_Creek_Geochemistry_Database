# ------------------------------------------------------------
# 04_monte_carlo_subsampling.R
#
# Purpose:
# For a reference (dense/continuous) chloride series, repeatedly
# subsample at candidate chemistry-sampling frequencies (daily,
# 2-day, 3-day, weekly, biweekly, monthly), reconstruct the full
# series by linear interpolation between subsampled points, and
# compare to the reference to quantify:
#   - chloride concentration error (RMSE, MAE)
#   - mass-flux error (if a paired discharge series is supplied)
#   - uncertainty (spread across Monte Carlo draws, varying the
#     random phase/offset of the sampling schedule)
#
# The "reference" series is normally the output of a fitted
# chloride-prediction model (03_chloride_models.R) applied to the
# full-resolution conductivity record, once real paired chemistry
# exists. Until then, `demo_monte_carlo()` below runs the full
# machinery on a synthetic reference series so the code path is
# validated end-to-end ahead of real data.
# ------------------------------------------------------------

#' Trapezoidal mass flux: integral of conc (mg/L == g/m3) * discharge (m3/s) dt
#' Returns total mass in grams over the series.
trapz_mass_flux <- function(time, conc_mgL, discharge_m3s) {
  o <- order(time)
  time <- time[o]; conc_mgL <- conc_mgL[o]; discharge_m3s <- discharge_m3s[o]

  dt_s <- as.numeric(diff(time), units = "secs")
  mass_rate_g_s <- conc_mgL * discharge_m3s  # mg/L == g/m3, so conc*Q -> g/s directly

  # trapezoidal rule
  sum(dt_s * (head(mass_rate_g_s, -1) + tail(mass_rate_g_s, -1)) / 2, na.rm = TRUE)
}

#' Median sampling interval of a time vector, in minutes
median_interval_min <- function(time) {
  as.numeric(median(diff(sort(time))), units = "mins")
}

#' Monte Carlo subsampling experiment
#'
#' @param reference_df data.frame with columns `time` (POSIXct, regular
#'   grid), `chloride_mgL`, and optionally `discharge_m3s`.
#' @param frequencies_days candidate chemistry sampling intervals to test.
#' @param n_draws Monte Carlo repetitions per frequency (varies phase/offset).
monte_carlo_sampling_frequency <- function(reference_df,
                                            frequencies_days = c(1, 2, 3, 7, 14, 30),
                                            n_draws = 200,
                                            seed = 8834) {

  set.seed(seed)
  reference_df <- reference_df[order(reference_df$time), ]
  has_q <- "discharge_m3s" %in% names(reference_df)

  true_flux <- if (has_q) {
    trapz_mass_flux(reference_df$time, reference_df$chloride_mgL, reference_df$discharge_m3s)
  } else NA_real_

  base_interval_min <- median_interval_min(reference_df$time)

  results <- list()

  for (freq_days in frequencies_days) {

    step_n <- max(1, round(freq_days * 24 * 60 / base_interval_min))

    if (step_n >= nrow(reference_df)) {
      message("Frequency ", freq_days, " days exceeds record length — skipping.")
      next
    }

    for (draw in seq_len(n_draws)) {

      offset <- sample.int(step_n, 1)
      idx <- seq(offset, nrow(reference_df), by = step_n)
      if (length(idx) < 3) next

      sub <- reference_df[idx, ]

      interp_cl <- approx(sub$time, sub$chloride_mgL, xout = reference_df$time, rule = 2)$y
      err <- reference_df$chloride_mgL - interp_cl

      flux_pct_error <- NA_real_
      if (has_q) {
        sim_flux <- trapz_mass_flux(reference_df$time, interp_cl, reference_df$discharge_m3s)
        flux_pct_error <- 100 * (sim_flux - true_flux) / true_flux
      }

      results[[length(results) + 1]] <- data.frame(
        frequency_days = freq_days,
        draw = draw,
        n_samples = length(idx),
        rmse = sqrt(mean(err^2, na.rm = TRUE)),
        mae = mean(abs(err), na.rm = TRUE),
        flux_pct_error = flux_pct_error
      )
    }
  }

  do.call(rbind, results)
}

#' Summarize Monte Carlo draws into one row per candidate frequency
summarize_sampling_frequency <- function(mc_results) {
  agg <- function(x) c(mean = mean(x, na.rm = TRUE),
                       sd = sd(x, na.rm = TRUE),
                       p05 = quantile(x, 0.05, na.rm = TRUE),
                       p95 = quantile(x, 0.95, na.rm = TRUE))

  out <- do.call(rbind, lapply(split(mc_results, mc_results$frequency_days), function(d) {
    data.frame(
      frequency_days = d$frequency_days[1],
      n_draws = nrow(d),
      rmse_mean = mean(d$rmse, na.rm = TRUE),
      rmse_p95 = quantile(d$rmse, 0.95, na.rm = TRUE),
      mae_mean = mean(d$mae, na.rm = TRUE),
      flux_pct_error_mean = mean(abs(d$flux_pct_error), na.rm = TRUE),
      flux_pct_error_p95 = quantile(abs(d$flux_pct_error), 0.95, na.rm = TRUE)
    )
  }))

  out[order(out$frequency_days), ]
}

# ------------------------------------------------------------
# Self-test (synthetic data) — run manually:
#   source("scripts/analysis/sampling_frequency/04_monte_carlo_subsampling.R")
#   demo_monte_carlo()
# ------------------------------------------------------------
simulate_synthetic_reference <- function(days = 180, interval_min = 15, seed = 5521) {
  set.seed(seed)
  time <- seq(as.POSIXct("2026-04-01", tz = "UTC"), by = paste(interval_min, "min"), length.out = days * 24 * 60 / interval_min)
  doy <- as.numeric(format(time, "%j"))
  hour <- as.numeric(format(time, "%H")) + as.numeric(format(time, "%M")) / 60

  chloride_mgL <- 12 + 3 * sin(2 * pi * doy / 365) + 0.5 * sin(2 * pi * hour / 24) + rnorm(length(time), 0, 0.3)
  discharge_m3s <- pmax(0.05, 0.3 + 0.1 * sin(2 * pi * doy / 365) + rnorm(length(time), 0, 0.02))

  data.frame(time = time, chloride_mgL = chloride_mgL, discharge_m3s = discharge_m3s)
}

demo_monte_carlo <- function() {
  ref <- simulate_synthetic_reference()
  mc <- monte_carlo_sampling_frequency(ref, n_draws = 100)
  summary_tbl <- summarize_sampling_frequency(mc)
  print(summary_tbl)
  invisible(list(mc = mc, summary = summary_tbl))
}
