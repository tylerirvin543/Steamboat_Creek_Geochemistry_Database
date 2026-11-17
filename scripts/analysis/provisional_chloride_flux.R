# PROVISIONAL chloride flux and thermal-water inflow for the logger period, estimated from conductance.
# Chloride is NOT measured in this period. It is predicted from specific conductance with the historical
# NDEP regression at Rhodes Road (181 pairs, SC about 70-750 uS/cm). Use only as an estimate; replace with
# the calibration from the Phase 1 samples. SBGG conductance (about 1000-1200) is far outside the fitted
# range, so downstream chloride is an extrapolation.

suppressPackageStartupMessages({library(dplyr); library(ggplot2); library(patchwork)})

provisional_chloride_flux <- function(con, start = "2026-07-15", end = "2026-10-10",
                                      c_thermal = 820, up_gauge = "USGS-10349300", down_gauge = "USGS-10349849",
                                      out_dir = "data/derived/provisional_chloride_flux", fig_dir = "output/figures/manuscript") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  suppressMessages(suppressWarnings({
    source("scripts/analysis/sampling_frequency/03_chloride_models.R", local = TRUE)
    source("scripts/analysis/sampling_frequency/06_monte_carlo_air_exclusion.R", local = TRUE)
  }))
  pr <- suppressMessages(get_chloride_conductance_pairs(con))
  m <- lm(chloride_mgL ~ sc_25c, data = pr)
  rng <- range(pr$sc_25c)

  ec <- get_sc_record(con); rt <- retrieval_times(ec)
  ec <- ec[is.na(ec$qc_flag), ]
  for (i in seq_len(nrow(rt))) ec <- ec[!(ec$site == rt$site[i] & ec$timestamp >= rt$t[i] - 3 * 86400 & ec$timestamp <= rt$t[i] + 3600), ]
  ec <- ec[!(ec$site == "SBGG" & ec$timestamp >= as.POSIXct("2026-09-29", tz = "UTC")), ]
  ec$hr <- as.POSIXct(floor(as.numeric(ec$timestamp) / 3600) * 3600, origin = "1970-01-01", tz = "UTC")
  sc <- ec |> group_by(site, hr) |> summarise(sc = mean(sc_25c), .groups = "drop")

  q <- DBI::dbGetQuery(con, "SELECT station_id, datetime, value FROM USGS_Timeseries WHERE parameter_code = '60' AND datetime >= '2026-07-01'")
  q$t <- as.POSIXct(q$datetime, tz = "UTC")
  q$hr <- as.POSIXct(floor(as.numeric(q$t) / 3600) * 3600, origin = "1970-01-01", tz = "UTC")
  qh <- q |> group_by(station_id, hr) |> summarise(Q = mean(value) * 0.0283168, .groups = "drop")  # m3/s

  up <- sc |> filter(site == "SBRR") |> inner_join(qh |> filter(station_id == up_gauge), by = "hr") |> transmute(hr, sc_up = sc, Q_up = Q)
  dn <- sc |> filter(site == "SBGG") |> inner_join(qh |> filter(station_id == down_gauge), by = "hr") |> transmute(hr, sc_dn = sc, Q_dn = Q)
  d <- inner_join(up, dn, by = "hr") |> filter(hr >= as.POSIXct(start, tz = "UTC"), hr <= as.POSIXct(end, tz = "UTC") + 86399)
  cf <- function(s) pmax(0, predict(m, data.frame(sc_25c = s)))
  ci <- function(s) predict(m, data.frame(sc_25c = s), interval = "confidence")
  d <- d |> mutate(cl_up = cf(sc_up), cl_dn = cf(sc_dn),
                   flux_up = Q_up * cl_up, flux_dn = Q_dn * cl_dn,           # g/s
                   Qtw_Ls = (flux_dn - flux_up) / c_thermal * 1000,
                   day = as.Date(hr))
  # Sensitivity: downstream chloride from a two-end-member conductance mixing line (SBRR water and thermal water
  # at 820 mg/L Cl and about 3600 uS/cm, the plant-outlet field conductance), not from the regression.
  sc_th <- 3600
  d <- d |> mutate(cl_dn_mix = cl_up + pmax(0, sc_dn - sc_up) / (sc_th - sc_up) * (c_thermal - cl_up),
                   Qtw_mix_Ls = (Q_dn * cl_dn_mix - Q_up * cl_up) / c_thermal * 1000)
  daily <- d |> group_by(day) |> summarise(sc_up = mean(sc_up), sc_dn = mean(sc_dn), Q_up_m3s = mean(Q_up), Q_dn_m3s = mean(Q_dn),
    cl_up = mean(cl_up), cl_dn = mean(cl_dn), flux_up_gs = mean(flux_up), flux_dn_gs = mean(flux_dn),
    Qtw_Ls = mean(Qtw_Ls), Qtw_mix_Ls = mean(Qtw_mix_Ls), cl_dn_mix = mean(cl_dn_mix), hours = n(), .groups = "drop")
  # Storm days: downstream discharge more than 3 times its running 7-day median. Storm runoff dilutes chloride, so
  # the conductance-based flux is not trusted on these days (see discharge_event_check.R).
  med7 <- stats::filter(daily$Q_dn_m3s, rep(1/7, 7), sides = 2); med7 <- sapply(seq_len(nrow(daily)), function(k) median(daily$Q_dn_m3s[max(1, k - 3):min(nrow(daily), k + 3)]))
  daily$storm_day <- daily$Q_dn_m3s > 3 * med7
  daily$storm_day <- daily$storm_day | c(FALSE, head(daily$storm_day, -1))
  write.csv(daily, file.path(out_dir, "provisional_chloride_flux_daily.csv"), row.names = FALSE)

  frac_out_dn <- mean(d$sc_dn > rng[2]); frac_out_up <- mean(d$sc_up > rng[2] | d$sc_up < rng[1])
  # slope/intercept uncertainty: recompute Qtw with the 95% confidence limits of the fit
  lo <- ci(d$sc_dn)[, "lwr"] ; hi <- ci(d$sc_dn)[, "upr"]
  lou <- ci(d$sc_up)[, "lwr"]; hiu <- ci(d$sc_up)[, "upr"]
  q_lo <- mean((d$Q_dn * pmax(0, lo) - d$Q_up * pmax(0, hiu)) / c_thermal * 1000)
  q_hi <- mean((d$Q_dn * pmax(0, hi) - d$Q_up * pmax(0, lou)) / c_thermal * 1000)
  summ <- data.frame(start = start, end = end, hours_used = nrow(d), days_used = nrow(daily),
    regression = sprintf("Cl = %.2f + %.4f SC (n=%d, R2=%.2f; SC range %d-%d)", coef(m)[1], coef(m)[2], nrow(pr), summary(m)$r.squared, round(rng[1]), round(rng[2])),
    mean_cl_up = mean(d$cl_up), mean_cl_dn = mean(d$cl_dn), mean_Q_up_m3s = mean(d$Q_up), mean_Q_dn_m3s = mean(d$Q_dn),
    mean_Qtw_Ls = mean(d$Qtw_Ls), storm_days = sum(daily$storm_day), mean_Qtw_Ls_no_storm_days = mean(daily$Qtw_Ls[!daily$storm_day]), mean_Qtw_mixing_no_storm_days = mean(daily$Qtw_mix_Ls[!daily$storm_day]), mean_cl_dn_mixing_line = mean(d$cl_dn_mix), mean_Qtw_mixing_line_Ls = mean(d$Qtw_mix_Ls), Qtw_Ls_fit_ci_low = q_lo, Qtw_Ls_fit_ci_high = q_hi,
    share_hours_SBGG_above_fit_range = frac_out_dn, share_hours_SBRR_outside_fit_range = frac_out_up,
    total_cl_up_t = sum(d$flux_up) * 3600 / 1e6, total_cl_dn_t = sum(d$flux_dn) * 3600 / 1e6)
  write.csv(summ, file.path(out_dir, "provisional_chloride_flux_summary.csv"), row.names = FALSE)

  g1 <- ggplot(daily, aes(day)) + geom_line(aes(y = cl_up, color = "SBRR (upstream)")) + geom_line(aes(y = cl_dn, color = "SBGG (downstream)")) +
    scale_color_manual(NULL, values = c("#0072B2", "#D55E00")) + labs(x = NULL, y = "Estimated chloride (mg/L)") + theme_minimal(base_size = 9) + theme(legend.position = "bottom")
  g2 <- ggplot(daily, aes(day)) + geom_line(aes(y = Qtw_Ls, color = "Regression (provisional)")) + geom_line(aes(y = Qtw_mix_Ls, color = "Mixing-line sensitivity")) + scale_color_manual(NULL, values = c("#009E73", "#CC79A7")) + geom_hline(yintercept = 0, color = "grey60") +
    labs(x = NULL, y = "Thermal inflow Q_TW (L/s)") + theme_minimal(base_size = 9) + theme(legend.position = "bottom")
  g3 <- ggplot(daily, aes(day)) + geom_line(aes(y = flux_up_gs, color = "SBRR")) + geom_line(aes(y = flux_dn_gs, color = "SBGG")) +
    scale_color_manual(NULL, values = c("#0072B2", "#D55E00")) + labs(x = NULL, y = "Chloride flux (g/s)") + theme_minimal(base_size = 9) + theme(legend.position = "bottom")
  fig <- g1 / g3 / g2 + plot_annotation(title = "PROVISIONAL chloride flux and thermal inflow, 2026-07-15 to 2026-10-10",
    caption = paste0("Estimate only: chloride is predicted from conductance with the historical Rhodes Road regression, not measured in this period.\n",
      sprintf("SBGG conductance is above the fitted range (%d uS/cm) in %.0f%% of hours, so downstream chloride is an extrapolation. Q_TW uses an 820 mg/L thermal end member.\n", round(rng[2]), 100 * frac_out_dn),
      "Discharge: USGS 10349300 (upstream) and 10349849 (downstream; not at SBGG). Open-air days and flagged readings removed."),
    theme = theme(plot.caption = element_text(hjust = 0, size = 7.5)))
  ggsave(file.path(fig_dir, "provisional_chloride_flux.png"), fig, width = 8, height = 8, dpi = 170)
  invisible(list(summary = summ, daily = daily))
}
