# ------------------------------------------------------------
# dem_helpers.R
#
# One place for DEM elevations used by the Leapfrog exports.
#   dem_z(x, y)               surface elevation (m) at NAD83 / UTM 11N coordinates, bilinear
#                             from the 1 m USGS 3DEP tile in data/raw/dem/. NA outside the tile.
#   refresh_dem_elevations(con)  keeps stored elevations in step with the DEM (below).
#
# Policy (2026-11-07): every exported feature gets Z from the DEM at its CURRENT coordinate,
# calculated at export time. Nothing derived from a position is stored, so if a location moves
# and the export is re-run, Z follows. For the database itself, refresh_dem_elevations():
#   - Wells.elevation_m is replaced by the DEM value when it was itself derived from a DEM or
#     3DEP query (notes contain 'elevation_m from/refreshed from USGS 3DEP' or '... from DEM')
#     or is empty, and the coordinate now gives a value more than 0.5 m different. Elevations
#     that came from a permit or survey (NDOM, NDWR, literature) are never overwritten.
#   - Locations.elevation_m is filled only where empty.
# Re-running changes nothing unless a coordinate (or the DEM) changed.
# ------------------------------------------------------------
suppressPackageStartupMessages({library(DBI); library(sf)})

.dem_env <- new.env()
.dem_files <- function() list.files("data/raw/dem", pattern = "\\.tif$", full.names = TRUE)
.dem_raster <- function() {
  p <- .dem_files(); if (!length(p)) return(NULL)
  key <- paste(p, file.mtime(p), collapse = "|")
  if (is.null(.dem_env$r) || !identical(.dem_env$key, key)) {
    .dem_env$r <- if (length(p) == 1) terra::rast(p) else terra::vrt(p)   # several 1 m tiles are mosaicked on the fly
    .dem_env$key <- key
  }
  .dem_env$r
}

dem_z <- function(x, y) {
  r <- .dem_raster(); if (is.null(r) || !length(x)) return(rep(NA_real_, length(x)))
  ok <- !is.na(x) & !is.na(y); z <- rep(NA_real_, length(x))
  if (any(ok)) z[ok] <- round(terra::extract(r, cbind(x[ok], y[ok]), method = "bilinear")[, 1], 2)
  z
}

latlon_to_utm <- function(lat, lon) {
  ok <- !is.na(lat) & !is.na(lon); out <- matrix(NA_real_, length(lat), 2, dimnames = list(NULL, c("X", "Y")))
  if (any(ok)) out[ok, ] <- st_coordinates(st_transform(st_as_sf(data.frame(lon = lon[ok], lat = lat[ok]), coords = c("lon", "lat"), crs = 4326), 26911))
  out
}

refresh_dem_elevations <- function(con, tol_m = 0.5) {
  message("---- Refreshing stored elevations from the DEM ----")
  if (is.null(.dem_raster())) { message("  no DEM under data/raw/dem; skipped"); return(invisible(NULL)) }
  w <- dbGetQuery(con, "SELECT well_id, latitude, longitude, elevation_m, notes FROM Wells WHERE latitude IS NOT NULL AND longitude IS NOT NULL")
  xy <- latlon_to_utm(w$latitude, w$longitude); w$dem <- dem_z(xy[, 1], xy[, 2])
  derived <- is.na(w$elevation_m) | grepl("elevation_m (from|refreshed from) (USGS 3DEP|DEM)", ifelse(is.na(w$notes), "", w$notes))
  upd <- w[derived & !is.na(w$dem) & (is.na(w$elevation_m) | abs(w$elevation_m - w$dem) > tol_m), ]
  for (i in seq_len(nrow(upd)))
    dbExecute(con, "UPDATE Wells SET elevation_m = ?, notes = CASE WHEN COALESCE(notes,'') LIKE '%elevation_m from DEM%' OR COALESCE(notes,'') LIKE '%elevation_m from USGS 3DEP%' OR COALESCE(notes,'') LIKE '%elevation_m refreshed from USGS 3DEP%' THEN notes ELSE TRIM(COALESCE(notes,'') || ' [elevation_m from DEM (USGS 3DEP 1 m tile)]') END WHERE well_id = ?", params = list(upd$dem[i], upd$well_id[i]))
  l <- dbGetQuery(con, "SELECT location_id, latitude, longitude FROM Locations WHERE latitude IS NOT NULL AND longitude IS NOT NULL AND elevation_m IS NULL")
  xyl <- latlon_to_utm(l$latitude, l$longitude); l$dem <- dem_z(xyl[, 1], xyl[, 2]); l <- l[!is.na(l$dem), ]
  for (i in seq_len(nrow(l))) dbExecute(con, "UPDATE Locations SET elevation_m = ? WHERE location_id = ?", params = list(l$dem[i], l$location_id[i]))
  chk <- w[!derived & !is.na(w$dem) & !is.na(w$elevation_m) & abs(w$elevation_m - w$dem) > 10, c("well_id", "latitude", "longitude", "elevation_m", "dem")]
  if (nrow(chk)) {
    chk$diff_m <- round(chk$elevation_m - chk$dem, 1); chk <- chk[order(-abs(chk$diff_m)), ]
    dir.create("data/derived", showWarnings = FALSE, recursive = TRUE); write.csv(chk, "data/derived/dem_elevation_discrepancies.csv", row.names = FALSE)
  }
  message("  -> Wells updated: ", nrow(upd), " | Locations filled: ", nrow(l), " | reported (non-derived) elevations more than 5 m from the DEM: ",
          sum(!derived & !is.na(w$dem) & abs(w$elevation_m - w$dem) > 5))
  invisible(list(wells = nrow(upd), locations = nrow(l)))
}
