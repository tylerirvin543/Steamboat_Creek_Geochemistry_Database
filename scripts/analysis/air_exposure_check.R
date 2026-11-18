# Look for periods when a conductivity logger may have been out of water, using its own temperature
# (the same temperature used to correct EC to SC25) against Reno Airport hourly air temperature
# (IEM ASOS, data/raw/airtemp/). Exploratory: no ground truth for exposure exists, so days are only
# flagged as candidates, never confirmed.
#   Water damps and delays the air temperature cycle: the ratio of the logger's daily temperature range to the
#   air range is well below 1. A logger sitting in air would approach 1 (less if sheltered in its housing).
#   Conductance in air can also jump (drying film, partial immersion), seen as an unusually large daily range.
suppressMessages({library(dplyr); library(lubridate); library(ggplot2); library(tidyr)})
air_exposure_check <- function(con, air_csv = "data/raw/airtemp/iem_asos_RNO_tmpf_2026-07-14_2026-10-14.csv",
                               out_dir = "data/derived/air_exposure_check", fig = "output/figures/manuscript/air_exposure_check.png") {
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  tz <- "America/Los_Angeles"
  co <- DBI::dbGetQuery(con, "select logger_id, timestamp, temperature_c, sc_25c, qc_flag from Conductivity_Observations")
  co$t <- with_tz(ymd_hms(co$timestamp, tz = "UTC"), tz)
  co$site <- ifelse(co$logger_id == 1, "SBGG", "SBRR")
  co <- co[is.na(co$qc_flag) | co$qc_flag != "field_visit_disturbance", ]
  air <- read.csv(air_csv); air$t <- with_tz(ymd_hm(air$valid, tz = "UTC"), tz)
  air$tC <- (as.numeric(air$tmpf) - 32) * 5 / 9; air <- air[is.finite(air$tC), ]
  airh <- air |> mutate(h = floor_date(t, "hour")) |> group_by(h) |> summarise(air = mean(tC), .groups = "drop")
  hr <- co |> mutate(h = floor_date(t, "hour")) |> group_by(site, h) |> summarise(wt = mean(temperature_c), n = n(), .groups = "drop") |> filter(n >= 10)
  tday <- hr |> inner_join(airh, by = "h") |> mutate(day = as.Date(h, tz = tz)) |> group_by(site, day) |> filter(n() >= 22) |>
    summarise(temp_ratio = (max(wt) - min(wt)) / (max(air) - min(air)), r_air = cor(wt, air), .groups = "drop")
  sday <- co |> mutate(day = as.Date(t, tz = tz)) |> group_by(site, day) |> filter(n() > 200) |>
    summarise(sc_range = max(sc_25c) - min(sc_25c), sc_med = median(sc_25c), .groups = "drop")
  d <- full_join(tday, sday, by = c("site", "day")) |> group_by(site) |>
    mutate(sc_range_rel = sc_range / sc_med, sc_z = (sc_range_rel - median(sc_range_rel, na.rm = TRUE)) / mad(sc_range_rel, na.rm = TRUE),
           cand_temp = temp_ratio > 0.55, cand_sc = sc_z > 6) |> ungroup()
  write.csv(d, file.path(out_dir, "daily_air_exposure_indicators.csv"), row.names = FALSE)
  pd <- d |> select(site, day, temp_ratio, sc_range_rel) |> pivot_longer(c(temp_ratio, sc_range_rel), names_to = "ind", values_to = "v") |>
    mutate(ind = recode(ind, temp_ratio = "Temperature range, logger / air", sc_range_rel = "SC25 daily range / median"))
cand <- d |> filter(cand_temp | cand_sc) |> select(site, day) |> tidyr::crossing(ind = unique(pd$ind))
  p <- ggplot(pd, aes(day, v)) + geom_line(color = "grey40", linewidth = 0.3) + geom_point(size = 0.8, color = "grey20") +
    geom_vline(data = data.frame(d = as.Date(c("2026-08-22", "2026-10-10"))), aes(xintercept = d), linetype = "dashed", color = "firebrick") +
    geom_vline(data = cand, aes(xintercept = day), color = "orange", alpha = 0.5) +
    facet_grid(ind ~ site, scales = "free_y", labeller = label_wrap_gen(18)) + labs(x = NULL, y = NULL) + theme_minimal(base_size = 9) + theme(strip.text.y = element_text(angle = 0))
  ggsave(fig, p, width = 7.2, height = 4.6, dpi = 200, bg = "white")
  invisible(d)
}
