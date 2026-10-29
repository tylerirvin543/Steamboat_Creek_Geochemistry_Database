# Cumulative departure from mean annual precipitation, Reno Airport
# (Collar 1990's method). Water years (Oct-Sep). Reads Weather_Observations.
# Descriptive only: no hypothesis test. Reno Airport is ~15 km north of the
# Steamboat field and ~100 m lower; Collar also used Sky Tavern.

library(DBI); library(dplyr); library(ggplot2)

build_precip_cumulative_departure <- function(con,
    station_id = "USW00023185",
    focus_start_wy = 2018, max_missing_frac = 0.10,
    out_png = "output/figures/manuscript/precip_cumulative_departure.png",
    out_csv = "data/derived/historical_comparison/precip_water_year_departure.csv") {

  d <- dbGetQuery(con, "select date, value from Weather_Observations
                        where station_id = ? and parameter = 'PRCP'", params = list(station_id)) |>
    mutate(date = as.Date(date), wy = as.integer(format(date, "%Y")) + (as.integer(format(date, "%m")) >= 10))

  wy <- d |>
    group_by(wy) |>
    summarise(n_days = n(), total_mm = sum(value), .groups = "drop") |>
    mutate(expected = ifelse(wy == max(wy), NA, ifelse(wy %% 4 == 0 & TRUE, 366, 365)),
           missing_frac = ifelse(is.na(expected), NA, 1 - n_days / expected),
           complete = !is.na(missing_frac) & missing_frac <= max_missing_frac)

  # Only complete water years enter the mean and the cumulative sum
  ok <- wy |> filter(complete)
  mu <- mean(ok$total_mm)
  ok <- ok |> mutate(departure_mm = total_mm - mu, cum_departure_mm = cumsum(departure_mm))
  out <- wy |> left_join(select(ok, wy, departure_mm, cum_departure_mm), by = "wy") |>
    mutate(long_term_mean_mm = mu)
  dir.create(dirname(out_csv), recursive = TRUE, showWarnings = FALSE)
  write.csv(out, out_csv, row.names = FALSE)

  p <- ggplot(filter(ok, wy >= 1938), aes(wy, cum_departure_mm)) +
    annotate("rect", xmin = 2021.5, xmax = 2025.5, ymin = -Inf, ymax = Inf, alpha = 0.12) +
    geom_hline(yintercept = 0, linewidth = 0.3) +
    geom_line() + geom_point(size = 1) +
    labs(x = "Water year (Oct-Sep)", y = "Cumulative departure from mean (mm)",
         title = "Reno Airport cumulative precipitation departure, 1938-2026",
         caption = sprintf("Mean %.0f mm/yr over %d complete water years (<=%d%% missing days). Shaded: 2022 onset to June 2025 eruption.\nReno Airport is about 15 km north of the field; descriptive only.",
                           mu, nrow(ok), round(100 * max_missing_frac))) +
    theme_minimal(base_size = 11) + theme(plot.caption = element_text(hjust = 0))
  dir.create(dirname(out_png), recursive = TRUE, showWarnings = FALSE)
  ggsave(out_png, p, width = 8, height = 4.8, dpi = 200)
  invisible(list(table = out, plot = p, mean_mm = mu))
}
