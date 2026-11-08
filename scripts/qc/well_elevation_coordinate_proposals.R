# Proposed (NOT applied) fixes for four wells whose stored elevation/coordinate
# disagree with the permit file and the DEM. Re-computed from the database each
# run; apply only after confirmation. Output: data/derived/well_elevation_coordinate_proposals.csv
library(DBI); library(dplyr); library(readr)
source("scripts/leapfrog/dem_helpers.R")
well_elevation_coordinate_proposals <- function(con, out = "data/derived/well_elevation_coordinate_proposals.csv") {
  w <- dbGetQuery(con, "SELECT well_id, well_name, latitude, longitude, elevation_m, coordinate_source FROM Wells
                        WHERE well_name IN ('83B-6R','83C-6ST1','13-5R','STMGID MW1','83A-6')")
  dz <- function(lat, lon) { xy <- latlon_to_utm(lat, lon); round(dem_z(xy[1], xy[2]), 1) }
  g <- function(n) w[w$well_name == n, ]
  rows <- list(
    tibble(well_name = "83B-6R", field = "elevation_m", stored = g("83B-6R")$elevation_m, evidence = "NDOM 4080 ft; permit file (0561) 5732 ft = 1747 m; DEM at stored coordinate",
           evidence_value = dz(g("83B-6R")$latitude, g("83B-6R")$longitude), proposed = dz(g("83B-6R")$latitude, g("83B-6R")$longitude),
           note = "Stored 1243.6 m is not credible for the 83-6 pad. Keep NDOM coordinate (35 m from 83A-6); the permit-file coordinate (-119.7882) is 1.36 km west, probably a UTM typo."),
    tibble(well_name = "83C-6ST1", field = "coordinate", stored = NA_real_, evidence = "stored point is 1.1 km east of the 83-6 pad; DEM there is 1545 m but stored elevation (1749 m) matches the pad",
           evidence_value = dz(g("83C-6ST1")$latitude, g("83C-6ST1")$longitude),
           proposed = NA_real_, note = paste0("Propose the 83A-6/83B-6R pad coordinate (", round(g("83A-6")$latitude, 5), ", ", round(g("83A-6")$longitude, 5), "), uncertainty ~150 m, then DEM elevation. Sidetrack shares its parent pad.")),
    tibble(well_name = "13-5R", field = "elevation_m", stored = g("13-5R")$elevation_m, evidence = "NDOM 5330 ft; permit file (0340) 5330 ft; permit 0205 well 5600 ft; DEM",
           evidence_value = dz(g("13-5R")$latitude, g("13-5R")$longitude), proposed = dz(g("13-5R")$latitude, g("13-5R")$longitude),
           note = "Coordinate agrees with permit file (26 m). Elevation 100 m below DEM; propose DEM value."),
    tibble(well_name = "STMGID MW1", field = "elevation_m", stored = g("STMGID MW1")$elevation_m, evidence = "NDWR site 087 N18 E20 19AAAB1 (section-level position); DEM at stored point",
           evidence_value = dz(g("STMGID MW1")$latitude, g("STMGID MW1")$longitude), proposed = dz(g("STMGID MW1")$latitude, g("STMGID MW1")$longitude),
           note = "Outside the Steamboat field. Stored elevation 92 m above DEM; coordinate unverified, needs the NDWR record. Propose DEM value only if the coordinate is confirmed."))
  d <- bind_rows(rows) |> mutate(status = "proposed_not_applied", stored = round(stored, 1))
  write_csv(d, out); d
}
