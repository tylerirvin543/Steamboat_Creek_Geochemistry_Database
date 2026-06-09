build_temp_gradient_links <- function(con) {
  
  message("[TEMP+FLOW] Linking temperature and gradients")
  
  temp <- dbGetQuery(con, "
    SELECT location_id, temperature, timestamp
    FROM vw_temperature_timeseries
  ")
  
  wells <- dbGetQuery(con, "
    SELECT well_id, location_id
    FROM Wells
  ")
  
  grad <- dbGetQuery(con, "
    SELECT 
      well_id_1,
      gradient,
      direction_deg,
      datetime(timestamp) AS timestamp
    FROM Hydraulic_Gradients
  ")
  
  
  locations <- dbGetQuery(con, "
  SELECT location_id, latitude, longitude
  FROM Locations
")
  
  
  # attach location
  grad <- grad %>%
    left_join(wells, by = c("well_id_1" = "well_id"))
  
  # ✅ restrict to overlapping time window
  temp_range <- range(temp$timestamp, na.rm = TRUE)
  
  grad <- grad %>%
    filter(
      timestamp >= temp_range[1],
      timestamp <= temp_range[2]
    )
  
  message("  → Gradients after time filter: ", nrow(grad))
  
  # align
  df <- align_timeseries(
    left_df = grad,
    right_df = temp,
    left_time = "timestamp",
    right_time = "timestamp",
    group_col = NULL,  # ✅ REMOVE GROUPING
    max_diff_minutes = 60
  )
  
  # join locations and geometry
  df <- df %>%
    left_join(locations, by = "location_id") %>%
    mutate(geom_wkt = paste0("POINT(", longitude, " ", latitude, ")"))
  
  
  
  # ✅ enforce valid matches
  df <- df %>%
    filter(!is.na(temperature))
  
  dbWriteTable(con, "temp_gradient", df, overwrite = TRUE)
  
  message("✅ temp_gradient ready (", nrow(df), " rows)")
}
