# ------------------------------------------------------------
# export_leapfrog_structure.R
#
# Structural, surface-feature and topographic inputs for Leapfrog, next to the well tables
# from export_leapfrog.R. EVERY coordinate here is NAD83 / UTM zone 11N (EPSG:26911), metres,
# and every Z is the DEM elevation at the feature's current X, Y (dem_helpers.R), computed at
# export time, so a moved feature gets a new Z on the next export.
#
# CSV vertex tables (X, Y, Z):
#   fault_traces.csv      FaultID, FaultName, Confidence, FaultType, DipDirection, UncertaintyM, Part, Vertex, X, Y, Z
#   fissure_traces.csv    FissureID, FissureName, StatusLabel, LengthM, UncertaintyM, Part, Vertex, X, Y, Z
#   mapped_polygons.csv   PolygonID, PolygonName, FeatureType, AreaM2, UncertaintyM, Part, Ring, Vertex, X, Y, Z
#   locations_points.csv  LocationID, Name, SiteType, X, Y, Z, CoordinateSource, UncertaintyM
# 3-D shapefiles for Leapfrog's GIS import (output/leapfrog/gis/): faults_3d, fissures_3d,
#   mapped_polygons_3d, locations_3d (all EPSG:26911 with Z).
# topography_dem_5m.tif   DEM clipped to the study area at 5 m (the 1 m tile is in data/raw/dem/).
# CRS_README.txt          coordinate system of every file in output/leapfrog/.
# Positional accuracy is limited by the source (e.g. 200 m for faults traced from a figure);
# it is carried in the UncertaintyM columns, not hidden.
# ------------------------------------------------------------
suppressPackageStartupMessages({library(DBI); library(sf); library(dplyr)})
source("scripts/leapfrog/dem_helpers.R")

.has_table <- function(con, t) t %in% dbListTables(con)

# vertices of an sf (UTM) with Z from the DEM
.vertices <- function(x, id_col, extra) {
  rows <- lapply(seq_len(nrow(x)), function(i) {
    xy <- st_coordinates(x[i, ])
    d <- data.frame(ID = x[[id_col]][i], X = round(xy[, "X"], 2), Y = round(xy[, "Y"], 2))
    d$Part <- if ("L3" %in% colnames(xy)) xy[, "L3"] else if ("L2" %in% colnames(xy)) xy[, "L2"] else xy[, "L1"]
    d$Ring <- if ("L3" %in% colnames(xy)) xy[, "L1"] else 1L
    for (n in names(extra)) d[[n]] <- x[[extra[[n]]]][i]
    d$Vertex <- seq_len(nrow(d)); d
  })
  out <- do.call(rbind, rows); out$Z <- dem_z(out$X, out$Y); out
}

# rebuild geometries as XYZ using the DEM
.with_z <- function(x) {
  g <- st_geometry(x); out <- vector("list", length(g))
  zfun <- function(m) cbind(m[, 1:2, drop = FALSE], dem_z(m[, 1], m[, 2]))
  for (i in seq_along(g)) {
    gi <- g[[i]]
    out[[i]] <- if (inherits(gi, "POINT")) st_point(c(unclass(gi)[1:2], dem_z(unclass(gi)[1], unclass(gi)[2])))
      else if (inherits(gi, "LINESTRING")) st_linestring(zfun(unclass(gi)))
      else if (inherits(gi, "MULTILINESTRING")) st_multilinestring(lapply(unclass(gi), zfun))
      else if (inherits(gi, "POLYGON")) st_polygon(lapply(unclass(gi), zfun))
      else if (inherits(gi, "MULTIPOLYGON")) st_multipolygon(lapply(unclass(gi), function(p) lapply(p, zfun)))
      else gi
  }
  st_set_geometry(x, st_sfc(out, crs = st_crs(x)))
}

.write_csv <- function(d, out_dir, nm) { write.csv(d, file.path(out_dir, nm), row.names = FALSE, na = ""); invisible(d) }
.no_dem_msg <- function(z) if (all(is.na(z))) " (no DEM found: Z empty)" else paste0(" (", sum(is.na(z)), " vertices outside the DEM)")

export_leapfrog_faults <- function(con, out_dir = "output/leapfrog") {
  message("---- Exporting Leapfrog fault traces ----")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  if (!.has_table(con, "Fault_Traces")) return(invisible(NULL))
  ft <- dbGetQuery(con, "SELECT fault_id, fault_name, fault_type, confidence, dip_direction, dip_angle_deg, dip_angle_basis, digitizing_uncertainty_m, geom_wkt FROM Fault_Traces")
  if (!nrow(ft)) { message("  no fault traces yet"); return(invisible(NULL)) }
  s <- st_transform(st_as_sf(ft, wkt = "geom_wkt", crs = 4326), 26911)
  v <- .vertices(s, "fault_id", list(FaultName = "fault_name", Confidence = "confidence", FaultType = "fault_type", DipDirection = "dip_direction", DipAngleDeg = "dip_angle_deg", DipBasis = "dip_angle_basis", UncertaintyM = "digitizing_uncertainty_m"))
  out <- v %>% transmute(FaultID = ID, FaultName, Confidence, FaultType, DipDirection, DipAngleDeg, DipBasis, UncertaintyM, Part, Vertex, X, Y, Z)
  .write_csv(out, out_dir, "fault_traces.csv")
  message("  -> fault_traces.csv: ", nrow(s), " trace(s), ", nrow(out), " vertices", .no_dem_msg(out$Z))
  invisible(s)
}

export_leapfrog_fissures <- function(con, out_dir = "output/leapfrog") {
  message("---- Exporting Leapfrog fissure traces ----")
  if (!.has_table(con, "Fissure_Traces")) return(invisible(NULL))
  fi <- dbGetQuery(con, "SELECT fissure_id, fissure_name, status_label, length_m, digitizing_uncertainty_m, geom_wkt FROM Fissure_Traces")
  if (!nrow(fi)) { message("  no fissure traces yet"); return(invisible(NULL)) }
  s <- st_transform(st_as_sf(fi, wkt = "geom_wkt", crs = 4326), 26911)
  v <- .vertices(s, "fissure_id", list(FissureName = "fissure_name", StatusLabel = "status_label", LengthM = "length_m", UncertaintyM = "digitizing_uncertainty_m"))
  out <- v %>% transmute(FissureID = ID, FissureName, StatusLabel, LengthM, UncertaintyM, Part, Vertex, X, Y, Z)
  .write_csv(out, out_dir, "fissure_traces.csv")
  message("  -> fissure_traces.csv: ", nrow(s), " line(s), ", nrow(out), " vertices", .no_dem_msg(out$Z))
  invisible(s)
}

export_leapfrog_polygons <- function(con, out_dir = "output/leapfrog") {
  message("---- Exporting Leapfrog mapped polygons ----")
  if (!.has_table(con, "Mapped_Polygons")) return(invisible(NULL))
  mp <- dbGetQuery(con, "SELECT polygon_id, polygon_name, feature_type, area_m2, digitizing_uncertainty_m, geom_wkt FROM Mapped_Polygons")
  if (!nrow(mp)) { message("  no polygons yet"); return(invisible(NULL)) }
  s <- st_transform(st_as_sf(mp, wkt = "geom_wkt", crs = 4326), 26911)
  v <- .vertices(s, "polygon_id", list(PolygonName = "polygon_name", FeatureType = "feature_type", AreaM2 = "area_m2", UncertaintyM = "digitizing_uncertainty_m"))
  out <- v %>% transmute(PolygonID = ID, PolygonName, FeatureType, AreaM2, UncertaintyM, Part, Ring, Vertex, X, Y, Z)
  .write_csv(out, out_dir, "mapped_polygons.csv")
  message("  -> mapped_polygons.csv: ", nrow(s), " polygon(s), ", nrow(out), " vertices", .no_dem_msg(out$Z))
  invisible(s)
}

export_leapfrog_locations <- function(con, out_dir = "output/leapfrog") {
  message("---- Exporting Leapfrog location points ----")
  l <- dbGetQuery(con, "SELECT location_id, name, site_type, latitude, longitude, coordinate_source, coordinate_uncertainty_m, elevation_m FROM Locations WHERE latitude IS NOT NULL AND longitude IS NOT NULL")
  s <- st_transform(st_as_sf(l, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE), 26911)
  xy <- st_coordinates(s)
  zd <- dem_z(xy[, 1], xy[, 2])
  out <- data.frame(LocationID = l$location_id, Name = l$name, SiteType = l$site_type, X = round(xy[, 1], 2), Y = round(xy[, 2], 2), Z = dplyr::coalesce(zd, l$elevation_m), Z_Source = ifelse(!is.na(zd), 'DEM', ifelse(!is.na(l$elevation_m), 'stored elevation (outside DEM)', NA)),
                    CoordinateSource = l$coordinate_source, UncertaintyM = l$coordinate_uncertainty_m)
  .write_csv(out, out_dir, "locations_points.csv")
  message("  -> locations_points.csv: ", nrow(out), " points", .no_dem_msg(out$Z))
  invisible(s)
}

export_leapfrog_gis_3d <- function(con, out_dir = "output/leapfrog") {
  message("---- Writing 3-D shapefiles for Leapfrog GIS import ----")
  gdir <- file.path(out_dir, "gis"); dir.create(gdir, showWarnings = FALSE, recursive = TRUE)
  wr <- function(x, name) {
    gt <- unique(as.character(st_geometry_type(x)))
    if (any(gt == 'MULTILINESTRING')) x <- suppressWarnings(st_cast(x, 'LINESTRING'))
    if (any(gt == 'MULTIPOLYGON')) x <- suppressWarnings(st_cast(x, 'POLYGON'))
    x <- .with_z(x)
    if (all(st_geometry_type(x) == 'POINT')) {
      z <- vapply(st_geometry(x), function(p) unclass(p)[3], 0)
      if (any(is.na(z))) message('  (', sum(is.na(z)), ' point(s) outside the DEM left out of ', name, ')')
      x <- x[!is.na(z), ]
    }
    shpt <- c(POINT = 'POINTZ', LINESTRING = 'ARCZ', POLYGON = 'POLYGONZ')[[as.character(st_geometry_type(x)[1])]]
    st_write(x, file.path(gdir, paste0(name, '.shp')), delete_layer = TRUE, quiet = TRUE, layer_options = paste0('SHPT=', shpt))
    message('  -> gis/', name, '.shp (', nrow(x), ')')
  }
  q <- function(sql) dbGetQuery(con, sql)
  tr <- function(df) st_transform(st_as_sf(df, wkt = "geom_wkt", crs = 4326), 26911)
  if (.has_table(con, "Fault_Traces")) { f <- q("SELECT fault_id AS id, fault_name AS name, confidence AS conf, fault_type AS type, dip_direction AS dip, digitizing_uncertainty_m AS unc_m, geom_wkt FROM Fault_Traces"); if (nrow(f)) wr(tr(f), "faults_3d") }
  if (.has_table(con, "Fissure_Traces")) { f <- q("SELECT fissure_id AS id, fissure_name AS name, length_m, geom_wkt FROM Fissure_Traces"); if (nrow(f)) wr(tr(f), "fissures_3d") }
  if (.has_table(con, "Mapped_Polygons")) { f <- q("SELECT polygon_id AS id, polygon_name AS name, feature_type AS type, area_m2, geom_wkt FROM Mapped_Polygons"); if (nrow(f)) wr(tr(f), "mapped_polygons_3d") }
  l <- q("SELECT location_id AS id, name, site_type AS type, latitude, longitude, elevation_m FROM Locations WHERE latitude IS NOT NULL AND longitude IS NOT NULL")
  lp <- st_transform(st_as_sf(l, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE), 26911); xy <- st_coordinates(lp)
  z <- dplyr::coalesce(dem_z(xy[, 1], xy[, 2]), l$elevation_m); keep <- !is.na(z)
  if (any(!keep)) message("  (", sum(!keep), " point(s) with no DEM or stored elevation left out of locations_3d)")
  p3 <- st_as_sf(data.frame(id = l$id[keep], name = l$name[keep], type = l$type[keep], X = xy[keep, 1], Y = xy[keep, 2], Z = z[keep]), coords = c("X", "Y", "Z"), crs = 26911)
  st_write(p3, file.path(gdir, "locations_3d.shp"), delete_layer = TRUE, quiet = TRUE, layer_options = "SHPT=POINTZ"); message("  -> gis/locations_3d.shp (", nrow(p3), ")")
  invisible(TRUE)
}

export_leapfrog_topography <- function(out_dir = "output/leapfrog", con = NULL, fact = 5L, pad_m = 1500) {
  message("---- Exporting Leapfrog topography ----")
  r <- .dem_raster(); if (is.null(r)) { message("  no DEM under data/raw/dem"); return(invisible(NULL)) }
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  # extent: the study-area rectangle if it is in the database, otherwise the collars, plus a padding
  e <- NULL
  if (!is.null(con) && .has_table(con, "Mapped_Polygons")) {
    sa <- dbGetQuery(con, "SELECT geom_wkt FROM Mapped_Polygons WHERE feature_type = 'study_area'")
    if (nrow(sa)) { bb <- st_bbox(st_transform(st_as_sf(sa, wkt = "geom_wkt", crs = 4326), 26911)); e <- terra::ext(bb["xmin"] - pad_m, bb["xmax"] + pad_m, bb["ymin"] - pad_m, bb["ymax"] + pad_m) }
  }
  if (is.null(e) && file.exists(file.path(out_dir, "collar.csv"))) { c0 <- read.csv(file.path(out_dir, "collar.csv")); e <- terra::ext(min(c0$X) - pad_m, max(c0$X) + pad_m, min(c0$Y) - pad_m, max(c0$Y) + pad_m) }
  if (!is.null(e)) r <- terra::crop(r, terra::intersect(e, terra::ext(r)))
  r5 <- terra::aggregate(r, fact = fact, fun = "mean", na.rm = TRUE)
  terra::writeRaster(r5, file.path(out_dir, "topography_dem_5m.tif"), overwrite = TRUE, datatype = "FLT4S")
  message("  -> topography_dem_5m.tif: ", terra::nrow(r5), " x ", terra::ncol(r5), " cells at ", round(terra::res(r5)[1], 2), " m")
  invisible(r5)
}

write_leapfrog_crs_readme <- function(out_dir = "output/leapfrog") {
  writeLines(c("Coordinate system of the files in this folder (written by export_leapfrog_structure.R)", "",
    "Projected coordinates (X/Y, UTM_E/UTM_N): NAD83 / UTM zone 11N, EPSG:26911, metres.",
    "Z and elevations: metres above the vertical datum of the USGS 3DEP 1 m DEM (NAVD88), sampled at each feature's current X, Y.",
    "Depths (From, To, MaxDepth, DepthToWater_m, Depth_m): metres below ground at the hole, no coordinates.", "",
    "collar.csv, fault_traces.csv, fissure_traces.csv, mapped_polygons.csv, locations_points.csv, geophysical_horizons.csv,",
    "geophysical_grid_surfaces.csv, topography_dem_5m.tif, gis/*.shp : EPSG:26911.",
    "survey.csv, lithology.csv, completion_interval.csv, chemistry_*.csv, water_levels.csv: no coordinates; join to collar.csv by HoleID.",
    "collar_incomplete.csv: reference only, geographic latitude/longitude (NAD83/WGS84), NOT for import.", "",
    "Z is recalculated from the DEM at every export, so a moved feature gets a new Z automatically."), file.path(out_dir, "CRS_README.txt"))
}

export_leapfrog_structure_all <- function(con, out_dir = "output/leapfrog") {
  export_leapfrog_faults(con, out_dir); export_leapfrog_fissures(con, out_dir); export_leapfrog_polygons(con, out_dir)
  export_leapfrog_locations(con, out_dir); export_leapfrog_gis_3d(con, out_dir); export_leapfrog_topography(out_dir, con); write_leapfrog_crs_readme(out_dir)
  invisible(TRUE)
}
