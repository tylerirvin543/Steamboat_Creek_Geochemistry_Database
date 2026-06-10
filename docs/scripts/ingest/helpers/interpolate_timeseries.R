build_interpolated_flow <- function(con) {
  
  message("\n[INTERP] Building interpolated flow time grid")
  
  df <- dbReadTable(con, "temp_flow_combined")
  
  interp <- interpolate_timeseries(
    df,
    time_col = "time",
    value_col = "discharge_m3_s",
    interval = "hour"
  )
  
  dbWriteTable(con, "temp_flow_hourly", interp, overwrite = TRUE)
  
  message("✅ interpolation complete (", nrow(interp), " rows)")
}