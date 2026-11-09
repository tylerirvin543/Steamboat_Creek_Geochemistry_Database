# ------------------------------------------------------------
# export_leapfrog_white_plate2.R
#
# Leapfrog-ready table of the drill holes drawn on White (1968) Plate 2 sections.
# The plate is not georeferenced, so X/Y come from the project's own coordinates
# (Wells table, NAD83 / UTM 11N) and Z follows the DEM policy in dem_helpers.R.
# The plate contributes the section-derived collar elevation, bottom elevation and drawn
# depth, and White's stated surface altitude and drilled depth are carried alongside as
# checks (never used to overwrite one another).
#
# Output (output/leapfrog/white_plate2_holes.csv), metres unless a column says ft:
#   HoleID            Wells.well_name
#   X, Y, Z           UTM 11N and DEM elevation (the usual collar convention)
#   Z_Plate           collar elevation read from the plate section
#   Z_Stated          White (1964) stated land-surface altitude
#   MaxDepth          preferred hole depth: stated if known, else drawn on the plate
#   DepthSource       stated | plate | none
#   MaxDepth_DB       Wells.total_depth (converted to m), for comparison
#   Z_Bottom          Z_Plate - drawn depth (m) and Z_Bottom_Stated from the stated depth
#   PlateStatus       anchor status (confirmed / provisional / unresolved)
#   Flags             free-text cautions (clipped by box, db depth disagrees, no coordinate...)
# ------------------------------------------------------------
suppressPackageStartupMessages({library(DBI); library(dplyr); library(sf); library(readr); library(fs)})
source("scripts/leapfrog/dem_helpers.R")
source("scripts/analysis/white_plate2_sections.R")

export_leapfrog_white_plate2 <- function(con, out_dir = "output/leapfrog") {
  message("---- Exporting White Plate 2 Leapfrog table ----")
  dir_create(out_dir)
  ex <- build_white_plate2_export()$export
  name_map <- c(low_terrace_gs1 = "GS-1", south_steamboat_well = "South Steamboat Well",
                high_terrace_gs2 = "GS-2", main_terrace_gs3 = "GS-3", main_terrace_gs4 = "GS-4",
                main_terrace_gs5 = "GS-5", main_terrace_gs6 = "GS-6", sinter_hill_gs6 = "GS-6",
                main_terrace_gs8 = "GS-8")
  ex$HoleID <- unname(name_map[ex$anchor_id])
  wells <- dbGetQuery(con, "SELECT well_name, latitude, longitude, elevation_m, total_depth FROM Wells")
  d <- left_join(ex, wells, by = c("HoleID" = "well_name"))
  d$X <- NA_real_; d$Y <- NA_real_
  ok <- !is.na(d$latitude) & !is.na(d$longitude)
  if (any(ok)) {
    u <- st_coordinates(st_transform(st_as_sf(d[ok, ], coords = c("longitude", "latitude"), crs = 4326, remove = FALSE), 26911))
    d$X[ok] <- u[, 1]; d$Y[ok] <- u[, 2]
  }
  d$Z_dem <- dem_z(d$X, d$Y)
  d$Z <- dplyr::coalesce(d$Z_dem, d$elevation_m)
  ft <- 0.3048
  d$depth_source <- ifelse(!is.na(d$stated_depth_ft), "stated", ifelse(!is.na(d$drawn_depth_ft), "plate", "none"))
  depth_ft <- dplyr::coalesce(d$stated_depth_ft, d$drawn_depth_ft)
  db_ft <- d$total_depth
  d$Flags <- mapply(function(r) {
    f <- character()
    if (is.na(d$X[r])) f <- c(f, "no coordinate in Wells")
    if (isTRUE(d$clipped_by_box[r])) f <- c(f, "stated bottom is below the plate box; drawn line clipped")
    if (!is.na(db_ft[r]) && !is.na(depth_ft[r]) && abs(db_ft[r] - depth_ft[r]) > 0.15 * depth_ft[r]) f <- c(f, sprintf("Wells.total_depth %.0f ft disagrees with %.0f ft here", db_ft[r], depth_ft[r]))
    if (!is.na(d$surface_diff_ft[r]) && abs(d$surface_diff_ft[r]) > 15) f <- c(f, "plate collar differs from stated altitude by more than 15 ft")
    if (!is.na(d$Z[r]) && !is.na(d$stated_surface_ft[r]) && abs(d$Z[r] - d$stated_surface_ft[r] * 0.3048) > 15) f <- c(f, sprintf("DEM elevation at the stored X/Y is %.0f m from White's stated altitude: coordinate may be wrong", abs(d$Z[r] - d$stated_surface_ft[r] * 0.3048)))
    if (d$status[r] != "confirmed") f <- c(f, paste("plate anchor", d$status[r]))
    if (is.na(d$hole_bottom_px[r])) f <- c(f, "no hole line drawn on the plate")
    paste(f, collapse = "; ")
  }, seq_len(nrow(d)))
  out <- data.frame(
    HoleID = d$HoleID, X = round(d$X, 2), Y = round(d$Y, 2), Z = round(d$Z, 2),
    Z_Plate = round(d$collar_elev_ft * ft, 2), Z_Stated = round(d$stated_surface_ft * ft, 2),
    MaxDepth = round(depth_ft * ft, 2), DepthSource = d$depth_source,
    MaxDepth_Drawn = round(d$drawn_depth_ft * ft, 2), MaxDepth_DB = round(db_ft * ft, 2),
    Z_Bottom = round(d$hole_bottom_elev_ft * ft, 2), Z_Bottom_Stated = round(d$stated_bottom_elev_ft * ft, 2),
    PlateStatus = d$status, Flags = d$Flags, stringsAsFactors = FALSE)
  write_csv(out, path(out_dir, "white_plate2_holes.csv"))
  message("[leapfrog] white_plate2_holes.csv: ", nrow(out), " holes (", sum(!is.na(out$X)), " with X/Y, ", sum(out$PlateStatus == "confirmed"), " confirmed on the plate)")
  invisible(out)
}
