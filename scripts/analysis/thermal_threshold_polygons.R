# ============================================================
# thermal_threshold_polygons.R
#
# Turns the calibrated NBMG thermal-infrared orthophoto layout
# (data/raw/arcgis/thermal_infrared/fissure_system_zoomin_calibrated_july2025.pdf)
# into temperature-threshold polygons.
#
# Method: render the PDF, read the colour bar (44 C top, 7 C bottom, linear
# stretch assumed), assign every map pixel the temperature of its nearest bar
# colour (pixels farther than `max_dist` RGB units from any bar colour, e.g. the
# satellite/hillshade background, are left unclassified), threshold at each
# cutoff, polygonise and drop speckle.
#
# IMPORTANT: the PDF is a layout export with NO embedded georeference. Polygons
# are first written in LOCAL METRES (scale bar: 20 m = 340 px at 300 dpi,
# +/-1 %), not map coordinates. They are placed on the map only when at least
# three control points are supplied in
# data/raw/arcgis/thermal_infrared/tir_control_points.csv
# (pixel_x, pixel_y at 300 dpi, lon, lat). Until then the Thermal_Areas table
# stays empty; nothing is guessed. A radiometric GeoTIFF from NBMG would
# replace this whole step.
# ============================================================
library(DBI); library(dplyr); library(magick); library(FNN); library(terra); library(sf); library(readr)

.tir_cfg <- list(
  pdf = "data/raw/arcgis/thermal_infrared/fissure_system_zoomin_calibrated_july2025.pdf",
  dpi = 300, bar_box = c(x = 2330, y = 4853, w = 20, h = 184), t_top = 44, t_bottom = 7,
  px_per_m_300dpi = 17.0, survey_date = "2025-07-07/08", survey_note = "July 2025 NBMG drone survey (Lindsey et al. 2026: 7-8 July)",
  uncertainty_c = 2)

tir_classify <- function(cfg = .tir_cfg, work_dir = "output/figures/thermal_work", half = TRUE, max_dist = 30) {
  dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)
  png <- file.path(work_dir, "tir_zoom_300.png")
  if (!file.exists(png)) pdftools::pdf_convert(cfg$pdf, format = "png", dpi = cfg$dpi, filenames = png, verbose = FALSE)
  im <- image_read(png)
  bx <- cfg$bar_box
  bar <- as.integer(image_data(image_crop(im, sprintf("%dx%d+%d+%d", bx["w"], bx["h"], bx["x"], bx["y"])), "rgb"))
  bar_col <- cbind(rowMeans(bar[, , 1]), rowMeans(bar[, , 2]), rowMeans(bar[, , 3]))  # h rows (top -> bottom)
  keep <- 3:(nrow(bar_col) - 2)                                                       # drop black border rows
  bar_col <- bar_col[keep, ]
  bar_t <- seq(cfg$t_top, cfg$t_bottom, length.out = nrow(bar_col))
  if (half) im <- image_resize(im, "50%")
  a <- as.integer(image_data(im, "rgb")); d <- dim(a)                                 # h x w x 3 after as.integer()
  px <- cbind(as.vector(a[, , 1]), as.vector(a[, , 2]), as.vector(a[, , 3]))
  nn <- get.knnx(bar_col, px, k = 1)
  temp <- bar_t[nn$nn.index[, 1]]; temp[nn$nn.dist[, 1] > max_dist] <- NA
  m <- matrix(temp, nrow = d[1], ncol = d[2])                                         # rows = y (top -> bottom)
  # mask the legend box (colour bar would otherwise classify as warm)
  sc <- if (half) 0.5 else 1
  m[max(1, floor(4650 * sc)):nrow(m), max(1, floor(2250 * sc)):ncol(m)] <- NA
  list(temp = m, px_per_m = cfg$px_per_m_300dpi * if (half) 0.5 else 1, scale = if (half) 2 else 1)
}

tir_threshold_polygons <- function(cls, cutoffs = c(20, 30, 40), min_area_m2 = 4) {
  m <- cls$temp; ppm <- cls$px_per_m
  out <- list()
  for (cut in cutoffs) {
    b <- matrix(as.integer(!is.na(m) & m >= cut), nrow = nrow(m))
    r <- rast(b, extent = ext(0, ncol(b) / ppm, 0, nrow(b) / ppm))
    p <- as.polygons(r, dissolve = TRUE); p <- p[p[[1]][, 1] == 1]
    if (nrow(p) == 0) next
    s <- st_cast(st_as_sf(p), "POLYGON")
    s$area_m2 <- as.numeric(st_area(s)); s <- s[s$area_m2 >= min_area_m2, ]
    if (nrow(s) == 0) next
    s$cutoff_c <- cut; out[[length(out) + 1]] <- s[, c("cutoff_c", "area_m2")]
  }
  do.call(rbind, out)
}

# Affine placement from >= 3 control points (pixel at 300 dpi -> lon/lat). Returns sf in EPSG:4326 or NULL.
tir_georeference <- function(polys_local, cls, control_csv = "data/raw/arcgis/thermal_infrared/tir_control_points.csv", cfg = .tir_cfg) {
  if (!file.exists(control_csv)) return(NULL)
  cp <- read_csv(control_csv, show_col_types = FALSE)
  cp <- cp[stats::complete.cases(cp[, c("pixel_x", "pixel_y", "lon", "lat")]), ]
  if (nrow(cp) < 3) return(NULL)
  utm <- st_coordinates(st_transform(st_as_sf(cp, coords = c("lon", "lat"), crs = 4326), 26911))
  ppm300 <- cfg$px_per_m_300dpi
  ly <- (5100 - cp$pixel_y) / ppm300
  fx <- lm(utm[, 1] ~ lx + ly); fy <- lm(utm[, 2] ~ lx + ly)
  rmse <- sqrt(mean(c(residuals(fx), residuals(fy))^2))
  message("  -> TIR georeference from ", nrow(cp), " control points, RMSE ", round(rmse, 1), " m")
  g <- st_geometry(polys_local)
  g2 <- lapply(g, function(poly) {
    for (i in seq_along(poly)) {
      xy <- poly[[i]]
      poly[[i]] <- cbind(predict(fx, data.frame(lx = xy[, 1], ly = xy[, 2])), predict(fy, data.frame(lx = xy[, 1], ly = xy[, 2])))
    }
    poly
  })
  out <- st_set_geometry(polys_local, st_sfc(g2, crs = 26911)) |> st_transform(4326)
  attr(out, "rmse_m") <- rmse
  out
}

run_tir_polygons <- function(con = NULL, cutoffs = c(20, 30, 40), out_dir = "data/derived/thermal_areas") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  cls <- tir_classify()
  loc <- tir_threshold_polygons(cls, cutoffs)
  st_write(loc, file.path(out_dir, "tir_july2025_local_metres.gpkg"), delete_dsn = TRUE, quiet = TRUE)
  summ <- loc |> st_drop_geometry() |> group_by(cutoff_c) |> summarise(n_polygons = n(), area_m2 = round(sum(area_m2)), .groups = "drop")
  write_csv(summ, file.path(out_dir, "tir_july2025_threshold_summary.csv"))
  geo <- tir_georeference(loc, cls)
  n_db <- 0L
  if (!is.null(geo) && !is.null(con)) {
    for (i in seq_len(nrow(geo))) {
      key <- paste("tir_july2025", geo$cutoff_c[i], i, sep = "_")
      if (nrow(dbGetQuery(con, "SELECT 1 FROM Thermal_Areas WHERE feature_key = ?", params = list(key))) > 0) next
      dbExecute(con, "INSERT INTO Thermal_Areas (feature_key, survey_date, cutoff_c, source_file, method, uncertainty_c, area_m2, georef_rmse_m, geom_wkt)
                      VALUES (?,?,?,?,?,?,?,?,?)",
                params = list(key, .tir_cfg$survey_date, geo$cutoff_c[i], basename(.tir_cfg$pdf), "colour-bar nearest-colour classification",
                              .tir_cfg$uncertainty_c, geo$area_m2[i], attr(geo, "rmse_m"), st_as_text(st_geometry(geo)[[i]])))
      n_db <- n_db + 1L
    }
  } else message("  -> not georeferenced (no tir_control_points.csv with >= 3 points): Thermal_Areas left empty")
  message("  -> threshold polygons written to ", out_dir, "; rows added to Thermal_Areas: ", n_db)
  list(summary = summ, polygons = loc, georeferenced = !is.null(geo))
}
