# ============================================================
# register_well_coordinates.R
#
# Purpose:
# Apply human-reviewed coordinate matches (currently: NBMG's
# "Geothermal_Wells" statewide ArcGIS Open Data layer -- see
# https://data-nbmg.opendata.arcgis.com/datasets/72341ba987e34c12a575c83f1d7c5367_0)
# to existing Wells rows in the Dhakal et al. (2025) flow network
# (see database/schema/05_well_network_schema.R,
# scripts/ingest/register_well_network.R). Kept as its own file/step
# because coordinate provenance is a materially different kind of
# claim than the network topology (well_role / port links) those
# handle, and deserves its own review trail.
#
# Input: data/raw/wells/dhakal_well_coordinates.csv
#   columns: well_name, latitude, longitude, apino,
#            coordinate_source, coordinate_uncertainty_m, notes
#   Each row's `notes` documents the exact NBMG record matched
#   (including its apino permit id where available), any competing
#   candidates considered and rejected, and a plain-language
#   confidence flag for ambiguous matches -- read that column before
#   trusting a given well's coordinate.
#
# Idempotency: matched on Wells.well_name (must already exist --
# typically created by register_well_network.R or
# 05_well_network_schema.R's seed step -- rows for an unknown
# well_name are skipped with a warning, not silently dropped).
# Coordinates are only written when the existing Wells.latitude is
# NULL, so a manually-corrected or field-verified coordinate is never
# clobbered by re-running this against a revised CSV.
# ============================================================

library(DBI)
library(dplyr)
library(readr)
library(fs)

register_well_coordinates <- function(
    con,
    coords_csv = "data/raw/wells/dhakal_well_coordinates.csv") {

  message("---- Registering NBMG-matched well coordinates ----")

  if (!file_exists(coords_csv)) {
    message("[register well coordinates] No coordinate map at ", coords_csv, " -- nothing to register.")
    return(invisible(NULL))
  }

  coords <- read_csv(coords_csv, show_col_types = FALSE) %>%
    mutate(well_name = trimws(well_name)) %>%
    filter(!is.na(well_name), well_name != "", !is.na(latitude), !is.na(longitude))

  updated <- 0L
  skipped_missing_well <- character(0)
  skipped_already_set <- character(0)

  for (i in seq_len(nrow(coords))) {
    row <- coords[i, ]

    well <- dbGetQuery(con, "SELECT well_id, latitude FROM Wells WHERE well_name = ?",
                        params = list(row$well_name))

    # Fall back to Well_Aliases if the coordinate CSV uses an alias (e.g.
    # "IW-5") rather than the canonical Wells.well_name (e.g. "46-28") --
    # both refer to the same physical well, and this lets a coordinate
    # file written from field/figure naming resolve without the caller
    # needing to know each well's canonical name in advance.
    if (nrow(well) == 0) {
      alias_match <- dbGetQuery(con, "
        SELECT w.well_id, w.latitude FROM Well_Aliases a
        JOIN Wells w ON w.well_id = a.well_id
        WHERE a.alias = ?
      ", params = list(row$well_name))
      if (nrow(alias_match) > 0) well <- alias_match
    }

    if (nrow(well) == 0) {
      skipped_missing_well <- c(skipped_missing_well, row$well_name)
      next
    }

    if (!is.na(well$latitude[1])) {
      skipped_already_set <- c(skipped_already_set, row$well_name)
      next
    }

    dbExecute(con, "
      UPDATE Wells
      SET latitude = ?, longitude = ?,
          coord_key = ? || '_' || ?,
          coordinate_source = ?, coordinate_uncertainty_m = ?, notes = ?
      WHERE well_id = ?
    ", params = list(
      row$latitude, row$longitude,
      row$latitude, row$longitude,
      row$coordinate_source, row$coordinate_uncertainty_m, row$notes,
      well$well_id[1]
    ))
    updated <- updated + 1L
  }

  if (length(skipped_missing_well) > 0) {
    warning("[register well coordinates] ", length(skipped_missing_well),
            " row(s) reference a well_name not found in Wells -- skipped: ",
            paste(skipped_missing_well, collapse = ", "),
            ". Add these via dhakal_well_network.csv first.")
  }

  message("  -> Coordinates set for ", updated, " well(s)",
          if (length(skipped_already_set) > 0) paste0(
            "; ", length(skipped_already_set),
            " already had a coordinate and were left untouched (",
            paste(skipped_already_set, collapse = ", "), ")"
          ) else "",
          ".")

  invisible(list(updated = updated, skipped_missing_well = skipped_missing_well,
                  skipped_already_set = skipped_already_set))
}
