# ============================================================
# create_analysis_views.R
#
# Purpose:
# Create derived / analysis-ready database views for
# hydrogeologic interpretation, GIS export, and modeling.
#
# Design:
# - Builds on normalized RAW tables
# - Produces reusable, queryable views
# - Separates RAW data from interpreted products
#
# Key Concepts:
# RAW → OBSERVATIONS → DERIVED VIEWS → EXPORT / ANALYSIS
#
# These views support:
# - Hydraulic head mapping
# - Time-series analysis
# - Daily / latest water level extraction
# - GIS-ready feature layers
#
# ============================================================

create_analysis_views <- function(con) {
  
  message("\n==================================================")
  message(" BUILDING ANALYSIS LAYERS (SQL ONLY)")
  message("==================================================")
  
  # -------------------------------------------------
  # 0. CLEANUP
  # -------------------------------------------------
  message("\n[SETUP] Dropping existing views...")
  
  views_to_drop <- c(
    "vw_hydraulic_head",
    "vw_water_level_latest",
    "vw_wells_gis",
    "vw_sample_master",
    "vw_major_ions",
    "vw_isotopes_gis",
    "vw_samples_locations",
    "vw_samples_gis",
    "vw_sample_wide",
    "vw_flux_summary",
    "vw_usgs_discharge",
    "vw_flux_vs_usgs",
    "vw_sample_hydrochem_flux",
    "vw_hydraulic_head",
    "vw_hydraulic_head_clean",
    "vw_temp_gradient",
    "vw_isotope_pairs",
    "vw_temperature_timeseries"
  )
  
  for (v in views_to_drop) {
    dbExecute(con, sprintf("DROP VIEW IF EXISTS %s", v))
  }
  
  message("✅ Cleanup complete")
  
  # -------------------------------------------------
  # 1. HYDRAULICS
  # -------------------------------------------------
  message("\n[HYDRAULICS]")
  
  dbExecute(con, "
  CREATE VIEW vw_hydraulic_head AS
  SELECT
    wl.observation_id,
    w.well_id,
    wl.timestamp,
    (w.elevation_m - wl.depth_to_water) AS hydraulic_head,
    w.latitude,
    w.longitude,
    w.coord_key,
    'POINT(' || w.longitude || ' ' || w.latitude || ')' AS geom_wkt
  FROM Water_Level_Observations wl
  JOIN Wells w ON wl.well_id = w.well_id
  WHERE wl.depth_to_water IS NOT NULL
  ")
  
  dbExecute(con, "
CREATE VIEW vw_hydraulic_head_clean AS
SELECT *
FROM vw_hydraulic_head
WHERE hydraulic_head IS NOT NULL
")
  
  
  dbExecute(con, "
  CREATE VIEW vw_water_level_latest AS
  SELECT *
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY well_id ORDER BY timestamp DESC) rn
    FROM vw_hydraulic_head
  )
  WHERE rn = 1
  ")
  
  dbExecute(con, "
  CREATE VIEW vw_wells_gis AS
  SELECT
    well_id,
    well_name,
    coord_key,
    latitude,
    longitude,
    elevation_m,
    'POINT(' || longitude || ' ' || latitude || ')' AS geom_wkt
  FROM Wells
  ")
  
  message("✅ Hydraulics ready")
  
  
  # -------------------------------------------------
  # TEMPERATURE TIMESERIES
  # -------------------------------------------------
  message("\n[TEMPERATURE]")
  
  dbExecute(con, "
CREATE VIEW vw_temperature_timeseries AS
SELECT
  t.logger_id,
  l.location_id,
  datetime(t.timestamp, 'unixepoch') AS timestamp,
  t.temperature
FROM Temperature_Observations t
JOIN Temperature_Loggers l
  ON t.logger_id = l.logger_id
WHERE t.temperature IS NOT NULL
")
  
  message("✅ Temperature ready")
  
  # -------------------------------------------------
  # 2. SAMPLE MASTER
  # -------------------------------------------------
  message("\n[CHEMISTRY]")
  
  dbExecute(con, "
  CREATE VIEW vw_sample_master AS
  SELECT
    s.sample_id,
    s.location_id,
    l.coord_key,
    l.name,
    l.latitude,
    l.longitude,
    la.analyte,
    la.value,
    la.units,
    'lab' AS source_type,
    'POINT(' || l.longitude || ' ' || l.latitude || ')' AS geom_wkt
  FROM Lab_Analyses la
  JOIN Samples s ON la.sample_id = s.sample_id
  JOIN Locations l ON s.location_id = l.location_id
  ")
  
  dbExecute(con, "
  CREATE VIEW vw_major_ions AS
  SELECT *
  FROM vw_sample_master
  WHERE analyte IN ('Ca','Mg','Na','K','Cl','SO4','HCO3')
  ")
  
  dbExecute(con, "
  CREATE VIEW vw_temp_gradient AS
  SELECT * FROM temp_gradient
  ")
  
  dbExecute(con, "
CREATE VIEW vw_isotope_pairs AS
SELECT
  ip.*,
  l.latitude,
  l.longitude,
  'POINT(' || l.longitude || ' ' || l.latitude || ')' AS geom_wkt
FROM isotope_pairs ip
JOIN Samples s ON ip.sample_id = s.sample_id
JOIN Locations l ON s.location_id = l.location_id
")
  
  # -------------------------------------------------
  # ISOTOPES (GIS-READY)
  # -------------------------------------------------
  dbExecute(con, "
CREATE VIEW vw_isotopes_gis AS
SELECT
  i.sample_id,
  l.coord_key,
  l.name,
  l.latitude,
  l.longitude,

  i.analyte,
  i.value,
  i.units,

  CASE
    WHEN i.analyte = 'd18O' THEN 'δ18O'
    WHEN i.analyte = 'dD'   THEN 'δ2H'
    ELSE NULL
  END AS analyte_label,

  'POINT(' || l.longitude || ' ' || l.latitude || ')' AS geom_wkt

FROM Isotope_Analyses i
JOIN Samples s ON i.sample_id = s.sample_id
JOIN Locations l ON s.location_id = l.location_id

WHERE i.value IS NOT NULL
")
  
  message("✅ Chemistry ready")
  
  # -------------------------------------------------
  # 3. USGS BASE (NO TIME MATCHING)
  # -------------------------------------------------
  message("\n[HYDROLOGY]")
  
  dbExecute(con, "
  CREATE VIEW vw_usgs_discharge AS
SELECT
  station_id,
  datetime,
  value * 0.0283168 AS discharge_m3_s
FROM USGS_Timeseries
WHERE parameter_code = '60'
  ")
  
  message("✅ USGS base ready")
  
  # -------------------------------------------------
  # 4. FIELD / FLUX SUMMARY
  # -------------------------------------------------
  message("\n[FIELD DATA]")
  
  dbExecute(con, "
  CREATE VIEW vw_flux_summary AS
  SELECT
    s.sample_id,
    l.coord_key,
    l.name,
    l.latitude,
    l.longitude,
    datetime(s.collection_time, 'unixepoch') AS timestamp,
    MAX(CASE WHEN fm.parameter = 'discharge_total' THEN fm.value END) AS discharge_m3_s,
    'POINT(' || l.longitude || ' ' || l.latitude || ')' AS geom_wkt
  FROM Samples s
  JOIN Field_Measurements fm ON s.sample_id = fm.sample_id
  JOIN Locations l ON s.location_id = l.location_id
  WHERE s.sample_id LIKE 'FLUX_%'
  GROUP BY s.sample_id
  ")
  
  message("✅ Field data ready")
  
  # -------------------------------------------------
  # 5. DERIVED VIEWS (USE R TABLES)
  # -------------------------------------------------
  
  # ✅ flux vs USGS
  dbExecute(con, "
  CREATE VIEW vw_flux_vs_usgs AS
  SELECT
    f.sample_id,
    f.coord_key,
    f.name,
    f.latitude,
    f.longitude,
    f.timestamp,
    f.discharge_m3_s AS field_discharge,
    u.discharge_m3_s AS usgs_discharge,
    (u.discharge_m3_s - f.discharge_m3_s) AS diff_m3_s,
    'POINT(' || f.longitude || ' ' || f.latitude || ')' AS geom_wkt
  FROM vw_flux_summary f
  LEFT JOIN sample_flow u
    ON f.sample_id = u.sample_id
  ")
  
  # ✅ sample hydrochem flux (uses materialized table)
  dbExecute(con, "
  CREATE VIEW vw_sample_hydrochem_flux AS
  SELECT *
  FROM sample_flux
  ")
  
  message("✅ Derived analysis ready")
  
  # -------------------------------------------------
  # 6. GIS OUTPUTS
  # -------------------------------------------------
  message("\n[GIS]")
  
  dbExecute(con, "
  CREATE VIEW vw_samples_locations AS
  SELECT DISTINCT sample_id, coord_key, geom_wkt
  FROM vw_sample_master
  ")
  
  dbExecute(con, "
  CREATE VIEW vw_samples_gis AS
  SELECT * FROM vw_sample_master
  ")
  
  message("✅ GIS ready")
  
  # -------------------------------------------------
  # COMPLETE
  # -------------------------------------------------
  message("\n✅ ANALYSIS VIEWS COMPLETE (FAST + CLEAN)\n")
}