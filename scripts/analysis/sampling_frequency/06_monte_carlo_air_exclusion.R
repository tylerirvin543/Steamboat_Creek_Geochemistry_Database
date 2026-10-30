# ------------------------------------------------------------
# 06_monte_carlo_air_exclusion.R
#
# Re-runs the Monte Carlo sampling-interval test (04_monte_carlo_subsampling.R)
# on the real SBRR/SBGG specific-conductance record after removing the days
# each logger sat in open air before retrieval.
#
# Exclusions (all applied before the test):
#   1. Every reading with a QC flag (spike, field_visit_disturbance), as in the
#      earlier version of this figure.
#   2. The `pre_retrieval_days` before each retrieval/relaunch, both loggers.
#      Field notes say the loggers sat in air for at least several days before
#      each pull; EC alone does not show it, so this window is a stated choice.
#   3. SBGG from `sbgg_air_start` to the end of the record. Field knowledge:
#      SBGG began to be exposed to open air in late September to early October;
#      the logger temperature record shows the daily range rising from about
#      5 C to 7-8 C from 2026-09-29, which is used as the onset date.
#
# The reference series is the logger SC record itself (stand-in for the dense
# chloride series a fitted Cl-SC model will eventually provide), as before.
# ------------------------------------------------------------

source("scripts/analysis/sampling_frequency/04_monte_carlo_subsampling.R")
suppressPackageStartupMessages({library(DBI); library(dplyr); library(ggplot2)})

get_sc_record <- function(con) {
  d <- dbGetQuery(con, "
    SELECT l.external_station_code AS site, o.timestamp, o.sc_25c, o.qc_flag
    FROM Conductivity_Observations o
    JOIN Conductivity_Loggers cl ON o.logger_id = cl.logger_id
    JOIN Locations l ON cl.location_id = l.location_id
    WHERE l.external_station_code IN ('SBRR','SBGG') AND o.sc_25c IS NOT NULL")
  d$timestamp <- as.POSIXct(d$timestamp, tz = "UTC")
  d
}

# Retrieval/relaunch times = last flagged field_visit_disturbance reading of each visit cluster
retrieval_times <- function(d) {
  f <- d |> filter(qc_flag == "field_visit_disturbance") |> arrange(site, timestamp)
  f |> group_by(site) |>
    mutate(cluster = cumsum(c(TRUE, diff(as.numeric(timestamp)) > 86400))) |>
    group_by(site, cluster) |> summarise(t = min(timestamp), .groups = "drop")
}

apply_air_exclusion <- function(d, pre_retrieval_days = 3, sbgg_air_start = as.POSIXct("2026-09-29", tz = "UTC")) {
  d <- d |> filter(is.na(qc_flag))
  if (pre_retrieval_days > 0) {
    # use the physical retrieval times from the unfiltered record
    rt <- retrieval_times(get("..raw", envir = parent.frame()))
    for (i in seq_len(nrow(rt))) {
      d <- d |> filter(!(site == rt$site[i] & timestamp >= rt$t[i] - pre_retrieval_days * 86400 & timestamp <= rt$t[i] + 3600))
    }
  }
  if (!is.na(sbgg_air_start)) d <- d |> filter(!(site == "SBGG" & timestamp >= sbgg_air_start))
  d
}

run_mc_site <- function(d, site_code, freqs = c(1, 2, 3, 7, 14), n_draws = 200, seed = 7391) {
  df <- d |> filter(site == site_code) |> arrange(timestamp) |> transmute(time = timestamp, chloride_mgL = sc_25c)
  mc <- monte_carlo_sampling_frequency(df, frequencies_days = freqs, n_draws = n_draws, seed = seed)
  mc$site <- site_code; mc$mean_sc <- mean(df$chloride_mgL); mc$n_readings <- nrow(df)
  mc$pct <- 100 * mc$rmse / mc$mean_sc
  mc
}

summ <- function(mc, label) {
  mc |> group_by(site, frequency_days) |>
    summarise(scenario = label, n_readings = first(n_readings), pct_mean = mean(pct), pct_p05 = quantile(pct, .05), pct_p95 = quantile(pct, .95), .groups = "drop")
}

run_monte_carlo_air_exclusion <- function(con,
    out_curve = "output/figures/manuscript/sampling_frequency_error_curve.png",
    out_box = "output/figures/manuscript/sampling_frequency_spread_boxplot.png",
    out_csv = "data/derived/sampling_frequency/mc_air_exclusion_summary.csv") {
  raw <- get_sc_record(con)
  ..raw <- raw
  scen <- list(
    "Earlier version (QC-flagged readings only removed)" = list(pre = 0, sbgg = NA),
    "Final: 3 days before each retrieval, SBGG air from 29 Sep" = list(pre = 3, sbgg = as.POSIXct("2026-09-29", tz = "UTC")),
    "Sensitivity: 7 days before retrieval, SBGG air from 25 Sep" = list(pre = 7, sbgg = as.POSIXct("2026-09-25", tz = "UTC")),
    "Sensitivity: 3 days before retrieval, SBGG air from 2 Oct" = list(pre = 3, sbgg = as.POSIXct("2026-10-02", tz = "UTC")))
  res <- list(); mcs <- list()
  for (nm in names(scen)) {
    s <- scen[[nm]]
    d <- raw |> filter(is.na(qc_flag))
    if (s$pre > 0) { rt <- retrieval_times(raw); for (i in seq_len(nrow(rt))) d <- d |> filter(!(site == rt$site[i] & timestamp >= rt$t[i] - s$pre * 86400 & timestamp <= rt$t[i] + 3600)) }
    if (!is.na(s$sbgg)) d <- d |> filter(!(site == "SBGG" & timestamp >= s$sbgg))
    mc <- bind_rows(run_mc_site(d, "SBRR"), run_mc_site(d, "SBGG"))
    mcs[[nm]] <- mc; res[[nm]] <- summ(mc, nm)
  }
  tab <- bind_rows(res)
  dir.create(dirname(out_csv), recursive = TRUE, showWarnings = FALSE)
  write.csv(tab, out_csv, row.names = FALSE)

  final_nm <- names(scen)[2]
  fin <- mcs[[final_nm]]; fs <- res[[final_nm]]
  pal <- c(SBRR = "#0072B2", SBGG = "#D55E00")
  n_by <- fs |> group_by(site) |> summarise(n = first(n_readings))
  cap <- sprintf("Source: real SBRR/SBGG specific-conductance record. QC-flagged readings, the 3 days before each retrieval, and SBGG from 2026-09-29\n(open-air exposure) are excluded. Readings used: SBRR %s, SBGG %s. 200 random start days per interval.",
                 format(n_by$n[n_by$site == "SBRR"], big.mark = ","), format(n_by$n[n_by$site == "SBGG"], big.mark = ","))
  p1 <- ggplot(fs, aes(frequency_days, pct_mean, color = site)) +
    geom_line() + geom_point(size = 2) +
    scale_color_manual(NULL, values = pal) +
    labs(x = "Candidate sampling interval (days)", y = "Reconstruction RMSE (% of mean specific conductance)",
         title = "Error-vs-sampling-frequency curve, SBRR and SBGG (air-exposure days removed)", caption = cap) +
    theme_minimal(base_size = 12) + theme(plot.caption = element_text(hjust = 0, size = 8, color = "grey35"))
  ggsave(out_curve, p1, width = 8, height = 5, dpi = 200)
  fin$interval <- factor(fin$frequency_days)
  p2 <- ggplot(fin, aes(interval, pct, fill = site)) + geom_boxplot(outlier.size = 0.6) +
    scale_fill_manual(NULL, values = pal) +
    labs(x = "Candidate sampling interval (days)", y = "Reconstruction RMSE (% of mean specific conductance)",
         title = "Spread across 200 random start days, by interval and site (air-exposure days removed)", caption = cap) +
    theme_minimal(base_size = 12) + theme(plot.caption = element_text(hjust = 0, size = 8, color = "grey35"))
  ggsave(out_box, p2, width = 8, height = 5, dpi = 200)
  invisible(tab)
}
