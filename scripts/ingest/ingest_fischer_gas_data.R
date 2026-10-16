# ============================================================
# ingest_fischer_gas_data.R
#
# Purpose:
# Ingests the 3 real fissure/fumarole gas samples (NV26-1, NV26-2,
# NV26-3) collected 2026-04-29/04-30 by T. Fischer and K. Mtili with
# P. Ruprecht at the Lower Sinter Terrace, from the hand-transcribed
# data/raw/gas(new)/fischer_gas_2026_clean.csv (see that CSV's own
# provenance notes -- transcribed directly from the real source
# spreadsheet, "Steamboat_NV gases 2026_Fisher_Tobias_Matili_Karim__
# Ruprecht_Philipp_Adams_Ian.xlsx", a multi-block, non-tabular sheet
# not suited to a direct readxl::read_excel() import).
#
# Location handling (per explicit 2026-10-16 user decision):
#   - NV26-1's coordinate is co-located (within GPS noise) with a
#     second, un-ingested SBF_0001 coordinate pair in the raw
#     data/raw/field/locations.xlsx file ("fissure near wellhead
#     temperature logger location"). Rather than create a new
#     Location, NV26-1 is linked to the existing, already-ingested
#     SBF_0001 Locations row (external_station_code = 'SBF_0001',
#     which has a real water/isotope sample, sample_id 816, collected
#     2026-05-01) via a Location_Aliases row -- the live SBF_0001
#     coordinate (a road-edge fix) sits ~60 m from NV26-1's own GPS fix;
#     this gap is recorded in the alias row's notes, not reconciled.
#   - NV26-2 and NV26-3 do not closely match any existing Location and
#     are registered as new Locations rows (site_type = 'fumarole',
#     coordinate_source = 'field_gps').
#
# Idempotent on Gas_Analyses.sample_label (UNIQUE). Safe to re-run.
#
# Usage:
#   source("scripts/ingest/ingest_fischer_gas_data.R")
#   ingest_fischer_gas_data(con)
# ============================================================

library(DBI)
library(dplyr)
library(readr)

ingest_fischer_gas_data <- function(
    con,
    csv_path = "data/raw/gas(new)/fischer_gas_2026_clean.csv") {

  if (!file.exists(csv_path)) {
    message("[fischer_gas] No file at ", csv_path, " -- nothing to ingest.")
    return(invisible(0L))
  }

  rows <- read_csv(csv_path, show_col_types = FALSE)

  n_inserted <- 0L
  n_skipped <- 0L
  n_locations_created <- 0L
  n_aliases_created <- 0L

  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]

    already <- dbGetQuery(con, "SELECT gas_analysis_id FROM Gas_Analyses WHERE sample_label = ?",
                           params = list(r$sample_label))
    if (nrow(already) > 0) {
      n_skipped <- n_skipped + 1L
      next
    }

    # ------------------------------------------------------------
    # Resolve location_id
    # ------------------------------------------------------------
    if (r$sample_label == "NV26-1") {
      sbf1 <- dbGetQuery(con, "SELECT location_id, latitude, longitude FROM Locations WHERE external_station_code = 'SBF_0001'")
      if (nrow(sbf1) == 0) {
        warning("[fischer_gas] SBF_0001 not found in Locations -- registering NV26-1 as its own new Location instead of aliasing.")
        location_id <- NA_integer_
      } else {
        location_id <- sbf1$location_id[1]
        dist_m <- tryCatch({
          # Quick equirectangular approximation -- adequate at this scale.
          lat1 <- sbf1$latitude[1]; lon1 <- sbf1$longitude[1]
          lat2 <- r$latitude[1]; lon2 <- r$longitude[1]
          dlat <- (lat2 - lat1) * 111320
          dlon <- (lon2 - lon1) * 111320 * cos(mean(c(lat1, lat2)) * pi / 180)
          sqrt(dlat^2 + dlon^2)
        }, error = function(e) NA_real_)

        existing_alias <- dbGetQuery(con, "SELECT alias FROM Location_Aliases WHERE location_id = ? AND alias = 'NV26-1'",
                                      params = list(location_id))
        if (nrow(existing_alias) == 0) {
          dbExecute(con, "
            INSERT INTO Location_Aliases (location_id, alias, alias_type, source, notes)
            VALUES (?, 'NV26-1', 'other', 'Fischer/Ruprecht UCSB gas sampling, April 2026', ?)
          ", params = list(
            location_id,
            sprintf("Gas sample NV26-1's own field GPS fix (%.6f, %.6f) is ~%.0f m from SBF_0001's on-file coordinate (a road-edge fix) -- treated as the same real fissure/fumarole point per 2026-10-16 user decision, not independently re-surveyed to resolve the gap.",
                    r$latitude[1], r$longitude[1], dist_m)
          ))
          n_aliases_created <- n_aliases_created + 1L
        }
      }
    } else {
      existing_loc <- dbGetQuery(con, "SELECT location_id FROM Locations WHERE external_station_code = ?",
                                  params = list(r$sample_label))
      if (nrow(existing_loc) > 0) {
        location_id <- existing_loc$location_id[1]
      } else {
        dbExecute(con, "
          INSERT INTO Locations (external_station_code, name, latitude, longitude, elevation_m, crs, site_type, coordinate_source, notes)
          VALUES (?, ?, ?, ?, ?, 'EPSG:4326', 'fumarole', 'field_gps', ?)
        ", params = list(
          r$sample_label, paste0("Fissure gas sample point ", r$sample_label),
          r$latitude[1], r$longitude[1], r$elev_m[1],
          paste0("Registered from the April 2026 Fischer/Ruprecht UCSB gas sampling campaign. ", r$notes[1])
        ))
        location_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
        n_locations_created <- n_locations_created + 1L
      }
    }

    dbExecute(con, "
      INSERT INTO Gas_Analyses (
        sample_label, location_id, collection_date, field_temp_c,
        co2_mol_pct, he_mol_pct, h2_mol_pct, ar_mol_pct, o2_mol_pct,
        n2_mol_pct, ch4_mol_pct, co_mol_pct, h2s_mol_pct, total_mol_pct,
        d13c_permil, d13c_error_permil,
        he3_he4_r_ra, he4_ne20, ne20_ne22, ne21_ne22, ar40_ar36, x_value, rc_ra,
        data_quality_flag, notes
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      r$sample_label, location_id, r$collection_date, r$field_temp_c,
      r$CO2, r$He, r$H2, r$Ar, r$O2, r$N2, r$CH4, r$CO, r$H2S, r$Total,
      r$d13C, r$d13C_err,
      r$R_Ra, r$He4_Ne20, r$Ne20_Ne22, r$Ne21_Ne22, r$Ar40_Ar36, r$x_value, r$rc_Ra,
      r$data_quality_flag, r$notes
    ))
    n_inserted <- n_inserted + 1L
  }

  message("[fischer_gas] Inserted ", n_inserted, " new Gas_Analyses row(s) (",
          n_skipped, " already present), ", n_locations_created, " new Location(s), ",
          n_aliases_created, " new Location_Aliases row(s).")
  invisible(list(inserted = n_inserted, skipped = n_skipped,
                 locations_created = n_locations_created, aliases_created = n_aliases_created))
}
