# ============================================================
# export_leapfrog_images.R
#
# Makes the georeferenced images used in ArcGIS usable in Leapfrog, and gives them a Z value.
#
# Why: the images are flat pictures. Leapfrog places a flat image at one elevation (or at 0 m, far
# below a model that sits near 1,400-2,000 m), and several of them are saved with a rotated
# geotransform (ArcGIS first-order polynomial, .tfwx / .pgwx), which Leapfrog does not handle. For
# each image this function writes, to output/leapfrog/images/:
#   <name>_26911.tif          north-up GeoTIFF in NAD83 / UTM 11N (EPSG:26911), same CRS as the
#                             DEM and every other Leapfrog file; no rotation, transparent outside
#                             the original footprint (alpha band)
#   <name>_dem.tif            the 1 m USGS 3DEP DEM on exactly the same grid (Float32), so the image
#                             and the surface it drapes over line up pixel for pixel
#   <name>_points_xyz.csv     one row per grid cell at `point_spacing_m`: X, Y, Z (DEM at that X, Y),
#                             R, G, B (and TempC for the thermal map), for import as points when an
#                             image cannot be draped. Z is calculated at export time from the current
#                             DEM, like every other Z in this folder.
#   IMAGES_README.txt         how to load them in Leapfrog
# ============================================================
suppressPackageStartupMessages({library(terra); library(sf); library(dplyr); library(readr)})
source("scripts/leapfrog/dem_helpers.R")

.lf_images <- list(
  list(name = "thermal_map_lower_sinter", path = "data/raw/IR/Callahan_2025/thermalmap_lowersinterter.tif",
       res = 0.5, point_spacing_m = 2, thermal = TRUE, method = "average",
       note = "NBMG/Callahan thermal map layout export; TempC is the color-ramp temperature (7-44 C, ceiling 44 C)"),
  list(name = "collar_plate3", path = "docs/literature/collar paper and plates/collar-plate3.tif",
       res = 1, point_spacing_m = 10, thermal = FALSE, method = "bilinear",
       note = "Collar (1990) Plate 3, georeferenced in ArcGIS (rotated first-order polynomial)"),
  list(name = "white1968_plate1_lower_sinter_zoomout", path = "docs/literature/White papers and plates/Lower_Sinter_Terrace_mapzoomout_Whiteplate1_458-c.png",
       res = 1, point_spacing_m = 5, thermal = FALSE, method = "bilinear", note = "White (1968) Plate 1, Lower Sinter Terrace, zoomed out"),
  list(name = "white1968_plate3_lower_sinter", path = "docs/literature/White papers and plates/Lower_Sinter_Terrace_map_Whiteplate3_458-c.png",
       res = 0.5, point_spacing_m = 2, thermal = FALSE, method = "bilinear", note = "White (1968) Plate 3, Lower Sinter Terrace"))

.ramp_temp_c <- function(rgb, t_bottom = 7, t_top = 44, max_dist = 25, min_sat = 60) {
  pal <- t(col2rgb(viridisLite::magma(256))); out <- rep(NA_real_, nrow(rgb))
  sat <- apply(rgb, 1, max) - apply(rgb, 1, min); ok <- which(!is.na(rgb[, 1]) & sat > min_sat)
  for (s in split(ok, ceiling(seq_along(ok) / 20000))) {
    x <- rgb[s, , drop = FALSE]
    d2 <- outer(x[, 1], pal[, 1], "-")^2 + outer(x[, 2], pal[, 2], "-")^2 + outer(x[, 3], pal[, 3], "-")^2
    i <- max.col(-d2, ties.method = "first"); d <- sqrt(d2[cbind(seq_len(nrow(x)), i)])
    out[s] <- ifelse(d < max_dist, t_bottom + (i - 1) / 255 * (t_top - t_bottom), NA)
  }
  round(out, 1)
}

export_leapfrog_images <- function(out_dir = "output/leapfrog/images", images = .lf_images) {
  message("---- Exporting Leapfrog images with Z (rectified, UTM 11N, DEM on the same grid) ----")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dem <- .dem_raster(); if (is.null(dem)) { message("  no DEM under data/raw/dem; skipped"); return(invisible(NULL)) }
  done <- list()
  for (im in images) {
    if (!file.exists(im$path)) { message("  - ", im$name, ": source file not found, skipped"); next }
    src <- suppressWarnings(rast(im$path))
    eu <- ext(project(as.polygons(ext(src), crs = crs(src)), "EPSG:26911"))
    res <- im$res
    xmin <- floor(eu$xmin / res) * res; xmax <- ceiling(eu$xmax / res) * res; ymin <- floor(eu$ymin / res) * res; ymax <- ceiling(eu$ymax / res) * res
    out_tif <- file.path(out_dir, paste0(im$name, "_26911.tif"))
    sf::gdal_utils("warp", source = normalizePath(im$path), destination = out_tif,
                   options = c("-overwrite", "-t_srs", "EPSG:26911", "-te", xmin, ymin, xmax, ymax, "-tr", res, res, "-r", im$method,
                               "-dstalpha", "-ot", "Byte", "-co", "COMPRESS=LZW", "-co", "TILED=YES", "-co", "BIGTIFF=IF_SAFER"), quiet = TRUE)
    img <- rast(out_tif)
    tmpl <- rast(ext(img), resolution = res, crs = "EPSG:26911")
    demc <- resample(crop(dem, ext(img)), tmpl, method = "bilinear"); names(demc) <- "elevation_m"
    out_dem <- file.path(out_dir, paste0(im$name, "_dem.tif")); writeRaster(demc, out_dem, overwrite = TRUE, datatype = "FLT4S", gdal = c("COMPRESS=LZW"))
    # points
    fact <- max(1, round(im$point_spacing_m / res)); a <- aggregate(img, fact = fact, fun = "mean", na.rm = TRUE)
    v <- values(a); xy <- xyFromCell(a, seq_len(ncell(a)))
    nb <- nlyr(a); alpha <- v[, nb]; rgbv <- v[, seq_len(min(3, nb - 1)), drop = FALSE]
    if (ncol(rgbv) == 1) rgbv <- cbind(rgbv, rgbv, rgbv)
    keep <- !is.na(alpha) & alpha > 127
    if (isTRUE(im$thermal)) keep <- keep & rowSums(rgbv) > 0
    pts <- data.frame(X = round(xy[keep, 1], 2), Y = round(xy[keep, 2], 2), R = round(rgbv[keep, 1]), G = round(rgbv[keep, 2]), B = round(rgbv[keep, 3]))
    pts$Z <- dem_z(pts$X, pts$Y); pts <- pts[!is.na(pts$Z), c("X", "Y", "Z", "R", "G", "B")]
    if (isTRUE(im$thermal)) pts$TempC <- .ramp_temp_c(as.matrix(pts[, c("R", "G", "B")]))
    write_csv(pts, file.path(out_dir, paste0(im$name, "_points_xyz.csv")))
    message(sprintf("  - %s: %d x %d px at %g m, %d points at %g m spacing; Z %.1f to %.1f m", im$name, ncol(img), nrow(img), res, nrow(pts), im$point_spacing_m, min(pts$Z), max(pts$Z)))
    done[[im$name]] <- data.frame(name = im$name, source = im$path, crs_in = crs(src, describe = TRUE)$code, grid_m = res, points = nrow(pts),
                                  x_min = xmin, x_max = xmax, y_min = ymin, y_max = ymax, z_min = min(pts$Z), z_max = max(pts$Z), note = im$note)
  }
  idx <- do.call(rbind, done); if (!is.null(idx)) write_csv(idx, file.path(out_dir, "images_index.csv"))
  writeLines(c(
"Images for Leapfrog, with a Z value",
"",
"All files are NAD83 / UTM zone 11N (EPSG:26911), metres, the same CRS as the DEM and the other files in output/leapfrog.",
"The source images carry no elevation, and several were saved rotated. Each image has been rectified (north-up, no rotation), and given a DEM on the same grid.",
"",
"For each image <name>:",
"  <name>_26911.tif       image (3 bands plus alpha; plates may be 1 band plus alpha)",
"  <name>_dem.tif         USGS 3DEP DEM resampled to exactly the same grid (elevation in metres)",
"  <name>_points_xyz.csv  X, Y, Z (DEM), R, G, B (and TempC for the thermal map), one row per grid cell at the spacing in images_index.csv",
"",
"Ways to use them in Leapfrog (pick one):",
"  1. Draped on topography (preferred). Import <name>_dem.tif as a topography/surface (or use the project topography), import <name>_26911.tif as a georeferenced image, and drape the image on the surface. Both files share one grid, so nothing needs to be shifted.",
"  2. As points. Import <name>_points_xyz.csv as a points object with X, Y, Z and colour or colour-by-attribute (R, G, B, or TempC for the thermal map).",
"  3. Flat at one elevation. Only for a quick look: set the image elevation to a single value; it will not follow the terrain.",
"",
"Z is the DEM at each cell and is recalculated whenever this export is re-run."), file.path(out_dir, "IMAGES_README.txt"))
  invisible(idx)
}
