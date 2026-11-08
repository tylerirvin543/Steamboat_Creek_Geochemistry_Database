#30_thermal_areas_schema
# ------------------------------------------------------------
# Temperature-threshold polygons from calibrated thermal-infrared imagery.
# Rows are written only when the imagery has been georeferenced from control
# points (see scripts/analysis/thermal_threshold_polygons.R); until then the
# table is empty by design. geom_wkt is EPSG:4326.
# ------------------------------------------------------------
library(DBI)
if (!exists("con")) stop("Database connection `con` not found. Run via run_pipeline.R.")
dbExecute(con, "
CREATE TABLE IF NOT EXISTS Thermal_Areas (
  thermal_area_id INTEGER PRIMARY KEY,
  feature_key TEXT UNIQUE,
  survey_date TEXT,
  cutoff_c REAL,
  source_file TEXT,
  method TEXT,
  uncertainty_c REAL,
  area_m2 REAL,
  georef_rmse_m REAL,
  geom_wkt TEXT NOT NULL
)")
