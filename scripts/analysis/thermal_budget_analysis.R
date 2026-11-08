# ============================================================
# thermal_budget_analysis.R
#
# Four read-only analyses built on Thermal_Areas (the >=30 C polygons from the
# georeferenced thermal map), the chloride mass balance, and the resort tank logger:
#
#   build_thermal_attribution(con)      area at or above 30 C by source (resort, fissure zone,
#                                       Lower Terrace channel, creek-corridor springs, ...)
#   estimate_thermal_budget(con)        order-of-magnitude surface heat loss versus the heat carried
#                                       by the thermal inflow, and an implied thermal-water temperature
#                                       from a creek energy balance (exploratory, assumptions listed)
#   build_resort_share_curve_figure()   resort share of the thermal inflow versus discharge rate
#   analyze_resort_schedule(con)        A009 (SBW_0002 tank) by month and a test of whether the resort
#                                       cycle appears in the creek conductivity difference
#
# Everything is an exploratory estimate; assumptions are written into the output tables.
# ============================================================
library(sf); library(dplyr); library(tidyr); library(ggplot2); library(patchwork); library(DBI); library(lubridate)
source("scripts/analysis/thermal_overlay_maps.R")   # .tom_bg(), .tom_cfg

.tba_cfg <- list(
  polygons = "data/derived/thermal_areas/tif_ge30C_polygons_epsg26911.gpkg",
  rings = "data/derived/thermal_areas/tif_yellow_rings_epsg26911.gpkg",
  cl_csv = "data/derived/chloride_mass_balance/chloride_mass_balance.csv",
  out_dir = "data/derived/thermal_areas",
  fig_dir = "output/figures/manuscript",
  # Ring centroids (EPSG:26911) of the ellipse annotations and the source each marks.
  anchors = data.frame(
    x = c(263966.0, 263789.6, 263833.7, 263907.8, 264014.3, 264046.6, 264078.0, 264035.5, 264036.0, 264055.3),
    y = c(4362797, 4362482, 4362538, 4362579, 4362565, 4363100, 4362648, 4363183, 4363266, 4362745),
    zone = c("Fissure zone (Fissures 42-44)", "Lower Terrace channel (northwest-southeast)",
             "Streak at the pipe end near the resort (uncertain)", "Hillside ellipse",
             rep("Creek-corridor springs and seeps", 6)),
    stringsAsFactors = FALSE),
  resort_anchor_x = 263847.6, resort_anchor_y = 4362494)

.tba_zone_levels <- c("Resort tanks, pipe and pavement", "Fissure zone (Fissures 42-44)",
                      "Lower Terrace channel (northwest-southeast)", "Creek-corridor springs and seeps",
                      "Streak at the pipe end near the resort (uncertain)", "Hillside ellipse",
                      "Annotated 13.5 m circles (ambiguous)", "Outside every outline")

.tba_zones <- function(cfg = .tba_cfg) {
  pol <- st_read(cfg$polygons, quiet = TRUE)
  rings <- st_read(cfg$rings, quiet = TRUE) |> st_transform(26911)
  ell <- rings[rings$class == "ellipse_anomaly", ]
  cen <- st_coordinates(st_centroid(st_geometry(ell)))
  ell$zone <- vapply(seq_len(nrow(ell)), function(i) {
    d <- sqrt((cfg$anchors$x - cen[i, 1])^2 + (cfg$anchors$y - cen[i, 2])^2)
    if (min(d) <= 30) cfg$anchors$zone[which.min(d)] else "Outside every outline"
  }, "")
  pc <- st_centroid(st_geometry(pol))
  pol$zone <- vapply(seq_len(nrow(pol)), function(i) {
    if (pol$class[i] == "resort_infrastructure") return("Resort tanks, pipe and pavement")
    if (pol$class[i] == "circle_13m") return("Annotated 13.5 m circles (ambiguous)")
    h <- which(lengths(st_intersects(ell, pc[i])) > 0)
    if (length(h)) ell$zone[h[which.min(ell$area_m2[h])]] else "Outside every outline"
  }, "")
  pol$zone <- factor(pol$zone, levels = .tba_zone_levels)
  pol
}

build_thermal_attribution <- function(con = NULL, cfg = .tba_cfg) {
  pol <- .tba_zones(cfg)
  tab <- pol |> st_drop_geometry() |> group_by(zone) |>
    summarise(polygons = n(), mean_temp_c = round(weighted.mean(temp_mean_c, area_m2), 1), max_temp_c = round(max(temp_max_c), 1), area_m2 = round(sum(area_m2), 1), .groups = "drop") |>
    select(zone, polygons, area_m2, mean_temp_c, max_temp_c) |>
    mutate(share_pct = round(100 * area_m2 / sum(area_m2), 1))
  dir.create(cfg$out_dir, recursive = TRUE, showWarnings = FALSE)
  write.csv(tab, file.path(cfg$out_dir, "thermal_area_attribution.csv"), row.names = FALSE)
  print(as.data.frame(tab))

  # Figure: whole-terrace map (polygons drawn 4 m wider for visibility) beside a bar of area by source
  r <- terra::rast(.tom_cfg$tif)
  bb <- st_bbox(pol); xl <- c(bb["xmin"] - 40, bb["xmax"] + 40); yl <- c(bb["ymin"] - 40, bb["ymax"] + 40)
  b <- .tom_bg(r, xl, yl, n = 9e5)
  zcol <- c("#d62728", "#ff7f0e", "#e6c229", "#17becf", "#9467bd", "grey60", "#1f77b4", "grey85")
  names(zcol) <- .tba_zone_levels
  p_map <- ggplot() +
    geom_tile(data = b$df, aes(x, y, fill = col), width = b$w, height = b$h) + scale_fill_identity() +
    geom_sf(data = st_buffer(pol, 4), aes(colour = zone), fill = NA, linewidth = 0.9) +
    scale_colour_manual(values = zcol, drop = FALSE, guide = "none") +
    coord_sf(xlim = xl, ylim = yl, datum = 26911, expand = FALSE) +
    labs(x = "Easting (m, EPSG:26911)", y = "Northing (m)") + theme(axis.text.x = element_text(size = 7))
  p_bar <- ggplot(tab |> mutate(zone = factor(zone, levels = rev(.tba_zone_levels))), aes(area_m2, zone, fill = zone)) +
    geom_col() + geom_text(aes(label = paste0(round(area_m2), " m2")), hjust = -0.1, size = 3) +
    scale_fill_manual(values = zcol, guide = "none") + scale_x_continuous(expand = expansion(mult = c(0, 0.25))) +
    scale_y_discrete(labels = function(x) stringr::str_wrap(x, 30)) +
    labs(x = "Area at or above 30 C (m2)", y = NULL)
  p <- p_map + p_bar + plot_layout(widths = c(1, 1.25))
  dir.create(cfg$fig_dir, recursive = TRUE, showWarnings = FALSE)
  ggsave(file.path(cfg$fig_dir, "thermal_area_attribution.png"), p, width = 11, height = 10, dpi = 140)
  invisible(tab)
}

estimate_thermal_budget <- function(con, cfg = .tba_cfg) {
  pol <- st_read(cfg$polygons, quiet = TRUE) |> st_drop_geometry()
  cl <- read.csv(cfg$cl_csv)
  sigma <- 5.670374e-8; eps <- 0.95; Ta <- 10
  loss <- function(h) {
    Ts <- pmax(pol$temp_mean_c, 30)
    q <- h * (Ts - Ta) + eps * sigma * ((Ts + 273.15)^4 - (Ta + 273.15)^4)
    sum(q * pol$area_m2) / 1e6
  }
  surf <- data.frame(item = "Surface heat loss from polygons at or above 30 C (MW)", low = loss(10), mid = loss(15), high = loss(25),
                     assumption = "Convective coefficient 10 / 15 / 25 W/m2/K, emissivity 0.95, ambient 10 C, surface = polygon mean temperature (ramp saturates at 44 C, so a lower bound)")
  Qth <- cl$Q_TW_Ls[1] / 1000                   # m3/s thermal inflow from the chloride balance
  adv <- function(Tth, Tcr = 15.2) Qth * 1000 * 4.18 * (Tth - Tcr) / 1000    # MW (1 L = 1 kg)
  advd <- data.frame(item = paste0("Heat carried by the ", round(Qth * 1000, 1), " L/s thermal inflow above creek temperature (MW), thermal water at 60 / 90 / 130 C"),
                     low = adv(60), mid = adv(90), high = adv(130), assumption = "Creek water 15.2 C; heat capacity 4.18 kJ/kg/K")
  # creek energy balance on the paired date
  Qu <- cl$discharge_up[1]; Qd <- cl$discharge_down[1]; Tu <- 15.2; Td <- 23.7
  Qin <- Qd - Qu; mixT <- (Qd * Td - Qu * Tu) / Qin
  Tth <- function(Tnt) (Qin * mixT - (Qin - Qth) * Tnt) / Qth
  implied <- data.frame(item = "Implied temperature of the thermal inflow (C), non-thermal inflow at 10 / 15.2 / 20 C",
                        low = Tth(10), mid = Tth(15.2), high = Tth(20),
                        assumption = sprintf("Energy balance between SBRR (%.3f m3/s, %.1f C) and SBBV (%.3f m3/s, %.1f C) on %s; total inflow %.0f L/s at a mixed %.1f C; no heat loss to air (so a lower bound)",
                                             Qu, Tu, Qd, Td, cl$date[1], Qin * 1000, mixT))
  share <- data.frame(item = "Surface heat loss as a share of the advected heat (%), mid surface loss over the 60 / 90 / 130 C cases",
                      low = 100 * surf$mid / advd$low, mid = 100 * surf$mid / advd$mid, high = 100 * surf$mid / advd$high,
                      assumption = "Mid convective coefficient (15 W/m2/K)")
  out <- bind_rows(surf, advd, implied, share) |> mutate(across(c(low, mid, high), ~ round(.x, 2)))
  write.csv(out, file.path(cfg$out_dir, "thermal_heat_budget_estimates.csv"), row.names = FALSE)
  print(as.data.frame(out[, c("item", "low", "mid", "high")]))
  invisible(out)
}

build_resort_share_curve_figure <- function(cfg = .tba_cfg, duty = 0.58) {
  cl <- read.csv(cfg$cl_csv)
  flux_diff <- cl$cl_flux_down_gs[1] - cl$cl_flux_up_gs[1]
  share <- function(Q) 100 * Q * 0.849 / flux_diff
  rate <- seq(0, 12, by = 0.05)
  df <- bind_rows(data.frame(Q = rate, s = share(rate), curve = "Pumped continuously"),
                  data.frame(Q = rate, s = share(rate * duty), curve = "Scaled by the A009 duty cycle (58% of the day)"))
  hist <- data.frame(Q = c(1.893, 3.785, 9.779), lab = c("30 gpm\n(1985 test)", "60 gpm\n(1945-52 average,\n1989 peak)", "155 gpm\n(1945-52 peak)"))
  hist$s <- share(hist$Q)
  p <- ggplot(df, aes(Q, s, colour = curve)) + geom_line(linewidth = 0.9) +
    geom_vline(data = hist, aes(xintercept = Q), linetype = "dashed", colour = "grey40") +
    geom_text(data = hist, aes(Q, 24, label = lab), inherit.aes = FALSE, size = 3, hjust = -0.05, lineheight = 0.9) +
    scale_colour_manual(values = c("#d62728", "#1f77b4"), name = NULL) +
    labs(x = "Resort discharge reaching the creek while pumping (L/s)", y = "Share of the 58.65 L/s thermal inflow (%)") +
    coord_cartesian(ylim = c(0, 28)) + theme(legend.position = "bottom")
  dir.create(cfg$fig_dir, recursive = TRUE, showWarnings = FALSE)
  ggsave(file.path(cfg$fig_dir, "resort_share_curve.png"), p, width = 7.5, height = 4.8, dpi = 150)
  invisible(p)
}

analyze_resort_schedule <- function(con, cfg = .tba_cfg) {
  tz <- "America/Los_Angeles"
  a9 <- dbGetQuery(con, "SELECT CAST(o.timestamp AS INTEGER) ts, o.temperature FROM Temperature_Observations o
                         JOIN Temperature_Loggers l ON l.logger_id = o.logger_id WHERE l.logger_name = 'A009' ORDER BY ts") |>
    filter(temperature > 68) |>
    mutate(t = with_tz(as.POSIXct(ts, origin = "1970-01-01", tz = "UTC"), tz), date = as.Date(t, tz = tz),
           hour = hour(t) + minute(t) / 60, month = format(t, "%Y-%m"), daytype = ifelse(wday(t, week_start = 1) <= 5, "Weekday", "Weekend"))
  days <- a9 |> group_by(date, month, daytype) |> filter(n() >= 0.9 * 288) |>
    summarise(mean = mean(temperature), range = max(temperature) - min(temperature), h_min = hour[which.min(temperature)],
              frac_hot = mean(temperature >= 75.5), .groups = "drop")
  hourly <- a9 |> mutate(h = floor(hour)) |> group_by(month, h) |> summarise(T = mean(temperature), .groups = "drop") |>
    group_by(month) |> arrange(h, .by_group = TRUE) |> summarise(on_fraction = mean(diff(T) > -0.02), .groups = "drop")
  by_month <- days |> group_by(month) |>
    summarise(days = n(), weekend_days = sum(daytype == "Weekend"), mean_c = round(mean(mean), 2), range_c = round(mean(range), 2),
              median_hour_of_min = round(median(h_min), 1), share_at_plateau = round(mean(frac_hot), 2), .groups = "drop") |>
    left_join(hourly |> mutate(on_fraction = round(on_fraction, 2)), by = "month")
  write.csv(by_month, "data/derived/resort_tank/a009_by_month.csv", row.names = FALSE)
  print(as.data.frame(by_month))

  # Does the resort cycle show in the creek? hourly SBGG (downstream) minus SBRR (upstream) specific conductance
  ec <- dbGetQuery(con, "SELECT c.timestamp, l.role, c.sc_25c FROM Conductivity_Observations c JOIN Conductivity_Loggers l USING(logger_id)
                         WHERE c.qc_flag IS NULL AND c.logger_event IS NULL AND c.sc_25c IS NOT NULL")
  ec <- ec |> mutate(t = with_tz(as.POSIXct(timestamp, tz = "UTC"), tz), h = floor_date(t, "hour"))
  hr <- ec |> group_by(role, h) |> summarise(sc = mean(sc_25c), .groups = "drop") |> pivot_wider(names_from = role, values_from = sc) |>
    mutate(diff = downstream - upstream_control) |> filter(!is.na(diff))
  a9h <- a9 |> mutate(h = floor_date(t, "hour")) |> group_by(h) |> summarise(tank = mean(temperature), .groups = "drop")
  j <- inner_join(hr, a9h, by = "h") |> mutate(hod = hour(h), date = as.Date(h, tz = tz), daytype = ifelse(wday(h, week_start = 1) <= 5, "Weekday", "Weekend")) |>
    group_by(date) |> filter(n() >= 20) |> mutate(diff_dm = diff - mean(diff), tank_dm = tank - mean(tank)) |> ungroup()
  prof <- j |> group_by(daytype, hod) |> summarise(diff_dm = mean(diff_dm), tank_dm = mean(tank_dm), up_dm = NA_real_, .groups = "drop")
  cors <- prof |> group_by(daytype) |> summarise(r_profile = round(cor(diff_dm, tank_dm), 2), .groups = "drop")
  # daily-detrended hourly series, lagged correlation over all overlapping hours
  ccf_out <- sapply(-6:6, function(k) {
    x <- j$diff_dm; y <- j$tank_dm
    if (k >= 0) cor(x[(1 + k):length(x)], y[1:(length(y) - k)], use = "complete.obs") else cor(x[1:(length(x) + k)], y[(1 - k):length(y)], use = "complete.obs")
  })
  lag_tab <- data.frame(lag_hours = -6:6, r = round(ccf_out, 2))
  res <- list(profile_correlation = cors, lagged = lag_tab, overlap_days = n_distinct(j$date), overlap_hours = nrow(j),
              creek_diff_range_uS = round(diff(range(prof$diff_dm)), 1), tank_range_c = round(diff(range(prof$tank_dm)), 2))
  print(res)
  write.csv(prof, "data/derived/resort_tank/creek_vs_tank_hourly_profile.csv", row.names = FALSE)
  invisible(res)
}

build_phreeqc_pca_figure <- function(con, cfg = .tba_cfg) {
  # PCA of the PHREEQC speciation output (log activities, saturation indices, pH, ionic strength),
  # one point per sample (latest run), coloured by site type. Sentinel values (-999.999) are dropped.
  pr <- dbGetQuery(con, "SELECT sample_id, parameter, value, run_date FROM PHREEQC_Results")
  pr <- pr |> arrange(desc(run_date)) |> distinct(sample_id, parameter, .keep_all = TRUE)
  keep <- grepl("^(log_activity_|SI_|ionic_strength|pH$)", pr$parameter) & pr$parameter != "SI_SiO2_a_"
  w <- pr[keep, ] |> mutate(value = ifelse(value <= -900, NA, value)) |>
    select(sample_id, parameter, value) |> pivot_wider(names_from = parameter, values_from = value)
  st <- dbGetQuery(con, "SELECT s.sample_id, l.site_type FROM Samples s JOIN Locations l ON l.location_id = s.location_id")
  w <- w |> left_join(st, by = "sample_id")
  X <- w |> select(-sample_id, -site_type); X <- X[, colMeans(is.na(X)) <= 0.1]; ok <- complete.cases(X)
  X <- X[, apply(X[ok, ], 2, stats::sd) > 0]; pc <- prcomp(X[ok, ], scale. = TRUE)
  ve <- round(100 * pc$sdev^2 / sum(pc$sdev^2), 1)
  sc <- data.frame(PC1 = pc$x[, 1], PC2 = pc$x[, 2], site_type = coalesce(w$site_type[ok], "unclassified"))
  ld <- data.frame(var = rownames(pc$rotation), PC1 = pc$rotation[, 1], PC2 = pc$rotation[, 2])
  ld$var <- sub("^log_activity_", "log a ", ld$var); ld$var <- gsub("_", "", ld$var)
  k <- 4 * max(abs(sc$PC1), abs(sc$PC2)) / max(abs(ld$PC1), abs(ld$PC2)) / 4
  p <- ggplot(sc, aes(PC1, PC2, colour = site_type)) + geom_point(alpha = 0.7, size = 1.8) +
    geom_segment(data = ld, aes(x = 0, y = 0, xend = PC1 * k, yend = PC2 * k), inherit.aes = FALSE, colour = "grey40", arrow = arrow(length = unit(0.12, "cm"))) +
    ggrepel::geom_text_repel(data = ld, aes(PC1 * k, PC2 * k, label = var), inherit.aes = FALSE, size = 2.6, colour = "grey20", max.overlaps = 30) +
    labs(x = sprintf("PC1 (%.1f%% of variance)", ve[1]), y = sprintf("PC2 (%.1f%% of variance)", ve[2]), colour = "Site type") +
    theme(legend.position = "bottom")
  dir.create(cfg$fig_dir, recursive = TRUE, showWarnings = FALSE)
  ggsave(file.path(cfg$fig_dir, "phreeqc_pca.png"), p, width = 8, height = 6.2, dpi = 140)
  write.csv(cbind(var = ld$var, round(pc$rotation[, 1:3], 3)), file.path(cfg$out_dir, "phreeqc_pca_loadings.csv"), row.names = FALSE)
  message(sprintf("[PHREEQC PCA] %d samples, %d variables, PC1 %.1f%%, PC2 %.1f%%", sum(ok), ncol(X), ve[1], ve[2]))
  invisible(list(scores = sc, var_explained = ve, loadings = ld))
}
