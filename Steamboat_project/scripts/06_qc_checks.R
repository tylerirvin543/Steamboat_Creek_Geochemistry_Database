#06_qc_checks
library(DBI)
library(RSQLite)
library(dplyr)

con <- dbConnect(SQLite(), "geochem_sampling.sqlite")

cat("\n==============================\n")
cat("QUALITY CONTROL CHECKS\n")
cat("==============================\n")

# --------------------------------------------------
# 1. LOCATION QC
# --------------------------------------------------

cat("\n-- Locations with missing coordinates --\n")
qc_locations_missing_coords <- dbGetQuery(con, "
SELECT * FROM Locations
WHERE latitude IS NULL OR longitude IS NULL;
")
print(qc_locations_missing_coords)

# --------------------------------------------------
# 2. SAMPLE METADATA QC
# --------------------------------------------------

cat("\n-- Samples without valid location or event --\n")
qc_samples_orphaned <- dbGetQuery(con, "
SELECT s.*
FROM Samples s
LEFT JOIN Locations l ON s.location_id = l.location_id
LEFT JOIN Sampling_Events e ON s.event_id = e.event_id
WHERE l.location_id IS NULL
   OR e.event_id IS NULL;
")
print(qc_samples_orphaned)

# --------------------------------------------------
# 3. FIELD MEASUREMENT QC
# --------------------------------------------------

# 3a. Impossible field values
cat("\n-- Field measurements with impossible values --\n")
qc_field_impossible <- dbGetQuery(con, "
SELECT *
FROM Field_Measurements
WHERE (parameter = 'pH' AND (value < 0 OR value > 14))
   OR (parameter = 'temperature' AND (value < -5 OR value > 120))
   OR (parameter = 'conductivity' AND value < 0);
")
print(qc_field_impossible)

# 3b. Missing critical field parameters
cat("\n-- Samples missing critical field parameters (pH or temperature) --\n")
qc_field_missing_core <- dbGetQuery(con, "
SELECT s.sample_id
FROM Samples s
LEFT JOIN Field_Measurements fm_pH
  ON s.sample_id = fm_pH.sample_id AND fm_pH.parameter = 'pH'
LEFT JOIN Field_Measurements fm_T
  ON s.sample_id = fm_T.sample_id AND fm_T.parameter = 'temperature'
WHERE fm_pH.value IS NULL
   OR fm_T.value IS NULL;
")
print(qc_field_missing_core)

# 3c. Duplicate field measurements that disagree
cat("\n-- Duplicate field measurements with large disagreement --\n")
qc_field_duplicates <- dbGetQuery(con, "
SELECT
  sample_id,
  parameter,
  COUNT(*) AS n_measurements,
  MIN(value) AS min_value,
  MAX(value) AS max_value
FROM Field_Measurements
GROUP BY sample_id, parameter
HAVING COUNT(*) > 1
   AND (MAX(value) - MIN(value)) >
       CASE
         WHEN parameter = 'pH' THEN 0.2
         WHEN parameter = 'temperature' THEN 1.0
         ELSE 0
       END;
")
print(qc_field_duplicates)

# 3d. Field vs Lab Alkalinity Consistency
cat("\n-- Field vs Lab Alkalinity comparison --\n")
qc_alkalinity <- dbGetQuery(con, "
SELECT
  s.sample_id,
  fm.value AS field_alkalinity,
  la.value AS lab_alkalinity,
  100.0 * (fm.value - la.value) / la.value AS percent_difference
FROM Samples s
JOIN Field_Measurements fm
  ON s.sample_id = fm.sample_id
  AND fm.parameter = 'alkalinity'
JOIN Lab_Analyses la
  ON s.sample_id = la.sample_id
  AND la.analyte IN ('Alkalinity', 'Alkalinity Total')
WHERE la.value IS NOT NULL
  AND fm.value IS NOT NULL;
")

print(qc_alkalinity)

# Flag large discrepancies (>15%)
qc_alkalinity_flagged <- qc_alkalinity %>%
  filter(abs(percent_difference) > 15)

print(qc_alkalinity_flagged)
# --------------------------------------------------
# 4. LAB ANALYSIS QC
# --------------------------------------------------

# 4a. Negative concentrations
cat("\n-- Lab analyses with negative concentrations --\n")
qc_lab_negative <- dbGetQuery(con, "
SELECT *
FROM Lab_Analyses
WHERE value < 0;
")
print(qc_lab_negative)

# 4b. Detection limit issues
cat("\n-- Lab analyses with invalid detection limits --\n")
qc_lab_dl <- dbGetQuery(con, "
SELECT *
FROM Lab_Analyses
WHERE detection_limit < 0
   OR (value IS NOT NULL AND detection_limit IS NOT NULL AND value < detection_limit);
")
print(qc_lab_dl)

# --------------------------------------------------
# 5. MAJOR ION COMPLETENESS
# --------------------------------------------------

cat("\n-- Samples missing major ions (Ca, Mg, Na, Cl) --\n")
qc_major_ions <- dbGetQuery(con, "
SELECT s.sample_id
FROM Samples s
LEFT JOIN Lab_Analyses ca ON s.sample_id = ca.sample_id AND ca.analyte = 'Ca'
LEFT JOIN Lab_Analyses mg ON s.sample_id = mg.sample_id AND mg.analyte = 'Mg'
LEFT JOIN Lab_Analyses na ON s.sample_id = na.sample_id AND na.analyte = 'Na'
LEFT JOIN Lab_Analyses cl ON s.sample_id = cl.sample_id AND cl.analyte = 'Cl'
WHERE ca.value IS NULL
   OR mg.value IS NULL
   OR na.value IS NULL
   OR cl.value IS NULL;
")
print(qc_major_ions)

# --------------------------------------------------
# 6. PHREEQC READINESS CHECK
# --------------------------------------------------

cat("\n-- Samples not ready for PHREEQC (incomplete solutions) --\n")
qc_phreeqc <- dbGetQuery(con, "
SELECT *
FROM PHREEQC_Solutions
WHERE completeness_flag != 'complete'
   OR ABS(charge_balance) > 5;
")
print(qc_phreeqc)


qc_summary <- data.frame(
  qc_run_date = Sys.Date(),
  total_samples = dbGetQuery(con, "SELECT COUNT(*) n FROM Samples")$n,
  samples_missing_pH = nrow(qc_field_missing_core),
  samples_missing_temperature = nrow(
    qc_field_missing_core  # same query covers both
  ),
  samples_missing_major_ions = nrow(qc_major_ions),
  samples_charge_imbalance = nrow(qc_phreeqc),
  samples_alkalinity_mismatch = nrow(qc_alkalinity_flagged)
)

dbWriteTable(
  con,
  "QC_Summary",
  qc_summary,
  append = TRUE
)

print(qc_summary)

dir.create("qc_reports", showWarnings = FALSE)

write.csv(
  qc_field_impossible,
  "qc_reports/field_impossible_values.csv",
  row.names = FALSE
)

write.csv(
  qc_field_missing_core,
  "qc_reports/missing_field_parameters.csv",
  row.names = FALSE
)

write.csv(
  qc_major_ions,
  "qc_reports/missing_major_ions.csv",
  row.names = FALSE
)

write.csv(
  qc_alkalinity_flagged,
  "qc_reports/alkalinity_mismatch.csv",
  row.names = FALSE
)

write.csv(
  qc_phreeqc,
  "qc_reports/not_phreeqc_ready.csv",
  row.names = FALSE
)
# --------------------------------------------------
# END
# --------------------------------------------------

dbDisconnect(con)

cat("\nQC checks complete.\n")