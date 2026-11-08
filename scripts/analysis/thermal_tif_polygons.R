# ============================================================
# thermal_tif_polygons.R
#
# Turns the georeferenced Callahan thermal map layout
# (data/raw/IR/Callahan_2025/thermalmap_lowersinterter.tif, EPSG:26911) into
# temperature-threshold polygons and writes them to Thermal_Areas.
#
# Method: every pixel is matched to the nearest colour of the magma ramp
# (7-44 C, linear stretch assumed from the PDF legend; the TIFF has no legend
# of its own). Pixels farther than `max_dist` RGB units from the ramp, weakly
# saturated pixels (hillshade, satellite), and the baked-in yellow/blue overlay
# colours are left out. The ramp saturates at 44 C.
#
# Classes (by the yellow annotation rings baked into the TIFF, saved by the
# earlier analysis to data/derived/thermal_areas/tif_yellow_rings_epsg26911.gpkg):
#   ellipse_anomaly, circle_13m, other_small  (inside a ring)
#   resort_infrastructure  (outside every ring, centroid within `resort_radius_m`
#                           of SBW_0002: tanks, pipe, pavement)
#   outside_rings          (everything else)
# The rings are analyst annotations, not a verified geothermal boundary.
#
# Idempotent: rows with this source_file are replaced on every run.
# ============================================================
library(terra); library(sf); library(dplyr); library(DBI)

.tif_cfg <- list(
  tif = "data/raw/IR/Callahan_2025/thermalmap_lowersinterter.tif",
  rings = "data/derived/thermal_areas/tif_yellow_rings_epsg26911.gpkg",
  t_bottom = 7, t_top = 44, max_dist = 25, min_sat = 60,
  min_polygon_m2 = 0.5, resort_radius_m = 60, resort_anchor = "SBW_0002")

.tif_hot_pixels <- function(cfg = .tif_cfg, cutoff = 30, chunk = 1000) {
  r <- rast(cfg$tif)
  pal <- t(col2rgb(viridisLite::magma(256)))
  idx_min <- floor((cutoff - cfg$t_bottom) / (cfg$t_top - cfg$t_bottom) * 255) + 1
  out <- list()
  for (r0 in seq(1, nrow(r), by = chunk)) {
    n <- min(chunk, nrow(r) - r0 + 1)
    v <- values(r, row = r0, nrows = n, mat = TRUE)
    mx <- pmax(v[, 1], v[, 2], v[, 3]); mn <- pmin(v[, 1], v[, 2], v[, 3])
    ov <- (v[, 1] > 200 & v[, 2] > 200 & v[, 3] < 80) | (v[, 3] > 150 & v[, 1] < 60)
    keep <- which(!is.na(v[, 1]) & (mx - mn) > cfg$min_sat & !ov & v[, 1] >= 120)
    if (!length(keep)) next
    x <- v[keep, , drop = FALSE]
    d2 <- outer(x[, 1], pal[, 1], "-")^2 + outer(x[, 2], pal[, 2], "-")^2 + outer(x[, 3], pal[, 3], "-")^2
    idx <- max.col(-d2, ties.method = "first"); d <- sqrt(d2[cbind(seq_len(nrow(x)), idx)])
    ok <- d < cfg$max_dist & idx >= idx_min
    if (any(ok)) out[[length(out) + 1]] <- data.frame(cell = (r0 - 1) * ncol(r) + keep[ok], idx = idx[ok])
  }
  hot <- do.call(rbind, out)
  hot$temp_c <- cfg$t_bottom + (hot$idx - 1) / 255 * (cfg$t_top - cfg$t_bottom)
  list(r = r, hot = hot)
}

build_tif_thermal_polygons <- function(con = NULL, cutoff = 30, cfg = .tif_cfg, write_db = !is.null(con),
                                       out_gpkg = "data/derived/thermal_areas/tif_ge30C_polygons_epsg26911.gpkg") {
  hp <- .tif_hot_pixels(cfg, cutoff)
  r <- hp$r; hot <- hp$hot
  message(sprintf("[TIF polygons] %d pixels >= %g C = %.0f m2", nrow(hot), cutoff, nrow(hot) * prod(res(r))))
  xy <- xyFromCell(r, hot$cell)
  pad <- res(r)
  e <- ext(min(xy[, 1]) - pad[1], max(xy[, 1]) + pad[1], min(xy[, 2]) - pad[2], max(xy[, 2]) + pad[2])
  m <- rast(e, resolution = res(r), crs = crs(r)); values(m) <- NA
  m[cellFromXY(m, xy)] <- 1
  pixel_area <- nrow(hot) * prod(res(r))
  # The thermal layer is semi-transparent over a hillshade, so hot blobs are speckled at pixel scale.
  # Close the mask (dilate then erode, about 0.5 m window) so each blob becomes one polygon.
  w <- matrix(1, nrow = 5, ncol = 3)   # 5 rows x 3 cols = ~0.49 m x ~0.52 m
  m[is.na(m)] <- 0
  dil <- focal(m, w = w, fun = "max", fillvalue = 0)
  ero <- focal(dil, w = w, fun = "min", fillvalue = 0)
  ero[ero == 0] <- NA
  pol <- as.polygons(ero, dissolve = TRUE) |> st_as_sf() |> st_cast("POLYGON", warn = FALSE)
  pol <- st_make_valid(pol) |> st_cast("POLYGON", warn = FALSE)   # as.polygons can leave touching-corner bowties
  pol$area_m2 <- as.numeric(st_area(pol))
  pol <- pol[pol$area_m2 >= cfg$min_polygon_m2, ]
  pol$temp_max_c <- NA_real_; pol$temp_mean_c <- NA_real_
  pt <- st_as_sf(data.frame(x = xy[, 1], y = xy[, 2], t = hot$temp_c), coords = c("x", "y"), crs = 26911)
  hit <- st_intersects(pol, pt)
  pol$temp_max_c <- vapply(hit, function(i) if (length(i)) max(pt$t[i]) else NA_real_, 1)
  pol$temp_mean_c <- vapply(hit, function(i) if (length(i)) mean(pt$t[i]) else NA_real_, 1)
  message(sprintf("[TIF polygons] %d polygons kept (>= %.2f m2), total polygon area %.0f m2 vs %.0f m2 counted pixel by pixel", nrow(pol), cfg$min_polygon_m2, sum(pol$area_m2), pixel_area))

  # class by yellow ring containment, then resort proximity
  pol$class <- "outside_rings"
  if (file.exists(cfg$rings)) {
    rings <- st_read(cfg$rings, quiet = TRUE) |> st_transform(26911)
    rings <- rings[rings$class != "large_enclosure", ]
    cen <- st_centroid(st_geometry(pol))
    cls <- vapply(seq_len(nrow(pol)), function(i) {
      h <- which(lengths(st_intersects(rings, cen[i])) > 0)
      if (!length(h)) h <- which(lengths(st_intersects(rings, pol[i, ])) > 0)
      if (!length(h)) return("outside_rings")
      rings$class[h[which.min(rings$area_m2[h])]]
    }, "")
    pol$class <- cls
  } else message("[TIF polygons] ring file not found; all polygons classed outside_rings")
  if (!is.null(con)) {
    a <- dbGetQuery(con, sprintf("SELECT latitude, longitude FROM Locations WHERE name='%s'", cfg$resort_anchor))
    if (nrow(a)) {
      anc <- st_as_sf(a, coords = c("longitude", "latitude"), crs = 4326) |> st_transform(26911)
      d <- as.numeric(st_distance(st_centroid(st_geometry(pol)), anc))
      pol$class[pol$class == "outside_rings" & d <= cfg$resort_radius_m] <- "resort_infrastructure"
    }
  }
  pol <- pol[order(-pol$area_m2), ]
  pol$feature_key <- sprintf("TIF_ge%g_%s_%03d", cutoff, pol$class, ave(seq_len(nrow(pol)), pol$class, FUN = seq_along))
  print(pol |> st_drop_geometry() |> group_by(class) |> summarise(polygons = n(), area_m2 = round(sum(area_m2), 1), .groups = "drop"))

  dir.create(dirname(out_gpkg), recursive = TRUE, showWarnings = FALSE)
  st_write(pol[, c("feature_key", "class", "area_m2", "temp_max_c", "temp_mean_c")], out_gpkg, delete_dsn = TRUE, quiet = TRUE)

  if (write_db) {
    stopifnot(dbExistsTable(con, "Thermal_Areas"))
    w <- st_transform(pol, 4326)
    method <- sprintf("TIFF RGB -> nearest magma colour (%g-%g C stretch assumed from PDF legend; saturates at %g C), RGB distance < %g, saturation > %g, overlay colours excluded; class = ",
                      cfg$t_bottom, cfg$t_top, cfg$t_top, cfg$max_dist, cfg$min_sat)
    dbExecute(con, "DELETE FROM Thermal_Areas WHERE source_file = ?", params = list(cfg$tif))
    rows <- data.frame(feature_key = pol$feature_key, survey_date = "unknown (flight date of this TIFF not recorded)", cutoff_c = cutoff,
                       source_file = cfg$tif, method = paste0(method, pol$class), uncertainty_c = NA_real_,
                       area_m2 = round(pol$area_m2, 3), georef_rmse_m = NA_real_,
                       geom_wkt = st_as_text(st_geometry(w), digits = 15), stringsAsFactors = FALSE)
    dbWriteTable(con, "Thermal_Areas", rows, append = TRUE)
    message(sprintf("[TIF polygons] wrote %d rows to Thermal_Areas", nrow(rows)))
  }
  invisible(pol)
}
