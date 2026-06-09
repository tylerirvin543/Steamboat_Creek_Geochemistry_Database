build_temp_flow <- function(con) {
  
  message("\n[ALIGN] Temperature ↔ USGS")
  
  library(data.table)
  
  # -----------------------------------------
  # 1. LOAD
  # -----------------------------------------
  temp <- as.data.table(get_temp_data(con))
  usgs <- as.data.table(get_usgs_data(con))
  
  # -----------------------------------------
  # 2. SPATIAL MAPPING
  # -----------------------------------------
  mapping <- assign_nearest_station(temp, usgs)
  
  temp <- merge(
    temp[, !("station_id"), with = FALSE],  # ✅ remove safely if exists
    mapping,
    by = "logger_id",
    all.x = TRUE
  )
  
  message("  → Loggers with station mapping: ",
          sum(!is.na(temp$station_id)), "/", nrow(temp))
  
  # -----------------------------------------
  # 3. ALIGNMENT
  # -----------------------------------------
  aligned <- align_timeseries(
    left_df  = temp,
    right_df = usgs,
    left_time  = "time",
    right_time = "datetime",
    group_col = "station_id",
    max_diff_minutes = 60
  )
  
  if (nrow(aligned) == 0) {
    warning("No aligned rows produced")
    return(invisible(NULL))
  }
  
  # -----------------------------------------
  # 4. NORMALIZE SCHEMA (CRITICAL)
  # -----------------------------------------
  
  # ✅ rename explicitly
  setnames(aligned, "left_time",  "logger_time")
  setnames(aligned, "right_time", "usgs_time")
  
  # ✅ enforce required columns only
  cols_keep <- c(
    "logger_id",
    "station_id",
    "logger_time",
    "usgs_time",
    "temperature",
    "discharge_m3_s",
    "latitude",
    "longitude"
  )
  
  cols_present <- intersect(cols_keep, names(aligned))
  aligned <- aligned[, ..cols_present]
  
  # -----------------------------------------
  # 5. GEOMETRY (SAFE)
  # -----------------------------------------
  if (all(c("longitude", "latitude") %in% names(aligned))) {
    aligned[, geom_wkt := paste0("POINT(", longitude, " ", latitude, ")")]
  } else {
    warning("Missing coordinates → geometry not created")
  }
  
  # -----------------------------------------
  # 6. WRITE (STABLE NAME)
  # -----------------------------------------
  message("  → Writing to database...")
  
  dbWriteTable(
    con,
    "temp_flow",   # ✅ canonical name
    aligned,
    overwrite = TRUE
  )
  
  dbExecute(con, "
    CREATE INDEX IF NOT EXISTS idx_temp_flow_time
    ON temp_flow(logger_time)
  ")
  
  message("✅ temp_flow ready (", nrow(aligned), " rows)")
}