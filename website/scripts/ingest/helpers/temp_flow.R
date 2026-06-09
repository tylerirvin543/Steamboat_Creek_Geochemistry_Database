build_temp_flow <- function(con) {
  
  message("\n[ALIGN] Temperature ↔ USGS")
  
  library(data.table)
  
  temp <- as.data.table(get_temp_data(con))
  usgs <- as.data.table(get_usgs_data(con))
  
  # -----------------------------------------
  # ✅ STEP 3: build spatial mapping
  # -----------------------------------------
  mapping <- assign_nearest_station(temp, usgs)
  
  if ("station_id" %in% names(temp)) {
    temp[, station_id := NULL]
  }
  
  # -----------------------------------------
  # ✅ STEP 4: attach mapping to temp
  # -----------------------------------------
  temp <- merge(temp, mapping, by = "logger_id", all.x = TRUE)
  
  # -----------------------------------------
  # 🔍 OPTIONAL sanity check
  # -----------------------------------------
  message("  → Loggers with station mapping: ",
          sum(!is.na(temp$station_id)), "/", nrow(temp))
  
  # -----------------------------------------
  # ✅ STEP 5: alignment
  # -----------------------------------------
  message("  → mapped station_id count:")
  print(table(is.na(temp$station_id)))
  
  aligned <- align_timeseries(
    left_df  = temp,
    right_df = usgs,
    left_time  = "time",
    right_time = "datetime",
    group_col = "station_id",
    max_diff_minutes = 60
  )
  
  # -----------------------------------------
  # ✅ post-processing
  # -----------------------------------------
  if (nrow(aligned) == 0) {
    warning("No aligned rows produced")
  }
  
  # ✅ rename columns to avoid duplicates (THIS IS WHERE IT GOES)
  setnames(aligned, "left_time",  "logger_time")
  setnames(aligned, "right_time", "usgs_time")
  
  # ✅ remove original time column if it exists
  if ("time" %in% names(aligned)) {
    aligned[, time := NULL]
  }
  
  # ✅ geometry
  aligned[, geom_wkt := paste0("POINT(", longitude, " ", latitude, ")")]
  
  message("  → Writing to database...")
  
  dbWriteTable(con, "temp_flow_combined", aligned, overwrite = TRUE)
  
  dbExecute(con, "
  CREATE INDEX IF NOT EXISTS idx_temp_flow_time
  ON temp_flow_combined(logger_time)
")
  
  message("✅ temp_flow ready (", nrow(aligned), " rows)")
}