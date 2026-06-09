run_qc_checks <- function(con) {
  
  message("---- Running QC checks ----")
  
  library(DBI)
  library(dplyr)
  
  # -----------------------------
  # SAFE INITIALIZATION
  # -----------------------------
  qc_field_missing_core <- data.frame()
  qc_major_ions <- data.frame()
  qc_phreeqc <- data.frame()
  qc_logger_no_obs <- data.frame()
  qc_logger_impossible <- data.frame()
  qc_logger_gaps <- data.frame()
  qc_alkalinity_flagged <- data.frame()
  qc_field_impossible <- data.frame()
  
  # -----------------------------
  # HELPER FUNCTIONS
  # -----------------------------
  report_qc <- function(df, name, preview_n = 10) {
    n <- nrow(df)
    
    if (n == 0) {
      message(name, ": ✅ none")
      return(invisible(NULL))
    }
    
    message(name, ": ⚠ ", n, " issues")
    print(head(df, preview_n))
    
    if (n > preview_n) {
      message("... (", n - preview_n, " more not shown)")
    }
  }
  
  write_qc <- function(df, path) {
    if (nrow(df) > 0) {
      write.csv(df, path, row.names = FALSE)
    }
  }
  
  cat("\n==============================\n")
  cat("QUALITY CONTROL CHECKS\n")
  cat("==============================\n")
  
  # ==================================================
  # 1. LOCATION QC
  # ==================================================
  
  qc_locations_missing_coords <- dbGetQuery(con, "
    SELECT * FROM Locations
    WHERE latitude IS NULL OR longitude IS NULL;
  ")
  
  report_qc(qc_locations_missing_coords, "Locations missing coordinates")
  
  # ==================================================
  # 2. SAMPLE QC
  # ==================================================
  
  qc_samples_orphaned <- dbGetQuery(con, "
    SELECT s.*
    FROM Samples s
    LEFT JOIN Locations l ON s.location_id = l.location_id
    LEFT JOIN Sampling_Events e ON s.event_id = e.event_id
    WHERE l.location_id IS NULL OR e.event_id IS NULL;
  ")
  
  report_qc(qc_samples_orphaned, "Orphaned samples")
  
  # ==================================================
  # 3. GRADIENT QC
  # ==================================================
  
  if (dbExistsTable(con, "Hydraulic_Gradients")) {
    grad <- dbGetQuery(con, "SELECT gradient FROM Hydraulic_Gradients")
    
    cat("\n-- Gradient summary --\n")
    print(summary(grad$gradient))
    
    qc_grad_extreme <- dbGetQuery(con, "
      SELECT * FROM Hydraulic_Gradients
      WHERE ABS(gradient) > 0.05
      LIMIT 10
    ")
    
    report_qc(qc_grad_extreme, "Extreme gradients (>0.05)")
  }
  
  # ==================================================
  # 4. LOGGER QC
  # ==================================================
  
  qc_logger_no_obs <- dbGetQuery(con, "
    SELECT l.*
    FROM Temperature_Loggers l
    LEFT JOIN Temperature_Observations o
      ON l.logger_id = o.logger_id
    WHERE o.observation_id IS NULL;
  ")
  report_qc(qc_logger_no_obs, "Loggers without observations")
  
  qc_logger_impossible <- dbGetQuery(con, "
    SELECT * FROM Temperature_Observations
    WHERE temperature < -10 OR temperature > 120;
  ")
  report_qc(qc_logger_impossible, "Out-of-range temperature")
  
  qc_logger_gaps <- dbGetQuery(con, "
    WITH ordered AS (
      SELECT logger_id, timestamp,
             LAG(timestamp) OVER (PARTITION BY logger_id ORDER BY timestamp) AS prev_time
      FROM Temperature_Observations
    ),
    diffs AS (
      SELECT logger_id, timestamp,
             julianday(timestamp) - julianday(prev_time) AS delta_days
      FROM ordered
      WHERE prev_time IS NOT NULL
    ),
    stats AS (
      SELECT logger_id, MEDIAN(delta_days) AS median_delta
      FROM diffs GROUP BY logger_id
    )
    SELECT d.logger_id, d.timestamp, d.delta_days * 86400 AS gap_seconds
    FROM diffs d
    JOIN stats s ON d.logger_id = s.logger_id
    WHERE d.delta_days > 2 * s.median_delta;
  ")
  report_qc(qc_logger_gaps, "Logger time gaps")
  
  qc_sample_no_logger <- dbGetQuery(con, "
    SELECT s.sample_id, s.collection_time
    FROM Samples s
    LEFT JOIN Temperature_Loggers tl
      ON tl.location_id = s.location_id
     AND s.collection_time BETWEEN tl.deployment_start AND tl.deployment_end
    WHERE tl.logger_id IS NULL;
  ")
  report_qc(qc_sample_no_logger, "Samples without active logger")
  
  # ==================================================
  # 5. FIELD QC
  # ==================================================
  
  qc_field_impossible <- dbGetQuery(con, "
    SELECT * FROM Field_Measurements
    WHERE (parameter = 'pH' AND (value < 0 OR value > 14))
       OR (parameter = 'temperature' AND (value < -5 OR value > 120));
  ")
  report_qc(qc_field_impossible, "Impossible field values")
  
  qc_field_missing_core <- dbGetQuery(con, "
    SELECT s.sample_id
    FROM Samples s
    LEFT JOIN Field_Measurements pH
      ON s.sample_id = pH.sample_id AND pH.parameter = 'pH'
    LEFT JOIN Field_Measurements T
      ON s.sample_id = T.sample_id AND T.parameter = 'temperature'
    WHERE pH.value IS NULL OR T.value IS NULL;
  ")
  report_qc(qc_field_missing_core, "Missing field parameters")
  
  # ==================================================
  # 6. LAB QC
  # ==================================================
  
  qc_lab_negative <- dbGetQuery(con, "
    SELECT * FROM Lab_Analyses WHERE value < 0;
  ")
  report_qc(qc_lab_negative, "Negative lab values")
  
  qc_lab_dl <- dbGetQuery(con, "
    SELECT * FROM Lab_Analyses
    WHERE detection_limit < 0
       OR (value < detection_limit);
  ")
  report_qc(qc_lab_dl, "Invalid detection limits")
  
  qc_major_ions <- dbGetQuery(con, "
    SELECT s.sample_id
    FROM Samples s
    LEFT JOIN Lab_Analyses ca ON s.sample_id = ca.sample_id AND ca.analyte = 'Ca'
    LEFT JOIN Lab_Analyses mg ON s.sample_id = mg.sample_id AND mg.analyte = 'Mg'
    LEFT JOIN Lab_Analyses na ON s.sample_id = na.sample_id AND na.analyte = 'Na'
    LEFT JOIN Lab_Analyses cl ON s.sample_id = cl.sample_id AND cl.analyte = 'Cl'
    WHERE ca.value IS NULL OR mg.value IS NULL OR na.value IS NULL OR cl.value IS NULL;
  ")
  report_qc(qc_major_ions, "Missing major ions")
  
  # ==================================================
  # 7. PHREEQC QC
  # ==================================================
  
  if (!dbExistsTable(con, "PHREEQC_Solutions")) {
    message("PHREEQC_Solutions not found — skipping QC")
  } else {
    qc_phreeqc <- dbGetQuery(con, "
      SELECT * FROM PHREEQC_Solutions
      WHERE completeness_flag != 'complete'
         OR ABS(charge_balance) > 5;
    ")
    report_qc(qc_phreeqc, "PHREEQC issues")
  }
  
  # ==================================================
  # SUMMARY
  # ==================================================
  
  summary_df <- data.frame(
    qc_run_date = Sys.Date(),
    total_samples = dbGetQuery(con, "SELECT COUNT(*) n FROM Samples")$n,
    missing_field_params = nrow(qc_field_missing_core),
    missing_major_ions = nrow(qc_major_ions),
    phreeqc_flagged = nrow(qc_phreeqc),
    loggers_without_obs = nrow(qc_logger_no_obs),
    logger_outliers = nrow(qc_logger_impossible)
  )
  
  dbExecute(con, "DROP TABLE IF EXISTS QC_Summary")
  
  dbWriteTable(
    con,
    "QC_Summary",
    summary_df,
    overwrite = TRUE
  )
  
  print(summary_df)
  
  # ==================================================
  # EXPORT
  # ==================================================
  
  dir.create("qc_reports", showWarnings = FALSE)
  
  write_qc(qc_field_impossible, "qc_reports/field_impossible.csv")
  write_qc(qc_field_missing_core, "qc_reports/missing_field.csv")
  write_qc(qc_major_ions, "qc_reports/missing_ions.csv")
  write_qc(qc_logger_no_obs, "qc_reports/loggers_no_obs.csv")
  write_qc(qc_logger_impossible, "qc_reports/logger_outliers.csv")
  write_qc(qc_logger_gaps, "qc_reports/logger_gaps.csv")
  
  cat("\nQC checks complete.\n")
}