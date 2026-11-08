# ============================================================
# thermal_overlay_maps.R
#
# Builds the manuscript figures that put the georeferenced thermal map (EPSG:26911),
# the >=30 C polygons in Thermal_Areas, mapped fissures and faults, our own points
# and loggers, and the historical White/Collar features on one map, plus the
# resort tank (A009) hourly temperature profile.
#
#   map_fissure_zone.png        fissure zone (SBF_0001/0002, SBW_0003, NV26-1)
#   map_resort_sw_cluster.png   resort tanks and the south-west anomaly cluster
#   a009_hourly_profile.png     mean tank temperature by hour of day, weekday vs weekend
#
# The NV26-1 point is the user's ArcGIS placement (2026-11-08); NV26-1 is stored as an
# alias of SBF_0001, so it has no Locations row of its own.
# ============================================================
library(terra); library(sf); library(dplyr); library(ggplot2); library(ggrepel); library(DBI); library(lubridate)

.tom_cfg <- list(tif = "data/raw/IR/Callahan_2025/thermalmap_lowersinterter.tif",
                 nv26_1 = c(lon = -119.7404718, lat = 39.3822595))

.tom_bg <- function(r, xlim, ylim, n = 7e5) {
  cr <- crop(r, ext(xlim[1], xlim[2], ylim[1], ylim[2]))
  s <- spatSample(cr, n, method = "regular", as.raster = TRUE)
  v <- values(s); xy <- xyFromCell(s, seq_len(ncell(s))); ok <- complete.cases(v) & rowSums(v) > 0
  list(df = data.frame(x = xy[ok, 1], y = xy[ok, 2], col = rgb(v[ok, 1], v[ok, 2], v[ok, 3], maxColorValue = 255)),
       w = res(s)[1], h = res(s)[2])
}

.tom_data <- function(con) {
  to_sf <- function(df, wkt = "geom_wkt") st_as_sf(df, wkt = wkt, crs = 4326) |> st_zm() |> st_transform(26911)
  fis <- to_sf(dbGetQuery(con, "SELECT fissure_name, geom_wkt FROM Fissure_Traces"))
  flt <- to_sf(dbGetQuery(con, "SELECT fault_name, confidence, geom_wkt FROM Fault_Traces"))
  ta <- dbGetQuery(con, "SELECT feature_key, geom_wkt, substr(method, instr(method, 'class = ') + 8) AS class FROM Thermal_Areas") |> to_sf()
  loc <- dbGetQuery(con, "SELECT l.location_id, l.name, l.external_station_code AS code, l.site_type, l.latitude AS lat, l.longitude AS lon,
                           g.logger_name FROM Locations l
                           LEFT JOIN Temperature_Loggers g ON g.location_id = l.location_id
                           WHERE l.latitude IS NOT NULL")
  pts <- st_as_sf(loc, coords = c("lon", "lat"), crs = 4326) |> st_transform(26911)
  list(fis = fis, flt = flt, ta = ta, pts = pts)
}

build_thermal_overlay_maps <- function(con, out_dir = "output/figures/manuscript", cfg = .tom_cfg) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  r <- rast(cfg$tif); d <- .tom_data(con)
  ours <- d$pts |> filter(grepl("^(SBS|SBF|SBW|SBO)_", name))
  hist <- d$pts |> filter(grepl("^WHITE1968_|^COLLAR|^MJ1995|^SOREY|^KLEIN", code), !location_id %in% ours$location_id)
  nv26 <- st_sf(name = "NV26-1", geometry = st_sfc(st_point(cfg$nv26_1), crs = 4326)) |> st_transform(26911)
  cls_col <- c(ellipse_anomaly = "#ff7f0e", resort_infrastructure = "#d62728", circle_13m = "#1f77b4",
               outside_rings = "#9467bd", other_small = "grey70")

  map_window <- function(xlim, ylim, file, title, width = 9, height = 8) {
    b <- .tom_bg(r, xlim, ylim)
    win <- st_as_sfc(st_bbox(c(xmin = xlim[1], xmax = xlim[2], ymin = ylim[1], ymax = ylim[2]), crs = st_crs(26911)))
    inw <- function(x) x[lengths(st_intersects(x, win)) > 0, ]
    oo <- inw(ours); lg <- oo |> filter(!is.na(logger_name))
    sp <- oo |> filter(is.na(logger_name), site_type %in% c("fumarole", "spring", "seep", "steaming ground", "well"))
    hh <- inw(hist)
    lab <- bind_rows(lg |> mutate(lab = paste0(name, " (", logger_name, ")")), sp |> mutate(lab = name))
    lab_xy <- cbind(st_drop_geometry(lab)[, "lab", drop = FALSE], st_coordinates(lab))
    hc <- st_coordinates(hh); h_xy <- data.frame(name = hh$name, X = hc[, 1], Y = hc[, 2])
    p <- ggplot() +
      geom_tile(data = b$df, aes(x, y, fill = col), width = b$w, height = b$h) + scale_fill_identity() +
      geom_sf(data = inw(d$flt), colour = "#4fc3f7", linewidth = 0.7, linetype = "dashed") +
      geom_sf(data = inw(d$fis), colour = "white", linewidth = 0.35, alpha = 0.8) +
      geom_sf(data = inw(d$ta), aes(colour = class), fill = NA, linewidth = 0.7) +
      scale_colour_manual(values = cls_col, name = ">=30 C polygons") +
      geom_sf(data = hh, shape = 5, size = 2, colour = "yellow", stroke = 0.8) +
      geom_text_repel(data = h_xy, aes(X, Y, label = name), size = 2.2, colour = "yellow", segment.colour = "yellow",
                      segment.alpha = 0.5, max.overlaps = 40) +
      geom_sf(data = sp, shape = 21, size = 2.6, fill = "cyan", colour = "black", stroke = 0.6) +
      geom_sf(data = lg, shape = 24, size = 3.4, fill = "limegreen", colour = "black", stroke = 0.7) +
      geom_sf(data = inw(nv26), shape = 23, size = 3, fill = "magenta", colour = "black") +
      geom_text_repel(data = lab_xy, aes(X, Y, label = lab), size = 2.8, colour = "white", fontface = "bold",
                      segment.colour = "white", bg.colour = "black", bg.r = 0.12, max.overlaps = 40) +
      coord_sf(xlim = xlim, ylim = ylim, datum = 26911, expand = FALSE) +
      labs(title = title, x = "Easting (m, EPSG:26911)", y = "Northing (m)") +
      theme(legend.position = "bottom")
    ggsave(file, p, width = width, height = height, dpi = 140)
    invisible(file)
  }
  map_window(c(263900, 264110), c(4362700, 4362890), file.path(out_dir, "map_fissure_zone.png"),
             "Fissure zone: SBF_0001, SBF_0002, SBW_0003 and NV26-1")
  map_window(c(263730, 263960), c(4362380, 4362600), file.path(out_dir, "map_resort_sw_cluster.png"),
             "Resort tanks and the south-west anomaly cluster")

  # A009 (SBW_0002 resort tank): mean temperature by hour of day, weekday vs weekend (local time)
  a9 <- dbGetQuery(con, "SELECT CAST(o.timestamp AS INTEGER) ts, o.temperature FROM Temperature_Observations o
                         JOIN Temperature_Loggers l ON l.logger_id = o.logger_id WHERE l.logger_name = 'A009' ORDER BY ts")
  a9 <- a9 |> filter(temperature > 68) |>
    mutate(t = with_tz(as.POSIXct(ts, origin = "1970-01-01", tz = "UTC"), "America/Los_Angeles"),
           daytype = ifelse(wday(t, week_start = 1) <= 5, "Weekday", "Weekend"), h = hour(t))
  hp <- a9 |> group_by(daytype, h) |> summarise(T = mean(temperature), .groups = "drop")
  p2 <- ggplot(hp, aes(h, T, colour = daytype)) + geom_line() + geom_point() +
    labs(x = "Hour of day (PDT)", y = "Mean tank temperature (C)", colour = NULL)
  ggsave(file.path(out_dir, "a009_hourly_profile.png"), p2, width = 7, height = 4.2, dpi = 150)
  message("[THERMAL MAPS] wrote map_fissure_zone.png, map_resort_sw_cluster.png, a009_hourly_profile.png to ", out_dir)
  invisible(TRUE)
}
