# Time-series figures for the thesis proposal (read-only on the database).
#  1. Temperature loggers with barometric pressure, precipitation and earthquakes on one date axis.
#  2. Conductivity record (SBRR, SBGG) with creek chloride samples as a separate series.
#  3. Chloride and Cl/B against specific conductance (the calibration so far).
#  4. Fissure-area chloride and Cl/B through time (not part of the calibration).
# Pressure, precipitation and earthquakes are shown for context; the figures do not test cause.

suppressPackageStartupMessages({library(dplyr); library(ggplot2); library(patchwork); library(lubridate)})

source("scripts/analysis/conservative_tracer_ratios.R")
.TZ <- "America/Los_Angeles"
.ts_theme <- function() theme_minimal(base_size = 9) +
  theme(plot.caption = element_text(hjust = 0), legend.position = "right",
        legend.key.size = grid::unit(0.35, "cm"), plot.title.position = "plot")

.num_time <- function(x) as.POSIXct(as.numeric(x), origin = "1970-01-01", tz = "UTC")
.quake_ticks <- function(con, xr) {
  q <- DBI::dbGetQuery(con, "SELECT event_time, magnitude, dist_to_steamboat_km FROM Earthquake_Events WHERE event_type = 'earthquake' AND dist_to_steamboat_km <= 60")
  q$time <- as.POSIXct(q$event_time, format = "%Y-%m-%d %H:%M:%OS", tz = "UTC")
  q <- q[!is.na(q$time) & q$time >= xr[1] & q$time <= xr[2], ]
  q$near <- ifelse(q$dist_to_steamboat_km <= 15, "within 15 km", "15-60 km")
  geom_vline(data = q, aes(xintercept = time, linetype = near), color = "#D55E00", alpha = 0.5, linewidth = 0.3, inherit.aes = FALSE)
}


#' Figure 1: logger temperatures with pressure, precipitation and earthquakes.
build_temperature_context_figure <- function(con, out_dir = "output/figures/manuscript") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  t <- DBI::dbGetQuery(con, "
    SELECT l.logger_name, lo.name AS site, o.timestamp, o.temperature
    FROM Temperature_Observations o
    JOIN Temperature_Loggers l ON l.logger_id = o.logger_id
    JOIN Locations lo ON lo.location_id = l.location_id
    WHERE o.temperature IS NOT NULL")
  t$time <- .num_time(t$timestamp)
  t$hour <- as.POSIXct(floor(as.numeric(t$time) / 3600) * 3600, origin = "1970-01-01", tz = "UTC")
  t$label <- paste(t$logger_name, t$site)
th <- t |> group_by(label, hour) |> summarise(temperature = mean(temperature), .groups = "drop") |>
    arrange(label, hour) |> group_by(label) |> mutate(seg = cumsum(c(1, diff(as.numeric(hour)) > 6 * 3600))) |> ungroup()
  grp <- th |> group_by(label) |> summarise(m = mean(temperature)) |>
    mutate(panel = ifelse(m > 30, "Loggers averaging above 30 C (fumarole, spring and well sites)",
                          "Loggers averaging below 30 C (creek and cooler ground)"))
  th <- left_join(th, grp[c("label", "panel")], by = "label")
  xr <- c(min(th$hour), as.POSIXct("2026-11-14", tz = "UTC"))
  last_logger <- max(th$hour)

  p1 <- ggplot(th, aes(hour, temperature, color = label, group = interaction(label, seg))) +
    geom_line(linewidth = 0.25) + facet_wrap(~panel, ncol = 1, scales = "free_y") +
    geom_vline(xintercept = last_logger, linetype = "dashed", color = "grey40") + .quake_ticks(con, xr) + scale_linetype_manual(NULL, values = c("within 15 km" = "solid", "15-60 km" = "dotted")) +
    labs(x = NULL, y = "Temperature (C), hourly mean", color = NULL) + .ts_theme() +
    coord_cartesian(xlim = xr) + guides(color = guide_legend(ncol = 1, override.aes = list(linewidth = 1)))

  pr <- DBI::dbGetQuery(con, "SELECT date, value FROM Weather_Observations WHERE parameter = 'MSLP'")
  pr$time <- as.POSIXct(pr$date, tz = .TZ)
  pr$day <- as.Date(pr$time, tz = .TZ)
  pd <- pr |> group_by(day) |> summarise(p = mean(value))
  p2 <- ggplot(pd, aes(as.POSIXct(day, tz = "UTC"), p)) + geom_line(linewidth = 0.3, color = "#0072B2") +
    labs(x = NULL, y = "Sea-level pressure\n(hPa, daily mean)") + .ts_theme() + coord_cartesian(xlim = xr)

  pc <- DBI::dbGetQuery(con, "SELECT date, value FROM Weather_Observations WHERE parameter = 'PRCP' AND station_id = 'USW00023185' AND date >= '2025-09-01'")
  pc$day <- as.Date(pc$date)
  p3 <- ggplot(pc, aes(as.POSIXct(day, tz = "UTC"), value)) + geom_col(width = 86400, fill = "#56B4E9") +
    labs(x = NULL, y = "Precipitation\n(mm per day)") + .ts_theme() + coord_cartesian(xlim = xr)

  q <- DBI::dbGetQuery(con, "SELECT event_time, magnitude, dist_to_steamboat_km FROM Earthquake_Events WHERE event_type = 'earthquake' AND magnitude >= 1.5")
  q$time <- as.POSIXct(q$event_time, format = "%Y-%m-%d %H:%M:%OS", tz = "UTC")
  q <- q[!is.na(q$time) & q$time >= xr[1], ]
  q$cls <- cut(q$dist_to_steamboat_km, c(-Inf, 15, 60, Inf), c("within 15 km", "15-60 km", "over 60 km"))
  p4 <- ggplot(q, aes(time, dist_to_steamboat_km, size = magnitude, color = cls)) + geom_point(alpha = 0.7) +
    scale_y_log10() + scale_size_continuous(range = c(0.6, 4), breaks = c(2, 3)) +
    scale_color_manual(values = c("within 15 km" = "#D55E00", "15-60 km" = "#E69F00", "over 60 km" = "grey60")) +
    labs(x = NULL, y = "Distance to field\n(km, log scale)", color = NULL, size = "Magnitude") + .ts_theme() +
    coord_cartesian(xlim = xr)

  fig <- p1 / p2 / p3 / p4 + plot_layout(heights = c(4, 1.2, 1.2, 1.6)) +
    plot_annotation(
      title = "Temperature loggers with barometric pressure, precipitation and earthquakes",
      caption = paste0("Dashed line: last temperature download (", format(last_logger, "%Y-%m-%d"), "); pressure, precipitation and earthquakes continue to 2026-11-14.\n",
                       "Pressure: Reno airport (IEM ASOS). Precipitation: Reno airport (NOAA GHCN-Daily). Earthquakes: USGS catalog, magnitude 1.5 and above, Reno-Tahoe region.\n",
                       "Orange vertical lines: earthquakes within 60 km (solid within 15 km, dotted 15-60 km). The series are shown on one date axis; no causal link is tested here."),
      theme = theme(plot.caption = element_text(hjust = 0, size = 8)))
  ggsave(file.path(out_dir, "temperature_context_timeseries.png"), fig, width = 10, height = 11.5, dpi = 170)
  invisible(fig)
}

#' Creek chloride samples (upstream and downstream stations) as a tidy table.
.creek_chloride <- function(con) {
  d <- DBI::dbGetQuery(con, "
    SELECT l.external_station_code AS code, l.name, s.sample_id, s.collection_time, s.data_source,
           MAX(CASE WHEN la.analyte = 'Cl' THEN la.value END) AS Cl,
           MAX(CASE WHEN la.analyte = 'B' THEN la.value END) AS B
    FROM Samples s JOIN Locations l ON l.location_id = s.location_id
    JOIN Lab_Analyses la ON la.sample_id = s.sample_id
    WHERE l.external_station_code IN ('SBRR','SBBV','SBGG','SB5','SB6','SB7','STBT02Steamboat-2a')
    GROUP BY s.sample_id")
  d$date <- .parse_any_date_ratios(d$collection_time)
  d$position <- ifelse(d$code %in% c("SBRR", "SB5", "SB6", "STBT02Steamboat-2a"), "Upstream (SBRR, Rhodes Road)", "Downstream (SBBV, SBGG, Geiger Grade)")
  d
}

#' Figure 2: conductivity record with creek chloride as a separate series.
build_conductivity_chloride_figure <- function(con, out_dir = "output/figures/manuscript") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  source("scripts/analysis/sampling_frequency/06_monte_carlo_air_exclusion.R", local = TRUE)
  source("scripts/analysis/conservative_tracer_ratios.R", local = TRUE)
  ec <- get_sc_record(con); rt <- retrieval_times(ec)
  ec$class <- ifelse(!is.na(ec$qc_flag), "QC-flagged", "Used")
  for (i in seq_len(nrow(rt))) ec$class[ec$site == rt$site[i] & is.na(ec$qc_flag) &
                                          ec$timestamp >= rt$t[i] - 3 * 86400 & ec$timestamp <= rt$t[i] + 3600] <- "Open-air days before retrieval"
  ec$class[ec$site == "SBGG" & is.na(ec$qc_flag) & ec$timestamp >= as.POSIXct("2026-09-29", tz = "UTC")] <- "Open-air days before retrieval"
  ec$site <- factor(ec$site, c("SBRR", "SBGG"), c("SBRR (Rhodes Road, upstream)", "SBGG (Geiger Grade, downstream)"))
  cl <- .creek_chloride(con); cl <- cl[!is.na(cl$Cl) & !is.na(cl$date) & cl$date >= as.Date("2025-01-01"), ]
  win <- range(ec$timestamp)
  xr <- as.POSIXct(c("2025-01-01", "2026-11-14"), tz = "UTC")
  pal <- c("Used" = "#0072B2", "Open-air days before retrieval" = "#999999", "QC-flagged" = "#D55E00")
  p1 <- ggplot(ec, aes(timestamp, sc_25c, color = class)) + .quake_ticks(con, xr) + geom_point(size = 0.2, alpha = 0.7) + scale_linetype_manual(NULL, values = c("within 15 km" = "solid", "15-60 km" = "dotted")) +
    facet_wrap(~site, ncol = 1, scales = "free_y") + scale_color_manual(NULL, values = pal) +
    guides(color = guide_legend(override.aes = list(size = 2, alpha = 1))) +
    labs(x = NULL, y = "Specific conductance (uS/cm, 25 C)") + .ts_theme() + coord_cartesian(xlim = xr) +
    theme(legend.position = "bottom")
  p2 <- ggplot(cl, aes(as.POSIXct(date, tz = "UTC"), Cl, color = position, shape = data_source)) +
    annotate("rect", xmin = win[1], xmax = win[2], ymin = -Inf, ymax = Inf, fill = "grey85", alpha = 0.5) +
    annotate("text", x = win[1], y = Inf, label = "logger record", hjust = 0, vjust = 1.5, size = 3) +
    geom_point(size = 2.2) + scale_color_manual(NULL, values = c("#0072B2", "#D55E00")) +
    labs(x = NULL, y = "Chloride (mg/L)", shape = "Source") + .ts_theme() + coord_cartesian(xlim = xr) +
    theme(legend.position = "bottom")
  n_in <- sum(as.POSIXct(cl$date, tz = "UTC") >= win[1])
  fig <- p1 / p2 + plot_layout(heights = c(3, 1.6)) + plot_annotation(
    title = "Conductivity record and creek chloride samples",
    caption = paste0("Loggers began 2026-07-15. Creek chloride samples on file inside the logger record: ", n_in,
                     ". The only recent pair is 2026-05-01 (SBRR and SBBV), before deployment;\ncalibration samples will fall in the shaded band.\n",
                     "Open-air days: three days before each retrieval, and SBGG from 2026-09-29 (daily temperature\nrange rises). Chloride is plotted on its own axis, not scaled to conductance."),
    theme = theme(plot.caption = element_text(hjust = 0, size = 8)))
  ggsave(file.path(out_dir, "conductivity_chloride_timeseries.png"), fig, width = 9, height = 8, dpi = 170)
  invisible(fig)
}

#' Figure 3: chloride and Cl/B against specific conductance (historical pairs; logger pairs when they exist).
build_calibration_so_far_figure <- function(con, out_dir = "output/figures/manuscript") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  suppressMessages(suppressWarnings(source("scripts/analysis/sampling_frequency/03_chloride_models.R", local = TRUE)))
  pr <- suppressMessages(get_chloride_conductance_pairs(con))
  b <- DBI::dbGetQuery(con, "SELECT sample_id, AVG(CASE WHEN lower(units) LIKE 'ug%' OR units LIKE '%g/L' AND lower(units) NOT LIKE 'mg%' THEN value / 1000.0 ELSE value END) AS B FROM Lab_Analyses WHERE analyte = 'B' GROUP BY sample_id")
  pr <- left_join(pr, b, by = "sample_id") |>
    mutate(Cl_B = ifelse(!is.na(B) & B > 0, chloride_mgL / B, NA_real_),
           set = ifelse(pairing_type == "historical_ndep", "Historical NDEP pairs (1987-2020s), Rhodes Road", "Logger-matched pairs"))
  m <- lm(chloride_mgL ~ sc_25c, data = pr)
  pa <- ggplot(pr, aes(sc_25c, chloride_mgL, color = set)) + geom_point(alpha = 0.6, size = 1.3) +
    geom_abline(intercept = coef(m)[1], slope = coef(m)[2], color = "#D55E00") +
    scale_color_manual(NULL, values = c("#0072B2", "#009E73")) +
    labs(x = "Specific conductance (uS/cm)", y = "Chloride (mg/L)",
         subtitle = sprintf("n = %d, Cl = %.1f + %.3f x SC, R-squared = %.2f", nrow(pr), coef(m)[1], coef(m)[2], summary(m)$r.squared)) +
    .ts_theme() + theme(legend.position = "bottom")
  pb_d <- pr[is.finite(pr$Cl_B), ]
  if (nrow(pb_d) >= 3) {
    mb <- lm(Cl_B ~ sc_25c, data = pb_d)
    pb <- ggplot(pb_d, aes(sc_25c, Cl_B)) + geom_point(alpha = 0.6, size = 1.3, color = "#0072B2") +
      labs(x = "Specific conductance (uS/cm)", y = "Cl/B (mass ratio)",
           subtitle = sprintf("n = %d with boron on file; no line drawn (boron near detection limit)", nrow(pb_d))) + .ts_theme()
  } else {
    pb <- ggplot() + annotate("text", x = 0, y = 0, label = sprintf("Cl/B against conductance:\nonly %d pairs have boron on file,\nso no fit is drawn.", nrow(pb_d))) +
      theme_void()
  }
  fig <- pa + pb + plot_annotation(
    title = "Chloride and Cl/B against conductance: the calibration so far",
    caption = "No chloride sample yet overlaps the 2026 logger record, so these are historical pairs (NDEP, same station). The line is a starting reference\nfor the logger calibration, not a fit to the loggers. Boron at this creek station is at or near the detection limit (0.01 to 0.1 mg/L),\nso Cl/B here is noisy; the ratio is more useful as a check on thermal-source composition than as a conductance proxy.",
    theme = theme(plot.caption = element_text(hjust = 0, size = 8)))
  ggsave(file.path(out_dir, "calibration_so_far.png"), fig, width = 10, height = 4.5, dpi = 170)
  invisible(fig)
}

#' Figure 4: chloride and Cl/B at the fissure area and thermal wells and springs through time.
build_fissure_series_figure <- function(con, out_dir = "output/figures/manuscript") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  source("scripts/analysis/conservative_tracer_ratios.R", local = TRUE)
  tr <- tryCatch(read.csv("data/derived/tracer_ratios/tracer_ratios_by_site.csv", stringsAsFactors = FALSE), error = function(e) NULL)
  th <- if (!is.null(tr)) tr |> filter(sample_group == "thermal_endmember", Cl > 0) |>
    transmute(sample_id, feature, data_source, date = as.Date(date), Cl, B) else NULL
  fis <- DBI::dbGetQuery(con, "
    SELECT s.sample_id, l.name AS feature, s.data_source, s.collection_time,
           MAX(CASE WHEN la.analyte = 'Cl' THEN la.value END) AS Cl,
           MAX(CASE WHEN la.analyte = 'B' THEN la.value END) AS B
    FROM Samples s JOIN Locations l ON l.location_id = s.location_id
    JOIN Lab_Analyses la ON la.sample_id = s.sample_id
    WHERE l.external_station_code IN ('SBF_0001','SBW_0003','SBW_0002','SBW_0001') OR s.data_source LIKE 'Lindsey%'
    GROUP BY s.sample_id")
  fis$date <- .parse_any_date_ratios(fis$collection_time)
  fis <- fis[, c("sample_id", "feature", "data_source", "date", "Cl", "B")]
  d <- bind_rows(th, fis) |> distinct(sample_id, .keep_all = TRUE) |> filter(!is.na(date), !is.na(Cl), Cl > 0) |>
    mutate(Cl_B = ifelse(!is.na(B) & B > 0, Cl / B, NA_real_),
           area = ifelse(feature %in% c("SBF_0001", "SBW_0003", "SBW_0002", "SBW_0001") | grepl("Lindsey", data_source),
                         "Fissure area (2025-2026)", "Other thermal wells and springs"))
  lab <- d |> filter(area == "Fissure area (2025-2026)" | date < as.Date("2000-01-01") & Cl > 700)
  base <- ggplot(d, aes(date, color = area, shape = data_source)) + scale_color_manual(NULL, values = c("#D55E00", "#0072B2")) +
    .ts_theme() + labs(x = NULL, shape = "Source") + theme(legend.position = "bottom")
  pa <- base + aes(y = Cl) + geom_point(size = 2) + labs(y = "Chloride (mg/L)")
  pb <- base + aes(y = Cl_B) + geom_point(size = 2, na.rm = TRUE) + labs(y = "Cl/B (mass ratio)")
  fig <- (pa + pb) + plot_layout(guides = "collect") & theme(legend.position = "bottom")
  fig <- fig + plot_annotation(
    title = "Chloride and Cl/B in the geothermal source: fissure area and other thermal wells and springs",
    caption = "Not part of the creek calibration. The fissure area is spatially and probably temporally disconnected from the creek (outflow travel time is unknown),\nso this shows how the source itself changes. Samples are sparse and from different laboratories; Lindsey and others (2026) are dated to June 2025 (month only).",
    theme = theme(plot.caption = element_text(hjust = 0, size = 8)))
  ggsave(file.path(out_dir, "fissure_series.png"), fig, width = 11, height = 4.8, dpi = 170)
  invisible(list(plot = fig, data = d))
}

build_proposal_timeseries_figures <- function(con) {
  build_temperature_context_figure(con)
  build_conductivity_chloride_figure(con)
  build_calibration_so_far_figure(con)
  build_fissure_series_figure(con)
  invisible(TRUE)
}
