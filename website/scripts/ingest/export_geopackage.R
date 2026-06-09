# ============================================================
# export_geopackage.R
#
# Purpose:
# Export database views and tables to a single GeoPackage
# for GIS (ArcGIS) and external use.
#
# Design:
# - One GeoPackage per run
# - Multiple layers (raw + derived)
# - Loop-based export for scalability
#
# Key Concepts:
# - RAW layers: full time series / original data
# - ANALYSIS layers: filtered, interpreted, map-ready
#
# ============================================================
# export_geopackage.R (REFACTORED WITH GRADIENT FILTERING)
# ============================================================
library(sf)
library(DBI)
library(dplyr)

export_geopackage <- function(con, mode = "OPERATIONAL") {
  
  message("\n---- Exporting GeoPackage ----")
  
  out_dir <- "output/geopackage"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  
  gpkg_path <- file.path(out_dir, "hydro_data.gpkg")
  
  if (mode == "DEMO" && file.exists(gpkg_path)) {
    file.remove(gpkg_path)
    message("[EXPORT] DEMO reset → removed existing GeoPackage")
  }
  
  # ============================================================
  # SAFE WRITER (POINT DATA)
  # ============================================================
  
  safe_write_layer <- function(df, layer_name) {
    
    if (nrow(df) == 0) {
      message("[EXPORT] Skipping ", layer_name, " (no rows)")
      return()
    }
    
    if (!"geom_wkt" %in% names(df)) {
      warning("[EXPORT] Skipping ", layer_name, " (no geom_wkt)")
      return()
    }
    
    sf_obj <- st_as_sf(df, wkt = "geom_wkt", crs = 4326)
    
    st_write(
      sf_obj,
      gpkg_path,
      layer = layer_name,
      delete_layer = TRUE,
      quiet = TRUE
    )
    
    message("[EXPORT] ✅ ", layer_name, " (", nrow(sf_obj), " rows)")
  }
  
  # ============================================================
  # STANDARD LAYERS
  # ============================================================
  
  layers <- list(
    locations = "SELECT * FROM vw_locations_gis",
    wells = "SELECT * FROM vw_wells_gis",
    
    hydraulic_head_clean = "SELECT * FROM vw_hydraulic_head_clean",
    water_level_latest = "SELECT * FROM vw_water_level_latest",
    
    temperature_timeseries = "SELECT * FROM vw_temperature_timeseries",
    
    sample_locations = "SELECT * FROM vw_samples_locations",
    samples = "SELECT * FROM vw_samples_gis",
    major_ions = "SELECT * FROM vw_major_ions",
    temp_gradient = "SELECT * FROM vw_temp_gradient",
    isotopes = "SELECT * FROM vw_isotopes_gis",
    isotope_pairs = "SELECT * FROM vw_isotope_pairs",
    gradient_vectors = "SELECT * FROM Gradient_Vectors_Scaled",
    
    flux = "SELECT * FROM vw_flux_summary",
    flux_vs_usgs = "SELECT * FROM vw_flux_vs_usgs",
    sample_flux = "SELECT * FROM vw_sample_hydrochem_flux",
    
    temp_flow = "SELECT * FROM temp_flow_combined",
    samples_flow = "SELECT * FROM usgs_samples_aligned"
  )
  
  # ============================================================
  # EXPORT STANDARD LAYERS
  # ============================================================
  
  for (layer_name in names(layers)) {
    
    message("\n[EXPORT] Processing: ", layer_name)
    
    tryCatch({
      df <- dbGetQuery(con, layers[[layer_name]])
      safe_write_layer(df, layer_name)
    }, error = function(e) {
      warning("[EXPORT] Failed: ", layer_name, " → ", e$message)
    })
  }
  
  # ============================================================
  # HYDRAULIC GRADIENTS
  # ============================================================
  
  message("\n[EXPORT] Processing: hydraulic_gradients")
  
  grad_df <- dbGetQuery(con, "SELECT * FROM Hydraulic_Gradients")
  
  if (nrow(grad_df) == 0) {
    message("[EXPORT] No gradient features to write")
    message("\n✅ GeoPackage export complete: ", gpkg_path)
    return()
  }
  
  message("  → Original gradients: ", nrow(grad_df))
  
  # -------------------------------
  # FILTER
  # -------------------------------
  
  grad_df <- grad_df %>%
    filter(distance_m <= 1500, abs(gradient) >= 0.001)
  
  message("  → After filtering: ", nrow(grad_df))
  
  # -------------------------------
  # CAP SIZE
  # -------------------------------
  
  max_export <- 500000
  
  if (nrow(grad_df) > max_export) {
    set.seed(42)
    grad_df <- grad_df %>% slice_sample(n = max_export)
    message("  → After cap (", max_export, "): ", nrow(grad_df))
  }
  
  # ============================================================
  # ✅ FIX GEOMETRY (EWKB → WKB → SF)
  # ============================================================
  
  # ============================================================
  # ✅ REBUILD GRADIENT GEOMETRY FROM WELL LOCATIONS
  # ============================================================
  
  # get well coordinates
  wells <- dbGetQuery(con, "
SELECT well_id, latitude, longitude
FROM Wells
")
  
  # attach coords
  grad_df <- grad_df %>%
    left_join(wells, by = c("well_id_1" = "well_id")) %>%
    rename(lat1 = latitude, lon1 = longitude) %>%
    left_join(wells, by = c("well_id_2" = "well_id")) %>%
    rename(lat2 = latitude, lon2 = longitude)
  
  grad_df <- grad_df %>%
    filter(
      !is.na(lat1), !is.na(lon1),
      !is.na(lat2), !is.na(lon2)
    )
  
  # convert to sf points
  pts1 <- st_as_sf(grad_df, coords = c("lon1", "lat1"), crs = 4326)
  pts2 <- st_as_sf(grad_df, coords = c("lon2", "lat2"), crs = 4326)
  
  # project to meters
  pts1 <- st_transform(pts1, 32611)
  pts2 <- st_transform(pts2, 32611)
  
  coords1 <- st_coordinates(pts1)
  coords2 <- st_coordinates(pts2)
  
  # build lines
  geom_list <- lapply(seq_len(nrow(grad_df)), function(i) {
    st_linestring(rbind(
      coords1[i, ],
      coords2[i, ]
    ))
  })
  
  grad_sf <- st_as_sf(
    grad_df,
    geometry = st_sfc(geom_list, crs = 32611)
  )
  # ============================================================
  # OPTIONAL: EXTRACT COORDINATES
  # ============================================================
  
  coords <- st_coordinates(grad_sf)
  
  if (nrow(coords) > 0) {
    coords_df <- as.data.frame(coords)
    
    start_pts <- coords_df[coords_df$L2 == 1, ]
    end_pts   <- coords_df[coords_df$L2 == 2, ]
    
    if (nrow(start_pts) == nrow(grad_sf)) {
      grad_sf$x_1 <- start_pts$X
      grad_sf$y_1 <- start_pts$Y
      grad_sf$x2  <- end_pts$X
      grad_sf$y2  <- end_pts$Y
    }
  }
  
  # ============================================================
  # WRITE
  # ============================================================
  
  st_write(
    grad_sf,
    gpkg_path,
    layer = "hydraulic_gradients",
    delete_layer = TRUE,
    quiet = TRUE
  )
  
  message("[EXPORT] ✅ hydraulic_gradients (", nrow(grad_sf), " rows)")
  
  message("\n✅ GeoPackage export complete: ", gpkg_path)
}