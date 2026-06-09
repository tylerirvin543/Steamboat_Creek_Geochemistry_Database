# scripts/analysis/build_analysis_products.R

build_sample_integrated <- function(con) {
  
  message("[ANALYSIS] Building sample_integrated")
  
  df <- dbGetQuery(con, "
  SELECT
    s.sample_id,
    s.collection_time,
    s.location_id,

    f.parameter,
    f.value AS field_value,

    l.analyte,
    l.value AS lab_value,

    sf.discharge_m3_s AS discharge,
    NULL AS temperature,

    ip.d18O,
    ip.d2H

  FROM Samples s

  LEFT JOIN Field_Measurements f 
    ON s.sample_id = f.sample_id

  LEFT JOIN Lab_Analyses l 
    ON s.sample_id = l.sample_id

  LEFT JOIN vw_sample_with_flow sf
    ON s.sample_id = sf.sample_id

  LEFT JOIN isotope_pairs ip
    ON s.sample_id = ip.sample_id
  ")
  
  dbWriteTable(con, "sample_integrated", df, overwrite = TRUE)
  
  message("✅ sample_integrated ready (", nrow(df), " rows)")
}

build_thermal_summary <- function(con) {
  
  message("[ANALYSIS] Building thermal_summary")
  
  df <- dbGetQuery(con, "
  SELECT
    logger_id,
    AVG(temperature) AS mean_temp,
    MIN(temperature) AS min_temp,
    MAX(temperature) AS max_temp,
    (MAX(temperature) - MIN(temperature)) AS temp_range
  FROM vw_temperature_timeseries
  GROUP BY logger_id
  ")
  
  dbWriteTable(con, "thermal_summary", df, overwrite = TRUE)
}

build_flow_summary <- function(con) {
  
  message("[ANALYSIS] Building flow_summary")
  
  if (!"Hydraulic_Gradients" %in% dbListTables(con)) {
    warning("Hydraulic_Gradients missing")
    return(NULL)
  }
  
  df <- dbGetQuery(con, "
    SELECT
      COUNT(*) AS n,
      AVG(gradient) AS mean_gradient,
      MAX(gradient) AS max_gradient
    FROM Hydraulic_Gradients
  ")
  
  dbWriteTable(con, "flow_summary", df, overwrite = TRUE)
}

build_hydrochem_summary <- function(con) {
  
  message("[ANALYSIS] Building hydrochem_summary")
  
  df <- dbGetQuery(con, "
  SELECT
    sample_id,
    SUM(CASE WHEN analyte = 'Na' THEN value ELSE 0 END) AS Na,
    SUM(CASE WHEN analyte = 'Cl' THEN value ELSE 0 END) AS Cl,
    SUM(CASE WHEN analyte = 'SO4' THEN value ELSE 0 END) AS SO4
  FROM Lab_Analyses
  GROUP BY sample_id
  ")
  
  dbWriteTable(con, "hydrochem_summary", df, overwrite = TRUE)
}

build_anomaly_flags <- function(con) {
  
  message("[ANALYSIS] Building anomaly flags")
  
  if (!"sample_integrated" %in% dbListTables(con)) {
    warning("sample_integrated missing")
    return(NULL)
  }
  
  df <- dbGetQuery(con, "
  SELECT
    sample_id,
    CASE 
      WHEN temperature > 80 THEN 1 ELSE 0
    END AS high_temp_flag
  FROM sample_integrated
  ")
  
  dbWriteTable(con, "anomaly_flags", df, overwrite = TRUE)
}

build_analysis_products <- function(con) {
  
  build_sample_integrated(con)
  build_thermal_summary(con)
  build_flow_summary(con)
  build_hydrochem_summary(con)
  build_anomaly_flags(con)
  
  message("✅ ALL ANALYSIS PRODUCTS COMPLETE")
}
