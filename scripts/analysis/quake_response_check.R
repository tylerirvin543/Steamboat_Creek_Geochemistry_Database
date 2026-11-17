# Do earthquakes line up with changes at the temperature loggers or the conductivity loggers?
# For each earthquake inside a logger's record, compare the mean of the 48 h after with the 48 h before,
# and put that difference against the distribution of the same 48 h-versus-48 h differences at all other
# times for that logger (z score). A change has to exceed the logger's usual drift to stand out.
# Descriptive only: counts of exceedances and a table, no causal test.

suppressPackageStartupMessages({library(dplyr); library(ggplot2)})

quake_response_check <- function(con, window_h = 48, out_dir = "data/derived/quake_response",
                                 fig_dir = "output/figures/manuscript") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  t <- DBI::dbGetQuery(con, "
    SELECT 'temperature' AS kind, l.logger_name || ' ' || lo.name AS series, o.timestamp, o.temperature AS v
    FROM Temperature_Observations o JOIN Temperature_Loggers l ON l.logger_id = o.logger_id
    JOIN Locations lo ON lo.location_id = l.location_id WHERE o.temperature IS NOT NULL")
  t$time <- as.POSIXct(as.numeric(t$timestamp), origin = "1970-01-01", tz = "UTC")
  c_ <- DBI::dbGetQuery(con, "
    SELECT 'conductance' AS kind, l.external_station_code AS series, o.timestamp, o.sc_25c AS v
    FROM Conductivity_Observations o JOIN Conductivity_Loggers cl ON o.logger_id = cl.logger_id
    JOIN Locations l ON cl.location_id = l.location_id
    WHERE o.sc_25c IS NOT NULL AND o.qc_flag IS NULL AND l.external_station_code IN ('SBRR','SBGG')")
  c_$time <- as.POSIXct(c_$timestamp, tz = "UTC")
  d <- bind_rows(t[c("kind", "series", "time", "v")], c_[c("kind", "series", "time", "v")]) |>
    mutate(hr = floor(as.numeric(time) / 3600)) |> group_by(kind, series, hr) |>
    summarise(v = mean(v), .groups = "drop")

  q <- DBI::dbGetQuery(con, "SELECT event_id, event_time, magnitude, dist_to_steamboat_km, event_type FROM Earthquake_Events WHERE event_type = 'earthquake'")
  q$hr <- floor(as.numeric(as.POSIXct(q$event_time, format = "%Y-%m-%d %H:%M:%OS", tz = "UTC")) / 3600)
  q <- q[!is.na(q$hr), ]

  step_fun <- function(s, h) {
    mean(s$v[s$hr > h & s$hr <= h + window_h]) - mean(s$v[s$hr <= h & s$hr > h - window_h])
  }
  res <- list()
  for (key in split(d, list(d$kind, d$series), drop = TRUE)) {
    key <- key[order(key$hr), ]
    r <- range(key$hr); allh <- seq(r[1] + window_h, r[2] - window_h, by = 6)
    # only hours with data on both sides
    ok <- vapply(allh, function(h) sum(key$hr > h & key$hr <= h + window_h) >= window_h * 0.8 &&
                                   sum(key$hr <= h & key$hr > h - window_h) >= window_h * 0.8, logical(1))
    base <- vapply(allh[ok], function(h) step_fun(key, h), numeric(1))
    if (length(base) < 30) next
    qs <- q[q$hr > r[1] + window_h & q$hr < r[2] - window_h, ]
    for (i in seq_len(nrow(qs))) {
      h <- qs$hr[i]
      if (sum(key$hr > h & key$hr <= h + window_h) < window_h * 0.8 || sum(key$hr <= h & key$hr > h - window_h) < window_h * 0.8) next
      st <- step_fun(key, h)
      res[[length(res) + 1]] <- data.frame(kind = key$kind[1], series = key$series[1], event_id = qs$event_id[i],
        event_time = qs$event_time[i], magnitude = qs$magnitude[i], dist_km = qs$dist_to_steamboat_km[i],
        step = st, z = (st - mean(base)) / sd(base), n_baseline = length(base))
    }
  }
  res <- bind_rows(res)
  res$near <- cut(res$dist_km, c(-Inf, 15, 60, Inf), c("within 15 km", "15-60 km", "over 60 km"))
  write.csv(res, file.path(out_dir, "quake_response_steps.csv"), row.names = FALSE)
  summ <- res |> group_by(kind, near) |>
    summarise(n_tests = n(), n_events = n_distinct(event_id), n_abs_z_gt_2 = sum(abs(z) > 2), expected_by_chance = round(0.0455 * n(), 1), .groups = "drop")
  write.csv(summ, file.path(out_dir, "quake_response_summary.csv"), row.names = FALSE)
  g <- ggplot(res, aes(event_time |> as.POSIXct(format = "%Y-%m-%d %H:%M:%OS", tz = "UTC"), z, color = near, size = magnitude)) +
    geom_hline(yintercept = c(-2, 2), linetype = "dashed", color = "grey50") + geom_point(alpha = 0.6) +
    facet_wrap(~kind, ncol = 1) + scale_size_continuous(range = c(0.8, 4)) +
    scale_color_manual(values = c("within 15 km" = "#D55E00", "15-60 km" = "#E69F00", "over 60 km" = "grey60")) +
    labs(x = NULL, y = "Step in 48 h means after vs before (z score)", color = NULL,
         title = "Change at the loggers around each earthquake",
         caption = "One point per earthquake and logger. Dashed lines: |z| = 2; about 5% of points are expected beyond them by chance.") +
    theme_minimal(base_size = 9) + theme(plot.caption = element_text(hjust = 0))
  ggsave(file.path(fig_dir, "quake_response_z.png"), g, width = 8, height = 6, dpi = 170)
  invisible(list(steps = res, summary = summ))
}
