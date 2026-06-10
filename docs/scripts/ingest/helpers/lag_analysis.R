build_lag_analysis <- function(con) {
  
  message("\n[ANALYSIS] Running lag correlation")
  
  df <- dbReadTable(con, "temp_flow_combined")
  
  lag_df <- lag_analysis(df)
  
  dbWriteTable(con, "temp_flow_lag_analysis", lag_df, overwrite = TRUE)
  
  message("✅ lag analysis complete")
}
