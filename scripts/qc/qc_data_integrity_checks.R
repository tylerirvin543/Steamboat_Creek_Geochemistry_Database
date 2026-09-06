run_qc_checks <- function(con) {
  
  message("---- Running QC checks ----")
  
  qc_run_time <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  
  library(DBI)
  library(dplyr)
  
  # ✅ ONLY in DEMO mode — RESET TABLE STRUCTURE
  dbExecute(con, "DROP TABLE IF EXISTS QC_Issues")

  
  dbExecute(con, "
CREATE TABLE IF NOT EXISTS QC_Issues (
  issue_id INTEGER PRIMARY KEY,
  table_name TEXT,
  qc_source TEXT,
  record_id TEXT,
  location_id INTEGER,
  issue_type TEXT,
  severity TEXT,
  message TEXT,
  created_at TEXT,
  qc_run_time TEXT
)
")

print(dbGetQuery(con, "PRAGMA table_info(QC_Issues)"))

safe_parse <- function(x) {
  result <- tryCatch(
    {
      out <- as.POSIXct(x, tz = "UTC")
      format(out, "%Y-%m-%d %H:%M:%S")
    },
    error = function(e) {
      rep(NA_character_, length(x))
    }
  )
  
  # ensure invalid conversions become NA
  result[!grepl("^\\d{4}-\\d{2}-\\d{2}", result)] <- NA
  
  result
}


log_qc_issue <- function(df, table_name, issue_type, severity, message) {
  
  n_rows <- nrow(df)
  if (n_rows == 0) return()
  
  tmp <- df %>%
    
    mutate(
      location_id = if ("location_id" %in% names(.)) location_id else rep(NA, n_rows),
      sample_id   = if ("sample_id" %in% names(.)) sample_id else rep(NA, n_rows),
      logger_id   = if ("logger_id" %in% names(.)) logger_id else rep(NA, n_rows),
      well_id     = if ("well_id" %in% names(.)) well_id else rep(NA, n_rows)
    ) %>%
    
    mutate(
      ct = if ("collection_time" %in% names(df)) {
        safe_parse(df$collection_time)
      } else rep(NA_character_, n_rows),
      
      ts = if ("timestamp" %in% names(df)) {
        safe_parse(df$timestamp)
      } else rep(NA_character_, n_rows),
      
      dt = if ("date" %in% names(df)) {
        safe_parse(df$date)
      } else rep(NA_character_, n_rows)
    ) %>%
    
    mutate(
      created_at = dplyr::coalesce(ct, ts, dt, rep(qc_run_time, n_rows)),
      created_at = ifelse(is.na(created_at), qc_run_time, created_at),
      
      record_id = dplyr::coalesce(
        as.character(sample_id),
        as.character(logger_id),
        as.character(well_id)
      )
    )
  
  # ✅ final output (safe and explicit)
  out <- data.frame(
    table_name  = table_name,
    qc_source   = table_name,
    record_id   = ifelse(is.na(tmp$record_id),
                         as.character(seq_len(n_rows)),
                         tmp$record_id),
    location_id = tmp$location_id,
    issue_type  = issue_type,
    severity    = severity,
    message     = message,
    created_at  = tmp$created_at,
    qc_run_time = qc_run_time,
    stringsAsFactors = FALSE
  )
  
  dbWriteTable(con, "QC_Issues", out, append = TRUE)
}
  
  # -----------------------------
  # SAFE INITIALIZATION
  # -----------------------------
  qc_field_missing_core <- data.frame()
  qc_major_ions <- data.frame()
  qc_phreeqc <- data.frame()
  qc_phreeqc_failures <- data.frame()
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
  
  log_qc_issue(
    qc_locations_missing_coords,
    "Locations",
    "missing_coordinates",
    "ERROR",
    "Location missing latitude or longitude"
  )
  
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
  
  log_qc_issue(
    qc_samples_orphaned,
    "Samples",
    "orphaned_record",
    "ERROR",
    "Sample missing location or event"
  )
  
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
    log_qc_issue(
      qc_grad_extreme,
      "Hydraulic_Gradients",
      "extreme_gradient",
      "WARN",
      "Gradient exceeds expected threshold"
    )
    
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
  log_qc_issue(
    qc_logger_no_obs,
    "Temperature_Loggers",
    "no_observations",
    "WARN",
    "Logger has no observations"
  )
  
  qc_logger_impossible <- dbGetQuery(con, "
    SELECT * FROM Temperature_Observations
    WHERE temperature < -10 OR temperature > 220;
  ")
  log_qc_issue(
    qc_logger_impossible,
    "Temperature_Observations",
    "impossible_value",
    "ERROR",
    "Temperature outside expected range"
  )
  
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
  log_qc_issue(
    qc_logger_gaps,
    "Temperature_Observations",
    "time_gap",
    "WARN",
    "Irregular time gaps in data"
  )
  
  qc_sample_no_logger <- dbGetQuery(con, "
    SELECT s.sample_id, s.collection_time, s.location_id
    FROM Samples s
    LEFT JOIN Temperature_Loggers tl
      ON tl.location_id = s.location_id
     AND s.collection_time BETWEEN tl.deployment_start AND tl.deployment_end
    WHERE tl.logger_id IS NULL;
  ")
  log_qc_issue(
    qc_sample_no_logger,
    "Samples",
    "no_active_logger",
    "WARN",
    "Sample collected with no active logger deployment"
  )
  
  # ==================================================
  # 5. FIELD QC
  # ==================================================
  
  qc_field_impossible <- dbGetQuery(con, "
    SELECT * FROM Field_Measurements
    WHERE (parameter = 'pH' AND (value < 0 OR value > 14))
       OR (parameter = 'temperature' AND (value < -5 OR value > 220));
  ")
  log_qc_issue(
    qc_field_impossible,
    "Field_Measurements",
    "impossible_value",
    "ERROR",
    "Field parameter outside valid range"
  )
  
  
  qc_field_missing_core <- dbGetQuery(con, "
    SELECT s.sample_id, s.location_id
    FROM Samples s
    LEFT JOIN Field_Measurements pH
      ON s.sample_id = pH.sample_id AND pH.parameter = 'pH'
    LEFT JOIN Field_Measurements T
      ON s.sample_id = T.sample_id AND T.parameter = 'temperature'
    WHERE pH.value IS NULL OR T.value IS NULL;
  ")
  log_qc_issue(
    qc_field_missing_core,
    "Samples",
    "missing_field_parameters",
    "WARN",
    "Missing pH or temperature"
  )
  
  # ==================================================
  # 6. LAB QC
  # ==================================================
  
  qc_lab_negative <- dbGetQuery(con, "
    SELECT * FROM Lab_Analyses WHERE value < 0;
  ")
  log_qc_issue(
    qc_lab_negative,
    "Lab_Analyses",
    "negative_value",
    "ERROR",
    "Negative lab value detected"
  )
  
  qc_lab_dl <- dbGetQuery(con, "
    SELECT * FROM Lab_Analyses
    WHERE detection_limit < 0
       OR (value < detection_limit);
  ")
  log_qc_issue(
    qc_lab_dl,
    "Lab_Analyses",
    "invalid_detection_limit",
    "ERROR",
    "Detection limit invalid or exceeded"
  )
  
  qc_major_ions <- dbGetQuery(con, "
    SELECT DISTINCT s.sample_id, s.location_id
    FROM Samples s
    LEFT JOIN Lab_Analyses ca ON s.sample_id = ca.sample_id AND ca.analyte = 'Ca'
    LEFT JOIN Lab_Analyses mg ON s.sample_id = mg.sample_id AND mg.analyte = 'Mg'
    LEFT JOIN Lab_Analyses na ON s.sample_id = na.sample_id AND na.analyte = 'Na'
    LEFT JOIN Lab_Analyses cl ON s.sample_id = cl.sample_id AND cl.analyte = 'Cl'
    WHERE ca.value IS NULL OR mg.value IS NULL OR na.value IS NULL OR cl.value IS NULL;
  ")
  log_qc_issue(
    qc_major_ions,
    "Samples",
    "missing_major_ions",
    "WARN",
    "Missing one or more major ions"
  )
  
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
    log_qc_issue(
      qc_phreeqc,
      "PHREEQC_Solutions",
      "invalid_solution",
      "WARN",
      "Incomplete solution or poor charge balance"
    )
  }

  if (dbExistsTable(con, "PHREEQC_Run_Failures")) {
    qc_phreeqc_failures <- dbGetQuery(con, "SELECT * FROM PHREEQC_Run_Failures")
    log_qc_issue(
      qc_phreeqc_failures,
      "PHREEQC_Run_Failures",
      "phreeqc_convergence_failure",
      "WARN",
      "Sample did not converge with any PHREEQC thermodynamic database"
    )
  }
  
  
  # ==================================================
  # 7. Website qc summary
  # ==================================================
  qc_summary <- dbGetQuery(con, "
SELECT issue_type, severity, COUNT(*) as n
FROM QC_Issues
GROUP BY issue_type, severity
")
  
  write.csv(qc_summary, "docs/data/qc_summary.csv", row.names = FALSE)
  
  # ==================================================
  # SUMMARY
  # ==================================================
  
  summary_df <- data.frame(
    qc_run_date = Sys.Date(),
    total_samples = dbGetQuery(con, "SELECT COUNT(*) n FROM Samples")$n,
    missing_field_params = nrow(qc_field_missing_core),
    missing_major_ions = nrow(qc_major_ions),
    phreeqc_flagged = nrow(qc_phreeqc),
    phreeqc_run_failures = nrow(qc_phreeqc_failures),
    loggers_without_obs = nrow(qc_logger_no_obs),
    logger_outliers = nrow(qc_logger_impossible)
  )
  
  
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
