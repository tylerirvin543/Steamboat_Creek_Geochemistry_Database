# Reusable check of a discharge event: is it a storm or an artifact, and what do conductance and the
# spring/well temperature loggers do around it? Shows discharge at both gauges (log axis), daily
# precipitation, specific conductance at SBRR and SBGG, and logger temperatures (as change from each
# logger's value at the start of the window). When chloride samples and discharge exist for the logger
# period, run this on any flagged discharge peak before using the flux for that date.
# Use: discharge_event_check(con, "2026-08-08", "2026-08-22")

suppressPackageStartupMessages({library(dplyr); library(ggplot2); library(patchwork)})

discharge_event_check <- function(con, start, end, out_dir = "data/derived/discharge_event_check",
                                  fig_dir = "output/figures/manuscript",
                                  up_gauge = "USGS-10349300", down_gauge = "USGS-10349849") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  s <- as.POSIXct(start, tz = "UTC"); e <- as.POSIXct(end, tz = "UTC") + 86399
  q <- DBI::dbGetQuery(con, sprintf("SELECT station_id, datetime, value FROM USGS_Timeseries WHERE parameter_code = '60' AND datetime BETWEEN '%s' AND '%s 23:59:59'", start, end))
  q$t <- as.POSIXct(q$datetime, tz = "UTC")
  q$gauge <- ifelse(q$station_id == up_gauge, "10349300 (SBRR)", "10349849 (downstream)")
  pc <- DBI::dbGetQuery(con, sprintf("SELECT date, value FROM Weather_Observations WHERE parameter = 'PRCP' AND station_id = 'USW00023185' AND date BETWEEN '%s' AND '%s'", start, end))
  pc$t <- as.POSIXct(pc$date, tz = "UTC") + 12 * 3600
  sc <- DBI::dbGetQuery(con, "SELECT l.external_station_code AS site, o.timestamp, o.sc_25c, o.qc_flag FROM Conductivity_Observations o
    JOIN Conductivity_Loggers cl ON o.logger_id = cl.logger_id JOIN Locations l ON cl.location_id = l.location_id
    WHERE l.external_station_code IN ('SBRR','SBGG') AND o.sc_25c IS NOT NULL")
  sc$t <- as.POSIXct(sc$timestamp, tz = "UTC"); sc <- sc[sc$t >= s & sc$t <= e & is.na(sc$qc_flag), ]
  tl <- DBI::dbGetQuery(con, "SELECT l.logger_name || ' ' || lo.name AS label, o.timestamp, o.temperature
    FROM Temperature_Observations o JOIN Temperature_Loggers l ON l.logger_id = o.logger_id JOIN Locations lo ON lo.location_id = l.location_id
    WHERE o.temperature IS NOT NULL")
  tl$t <- as.POSIXct(as.numeric(tl$timestamp), origin = "1970-01-01", tz = "UTC"); tl <- tl[tl$t >= s & tl$t <= e, ]
  tl$h <- as.POSIXct(floor(as.numeric(tl$t) / 3600) * 3600, origin = "1970-01-01", tz = "UTC")
  th <- tl |> group_by(label, h) |> summarise(v = mean(temperature), .groups = "drop") |> group_by(label) |>
    mutate(dT = v - first(v)) |> ungroup()
  peak <- q |> filter(station_id == down_gauge) |> slice_max(value, n = 1, with_ties = FALSE)

  xl <- coord_cartesian(xlim = c(s, e)); th0 <- theme_minimal(base_size = 9) + theme(legend.position = "right", legend.key.size = grid::unit(0.3, "cm"))
  vl <- geom_vline(xintercept = peak$t, linetype = "dashed", color = "grey40")
  p1 <- ggplot(q, aes(t, value, color = gauge)) + geom_line(linewidth = 0.3) + scale_y_log10() + vl +
    labs(x = NULL, y = "Discharge (cfs, log)", color = NULL) + th0 + xl
  p2 <- ggplot(pc, aes(t, value)) + geom_col(width = 86400, fill = "#56B4E9") + vl + labs(x = NULL, y = "Reno precipitation\n(mm/day)") + th0 + xl
  p3 <- ggplot(sc, aes(t, sc_25c)) + geom_point(size = 0.2, color = "#0072B2") + facet_wrap(~site, ncol = 1, scales = "free_y") + vl +
    labs(x = NULL, y = "Specific conductance\n(uS/cm)") + th0 + xl
  p4 <- ggplot(th, aes(h, dT, color = label)) + geom_line(linewidth = 0.3) + vl +
    labs(x = NULL, y = "Temperature change from\nstart of window (C)", color = NULL) + th0 + xl
  fig <- p1 / p2 / p3 / p4 + plot_layout(heights = c(1.4, 0.8, 2, 2)) + plot_annotation(
    title = sprintf("Discharge event check, %s to %s", start, end),
    caption = "Dashed line: peak at the downstream gauge. Exploratory; used to decide whether a discharge peak is a storm before using the flux for that date.",
    theme = theme(plot.caption = element_text(hjust = 0, size = 8)))
  ggsave(file.path(fig_dir, sprintf("discharge_event_check_%s.png", start)), fig, width = 9, height = 11, dpi = 160)

  # numbers: conductance and temperature, 24 h before vs after the peak
  w <- 24 * 3600
  ch <- function(df, tcol, vcol, key) df |> group_by(across(all_of(key))) |>
    summarise(before = mean(.data[[vcol]][.data[[tcol]] >= peak$t - w & .data[[tcol]] < peak$t], na.rm = TRUE),
              after = mean(.data[[vcol]][.data[[tcol]] >= peak$t & .data[[tcol]] < peak$t + w], na.rm = TRUE), .groups = "drop") |>
    mutate(change = after - before)
  sc_ch <- ch(sc, "t", "sc_25c", "site") |> mutate(kind = "conductance")
  tl_ch <- ch(tl, "t", "temperature", "label") |> rename(site = label) |> mutate(kind = "temperature")
  res <- bind_rows(sc_ch, tl_ch)
  write.csv(res, file.path(out_dir, sprintf("event_%s_changes.csv", start)), row.names = FALSE)
  invisible(list(peak = peak, changes = res, plot = fig))
}
