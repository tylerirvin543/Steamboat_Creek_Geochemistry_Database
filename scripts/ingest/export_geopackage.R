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
    
    if (!"geom_wkt" %in% names(df) &&
        all(c("latitude", "longitude") %in% names(df))) {
      
      sf_obj <- st_as_sf(df, coords = c("longitude", "latitude"), crs = 4326)
      
    } else if ("geom_wkt" %in% names(df)) {
      
      sf_obj <- st_as_sf(df, wkt = "geom_wkt", crs = 4326)
      
    } else {
      warning("[EXPORT] Skipping ", layer_name, " (no geometry)")
      return()
    }
    
    if (!"location_id" %in% names(df)) {
      message("[EXPORT] ℹ ", layer_name, " has no location_id (non-location layer)")
    }
    
    
    if (any(!sf::st_is_valid(sf_obj))) {
      warning("[EXPORT] ", layer_name, " contains invalid geometry")
    }
    
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
    
    # -------------------------
    # CORE SPATIAL FRAMEWORK
    # -------------------------
    locations = "SELECT * FROM vw_locations_gis",
    wells = "SELECT * FROM vw_wells_gis",
    
    # -------------------------
    # HYDROLOGIC ANALYSIS
    # -------------------------
    hydraulic_head = "SELECT * FROM vw_hydraulic_head_clean",
    water_level_latest = "SELECT * FROM vw_water_level_latest",
    
    # -------------------------
    # THERMAL SYSTEM
    # -------------------------
    temperature_timeseries = "SELECT * FROM vw_temperature_timeseries",
    
    # -------------------------
    # GEOCHEMISTRY (CURATED)
    # -------------------------
    major_ions = "SELECT * FROM vw_major_ions",
    isotopes = "SELECT * FROM vw_isotopes_gis",
    
    # -------------------------
    # INTEGRATED PRODUCTS
    # -------------------------
    sample_flow = "SELECT * FROM vw_sample_hydrochem_flux",
    temp_flow = "SELECT * FROM temp_flow"
  )
  
  # ============================================================
  # EXPORT STANDARD LAYERS
  # ============================================================
  
  requires_table <- list(sample_flow = "sample_flux", temp_flow = "temp_flow")

  for (layer_name in names(layers)) {
    
    message("\n[EXPORT] Processing: ", layer_name)
    
    needed_table <- requires_table[[layer_name]]
    if (!is.null(needed_table) && !dbExistsTable(con, needed_table)) { message("[EXPORT] Skipping ", layer_name, " (underlying table missing)"); next }
    tryCatch({
      df <- dbGetQuery(con, layers[[layer_name]])
      safe_write_layer(df, layer_name)
    }, error = function(e) {
      warning("[EXPORT] Failed: ", layer_name, " → ", e$message)
    })
  }
  
  # ============================================================
  # QC LAYER
  # ============================================================
  
  message("\n[EXPORT] Processing: qc_issues")
  
  tryCatch({
    
    qc_df <- dbGetQuery(con, "
    SELECT q.*, l.latitude, l.longitude
    FROM QC_Issues q
    LEFT JOIN Locations l
      ON q.location_id = l.location_id
    WHERE l.latitude IS NOT NULL

  ")
    
    if (nrow(qc_df) > 0) {
      
      qc_sf <- st_as_sf(
        qc_df,
        coords = c("longitude", "latitude"),
        crs = 4326
      )
      
      st_write(
        qc_sf,
        gpkg_path,
        layer = "qc_issues",
        delete_layer = TRUE,
        quiet = TRUE
      )
      
      message("[EXPORT] ✅ qc_issues (", nrow(qc_sf), " rows)")
      
    } else {
      message("[EXPORT] No QC spatial issues to export")
    }
    
  }, error = function(e) {
    warning("[EXPORT] QC export failed → ", e$message)
  })
  
  # ============================================================
  # HYDRAULIC GRADIENTS
  # ============================================================
  
  message("\n[EXPORT] Processing: hydraulic_gradients")
  
  if (!("Hydraulic_Gradients" %in% dbListTables(con))) {
    message("[EXPORT] Hydraulic_Gradients table does not exist yet (run the gradient-calculation stage of run_pipeline.R first) -- skipping.")
    message("\n✅ GeoPackage export complete: ", gpkg_path)
    return()
  }

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
    filter(distance_m <= 1500, abs(gradient) >= 0.0001)
  
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
  
  grad_sf <- st_transform(grad_sf, 4326)
  
  grad_sf <- grad_sf %>%
    mutate(
      gradient_class = case_when(
        abs(gradient) < 0.001 ~ "low",
        abs(gradient) < 0.01  ~ "moderate",
        TRUE ~ "high"
      )
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
  
  message("\n[EXPORT SUMMARY]")
  message("GeoPackage path: ", gpkg_path)
  
  layer_count <- length(layers) + 1  # gradients
  
  if (exists("qc_sf") && nrow(qc_sf) > 0) {
    layer_count <- layer_count + 1
  }
  
  message("Layers exported: ", layer_count)
  
  message("[EXPORT] ✅ hydraulic_gradients (", nrow(grad_sf), " rows)")
  
  message("\n✅ GeoPackage export complete: ", gpkg_path)
}