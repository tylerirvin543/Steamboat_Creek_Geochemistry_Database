# ============================================================
# ingest_fault_traces.R
#
# ingest_fault_traces(con, shapefile_dir = "data/raw/arcgis/faults")
#
# Reads user-digitized fault/lineament shapefiles into Fault_Traces
# (database/schema/11_fault_traces_schema.R, structure-only until this
# script gives it real data). Mirrors register_facility_areas.R's
# pattern exactly (sf::st_read() + reproject to EPSG:4326, since the
# payload is genuinely spatial line geometry, not tabular), just for
# LINESTRING/MULTILINESTRING instead of polygons.
#
# This is the receiving end of the "ArcGIS out, ArcGIS back in" loop
# scoped in README.md's Leapfrog section (2026-09-12) and reiterated
# in Session 31's notes: this project's own well/location coordinates
# were already exported (GeoPackage) to serve as digitizing control
# points; the user overlays a real fault map (Collar & Huntley 1990
# Figure 1 is the current best candidate, per notebooks/07's Section
# 4.6 -- a real fault-and-lineament map with 10 already-coordinated
# wells visible on it) on satellite imagery in ArcGIS and traces the
# faults/lineaments as a new line shapefile; this script reads that
# shapefile back in.
#
# Expected shapefile attributes (case-insensitive, best-effort match;
# missing attributes fall back to sensible defaults rather than
# erroring, since the exact attribute schema depends on how the user
# sets up their ArcGIS digitizing layer):
#   - a name/label field (e.g. "Name", "fault_name", "Label") -> fault_name
#   - a type field (e.g. "Type", "fault_type") matching this project's
#     Fault_Traces.fault_type CHECK constraint values
#     ('mapped_fault_inferred', 'mapped_fault_concealed',
#     'air_photo_lineament') -- unmatched/missing values fall back to
#     'unknown', never guessed from geometry alone.
#   - `source` defaults to the shapefile's own filename if no source
#     column exists; ALWAYS pass `source_citation` explicitly (e.g.
#     "Collar & Huntley 1990, Figure 1") when calling this function --
#     the shapefile itself usually can't self-describe which published
#     figure it was traced from.
#
# Idempotency: matched on `fault_name` (kept unique per source in
# practice by the caller's naming, e.g. "CollarHuntley1990_F1") --
# an existing row is left untouched, never overwritten. If you
# re-digitize a fault and want the new trace to replace the old one,
# delete the old Fault_Traces row yourself first; this script will not
# do it for you.
# ============================================================

library(DBI)
library(sf)

.find_fault_shapefiles <- function(shapefile_dir) {
  list.files(shapefile_dir, pattern = "\\.shp$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
}

.match_col <- function(names_lower, candidates) {
  hit <- candidates[candidates %in% names_lower]
  if (length(hit) == 0) return(NA_character_)
  hit[1]
}

ingest_fault_traces <- function(con, shapefile_dir = "data/raw/arcgis/faults",
                                 source_citation = NULL,
                                 default_uncertainty_m = 200) {
  message("---- Registering digitized fault traces ----")

  if (!dir.exists(shapefile_dir)) {
    message("[fault_traces] No directory at ", shapefile_dir, " -- nothing to register yet.",
            " (Expected once fault lineaments are digitized in ArcGIS -- see script header.)")
    return(invisible(NULL))
  }

  shps <- .find_fault_shapefiles(shapefile_dir)
  if (length(shps) == 0) {
    message("[fault_traces] No .shp files found under ", shapefile_dir, " -- nothing to register yet.")
    return(invisible(NULL))
  }

  existing <- tryCatch(dbGetQuery(con, "SELECT fault_name FROM Fault_Traces")$fault_name,
                        error = function(e) character(0))
  n_inserted <- 0L

  for (shp in shps) {
    fl <- sf::st_read(shp, quiet = TRUE)
    fl <- sf::st_transform(fl, 4326)
    names_lower <- tolower(names(fl))

    name_col <- .match_col(names_lower, c("name", "fault_name", "label"))
    type_col <- .match_col(names_lower, c("type", "fault_type"))
    src_col <- .match_col(names_lower, c("source", "src"))
    unc_col <- .match_col(names_lower, c("uncertainty", "digitizing_uncertainty_m", "accuracy_m"))

    valid_types <- c("mapped_fault_inferred", "mapped_fault_concealed", "air_photo_lineament", "unknown")

    for (i in seq_len(nrow(fl))) {
      row <- fl[i, ]
      fault_name <- if (!is.na(name_col)) as.character(row[[names(fl)[names_lower == name_col][1]]]) else NA
      if (is.na(fault_name) || fault_name == "") {
        fault_name <- paste0(tools::file_path_sans_ext(basename(shp)), "_", i)
      }
      if (fault_name %in% existing) {
        message("[fault_traces] '", fault_name, "' already registered -- skipping (delete the row first to re-digitize).")
        next
      }

      fault_type <- if (!is.na(type_col)) tolower(as.character(row[[names(fl)[names_lower == type_col][1]]])) else "unknown"
      if (!fault_type %in% valid_types) fault_type <- "unknown"

      source_val <- if (!is.null(source_citation)) source_citation else if (!is.na(src_col)) as.character(row[[names(fl)[names_lower == src_col][1]]]) else basename(shp)
      uncertainty_val <- if (!is.na(unc_col)) suppressWarnings(as.numeric(row[[names(fl)[names_lower == unc_col][1]]])) else default_uncertainty_m
      if (is.na(uncertainty_val)) uncertainty_val <- default_uncertainty_m

      wkt <- sf::st_as_text(sf::st_geometry(row)[[1]])

      dbExecute(con, "
        INSERT INTO Fault_Traces (fault_name, fault_type, geom_wkt, crs, digitizing_uncertainty_m, source, notes)
        VALUES (?, ?, ?, 'EPSG:4326', ?, ?, ?)
      ", params = list(fault_name, fault_type, wkt, uncertainty_val, source_val,
                        paste0("Digitized in ArcGIS, imported from ", basename(shp))))
      n_inserted <- n_inserted + 1L
      existing <- c(existing, fault_name)
    }
  }

  message("[fault_traces] Registered ", n_inserted, " new fault trace(s) from ", length(shps), " shapefile(s).")
  invisible(n_inserted)
}
