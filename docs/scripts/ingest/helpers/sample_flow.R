build_sample_flow <- function(con) {
  
  message("\n[ALIGN] Samples ↔ USGS")
  
  library(data.table)
  
  samples <- as.data.table(get_sample_data(con))
  usgs    <- as.data.table(get_usgs_data(con))
  
  # -----------------------------------------
  # ✅ SPATIAL MAPPING (reuse temp logic)
  # -----------------------------------------
  
  # temporarily rename for compatibility
  samples_tmp <- copy(samples)
  samples_tmp[, logger_id := sample_id]
  
  mapping <- assign_nearest_station(samples_tmp, usgs)
  
  # rename back to sample_id
  setnames(mapping, "logger_id", "sample_id")
  
  # merge mapping
  samples <- merge(samples, mapping, by = "sample_id", all.x = TRUE)
  
  message("  → Samples with station mapping: ",
          sum(!is.na(samples$station_id)), "/", nrow(samples))
  
  # -----------------------------------------
  # ✅ ALIGNMENT
  # -----------------------------------------
  
  message("  → Aligning timeseries...")
  
  aligned <- align_timeseries(
    left_df  = samples,
    right_df = usgs,
    left_time  = "sample_time",
    right_time = "datetime",
    group_col = "station_id",
    max_diff_minutes = 30
  )
  
  if (nrow(aligned) == 0) {
    warning("No sample-flow matches produced")
  }
  
  # -----------------------------------------
  # ✅ post-processing (FIXED VERSION)
  # -----------------------------------------
  
  # ✅ rename aligned times
  setnames(aligned, "left_time",  "sample_time_aligned")
  setnames(aligned, "right_time", "usgs_time")
  
  # ✅ remove original sample_time to avoid duplication
  if ("sample_time" %in% names(aligned)) {
    aligned[, sample_time := NULL]
  }
  
  # ✅ rename aligned one to canonical name
  setnames(aligned, "sample_time_aligned", "sample_time")
  
  # ✅ geometry
  aligned[, geom_wkt := paste0("POINT(", longitude, " ", latitude, ")")]

  message("  → Writing to database...")
  
  dbWriteTable(con, "usgs_samples_aligned", aligned, overwrite = TRUE)
  
  dbExecute(con, "
    CREATE INDEX IF NOT EXISTS idx_sample_flow_sample
    ON usgs_samples_aligned(sample_id)
  ")
  
  message("✅ sample_flow ready (", nrow(aligned), " rows)")
}