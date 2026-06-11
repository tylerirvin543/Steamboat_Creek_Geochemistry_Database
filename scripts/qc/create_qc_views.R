
create_qc_views <- function(con) {
  
  message("\n[QC] Building QC-derived views")
  
  # -----------------------------
  # CLEANUP
  # -----------------------------
  dbExecute(con, "DROP VIEW IF EXISTS vw_sample_quality")
  dbExecute(con, "DROP VIEW IF EXISTS vw_major_ions_clean")
  dbExecute(con, "DROP VIEW IF EXISTS vw_sample_flow_clean")
  
  # -----------------------------
  # SAMPLE QUALITY
  # -----------------------------
  dbExecute(con, "
    CREATE VIEW vw_sample_quality AS
    SELECT
      s.sample_id,
      s.location_id,
      l.latitude,
      l.longitude,
    
      CASE 
        WHEN s.sample_id IN (
          SELECT record_id FROM QC_Issues
          WHERE issue_type = 'missing_major_ions'
        ) THEN 0 ELSE 1
      END AS has_chemistry,
    
      CASE 
        WHEN s.sample_id IN (
          SELECT record_id FROM QC_Issues
          WHERE issue_type = 'missing_field_parameters'
        ) THEN 0 ELSE 1
      END AS has_field,
    
      CASE 
        WHEN s.sample_id NOT IN (
          SELECT record_id FROM QC_Issues
          WHERE severity = 'ERROR'
        ) THEN 1 ELSE 0
      END AS is_valid,
    
      CASE
        WHEN 
          s.sample_id NOT IN (
            SELECT record_id FROM QC_Issues
            WHERE severity = 'ERROR'
          )
          AND s.sample_id NOT IN (
            SELECT record_id FROM QC_Issues
            WHERE issue_type = 'missing_major_ions'
          )
          AND s.sample_id NOT IN (
            SELECT record_id FROM QC_Issues
            WHERE issue_type = 'missing_field_parameters'
          )
        THEN 'complete'
        
        WHEN s.sample_id NOT IN (
          SELECT record_id FROM QC_Issues
          WHERE issue_type = 'missing_major_ions'
        ) THEN 'chem_only'
    
        WHEN s.sample_id NOT IN (
          SELECT record_id FROM QC_Issues
          WHERE issue_type = 'missing_field_parameters'
        ) THEN 'field_only'
    
        ELSE 'incomplete'
      END AS quality_class,
    
      'POINT(' || l.longitude || ' ' || l.latitude || ')' AS geom_wkt
    
    FROM Samples s
    JOIN Locations l ON s.location_id = l.location_id
  ")
  
  # -----------------------------
  # CLEAN MAJOR IONS
  # -----------------------------
  dbExecute(con, "
    CREATE VIEW vw_major_ions_clean AS
    SELECT *
    FROM vw_major_ions
    WHERE sample_id NOT IN (
      SELECT record_id
      FROM QC_Issues
      WHERE severity = 'ERROR'
    )
  ")
  
  # -----------------------------
  # CLEAN SAMPLE FLOW
  # -----------------------------
  dbExecute(con, "
    CREATE VIEW vw_sample_flow_clean AS
    SELECT *
    FROM sample_flow
    WHERE sample_id NOT IN (
      SELECT record_id
      FROM QC_Issues
      WHERE severity = 'ERROR'
    )
  ")
  
  message("✅ QC-derived views built")
}