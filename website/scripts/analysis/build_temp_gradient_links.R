build_temp_gradient_links <- function(con) {
  
  message("[TEMP+FLOW] Linking temperature and gradients")
  
  temp <- dbGetQuery(con, "
    SELECT location_id, temperature, timestamp
    FROM temperature_timeseries
  ")
  
  wells <- dbGetQuery(con, "
    SELECT well_id, location_id
    FROM Wells
  ")
  
  grad <- dbGetQuery(con, "
    SELECT well_id_1, gradient, direction_deg, timestamp
    FROM Hydraulic_Gradients
  ")
  
  df <- grad %>%
    left_join(wells, by = c("well_id_1" = "well_id")) %>%
    left_join(temp, by = c("location_id", "timestamp"))
  
  df <- df %>%
    filter(!is.na(temperature))
  
  dbWriteTable(con, "Temperature_Gradient_Link", df, overwrite = TRUE)
}