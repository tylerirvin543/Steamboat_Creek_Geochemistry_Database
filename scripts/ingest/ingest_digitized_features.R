# ------------------------------------------------------------
# ingest_digitized_features.R
#
# Reads data/raw/arcgis/features/Steamboat_digitized_features.gpkg (layers copied from
# the ArcGIS project geodatabase) into Fissure_Traces and Mapped_Polygons.
#   fissures_closed         -> Fissure_Traces   (53 lines)
#   sinter_mounds           -> Mapped_Polygons  feature_type 'sinter_mound'
#   sinter_ridges           -> Mapped_Polygons  feature_type 'sinter_ridge'
#   sinter_terrace_outline  -> Mapped_Polygons  feature_type 'sinter_terrace_outline'
#   study_area              -> Mapped_Polygons  feature_type 'study_area'
# Idempotent. Each source layer is authoritative: a feature's key is the layer name plus a
# hash of its geometry, and if the set of keys for a layer differs from the database the
# layer's rows are deleted and reloaded. So moving or redrawing a feature in ArcGIS and
# re-copying the layer updates the database instead of adding a duplicate.
# Uncertainty is set to 25 m for hand-digitized outlines over imagery (edit if needed).
# ------------------------------------------------------------
suppressPackageStartupMessages({library(DBI); library(sf)})

ingest_digitized_features <- function(con, gpkg = "data/raw/arcgis/features/Steamboat_digitized_features.gpkg", uncertainty_m = 25) {
  message("---- Ingesting digitized fissures and polygons ----")
  if (!file.exists(gpkg)) { message("  no file at ", gpkg); return(invisible(NULL)) }
  src <- "Digitized in ArcGIS (Steamboat.gdb graphics layers)"
  key_of <- function(layer, x) paste0(layer, "|", vapply(st_as_text(st_geometry(x), digits = 8), function(s) substr(digest::digest(s, algo = "md5"), 1, 12), ""))
  load_layer <- function(layer, table, build) {
    x <- st_read(gpkg, layer = layer, quiet = TRUE); x <- x[!st_is_empty(x), ]
    # ArcGIS can store curved polygons (MULTISURFACE); read those through terra, which linearizes them
    if (inherits(st_geometry(x), c("sfc_MULTISURFACE", "sfc_CURVEPOLYGON", "sfc_COMPOUNDCURVE", "sfc_MULTICURVE"))) x <- st_set_crs(st_as_sf(terra::vect(gpkg, layer = layer)), 4326)
    x <- x[!st_is_empty(x), ]
    x <- st_zm(st_transform(x, 4326))
    x$feature_key <- key_of(layer, x)
    have <- dbGetQuery(con, sprintf("SELECT feature_key FROM %s WHERE source_layer IN (%s)", table, paste0("'", unique(x$source_layer), "'", collapse = ",")))$feature_key
    if (setequal(have, x$feature_key)) { message("  ", layer, ": ", nrow(x), " feature(s) unchanged"); return(invisible(0L)) }
    dbExecute(con, sprintf("DELETE FROM %s WHERE source_layer IN (%s)", table, paste0("'", unique(x$source_layer), "'", collapse = ",")))
    build(x); message("  ", layer, ": loaded ", nrow(x), " feature(s)", if (length(have)) " (replaced the previous version)" else "")
    invisible(nrow(x))
  }
  # fissures
  load_layer("fissures_closed", "Fissure_Traces", function(x) {
    len <- as.numeric(st_length(st_transform(x, 26911)))
    for (i in seq_len(nrow(x)))
      dbExecute(con, "INSERT INTO Fissure_Traces (fissure_name, orig_name, status_label, geom_wkt, length_m, digitizing_uncertainty_m, source_layer, feature_key, source, notes) VALUES (?,?,?,?,?,?,?,?,?,?)",
                params = list(sprintf("Fissure %02d", i), x$orig_name[i], "closed (from the layer name 'ClosedFissure...'; meaning to be confirmed)",
                              st_as_text(st_geometry(x)[[i]], digits = 8), round(len[i], 1), uncertainty_m, x$source_layer[i], x$feature_key[i], src,
                              "Name 'Line n' is the ArcGIS graphics default, not a feature name."))
  })
  poly <- function(layer, ftype, prefix) load_layer(layer, "Mapped_Polygons", function(x) {
    ar <- as.numeric(st_area(st_transform(x, 26911)))
    for (i in seq_len(nrow(x)))
      dbExecute(con, "INSERT INTO Mapped_Polygons (feature_type, polygon_name, orig_name, geom_wkt, area_m2, digitizing_uncertainty_m, source_layer, feature_key, source, notes) VALUES (?,?,?,?,?,?,?,?,?,?)",
                params = list(ftype, if (nrow(x) > 1) sprintf("%s %02d", prefix, i) else prefix, x$orig_name[i], st_as_text(st_geometry(x)[[i]], digits = 8), round(ar[i], 1),
                              uncertainty_m, x$source_layer[i], x$feature_key[i], src, NA_character_))
  })
  poly("sinter_mounds", "sinter_mound", "Sinter mound")
  poly("sinter_ridges", "sinter_ridge", "Sinter ridge")
  poly("sinter_terrace_outline", "sinter_terrace_outline", "Sinter terrace outline")
  poly("study_area", "study_area", "Study area rectangle")
  invisible(TRUE)
}
