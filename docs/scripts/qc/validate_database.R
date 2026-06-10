library(DBI)
library(dplyr)

validate_database <- function(con) {
  
  message("---- Running database validation ----")
  
  if (missing(con)) {
    stop("Database connection `con` not provided.")
  }
  
  # -------------------------------------------------
  # CREATE VALIDATION LOG TABLE
  # -------------------------------------------------
  dbExecute(con, "
  CREATE TABLE IF NOT EXISTS Validation_Log (
    validation_id INTEGER PRIMARY KEY,
    run_time TEXT,
    check_name TEXT,
    status TEXT,
    value INTEGER,
    message TEXT
  )
  ")
  
  run_time <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  
  log_check <- function(name, status, value = NA, message = "") {
    dbExecute(con, "
      INSERT INTO Validation_Log (run_time, check_name, status, value, message)
      VALUES (?, ?, ?, ?, ?)
    ", params = list(run_time, name, status, value, message))
  }
  
  # -------------------------------------------------
  # REQUIRED TABLES
  # -------------------------------------------------
  required_tables <- c(
    "temp_flow_combined",
    "usgs_samples_aligned",
    "sample_flux"
  )
  
  for (t in required_tables) {
    if (!dbExistsTable(con, t)) {
      warning(paste("Missing required analysis table:", t))
      log_check(paste("missing_table:", t), "WARN", NA, "Table missing")
    } else {
      log_check(paste("missing_table:", t), "OK")
    }
  }
  
  # -------------------------------------------------
  # TEMP FLOW VALIDATION
  # -------------------------------------------------
  if (dbExistsTable(con, "temp_flow_combined")) {
    
    flow_rows <- dbGetQuery(con,
                            "SELECT COUNT(*) n FROM temp_flow_combined")$n
    
    if (flow_rows == 0) {
      warning("temp_flow_combined is empty")
      log_check("temp_flow_rows", "WARN", flow_rows, "Empty table")
    } else {
      log_check("temp_flow_rows", "OK", flow_rows)
    }
    
    bad_time <- dbGetQuery(con, "
      SELECT COUNT(*) n
      FROM temp_flow_combined
      WHERE time_diff_min > 10
    ")$n
    
    if (bad_time > 0) {
      warning(paste(bad_time, "rows exceed time alignment window"))
      log_check("temp_flow_time_window", "WARN", bad_time)
    } else {
      log_check("temp_flow_time_window", "OK", 0)
    }
  }
  
  # -------------------------------------------------
  # SAMPLE FLOW VALIDATION
  # -------------------------------------------------
  missing_flow <- if (dbExistsTable(con, "usgs_samples_aligned")) {
    dbGetQuery(con, "
      SELECT COUNT(*) n
      FROM usgs_samples_aligned
      WHERE discharge_m3_s IS NULL
    ")$n
  } else 0
  
  if (missing_flow > 0) {
    warning(paste(missing_flow, "aligned sample rows missing discharge"))
    log_check("sample_flow_missing", "WARN", missing_flow)
  } else {
    log_check("sample_flow_missing", "OK", 0)
  }
  
  # duplicates
  dup_samples <- if (dbExistsTable(con, "usgs_samples_aligned")) {
    dbGetQuery(con, "
      SELECT COUNT(*) n FROM (
        SELECT sample_id, COUNT(*) c
        FROM usgs_samples_aligned
        GROUP BY sample_id
        HAVING c > 1
      )
    ")$n
  } else 0
  
  if (dup_samples > 0) {
    warning(paste(dup_samples, "samples have multiple flow matches"))
    log_check("sample_flow_duplicates", "WARN", dup_samples)
  } else {
    log_check("sample_flow_duplicates", "OK", 0)
  }
  
  # -------------------------------------------------
  # SAMPLE FLUX VALIDATION
  # -------------------------------------------------
  bad_flux <- if (dbExistsTable(con, "sample_flux")) {
    dbGetQuery(con, "
      SELECT COUNT(*) n
      FROM sample_flux
      WHERE mass_flux IS NULL OR discharge_m3_s IS NULL
    ")$n
  } else 0
  
  if (bad_flux > 0) {
    warning(paste(bad_flux, "sample_flux rows missing values"))
    log_check("sample_flux_missing", "WARN", bad_flux)
  } else {
    log_check("sample_flux_missing", "OK", 0)
  }
  
  # -------------------------------------------------
  # ROW COUNTS
  # -------------------------------------------------
  tables <- c(
    "Locations",
    "Sampling_Events",
    "Samples",
    "Field_Measurements",
    "Lab_Analyses",
    "Temperature_Observations",
    "Wells",
    "Water_Level_Observations",
    "Hydraulic_Gradients"
  )
  
  for (t in tables) {
    n <- if (dbExistsTable(con, t)) {
      dbGetQuery(con, paste0("SELECT COUNT(*) n FROM ", t))$n
    } else NA
    
    status <- if (is.na(n)) "WARN" else if (n == 0) "WARN" else "OK"
    
    log_check(paste("row_count:", t), status, n)
  }
  
  # -------------------------------------------------
  # KEY MATCH CHECKS
  # -------------------------------------------------
  
  bad_samples <- dbGetQuery(con, "
    SELECT COUNT(*) n FROM Samples WHERE location_id IS NULL
  ")$n
  
  if (bad_samples > 0) {
    log_check("samples_missing_location", "ERROR", bad_samples)
    stop("ERROR: Samples missing location_id")
  } else {
    log_check("samples_missing_location", "OK", 0)
  }
  
  # -------------------------------------------------
  # GEOMETRY CHECK
  # -------------------------------------------------
  
  bad_geom <- dbGetQuery(con, "
    SELECT COUNT(*) n FROM Locations WHERE geom IS NULL
  ")$n
  
  if (bad_geom > 0) {
    warning(paste(bad_geom, "locations missing geometry"))
    log_check("missing_geometry", "WARN", bad_geom)
  } else {
    log_check("missing_geometry", "OK", 0)
  }
  
  message("✅ Database validation complete")
}