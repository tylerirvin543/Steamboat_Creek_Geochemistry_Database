# Compare Lindsey et al. (2026) Fig. 3 logger traces (1-8 July 2025, digitized by eye)
# with this project's A009 (resort tank) and A005 (fumarole, SBF_0001) over an 8-day window.
library(DBI); library(dplyr); library(ggplot2); library(readr)

build_lindsey_logger_comparison <- function(con,
    start = "2026-07-16", out_png = "output/figures/manuscript/lindsey_vs_our_loggers.png") {
  tz <- "America/Los_Angeles"
  t0 <- as.POSIXct(start, tz = tz)
  ours <- dbGetQuery(con, "SELECT l.logger_name, o.timestamp, o.temperature
      FROM Temperature_Observations o JOIN Temperature_Loggers l ON o.logger_id = l.logger_id
      WHERE l.logger_name IN ('A009','A005')") |>
    mutate(t = as.POSIXct(as.numeric(timestamp), origin = "1970-01-01", tz = tz),
           day = as.numeric(difftime(t, t0, units = "days"))) |>
    filter(day >= 0, day <= 8) |>
    transmute(site = ifelse(logger_name == "A009", "Resort holding tank", "Fissure / fumarole"),
              source = ifelse(logger_name == "A009", "This project, A009 (16-24 Jul 2026)",
                              "This project, A005 (16-24 Jul 2026)"),
              day, temp_c = temperature)
  lind <- read_csv("data/raw/historical/lindsey2026_fig3_digitized.csv", show_col_types = FALSE) |>
    filter(logger != "well") |>
    transmute(site = ifelse(logger == "resort_tank", "Resort holding tank", "Fissure / fumarole"),
              source = ifelse(logger == "resort_tank", "Lindsey et al. 2026 (1-8 Jul 2025)",
                              "Lindsey et al. 2026, main fissure (daily mean)"),
              day, temp_c)
  d <- bind_rows(ours, lind)
  p <- ggplot(d, aes(day, temp_c, colour = source)) +
    geom_line(data = ~filter(.x, grepl("Lindsey", source)), linewidth = 1) +
    geom_line(data = ~filter(.x, !grepl("Lindsey", source)), linewidth = 0.3, alpha = 0.8) +
    facet_wrap(~site, ncol = 1, scales = "free_y") +
    labs(x = "Days from start of window", y = "Temperature (deg C)", colour = NULL,
         title = "Lindsey et al. (2026) logger traces vs. this project's loggers",
         caption = paste(strwrap(paste("Lindsey values digitized by eye from her Fig. 3 (about +/-1 C); the fissure line is the daily mean,",
                         "which oscillates about +/-2.5 C. Different years and windows; sensor positions may differ.\n",
                         "Her uncapped-well trace (89-90 C) has no counterpart in this project."), 95), collapse = "
")) +
    theme_minimal(base_size = 11) + theme(legend.position = "bottom", legend.direction = "vertical")
  ggsave(out_png, p, width = 8, height = 7, dpi = 200)
  s <- d |> group_by(site, source) |> summarise(median = median(temp_c), min = min(temp_c), max = max(temp_c), .groups = "drop")
  write_csv(s, "data/derived/lindsey_vs_our_loggers_summary.csv")
  list(plot = p, summary = s)
}
